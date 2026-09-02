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
import java.util.concurrent.CancellationException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

class MicrosoftEdgeTts(private val context: Context) {
    private val client = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()
    private val requestGeneration = AtomicLong(0L)
    private val clockSkewMillis = AtomicLong(0L)
    private val playbackLock = Any()
    private var player: MediaPlayer? = null
    private var activeWebSocket: WebSocket? = null
    private var activePlaybackLatch: CountDownLatch? = null

    fun speak(
        text: String,
        voice: String,
        traceId: String = VoiceLatencyTraceContext.currentTraceId(),
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
                val audio = synthesize(text, voice, traceId, generation)
                ensureCurrent(generation)
                playAudio(audio, traceId, generation, onPlaybackStarted)
                ensureCurrent(generation)
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

    fun stop() {
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
        client.dispatcher.executorService.shutdown()
    }

    private fun synthesize(text: String, voice: String, traceId: String, generation: Long): ByteArray {
        var lastFailure: Throwable? = null
        repeat(2) { attempt ->
            try {
                return synthesizeOnce(text, voice, traceId, generation)
            } catch (failure: MicrosoftEdgeTtsHandshakeException) {
                lastFailure = failure
                if (attempt == 0 && failure.statusCode == 403 && adjustClockSkew(failure.serverDate)) {
                    ensureCurrent(generation)
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
        generation: Long
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
                if (requestGeneration.get() != generation) {
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
                if (requestGeneration.get() != generation) return
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
                if (requestGeneration.get() != generation) return
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
        synchronized(playbackLock) {
            if (requestGeneration.get() == generation) activeWebSocket = webSocket else webSocket.cancel()
        }

        if (!done.await(30, TimeUnit.SECONDS)) {
            webSocket.cancel()
            error("Microsoft TTS timeout")
        }
        synchronized(playbackLock) {
            if (activeWebSocket === webSocket) activeWebSocket = null
        }
        ensureCurrent(generation)
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
        stop()
        return requestGeneration.get()
    }

    private fun ensureCurrent(generation: Long) {
        if (requestGeneration.get() != generation) throw CancellationException("Microsoft TTS request cancelled")
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
}

private class MicrosoftEdgeTtsHandshakeException(
    val statusCode: Int,
    val serverDate: String?,
    cause: Throwable
) : IllegalStateException("Microsoft TTS handshake failed: HTTP $statusCode", cause)
