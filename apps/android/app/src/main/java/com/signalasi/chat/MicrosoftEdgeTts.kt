package com.signalasi.chat

import android.content.Context
import android.media.MediaPlayer
import com.signalasi.chat.voice.metrics.VoiceLatencyTelemetry
import com.signalasi.chat.voice.metrics.VoiceLatencyTraceContext
import com.signalasi.chat.voice.metrics.VoiceTraceEvents
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CancellationException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

class MicrosoftEdgeTts(private val context: Context) {
    private data class PrefetchRequest(
        val sessionId: String,
        val key: String,
        val text: String,
        val voice: String,
        val cancelled: AtomicBoolean = AtomicBoolean(false),
        val socket: AtomicReference<WebSocket?> = AtomicReference(null),
        val audio: CompletableFuture<ByteArray> = CompletableFuture()
    ) {
        fun cancel() {
            cancelled.set(true)
            socket.getAndSet(null)?.cancel()
            if (audio.isDone && !audio.isCompletedExceptionally && !audio.isCancelled) {
                audio.getNow(null)?.fill(0)
            }
            audio.cancel(true)
        }
    }

    private val client = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()
    private val requestGeneration = AtomicLong(0L)
    private val clockSkewMillis = AtomicLong(0L)
    private val playbackLock = Any()
    private val prefetches = ConcurrentHashMap<String, PrefetchRequest>()
    private val prefetchExecutor = Executors.newFixedThreadPool(2) { runnable ->
        Thread(runnable, "signalasi-edge-tts-prefetch").apply { isDaemon = true }
    }
    private var player: MediaPlayer? = null
    private var activeWebSocket: WebSocket? = null
    private var activePlaybackLatch: CountDownLatch? = null

    fun speak(
        text: String,
        voice: String,
        traceId: String = VoiceLatencyTraceContext.currentTraceId(),
        prefetchKey: String = "",
        onPlaybackStarted: () -> Unit = {},
        recordCompletion: Boolean = true,
        onDone: (Boolean, String?) -> Unit
    ) {
        if (text.isBlank()) {
            onDone(true, null)
            return
        }
        val generation = beginRequest()
        trace(traceId, VoiceTraceEvents.TTS_REQUEST_STARTED, once = true)
        Thread {
            val result = runCatching {
                val audio = awaitPrefetchedAudio(prefetchKey, text, voice, generation)
                    ?: synthesizeCurrent(text, voice, traceId, generation)
                try {
                    ensureCurrent(generation)
                    playAudio(audio, traceId, generation, onPlaybackStarted)
                    ensureCurrent(generation)
                } finally {
                    audio.fill(0)
                }
            }
            val cancelled = result.exceptionOrNull() is CancellationException || requestGeneration.get() != generation
            if (result.isSuccess && !cancelled) {
                if (recordCompletion) {
                    trace(
                        traceId,
                        VoiceTraceEvents.TTS_COMPLETED,
                        mapOf("tts_provider" to "microsoft_edge", "success" to "true"),
                        once = true
                    )
                }
                onDone(true, null)
            } else {
                if (recordCompletion && !cancelled) {
                    trace(
                        traceId,
                        VoiceTraceEvents.TTS_COMPLETED,
                        mapOf(
                            "tts_provider" to "microsoft_edge",
                            "success" to "false",
                            "error_code" to result.exceptionOrNull()?.javaClass?.simpleName.orEmpty()
                        ),
                        once = true
                    )
                }
                onDone(false, if (cancelled) "cancelled" else result.exceptionOrNull()?.message)
            }
        }.start()
    }

    fun prefetch(
        sessionId: String,
        key: String,
        text: String,
        voice: String,
        traceId: String = VoiceLatencyTraceContext.currentTraceId()
    ) {
        if (sessionId.isBlank() || key.isBlank() || text.isBlank() || prefetches.size >= MAX_PREFETCHES) return
        val request = PrefetchRequest(sessionId, key, text, voice)
        if (prefetches.putIfAbsent(key, request) != null) return
        prefetchExecutor.execute {
            val result = runCatching {
                synthesize(
                    text = text,
                    voice = voice,
                    traceId = traceId,
                    isActive = { !request.cancelled.get() },
                    onSocketChanged = request.socket::set
                )
            }
            if (result.isSuccess) {
                val bytes = result.getOrThrow()
                if (request.cancelled.get() || !request.audio.complete(bytes)) bytes.fill(0)
            } else {
                request.audio.completeExceptionally(
                    result.exceptionOrNull() ?: CancellationException("Microsoft TTS prefetch cancelled")
                )
            }
        }
    }

    fun clearPrefetches(sessionId: String = "") {
        prefetches.entries
            .filter { sessionId.isBlank() || it.value.sessionId == sessionId }
            .forEach { (key, request) ->
                if (prefetches.remove(key, request)) request.cancel()
            }
    }

    fun stop() {
        stopCurrentRequest()
        clearPrefetches()
    }

    private fun stopCurrentRequest() {
        val socket: WebSocket?
        val mediaPlayer: MediaPlayer?
        val latch: CountDownLatch?
        synchronized(playbackLock) {
            requestGeneration.incrementAndGet()
            socket = activeWebSocket
            mediaPlayer = player
            latch = activePlaybackLatch
            activeWebSocket = null
            player = null
            activePlaybackLatch = null
        }
        socket?.cancel()
        runCatching {
            mediaPlayer?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        }
        latch?.countDown()
    }

    fun shutdown() {
        stop()
        prefetchExecutor.shutdownNow()
        client.dispatcher.executorService.shutdown()
    }

    private fun synthesizeCurrent(
        text: String,
        voice: String,
        traceId: String,
        generation: Long
    ): ByteArray = synthesize(
        text = text,
        voice = voice,
        traceId = traceId,
        isActive = { requestGeneration.get() == generation },
        onSocketChanged = { socket ->
            synchronized(playbackLock) {
                if (requestGeneration.get() == generation) {
                    activeWebSocket = socket
                } else {
                    socket?.cancel()
                }
            }
        }
    )

    private fun synthesize(
        text: String,
        voice: String,
        traceId: String,
        isActive: () -> Boolean,
        onSocketChanged: (WebSocket?) -> Unit
    ): ByteArray {
        var lastFailure: Throwable? = null
        repeat(2) { attempt ->
            try {
                return synthesizeOnce(text, voice, traceId, isActive, onSocketChanged)
            } catch (failure: MicrosoftEdgeTtsHandshakeException) {
                lastFailure = failure
                if (attempt == 0 && failure.statusCode == 403 && adjustClockSkew(failure.serverDate)) {
                    ensureActive(isActive)
                    return@repeat
                }
                throw failure
            }
        }
        throw lastFailure ?: IllegalStateException("Microsoft TTS failed")
    }

    private fun synthesizeOnce(
        text: String,
        voice: String,
        traceId: String,
        isActive: () -> Boolean,
        onSocketChanged: (WebSocket?) -> Unit
    ): ByteArray {
        val requestId = UUID.randomUUID().toString().replace("-", "")
        val connectionId = UUID.randomUUID().toString().replace("-", "")
        val muid = UUID.randomUUID().toString().replace("-", "").uppercase()
        val audio = ByteArrayOutputStream()
        val done = CountDownLatch(1)
        var failure: Throwable? = null
        val epochMillis = System.currentTimeMillis() + clockSkewMillis.get()
        val requestBuilder = Request.Builder().url(
            MicrosoftEdgeTtsProtocol.websocketUrl(connectionId, epochMillis / 1_000L)
        )
        MicrosoftEdgeTtsProtocol.requestHeaders(muid).forEach(requestBuilder::addHeader)
        val request = requestBuilder.build()

        val webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                if (!isActive()) {
                    webSocket.cancel()
                    done.countDown()
                    return
                }
                trace(
                    traceId,
                    VoiceTraceEvents.TTS_CONNECTED,
                    mapOf("tts_provider" to "microsoft_edge", "http_status" to response.code.toString()),
                    once = true
                )
                webSocket.send(MicrosoftEdgeTtsProtocol.speechConfigMessage(epochMillis))
                webSocket.send(
                    MicrosoftEdgeTtsProtocol.ssmlMessage(requestId, text, voice, epochMillis)
                )
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                if (!isActive()) return
                val raw = bytes.toByteArray()
                val headerEnd = findHeaderEnd(raw)
                val payload = if (headerEnd >= 0) raw.copyOfRange(headerEnd, raw.size) else raw
                if (payload.isNotEmpty()) {
                    trace(
                        traceId,
                        VoiceTraceEvents.TTS_FIRST_AUDIO,
                        mapOf("tts_provider" to "microsoft_edge"),
                        once = true
                    )
                    audio.write(payload)
                }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                if (!isActive()) return
                if (text.contains("Path:turn.end", ignoreCase = true)) {
                    done.countDown()
                    webSocket.close(1000, "done")
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                failure = if (response != null) {
                    MicrosoftEdgeTtsHandshakeException(response.code, response.header("Date"), t)
                } else {
                    t
                }
                done.countDown()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                done.countDown()
            }
        })
        onSocketChanged(webSocket)

        try {
            if (!done.await(30, TimeUnit.SECONDS)) {
                webSocket.cancel()
                error("Microsoft TTS timeout")
            }
        } finally {
            onSocketChanged(null)
        }
        ensureActive(isActive)
        failure?.let { throw it }
        val data = audio.toByteArray()
        if (data.isEmpty()) error("Microsoft TTS returned empty audio")
        return data
    }

    private fun adjustClockSkew(serverDate: String?): Boolean {
        val serverMillis = runCatching {
            ZonedDateTime.parse(serverDate.orEmpty(), DateTimeFormatter.RFC_1123_DATE_TIME)
                .toInstant()
                .toEpochMilli()
        }.getOrNull() ?: return false
        clockSkewMillis.set(serverMillis - System.currentTimeMillis())
        return true
    }

    private fun playAudio(
        audio: ByteArray,
        traceId: String,
        generation: Long,
        onPlaybackStarted: () -> Unit
    ) {
        ensureCurrent(generation)
        val file = File(context.cacheDir, "signalasi_tts_${System.currentTimeMillis()}.mp3")
        file.writeBytes(audio)
        val latch = CountDownLatch(1)
        val mp = MediaPlayer()
        synchronized(playbackLock) {
            ensureCurrent(generation)
            player = mp
            activePlaybackLatch = latch
        }
        mp.setDataSource(file.absolutePath)
        mp.setOnCompletionListener {
            it.release()
            synchronized(playbackLock) {
                if (player === it) player = null
                if (activePlaybackLatch === latch) activePlaybackLatch = null
            }
            file.delete()
            latch.countDown()
        }
        mp.setOnErrorListener { mediaPlayer, _, _ ->
            mediaPlayer.release()
            synchronized(playbackLock) {
                if (player === mediaPlayer) player = null
                if (activePlaybackLatch === latch) activePlaybackLatch = null
            }
            file.delete()
            latch.countDown()
            true
        }
        mp.prepare()
        ensureCurrent(generation)
        mp.start()
        runCatching(onPlaybackStarted)
        trace(
            traceId,
            VoiceTraceEvents.TTS_PLAYBACK_STARTED,
            mapOf("tts_provider" to "microsoft_edge"),
            once = true
        )
        latch.await(90, TimeUnit.SECONDS)
        file.delete()
        ensureCurrent(generation)
    }

    private fun beginRequest(): Long {
        stopCurrentRequest()
        return requestGeneration.get()
    }

    private fun awaitPrefetchedAudio(
        key: String,
        text: String,
        voice: String,
        generation: Long
    ): ByteArray? {
        if (key.isBlank()) return null
        val request = prefetches[key] ?: return null
        if (request.text != text || request.voice != voice) {
            if (prefetches.remove(key, request)) request.cancel()
            return null
        }
        try {
            while (true) {
                ensureCurrent(generation)
                try {
                    return request.audio.get(PREFETCH_WAIT_SLICE_MILLIS, TimeUnit.MILLISECONDS)
                } catch (_: TimeoutException) {
                    continue
                }
            }
        } catch (_: ExecutionException) {
            return null
        } catch (_: java.util.concurrent.CancellationException) {
            ensureCurrent(generation)
            return null
        } finally {
            prefetches.remove(key, request)
        }
    }

    private fun ensureCurrent(generation: Long) {
        if (requestGeneration.get() != generation) throw CancellationException("Microsoft TTS request cancelled")
    }

    private fun ensureActive(isActive: () -> Boolean) {
        if (!isActive()) throw CancellationException("Microsoft TTS request cancelled")
    }

    private fun trace(
        traceId: String,
        event: String,
        attributes: Map<String, String> = mapOf("tts_provider" to "microsoft_edge"),
        once: Boolean = false
    ) {
        if (traceId.isNotBlank()) {
            VoiceLatencyTelemetry.record(context, traceId, event, attributes, once)
        }
    }

    private fun findHeaderEnd(raw: ByteArray): Int {
        for (i in 0 until raw.size - 3) {
            if (raw[i] == '\r'.code.toByte() &&
                raw[i + 1] == '\n'.code.toByte() &&
                raw[i + 2] == '\r'.code.toByte() &&
                raw[i + 3] == '\n'.code.toByte()
            ) {
                return i + 4
            }
        }
        return -1
    }

    private companion object {
        const val MAX_PREFETCHES = 12
        const val PREFETCH_WAIT_SLICE_MILLIS = 100L
    }
}

private class MicrosoftEdgeTtsHandshakeException(
    val statusCode: Int,
    val serverDate: String?,
    cause: Throwable
) : IllegalStateException("Microsoft TTS handshake failed: HTTP $statusCode", cause)
