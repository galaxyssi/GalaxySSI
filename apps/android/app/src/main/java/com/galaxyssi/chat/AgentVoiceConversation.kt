package com.galaxyssi.chat

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.app.Dialog
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import com.galaxyssi.chat.ui.AgentVoicePanel
import com.galaxyssi.chat.ui.AgentComposerUiPolicy
import com.galaxyssi.chat.voice.ForegroundChineseWake
import com.galaxyssi.chat.voice.LocalWakeAvailability
import com.galaxyssi.chat.voice.TranscriptHypothesis
import com.galaxyssi.chat.voice.VoiceConversationSession
import com.galaxyssi.chat.voice.VoiceInteractionEvent
import com.galaxyssi.chat.voice.VoiceInteractionPhase
import com.galaxyssi.chat.voice.VoiceInteractionState
import com.galaxyssi.chat.voice.audio.AcousticBargeInCallbacks
import com.galaxyssi.chat.voice.audio.AcousticBargeInCapture
import com.galaxyssi.chat.voice.audio.PcmSnapshot
import com.galaxyssi.chat.voice.audio.PcmWaveFileAdapter
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTelemetry
import com.galaxyssi.chat.voice.metrics.VoiceTraceEvents
import com.galaxyssi.chat.voice.tts.TtsCancelReason
import com.galaxyssi.chat.voice.tts.TtsChunkSchedulerCallbacks
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal class AgentVoiceConversation(private val activity: MainActivity) {
    val session = VoiceConversationSession()
    val panel = AgentVoicePanel(activity)
    private val replySpeech = AgentVoiceReplySpeech(session)
    internal val communicationAudio = com.galaxyssi.chat.voice.audio.VoiceCommunicationAudioSession(activity)
    private val preferences = activity.getSharedPreferences("galaxyssi_voice_conversation", 0)
    private var foreground = false
    private var pendingPermission = false
    private var pendingWakePermission = false
    private var speechRevision = 0L
    private var wakeArmed = false
    private var ownsScreenCapture = false
    private var screenPermissionGeneration: Long? = null
    private var screenConsentGeneration: Long? = null
    private var screenConsentDialog: AlertDialog? = null
    private var screenCaptureJob: Job? = null
    private var resumeAfterVisualInput = false
    private var cameraPermissionGeneration: Long? = null
    private var cameraConsentDialog: AlertDialog? = null
    private var visualSubmission: Job? = null
    private var pendingVisualTraceId = ""
    private var lastStatus = ""
    private var levelTick: Runnable? = null
    private var wakeStatusView: TextView? = null
    private var wakePrepareView: TextView? = null
    private var wakePhraseView: TextView? = null
    private var wakeDetailView: TextView? = null
    private var wakeToggle: Switch? = null
    private var bargeAsr: AgentBargeInTranscription? = null
    internal val bargeIn = AcousticBargeInCapture(activity.voiceAudioHub(), activity.voiceAssistantScope) {
        activity.runOnUiThread(it)
    }
    private var bargeInUnavailableForCall = false
    internal val cameraPreview = AgentVoiceCameraPreview(activity,
        onActiveChanged = { active -> panel.setCameraActive(active) },
        onFailure = { Toast.makeText(activity, R.string.voice_call_camera_error, Toast.LENGTH_LONG).show() }
    )
    private val chineseWake = ForegroundChineseWake(activity,
        onState = { state ->
            if (usesChineseWake()) wakeArmed = state.availability == LocalWakeAvailability.LISTENING
            renderWakeSettings()
        },
        onWake = { command ->
            if (visible() && !session.active && usesChineseWake() && preferences.getBoolean("foreground_wake", false)) {
                start(command)
            }
        }
    )
    internal val wakeDiagnostics get() = chineseWake.diagnostics
    val entry = ImageButton(activity).apply {
        setImageResource(R.drawable.ic_voice_call_wave)
        imageTintList = ColorStateList.valueOf(activity.getColor(R.color.text_primary))
        setBackgroundResource(android.R.color.transparent)
        setPadding(activity.dp(14), activity.dp(12), activity.dp(14), activity.dp(12))
        contentDescription = activity.getString(R.string.voice_call_start)
        tooltipText = contentDescription
        setOnClickListener { if (session.active) expand() else start() }
        setOnLongClickListener { showSettings(); true }
    }

    init {
        if (!preferences.contains("wake_phrase")) {
            preferences.edit().putString("wake_phrase",
                if (preferences.getBoolean("foreground_wake", false)) "hello" else "galaxy"
            ).apply()
        }
        val shell = activity.findViewById<LinearLayout>(R.id.agentInputShell)
        shell.addView(panel, shell.indexOfChild(activity.agentComposerRow), LinearLayout.LayoutParams(-1, -2))
        val output = activity.findViewById<View>(R.id.agentOutputViewport)
        val outputParent = output.parent as LinearLayout
        outputParent.addView(cameraPreview.view, outputParent.indexOfChild(output),
            LinearLayout.LayoutParams(-1, activity.dp((activity.resources.configuration.screenHeightDp * 0.22f).toInt().coerceIn(100, 220))).apply {
                marginStart = activity.dp(12); marginEnd = activity.dp(12)
                topMargin = activity.dp(8); bottomMargin = activity.dp(8)
            })
        activity.agentPrimaryActionSlot.addView(entry,
            FrameLayout.LayoutParams(activity.dp(52), activity.dp(54), Gravity.CENTER))
        updateEntry(activity.agentGoalInput.text?.isNotBlank() == true || activity.agentInputAttachments.isNotEmpty())
        panel.collapse.setOnClickListener { session.expand(false); render() }
        panel.keyboard.setOnClickListener {
            resumeAfterVisualInput = false
            pauseMicrophone()
            session.expand(false)
            render()
            activity.enterAgentComposerTextMode()
        }
        panel.microphone.setOnClickListener {
            resumeAfterVisualInput = false
            when {
                !session.muted && activity.isVoiceCaptureActive() && !activity.voiceAssistantSpeaking -> pauseMicrophone()
                else -> listen()
            }
        }
        panel.hangup.setOnClickListener { end() }
        panel.camera.setOnClickListener { toggleCamera() }
        panel.screen.setOnClickListener {
            if (!session.active || !visible() || screenPermissionGeneration != null ||
                screenCaptureJob != null || screenConsentDialog != null) return@setOnClickListener
            if (activity.agentInputAttachments.size >= MAX_AGENT_ATTACHMENTS) {
                Toast.makeText(activity, R.string.agent_attachment_rejected, Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            resumeAfterVisualInput = !session.muted
            pauseMicrophone()
            requestScreenInputConsent()
        }
    }

    fun visible(): Boolean = foreground && hasAgentSurface()

    private fun hasAgentSurface(): Boolean = activity.activeMainTab == PAGE_AGENT &&
        activity.agentPage.visibility == View.VISIBLE && activity.mainPage.visibility == View.VISIBLE &&
        activity.featurePage.visibility != View.VISIBLE && activity.chatPage.visibility != View.VISIBLE

    fun canUseAssistant(): Boolean = visible() && (wakeArmed || (session.active && !session.muted))

    fun updateEntry(hasInput: Boolean) {
        val composerState = AgentComposerUiPolicy.resolve(
            hasInput = hasInput,
            textModeActive = activity.agentComposerTextMode,
            actionTrayRequested = activity.agentActionTrayExpanded,
            voiceEntryAvailable = true
        )
        entry.visibility = if (composerState.showVoiceButton) View.VISIBLE else View.GONE
        activity.agentPrimaryActionSlot.visibility = if (composerState.showPrimaryActionSlot) View.VISIBLE else View.GONE
        entry.isSelected = session.active
        entry.imageTintList = ColorStateList.valueOf(activity.getColor(
            if (session.active) R.color.agent_voice_transcript_dot else R.color.text_primary
        ))
    }

    fun onForeground(value: Boolean) {
        foreground = value
        if (!value) {
            cameraPreview.stop()
            cancelVisualSubmission()
            if (screenCaptureJob != null) {
                resumeAfterVisualInput = false
                screenCaptureJob?.cancel()
            }
            chineseWake.stop()
            wakeArmed = false
            if (session.active) pauseMicrophone() else activity.releaseWakeWordEngine()
            communicationAudio.release()
        } else if (pendingPermission && activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            pendingPermission = false
            start()
        } else if (resumeAfterVisualInput && session.active) {
            onVisualInputReturned()
        } else if (!session.active) {
            refreshWake()
        }
        if (value && cameraPermissionGeneration != null &&
            activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            onCameraPermission(true)
        }
    }

    fun onNavigationChanged() {
        if (session.active && (!hasAgentSurface() || activity.agentTranscriptStore.activeConversation().id != session.conversationId)) end()
        refreshWake()
    }

    fun start(wakeCommand: String = "") {
        if (!visible()) return
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            pendingPermission = true
            activity.ensureRecordPermission()
            return
        }
        chineseWake.stop()
        wakeArmed = false
        activity.stopVoiceAssistant()
        if (!communicationAudio.acquire()) {
            Toast.makeText(activity, R.string.voice_call_audio_route_unavailable, Toast.LENGTH_LONG).show()
            return
        }
        session.begin(activity.agentTranscriptStore.activeConversation().id)
        bargeInUnavailableForCall = false
        activity.setAgentActionTrayExpanded(false)
        activity.exitAgentComposerTextMode(hideKeyboard = true)
        render()
        if (wakeCommand.isBlank()) listen() else routeWakeCommand(wakeCommand)
    }

    fun onPermission(granted: Boolean): Boolean {
        if (pendingWakePermission) {
            pendingWakePermission = false
            if (!granted) preferences.edit().putBoolean("foreground_wake", false).apply()
            wakeToggle?.isChecked = preferences.getBoolean("foreground_wake", false)
            refreshWake()
            renderWakeSettings()
            return true
        }
        if (!pendingPermission) return false
        pendingPermission = granted && !visible()
        if (granted && visible()) start()
        if (!granted) Toast.makeText(activity, R.string.voice_call_permission, Toast.LENGTH_LONG).show()
        return true
    }

    fun onVisualInputReturned() {
        if (!resumeAfterVisualInput || !session.active || !visible()) return
        if (screenPermissionGeneration != null || screenConsentDialog != null || screenCaptureJob != null) return
        resumeAfterVisualInput = false
        listen()
    }

    private fun requestScreenInputConsent() {
        val token = session.generation
        if (screenConsentGeneration == token) { requestScreenInput(); return }
        screenConsentDialog = AlertDialog.Builder(activity)
            .setTitle(R.string.voice_call_screen_consent_title)
            .setMessage(R.string.voice_call_screen_consent_message)
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(R.string.common_confirm) { _, _ ->
                if (session.isCurrent(token) && visible()) {
                    screenConsentGeneration = token
                    requestScreenInput()
                }
            }
            .create().also { dialog ->
                dialog.setOnDismissListener {
                    if (screenConsentDialog === dialog) screenConsentDialog = null
                    onVisualInputReturned()
                }
                dialog.show()
            }
    }

    private fun requestScreenInput() {
        if (AgentScreenCaptureService.isActive()) {
            captureScreenInput { check(AgentScreenCaptureService.requestCapture(activity)) }
        } else {
            screenPermissionGeneration = session.generation
            val manager = activity.getSystemService(android.media.projection.MediaProjectionManager::class.java)
            activity.startActivityForResult(manager.createScreenCaptureIntent(), REQUEST_VOICE_SCREEN_CAPTURE)
        }
    }

    private fun captureScreenInput(startCapture: () -> Unit) {
        val token = session.generation
        showStatus(R.string.voice_call_screen_capturing)
        lateinit var job: Job
        job = activity.voiceAssistantScope.launch(Dispatchers.Main.immediate, start = CoroutineStart.LAZY) {
            var frame: java.io.File? = null
            var stored: StoredVoiceVisualFrame? = null
            var addedToDraft = false
            try {
                frame = AgentVoiceScreenFrameCapture.capture(activity, startCapture)
                stored = AgentVoiceFrameStore.persist(activity, frame, AgentVoiceFrameSource.SCREEN)
                if (session.isCurrent(token, activity.agentTranscriptStore.activeConversation().id) && visible() &&
                    activity.agentInputAttachments.size < MAX_AGENT_ATTACHMENTS) {
                    activity.agentInputAttachments += stored.attachment
                    activity.renderAgentInputAttachments()
                    addedToDraft = true
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                if (session.isCurrent(token) && visible()) {
                    Toast.makeText(activity, R.string.voice_call_screen_frame_failed, Toast.LENGTH_LONG).show()
                }
            } finally {
                frame?.delete()
                if (!addedToDraft) stored?.file?.delete()
                if (screenCaptureJob === job) screenCaptureJob = null
                if (session.isCurrent(token) && visible()) {
                    if (!resumeAfterVisualInput && session.muted) showStatus(R.string.voice_call_muted)
                    onVisualInputReturned()
                }
            }
        }
        screenCaptureJob = job
        job.start()
    }

    fun onScreenCapturePermission(resultCode: Int, data: Intent?) {
        val token = screenPermissionGeneration ?: return
        screenPermissionGeneration = null
        if (!session.isCurrent(token, activity.agentTranscriptStore.activeConversation().id) || !hasAgentSurface()) return
        if (resultCode == Activity.RESULT_OK && data != null) {
            ownsScreenCapture = true
            captureScreenInput { AgentScreenCaptureService.start(activity, resultCode, data) }
        } else {
            Toast.makeText(activity, R.string.agent_screen_capture_permission_denied, Toast.LENGTH_SHORT).show()
        }
        onVisualInputReturned()
    }

    private fun toggleCamera() {
        if (!session.active || !visible()) return
        if (cameraPreview.active) { cameraPreview.stop(); return }
        if (!preferences.getBoolean("camera_share_accepted", false)) {
            if (cameraConsentDialog?.isShowing == true) return
            val token = session.generation
            cameraConsentDialog = AlertDialog.Builder(activity)
                .setTitle(R.string.voice_call_camera_consent_title)
                .setMessage(R.string.voice_call_camera_consent_message)
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.common_confirm) { _, _ ->
                    if (session.isCurrent(token) && visible()) {
                        preferences.edit().putBoolean("camera_share_accepted", true).apply()
                        toggleCamera()
                    }
                }
                .create().also { dialog ->
                    dialog.setOnDismissListener { if (cameraConsentDialog === dialog) cameraConsentDialog = null }
                    dialog.show()
                }
            return
        }
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            cameraPermissionGeneration = session.generation
            activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), REQUEST_AGENT_CAMERA_PERMISSION)
        } else cameraPreview.start()
    }

    fun onCameraPermission(granted: Boolean): Boolean {
        val token = cameraPermissionGeneration ?: return false
        if (granted && session.isCurrent(token) && !visible()) return true
        cameraPermissionGeneration = null
        if (granted && session.isCurrent(token) && visible()) cameraPreview.start()
        else if (!granted) Toast.makeText(activity, R.string.agent_camera_permission_required, Toast.LENGTH_LONG).show()
        return true
    }

    private fun cancelVisualSubmission() {
        visualSubmission?.cancel()
        visualSubmission = null
        pendingVisualTraceId = ""
    }

    fun end() {
        resumeAfterVisualInput = false
        screenConsentDialog?.dismiss()
        screenCaptureJob?.cancel()
        AgentRichPlaybackCoordinator.pauseAudioVideo()
        cameraConsentDialog?.dismiss()
        cameraPreview.stop()
        cancelVisualSubmission()
        chineseWake.stop()
        session.end()
        activity.voiceCoordinatorSession(session.latestTraceId).takeIf(String::isNotBlank)?.let { trace ->
            activity.dispatchVoiceCoordinator(VoiceInteractionEvent.Cancelled(trace, "inline_call_ended"))
        }
        speechRevision++
        stopReplySpeech()
        wakeArmed = false
        resumeAfterVisualInput = false
        stopLevelTick()
        activity.stopVoiceAssistant()
        if (ownsScreenCapture) AgentScreenCaptureService.stop(activity)
        communicationAudio.release()
        ownsScreenCapture = false
        render()
        // Hanging up ends media, not an already dispatched agent task.
    }

    private fun expand() {
        activity.exitAgentComposerTextMode(hideKeyboard = true)
        session.expand(true)
        render()
    }

    private fun listen(afterPlayback: Boolean = false) {
        if (!session.active || !visible()) return
        if (activity.agentTranscriptStore.activeConversation().id != session.conversationId) { end(); return }
        if (!communicationAudio.acquire()) {
            session.mute(true)
            panel.setMuted(true)
            showStatus(R.string.voice_call_audio_route_unavailable)
            return
        }
        val drainSpeaker = afterPlayback || activity.voiceAssistantSpeaking
        AgentRichPlaybackCoordinator.pauseAudioVideo()
        stopAcousticCapture()
        speechRevision++
        stopReplySpeech()
        activity.stopSpeechPlaybackOnly(TtsCancelReason.USER_STOP)
        activity.releaseVoicePlaybackAudioFocus()
        session.mute(false)
        activity.voiceAssistantAwake = true
        panel.transcript.text = ""
        showStatus(R.string.voice_call_listening)
        panel.setMuted(false)
        val token = session.generation
        val revision = speechRevision
        activity.handler.postDelayed({
            beginListeningWhenReady(token, revision, SystemClock.elapsedRealtime() + 3_000L)
        }, if (drainSpeaker) 300L else 0L)
        startLevelTick()
    }

    private fun beginListeningWhenReady(token: Long, revision: Long, deadline: Long) {
        if (!session.isCurrent(token) || speechRevision != revision || session.muted || !visible()) return
        if (!activity.isVoiceCaptureActive()) {
            activity.startCommandListening()
        } else if (SystemClock.elapsedRealtime() < deadline) {
            activity.handler.postDelayed({ beginListeningWhenReady(token, revision, deadline) }, 50L)
        } else {
            updateStatus(activity.getString(R.string.voice_status_recording_failed), "")
        }
    }

    private fun stopReplySpeech() {
        activity.applyAgentReplySpeechCommand(replySpeech.controller.stop(), replySpeech.controller)
    }

    fun stopAcousticCapture() {
        bargeAsr?.close()
        bargeAsr = null
        bargeIn.stop()
    }

    internal fun acceptsBargeInPartial(traceId: String): Boolean = session.acceptsTrace(traceId) && visible() &&
        bargeAsr?.let { it.traceId == traceId && it.receivingAudio } == true && bargeIn.collectingUtterance

    private fun updateBargeInTranscription(action: (AgentBargeInTranscription) -> Unit) {
        val transcription = bargeAsr ?: return
        runCatching { action(transcription) }.onFailure { error ->
            transcription.close()
            if (bargeAsr === transcription) bargeAsr = null
            VoiceLatencyTelemetry.record(activity, transcription.traceId, "barge_in_partial_unavailable",
                mapOf("error" to error.javaClass.simpleName), once = true)
        }
    }

    private fun startBargeInMonitor(token: Long, speech: Long) {
        fun ownsSpeech() = session.isCurrent(token) && speechRevision == speech && !session.muted && visible() && communicationAudio.active
        if (!communicationAudio.active) return
        if (!ownsSpeech() || bargeIn.active || bargeInUnavailableForCall || !activity.voiceAssistantSpeaking) return
        var inputRevision = speech
        var traceId = ""
        val playingTrace = session.traceForTurn(session.latestTurnId)
        fun ownsInput() = session.isCurrent(token) && speechRevision == inputRevision &&
            !session.muted && visible() && traceId.isNotBlank() && session.acceptsTrace(traceId)
        bargeIn.start(AcousticBargeInCallbacks(
            onDiagnostics = { statistics, state, outcome ->
                VoiceLatencyTelemetry.record(activity, playingTrace, "barge_in_monitor_summary", mapOf(
                    "aec_enabled" to state.acousticEchoCancelerEnabled.toString(),
                    "noise_suppression_enabled" to state.noiseSuppressorEnabled.toString(),
                    "input_route" to state.inputRoute,
                    "audio_source" to state.audioSource.toString(),
                    "duration_ms" to statistics.monitoredMs.toString(),
                    "max_rms" to statistics.maxRms.toString(),
                    "max_vad_probability" to statistics.maxProbability.toString(),
                    "candidate_duration_ms" to statistics.maxCandidateMs.toString(),
                    "capture_outcome" to outcome
                ))
            },
            onReady = { state ->
                VoiceLatencyTelemetry.record(activity, playingTrace, "barge_in_monitor_ready", mapOf(
                    "aec_enabled" to state.acousticEchoCancelerEnabled.toString(),
                    "noise_suppression_enabled" to state.noiseSuppressorEnabled.toString(),
                    "input_route" to state.inputRoute,
                    "audio_source" to state.audioSource.toString()
                ), once = true)
            },
            onDetected = {
                if (!ownsSpeech()) bargeIn.stop() else {
                    VoiceLatencyTelemetry.record(activity, playingTrace, VoiceTraceEvents.TTS_BARGE_IN_STARTED, once = true)
                    speechRevision++
                    inputRevision = speechRevision
                    stopReplySpeech()
                    activity.stopSpeechPlaybackOnly(TtsCancelReason.USER_STOP)
                    activity.releaseVoicePlaybackAudioFocus()
                    activity.voiceAssistantAwake = true
                    traceId = VoiceLatencyTelemetry.startSession(activity, mapOf("recording_source" to "acoustic_barge_in"))
                    val coordinator = activity.beginVoiceCoordinatorSession("voice_wakeup", traceId)
                    activity.activeVoiceTraceId = traceId
                    if (coordinator.isNotBlank()) {
                        activity.dispatchVoiceCoordinator(VoiceInteractionEvent.CapturePrepared(coordinator))
                        activity.dispatchVoiceCoordinator(VoiceInteractionEvent.SpeechStarted(coordinator, SystemClock.elapsedRealtimeNanos()))
                    }
                    panel.transcript.text = ""
                    panel.waveform.reset()
                    showStatus(R.string.voice_call_listening)
                    bargeAsr?.close()
                    bargeAsr = runCatching { AgentBargeInTranscription(activity, traceId) }
                        .onFailure { VoiceLatencyTelemetry.record(activity, traceId, "barge_in_partial_unavailable",
                            mapOf("error" to it.javaClass.simpleName), once = true) }
                        .getOrNull()
                    VoiceLatencyTelemetry.record(activity, playingTrace, VoiceTraceEvents.TTS_BARGE_IN_COMPLETED, once = true)
                }
            },
            onLevel = { if (ownsInput()) {
                panel.waveform.pushAmplitude(it)
                updateBargeInTranscription { transcription -> transcription.requestPartial(bargeIn::utteranceWindow) }
            } },
            onAudio = { snapshot -> if (ownsInput()) updateBargeInTranscription { it.offer(snapshot) } },
            onUtterance = { snapshot ->
                if (!ownsInput()) snapshot.samples.fill(0) else {
                    showStatus(R.string.voice_call_processing)
                    panel.waveform.reset()
                    transcribeBargeIn(snapshot, traceId, token, inputRevision)
                }
            },
            onMonitorRenewal = { if (ownsSpeech()) startBargeInMonitor(token, speech) },
            onUnavailable = {
                if (traceId.isBlank() && ownsSpeech()) {
                    bargeInUnavailableForCall = true
                    Toast.makeText(activity, R.string.voice_call_barge_unavailable, Toast.LENGTH_LONG).show()
                } else if (ownsInput()) {
                    bargeAsr?.close()
                    bargeAsr = null
                    updateStatus(activity.getString(R.string.voice_status_recording_failed), "")
                }
            }
        ))
    }

    private fun transcribeBargeIn(snapshot: PcmSnapshot, traceId: String, token: Long, revision: Long) {
        val transcription = bargeAsr?.takeIf { it.traceId == traceId }
        activity.voiceAssistantScope.launch {
            var file: java.io.File? = null
            var handedToAsr = false
            try {
                try {
                    transcription?.finish(snapshot)
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (error: Throwable) {
                    withContext(Dispatchers.Main.immediate) {
                        transcription?.close()
                        if (bargeAsr === transcription) bargeAsr = null
                    }
                    VoiceLatencyTelemetry.record(activity, traceId, "barge_in_stream_final_failed",
                        mapOf("error" to error.javaClass.simpleName), once = true)
                    // The full retained PCM still follows ordinary final transcription.
                }
                withContext(Dispatchers.IO) {
                    file = runCatching {
                        PcmWaveFileAdapter.write(snapshot, activity.cacheDir, "voice_barge_${System.currentTimeMillis()}")
                    }.getOrNull()
                }
                withContext(Dispatchers.Main.immediate) {
                    if (!session.isCurrent(token) || speechRevision != revision || !session.acceptsTrace(traceId) || !visible()) {
                        return@withContext
                    }
                    val capturedFile = file
                    if (capturedFile == null) {
                        updateStatus(activity.getString(R.string.voice_status_recording_failed), "")
                    } else {
                        activity.finalizePcmVoiceCommand(capturedFile, snapshot.durationMs, traceId,
                            activity.voiceCoordinatorSession(traceId), snapshot.samples, snapshot.sampleRateHz)
                        handedToAsr = true
                    }
                }
            } finally {
                if (!handedToAsr) {
                    snapshot.samples.fill(0)
                    withContext(NonCancellable + Dispatchers.IO) { file?.delete() }
                }
            }
        }
    }

    private fun routeWakeCommand(text: String) {
        activity.voiceAssistantAwake = true
        val traceId = VoiceLatencyTelemetry.startSession(activity, mapOf("recording_source" to "foreground_chinese_wake"))
        val coordinator = activity.beginVoiceCoordinatorSession("voice_wakeup", traceId)
        activity.activeVoiceTraceId = traceId
        if (coordinator.isNotBlank()) {
            activity.dispatchVoiceCoordinator(VoiceInteractionEvent.CapturePrepared(coordinator))
            activity.dispatchVoiceCoordinator(VoiceInteractionEvent.FinalizationStarted(coordinator))
        }
        val accepted = activity.acceptVoiceCoordinatorFinal(traceId, TranscriptHypothesis(
            text = text, revision = 1, provider = "android_on_device", isFinal = true, language = chineseWake.snapshot.languageTag
        ))
        if (accepted) routeTranscript(text, traceId)
    }

    private fun pauseMicrophone(preserveMediaPlayback: Boolean = false) {
        cancelVisualSubmission()
        if (!preserveMediaPlayback) session.mute(true)
        session.cancelPendingInput()
        speechRevision++
        stopReplySpeech()
        stopLevelTick()
        activity.stopVoiceAssistant()
        showStatus(R.string.voice_call_muted)
        panel.setMuted(true)
    }

    fun pauseForMediaPlayback(): Long? {
        if (!visible()) return null
        val id = session.beginMediaPlayback() ?: return null
        pauseMicrophone(preserveMediaPlayback = true)
        return id
    }

    fun finishMediaPlayback(id: Long) {
        if (session.finishMediaPlayback(id) && visible()) listen()
    }

    fun cancelMediaPlayback(id: Long) {
        session.cancelMediaPlayback(id)
    }

    fun registerTrace(purpose: String, traceId: String) {
        if (purpose == "voice_wakeup" && session.active) {
            cancelVisualSubmission()
            session.registerTrace(traceId)
            stopReplySpeech()
        }
    }

    fun routeTranscript(text: String, traceId: String): Boolean {
        if (!session.ownsTrace(traceId)) return false
        if (!session.acceptsTrace(traceId) || !visible()) return true
        if (activity.agentTranscriptStore.activeConversation().id != session.conversationId) { end(); return true }
        panel.transcript.text = text
        showStatus(R.string.voice_call_processing)
        stopLevelTick()
        if (pendingVisualTraceId == traceId) return true
        if (cameraPreview.active) {
            val token = session.generation
            val attachments = activity.agentInputAttachments.toList()
            pendingVisualTraceId = traceId
            visualSubmission = activity.voiceAssistantScope.launch(Dispatchers.Main.immediate) {
                var frame: java.io.File? = null
                var stored: StoredVoiceVisualFrame? = null
                var submitted = false
                try {
                    frame = cameraPreview.captureFrame()
                    stored = AgentVoiceFrameStore.persist(activity, frame)
                    if (session.isCurrent(token) && session.acceptsTrace(traceId) && visible() &&
                        cameraPreview.active &&
                        activity.agentTranscriptStore.activeConversation().id == session.conversationId) {
                        activity.submitAgentGoal(voiceTraceId = traceId,
                            pendingVoiceConversationId = session.conversationId, goalOverride = text,
                            attachmentsOverride = attachments + stored.attachment)
                        submitted = true
                    }
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    if (session.isCurrent(token) && session.acceptsTrace(traceId) && visible()) {
                        Toast.makeText(activity, R.string.voice_call_camera_frame_failed, Toast.LENGTH_LONG).show()
                        listen()
                    }
                } finally {
                    frame?.delete()
                    if (!submitted) stored?.file?.delete()
                    if (pendingVisualTraceId == traceId) { pendingVisualTraceId = ""; visualSubmission = null }
                }
            }
            return true
        }
        activity.submitAgentGoal(
            voiceTraceId = traceId,
            pendingVoiceConversationId = session.conversationId,
            goalOverride = text,
            attachmentsOverride = activity.agentInputAttachments.toList()
        )
        return true
    }

    fun onUtterance(state: VoiceInteractionState) {
        if (!session.acceptsTrace(state.sessionId)) return
        when (state.phase) {
            VoiceInteractionPhase.PREPARING, VoiceInteractionPhase.LISTENING, VoiceInteractionPhase.ENDPOINTING -> showStatus(R.string.voice_call_listening)
            VoiceInteractionPhase.FINALIZING_ASR, VoiceInteractionPhase.ROUTING,
            VoiceInteractionPhase.WAITING_MODEL_FIRST_TOKEN, VoiceInteractionPhase.STARTING_AGENT,
            VoiceInteractionPhase.AGENT_RUNNING, VoiceInteractionPhase.EXECUTING_LOCAL_ACTION -> showStatus(R.string.voice_call_processing)
            VoiceInteractionPhase.FAILED -> {
                stopLevelTick()
                if (state.failure?.code in setOf(
                        "mobile_agent_blocked", "mobile_agent_failed",
                        "agent_failed", "agent_timed_out", "agent_not_found"
                    )) {
                    // The canonical task result will explain the failure through normal reply speech.
                    showStatus(R.string.voice_call_task_failed)
                } else {
                    showStatus(R.string.voice_status_transcription_failed)
                    session.mute(true)
                    panel.setMuted(true)
                }
            }
            else -> Unit
        }
        val text = state.finalText ?: state.partialText.ifBlank { state.stableText }
        if (text.isNotBlank()) panel.transcript.text = text
    }

    fun onEntries(entries: List<AgentTranscriptEntry>) {
        if (!session.active || session.muted || !visible() || bargeIn.collectingUtterance ||
            (activity.isVoiceCaptureActive() && !bargeIn.active)) return
        val command = replySpeech.observe(entries)
        if (command.completedWithoutPlayback) {
            listen()
            return
        }
        val token = session.generation
        if (command.beginSessionId.isNotBlank()) speechRevision++
        val speech = speechRevision
        val traceId = session.traceForTurn(session.latestTurnId)
        val playbackSessionId = command.beginSessionId
        fun ownsPlayback() = session.isCurrent(token) && speechRevision == speech && !session.muted && visible()
        activity.applyAgentReplySpeechCommand(
            command,
            replySpeech.controller,
            traceId,
            TtsChunkSchedulerCallbacks(
                onPlaybackStarted = { chunk ->
                    if (ownsPlayback()) {
                        VoiceLatencyTelemetry.record(activity, traceId, VoiceTraceEvents.VOICE_REPLY_PLAYBACK_STARTED,
                            mapOf("playback_session_id" to chunk.requestId,
                                "speech_characters" to chunk.speechText.codePointCount(0, chunk.speechText.length).toString(),
                                "tts_provider" to activity.activeProgressiveSpeechProvider), once = true)
                        showStatus(R.string.voice_call_speaking)
                        panel.transcript.text = chunk.speechText
                        startBargeInMonitor(token, speech)
                    }
                },
                onFinished = { success, errorCode ->
                    if (ownsPlayback()) {
                        VoiceLatencyTelemetry.record(activity, traceId, VoiceTraceEvents.VOICE_REPLY_PLAYBACK_FINISHED,
                            mapOf("playback_session_id" to playbackSessionId, "success" to success.toString(),
                                "error_code" to errorCode.orEmpty()), once = true)
                        if (!success) Toast.makeText(activity, R.string.agent_reply_speech_failed, Toast.LENGTH_SHORT).show()
                        listen(afterPlayback = true)
                    }
                },
                onCancelled = { reason ->
                    if (ownsPlayback()) {
                        VoiceLatencyTelemetry.record(activity, traceId, VoiceTraceEvents.VOICE_REPLY_PLAYBACK_CANCELLED,
                            mapOf("playback_session_id" to playbackSessionId, "error_code" to reason.name), once = true)
                        bargeIn.stop()
                        session.mute(true)
                        panel.setMuted(true)
                        showStatus(R.string.voice_call_muted)
                    }
                }
            )
        )
    }

    fun updateStatus(status: String, detail: String) {
        if (wakeArmed && status == activity.getString(R.string.voice_status_local_wake_failed)) {
            wakeArmed = false
            preferences.edit().putBoolean("foreground_wake", false).apply()
            renderWakeSettings()
            Toast.makeText(activity, R.string.voice_call_wake_unavailable, Toast.LENGTH_LONG).show()
        }
        if (!session.active) return
        if (status == activity.getString(R.string.voice_status_recording) &&
            detail.isNotBlank() && detail != activity.getString(R.string.voice_status_recording_detail)
        ) panel.transcript.text = detail
        if (status == activity.getString(R.string.voice_status_recording_failed) ||
            status == activity.getString(R.string.voice_status_transcription_failed)
        ) {
            stopLevelTick()
            session.mute(true)
            panel.setMuted(true)
            lastStatus = status
            panel.status.text = status
        }
    }

    fun onWakeDetected(): Boolean {
        if (!wakeArmed || !visible()) return false
        start()
        return true
    }

    fun refreshWake() {
        val enabled = preferences.getBoolean("foreground_wake", false)
        if (!enabled || !visible() || session.active ||
            activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            chineseWake.stop()
            if (wakeArmed) activity.releaseWakeWordEngine()
            wakeArmed = false
            return
        }
        if (usesChineseWake()) {
            activity.releaseWakeWordEngine()
            chineseWake.setEnabled(true)
            return
        }
        chineseWake.stop()
        if (wakeArmed) return
        wakeArmed = true
        activity.voiceAssistantAwake = false
        activity.startOpenWakeWordListening(VoiceAssistantSettings.get(activity))
        renderWakeSettings()
    }

    private fun usesChineseWake() = preferences.getString("wake_phrase", "galaxy") == "galaxy"

    fun showSettings() {
        val dialog = Dialog(activity)
        val content = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(activity.dp(24), activity.dp(20), activity.dp(24), activity.dp(24))
            setBackgroundColor(activity.getColor(R.color.surface_bg))
        }
        fun label(text: Int, size: Float = 16f) = TextView(activity).apply {
            setText(text); textSize = size; setTextColor(activity.getColor(R.color.text_primary))
            setPadding(0, activity.dp(12), 0, activity.dp(12))
        }
        content.addView(label(R.string.voice_call_title, 18f))
        wakeToggle = Switch(activity).apply {
            setText(R.string.voice_call_wake)
            isChecked = preferences.getBoolean("foreground_wake", false)
            setPadding(0, activity.dp(12), 0, activity.dp(12))
            setOnCheckedChangeListener { _, enabled ->
                preferences.edit().putBoolean("foreground_wake", enabled).apply()
                if (enabled && activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                    pendingWakePermission = true
                    activity.ensureRecordPermission()
                }
                refreshWake()
                renderWakeSettings()
            }
        }.also(content::addView)
        wakePhraseView = label(R.string.voice_call_wake_word).apply {
            setOnClickListener {
                val options = arrayOf(activity.getString(R.string.voice_call_wake_chinese), activity.getString(R.string.voice_call_wake_hello))
                AlertDialog.Builder(activity).setTitle(R.string.voice_call_wake_word)
                    .setSingleChoiceItems(options, if (usesChineseWake()) 0 else 1) { choice, index ->
                        chineseWake.stop()
                        activity.releaseWakeWordEngine()
                        wakeArmed = false
                        preferences.edit().putString("wake_phrase", if (index == 0) "galaxy" else "hello").apply()
                        choice.dismiss()
                        renderWakeSettings()
                        refreshWake()
                        if (usesChineseWake() && !preferences.getBoolean("foreground_wake", false)) chineseWake.checkSupport()
                    }.show()
            }
        }.also(content::addView)
        wakeDetailView = label(R.string.voice_call_wake_local, 14f).also(content::addView)
        wakeStatusView = label(R.string.voice_call_wake_checking, 14f).also(content::addView)
        wakePrepareView = label(R.string.voice_call_wake_check).apply {
            setTextColor(activity.getColor(R.color.agent_voice_transcript_dot))
            setOnClickListener {
                if (chineseWake.snapshot.availability == LocalWakeAvailability.NEEDS_DOWNLOAD) {
                    chineseWake.requestModelDownload()
                } else {
                    refreshWake()
                    if (chineseWake.snapshot.availability !in setOf(LocalWakeAvailability.CHECKING, LocalWakeAvailability.LISTENING)) {
                        chineseWake.checkSupport()
                    }
                }
            }
        }.also(content::addView)
        content.addView(label(R.string.voice_call_wake_settings).apply {
            setOnClickListener { dialog.dismiss(); activity.showVoiceAssistantSettingsPage() }
        })
        dialog.setContentView(content)
        dialog.setOnDismissListener {
            wakeStatusView = null
            wakePrepareView = null
            wakePhraseView = null
            wakeDetailView = null
            wakeToggle = null
        }
        dialog.window?.apply { setGravity(Gravity.BOTTOM); setLayout(-1, -2) }
        dialog.show()
        dialog.window?.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        renderWakeSettings()
        if (usesChineseWake() && chineseWake.snapshot.availability != LocalWakeAvailability.LISTENING) chineseWake.checkSupport()
    }

    private fun renderWakeSettings() {
        val chinese = usesChineseWake()
        wakePhraseView?.setText(if (chinese) R.string.voice_call_wake_chinese else R.string.voice_call_wake_hello)
        wakeDetailView?.setText(if (chinese) R.string.voice_call_wake_chinese_detail else R.string.voice_call_wake_local)
        val availability = chineseWake.snapshot.availability
        val status = if (!chinese) {
            if (wakeArmed) R.string.voice_call_wake_listening else R.string.voice_call_wake_paused
        } else when (availability) {
            LocalWakeAvailability.UNCHECKED -> R.string.voice_call_wake_unchecked
            LocalWakeAvailability.CHECKING -> R.string.voice_call_wake_checking
            LocalWakeAvailability.NEEDS_DOWNLOAD -> R.string.voice_call_wake_needs_download
            LocalWakeAvailability.DOWNLOAD_PENDING -> R.string.voice_call_wake_download_pending
            LocalWakeAvailability.READY -> R.string.voice_call_wake_ready
            LocalWakeAvailability.LISTENING -> R.string.voice_call_wake_listening
            LocalWakeAvailability.UNAVAILABLE -> R.string.voice_call_wake_chinese_unavailable
            LocalWakeAvailability.FAILED -> R.string.voice_call_wake_failed
        }
        wakeStatusView?.setText(status)
        wakePrepareView?.apply {
            visibility = if (chinese && availability != LocalWakeAvailability.LISTENING) View.VISIBLE else View.GONE
            isEnabled = availability != LocalWakeAvailability.CHECKING
            setText(if (availability == LocalWakeAvailability.NEEDS_DOWNLOAD) R.string.voice_call_wake_download else R.string.voice_call_wake_check)
        }
    }

    private fun render() {
        panel.visibility = if (session.active && session.expanded) View.VISIBLE else View.GONE
        activity.agentComposerRow.visibility = if (session.active && session.expanded) View.GONE else View.VISIBLE
        updateEntry(activity.agentGoalInput.text?.isNotBlank() == true || activity.agentInputAttachments.isNotEmpty())
    }

    private fun showStatus(resource: Int) {
        val text = activity.getString(resource)
        if (lastStatus != text) { lastStatus = text; panel.status.text = text }
    }

    private fun startLevelTick() {
        stopLevelTick()
        val token = session.generation
        levelTick = object : Runnable {
            override fun run() {
                if (!session.isCurrent(token) || session.muted || !visible()) return
                val amplitude = runCatching { activity.currentVoiceAmplitude() }.getOrDefault(0)
                panel.waveform.pushAmplitude(amplitude)
                activity.handler.postDelayed(this, 100)
            }
        }.also { activity.handler.post(it) }
    }

    private fun stopLevelTick() { levelTick?.let(activity.handler::removeCallbacks); levelTick = null; panel.waveform.reset() }
}

internal fun MainActivity.isVoiceAssistantSurfaceVisible(): Boolean =
    (activeMainTab == PAGE_VOICE && wakePage.visibility == View.VISIBLE) ||
        agentVoiceConversation?.canUseAssistant() == true
