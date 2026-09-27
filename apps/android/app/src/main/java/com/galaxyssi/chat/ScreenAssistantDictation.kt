package com.galaxyssi.chat

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.galaxyssi.chat.voice.audio.AdaptiveEndpointConfig
import com.galaxyssi.chat.voice.audio.DirectPcmFramePacket
import com.galaxyssi.chat.voice.audio.EndpointReason
import com.galaxyssi.chat.voice.audio.PcmCaptureConfig
import com.galaxyssi.chat.voice.audio.PcmFramePacket
import com.galaxyssi.chat.voice.audio.PcmStopReason
import com.galaxyssi.chat.voice.audio.PcmWaveFileAdapter
import com.galaxyssi.chat.voice.audio.VoiceAudioHubListener
import com.galaxyssi.chat.voice.audio.VoiceAudioSession
import com.galaxyssi.chat.voice.audio.VoiceAudioSessionConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.util.UUID

internal const val SCREEN_ASSISTANT_DICTATION_PURPOSE = "screen_assistant_dictation"

internal enum class ScreenAssistantDictationState { IDLE, RECORDING, RECOGNIZING }

internal object ScreenAssistantComposerPolicy {
    fun canSubmit(text: CharSequence, state: ScreenAssistantDictationState): Boolean =
        text.isNotBlank() && state == ScreenAssistantDictationState.IDLE

    fun returnsDraftOnly(purpose: String): Boolean = purpose == SCREEN_ASSISTANT_DICTATION_PURPOSE
}

/** Shares the home audio hub and configured ASR; never dispatches a voice command. */
internal class ScreenAssistantDictation(
    private val runner: MainActivity,
    private val onState: (ScreenAssistantDictationState) -> Unit,
    private val onText: (String) -> Unit,
    private val onError: (Int) -> Unit
) : AutoCloseable {
    private val main = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val hub = runner.voiceAudioHub()
    private val traceId = "screen-dictation-${UUID.randomUUID()}"
    private var session: VoiceAudioSession? = null
    private var stopping = false
    private var foregroundClaimed = false
    @Volatile private var closed = false

    fun start(): Boolean {
        if (closed || session != null || runner.isVoiceCaptureActive()) return false
        if (runner.isHighAccuracyQnnSelected()) {
            foregroundClaimed = true
            runner.highAccuracyAsrController.onAppForegroundChanged(true)
            runner.highAccuracyAsrController.onMicrophonePermissionChanged(true)
        }
        val online = runner.startOnlineRealtimeAsrTurn(SCREEN_ASSISTANT_DICTATION_PURPOSE, traceId)
        val qnn = if (online == null) {
            runner.startHighAccuracyAsrTurn(SCREEN_ASSISTANT_DICTATION_PURPOSE, traceId)
        } else null
        val endpoint = AdaptiveEndpointConfig(noSpeechTimeoutMs = 10_000L)
        session = hub.start(
            VoiceAudioSessionConfig(
                capture = PcmCaptureConfig(frameDurationMs = if (qnn != null) 10 else 20),
                endpoint = endpoint,
                autoEndpoint = true
            ),
            object : VoiceAudioHubListener {
                override val acceptsDirectPcmFrames = qnn != null
                override val acceptsPcmFrames = online != null
                override fun onDirectPcmFrame(session: VoiceAudioSession, frame: DirectPcmFramePacket) {
                    qnn?.offer(frame)
                }
                override fun onPcmFrame(session: VoiceAudioSession, frame: PcmFramePacket) {
                    online?.offer(frame)
                }
                override fun onEndpoint(session: VoiceAudioSession, reason: EndpointReason) {
                    main.post {
                        if (this@ScreenAssistantDictation.session?.id != session.id || closed) return@post
                        stop(reason != EndpointReason.NO_SPEECH_TIMEOUT)
                    }
                }
                override fun onFailure(session: VoiceAudioSession, error: Throwable) {
                    main.post {
                        if (closed) return@post
                        Log.w("GalaxySSIScreenVoice", "Dictation capture failed", error)
                        stop(false)
                        onError(R.string.voice_status_recording_failed)
                    }
                }
            }
        )
        if (session == null) {
            clearAsr()
            releaseForeground()
            return false
        }
        Log.i("GalaxySSIScreenVoice", "Dictation started trace=$traceId")
        onState(ScreenAssistantDictationState.RECORDING)
        return true
    }

    fun stop(send: Boolean = true) {
        val active = session ?: return
        if (stopping) return
        stopping = true
        val reason = if (send) PcmStopReason.USER_SEND else PcmStopReason.USER_CANCEL
        hub.requestStop(active, reason)
        if (!closed) onState(ScreenAssistantDictationState.RECOGNIZING)
        scope.launch {
            val capture = runCatching { hub.stop(active, reason) }.getOrNull()
            val samples = capture?.snapshot?.samples
            try {
                runner.finishStreamingPcmAsr(traceId, capture?.snapshot, send && !closed,
                    capture != null, mayKeepFinal = { !closed })
                if (closed || !send || capture == null || samples == null || samples.isEmpty() || !capture.snapshot.speechDetected) {
                    clearAsr()
                    main.post {
                        releaseForeground()
                        if (!closed) {
                            onState(ScreenAssistantDictationState.IDLE)
                            onError(R.string.voice_status_no_speech)
                        }
                    }
                    return@launch
                }
                val file = PcmWaveFileAdapter.write(capture.snapshot, runner.cacheDir, traceId)
                main.post {
                    releaseForeground()
                    if (closed || runner.isDestroyed || runner.isFinishing) {
                        file.delete()
                        samples.fill(0)
                        clearAsr()
                        return@post
                    }
                    runner.transcribeLocally(
                        sourceFile = file,
                        traceId = traceId,
                        pcmSamples = samples,
                        sampleRateHz = capture.snapshot.sampleRateHz,
                        purpose = SCREEN_ASSISTANT_DICTATION_PURPOSE,
                        onSuccess = { text ->
                            samples.fill(0)
                            if (!closed) {
                                onState(ScreenAssistantDictationState.IDLE)
                                onText(text)
                            }
                        },
                        onFailure = {
                            samples.fill(0)
                            if (!closed) {
                                onState(ScreenAssistantDictationState.IDLE)
                                onError(R.string.voice_status_transcription_failed)
                            }
                        }
                    )
                }
            } catch (error: Exception) {
                samples?.fill(0)
                clearAsr()
                Log.w("GalaxySSIScreenVoice", "Dictation finalization failed", error)
                main.post {
                    releaseForeground()
                    if (!closed) {
                        onState(ScreenAssistantDictationState.IDLE)
                        onError(R.string.voice_status_transcription_failed)
                    }
                }
            } finally {
                if (closed || !send || capture?.snapshot?.speechDetected != true) samples?.fill(0)
                Log.i("GalaxySSIScreenVoice", "Dictation microphone stopped trace=$traceId")
                main.post { releaseForeground() }
                scope.cancel()
            }
        }
    }

    private fun clearAsr() {
        runner.onlineRealtimeAsrTurns.remove(traceId)?.close()
        runner.onlineRealtimeAsrFinals.remove(traceId)
        runner.closeLiveWhisperSession(traceId)
    }

    private fun releaseForeground() {
        if (!foregroundClaimed) return
        foregroundClaimed = false
        if (!runner.isDestroyed) {
            runner.highAccuracyAsrController.onAppForegroundChanged(runner.conversationWindow.visible)
        }
    }

    override fun close() {
        if (closed) return
        closed = true
        if (session != null && !stopping) stop(false)
        else if (!stopping) {
            clearAsr()
            releaseForeground()
            scope.cancel()
        }
    }
}
