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

internal fun MainActivity.displayContactName(contact: Contact): String = when (contact.id) {
    CONTACT_SYSTEM.id -> getString(R.string.chat_system_notice)
    CONTACT_ME.id -> AppStore.profile(this).optString("name")
        .ifBlank { SignalASIDeviceIdentityName.current(this) }
    else -> contact.name
}

internal fun MainActivity.showChatPage(contact: Contact) {
    selectedContact = contact
    val raw = AppStore.contactById(this, contact.id)
    val isCloud = raw?.optString("delivery_mode") == "cloud_api"
    chatTitle.text = displayContactName(contact)
    chatModelTag.visibility = if (isCloud) View.VISIBLE else View.GONE
    statusDot.visibility = if (isCloud) View.GONE else View.VISIBLE
    chatSubtitle.visibility = if (isCloud) View.GONE else View.VISIBLE
    chatSubtitle.text = when {
        contact.id == CONTACT_SYSTEM.id -> getString(R.string.chat_system_notice)
        else -> getString(R.string.chat_link_encrypted)
    }
    chatModelButton.visibility = if (isCloud) View.VISIBLE else View.GONE
    chatModelButton.background = getDrawable(R.drawable.model_selector_background)
    chatModelLabel.text = if (isCloud) selectedCloudModelLabel(contact.id) else ""
    chatModelButton.setOnClickListener {
        if (isCloud) showCloudModelSwitchPage(contact)
    }
    bindContactAvatar(chatAvatar, contact)
    exitChatComposerTextMode(hideKeyboard = true)
    summaries.getOrPut(contact.id) { ContactSummary() }.unreadCount = 0
    markContactRead(contact.id)
    messageAdapter = MessageAdapter(currentMessages,
        onPlayVoiceMessage = { msgId -> playVoiceMessage(msgId) },
        onMessageActions = { position -> showMessageActionsPage(position) },
        onOpenAttachment = { attachment -> openPeerAttachment(attachment) })
    messageList.adapter = messageAdapter
    val notificationsOnly = contact.id == CONTACT_SYSTEM.id
    chatInputBar.visibility = if (notificationsOnly) View.GONE else View.VISIBLE
    wakePage.visibility = View.GONE
    mainPage.visibility = View.GONE
    featurePage.visibility = View.GONE
    chatPage.visibility = View.VISIBLE
    loadLatestChatHistory(
        contactId = contact.id,
        force = !loadedHistoryContacts.contains(contact.id),
        scrollAfterLoad = true
    )
    refreshContactList()
}

internal fun MainActivity.scrollToBottom() {
    val lastIndex = (messageList.adapter?.itemCount ?: currentMessages.size) - 1
    if (lastIndex >= 0) {
        (messageList.layoutManager as? LinearLayoutManager)
            ?.scrollToPositionWithOffset(lastIndex, 0)
            ?: messageList.scrollToPosition(lastIndex)
    }
}

internal fun MainActivity.showContactPage() {
    returnFromContactChatToConversationHub()
}

internal fun MainActivity.returnFromContactChatToConversationHub() {
    chatPage.visibility = View.GONE
    wakePage.visibility = View.GONE
    mainPage.visibility = View.VISIBLE
    showMainTab(PAGE_AGENT)
    handler.post { showConversationHub(ConversationHubTab.CONVERSATIONS) }
}

internal fun MainActivity.configureContacts() {
    val items = buildDirectoryContacts()
    directoryContacts.clear()
    directoryContacts.addAll(items)
    directoryAdapter = ContactAdapter(directoryContacts, summaries, { contact ->
        showContactDetail(contact)
    }, { contact ->
        confirmDeleteContact(contact)
    }, showSummary = false)
    findViewById<RecyclerView>(R.id.directoryList).apply {
        layoutManager = LinearLayoutManager(this@configureContacts)
        adapter = directoryAdapter
    }

    val chatItems = buildChatContacts()
    ensureDesignSummaries()
    contactAdapter = ContactAdapter(chatItems, summaries, { contact ->
        showChatPage(contact)
    }, { contact ->
        confirmDeleteChat(contact)
    }, showSummary = true)
    findViewById<RecyclerView>(R.id.contactList).apply {
        layoutManager = LinearLayoutManager(this@configureContacts)
        adapter = contactAdapter
    }
}

internal fun MainActivity.configureMainTabs() {
    mainTitle.setOnClickListener {
        if (activeMainTab == PAGE_MESSAGES && mainPage.visibility == View.VISIBLE) {
            showMainTab(PAGE_VOICE)
        }
    }
    findViewById<View>(R.id.settingsMessagesButton).setOnClickListener { showMainTab(PAGE_MESSAGES) }
    findViewById<View>(R.id.settingsContactsButton).setOnClickListener { showMainTab(PAGE_CONTACTS) }
    findViewById<View>(R.id.settingsDiscoverButton).setOnClickListener { showMainTab(PAGE_DISCOVER) }
    findViewById<View>(R.id.settingsAgentMemoryButton).setOnClickListener { showAgentMemoryPage() }
    findViewById<View>(R.id.settingsAgentKnowledgeButton).setOnClickListener { showAgentKnowledgePage() }
    findViewById<View>(R.id.settingsAgentControlButton).setOnClickListener { showOnDeviceAgentFeaturePage() }
    findViewById<View>(R.id.settingsRecentTasksButton).setOnClickListener { showAgentRecentTasksPage() }
    meProfileText.setOnClickListener { showEditNicknameDialog() }
    findViewById<View>(R.id.meProfileCard).setOnClickListener { showEditNicknameDialog() }
    meAvatar.setOnClickListener { pickAvatar() }
    mainActionButton.setOnClickListener {
        showAddContactMenu()
    }
    findViewById<View>(R.id.newFriendsButton).setOnClickListener { showFriendRequestsDialog() }
    findViewById<View>(R.id.groupChatsButton).setOnClickListener { showGroupFeaturePage() }
    findViewById<View>(R.id.myAgentsButton).setOnClickListener { showAgentFeaturePage() }
    findViewById<View>(R.id.myDevicesButton).setOnClickListener { showDeviceFeaturePage() }
    findViewById<View>(R.id.aiAgentButton).setOnClickListener { showAgentFeaturePage() }
    findViewById<View>(R.id.deviceCenterButton).setOnClickListener { showDeviceFeaturePage() }
    findViewById<View>(R.id.automationButton).setOnClickListener { showAutomationFeaturePage() }
    findViewById<View>(R.id.securityCenterButton).setOnClickListener { showSecurityFeaturePage() }
    findViewById<View>(R.id.labButton).setOnClickListener { showLocalModelFeaturePage() }
    findViewById<TextView>(R.id.scanButton).setOnClickListener {
        scanMode = "contact"
        startSecurityScan()
    }
    findViewById<TextView>(R.id.myQrButton).setOnClickListener { showMyQrPayload() }
    findViewById<TextView>(R.id.createGroupButton).setOnClickListener { showCreateGroupFeaturePage() }
    findViewById<View>(R.id.exportBackupButton).setOnClickListener { showExportBackupDialog() }
    findViewById<View>(R.id.importBackupButton).setOnClickListener { openBackupImportPicker() }
    findViewById<View>(R.id.languageSettingsButton).setOnClickListener { showLanguageSettingsPage() }
    findViewById<View>(R.id.protocolQualityButton).setOnClickListener { showProtocolQualityFeaturePage() }
    findViewById<View>(R.id.advancedOptionsButton).setOnClickListener { showAdvancedOptionsFeaturePage() }
    findViewById<View>(R.id.localModelSettingsButton).setOnClickListener { showLocalModelFeaturePage() }
    findViewById<View>(R.id.voiceAssistantSettingsButton).setOnClickListener { showVoiceAssistantSettingsPage() }
    findViewById<View>(R.id.onDeviceAgentButton).setOnClickListener { showOnDeviceAgentFeaturePage() }
    findViewById<View>(R.id.destroyDataButton).setOnClickListener { confirmDestroyAllData() }
    findViewById<View>(R.id.aboutSignalASIButton).setOnClickListener { showAboutSignalASIPage() }
    backButton.setOnClickListener { showContactPage() }
    setFeatureBackAction()
}

internal fun MainActivity.configureAgentPage() {
    agentOutputLayout = LinearLayoutManager(this)
    agentTranscriptAdapter = AgentTranscriptRecyclerAdapter(this)
    var olderPageRequestedForGesture = false
    agentOutputList.apply {
        layoutManager = agentOutputLayout
        adapter = agentTranscriptAdapter
        itemAnimator = null
        setItemViewCacheSize(4)
        recycledViewPool.setMaxRecycledViews(0, 8)
        addOnItemTouchListener(object : RecyclerView.SimpleOnItemTouchListener() {
            private var downY = 0f

            override fun onInterceptTouchEvent(
                recyclerView: RecyclerView,
                event: MotionEvent
            ): Boolean {
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        downY = event.y
                        olderPageRequestedForGesture = false
                    }
                    MotionEvent.ACTION_MOVE -> {
                        if (
                            !olderPageRequestedForGesture &&
                            AgentTranscriptScrollPolicy.shouldLoadOlderFromPull(
                                downY = downY,
                                currentY = event.y,
                                canScrollUp = recyclerView.canScrollVertically(-1),
                                hydrationPending = initialAgentHydrationPending,
                                thresholdPx = dp(12)
                            )
                        ) {
                            olderPageRequestedForGesture = true
                            loadOlderAgentTranscriptEntries()
                        }
                    }
                }
                return false
            }
        })
        addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                when (newState) {
                    RecyclerView.SCROLL_STATE_DRAGGING -> agentTranscriptUserScrollActive = true
                    RecyclerView.SCROLL_STATE_IDLE -> agentTranscriptUserScrollActive = false
                }
            }

            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                val itemCount = agentTranscriptAdapter.itemCount
                val lastPosition = agentOutputLayout.findLastVisibleItemPosition()
                val lastView = agentOutputLayout.findViewByPosition(lastPosition)
                val remaining = if (lastPosition == itemCount - 1 && lastView != null) {
                    lastView.bottom - (recyclerView.height - recyclerView.paddingBottom)
                } else {
                    Int.MAX_VALUE
                }
                agentTranscriptAutoFollow = AgentTranscriptScrollPolicy.nextAutoFollow(
                    current = agentTranscriptAutoFollow,
                    userScrollActive = agentTranscriptUserScrollActive,
                    itemCount = itemCount,
                    lastVisiblePosition = lastPosition,
                    remainingPx = remaining,
                    thresholdPx = dp(56)
                )
                if (AgentTranscriptScrollPolicy.shouldLoadOlderFromScroll(
                        dy = dy,
                        firstVisiblePosition = agentOutputLayout.findFirstVisibleItemPosition(),
                        hydrationPending = initialAgentHydrationPending
                    ) && !olderPageRequestedForGesture
                ) {
                    olderPageRequestedForGesture = true
                    loadOlderAgentTranscriptEntries()
                }
            }
        })
    }
    findViewById<View>(R.id.agentSessionTitleTap).setOnClickListener { showAgentSessionsPage() }
    findViewById<View>(R.id.agentModelSelectionTap).setOnClickListener { showAgentModelSelectionPage() }
    agentSettingsButton.setOnClickListener { showMainTab(PAGE_SETTINGS) }
    agentInsightBar.setOnClickListener { showGlobalInsightsDialog() }
    agentMemoryCaptureButton.setOnClickListener {
        val next = !mobileNativeAgent.safetySettings().memoryCapture
        renderAgentState(mobileNativeAgent.updateMemoryCapture(next))
    }
    agentMemoryText.setOnClickListener { showAgentMemoryPage() }
    agentKnowledgeText.setOnClickListener { showAgentKnowledgePage() }
    agentAttachButton.setOnClickListener { showAgentAttachmentMenu() }
    findViewById<View>(R.id.agentActionNewSession).setOnClickListener {
        setAgentActionTrayExpanded(false)
        createAgentConversation()
    }
    findViewById<View>(R.id.agentActionSessions).setOnClickListener {
        setAgentActionTrayExpanded(false)
        showAgentSessionsPage()
    }
    findViewById<View>(R.id.agentActionScan).setOnClickListener {
        setAgentActionTrayExpanded(false)
        scanMode = "contact"
        startSecurityScan()
    }
    findViewById<View>(R.id.agentActionCamera).setOnClickListener {
        setAgentActionTrayExpanded(false)
        openAgentCamera()
    }
    findViewById<View>(R.id.agentActionAddFile).setOnClickListener {
        setAgentActionTrayExpanded(false)
        openAgentAttachmentPicker(imagesOnly = false)
    }
    agentSubmitButton.setOnClickListener {
        Log.d("SignalASIAgent", "Agent submit clicked")
        exitAgentComposerTextMode(hideKeyboard = true)
        handleAgentPrimaryAction()
    }
    agentGoalInput.setOnEditorActionListener { _, _, _ ->
        exitAgentComposerTextMode(hideKeyboard = true)
        submitAgentGoal()
        true
    }
    agentGoalInput.addTextChangedListener(object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            updateAgentSubmitButtonAppearance(s?.isNotBlank() == true || agentInputAttachments.isNotEmpty())
        }
        override fun afterTextChanged(s: Editable?) = Unit
    })
    agentGoalInput.setOnFocusChangeListener { _, hasFocus ->
        if (hasFocus) setAgentActionTrayExpanded(false)
    }
    updateAgentSubmitButtonAppearance(agentGoalInput.text?.isNotBlank() == true || agentInputAttachments.isNotEmpty())
    agentScreenSearchInput.addTextChangedListener(object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            latestAgentScreenContext?.let { renderAgentScreenDetails(it) }
        }
        override fun afterTextChanged(s: Editable?) = Unit
    })
    agentHoldToTalkController = AppleHoldToTalkController(
        activity = this,
        pressTarget = agentGoalInput,
        instruction = agentRecordingInstruction,
        idleContent = agentComposerRow,
        recordingGroup = agentRecordingCenter,
        waveform = agentRecordingWaveform,
        transcript = agentRecordingTranscript,
        timer = agentRecordingTimer,
        hasPermission = {
            checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        },
        requestPermission = {
            requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), REQUEST_RECORD_AUDIO)
        },
        startRecording = { startRecording("agent_input") },
        currentAmplitude = { currentVoiceAmplitude() },
        finishRecording = { send -> stopAgentInputRecording(send) },
        onTap = { enterAgentComposerTextMode() },
        onRecordingStarted = {
            setAgentActionTrayExpanded(false)
            agentGoalInput.clearFocus()
            getSystemService(InputMethodManager::class.java)
                .hideSoftInputFromWindow(agentGoalInput.windowToken, 0)
        },
        stableTranscriptColor = Color.WHITE,
        unstableTranscriptColor = Color.parseColor("#E8FFE9"),
        idleInstructionRes = R.string.agent_voice_recording_hint,
        recordingInstructionRes = R.string.agent_voice_recording_hint,
        holdStartDelayMillis = 280L
    )
    agentRecordingWaveform.useDenseRecordingStyle()
    agentRecordingWaveform.setColors(Color.WHITE, getColorCompat(R.color.apple_voice_cancel))
    agentGoalInput.setOnTouchListener { view, event ->
        if (agentComposerTextMode) false else agentHoldToTalkController.onTouch(view, event)
    }
    installAgentComposerKeyboardObserver()
    exitAgentComposerTextMode(hideKeyboard = false)
    if (VoiceFeatureFlags.isAgentVoiceRunBridgeEnabled(this)) {
        restoreVoiceAgentRunCards()
    }
}

internal fun MainActivity.loadOlderAgentTranscriptEntries() {
    if (agentTranscriptPageLoading || agentTranscriptAllLoaded || agentRenderedConversationId.isBlank()) return
    agentTranscriptPageLoading = true
    val conversationId = agentRenderedConversationId
    val beforeSequence = agentTranscriptWindow.nextBeforeSequence
    if (beforeSequence == null) {
        agentTranscriptAllLoaded = true
        agentTranscriptPageLoading = false
        return
    }
    thread(name = "signalasi-agent-transcript-page") {
        val pageResult = runCatching {
            agentTranscriptStore.page(
                conversationId = conversationId,
                beforeSequenceExclusive = beforeSequence,
                pageSize = AGENT_TRANSCRIPT_PAGE_ITEMS
            )
        }
        runOnUiThread {
            if (conversationId != agentRenderedConversationId) {
                agentTranscriptPageLoading = false
                return@runOnUiThread
            }
            val page = pageResult.getOrElse {
                agentTranscriptPageLoading = false
                return@runOnUiThread
            }
            val added = agentTranscriptWindow.prependOlder(conversationId, page)
            agentTranscriptAllLoaded = !page.hasMore
            if (added > 0) {
                renderAgentTranscript(agentTranscriptWindow.entries)
            }
            agentTranscriptPageLoading = false
        }
    }
}

internal fun MainActivity.clearAgentTranscriptRows() {
    if (isAgentTranscriptAdapterInitialized()) agentTranscriptAdapter.clear()
    renderedAgentTranscriptIds.clear()
    renderedAgentTranscriptSignatures.clear()
    renderedAgentTranscriptSourceEntries = emptyList()
}

internal fun MainActivity.resetAgentTranscriptRendering(conversationId: String = "") {
    clearAgentTranscriptRows()
    expandedAgentTranscriptEntries.clear()
    expandedAgentTranscriptText.clear()
    agentTranscriptExpansionInFlight.clear()
    agentResponseSectionExpansion.clear()
    agentTranscriptPageLoading = false
    agentTranscriptAllLoaded = false
    agentRenderedConversationId = conversationId
    agentTranscriptWindow.reset(conversationId)
}

internal fun MainActivity.deleteAgentTranscriptByDedupeKey(
    conversationId: String,
    dedupeKey: String
): Boolean {
    val removed = agentTranscriptStore.deleteByDedupeKey(conversationId, dedupeKey)
    if (removed) {
        val removeVisibleEntry = {
            if (agentTranscriptWindow.conversationId == conversationId) {
                agentTranscriptWindow.entries
                    .filter { it.dedupeKey == dedupeKey }
                    .map(AgentTranscriptEntry::id)
                    .forEach(agentTranscriptWindow::remove)
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            removeVisibleEntry()
        } else {
            handler.post(removeVisibleEntry)
        }
    }
    return removed
}

internal fun MainActivity.requestAgentTranscriptWindowRefresh(conversationId: String) {
    val cleanConversationId = conversationId.trim()
    if (cleanConversationId.isBlank()) return
    if (Looper.myLooper() != Looper.getMainLooper()) {
        handler.post { requestAgentTranscriptWindowRefresh(cleanConversationId) }
        return
    }
    if (isFinishing || isDestroyed || agentRenderedConversationId != cleanConversationId) return
    agentTranscriptRefreshConversationId = cleanConversationId
    agentTranscriptRefreshPageSize = maxOf(
        INITIAL_VISIBLE_AGENT_TRANSCRIPT_ITEMS,
        agentTranscriptWindow.entries.size
    )
    agentTranscriptRefreshRequested = true
    startNextAgentTranscriptWindowRefresh()
}

private fun MainActivity.startNextAgentTranscriptWindowRefresh() {
    if (agentTranscriptRefreshInProgress || !agentTranscriptRefreshRequested) return
    val conversationId = agentTranscriptRefreshConversationId
    val pageSize = agentTranscriptRefreshPageSize
    agentTranscriptRefreshRequested = false
    agentTranscriptRefreshInProgress = true
    agentTranscriptContentExecutor.execute {
        val startedAt = SystemClock.elapsedRealtime()
        val pageResult = runCatching {
            agentTranscriptStore.page(
                conversationId = conversationId,
                pageSize = pageSize
            )
        }
        handler.post {
            pageResult.onSuccess { page ->
                if (!isFinishing && !isDestroyed && agentRenderedConversationId == conversationId) {
                    agentTranscriptWindow.replace(conversationId, page)
                    agentTranscriptAllLoaded = !page.hasMore
                    renderAgentTranscript(agentTranscriptWindow.entries)
                }
            }.onFailure { error ->
                Log.w(
                    "SignalASIAgent",
                    "Background transcript refresh failed conversation=${conversationId.take(8)}",
                    error
                )
            }
            val elapsed = SystemClock.elapsedRealtime() - startedAt
            if (elapsed >= AGENT_TRANSCRIPT_PERF_LOG_THRESHOLD_MS) {
                Log.d(
                    "SignalASIPerf",
                    "transcript_refresh_async conversation=${conversationId.take(8)} " +
                        "page_size=$pageSize elapsed_ms=$elapsed"
                )
            }
            agentTranscriptRefreshInProgress = false
            startNextAgentTranscriptWindowRefresh()
        }
    }
}

internal fun MainActivity.refreshAgentTranscriptWindow(
    conversationId: String = agentTranscriptStore.activeConversation().id
) {
    requestAgentTranscriptWindowRefresh(conversationId)
}

internal fun MainActivity.publishRemoteAgentTaskCancellation(state: AgentUiState): Boolean? {
    val result = state.lastActionResult
    val taskId = result?.metadata?.get("remote_task_id").orEmpty()
    val contactId = result?.metadata?.get("contact_id").orEmpty()
    val sourceMessageId = result?.metadata?.get("source_message_id")?.toLongOrNull() ?: 0L
    val conversationId = result?.metadata?.get("conversation_id").orEmpty()
    val turnId = result?.metadata?.get("turn_id").orEmpty()
    if (taskId.isBlank() || contactId.isBlank() || sourceMessageId <= 0L ||
        conversationId.isBlank() || turnId.isBlank()
    ) {
        return null
    }
    val sent = SignalASIMqttClient.publishAgentTaskCancel(
        taskId = taskId,
        contactId = contactId,
        sourceMessageId = sourceMessageId,
        conversationId = conversationId,
        turnId = turnId,
        topicOverride = AppStore.outgoingTopicForContact(this, contactId)
    )
    if (sent) {
        completedConnectorTaskIds.add(taskId)
        supersededConnectorSourceIds.add(sourceMessageId)
        activeAgentTasks.remove(sourceMessageId)
    }
    return sent
}

internal fun MainActivity.startAgentScreenUnderstanding() {
    if (AgentScreenCaptureService.requestCapture(this)) {
        Toast.makeText(this, getString(R.string.agent_screen_capture_running), Toast.LENGTH_SHORT).show()
        return
    }
    val manager = getSystemService(android.media.projection.MediaProjectionManager::class.java)
    startActivityForResult(manager.createScreenCaptureIntent(), REQUEST_AGENT_SCREEN_CAPTURE)
}

internal fun MainActivity.handleAgentPrimaryAction() {
    if (!agentGoalInput.text?.toString()?.trim().isNullOrBlank() || agentInputAttachments.isNotEmpty()) {
        submitAgentGoal()
        return
    }
    val state = mobileNativeAgent.snapshot()
    if (state.phase == AgentPhase.PAUSED) {
        renderAgentState(mobileNativeAgent.resumeCurrentTask())
    } else if (state.phase == AgentPhase.WAITING_RESPONSE) {
        Toast.makeText(this, getString(R.string.agent_empty_goal), Toast.LENGTH_SHORT).show()
    } else if (state.pendingAction != null) {
        runAgentOperationAsync { mobileNativeAgent.approveNextAction(highRiskConfirmed = true) }
    } else {
        submitAgentGoal()
    }
}

internal fun MainActivity.runAgentOperationAsync(
    onComplete: (AgentUiState) -> Unit = {},
    operation: () -> AgentUiState
) {
    if (agentOperationInFlight) return
    agentOperationInFlight = true
    thread(name = "signalasi-agent-operation") {
        val runtime = mobileNativeAgent
        val turnId = agentRuntimeTurnIds[runtime].orEmpty()
        if (turnId.isNotBlank()) bindAgentExecutionLoop(runtime, turnId)
        val outcome = runCatching {
            var state = operation()
            if (turnId.isNotBlank()) {
                state = finalizeAgentExecutionLoop(runtime, turnId, state)
                persistAgentWorkspaceSnapshot(turnId, state, runtime)
            }
            state
        }
        runOnUiThread {
            agentOperationInFlight = false
            val state = outcome.getOrElse { runtime.snapshot() }
            renderAgentState(state)
            onComplete(state)
            consumePendingAgentConnectorResponses()
            outcome.exceptionOrNull()?.let { error ->
                Toast.makeText(this@runAgentOperationAsync, error.message ?: "Agent operation failed", Toast.LENGTH_LONG).show()
            }
        }
    }
}

internal fun MainActivity.agentTimelineRuntime(entry: AgentTranscriptEntry): MobileNativeAgent? {
    val candidates = buildList {
        addAll(activeAgentTasks.values)
        addAll(provisionalAgentTasks)
        add(mobileNativeAgent)
    }.distinct()
    val linkedTurnId = entry.turnId.ifBlank { entry.taskId }
    if (linkedTurnId.isNotBlank()) {
        candidates.firstOrNull { runtime ->
            agentRuntimeTurnIds[runtime] == linkedTurnId
        }?.let { return it }
    }
    return null
}

internal fun MainActivity.rememberAgentExecutionPresentation(
    taskId: String,
    presentation: AgentExecutionPresentation
) {
    if (taskId.isBlank()) return
    agentExecutionPresentations[taskId] = presentation
    if (agentExecutionPresentations.size <= 512) return
    agentExecutionPresentations.entries
        .asSequence()
        .filter { !it.value.cancellable }
        .sortedBy { entry ->
            entry.value.completedAtMillis.takeIf { it > 0L }
                ?: entry.value.startedAtMillis
        }
        .take(agentExecutionPresentations.size - 384)
        .forEach { agentExecutionPresentations.remove(it.key, it.value) }
}

internal fun MainActivity.agentExecutionPresentation(
    entry: AgentTranscriptEntry,
    processEntries: List<AgentTranscriptEntry>,
    startedAtMillis: Long,
    completedAtMillis: Long?
): AgentExecutionPresentation {
    agentExecutionPresentations[entry.taskId]?.let { remote ->
        return remote.copy(
            completedAtMillis = completedAtMillis ?: remote.completedAtMillis,
            cancellable = remote.cancellable && completedAtMillis == null
        )
    }
    val state = lastRenderedAgentState?.takeIf { rendered ->
        rendered.sessionId == entry.taskId || rendered.sessionId == entry.turnId
    }
    val route = state?.plan?.route
    val orphanResolution = AgentTimelineOrphanPolicy.resolve(
        hasRuntime = state != null,
        startedAtMillis = startedAtMillis,
        completedAtMillis = completedAtMillis
    )
    val phase = state?.phase ?: orphanResolution.phase
    val effectiveCompletedAtMillis = completedAtMillis
        ?: orphanResolution.completedAtMillis.takeIf { it > 0L }
    val latestStep = state?.pendingAction?.description
        .orEmpty()
        .ifBlank {
            processEntries.lastOrNull()
                ?.text
                ?.takeUnless { it.contains(" \u00b7 ") }
                .orEmpty()
        }
        .ifBlank { agentExecutionPhaseText(phase) }
    return AgentExecutionPresentationPolicy.local(
        route = route ?: AgentRoute(),
        action = state?.pendingAction ?: state?.plan?.actions?.lastOrNull { action ->
            action.status in setOf(
                AgentActionStatus.RUNNING,
                AgentActionStatus.WAITING_RESPONSE,
                AgentActionStatus.COMPLETED
            )
        },
        selectedAgentOrModel = state?.plan?.selectedAgentOrModel.orEmpty(),
        phase = phase,
        currentStep = localizedAgentProcessText(latestStep),
        startedAtMillis = startedAtMillis,
        completedAtMillis = effectiveCompletedAtMillis ?: 0L
    )
}

internal fun MainActivity.agentExecutionHostText(kind: AgentExecutionLocationKind): String =
    getString(when (kind) {
        AgentExecutionLocationKind.PHONE -> R.string.agent_execution_host_phone
        AgentExecutionLocationKind.DESKTOP -> R.string.agent_execution_host_desktop
        AgentExecutionLocationKind.CLOUD -> R.string.agent_execution_host_cloud
        AgentExecutionLocationKind.CONNECTED_DEVICE -> R.string.agent_execution_host_device
        AgentExecutionLocationKind.UNKNOWN -> R.string.agent_execution_host_automatic
    })

internal fun MainActivity.agentExecutionRuntimeText(
    presentation: AgentExecutionPresentation
): String = presentation.runtimeLabelHint.ifBlank {
    agentExecutionRuntimeText(presentation.runtimeKind)
}

internal fun MainActivity.agentExecutionRuntimeText(kind: AgentExecutionRuntimeKind): String =
    getString(when (kind) {
        AgentExecutionRuntimeKind.PHONE_NATIVE -> R.string.agent_execution_runtime_android
        AgentExecutionRuntimeKind.PHONE_LINUX -> R.string.agent_execution_runtime_linux
        AgentExecutionRuntimeKind.PHONE_LOCAL_MODEL ->
            R.string.agent_execution_runtime_local_model
        AgentExecutionRuntimeKind.PHONE_CLOUD_API ->
            R.string.agent_execution_runtime_cloud_api
        AgentExecutionRuntimeKind.DESKTOP_AGENT ->
            R.string.agent_execution_runtime_desktop_agent
        AgentExecutionRuntimeKind.DESKTOP_TOOL ->
            R.string.agent_execution_runtime_desktop_tool
        AgentExecutionRuntimeKind.CONNECTED_DEVICE ->
            R.string.agent_execution_runtime_connected_device
        AgentExecutionRuntimeKind.KNOWLEDGE ->
            R.string.agent_execution_runtime_knowledge
        AgentExecutionRuntimeKind.UNKNOWN ->
            R.string.agent_execution_runtime_automatic
    })

internal fun MainActivity.agentExecutionHostTextColor(kind: AgentExecutionLocationKind): Int =
    Color.parseColor(when (kind) {
        AgentExecutionLocationKind.PHONE -> "#16875B"
        AgentExecutionLocationKind.DESKTOP -> "#2268C8"
        AgentExecutionLocationKind.CLOUD -> "#6250C5"
        AgentExecutionLocationKind.CONNECTED_DEVICE -> "#9A6200"
        AgentExecutionLocationKind.UNKNOWN -> "#66717C"
    })

internal fun MainActivity.agentExecutionHostBackgroundColor(kind: AgentExecutionLocationKind): Int =
    Color.parseColor(when (kind) {
        AgentExecutionLocationKind.PHONE -> "#EAF7F0"
        AgentExecutionLocationKind.DESKTOP -> "#EAF2FF"
        AgentExecutionLocationKind.CLOUD -> "#F0EEFF"
        AgentExecutionLocationKind.CONNECTED_DEVICE -> "#FFF4E5"
        AgentExecutionLocationKind.UNKNOWN -> "#F0F2F4"
    })

internal fun MainActivity.agentExecutionPhaseText(phase: AgentPhase): String = getString(when (phase) {
    AgentPhase.OBSERVING -> R.string.agent_status_observing
    AgentPhase.PLANNING -> R.string.agent_status_planning
    AgentPhase.WAITING_CONFIRMATION -> R.string.agent_status_waiting_confirmation
    AgentPhase.EXECUTING -> R.string.agent_status_executing
    AgentPhase.VERIFYING -> R.string.agent_status_verifying
    AgentPhase.WAITING_RESPONSE -> R.string.agent_status_waiting_response
    AgentPhase.PAUSED -> R.string.agent_status_paused
    AgentPhase.CANCELLED -> R.string.agent_status_cancelled
    AgentPhase.BLOCKED -> R.string.agent_status_blocked
    AgentPhase.COMPLETED -> R.string.agent_status_completed
    AgentPhase.FAILED -> R.string.agent_status_failed
})

internal fun MainActivity.showAgentTimelineMenu(
    entry: AgentTranscriptEntry,
    anchor: View,
    includeCancel: Boolean = true
) {
    val runtime = agentTimelineRuntime(entry)
    if (runtime == null) {
        Toast.makeText(
            this,
            getString(R.string.agent_loop_timeline_action_unavailable),
            Toast.LENGTH_SHORT
        ).show()
        return
    }
    val actions = AgentExecutionLoopTimelinePolicy.actionsForPhase(runtime.snapshot().phase)
        .filter { includeCancel || it != AgentExecutionLoopTimelineAction.CANCEL }
    if (actions.isEmpty()) {
        Toast.makeText(
            this,
            getString(R.string.agent_loop_timeline_action_unavailable),
            Toast.LENGTH_SHORT
        ).show()
        return
    }
    PopupMenu(this, anchor).apply {
        actions.forEachIndexed { order, action ->
            menu.add(0, action.ordinal, order, agentTimelineActionLabel(action))
        }
        setOnMenuItemClickListener { item ->
            actions.firstOrNull { it.ordinal == item.itemId }?.let { action ->
                runAgentTimelineAction(entry, runtime, action)
                true
            } ?: false
        }
        show()
    }
}

internal fun MainActivity.agentTimelineActionLabel(action: AgentExecutionLoopTimelineAction): String =
    getString(when (action) {
        AgentExecutionLoopTimelineAction.PAUSE -> R.string.agent_pause_button
        AgentExecutionLoopTimelineAction.RESUME -> R.string.agent_resume_button
        AgentExecutionLoopTimelineAction.RETRY -> R.string.common_retry
        AgentExecutionLoopTimelineAction.REPLAN -> R.string.agent_loop_timeline_replan_action
        AgentExecutionLoopTimelineAction.CANCEL -> R.string.common_cancel
    })

internal fun MainActivity.runAgentTimelineAction(
    entry: AgentTranscriptEntry,
    runtime: MobileNativeAgent,
    action: AgentExecutionLoopTimelineAction
) {
    if (action !in AgentExecutionLoopTimelinePolicy.actionsForPhase(runtime.snapshot().phase)) {
        Toast.makeText(
            this,
            getString(R.string.agent_loop_timeline_action_unavailable),
            Toast.LENGTH_SHORT
        ).show()
        return
    }
    var remoteCancellationFailed = false
    runAgentTimelineOperation(
        entry = entry,
        runtime = runtime,
        onComplete = {
            if (remoteCancellationFailed) {
                Toast.makeText(
                    this,
                    getString(R.string.agent_loop_timeline_remote_cancel_failed),
                    Toast.LENGTH_LONG
                ).show()
            }
        }
    ) {
        when (action) {
            AgentExecutionLoopTimelineAction.PAUSE -> runtime.pauseCurrentTask()
            AgentExecutionLoopTimelineAction.RESUME -> runtime.resumeCurrentTask()
            AgentExecutionLoopTimelineAction.RETRY -> runtime.retryFailedAction()
            AgentExecutionLoopTimelineAction.REPLAN -> runtime.replanCurrentTask()
            AgentExecutionLoopTimelineAction.CANCEL -> {
                remoteCancellationFailed =
                    publishRemoteAgentTaskCancellation(runtime.snapshot()) == false
                val turnId = entry.turnId.ifBlank {
                    agentRuntimeTurnIds[runtime].orEmpty()
                }
                turnId.takeIf(String::isNotBlank)
                    ?.let { AgentTaskRuntime.supervisor(this).cancellationSource(it) }
                    ?.cancel("User cancelled the Agent task")
                runtime.cancelCurrentTask()
            }
        }
    }
}

internal fun MainActivity.runAgentTimelineOperation(
    entry: AgentTranscriptEntry,
    runtime: MobileNativeAgent,
    onComplete: (AgentUiState) -> Unit = {},
    operation: () -> AgentUiState
) {
    val turnId = entry.turnId.ifBlank { agentRuntimeTurnIds[runtime].orEmpty() }
    val operationKey = turnId.ifBlank { runtime.snapshot().sessionId }
    if (!agentTimelineOperationsInFlight.add(operationKey)) return
    val conversationId = entry.conversationId.ifBlank {
        agentRuntimeConversationIds[runtime].orEmpty()
    }
    thread(name = "signalasi-agent-timeline-operation") {
        if (turnId.isNotBlank()) bindAgentExecutionLoop(runtime, turnId)
        val outcome = runCatching {
            var state = operation()
            if (turnId.isNotBlank()) {
                state = finalizeAgentExecutionLoop(runtime, turnId, state)
                persistAgentWorkspaceSnapshot(turnId, state, runtime)
            }
            state
        }
        runOnUiThread {
            agentTimelineOperationsInFlight.remove(operationKey)
            val state = outcome.getOrElse { runtime.snapshot() }
            renderAgentState(state, conversationId, turnId)
            onComplete(state)
            outcome.exceptionOrNull()?.let { error ->
                Toast.makeText(
                    this@runAgentTimelineOperation,
                    error.message ?: getString(R.string.agent_loop_timeline_action_unavailable),
                    Toast.LENGTH_LONG
                ).show()
            }
        }
    }
}

internal fun MainActivity.activeAgentTurnForConversation(
    conversationId: String,
    excludingTurnId: String
): ActiveAgentTurn? {
    return buildList {
        addAll(activeAgentTasks.values)
        addAll(provisionalAgentTasks)
        add(mobileNativeAgent)
    }
        .distinct()
        .mapNotNull { runtime ->
            val runtimeConversationId = agentRuntimeConversationIds[runtime].orEmpty()
            val runtimeTurnId = agentRuntimeTurnIds[runtime].orEmpty()
            val state = runtime.snapshot()
            val persistedTaskPhase = state.plan?.planId?.let { planId ->
                state.recentTasks.firstOrNull { it.taskId == planId }?.phase
            }
            if (
                runtimeConversationId == conversationId &&
                runtimeTurnId.isNotBlank() &&
                runtimeTurnId != excludingTurnId &&
                AgentActiveTurnPolicy.isRuntimeActive(
                    phase = state.phase,
                    loopPhase = state.executionLoop?.phase,
                    persistedTaskPhase = persistedTaskPhase
                )
            ) {
                ActiveAgentTurn(runtime, runtimeTurnId, state)
            } else {
                null
            }
        }
        .lastOrNull()
}

internal fun MainActivity.cancelActiveAgentTurn(
    active: ActiveAgentTurn,
    interventionTurnId: String
) {
    if (active.isDesktopTask) {
        publishRemoteAgentTaskCancellation(active.state)
    }
    AgentTaskRuntime.supervisor(this).cancellationSource(active.turnId)
        ?.cancel("Superseded by a newer user instruction")
    PhoneExecutionAuthority.requestCancellation(active.state.sessionId)
    val cancelled = active.runtime.cancelCurrentTask()
    val runId = agentRunIdsByTurn[active.turnId].orEmpty()
    agentRunRecorder.run(runId)?.let { run ->
        appendRunControlEvent(
            run = run,
            messageId = active.turnId,
            taskId = active.turnId,
            agentId = active.state.plan?.selectedAgentOrModel.orEmpty()
                .ifBlank { "signalasi-mobile" },
            type = AgentRunControlEventType.RUN_CANCELLED,
            payload = mapOf(
                "intervention_turn_id" to interventionTurnId,
                "reason" to "superseded_by_user"
            )
        )
    }
    activeAgentTasks.entries
        .filter { it.value === active.runtime }
        .forEach { activeAgentTasks.remove(it.key, it.value) }
    provisionalAgentTasks.remove(active.runtime)
    if (agentTranscriptStore.activeConversation().id ==
        agentRuntimeConversationIds[active.runtime]
    ) {
        runOnUiThread {
            renderAgentState(cancelled, agentRuntimeConversationIds[active.runtime].orEmpty(), active.turnId)
        }
    }
}

internal fun MainActivity.interruptActiveAgentTurn(
    active: ActiveAgentTurn,
    conversationId: String,
    interventionTurnId: String
) {
    cancelActiveAgentTurn(active, interventionTurnId)
    agentTranscriptStore.append(
        AgentTranscriptRole.PROCESS,
        getString(R.string.agent_task_status_cancelled),
        dedupeKey = "active-turn-interrupt:$interventionTurnId",
        conversationId = conversationId,
        turnId = interventionTurnId,
        taskId = interventionTurnId
    )
    AgentTurnAttachmentRegistry.remove(interventionTurnId)
    runOnUiThread {
        refreshAgentTranscriptWindow(conversationId)
    }
}

internal fun MainActivity.submitAgentGoal(
    voiceTraceId: String = "",
    pendingVoiceDedupeKey: String = "",
    pendingVoiceConversationId: String = "",
    goalOverride: String? = null,
    attachmentsOverride: List<AgentInputAttachment>? = null
) {
    val submissionStartedAt = SystemClock.elapsedRealtime()
    val goal = goalOverride?.trim()
        ?: agentGoalInput.text?.toString()?.trim().orEmpty()
    val attachments = AgentVoiceAttachmentSubmissionPolicy.select(
        goalOverride = goalOverride,
        composerAttachments = agentInputAttachments,
        attachmentSnapshot = attachmentsOverride
    )
    if (goal.isBlank() && attachments.isEmpty()) {
        Toast.makeText(this, getString(R.string.agent_empty_goal), Toast.LENGTH_SHORT).show()
        return
    }
    val conversation = pendingVoiceConversationId
        .takeIf(String::isNotBlank)
        ?.let(agentTranscriptStore::conversation)
        ?: agentTranscriptStore.activeConversation()
    val turnId = UUID.randomUUID().toString()
    if (!initialAgentHydrationPending) {
        agentTranscriptStore.preparedContext(conversation.id)?.let { prepared ->
            agentContextBeforeTurn[turnId] = prepared
        }
    }
    if (agentContextBeforeTurn.size > 2_000) {
        agentContextBeforeTurn.keys.take(400).forEach(agentContextBeforeTurn::remove)
    }
    if (voiceTraceId.isNotBlank()) {
        activeVoiceTraceId = voiceTraceId
        voiceTraceIdsByTurn[turnId] = voiceTraceId
        voiceTurnContextsByTraceId[voiceTraceId] = VoiceTurnContext(conversation.id, turnId)
        if (voiceTurnContextsByTraceId.size > 256) {
            voiceTurnContextsByTraceId.keys.take(64).forEach(voiceTurnContextsByTraceId::remove)
        }
    }
    voiceCoordinatorSession(voiceTraceId).takeIf(String::isNotBlank)?.let { sessionId ->
        voiceCoordinatorIdsByTurn[turnId] = sessionId
    }
    agentTranscriptAutoFollow = true
    pendingAgentReplyIndicators[turnId] = PendingAgentReplyIndicator(
        conversationId = conversation.id,
        turnId = turnId,
        startedAtMillis = System.currentTimeMillis()
    )
    if (pendingAgentReplyIndicators.size > MAX_PENDING_AGENT_REPLY_INDICATORS) {
        pendingAgentReplyIndicators.values
            .sortedBy(PendingAgentReplyIndicator::startedAtMillis)
            .take(pendingAgentReplyIndicators.size - MAX_PENDING_AGENT_REPLY_INDICATORS)
            .forEach { pendingAgentReplyIndicators.remove(it.turnId, it) }
    }
    val attachmentLabel = when (attachments.size) {
        0 -> ""
        1 -> "[${attachments.first().displayName}]"
        else -> getString(R.string.agent_attachment_count, attachments.size)
    }
    AgentTurnAttachmentRegistry.put(turnId, attachments)
    if (goalOverride == null) {
        agentGoalInput.setText("")
        agentInputAttachments.clear()
        renderAgentInputAttachments()
        agentGoalInput.clearFocus()
        getSystemService(InputMethodManager::class.java)
            .hideSoftInputFromWindow(agentGoalInput.windowToken, 0)
    } else if (attachmentsOverride != null && attachments.isNotEmpty()) {
        val consumedAttachmentIds = attachments.mapTo(hashSetOf(), AgentInputAttachment::id)
        if (agentInputAttachments.removeAll { it.id in consumedAttachmentIds }) {
            renderAgentInputAttachments()
        }
    }
    val baseGoal = goal.ifBlank { getString(R.string.agent_attachment_default_goal) }
    agentTurnGoals[turnId] = goal.ifBlank { attachmentLabel }.ifBlank { baseGoal }
    if (agentTurnGoals.size > 2_000) {
        agentTurnGoals.keys.take(400).forEach(agentTurnGoals::remove)
    }
    val submittedText = goal.ifBlank { attachmentLabel }
    val richOutputJson = AgentRichContentCodec.encode(attachments.map(AgentInputAttachment::richBlock))
    agentSubmissionExecutor.execute {
        if (pendingVoiceDedupeKey.isNotBlank()) {
            agentTranscriptStore.upsert(
                AgentTranscriptRole.USER,
                submittedText,
                dedupeKey = pendingVoiceDedupeKey,
                conversationId = conversation.id,
                turnId = turnId,
                taskId = turnId,
                richOutputJson = richOutputJson
            )
        } else {
            agentTranscriptStore.append(
                AgentTranscriptRole.USER,
                submittedText,
                conversationId = conversation.id,
                turnId = turnId,
                taskId = turnId,
                richOutputJson = richOutputJson
            )
        }
        Log.i(
            "SignalASILatency",
            "agent_submit stage=user_persisted turn=${turnId.take(8)} " +
                "elapsed_ms=${SystemClock.elapsedRealtime() - submissionStartedAt}"
        )
        runOnUiThread {
            if (isFinishing || isDestroyed) return@runOnUiThread
            if (pendingVoiceDedupeKey.isNotBlank() &&
                agentTranscriptWindow.conversationId == conversation.id
            ) {
                agentTranscriptWindow.entries
                    .filter { it.dedupeKey == pendingVoiceDedupeKey }
                    .map(AgentTranscriptEntry::id)
                    .forEach(agentTranscriptWindow::remove)
            }
            if (attachments.isEmpty()) {
                continueAgentGoalSubmission(
                    goal = baseGoal,
                    conversationId = conversation.id,
                    turnId = turnId,
                    originalGoal = goal
                )
            } else {
                stageAgentGoalAttachments(
                    goal = goal,
                    baseGoal = baseGoal,
                    conversation = conversation,
                    turnId = turnId,
                    attachments = attachments
                )
            }
            Log.i(
                "SignalASILatency",
                "agent_submit stage=route_scheduled turn=${turnId.take(8)} " +
                    "elapsed_ms=${SystemClock.elapsedRealtime() - submissionStartedAt}"
            )
            refreshGlobalAgentCognition()
            refreshAgentConversationHeader()
            refreshAgentTranscriptWindow(conversation.id)
        }
        AgentLearningAnalyzer.correctionFeedback(goal)?.let { feedback ->
            agentRunRecorder.addFeedback(conversation.id, feedback)?.let { correctedRun ->
                agentLearningEngine.observeFeedback(correctedRun, agentRunRecorder.recentRuns())
            }
        }
    }
}

internal fun MainActivity.stageAgentGoalAttachments(
    goal: String,
    baseGoal: String,
    conversation: AgentConversation,
    turnId: String,
    attachments: List<AgentInputAttachment>
) {
    thread(name = "signalasi-agent-attachments") {
        val staged = runCatching {
            AgentAttachmentWorkspaceStager.stage(
                applicationContext,
                conversation.id,
                turnId,
                attachments
            )
        }.getOrDefault(emptyList())
        val attachmentManifest = buildString {
            attachments.forEach { attachment ->
                append("- ").append(attachment.displayName)
                append(" (").append(attachment.mimeType).append(", ")
                append(AgentInputAttachment.humanSize(attachment.sizeBytes)).append(")\n")
            }
            if (staged.isNotEmpty()) {
                append("Phone project paths:\n")
                staged.forEach { item ->
                    append("- ").append(item.relativePath)
                        .append(" | sha256=").append(item.sha256).append("\n")
                }
            }
        }
        val executionGoal = buildString {
            append(baseGoal)
            append("\n\nAttached input:\n")
            append(
                AgentUntrustedEvidenceBoundary.wrapText(
                    "attachment_manifest",
                    "${conversation.id}/$turnId",
                    attachmentManifest
                )
            )
            append('\n')
            if (goal.isBlank()) {
                append("Do not inspect the attached content until the user provides a task.")
            } else {
                append("Use the attached content when completing the request.")
            }
        }
        runOnUiThread {
            continueAgentGoalSubmission(
                executionGoal,
                conversation.id,
                turnId,
                forcedAction = if (staged.isEmpty()) attachmentConnectorAction(executionGoal) else null,
                originalGoal = goal
            )
        }
        if (goal.isNotBlank() && !conversation.privateMode && !conversation.trackingPaused) {
            attachments.filterNot { attachment ->
                attachment.mimeType.startsWith("image/") ||
                    attachment.mimeType.startsWith("video/") ||
                    attachment.mimeType.startsWith("audio/")
            }.forEach { attachment ->
                runCatching { AgentKnowledgeImporter(applicationContext).importDocument(attachment.uri) }
            }
        }
    }
}

internal fun MainActivity.attachmentConnectorAction(goal: String): AgentAction? {
    val targets = AppStoreAgentConnectorRegistry(this).availableTargets()
    val target = listOf("codex", "hermes").firstNotNullOfOrNull { preferredId ->
        targets.firstOrNull { candidate ->
            candidate.status == AgentConnectorStatus.AVAILABLE &&
                (candidate.id == preferredId || candidate.id.endsWith(":$preferredId"))
        }
    } ?: return null
    return AgentAction(
        id = "attachment-${target.id}",
        kind = AgentActionKind.CALL_CONNECTOR,
        target = target.title,
        risk = AgentRisk.LOW,
        status = AgentActionStatus.PENDING_CONFIRMATION,
        description = "Process the attached input with ${target.title}",
        parameters = mapOf("connector_id" to target.id, "prompt" to goal),
        requiresConfirmation = false
    )
}

internal fun MainActivity.continueAgentGoalSubmission(
    goal: String,
    conversationId: String,
    turnId: String,
    forcedAction: AgentAction? = null,
    originalGoal: String = goal,
    executionModeOverride: AgentTaskExecutionMode? = null
) {
    val routingStartedAt = SystemClock.elapsedRealtime()
    val voiceTraceId = voiceTraceIdsByTurn[turnId].orEmpty()
    VoiceLatencyTelemetry.record(
        this,
        voiceTraceId,
        VoiceTraceEvents.ROUTE_STARTED,
        once = true
    )
    val taskExecutionMode = executionModeOverride
        ?: AgentTaskExecutionModePolicy.resolve(
            originalGoal.ifBlank { goal },
            mobileNativeAgent.safetySettings().taskExecutionMode
        ).mode
    val localAgentControlCommand = AgentLocalControlCommandPolicy.matches(goal)
    if (
        !localAgentControlCommand &&
        taskExecutionMode != AgentTaskExecutionMode.PLAN_ONLY &&
        handleAgentSkillCommand(goal, conversationId, turnId)
    ) return
    agentRoutingExecutor.execute {
        if (initialAgentHydrationPending) {
            val hydrationWaitStartedAt = SystemClock.elapsedRealtime()
            initialAgentHydrationReady.await()
            Log.i(
                "SignalASILatency",
                "agent_route stage=hydration_ready turn=${turnId.take(8)} " +
                    "wait_ms=${SystemClock.elapsedRealtime() - hydrationWaitStartedAt}"
            )
        }
        val baseConversationContext = agentContextBeforeTurn.remove(turnId)
            ?: agentTranscriptStore.context(
                conversationId = conversationId,
                excludeTurnId = turnId
            )
        Log.i(
            "SignalASILatency",
            "agent_route stage=context_loaded turn=${turnId.take(8)} " +
                "elapsed_ms=${SystemClock.elapsedRealtime() - routingStartedAt}"
        )
        val correctionContext = voiceCorrectionJournal.contextBlock(conversationId)
        val localConversationContext = if (correctionContext.isBlank()) {
            baseConversationContext
        } else {
            baseConversationContext.copy(
                summary = listOf(baseConversationContext.summary, correctionContext)
                    .filter(String::isNotBlank)
                    .joinToString("\n\n")
            )
        }
        val turnAttachments = AgentTurnAttachmentRegistry.get(turnId)
        val clarification = AgentClarificationPolicy.decide(
            goal = originalGoal,
            hasAttachments = turnAttachments.isNotEmpty(),
            hasConversationContext = localConversationContext.summary.isNotBlank() ||
                localConversationContext.turns.isNotEmpty(),
            preferenceMode = mobileNativeAgent.preferenceMode()
        )
        if (clarification.mode == AgentClarificationMode.ASK_LOCALLY) {
            agentTranscriptStore.append(
                AgentTranscriptRole.ASSISTANT,
                agentClarificationQuestion(clarification.question),
                dedupeKey = "clarification:$turnId",
                conversationId = conversationId,
                turnId = turnId,
                taskId = turnId
            )
            AgentTurnAttachmentRegistry.remove(turnId)
            Log.d(
                "SignalASIAgent",
                "clarification_completed turn=${turnId.take(8)} question=${clarification.question.name}"
            )
            runOnUiThread { refreshAgentTranscriptWindow(conversationId) }
            return@execute
        }
        var executionGoal = if (clarification.mode == AgentClarificationMode.ASK_WITH_MODEL) {
            buildString {
                append(getString(R.string.agent_attachment_default_goal))
                if (turnAttachments.isNotEmpty()) {
                    append("\nAttachment names: ")
                    append(turnAttachments.joinToString(", ") { it.displayName })
                }
            }
        } else {
            goal
        }
        AgentSupervisedProjectContinuationPolicy.mergedGoal(
            latestRequest = originalGoal.ifBlank { executionGoal },
            conversationContext = localConversationContext
        )?.let { resumedGoal ->
            executionGoal = resumedGoal
            clearSupersededAgentFailureEntries(conversationId)
            Log.i(
                "SignalASIAgent",
                "restored supervised phone project context turn=${turnId.take(8)}"
            )
        }
        val activeTurn = if (taskExecutionMode == AgentTaskExecutionMode.PLAN_ONLY) {
            null
        } else {
            activeAgentTurnForConversation(conversationId, turnId)
        }
        val activeTurnDecision = activeTurn?.let { active ->
            AgentActiveTurnPolicy.decide(
                request = originalGoal.ifBlank { executionGoal },
                activeGoal = active.state.currentGoal,
                hasNewAttachments = turnAttachments.isNotEmpty()
            )
        }
        if (
            activeTurn != null &&
            activeTurnDecision?.disposition == AgentActiveTurnDisposition.INTERRUPT
        ) {
            interruptActiveAgentTurn(activeTurn, conversationId, turnId)
            return@execute
        }
        var interventionDisposition = ""
        var activeDesktopSteerAction: AgentAction? = null
        if (
            activeTurn != null &&
            activeTurnDecision?.disposition == AgentActiveTurnDisposition.STEER
        ) {
            if (activeTurn.isDesktopTask) {
                interventionDisposition = "steer"
                activeDesktopSteerAction = activeTurn.state.plan
                    ?.actions
                    ?.lastOrNull { it.kind == AgentActionKind.CALL_CONNECTOR }
                    ?.let { previous ->
                        previous.copy(
                            id = "steer-$turnId",
                            status = AgentActionStatus.PENDING_CONFIRMATION,
                            description = previous.description,
                            parameters = previous.parameters + ("prompt" to executionGoal),
                            requiresConfirmation = false,
                            result = "",
                            evidence = ""
                        )
                    }
            } else {
                interventionDisposition = "supersede"
                cancelActiveAgentTurn(activeTurn, turnId)
                executionGoal = AgentActiveTurnPolicy.supersedingGoal(
                    activeGoal = activeTurn.state.currentGoal,
                    intervention = executionGoal,
                    kind = activeTurnDecision.interventionKind
                )
            }
        }
        val modelExecutionSiteDecisionRequired =
            AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(
                executionGoal,
                localConversationContext
            ) && activeDesktopSteerAction == null
        if (
            !localAgentControlCommand &&
            !modelExecutionSiteDecisionRequired &&
            taskExecutionMode != AgentTaskExecutionMode.PLAN_ONLY
        ) {
            AgentFastLocalResponse.reply(executionGoal, localConversationContext)?.let { response ->
                if (AgentResponseSelfCheck.evaluate(executionGoal, response).accepted) {
                    selectVoiceCoordinatorRoute(
                        voiceTraceId,
                        VoiceRouteKind.LOCAL_ACTION,
                        "signalasi-mobile"
                    )
                    agentTranscriptStore.append(
                        AgentTranscriptRole.ASSISTANT,
                        response,
                        dedupeKey = "fast-local:$turnId",
                        conversationId = conversationId,
                        turnId = turnId,
                        taskId = turnId
                    )
                    voiceCoordinatorSession(voiceTraceId).takeIf(String::isNotBlank)?.let { sessionId ->
                        dispatchVoiceCoordinator(VoiceInteractionEvent.LocalActionCompleted(sessionId))
                        voiceCoordinatorIdsByTurn.remove(turnId)
                    }
                    Log.d("SignalASIAgent", "fast_local_completed turn=${turnId.take(8)}")
                    runOnUiThread { refreshAgentTranscriptWindow(conversationId) }
                    return@execute
                }
                Log.w("SignalASIAgent", "fast_local_response_self_check_failed turn=${turnId.take(8)}")
            }
        }
        val routeSelectionGoal = executionGoal
        val routeSelectionFuture = if (
            taskExecutionMode != AgentTaskExecutionMode.PLAN_ONLY &&
            !localAgentControlCommand &&
            !modelExecutionSiteDecisionRequired &&
            forcedAction == null &&
            !AgentScreenObservationPolicy.requiresObservation(routeSelectionGoal)
        ) {
            agentRouteSelectionExecutor.submit<AgentAction?> {
                deterministicSystemActionFor(routeSelectionGoal, localConversationContext)
            }
        } else {
            null
        }
        val conversationContext = if (modelExecutionSiteDecisionRequired) {
            // Project execution already receives the durable conversation summary,
            // recent turns, project ledger and tool observations. Loading the whole
            // personal world model here blocks the foreground route and duplicates
            // context without improving the next executable decision.
            localConversationContext.copy(globalContext = "")
        } else {
            globalSuperAgentRuntime.augmentContext(localConversationContext, executionGoal)
        }
        Log.i(
            "SignalASILatency",
            "agent_route stage=context_augmented turn=${turnId.take(8)} " +
                "elapsed_ms=${SystemClock.elapsedRealtime() - routingStartedAt}"
        )
        val skillMatch = if (
            localAgentControlCommand ||
                modelExecutionSiteDecisionRequired ||
                taskExecutionMode == AgentTaskExecutionMode.PLAN_ONLY
        ) {
            null
        } else {
            agentSkillMatcher.match(executionGoal)
        }
        Log.i(
            "SignalASILatency",
            "agent_route stage=skill_matched turn=${turnId.take(8)} " +
                "elapsed_ms=${SystemClock.elapsedRealtime() - routingStartedAt}"
        )
        val requestedForcedAction = if (
            localAgentControlCommand ||
                modelExecutionSiteDecisionRequired ||
                taskExecutionMode == AgentTaskExecutionMode.PLAN_ONLY
        ) {
            null
        } else {
            forcedAction ?: activeDesktopSteerAction
        }
        val resolvedForcedAction = requestedForcedAction?.let { action ->
            if (clarification.mode == AgentClarificationMode.ASK_WITH_MODEL) {
                action.copy(parameters = action.parameters + ("prompt" to executionGoal))
            } else {
                action
            }
        }
        val deterministicAction = if (localAgentControlCommand || modelExecutionSiteDecisionRequired) {
            null
        } else {
            resolvedForcedAction
                ?: routeSelectionFuture?.let { future ->
                    runCatching { future.get() }
                        .onFailure { error ->
                            Log.w("SignalASILatency", "agent_route preselection_failed", error)
                        }
                        .getOrNull()
                }
                ?: deterministicSystemActionFor(executionGoal, conversationContext)
        }
        Log.i(
            "SignalASILatency",
            "agent_route stage=action_resolved turn=${turnId.take(8)} " +
                "elapsed_ms=${SystemClock.elapsedRealtime() - routingStartedAt}"
        )
        Log.d(
            "SignalASIAgent",
            "route_resolved turn=${turnId.take(8)} tool=${deterministicAction?.parameters?.get("tool_id").orEmpty()} " +
                "action=${deterministicAction?.id.orEmpty()} skill=${skillMatch != null} " +
                "model_execution_site=$modelExecutionSiteDecisionRequired " +
                "elapsed_ms=${SystemClock.elapsedRealtime() - routingStartedAt}"
        )
        val run = agentRunRecorder.begin(
            conversationId = conversationId,
            request = executionGoal,
            activeSkillId = if (deterministicAction == null) skillMatch?.installation?.id.orEmpty() else ""
        )
        Log.i(
            "SignalASILatency",
            "agent_route stage=run_recorded turn=${turnId.take(8)} " +
                "elapsed_ms=${SystemClock.elapsedRealtime() - routingStartedAt}"
        )
        val selectedRouteAction = resolvedForcedAction ?: deterministicAction
        val selectedAgentId = selectedRouteAction
            ?.parameters?.get("connector_id")
            .orEmpty()
            .ifBlank { "signalasi-mobile" }
        if (selectedRouteAction != null) {
            if (selectedAgentId != "signalasi-mobile") {
                updateAgentExecutionTarget(
                    conversationId = conversationId,
                    connectorId = selectedAgentId,
                    fallbackTarget = selectedRouteAction.target
                )
            }
            selectVoiceCoordinatorRoute(
                voiceTraceId,
                if (selectedAgentId == "signalasi-mobile") {
                    VoiceRouteKind.LOCAL_ACTION
                } else {
                    VoiceRouteKind.REMOTE_AGENT
                },
                selectedAgentId
            )
        }
        VoiceLatencyTelemetry.record(
            this,
            voiceTraceId,
            VoiceTraceEvents.ROUTE_SELECTED,
            mapOf(
                "agent_provider" to selectedAgentId.substringAfterLast(':'),
                "execution_mode" to taskExecutionMode.wireValue
            ),
            once = true
        )
        agentRunIdsByTurn[turnId] = run.runId
        val backgroundDirectAction = selectedRouteAction?.takeIf { action ->
            action.canBypassAgentReasoningLoop() &&
                !AgentDirectExecutionPolicy.requiresUiThread(action)
        }
        backgroundDirectAction?.let { action ->
            Log.d(
                "SignalASIAgent",
                "route_direct turn=${turnId.take(8)} action=${action.id}"
            )
            executeDirectSystemAction(
                action = action,
                conversationId = conversationId,
                turnId = turnId,
                conversationContext = conversationContext,
                goal = executionGoal,
                executionMode = taskExecutionMode
            )
        }
        val createdEventPayload: AgentNativeJsonObject =
            if (activeTurn != null && interventionDisposition.isNotBlank()) {
                mapOf(
                    "task_disposition" to interventionDisposition,
                    "active_turn_id" to activeTurn.turnId,
                    "intervention_kind" to activeTurnDecision
                        ?.interventionKind
                        ?.name
                        .orEmpty()
                        .lowercase(Locale.ROOT)
                )
            } else {
                emptyMap()
            }
        appendRunControlEvents(
            run = run,
            messageId = turnId,
            taskId = turnId,
            agentId = selectedAgentId,
            events = listOf(
                AgentRunControlEventType.RUN_CREATED to createdEventPayload,
                AgentRunControlEventType.RUN_STARTED to emptyMap()
            )
        )
        Log.i(
            "SignalASILatency",
            "agent_route stage=run_events_recorded turn=${turnId.take(8)} " +
                "elapsed_ms=${SystemClock.elapsedRealtime() - routingStartedAt}"
        )
        Log.d(
            "SignalASIAgent",
            "run_recorded turn=${turnId.take(8)} elapsed_ms=${SystemClock.elapsedRealtime() - routingStartedAt}"
        )
        when {
            backgroundDirectAction != null -> Unit
            resolvedForcedAction != null -> {
                Log.d(
                    "SignalASIAgent",
                    "route_forced_connector turn=${turnId.take(8)} action=${resolvedForcedAction.id}"
                )
                executeConcurrentAgentGoal(
                    executionGoal,
                    conversationContext,
                    conversationId,
                    turnId,
                    resolvedForcedAction,
                    taskExecutionMode
                )
            }
            deterministicAction != null && deterministicAction.canBypassAgentReasoningLoop() -> {
                Log.d(
                    "SignalASIAgent",
                    "route_direct turn=${turnId.take(8)} action=${deterministicAction.id}"
                )
                if (AgentDirectExecutionPolicy.requiresUiThread(deterministicAction)) {
                    runOnUiThread {
                        executeDirectSystemAction(
                            action = deterministicAction,
                            conversationId = conversationId,
                            turnId = turnId,
                            conversationContext = conversationContext,
                            goal = executionGoal,
                            executionMode = taskExecutionMode
                        )
                    }
                } else {
                    executeDirectSystemAction(
                        action = deterministicAction,
                        conversationId = conversationId,
                        turnId = turnId,
                        conversationContext = conversationContext,
                        goal = executionGoal,
                        executionMode = taskExecutionMode
                    )
                }
            }
            deterministicAction != null -> {
                Log.d(
                    "SignalASIAgent",
                    "route_protected turn=${turnId.take(8)} action=${deterministicAction.id}"
                )
                executeConcurrentAgentGoal(
                    executionGoal,
                    conversationContext,
                    conversationId,
                    turnId,
                    deterministicAction,
                    taskExecutionMode
                )
            }
            skillMatch != null &&
                executeMatchedSkill(
                    skillMatch,
                    conversationId,
                    turnId,
                    executionGoal,
                    conversationContext
                ) -> Unit
            else -> executeConcurrentAgentGoal(
                executionGoal,
                conversationContext,
                conversationId,
                turnId,
                executionMode = taskExecutionMode
            )
        }
    }
}

internal fun AgentAction.canBypassAgentReasoningLoop(): Boolean =
    kind != AgentActionKind.CALL_CONNECTOR &&
        AgentConfirmationPolicy.tier(this) == AgentConfirmationTier.DIRECT

internal fun MainActivity.clearSupersededAgentFailureEntries(conversationId: String) {
    if (Looper.myLooper() == Looper.getMainLooper()) {
        agentTaskLivenessExecutor.execute { clearSupersededAgentFailureEntries(conversationId) }
        return
    }
    val staleEntries = agentTranscriptStore.list(conversationId).filter { entry ->
        entry.dedupeKey.startsWith("task-watchdog:") ||
            entry.dedupeKey.startsWith("task-watchdog-timeout:") ||
            entry.dedupeKey.startsWith("agent-recovery:")
    }
    if (staleEntries.isEmpty()) return
    staleEntries.map(AgentTranscriptEntry::dedupeKey)
        .distinct()
        .forEach { dedupeKey ->
            agentTranscriptStore.deleteByDedupeKey(conversationId, dedupeKey)
        }
    runOnUiThread {
        if (agentTranscriptWindow.conversationId == conversationId) {
            staleEntries.map(AgentTranscriptEntry::id).forEach(agentTranscriptWindow::remove)
        }
        requestAgentTranscriptWindowRefresh(conversationId)
    }
}
