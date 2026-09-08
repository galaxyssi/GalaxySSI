package com.galaxyssi.chat.voice.audio

import android.media.MediaRecorder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

internal data class AcousticBargeInCallbacks(
    val onReady: (PcmRecorderState) -> Unit = {},
    val onDetected: () -> Unit,
    val onLevel: (Int) -> Unit = {},
    // Audio samples are borrowed for this callback and wiped immediately afterwards.
    val onAudio: ((PcmSnapshot) -> Unit)? = null,
    val onUtterance: (PcmSnapshot) -> Unit,
    val onDiagnostics: (AcousticBargeInStatistics, PcmRecorderState, String) -> Unit = { _, _, _ -> },
    val onMonitorRenewal: () -> Unit = {},
    val onUnavailable: (String) -> Unit = {}
)

/** Keeps capture open through interruption so the first word is not lost on a mic handover. */
internal class AcousticBargeInCapture(
    private val hub: VoiceAudioHub,
    private val scope: CoroutineScope,
    private val dispatch: (() -> Unit) -> Unit
) {
    private class Run(val callbacks: AcousticBargeInCallbacks) {
        val policy = AcousticBargeInPolicy()
        val finishing = AtomicBoolean(false)
        @Volatile var cancelled = false
        @Volatile var collecting = false
        @Volatile var interruptionDelivered = false
        @Volatile var protectionLost = false
        @Volatile var session: VoiceAudioSession? = null
        var frameSamples = 320
        var frames = 0L
        var nextStreamSample: Long? = null
        var watchdog: Job? = null
    }

    @Volatile private var current: Run? = null
    val active: Boolean get() = current != null
    val collectingUtterance: Boolean get() = current?.collecting == true

    fun start(callbacks: AcousticBargeInCallbacks): Boolean {
        if (current != null || hub.activeSession() != null) return false
        val run = Run(callbacks)
        current = run
        run.watchdog = scope.launch {
            delay(115_000L)
            finish(run, unavailable = "barge_in_capture_timeout")
        }
        val session = hub.start(
            VoiceAudioSessionConfig(
                capture = PcmCaptureConfig(
                    maxDurationMs = 120_000L,
                    preferredAudioSources = listOf(MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                        MediaRecorder.AudioSource.VOICE_RECOGNITION, MediaRecorder.AudioSource.MIC)
                ),
                endpoint = AdaptiveEndpointConfig(maxDurationMs = 120_000L),
                autoEndpoint = false
            ),
            object : VoiceAudioHubListener {
                override val acceptsPcmFrames = true
                override fun onCaptureReady(session: VoiceAudioSession, state: PcmRecorderState) {
                    run.session = session
                    if (run.cancelled) { finish(run); return }
                    dispatchIfCurrent(run) { callbacks.onReady(state) }
                    if (!AcousticBargeInPolicy.hasEchoProtection(state)) {
                        run.protectionLost = true
                        finish(run, unavailable = "echo_protection_unavailable")
                    }
                }

                override fun onPcmFrame(session: VoiceAudioSession, frame: PcmFramePacket) {
                    run.frameSamples = frame.samples.size
                    run.frames++
                    frame.samples.fill(0)
                }

                override fun onAudioLevel(session: VoiceAudioSession, decision: VadDecision) {
                    if (run.cancelled || run.finishing.get()) return
                    if (!run.interruptionDelivered && !AcousticBargeInPolicy.hasEchoProtection(hub.currentState())) {
                        run.protectionLost = true
                        finish(run, unavailable = "echo_protection_lost")
                        return
                    }
                    val update = run.policy.accept(decision, run.frameSamples)
                    if (update.started) {
                        run.collecting = true
                        val statistics = run.policy.statistics()
                        val protectedState = hub.currentState()
                        dispatchIfCurrent(run) {
                            if (run.protectionLost || (!run.finishing.get() &&
                                    !AcousticBargeInPolicy.hasEchoProtection(hub.currentState()))) {
                                run.protectionLost = true
                                finish(run, unavailable = "echo_protection_lost")
                            } else {
                                run.interruptionDelivered = true
                                callbacks.onDiagnostics(statistics, protectedState, "detected")
                                callbacks.onDetected()
                            }
                        }
                        run.nextStreamSample = run.policy.streamStartSample()
                        emitAudio(run)
                    }
                    if (run.collecting && run.frames % 5L == 0L) {
                        emitAudio(run)
                        dispatchIfCurrent(run) { callbacks.onLevel(decision.peak) }
                    }
                    if (update.endpoint) finish(run, send = true)
                    if (update.renewMonitor) finish(run, renew = true)
                }

                override fun onInputRouteChanged(session: VoiceAudioSession, route: String) {
                    if (!AcousticBargeInPolicy.hasEchoProtection(hub.currentState())) {
                        run.protectionLost = true
                        finish(run, unavailable = "audio_route_changed")
                    }
                }

                override fun onFailure(session: VoiceAudioSession, error: Throwable) {
                    run.session = session
                    finish(run, unavailable = (error as? PcmCaptureException)?.code ?: "barge_in_capture_failed")
                }
            }
        )
        if (session == null) { run.watchdog?.cancel(); current = null; return false }
        run.session = session
        if (run.cancelled) finish(run)
        return true
    }

    fun stop() {
        val run = current ?: return
        run.cancelled = true
        finish(run)
    }

    fun utteranceWindow(maxDurationMs: Long): PcmSnapshot? {
        val run = current?.takeIf { it.collecting && !it.cancelled && !it.finishing.get() } ?: return null
        val session = run.session ?: return null
        val raw = hub.snapshotWindow(session, maxDurationMs, trimToSpeech = false) ?: return null
        return try { run.policy.utterance(raw) } finally { raw.samples.fill(0) }
    }

    private fun emitAudio(run: Run) {
        if (run.callbacks.onAudio == null || run.cancelled) return
        val start = run.nextStreamSample ?: return
        val session = run.session ?: return
        val snapshot = hub.snapshotFrom(session, start) ?: return
        dispatchAudio(run, snapshot)
    }

    private fun dispatchAudio(run: Run, snapshot: PcmSnapshot) {
        if (snapshot.samples.isEmpty()) return
        run.nextStreamSample = snapshot.captureEndSampleExclusive
        dispatch {
            try {
                if (current === run && !run.cancelled && !run.protectionLost) run.callbacks.onAudio?.invoke(snapshot)
            } finally { snapshot.samples.fill(0) }
        }
    }

    private fun finish(run: Run, send: Boolean = false, renew: Boolean = false, unavailable: String? = null) {
        val session = run.session ?: return
        if (!run.finishing.compareAndSet(false, true)) return
        run.watchdog?.cancel()
        val statistics = run.policy.statistics()
        val state = hub.currentState()
        hub.requestStop(session, if (send) PcmStopReason.USER_SEND else PcmStopReason.USER_CANCEL)
        scope.launch {
            val capture = runCatching {
                hub.stop(session, if (send) PcmStopReason.USER_SEND else PcmStopReason.USER_CANCEL, trimToSpeech = false)
            }.getOrNull()
            val utterance = if (send && !run.cancelled && !run.protectionLost) capture?.snapshot?.let(run.policy::utterance) else null
            if (utterance != null && run.callbacks.onAudio != null) {
                val start = run.nextStreamSample ?: utterance.captureStartSample
                val offset = (start - utterance.captureStartSample).toInt().coerceIn(0, utterance.samples.size)
                dispatchAudio(run, utterance.copy(
                    samples = utterance.samples.copyOfRange(offset, utterance.samples.size),
                    captureStartSample = utterance.captureStartSample + offset
                ))
            }
            capture?.snapshot?.samples?.fill(0)
            dispatch {
                if (current !== run) { utterance?.samples?.fill(0); return@dispatch }
                current = null
                run.callbacks.onDiagnostics(statistics, state, when {
                    run.cancelled -> "cancelled"
                    utterance != null -> "submitted"
                    renew -> "renewed"
                    else -> unavailable ?: "capture_failed"
                })
                if (run.cancelled) { utterance?.samples?.fill(0); return@dispatch }
                when {
                    utterance != null -> run.callbacks.onUtterance(utterance)
                    renew -> run.callbacks.onMonitorRenewal()
                    else -> run.callbacks.onUnavailable(unavailable ?: "barge_in_capture_failed")
                }
            }
        }
    }

    private fun dispatchIfCurrent(run: Run, block: () -> Unit) = dispatch {
        if (current === run && !run.cancelled) block()
    }
}
