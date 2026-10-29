package com.galaxyssi.chat

import android.content.Context
import com.galaxyssi.chat.voice.audio.AndroidPcmRecorder
import com.galaxyssi.chat.voice.audio.PcmCaptureConfig
import com.galaxyssi.chat.voice.audio.PcmStopReason
import com.galaxyssi.chat.voice.audio.VoiceAudioHub
import com.galaxyssi.chat.voice.audio.VoiceAudioHubListener
import com.galaxyssi.chat.voice.audio.VoiceAudioSession
import com.galaxyssi.chat.voice.audio.VoiceAudioSessionConfig
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Uses the existing 16 kHz Whisper/QNN path; recognition never submits an Agent task. */
internal class DesktopDraftVoice(
    context: Context,
    private val onBusy: (Boolean) -> Unit,
    private val onTranscript: (String) -> Unit,
    private val onFailure: () -> Unit
) {
    private val context = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val hub = VoiceAudioHub(AndroidPcmRecorder(this.context), scope,
        vadFactory = { com.galaxyssi.chat.voice.audio.NeuralSpeechVad(
            com.galaxyssi.chat.voice.audio.SileroSpeechProbabilityModel(this.context.assets)
        ) })
    private var session: VoiceAudioSession? = null
    private var busy = false
    @Volatile private var generation = 0L
    @Volatile private var closed = false

    fun start(): Boolean {
        if (closed || busy || session != null) return false
        val epoch = ++generation
        session = hub.start(
            VoiceAudioSessionConfig(capture = PcmCaptureConfig(maxDurationMs = 120_000)),
            object : VoiceAudioHubListener {
                override fun onFailure(session: VoiceAudioSession, error: Throwable) {
                    scope.launch(Dispatchers.Main) {
                        if (generation == epoch && !closed) { cancel(); onFailure() }
                    }
                }
            }
        )
        return session != null
    }

    fun amplitude(): Int = hub.currentAmplitude()

    fun finish(transcribe: Boolean) {
        val active = session ?: return
        session = null
        busy = true
        val epoch = generation
        val reason = if (transcribe) PcmStopReason.USER_SEND else PcmStopReason.USER_CANCEL
        hub.requestStop(active, reason)
        onBusy(transcribe)
        scope.launch {
            var samples: ShortArray? = null
            try {
                val capture = withContext(NonCancellable) { hub.stop(active, reason) }
                samples = capture?.snapshot?.samples
                if (transcribe && capture?.snapshot?.speechDetected == true &&
                    samples != null && samples.isNotEmpty() && generation == epoch && !closed) {
                    val text = LocalWhisperAsr.transcribePcm(context, samples, capture.snapshot.sampleRateHz,
                        language = VoiceAssistantSettings.get(context).asrLanguage,
                        traceId = "desktop-draft-${active.id}",
                        source = "desktop_draft_pcm16")
                    withContext(Dispatchers.Main) {
                        if (generation == epoch && !closed) {
                            if (text.isNotBlank()) onTranscript(text) else onFailure()
                        }
                    }
                } else if (transcribe) {
                    withContext(Dispatchers.Main) { if (generation == epoch && !closed) onFailure() }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { if (generation == epoch && !closed) onFailure() }
            } finally {
                samples?.fill(0)
                withContext(NonCancellable + Dispatchers.Main) {
                    busy = false
                    if (!closed) onBusy(false)
                    else scope.cancel()
                }
            }
        }
    }

    fun cancel() {
        generation++
        finish(false)
    }

    fun close() {
        closed = true
        cancel()
        if (!busy) scope.cancel()
    }
}
