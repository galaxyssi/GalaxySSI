package com.galaxyssi.chat.voice.asr.online

import com.galaxyssi.chat.voice.asr.AsrAbortReason
import com.galaxyssi.chat.voice.asr.AsrAudioFrame
import com.galaxyssi.chat.voice.asr.AsrAvailability
import com.galaxyssi.chat.voice.asr.AsrError
import com.galaxyssi.chat.voice.asr.AsrEvent
import com.galaxyssi.chat.voice.asr.AsrMetrics
import com.galaxyssi.chat.voice.asr.AsrProvider
import com.galaxyssi.chat.voice.asr.AsrProviderSelector
import com.galaxyssi.chat.voice.asr.AsrSession
import com.galaxyssi.chat.voice.asr.AsrSessionConfig
import com.galaxyssi.chat.voice.asr.AsrTransport
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

class RealtimeAsrProvider(
    override val id: String,
    private val client: OkHttpClient,
    private val credentialSource: RealtimeAsrCredentialSource,
    private val protocol: RealtimeAsrWireProtocol = SignalAsrRealtimeProtocol,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val nowEpochMs: () -> Long = System::currentTimeMillis,
    private val heartbeatIntervalMs: Long = 10_000L,
    private val maximumReconnects: Int = 2,
    private val sendQueueCapacity: Int = 12
) : AsrProvider, AutoCloseable {
    init {
        require(id.isNotBlank())
        require(heartbeatIntervalMs in 1_000L..60_000L)
        require(maximumReconnects in 0..5)
        require(sendQueueCapacity in 2..64)
    }

    override suspend fun isAvailable(config: AsrSessionConfig): AsrAvailability {
        if (!AsrProviderSelector.onlineAllowed(config)) {
            return AsrAvailability.unavailable("online_asr_blocked_by_privacy_or_network")
        }
        val broker = credentialSource.availability(config)
        if (!broker.available) return broker
        return if (AsrTransport.WEBSOCKET in config.preferredTransports) {
            AsrAvailability.ready(AsrTransport.WEBSOCKET)
        } else {
            AsrAvailability.unavailable("websocket_transport_not_allowed")
        }
    }

    override suspend fun createSession(config: AsrSessionConfig): AsrSession {
        val availability = isAvailable(config)
        check(availability.available) { "Realtime ASR unavailable: ${availability.reasonCode}" }
        val credential = credentialSource.issue(config)
        check(!credential.isExpired(nowEpochMs(), 5_000L)) { "Realtime ASR credential expires too soon" }
        check(AsrTransport.WEBSOCKET in credential.supportedTransports) {
            "Realtime ASR credential does not support WebSocket"
        }
        return RealtimeAsrSession(
            providerId = id,
            config = config,
            credential = credential,
            client = client,
            protocol = protocol,
            dispatcher = dispatcher,
            nowEpochMs = nowEpochMs,
            heartbeatIntervalMs = heartbeatIntervalMs,
            maximumReconnects = maximumReconnects,
            sendQueueCapacity = sendQueueCapacity
        )
    }

    override fun close() {
        credentialSource.close()
    }
}

internal class RealtimeAsrSession(
    private val providerId: String,
    private val config: AsrSessionConfig,
    private val credential: EphemeralAsrCredential,
    private val client: OkHttpClient,
    private val protocol: RealtimeAsrWireProtocol,
    dispatcher: CoroutineDispatcher,
    private val nowEpochMs: () -> Long,
    private val heartbeatIntervalMs: Long,
    private val maximumReconnects: Int,
    sendQueueCapacity: Int
) : AsrSession {
    private sealed interface Outbound {
        data class Audio(val batch: AsrAudioBatch) : Outbound
        data object Finish : Outbound
    }

    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val mutableEvents = MutableSharedFlow<AsrEvent>(replay = 1, extraBufferCapacity = 128)
    private val queue = Channel<Outbound>(sendQueueCapacity)
    private val batcher = RealtimePcmBatcher()
    private val started = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val finishRequested = AtomicBoolean(false)
    private val finalSeen = AtomicBoolean(false)
    private val audioSent = AtomicBoolean(false)
    private val terminalEventSent = AtomicBoolean(false)
    private val ready = CompletableDeferred<Unit>()
    private val socket = AtomicReference<WebSocket?>()
    private val socketGeneration = AtomicInteger(0)
    private val reconnectCount = AtomicInteger(0)
    private val droppedAudioBatches = AtomicInteger(0)
    private val sentAudioMs = AtomicLong(0L)
    private val highestRevision = AtomicInteger(-1)
    private var senderJob: Job? = null
    private var heartbeatJob: Job? = null

    override val events: Flow<AsrEvent> = mutableEvents.asSharedFlow()

    override suspend fun start() {
        if (!started.compareAndSet(false, true)) {
            ready.await()
            return
        }
        senderJob = scope.launch { sendLoop() }
        connect()
        try {
            withTimeout(config.connectTimeoutMs) { ready.await() }
        } catch (error: Throwable) {
            emitFatal("connect_timeout", retryable = false)
            closeInternal("connect_timeout", cancelSocket = true)
            throw error
        }
    }

    override suspend fun pushPcm(frame: AsrAudioFrame) {
        if (closed.get() || finishRequested.get()) return
        if (credential.isExpired(nowEpochMs(), 1_000L)) {
            emitFatal("credential_expired", retryable = true)
            closeInternal("credential_expired", cancelSocket = true)
            return
        }
        batcher.offer(frame).forEach(::enqueueBatch)
    }

    override suspend fun finishInput() {
        if (closed.get() || !finishRequested.compareAndSet(false, true)) return
        batcher.flush()?.let(::enqueueBatch)
        if (!queue.trySend(Outbound.Finish).isSuccess) {
            emitRecoverable("send_queue_overflow", retryable = false)
            closeInternal("send_queue_overflow", cancelSocket = true)
        }
    }

    override fun requestAbort(reason: AsrAbortReason) {
        if (closed.get()) return
        socket.get()?.send(protocol.abortMessage(config, reason.name.lowercase()))
        closeInternal(reason.name.lowercase(), cancelSocket = false)
    }

    override fun close() {
        closeInternal("session_closed", cancelSocket = true)
    }

    private fun connect() {
        if (closed.get()) return
        if (credential.isExpired(nowEpochMs(), 1_000L)) {
            emitFatal("credential_expired", retryable = true)
            closeInternal("credential_expired", cancelSocket = true)
            return
        }
        val generation = socketGeneration.incrementAndGet()
        val request = Request.Builder()
            .url(credential.websocketUrl)
            .header(credential.authorizationHeader, credential.authorizationValue())
            .header("X-GalaxySSI-Session", credential.providerSessionId)
            .build()
        socket.set(client.newWebSocket(request, listener(generation)))
    }

    private fun listener(generation: Int) = object : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            if (generation != socketGeneration.get() || closed.get()) {
                webSocket.cancel()
                return
            }
            socket.set(webSocket)
            if (!webSocket.send(protocol.startMessage(config, credential))) {
                handleSocketFailure(generation, "session_start_send_failed")
                return
            }
            emit(AsrEvent.Ready(providerId, credential.providerSessionId, AsrTransport.WEBSOCKET))
            ready.complete(Unit)
            heartbeatJob?.cancel()
            heartbeatJob = scope.launch {
                while (isActive && !closed.get()) {
                    delay(heartbeatIntervalMs)
                    socket.get()?.send(protocol.heartbeatMessage(config, nowEpochMs()))
                }
            }
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            if (generation != socketGeneration.get() || closed.get()) return
            protocol.parseServerEvent(text, config, credential)?.let(::handleServerEvent)
        }

        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            emitRecoverable("unexpected_binary_event", retryable = true)
        }

        override fun onFailure(webSocket: WebSocket, error: Throwable, response: Response?) {
            if (generation != socketGeneration.get() || closed.get()) return
            handleSocketFailure(generation, failureCode(response?.code, error))
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            if (generation != socketGeneration.get() || closed.get()) return
            if (finalSeen.get() || finishRequested.get()) {
                closeInternal("provider_closed", cancelSocket = false)
            } else {
                handleSocketFailure(generation, "provider_closed_$code")
            }
        }
    }

    private suspend fun sendLoop() {
        for (item in queue) {
            if (closed.get()) break
            try {
                ready.await()
            } catch (_: Throwable) {
                break
            }
            val activeSocket = socket.get()
            if (activeSocket == null) {
                emitRecoverable("socket_not_ready", retryable = true)
                break
            }
            when (item) {
                is Outbound.Audio -> {
                    val sent = activeSocket.send(protocol.encodeAudio(item.batch))
                    if (!sent) {
                        item.batch.samples.fill(0)
                        handleSocketFailure(socketGeneration.get(), "audio_send_failed")
                        break
                    }
                    audioSent.set(true)
                    sentAudioMs.addAndGet(item.batch.durationMs)
                    item.batch.samples.fill(0)
                }
                Outbound.Finish -> {
                    if (!activeSocket.send(protocol.finishMessage(config))) {
                        handleSocketFailure(socketGeneration.get(), "finish_send_failed")
                    }
                }
            }
        }
    }

    private fun enqueueBatch(batch: AsrAudioBatch) {
        if (queue.trySend(Outbound.Audio(batch)).isSuccess) return
        batch.samples.fill(0)
        droppedAudioBatches.incrementAndGet()
        emitRecoverable("send_queue_overflow", retryable = false)
    }

    private fun handleServerEvent(event: AsrEvent) {
        when (event) {
            is AsrEvent.Partial -> if (acceptRevision(event.hypothesis.revision, allowSame = false)) emit(event)
            is AsrEvent.Stable -> if (acceptRevision(event.hypothesis.revision, allowSame = true)) emit(event)
            is AsrEvent.Final -> {
                if (event.hypothesis.transcriptId != config.transcriptId || !finalSeen.compareAndSet(false, true)) return
                highestRevision.updateAndGet { current -> maxOf(current, event.hypothesis.revision) }
                emit(event)
                emitMetrics()
            }
            is AsrEvent.FatalError -> {
                emit(event)
                closeInternal(event.error.code, cancelSocket = true)
            }
            is AsrEvent.Closed -> closeInternal(event.reasonCode.ifBlank { "provider_closed" }, cancelSocket = false)
            else -> emit(event)
        }
    }

    private fun acceptRevision(revision: Int, allowSame: Boolean): Boolean {
        while (true) {
            val current = highestRevision.get()
            if (revision < current || (!allowSame && revision == current)) return false
            if (revision == current || highestRevision.compareAndSet(current, revision)) return true
        }
    }

    private fun handleSocketFailure(generation: Int, code: String) {
        if (generation != socketGeneration.get() || closed.get()) return
        heartbeatJob?.cancel()
        val canReconnect = !audioSent.get() && !finishRequested.get() &&
            reconnectCount.get() < maximumReconnects && !credential.isExpired(nowEpochMs(), 2_000L)
        if (canReconnect) {
            val attempt = reconnectCount.incrementAndGet()
            emitRecoverable(code, retryable = true)
            scope.launch {
                delay((attempt * 150L).coerceAtMost(600L))
                connect()
            }
        } else {
            emitRecoverable(code, retryable = false)
            if (!ready.isCompleted) ready.completeExceptionally(IllegalStateException(code))
            closeInternal(code, cancelSocket = true)
        }
    }

    private fun emitMetrics() {
        emit(
            AsrEvent.Metrics(
                AsrMetrics(
                    providerId = providerId,
                    providerSessionId = credential.providerSessionId,
                    audioSentMs = sentAudioMs.get(),
                    reconnectCount = reconnectCount.get(),
                    droppedAudioBatches = droppedAudioBatches.get()
                )
            )
        )
    }

    private fun emitRecoverable(code: String, retryable: Boolean) {
        emit(
            AsrEvent.RecoverableError(
                AsrError(code, retryable = retryable, providerId = providerId, providerSessionId = credential.providerSessionId)
            )
        )
    }

    private fun emitFatal(code: String, retryable: Boolean) {
        emit(
            AsrEvent.FatalError(
                AsrError(code, retryable = retryable, providerId = providerId, providerSessionId = credential.providerSessionId)
            )
        )
    }

    private fun emit(event: AsrEvent) {
        mutableEvents.tryEmit(event)
    }

    private fun closeInternal(reasonCode: String, cancelSocket: Boolean) {
        if (!closed.compareAndSet(false, true)) return
        heartbeatJob?.cancel()
        senderJob?.cancel()
        batcher.clear()
        queue.close()
        while (true) {
            val item = queue.tryReceive().getOrNull() ?: break
            if (item is Outbound.Audio) item.batch.samples.fill(0)
        }
        val activeSocket = socket.getAndSet(null)
        if (cancelSocket) activeSocket?.cancel() else activeSocket?.close(1000, reasonCode.take(120))
        credential.close()
        if (!ready.isCompleted) ready.completeExceptionally(IllegalStateException(reasonCode))
        if (terminalEventSent.compareAndSet(false, true)) {
            emit(AsrEvent.Closed(providerId, credential.providerSessionId, reasonCode))
        }
    }

    private fun failureCode(responseCode: Int?, error: Throwable): String = when {
        responseCode == 401 || responseCode == 403 -> "credential_rejected"
        responseCode != null -> "websocket_http_$responseCode"
        error.message?.contains("timeout", ignoreCase = true) == true -> "network_timeout"
        else -> "network_disconnected"
    }
}
