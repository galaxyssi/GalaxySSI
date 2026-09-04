package com.galaxyssi.chat.voice.audio

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

data class VoiceAudioSessionConfig(
    val capture: PcmCaptureConfig = PcmCaptureConfig(),
    val endpoint: AdaptiveEndpointConfig = AdaptiveEndpointConfig(),
    val autoEndpoint: Boolean = false
)

data class VoiceAudioSession(val id: String)

interface VoiceAudioHubListener {
    val acceptsDirectPcmFrames: Boolean
        get() = false

    val acceptsPcmFrames: Boolean
        get() = false

    fun onCaptureReady(session: VoiceAudioSession, state: PcmRecorderState) = Unit
    fun onDirectPcmFrame(session: VoiceAudioSession, frame: DirectPcmFramePacket) = Unit
    fun onPcmFrame(session: VoiceAudioSession, frame: PcmFramePacket) = Unit
    fun onAudioLevel(session: VoiceAudioSession, decision: VadDecision) = Unit
    fun onSpeechStarted(session: VoiceAudioSession, sequence: Long) = Unit
    fun onSpeechEndedCandidate(session: VoiceAudioSession, sequence: Long) = Unit
    fun onEndpoint(session: VoiceAudioSession, reason: EndpointReason) = Unit
    fun onInputRouteChanged(session: VoiceAudioSession, route: String) = Unit
    fun onFailure(session: VoiceAudioSession, error: Throwable) = Unit
}

class VoiceAudioHub(
    private val recorder: PcmRecorder,
    private val scope: CoroutineScope,
    private val sessionIdFactory: () -> String = { UUID.randomUUID().toString() },
    private val vadFactory: () -> VoiceActivityDetector = { AdaptiveSpeechVad() }
) {
    private data class ActiveSession(
        val public: VoiceAudioSession,
        val config: VoiceAudioSessionConfig,
        val store: SpeechSegmentStore,
        val vad: VoiceActivityDetector,
        val endpoint: AdaptiveEndpointDetector,
        val listener: VoiceAudioHubListener,
        val stopRequested: AtomicBoolean = AtomicBoolean(false),
        val completion: CompletableDeferred<Unit> = CompletableDeferred(),
        var lastRoute: String = "",
        var job: Job? = null
    )

    private val lock = Any()
    private var active: ActiveSession? = null

    fun start(
        config: VoiceAudioSessionConfig,
        listener: VoiceAudioHubListener = object : VoiceAudioHubListener {}
    ): VoiceAudioSession? {
        val session = synchronized(lock) {
            if (active != null) return null
            val public = VoiceAudioSession(sessionIdFactory())
            ActiveSession(
                public = public,
                config = config,
                store = InMemorySpeechSegmentStore(config.capture.sampleRateHz, config.capture.maxDurationMs + 1_000L),
                vad = vadFactory(),
                endpoint = AdaptiveEndpointDetector(
                    config.capture.sampleRateHz,
                    config.endpoint,
                    config.autoEndpoint
                ),
                listener = listener
            ).also { active = it }
        }
        session.job = scope.launch {
            try {
                val frames = recorder.start(session.config.capture)
                if (session.stopRequested.get()) {
                    recorder.stop(PcmStopReason.USER_CANCEL)
                    return@launch
                }
                val readyState = recorder.currentState()
                session.lastRoute = readyState.inputRoute
                safely { session.listener.onCaptureReady(session.public, readyState) }
                frames.collect { frame ->
                    try {
                        processFrame(session, frame)
                    } finally {
                        frame.close()
                    }
                }
            } catch (error: Throwable) {
                if (!session.stopRequested.get()) {
                    safely { session.listener.onFailure(session.public, error) }
                }
            } finally {
                session.completion.complete(Unit)
                if (!session.stopRequested.get()) {
                    session.store.clear()
                    synchronized(lock) {
                        if (active === session) active = null
                    }
                }
            }
        }
        return session.public
    }

    fun currentAmplitude(): Int = recorder.currentState().currentAmplitude

    fun currentState(): PcmRecorderState = recorder.currentState()

    fun requestStop(session: VoiceAudioSession, reason: PcmStopReason) {
        val current = synchronized(lock) { active?.takeIf { it.public.id == session.id } } ?: return
        current.stopRequested.set(true)
        recorder.requestStop(reason)
    }

    suspend fun stop(session: VoiceAudioSession, reason: PcmStopReason): VoiceAudioCaptureResult? {
        val current = synchronized(lock) { active?.takeIf { it.public.id == session.id } } ?: return null
        current.stopRequested.set(true)
        recorder.stop(reason)
        current.completion.await()
        val state = recorder.currentState()
        val result = VoiceAudioCaptureResult(
            sessionId = session.id,
            stopReason = state.stopReason ?: reason,
            snapshot = current.store.snapshot(
                SegmentRange(
                    preRollMs = current.config.endpoint.preRollMs,
                    postRollMs = current.config.endpoint.postRollMs
                )
            ),
            diagnostics = state.diagnostics,
            audioSource = state.audioSource,
            inputRoute = state.inputRoute
        )
        current.store.clear()
        synchronized(lock) {
            if (active === current) active = null
        }
        return result
    }

    fun activeSession(): VoiceAudioSession? = synchronized(lock) { active?.public }

    fun snapshotWindow(session: VoiceAudioSession, maxDurationMs: Long): PcmSnapshot? {
        val current = synchronized(lock) { active?.takeIf { it.public.id == session.id } } ?: return null
        return current.store.snapshotWindow(maxDurationMs)
    }

    private fun processFrame(session: ActiveSession, frame: AudioFrame) {
        session.store.append(frame)
        if (session.listener.acceptsDirectPcmFrames) {
            frame.directPcm16Buffer()?.let { pcm16 ->
                safely {
                    session.listener.onDirectPcmFrame(
                        session.public,
                        DirectPcmFramePacket(
                            sequence = frame.sequence,
                            captureTimeNanos = frame.captureTimeNanos,
                            pcm16 = pcm16,
                            sampleCount = frame.validSamples,
                            sampleRateHz = session.config.capture.sampleRateHz
                        )
                    )
                }
            }
        }
        if (session.listener.acceptsPcmFrames) {
            safely {
                session.listener.onPcmFrame(
                    session.public,
                    PcmFramePacket(
                        sequence = frame.sequence,
                        captureTimeNanos = frame.captureTimeNanos,
                        samples = frame.samples.copyOf(frame.validSamples),
                        sampleRateHz = session.config.capture.sampleRateHz
                    )
                )
            }
        }
        val vad = session.vad.accept(frame)
        val endpoint = session.endpoint.accept(frame, vad)
        if (endpoint.speechStarted) {
            session.store.markSpeechStart(frame.sequence)
            safely { session.listener.onSpeechStarted(session.public, frame.sequence) }
        }
        if (endpoint.speechEndedCandidate) {
            session.store.markSpeechEnd(frame.sequence)
            safely { session.listener.onSpeechEndedCandidate(session.public, frame.sequence) }
        }
        safely { session.listener.onAudioLevel(session.public, vad) }
        val route = recorder.currentState().inputRoute
        if (route.isNotBlank() && route != session.lastRoute) {
            session.lastRoute = route
            safely { session.listener.onInputRouteChanged(session.public, route) }
        }
        endpoint.endpointReason?.let { reason ->
            if (session.stopRequested.compareAndSet(false, true)) {
                safely { session.listener.onEndpoint(session.public, reason) }
            }
        }
    }

    private inline fun safely(block: () -> Unit) {
        runCatching(block)
    }
}
