package com.signalasi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DownloadManager
import android.app.Dialog
import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.drawable.AnimatedImageDrawable
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaRecorder
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.OpenableColumns
import android.provider.MediaStore
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.text.Editable
import android.text.InputType
import android.text.SpannableString
import android.text.Spanned
import android.text.TextPaint
import android.text.TextUtils
import android.text.TextWatcher
import android.text.style.CharacterStyle
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.UpdateAppearance
import android.util.Base64
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.widget.*
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.zxing.BarcodeFormat
import com.google.zxing.integration.android.IntentIntegrator
import com.google.zxing.qrcode.QRCodeWriter
import com.rementia.openwakeword.lib.WakeWordEngine
import com.rementia.openwakeword.lib.model.DetectionMode
import com.rementia.openwakeword.lib.model.WakeWordModel
import com.signalasi.chat.SignalASIMqttClient.Listener
import com.signalasi.chat.ui.AgentComposerUiPolicy
import com.signalasi.chat.ui.AppleHoldToTalkController
import com.signalasi.chat.ui.VoiceWaveformView
import com.signalasi.chat.voice.TranscriptHypothesis
import com.signalasi.chat.voice.VoiceFailure
import com.signalasi.chat.voice.VoiceFeatureFlags
import com.signalasi.chat.voice.VoiceInteractionCommand
import com.signalasi.chat.voice.VoiceInteractionCoordinator
import com.signalasi.chat.voice.VoiceInteractionCoordinatorRegistry
import com.signalasi.chat.voice.VoiceInteractionEvent
import com.signalasi.chat.voice.VoiceInteractionPhase
import com.signalasi.chat.voice.VoiceRouteDecision
import com.signalasi.chat.voice.VoiceRouteKind
import com.signalasi.chat.voice.VoiceSessionConfig
import com.signalasi.chat.voice.VoiceTtsRequest
import com.signalasi.chat.voice.VoiceTtsRequestRegistry
import com.signalasi.chat.voice.audio.AdaptiveEndpointConfig
import com.signalasi.chat.voice.audio.AndroidPcmRecorder
import com.signalasi.chat.voice.audio.DirectPcmFramePacket
import com.signalasi.chat.voice.audio.EndpointReason
import com.signalasi.chat.voice.audio.PcmCaptureConfig
import com.signalasi.chat.voice.audio.PcmSnapshot
import com.signalasi.chat.voice.audio.PcmStopReason
import com.signalasi.chat.voice.audio.PcmWaveFileAdapter
import com.signalasi.chat.voice.audio.VadDecision
import com.signalasi.chat.voice.audio.VoiceAudioHub
import com.signalasi.chat.voice.audio.VoiceAudioHubListener
import com.signalasi.chat.voice.asr.AsrNetworkType
import com.signalasi.chat.voice.asr.AsrProviderSelector
import com.signalasi.chat.voice.asr.AsrSessionConfig
import com.signalasi.chat.voice.asr.VoiceRecognitionPreference
import com.signalasi.chat.voice.asr.online.CachingRealtimeAsrCredentialSource
import com.signalasi.chat.voice.asr.online.HttpRealtimeAsrCredentialSource
import com.signalasi.chat.voice.asr.online.OnlineAsrCompletion
import com.signalasi.chat.voice.asr.online.OnlineRealtimeAsrTurn
import com.signalasi.chat.voice.asr.online.RealtimeAsrPreconnector
import com.signalasi.chat.voice.asr.online.RealtimeAsrProvider
import com.signalasi.chat.voice.asr.online.RealtimeAsrTurnAction
import com.signalasi.chat.voice.asr.remote.RemoteWhisperNodeClient
import com.signalasi.chat.voice.asr.remote.RemoteWhisperNodeRegistry
import com.signalasi.chat.voice.asr.remote.RemoteWhisperRoutingPolicy
import com.signalasi.chat.voice.asr.remote.SignalASILinkRemoteWhisperTransport
import com.signalasi.chat.voice.asr.local.AbortReason
import com.signalasi.chat.voice.asr.local.AsrConfig as HighAccuracyAsrConfig
import com.signalasi.chat.voice.asr.local.AsrEvent as HighAccuracyAsrEvent
import com.signalasi.chat.voice.asr.local.AsrPerformanceMode
import com.signalasi.chat.voice.asr.local.DefaultWhisperDecodeScheduler
import com.signalasi.chat.voice.asr.local.HighAccuracyAsrResult
import com.signalasi.chat.voice.asr.local.AsrTranscriptCompletenessPolicy
import com.signalasi.chat.voice.asr.local.HighAccuracyLocalAsrController
import com.signalasi.chat.voice.asr.local.HighAccuracyLocalAsrTurn
import com.signalasi.chat.voice.asr.local.LiveWhisperTranscriptionSession
import com.signalasi.chat.voice.asr.local.LiveWhisperTranscriptUpdate
import com.signalasi.chat.voice.asr.local.NativeWhisperCode
import com.signalasi.chat.voice.asr.local.LargeTurboQnnModelAction
import com.signalasi.chat.voice.asr.local.LargeTurboQnnModelManager
import com.signalasi.chat.voice.asr.local.LargeTurboQnnModelStatus
import com.signalasi.chat.voice.asr.local.QnnAsrEligibility
import com.signalasi.chat.voice.asr.local.QnnModelDownloadNetworkPolicy
import com.signalasi.chat.voice.asr.local.QnnWhisperPackageManager
import com.signalasi.chat.voice.asr.local.QnnWhisperPackageStatus
import com.signalasi.chat.voice.asr.local.WhisperDecodeScheduler
import com.signalasi.chat.voice.asr.local.largeTurboQnnModelAction
import com.signalasi.chat.voice.benchmark.WhisperBenchmarkManager
import com.signalasi.chat.voice.benchmark.WhisperBenchmarkDeferredException
import com.signalasi.chat.voice.benchmark.WhisperBenchmarkProgress
import com.signalasi.chat.voice.benchmark.WhisperBenchmarkRecord
import com.signalasi.chat.voice.benchmark.WhisperBenchmarkStage
import com.signalasi.chat.voice.benchmark.WhisperProviderChoice
import com.signalasi.chat.voice.benchmark.WhisperUserVoiceMode
import com.signalasi.chat.voice.correction.AndroidVoiceExecutionRecordStore
import com.signalasi.chat.voice.correction.CorrectionDecision
import com.signalasi.chat.voice.correction.DefaultVoiceCommandRiskClassifier
import com.signalasi.chat.voice.correction.TranscriptDiff
import com.signalasi.chat.voice.correction.VoiceCommandRisk
import com.signalasi.chat.voice.correction.VoiceCorrectionContextRecord
import com.signalasi.chat.voice.correction.VoiceCorrectionJournal
import com.signalasi.chat.voice.correction.VoiceExecutionLedger
import com.signalasi.chat.voice.correction.VoiceEntityType
import com.signalasi.chat.voice.correction.VoiceSecondPassCoordinator
import com.signalasi.chat.voice.correction.VoiceSecondPassRequest
import com.signalasi.chat.voice.correction.VoiceSecondPassResult
import com.signalasi.chat.voice.correction.VoiceSecondPassTriggerPolicy
import com.signalasi.chat.voice.audio.VoiceAudioSession
import com.signalasi.chat.voice.audio.VoiceAudioSessionConfig
import com.signalasi.chat.voice.agent.VoiceAgentEvent
import com.signalasi.chat.voice.agent.VoiceAgentRunBridge
import com.signalasi.chat.voice.agent.VoiceAgentRunListener
import com.signalasi.chat.voice.agent.VoiceAgentRunSnapshot
import com.signalasi.chat.voice.agent.VoiceAgentRunState
import com.signalasi.chat.voice.agent.VoiceAgentRunUpdate
import com.signalasi.chat.voice.metrics.VoiceLatencyTelemetry
import com.signalasi.chat.voice.metrics.VoiceLatencyTraceContext
import com.signalasi.chat.voice.metrics.VoiceTraceEvents
import com.signalasi.chat.voice.model.WhisperExecutionMode
import com.signalasi.chat.voice.model.WhisperCertificationLevel
import com.signalasi.chat.voice.model.WhisperMemoryAdmissionPolicy
import com.signalasi.chat.voice.model.WhisperModelFamily
import com.signalasi.chat.voice.model.WhisperModelFallbackPolicy
import com.signalasi.chat.voice.reliability.AndroidVoiceReliabilityController
import com.signalasi.chat.voice.reliability.VoicePipelineFeature
import com.signalasi.chat.voice.reliability.VoicePerformanceHealth
import com.signalasi.chat.voice.reliability.VoiceResourceMode
import com.signalasi.chat.voice.reliability.VoiceWorkloadProfile
import com.signalasi.chat.voice.modelstream.ModelStreamCancelReason
import com.signalasi.chat.voice.modelstream.CommittedSpeechChunk
import com.signalasi.chat.voice.modelstream.DefaultSentenceCommitter
import com.signalasi.chat.voice.modelstream.ModelStreamEvent
import com.signalasi.chat.voice.modelstream.ModelStreamUiMerger
import com.signalasi.chat.voice.modelstream.ModelStreamUiUpdate
import com.signalasi.chat.voice.modelstream.ModelUsage
import com.signalasi.chat.voice.modelstream.SentenceCommitter
import com.signalasi.chat.voice.tts.BargeInActions
import com.signalasi.chat.voice.tts.BargeInController
import com.signalasi.chat.voice.tts.BargeInTaskKind
import com.signalasi.chat.voice.tts.ProgressiveTtsUtteranceRegistry
import com.signalasi.chat.voice.tts.ProgressiveTtsUtteranceRequest
import com.signalasi.chat.voice.tts.TtsCancelReason
import com.signalasi.chat.voice.tts.TtsChunkPlayback
import com.signalasi.chat.voice.tts.TtsChunkPlaybackCallbacks
import com.signalasi.chat.voice.tts.TtsChunkPlayer
import com.signalasi.chat.voice.tts.TtsChunkScheduler
import com.signalasi.chat.voice.tts.TtsChunkSchedulerCallbacks
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import okhttp3.OkHttpClient
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sin

internal fun MainActivity.showMainTab(
    tab: String,
    preserveNavigationContent: Boolean = false
) {
    AppForegroundTracker.onConversationHidden(this)
    val navigationToken = if (preserveNavigationContent) null else navigationContentGate.begin()
    val previousTab = activeMainTab
    if (tab != PAGE_AGENT && isAgentActionTrayInitialized() && agentActionTrayExpanded) {
        setAgentActionTrayExpanded(false)
    }
    if (tab != PAGE_AGENT && isAgentGoalInputInitialized() && agentComposerTextMode) {
        exitAgentComposerTextMode(hideKeyboard = true)
    }
    if (tab != PAGE_AGENT && agentVoiceListening) {
        stopAgentVoiceInput()
    }
    activeMainTab = tab
    controlCenterDestination = null
    controlCenterBackStack.clear()
    wakePage.visibility = if (tab == PAGE_VOICE) View.VISIBLE else View.GONE
    chatPage.visibility = View.GONE
    featurePage.visibility = View.GONE
    if (tab == PAGE_VOICE && previousTab != PAGE_VOICE) {
        startVoiceAssistant()
    } else if (previousTab == PAGE_VOICE && tab != PAGE_VOICE) {
        stopVoiceAssistant()
    }

    if (tab == PAGE_AGENT || tab == PAGE_MESSAGES || tab == PAGE_DISCOVER || tab == PAGE_SETTINGS) {
        mainPage.visibility = View.VISIBLE
        mainTopBar.visibility = if (tab == PAGE_AGENT) View.GONE else View.VISIBLE
        mainBackButton.visibility = if (tab == PAGE_SETTINGS) View.VISIBLE else View.INVISIBLE
        mainBackButton.setOnClickListener {
            if (activeMainTab == PAGE_SETTINGS) showMainTab(PAGE_AGENT)
        }
        mainActionButton.visibility = View.INVISIBLE
        mainActionButton.text = ""
        mainTitle.text = when (tab) {
            PAGE_AGENT -> getString(R.string.tab_agent)
            PAGE_MESSAGES -> getString(R.string.title_messages)
            PAGE_DISCOVER -> getString(R.string.tab_discover)
            PAGE_SETTINGS -> getString(R.string.settings_control_center_title)
            else -> ""
        }
    } else {
        mainPage.visibility = View.GONE
    }
    agentPage.visibility = if (tab == PAGE_AGENT) View.VISIBLE else View.GONE
    contactPage.visibility = if (tab == PAGE_MESSAGES) View.VISIBLE else View.GONE
    discoverPage.visibility = if (tab == PAGE_DISCOVER) View.VISIBLE else View.GONE
    mePage.visibility = if (tab == PAGE_SETTINGS) View.VISIBLE else View.GONE
    if (tab == PAGE_SETTINGS) {
        val settingsNavigationToken = navigationToken ?: navigationContentGate.begin()
        handler.postDelayed({
            if (activeMainTab == PAGE_SETTINGS &&
                featurePage.visibility != View.VISIBLE &&
                navigationContentGate.isCurrent(settingsNavigationToken)
            ) {
                refreshSettingsControlCenterAsync(settingsNavigationToken)
            }
        }, FAST_NAVIGATION_CONTENT_DELAY_MILLIS)
    }
    if (tab == PAGE_AGENT) refreshGlobalInsightIndicator()
}

internal fun MainActivity.applyAgentBrandLogoTextScale() {
    val sizeDp = (AGENT_BRAND_LOGO_BASE_DP * resources.configuration.fontScale)
        .roundToInt()
        .coerceIn(AGENT_BRAND_LOGO_MIN_DP, AGENT_BRAND_LOGO_MAX_DP)
    agentBrandLogo.layoutParams = agentBrandLogo.layoutParams.apply {
        width = dp(sizeDp)
        height = dp(sizeDp)
    }
}

internal fun MainActivity.configureMessages() {
    messageAdapter = MessageAdapter(currentMessages,
        onPlayVoiceMessage = { msgId -> playVoiceMessage(msgId) },
        onMessageActions = { position -> showMessageActions(position) },
        onOpenAttachment = { attachment -> openPeerAttachment(attachment) })
    messageList.apply {
        layoutManager = LinearLayoutManager(this@configureMessages).apply { stackFromEnd = true }
        adapter = messageAdapter
        addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (dy >= 0) return
                val layout = recyclerView.layoutManager as? LinearLayoutManager ?: return
                if (layout.findFirstVisibleItemPosition() <= CHAT_HISTORY_PREFETCH_POSITION) {
                    selectedContact?.id?.let(::loadOlderChatHistory)
                }
            }
        })
    }
}

internal fun MainActivity.configureInput() {
    sendButton.setOnClickListener {
        exitChatComposerTextMode(hideKeyboard = true)
        sendText()
    }
    sendButton.visibility = View.GONE
    messageInput.setOnEditorActionListener { _, actionId, _ ->
        if (actionId == android.view.inputmethod.EditorInfo.IME_ACTION_SEND) {
            exitChatComposerTextMode(hideKeyboard = true)
            sendText()
            true
        } else false
    }
    messageInput.addTextChangedListener(object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = updateInputActions()
        override fun afterTextChanged(s: Editable?) = Unit
    })
    imageButton.setOnClickListener { setChatActionTrayExpanded(!isChatActionTrayExpanded()) }
    findViewById<View>(R.id.chatActionNewSession).setOnClickListener {
        setChatActionTrayExpanded(false)
        showAgentHomeFromChat()
        createAgentConversation()
    }
    findViewById<View>(R.id.chatActionSessions).setOnClickListener {
        setChatActionTrayExpanded(false)
        showAgentHomeFromChat()
        showAgentSessionsPage()
    }
    findViewById<View>(R.id.chatActionScan).setOnClickListener {
        setChatActionTrayExpanded(false)
        scanMode = "contact"
        startSecurityScan()
    }
    findViewById<View>(R.id.chatActionCamera).setOnClickListener {
        setChatActionTrayExpanded(false)
        openChatCamera()
    }
    findViewById<View>(R.id.chatActionAddFile).setOnClickListener {
        setChatActionTrayExpanded(false)
        openChatAttachmentPicker()
    }
    holdToTalkController = AppleHoldToTalkController(
        activity = this,
        pressTarget = messageInput,
        instruction = chatRecordingInstruction,
        idleContent = chatComposerRow,
        recordingGroup = chatRecordingCenter,
        waveform = chatRecordingWaveform,
        transcript = chatRecordingTranscript,
        timer = chatRecordingTimer,
        hasPermission = {
            checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        },
        requestPermission = {
            requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), REQUEST_RECORD_AUDIO)
        },
        startRecording = { startRecording("chat_message") },
        currentAmplitude = { currentVoiceAmplitude() },
        finishRecording = { send -> stopRecording(send) },
        onTap = { enterChatComposerTextMode() },
        onRecordingStarted = {
            messageInput.clearFocus()
            getSystemService(InputMethodManager::class.java)
                .hideSoftInputFromWindow(messageInput.windowToken, 0)
        },
        stableTranscriptColor = Color.WHITE,
        unstableTranscriptColor = Color.parseColor("#E8FFE9"),
        idleInstructionRes = R.string.agent_voice_recording_hint,
        recordingInstructionRes = R.string.agent_voice_recording_hint,
        holdStartDelayMillis = 280L
    )
    chatRecordingWaveform.useDenseRecordingStyle()
    chatRecordingWaveform.setColors(Color.WHITE, getColorCompat(R.color.apple_voice_cancel))
    messageInput.setOnTouchListener { view, event ->
        if (chatComposerTextMode) false else holdToTalkController.onTouch(view, event)
    }
    installChatComposerKeyboardObserver()
    exitChatComposerTextMode(hideKeyboard = false)
    updateInputActions()
}

internal fun MainActivity.updateInputActions() {
    val hasText = !messageInput.text?.toString()?.trim().isNullOrEmpty()
    val composerState = AgentComposerUiPolicy.resolve(
        hasInput = hasText,
        hasPendingPrimaryAction = false,
        textModeActive = chatComposerTextMode,
        actionTrayRequested = isChatActionTrayExpanded()
    )
    setChatActionTrayRequested(composerState.showActionTray)
    chatPrimaryActionSlot.visibility = if (composerState.showPrimaryActionSlot) View.VISIBLE else View.GONE
    imageButton.visibility = if (composerState.showMoreButton) View.VISIBLE else View.GONE
    sendButton.visibility = if (composerState.showSendButton) View.VISIBLE else View.GONE
    renderChatActionTray(composerState.showActionTray)
    imageButton.renderComposerMoreButton(composerState.showActionTray)
    imageButton.contentDescription = getString(
        if (composerState.showActionTray) R.string.agent_attachment_close_menu
        else R.string.agent_attachment_open_menu
    )
    sendButton.setBackgroundResource(
        if (hasText) R.drawable.agent_send_button_active_background
        else R.drawable.agent_send_button_background
    )
    sendButton.imageTintList = android.content.res.ColorStateList.valueOf(
        if (hasText) Color.parseColor("#087F69") else Color.WHITE
    )
}

internal fun MainActivity.enterChatComposerTextMode() {
    if (chatComposerTextMode) return
    setChatActionTrayRequested(false)
    chatComposerTextMode = true
    chatComposerKeyboardObserved = false
    chatComposerRow.clearFocus()
    messageInput.requestFocus()
    messageInput.setSelection(messageInput.text?.length ?: 0)
    updateInputActions()
    messageInput.post {
        getSystemService(InputMethodManager::class.java)
            .showSoftInput(messageInput, InputMethodManager.SHOW_IMPLICIT)
    }
}

internal fun MainActivity.setChatActionTrayExpanded(expanded: Boolean) {
    if (expanded) {
        exitChatComposerTextMode(hideKeyboard = true)
    }
    setChatActionTrayRequested(expanded)
    updateInputActions()
}

internal fun MainActivity.exitChatComposerTextMode(hideKeyboard: Boolean) {
    chatComposerTextMode = false
    chatComposerKeyboardObserved = false
    if (hideKeyboard) {
        getSystemService(InputMethodManager::class.java)
            .hideSoftInputFromWindow(messageInput.windowToken, 0)
    }
    messageInput.clearFocus()
    chatComposerRow.isFocusableInTouchMode = true
    chatComposerRow.requestFocus()
    updateInputActions()
}

internal fun MainActivity.installChatComposerKeyboardObserver() {
    val root = findViewById<View>(android.R.id.content)
    root.viewTreeObserver.addOnGlobalLayoutListener {
        if (!chatComposerTextMode) return@addOnGlobalLayoutListener
        val visibleFrame = Rect()
        root.getWindowVisibleDisplayFrame(visibleFrame)
        val rootHeight = root.rootView.height.coerceAtLeast(1)
        val keyboardVisible = rootHeight - visibleFrame.bottom > rootHeight * 0.15f
        if (keyboardVisible) {
            chatComposerKeyboardObserved = true
        } else if (chatComposerKeyboardObserved) {
            chatComposerKeyboardClosedAt = SystemClock.elapsedRealtime()
            exitChatComposerTextMode(hideKeyboard = false)
        }
    }
}

internal fun MainActivity.ensureRecordPermission(): Boolean {
    return if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
        true
    } else {
        requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), REQUEST_RECORD_AUDIO)
        false
    }
}

internal fun MainActivity.sendText() {
    val content = messageInput.text?.toString()?.trim().orEmpty()
    if (content.isEmpty()) return
    val contact = selectedContact ?: return
    messageInput.text?.clear()
    sendOutgoingText(contact, content)
}

internal fun MainActivity.sendOutgoingText(contact: Contact, content: String, voiceTraceId: String = "") {
    selectedContact = contact
    val msg = ChatMessage(
        newMessageId(),
        content,
        true,
        CONTACT_ME,
        deliveryStatus = getString(R.string.delivery_status_sending),
        deliveryTrace = mutableListOf(newTraceEvent("created", "user_send"))
    )
    addMessage(msg)
    voiceCoordinatorSession(voiceTraceId).takeIf(String::isNotBlank)?.let { sessionId ->
        voiceCoordinatorIdsBySourceMessage[msg.id] = sessionId
    }
    val raw = AppStore.contactById(this, contact.id)
    if (raw?.optString("delivery_mode") == "cloud_api") {
        selectVoiceCoordinatorRoute(voiceTraceId, VoiceRouteKind.CLOUD_MODEL, contact.id)
        VoiceLatencyTelemetry.record(
            this,
            voiceTraceId,
            VoiceTraceEvents.ROUTE_STARTED,
            once = true
        )
        VoiceLatencyTelemetry.record(
            this,
            voiceTraceId,
            VoiceTraceEvents.ROUTE_SELECTED,
            mapOf(
                "model_provider" to raw.optString("cloud_provider", raw.optString("cloud_api_style", "cloud")),
                "execution_mode" to "cloud_api"
            ),
            once = true
        )
        updateMessageStatus(msg.id, contact.id, getString(R.string.delivery_status_requesting))
        appendDeliveryTrace(msg.id, contact.id, "cloud_request", raw.optString("cloud_provider"))
        val selectedModel = AppStore.selectedCloudModelContact(this, contact.id) ?: raw
        val contextTurns = (messages[contact.id] ?: currentMessages)
            .filterNot { it.isSystem }
            .map { it.copy() }
        requestCloudModelReply(contact, selectedModel, contextTurns, msg.id, voiceTraceId)
        return
    }
    val target = AppStore.outgoingTopicForContact(this, contact.id)
    if (target != null) {
        val peerChat = AppStore.isDesktopDeviceContact(this, contact.id) ||
            AppStore.isPersonContact(this, contact.id)
        if (!peerChat) selectVoiceCoordinatorRoute(voiceTraceId, VoiceRouteKind.REMOTE_AGENT, contact.id)
        appendDeliveryTrace(msg.id, contact.id, "queued", target)
        val deliveryTrace = deliveryTraceJson(msg.deliveryTrace)
        outboundMessageExecutor.execute {
            val publishResult = runCatching {
                if (peerChat) {
                    SignalASIMqttClient.publishPeerMessageResult(
                        content = content,
                        contactId = contact.id,
                        topicOverride = target,
                        clientMessageId = msg.id,
                        deliveryTrace = deliveryTrace
                    )
                } else {
                    SignalASIMqttClient.publishUserMessageResult(
                        content,
                        contact.id,
                        topicOverride = target,
                        clientMessageId = msg.id,
                        deliveryTrace = deliveryTrace,
                        traceId = voiceTraceId
                    )
                }
            }.onFailure {
                Log.e("SignalASILink", "Message publish failed", it)
            }.getOrDefault(MqttPublishResult.FAILED)
            runOnUiThread {
                when (publishResult) {
                    MqttPublishResult.PUBLISHED -> {
                        appendDeliveryTrace(msg.id, contact.id, "mqtt_published", target)
                        updateMessageStatus(msg.id, contact.id, getString(R.string.delivery_status_sent))
                        markDeliveredSoon(msg, contact.id)
                    }
                    MqttPublishResult.QUEUED -> {
                        updateMessageStatus(msg.id, contact.id, getString(R.string.delivery_status_queued))
                    }
                    MqttPublishResult.FAILED -> {
                        appendDeliveryTrace(msg.id, contact.id, "publish_failed", target)
                        updateMessageStatus(msg.id, contact.id, getString(R.string.delivery_status_failed))
                        failVoiceCoordinator(voiceTraceId, "publish_failed")
                        voiceCoordinatorIdsBySourceMessage.remove(msg.id)
                    }
                }
            }
        }
    } else {
        appendDeliveryTrace(msg.id, contact.id, "link_unavailable", "No paired SignalASI Link v1 relationship")
        updateMessageStatus(msg.id, contact.id, getString(R.string.delivery_status_failed))
        failVoiceCoordinator(voiceTraceId, "trusted_route_unavailable")
        voiceCoordinatorIdsBySourceMessage.remove(msg.id)
    }
}

internal fun MainActivity.requestCloudModelReply(
    contact: Contact,
    raw: JSONObject,
    contextTurns: List<ChatMessage>,
    outgoingId: Long,
    voiceTraceId: String = ""
) {
    if (!VoiceFeatureFlags.isCloudModelStreamingEnabled(this)) {
        requestCloudModelReplyLegacy(contact, raw, contextTurns, outgoingId, voiceTraceId)
        return
    }
    cancelActiveCloudStream(contact.id, ModelStreamCancelReason.NEW_REQUEST)
    val requestId = "cloud-${contact.id}-${outgoingId}-${UUID.randomUUID()}"
    val progressiveSpeechEnabled = shouldUseProgressiveCloudSpeech(voiceTraceId)
    val sentenceCommitter = if (progressiveSpeechEnabled) {
        DefaultSentenceCommitter().apply { reset(requestId) }
    } else {
        null
    }
    val state = ActiveCloudStream(
        requestId = requestId,
        contact = contact,
        outgoingId = outgoingId,
        incomingId = newMessageId(),
        voiceTraceId = voiceTraceId,
        selectedModel = raw.optString("selected_cloud_model", raw.optString("cloud_model")),
        sentenceCommitter = sentenceCommitter,
        progressiveSpeechEnabled = progressiveSpeechEnabled
    )
    if (progressiveSpeechEnabled) beginProgressiveCloudSpeech(state)
    VoiceLatencyTelemetry.record(
        this,
        voiceTraceId,
        VoiceTraceEvents.MODEL_REQUEST_STARTED,
        mapOf(
            "model_provider" to raw.optString("cloud_provider", raw.optString("cloud_api_style", "cloud")),
            "execution_mode" to "streaming"
        ),
        once = true
    )
    val job = voiceAssistantScope.launch(start = CoroutineStart.LAZY) {
        CloudConversationStreamEngine.streamConversation(
            context = this@requestCloudModelReply,
            contact = raw,
            turns = contextTurns,
            requestId = requestId,
            onToolEvent = { event -> postCloudToolEvent(contact, event) }
        ).collect { event -> consumeCloudStreamEvent(state, event, raw) }
    }
    activeCloudStreams[contact.id] = state
    activeCloudStreamJobs[contact.id] = job
    job.invokeOnCompletion { error ->
        handler.post {
            activeCloudStreamJobs.remove(contact.id, job)
            if (activeCloudStreams[contact.id] === state && !state.finalized && error != null) {
                finishCloudStreamFailure(
                    state,
                    com.signalasi.chat.voice.modelstream.ModelStreamError(
                        code = if (error is CancellationException) "CANCELLED" else "STREAM_FAILED",
                        message = error.message.orEmpty().ifBlank { getString(R.string.cloud_unknown_error) },
                        partialResponse = state.merger.snapshot().isNotBlank()
                    )
                )
            }
        }
    }
    job.start()
}

internal fun MainActivity.requestCloudModelReplyLegacy(
    contact: Contact,
    raw: JSONObject,
    contextTurns: List<ChatMessage>,
    outgoingId: Long,
    voiceTraceId: String
) {
    cloudExecutor.execute {
        val result = runCatching {
            VoiceLatencyTraceContext.withTrace(voiceTraceId) {
                CloudModelClient.send(this@requestCloudModelReplyLegacy, raw, contextTurns) { event ->
                    runOnUiThread {
                        val detail = event.detail
                            .replace(Regex("[\\r\\n]+"), " ")
                            .take(120)
                        val text = if (event.stage == "running") {
                            getString(R.string.cloud_tool_running, event.tool, detail)
                        } else {
                            getString(R.string.cloud_tool_completed, event.tool, detail)
                        }
                        addMessage(ChatMessage(
                            newMessageId(),
                            text,
                            false,
                            contact,
                            isSystem = true,
                            deliveryTrace = mutableListOf(newTraceEvent("cloud_tool_${event.stage}", event.tool))
                        ))
                    }
                }
            }
        }
        runOnUiThread {
            if (result.isSuccess) {
                voiceCoordinatorSession(voiceTraceId).takeIf(String::isNotBlank)?.let { sessionId ->
                    dispatchVoiceCoordinator(
                        VoiceInteractionEvent.ModelDelta(sessionId, result.getOrThrow())
                    )
                }
                appendDeliveryTrace(outgoingId, contact.id, "cloud_reply", raw.optString("selected_cloud_model"))
                updateMessageStatus(outgoingId, contact.id, getString(R.string.delivery_status_replied))
                val reply = ChatMessage(
                    newMessageId(),
                    result.getOrThrow(),
                    false,
                    contact,
                    deliveryTrace = mutableListOf(newTraceEvent("cloud_reply_received", raw.optString("selected_cloud_model")))
                )
                addMessage(reply, fromIncoming = true)
                maybeSpeakIncomingReply(reply, voiceTraceId)
            } else {
                failVoiceCoordinator(
                    voiceTraceId,
                    result.exceptionOrNull()?.javaClass?.simpleName ?: "cloud_model_failed"
                )
                appendDeliveryTrace(outgoingId, contact.id, "cloud_error", result.exceptionOrNull()?.message?.take(120).orEmpty())
                updateMessageStatus(outgoingId, contact.id, getString(R.string.delivery_status_failed))
                addMessage(ChatMessage(
                    newMessageId(),
                    getString(R.string.cloud_request_failed, result.exceptionOrNull()?.message?.take(220) ?: getString(R.string.cloud_unknown_error)),
                    false,
                    contact,
                    deliveryTrace = mutableListOf(newTraceEvent("cloud_error", result.exceptionOrNull()?.message?.take(120).orEmpty()))
                ), fromIncoming = true)
                VoiceLatencyTelemetry.record(
                    this@requestCloudModelReplyLegacy,
                    voiceTraceId,
                    VoiceTraceEvents.SESSION_FAILED,
                    mapOf("error_code" to result.exceptionOrNull()?.javaClass?.simpleName.orEmpty()),
                    once = true
                )
            }
            voiceCoordinatorIdsBySourceMessage.remove(outgoingId)
        }
    }
}

internal fun MainActivity.postCloudToolEvent(contact: Contact, event: CloudToolEvent) {
    handler.post {
        if (isDestroyed) return@post
        val detail = event.detail.replace(Regex("[\\r\\n]+"), " ").take(120)
        val text = if (event.stage == "running") {
            getString(R.string.cloud_tool_running, event.tool, detail)
        } else {
            getString(R.string.cloud_tool_completed, event.tool, detail)
        }
        addMessage(
            ChatMessage(
                newMessageId(),
                text,
                false,
                contact,
                isSystem = true,
                deliveryTrace = mutableListOf(newTraceEvent("cloud_tool_${event.stage}", event.tool))
            )
        )
    }
}

internal fun MainActivity.consumeCloudStreamEvent(
    state: ActiveCloudStream,
    event: ModelStreamEvent,
    raw: JSONObject
) {
    when (event) {
        is ModelStreamEvent.Connected -> VoiceLatencyTelemetry.record(
            this,
            state.voiceTraceId,
            VoiceTraceEvents.MODEL_CONNECTED,
            mapOf("http_status" to event.httpStatus.toString()),
            once = true
        )
        is ModelStreamEvent.TextDelta -> {
            VoiceLatencyTelemetry.record(
                this,
                state.voiceTraceId,
                VoiceTraceEvents.MODEL_FIRST_DELTA,
                once = true
            )
            val update = state.merger.offer(event.sequence, event.text, event.receivedAtElapsedMs)
            val speechChunks = state.sentenceCommitter?.acceptDelta(event.sequence, event.text).orEmpty()
            handler.post {
                if (activeCloudStreams[state.contact.id] !== state || state.finalized) return@post
                voiceCoordinatorSession(state.voiceTraceId).takeIf(String::isNotBlank)?.let { sessionId ->
                    dispatchVoiceCoordinator(VoiceInteractionEvent.ModelDelta(sessionId, event.text))
                }
                if (speechChunks.isNotEmpty()) {
                    enqueueProgressiveSpeech(state, speechChunks)
                } else {
                    scheduleSentenceCommit(state)
                }
                update?.let { applyCloudStreamUiUpdate(state, it) }
                scheduleCloudStreamFlush(state)
            }
        }
        is ModelStreamEvent.Completed -> handler.post {
            if (activeCloudStreams[state.contact.id] === state && !state.finalized) {
                finishCloudStreamSuccess(state, raw)
            }
        }
        is ModelStreamEvent.Failed -> handler.post {
            if (activeCloudStreams[state.contact.id] === state && !state.finalized) {
                finishCloudStreamFailure(state, event.error)
            }
        }
        is ModelStreamEvent.ToolCallDelta -> Unit
        is ModelStreamEvent.Usage -> state.usage = event.usage
    }
}

internal fun MainActivity.scheduleCloudStreamFlush(state: ActiveCloudStream) {
    state.flushRunnable?.let(handler::removeCallbacks)
    val task = Runnable {
        if (activeCloudStreams[state.contact.id] !== state || state.finalized) return@Runnable
        state.merger.flush(cloudStreamClockMs())?.let { applyCloudStreamUiUpdate(state, it) }
    }
    state.flushRunnable = task
    handler.postDelayed(task, CLOUD_STREAM_UI_INTERVAL_MS)
}

internal fun MainActivity.scheduleSentenceCommit(state: ActiveCloudStream) {
    if (!state.progressiveSpeechEnabled || state.sentenceCommitter == null || state.sentenceCommitRunnable != null) {
        return
    }
    val task = Runnable {
        state.sentenceCommitRunnable = null
        if (activeCloudStreams[state.contact.id] !== state || state.finalized) return@Runnable
        val chunks = state.sentenceCommitter.commitDue()
        if (chunks.isNotEmpty()) enqueueProgressiveSpeech(state, chunks)
    }
    state.sentenceCommitRunnable = task
    handler.postDelayed(task, 525L)
}

internal fun MainActivity.applyCloudStreamUiUpdate(state: ActiveCloudStream, update: ModelStreamUiUpdate) {
    if (update.text.isBlank()) return
    val list = messages.getOrPut(state.contact.id) { mutableListOf() }
    val index = list.indexOfFirst { it.id == state.incomingId }
    if (index < 0) {
        val visible = chatPage.visibility == View.VISIBLE && selectedContact?.id == state.contact.id
        val message = ChatMessage(
            id = state.incomingId,
            content = update.text,
            isMine = false,
            contact = state.contact,
            deliveryStatus = getString(R.string.cloud_streaming_status),
            deliveryTrace = mutableListOf(newTraceEvent("cloud_streaming", state.selectedModel))
        )
        list.add(message)
        val summary = summaries.getOrPut(state.contact.id) { ContactSummary() }
        summary.lastMessage = update.text
        summary.lastAt = message.timestamp
        if (!visible) summary.unreadCount += 1
        refreshContactList()
    } else {
        val previous = list[index]
        list[index] = previous.copy(content = update.text).also {
            it.deliveryStatus = previous.deliveryStatus
        }
    }
    refreshVisibleMessages(state.contact.id)
}

internal fun MainActivity.finishCloudStreamSuccess(state: ActiveCloudStream, raw: JSONObject) {
    state.flushRunnable?.let(handler::removeCallbacks)
    state.flushRunnable = null
    state.sentenceCommitRunnable?.let(handler::removeCallbacks)
    state.sentenceCommitRunnable = null
    val update = state.merger.flush(cloudStreamClockMs(), complete = true)
    update?.let { applyCloudStreamUiUpdate(state, it) }
    val finalText = state.merger.snapshot().trim()
    if (finalText.isBlank()) {
        finishCloudStreamFailure(
            state,
            com.signalasi.chat.voice.modelstream.ModelStreamError(
                code = "EMPTY_RESPONSE",
                message = getString(R.string.cloud_empty_response)
            )
        )
        return
    }
    state.finalized = true
    activeCloudStreams.remove(state.contact.id, state)
    activeCloudStreamJobs.remove(state.contact.id)
    appendDeliveryTrace(state.outgoingId, state.contact.id, "cloud_reply", state.selectedModel)
    updateMessageStatus(state.outgoingId, state.contact.id, getString(R.string.delivery_status_replied))
    val reply = persistCloudStreamMessage(state, finalText, status = null, terminalStage = "cloud_reply_received")
    if (state.progressiveSpeechEnabled) {
        enqueueProgressiveSpeech(state, state.sentenceCommitter?.flush().orEmpty())
        progressiveTtsScheduler.finish(state.requestId)
    } else {
        maybeSpeakIncomingReply(reply, state.voiceTraceId)
    }
    voiceCoordinatorIdsBySourceMessage.remove(state.outgoingId)
    val usage = state.usage
    VoiceLatencyTelemetry.record(
        this,
        state.voiceTraceId,
        VoiceTraceEvents.MODEL_REQUEST_COMPLETED,
        buildMap {
            put("model", raw.optString("selected_cloud_model", raw.optString("cloud_model")))
            usage?.let {
                put("input_tokens", it.inputTokens.toString())
                put("output_tokens", it.outputTokens.toString())
                put("cached_input_tokens", it.cachedInputTokens.toString())
            }
        },
        once = true
    )
    VoiceLatencyTelemetry.record(
        this,
        state.voiceTraceId,
        VoiceTraceEvents.SESSION_COMPLETED,
        mapOf("model" to raw.optString("selected_cloud_model", raw.optString("cloud_model"))),
        once = true
    )
}

internal fun MainActivity.finishCloudStreamFailure(
    state: ActiveCloudStream,
    error: com.signalasi.chat.voice.modelstream.ModelStreamError
) {
    if (state.finalized) return
    state.finalized = true
    state.flushRunnable?.let(handler::removeCallbacks)
    state.flushRunnable = null
    state.sentenceCommitRunnable?.let(handler::removeCallbacks)
    state.sentenceCommitRunnable = null
    activeCloudStreams.remove(state.contact.id, state)
    activeCloudStreamJobs.remove(state.contact.id)
    val partialText = state.merger.snapshot().trim()
    appendDeliveryTrace(state.outgoingId, state.contact.id, "cloud_error", error.code)
    updateMessageStatus(state.outgoingId, state.contact.id, getString(R.string.delivery_status_failed))
    if (partialText.isNotBlank()) {
        persistCloudStreamMessage(
            state,
            partialText,
            status = getString(R.string.cloud_stream_interrupted_status),
            terminalStage = "cloud_stream_interrupted"
        )
        if (error.code != "CANCELLED") {
            addMessage(
                ChatMessage(
                    newMessageId(),
                    getString(R.string.cloud_stream_interrupted_notice),
                    false,
                    state.contact,
                    isSystem = true
                ),
                fromIncoming = true
            )
        }
        if (state.progressiveSpeechEnabled && error.code != "CANCELLED") {
            enqueueProgressiveSpeech(state, state.sentenceCommitter?.flush().orEmpty())
            progressiveTtsScheduler.finish(state.requestId)
        }
    } else if (error.code != "CANCELLED") {
        addMessage(
            ChatMessage(
                newMessageId(),
                getString(R.string.cloud_request_failed, error.message.take(220)),
                false,
                state.contact,
                deliveryTrace = mutableListOf(newTraceEvent("cloud_error", error.code))
            ),
            fromIncoming = true
        )
        if (state.progressiveSpeechEnabled) {
            progressiveTtsScheduler.cancel(state.requestId, TtsCancelReason.PLAYBACK_FAILED)
            resumeVoiceAssistantListening(state.voiceTraceId)
        }
    }
    if (state.progressiveSpeechEnabled && error.code == "CANCELLED") {
        progressiveTtsScheduler.cancel(state.requestId, TtsCancelReason.SESSION_CHANGED)
    }
    failVoiceCoordinator(state.voiceTraceId, error.code)
    voiceCoordinatorIdsBySourceMessage.remove(state.outgoingId)
    VoiceLatencyTelemetry.record(
        this,
        state.voiceTraceId,
        VoiceTraceEvents.SESSION_FAILED,
        mapOf("error_code" to error.code),
        once = true
    )
}

internal fun MainActivity.persistCloudStreamMessage(
    state: ActiveCloudStream,
    text: String,
    status: String?,
    terminalStage: String
): ChatMessage {
    val list = messages.getOrPut(state.contact.id) { mutableListOf() }
    var index = list.indexOfFirst { it.id == state.incomingId }
    if (index < 0) {
        applyCloudStreamUiUpdate(state, ModelStreamUiUpdate(text, firstDelta = true, complete = true))
        index = list.indexOfFirst { it.id == state.incomingId }
    }
    val current = list[index]
    current.deliveryTrace.removeAll { it.stage == "cloud_streaming" }
    current.deliveryTrace.add(newTraceEvent(terminalStage, state.selectedModel))
    val persisted = current.copy(content = text).also { it.deliveryStatus = status }
    list[index] = persisted
    persisted.deliveryTrace.add(newTraceEvent("persisted", "local_history"))
    saveChatHistory(persisted)
    val summary = summaries.getOrPut(state.contact.id) { ContactSummary() }
    summary.lastMessage = text
    summary.lastAt = persisted.timestamp
    GlobalConversationEventBus.publishChatMessage(
        this,
        state.contact.id,
        state.contact.name,
        persisted.id,
        text,
        GlobalConversationActor.ASSISTANT,
        persisted.timestamp,
        mapOf("direction" to "incoming", "stream_request_id" to state.requestId)
    )
    refreshVisibleMessages(state.contact.id)
    refreshContactList()
    return persisted
}

internal fun MainActivity.cancelActiveCloudStream(contactId: String, reason: ModelStreamCancelReason) {
    val state = activeCloudStreams.remove(contactId) ?: return
    state.flushRunnable?.let(handler::removeCallbacks)
    state.flushRunnable = null
    state.sentenceCommitRunnable?.let(handler::removeCallbacks)
    state.sentenceCommitRunnable = null
    state.finalized = true
    if (state.progressiveSpeechEnabled) {
        progressiveTtsScheduler.cancel(
            state.requestId,
            when (reason) {
                ModelStreamCancelReason.VOICE_BARGE_IN -> TtsCancelReason.VOICE_BARGE_IN
                ModelStreamCancelReason.NEW_REQUEST -> TtsCancelReason.NEW_RESPONSE
                ModelStreamCancelReason.APP_DESTROYED -> TtsCancelReason.APP_DESTROYED
                else -> TtsCancelReason.SESSION_CHANGED
            }
        )
    }
    val partial = state.merger.snapshot().trim()
    if (partial.isNotBlank()) {
        persistCloudStreamMessage(
            state,
            partial,
            status = getString(R.string.cloud_stream_cancelled_status),
            terminalStage = "cloud_stream_cancelled"
        )
    }
    val job = activeCloudStreamJobs.remove(contactId)
    voiceAssistantScope.launch { CloudConversationStreamEngine.cancel(state.requestId, reason) }
    job?.cancel(CancellationException(reason.name))
    failVoiceCoordinator(state.voiceTraceId, reason.name)
    voiceCoordinatorIdsBySourceMessage.remove(state.outgoingId)
}

internal fun MainActivity.cloudStreamClockMs(): Long = System.nanoTime() / 1_000_000L

internal fun MainActivity.handleDebugSendIntent(intent: Intent?) {
    if ((applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) == 0) return
    val agentGoalEncoded = intent?.getStringExtra("signalasi_debug_agent_goal_b64")?.trim().orEmpty()
    if (agentGoalEncoded.isNotBlank()) {
        val token = intent?.getStringExtra("signalasi_debug_agent_token")?.trim().orEmpty()
            .ifBlank { UUID.randomUUID().toString() }
        val newConversation = intent?.getBooleanExtra("signalasi_debug_agent_new_conversation", true) != false
        val attachmentName = intent?.getStringExtra("signalasi_debug_agent_attachment_name")?.trim().orEmpty()
        val attachmentEncoded = intent?.getStringExtra("signalasi_debug_agent_attachment_b64")?.trim().orEmpty()
        intent?.removeExtra("signalasi_debug_agent_goal_b64")
        intent?.removeExtra("signalasi_debug_agent_token")
        intent?.removeExtra("signalasi_debug_agent_new_conversation")
        intent?.removeExtra("signalasi_debug_agent_attachment_name")
        intent?.removeExtra("signalasi_debug_agent_attachment_b64")
        val goal = runCatching {
            String(Base64.decode(agentGoalEncoded, Base64.DEFAULT), Charsets.UTF_8)
        }.getOrDefault("").trim()
        val attachment = if (attachmentName.isNotBlank() && attachmentEncoded.length <= 1_500_000) {
            runCatching {
                DebugAgentAttachment(
                    name = attachmentName.take(120),
                    bytes = Base64.decode(attachmentEncoded, Base64.DEFAULT)
                )
            }.getOrNull()?.takeIf { it.bytes.size <= 1_048_576 }
        } else {
            null
        }
        if (goal.isNotBlank()) scheduleDebugAgentGoal(token, goal, newConversation, attachment)
    }
    val contactId = intent?.getStringExtra("signalasi_debug_contact")?.trim().orEmpty()
    val content = intent?.getStringExtra("signalasi_debug_text")?.trim().orEmpty()
    if (contactId.isBlank() || content.isBlank()) return
    intent?.removeExtra("signalasi_debug_contact")
    intent?.removeExtra("signalasi_debug_text")
    scheduleDebugOutgoing(contactId, content, attempt = 0)
}

internal fun MainActivity.handleDebugIncomingIntent(intent: Intent?) {
    if ((applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) == 0) return
    val revoke = intent?.getBooleanExtra("signalasi_debug_revoke", false) == true
    val status = intent?.getBooleanExtra("signalasi_debug_status", false) == true
    val pairing = intent?.getBooleanExtra("signalasi_debug_pairing", false) == true
    val openAgents = intent?.getBooleanExtra("signalasi_debug_open_agents", false) == true
    val openSecurity = intent?.getBooleanExtra("signalasi_debug_open_security", false) == true
    val openVoice = intent?.getBooleanExtra("signalasi_debug_open_voice", false) == true
    val openVoiceSettings = intent?.getBooleanExtra("signalasi_debug_open_voice_settings", false) == true
    val openLanguageSettings = intent?.getBooleanExtra("signalasi_debug_open_language_settings", false) == true
    val openOnDeviceAgent = intent?.getBooleanExtra("signalasi_debug_open_on_device_agent", false) == true
    val openBackupExport = intent?.getBooleanExtra("signalasi_debug_open_backup_export", false) == true
    val openBackupImport = intent?.getBooleanExtra("signalasi_debug_open_backup_import", false) == true
    val openDestroyData = intent?.getBooleanExtra("signalasi_debug_open_destroy_data", false) == true
    val destroyAllData = intent?.getBooleanExtra("signalasi_debug_destroy_all_data", false) == true
    val openProtocolQuality = intent?.getBooleanExtra("signalasi_debug_open_protocol_quality", false) == true
    val openSignalLinkProtocol = intent?.getBooleanExtra("signalasi_debug_open_signal_link_protocol", false) == true
    val openAdvancedOptions = intent?.getBooleanExtra("signalasi_debug_open_advanced_options", false) == true
    val openRecentTasks = intent?.getBooleanExtra("signalasi_debug_open_recent_tasks", false) == true
    val openMessages = intent?.getBooleanExtra("signalasi_debug_open_messages", false) == true
    val openContacts = intent?.getBooleanExtra("signalasi_debug_open_contacts", false) == true
    val openContactId = intent?.getStringExtra("signalasi_debug_open_contact")?.trim().orEmpty()
    val openContactDetailId = intent?.getStringExtra("signalasi_debug_open_contact_detail")?.trim().orEmpty()
    val openNewFriends = intent?.getBooleanExtra("signalasi_debug_open_new_friends", false) == true
    val openGroup = intent?.getBooleanExtra("signalasi_debug_open_group", false) == true
    val openCreateGroup = intent?.getBooleanExtra("signalasi_debug_open_create_group", false) == true
    val openDevice = intent?.getBooleanExtra("signalasi_debug_open_device", false) == true
    val openAutomation = intent?.getBooleanExtra("signalasi_debug_open_automation", false) == true
    val openLocalModel = intent?.getBooleanExtra("signalasi_debug_open_local_model", false) == true
    val openCloudProviders = intent?.getBooleanExtra("signalasi_debug_open_cloud_providers", false) == true
    val openCloudProvider = intent?.getStringExtra("signalasi_debug_open_cloud_provider")?.trim().orEmpty()
    val seedCloudProvider = intent?.getStringExtra("signalasi_debug_seed_cloud_provider")?.trim().orEmpty()
    val openCloudSwitchProvider = intent?.getStringExtra("signalasi_debug_open_cloud_switch_provider")?.trim().orEmpty()
    val approveFriendId = intent?.getStringExtra("signalasi_debug_approve_friend")?.trim().orEmpty()
    val deleteContactId = intent?.getStringExtra("signalasi_debug_delete_contact")?.trim().orEmpty()
    val renameContactId = intent?.getStringExtra("signalasi_debug_rename_contact")?.trim().orEmpty()
    val renameContactNameB64 = intent?.getStringExtra("signalasi_debug_rename_name_b64")?.trim().orEmpty()
    val renameContactName = if (renameContactNameB64.isNotBlank()) {
        runCatching {
            String(Base64.decode(renameContactNameB64, Base64.NO_WRAP), Charsets.UTF_8).trim()
        }.getOrDefault("")
    } else {
        intent?.getStringExtra("signalasi_debug_rename_name")?.trim().orEmpty()
    }
    val backupRoundtripToken = intent?.getStringExtra("signalasi_debug_backup_roundtrip")?.trim().orEmpty()
    val cloudModelsRoundtripToken = intent?.getStringExtra("signalasi_debug_cloud_models_roundtrip")?.trim().orEmpty()
    val chatHistoryProbeEncoded = intent?.getStringExtra("signalasi_debug_chat_history_probe_b64")?.trim().orEmpty()
    val secureStateProbeEncoded = intent?.getStringExtra("signalasi_debug_secure_state_probe_b64")?.trim().orEmpty()
    val voiceSettingsRoundtripToken = intent?.getStringExtra("signalasi_debug_voice_settings_roundtrip")?.trim().orEmpty()
    val controlCenterRoundtripToken = intent?.getStringExtra("signalasi_debug_control_center_roundtrip")?.trim().orEmpty()
    val controlCenterThemeToken = intent?.getStringExtra("signalasi_debug_control_center_theme")?.trim().orEmpty()
    val homeAssistantTestUrl = intent?.getStringExtra("signalasi_debug_home_assistant_url")?.trim().orEmpty()
    val controlCenterPage = intent?.getStringExtra("signalasi_debug_control_center_page")?.trim().orEmpty()
    val scanPayload = intent?.getStringExtra("signalasi_debug_scan_payload")?.trim().orEmpty()
    val scanPayloadB64 = intent?.getStringExtra("signalasi_debug_scan_payload_b64")?.trim().orEmpty()
    val autoConfirmScan = intent?.getBooleanExtra("signalasi_debug_auto_confirm_scan", false) == true
    val incomingPayload = intent?.getStringExtra("signalasi_debug_incoming")?.trim().orEmpty()
    val incomingPayloadB64 = intent?.getStringExtra("signalasi_debug_incoming_b64")?.trim().orEmpty()
    DebugIntentExtras.consume { key -> intent?.removeExtra(key) }
    if (controlCenterThemeToken.isNotBlank()) {
        val isNight = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES
        getSharedPreferences("signalasi_debug", Context.MODE_PRIVATE).edit()
            .putString(
                "control_center_theme_result",
                JSONObject()
                    .put("token", controlCenterThemeToken)
                    .put("night", isNight)
                    .put("page_bg", getColorCompat(R.color.page_bg).toLong() and 0xffffffffL)
                    .toString()
            )
            .commit()
        showMainTab(PAGE_SETTINGS)
        return
    }
    if (controlCenterPage.isNotBlank()) {
        showMainTab(PAGE_SETTINGS)
        if (!controlCenterPage.equals("home", ignoreCase = true)) {
            ControlCenterRoute.fromWireValue(controlCenterPage)?.let {
                openControlCenterDestination(ControlCenterDestination(it))
            }
        }
        return
    }
    if (homeAssistantTestUrl.isNotBlank()) {
        HomeAssistantSettingsStore.save(
            this,
            HomeAssistantSettings(
                enabled = true,
                baseUrl = homeAssistantTestUrl,
                accessToken = "signalasi-control-center-test",
                defaultEntityId = "light.qa_lamp"
            )
        )
        showMainTab(PAGE_SETTINGS)
        openControlCenterDestination(ControlCenterDestination(ControlCenterRoute.SMART_SPACES))
        return
    }
    if (approveFriendId.isNotBlank()) {
        AppStore.approveFriendRequestForSignalasiId(this, approveFriendId)
        refreshContactList()
        refreshDirectoryContacts()
        return
    }
    if (deleteContactId.isNotBlank()) {
        AppStore.deleteContact(this, deleteContactId, deleteMessages = false)
        refreshContactList()
        refreshDirectoryContacts()
        return
    }
    if (renameContactId.isNotBlank() && renameContactName.isNotBlank()) {
        AppStore.renameContact(this, renameContactId, renameContactName)
        refreshContactList()
        refreshDirectoryContacts()
        if (openContactDetailId.isNotBlank()) {
            showContactDetail(contactById(openContactDetailId))
        }
        return
    }
    if (scanPayloadB64.isNotBlank()) {
        val decoded = runCatching {
            String(Base64.decode(scanPayloadB64, Base64.NO_WRAP), Charsets.UTF_8)
        }.getOrDefault("")
        handleSecurityScan(decoded, autoConfirmScan)
        return
    }
    if (scanPayload.isNotBlank()) {
        handleSecurityScan(scanPayload, autoConfirmScan)
        return
    }
    if (backupRoundtripToken.isNotBlank()) {
        runDebugBackupRoundtrip(backupRoundtripToken)
        return
    }
    if (cloudModelsRoundtripToken.isNotBlank()) {
        runDebugCloudModelsRoundtrip(cloudModelsRoundtripToken)
        return
    }
    if (chatHistoryProbeEncoded.isNotBlank()) {
        runDebugChatHistoryProbe(chatHistoryProbeEncoded)
        return
    }
    if (secureStateProbeEncoded.isNotBlank()) {
        runDebugSecureStateProbe(secureStateProbeEncoded)
        return
    }
    if (voiceSettingsRoundtripToken.isNotBlank()) {
        runDebugVoiceSettingsRoundtrip(voiceSettingsRoundtripToken)
        return
    }
    if (controlCenterRoundtripToken.isNotBlank()) {
        runDebugControlCenterRoundtrip(controlCenterRoundtripToken)
        return
    }
    if (destroyAllData) {
        AppStore.destroyAllPrivateData(this)
        CloudConversationContextStore.clear(this)
        messages.clear()
        summaries.clear()
        currentMessages.clear()
        loadChatHistory()
        refreshContactList()
        refreshDirectoryContacts()
        showMainTab(PAGE_MESSAGES)
        return
    }
    if (pairing) {
        SignalASICrypto.debugSetVerifiedPcFingerprint(this, "DEBUG_PC_FINGERPRINT_FOR_UI_TEST_000000000000000000000000")
        AppStore.markHermesVerified(this)
        refreshContactList()
        refreshDirectoryContacts()
    }
    val payload = if (revoke) {
        """{"type":"pairing_revoked","content":"desktop_revoked"}"""
    } else if (status) {
        """{"type":"connector_status","content":"debug connector status","connector_agents":[{"id":"codex","name":"Codex Agent","status":"ready","detail":"debug ready","setup":"Ready for live use","kind":"local-cli"},{"id":"claude","name":"Claude Code","status":"needs_setup","detail":"debug missing claude","setup":"Install Claude Code CLI","kind":"local-cli"},{"id":"local-llm","name":"Local LLM","status":"needs_setup","detail":"debug missing local model","setup":"Start Ollama or configure LM Studio","kind":"local-model"},{"id":"custom-agent","name":"Custom Agent","status":"needs_setup","detail":"debug missing custom command","setup":"Set a CLI or MCP wrapper command","kind":"custom-cli"},{"id":"research-agent","name":"Research Agent","status":"ready","detail":"debug dynamic connector","setup":"Ready for live use","kind":"custom-cli"}]}"""
    } else {
        if (incomingPayloadB64.isNotBlank()) {
            String(Base64.decode(incomingPayloadB64, Base64.DEFAULT), Charsets.UTF_8).trim()
        } else {
            incomingPayload
        }
    }
    if (payload.isBlank()) {
        val seededCloudContact = if (seedCloudProvider.isNotBlank() || openCloudSwitchProvider.isNotBlank()) {
            debugSeedCloudProvider(seedCloudProvider.ifBlank { openCloudSwitchProvider })
        } else {
            null
        }
        if (openMessages) {
            reloadChatHistoryIfChanged(force = true)
            showMainTab(PAGE_MESSAGES)
        }
        if (openContacts) {
            reloadChatHistoryIfChanged(force = true)
            showConversationHub(ConversationHubTab.CONTACTS)
        }
        if (openVoice) {
            showMainTab(PAGE_VOICE)
        }
        if (openContactId.isNotBlank()) {
            reloadChatHistoryIfChanged(force = true)
            showChatPage(contactById(openContactId))
        }
        if (openContactDetailId.isNotBlank()) {
            showContactDetail(contactById(openContactDetailId))
        }
        if (openNewFriends) {
            showFriendRequestsDialog()
        }
        if (openGroup) {
            showGroupFeaturePage()
        }
        if (openCreateGroup) {
            showCreateGroupFeaturePage()
        }
        if (openDevice) {
            showDeviceFeaturePage()
        }
        if (openAutomation) {
            showAutomationFeaturePage()
        }
        if (openLocalModel) {
            showLocalModelFeaturePage()
        }
        if (openCloudProviders) {
            showCloudProviderPage()
        }
        if (openCloudProvider.isNotBlank()) {
            showCloudModelPage(openCloudProvider)
        }
        if (openCloudSwitchProvider.isNotBlank() && seededCloudContact != null) {
            showCloudModelSwitchPage(seededCloudContact)
        } else if (seedCloudProvider.isNotBlank() && seededCloudContact != null) {
            showChatPage(seededCloudContact)
        }
        if (openAgents) {
            showAgentFeaturePage()
        }
        if (openSecurity) {
            showSecurityFeaturePage()
        }
        if (openVoiceSettings) {
            showVoiceAssistantSettingsPage()
        }
        if (openLanguageSettings) {
            showLanguageSettingsPage()
        }
        if (openOnDeviceAgent) {
            showOnDeviceAgentFeaturePage()
        }
        if (openBackupExport) {
            showExportBackupDialog()
        }
        if (openBackupImport) {
            showBackupImportPasswordPreview()
        }
        if (openDestroyData) {
            confirmDestroyAllData()
        }
        if (openProtocolQuality) {
            showProtocolQualityFeaturePage()
        }
        if (openSignalLinkProtocol) {
            showSignalLinkProtocolPage()
        }
        if (openAdvancedOptions) {
            showAdvancedOptionsFeaturePage()
        }
        if (openRecentTasks) {
            showAgentRecentTasksPage()
        }
        return
    }
    Log.i("SignalASIDebug", "Processing debug incoming payload")
    if (openVoice) {
        showMainTab(PAGE_VOICE)
    }
    onMessage(payload)
    if (openContacts) {
        reloadChatHistoryIfChanged(force = true)
        showConversationHub(ConversationHubTab.CONTACTS)
    }
    if (openContactId.isNotBlank()) {
        reloadChatHistoryIfChanged(force = true)
        showChatPage(contactById(openContactId))
    }
    if (openContactDetailId.isNotBlank()) {
        showContactDetail(contactById(openContactDetailId))
    }
    if (openNewFriends) {
        showFriendRequestsDialog()
    }
    if (openGroup) {
        showGroupFeaturePage()
    }
    if (openCreateGroup) {
        showCreateGroupFeaturePage()
    }
    if (openDevice) {
        showDeviceFeaturePage()
    }
    if (openAutomation) {
        showAutomationFeaturePage()
    }
    if (openLocalModel) {
        showLocalModelFeaturePage()
    }
    if (openCloudProviders) {
        showCloudProviderPage()
    }
    if (openCloudProvider.isNotBlank()) {
        showCloudModelPage(openCloudProvider)
    }
    if (openAgents) {
        showAgentFeaturePage()
    }
    if (openSecurity) {
        showSecurityFeaturePage()
    }
    if (openVoiceSettings) {
        showVoiceAssistantSettingsPage()
    }
    if (openLanguageSettings) {
        showLanguageSettingsPage()
    }
    if (openOnDeviceAgent) {
        showOnDeviceAgentFeaturePage()
    }
    if (openBackupExport) {
        showExportBackupDialog()
    }
    if (openBackupImport) {
        showBackupImportPasswordPreview()
    }
    if (openDestroyData) {
        confirmDestroyAllData()
    }
    if (openProtocolQuality) {
        showProtocolQualityFeaturePage()
    }
    if (openSignalLinkProtocol) {
        showSignalLinkProtocolPage()
    }
    if (openAdvancedOptions) {
        showAdvancedOptionsFeaturePage()
    }
    Toast.makeText(this, getString(R.string.debug_incoming_processed), Toast.LENGTH_SHORT).show()
}
