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

internal fun MainActivity.createAgentConversation(preselectedTarget: AgentCallableTarget? = null) {
    agentInputAttachments.clear()
    renderAgentInputAttachments()
    agentGoalInput.setText("")
    val conversation = agentTranscriptStore.createConversation()
    preselectedTarget?.let { target ->
        val existingConfiguration = AgentModelSelectionSettings.configurationForTarget(
            this,
            conversation.id,
            target.id
        )
        val displayName = agentModelTargetDisplayName(target)
        val reasoningEffort = existingConfiguration?.reasoningEffort
            ?.takeIf { it in target.invocationProfile.reasoningEfforts }
            ?: target.invocationProfile.reasoningEfforts.firstOrNull()
            ?: AgentModelReasoningEffort.AUTO
        AgentModelSelectionSettings.selectManual(
            this,
            conversationId = conversation.id,
            targetId = target.id,
            modelId = target.invocationProfile.normalizedModelId(
                existingConfiguration?.modelId.orEmpty()
            ),
            displayName = displayName,
            reasoningEffort = reasoningEffort,
            rememberAsDefault = false
        )
        agentTranscriptStore.setSelectedModelOrAgent(conversation.id, displayName)
    }
    lastRenderedAgentState = null
    renderAgentState(mobileNativeAgent.startNewConversation(conversation.id), conversation.id, syncTranscript = false)
    resetAgentTranscriptRendering(conversation.id)
    refreshAgentConversationHeader()
    refreshAgentTranscriptWindow()
    if (featurePage.visibility == View.VISIBLE) hideFeaturePage()
}

internal fun MainActivity.openContactMessaging(contact: Contact) {
    val raw = AppStore.contactById(this, contact.id)
    if (!ScannedAgentConversationPolicy.opensAgentConversation(raw)) {
        showChatPage(contact)
        return
    }
    val registryTargets = AppStoreAgentConnectorRegistry(this).availableTargets()
    val selectedTarget = ScannedAgentConversationPolicy.resolveTarget(
        contactId = contact.id,
        contact = raw,
        targets = registryTargets
    ) ?: AgentCallableTarget(
        id = raw?.optString("id").orEmpty().ifBlank { contact.id },
        title = raw?.optString("display_name").orEmpty()
            .ifBlank { raw?.optString("name").orEmpty() }
            .ifBlank { contact.name },
        kind = AgentConnectorKind.AGENT,
        status = AgentConnectorStatus.DISCONNECTED,
        capabilities = listOf(AgentCapability.CHAT),
        adapterType = raw?.optJSONObject("adapter")?.optString("adapter_type").orEmpty(),
        invocationProfile = AgentInvocationProfileJsonCodec.decode(
            raw?.optJSONObject("invocation_profile")
        )
    )
    showMainTab(PAGE_AGENT)
    createAgentConversation(selectedTarget)
}

private data class AgentModelSelectionContent(
    val conversationId: String,
    val targets: List<AgentCallableTarget>,
    val selection: AgentModelSelection,
    val localProfiles: List<LocalModelRuntimeProfile>
)

internal fun MainActivity.showAgentModelSelectionPage() {
    SignalASIMqttClient.requestCapabilityManifestRefresh(force = true)
    showFeaturePage(getString(R.string.agent_model_selection_title))
    setFeatureBackAction { hideFeaturePage() }
    val generation = navigationContentGate.begin()
    val fastConversationId = agentRenderedConversationId
    val fastTargets = lastRenderedAgentState?.callableTargets.orEmpty()
    if (fastConversationId.isNotBlank() && fastTargets.isNotEmpty()) {
        renderAgentModelSelectionPage(
            AgentModelSelectionContent(
                conversationId = fastConversationId,
                targets = fastTargets,
                selection = AgentModelSelectionSettings.selection(this, fastConversationId),
                localProfiles = emptyList()
            )
        )
    } else {
        featureContent.addView(featureValueRow(
            getString(R.string.navigation_content_loading),
            "",
            R.drawable.ic_settings_model,
            ""
        ))
    }
    navigationContentExecutor.execute {
        val content = runCatching {
            val conversationId = agentTranscriptStore.activeConversation().id
            AgentModelSelectionContent(
                conversationId = conversationId,
                targets = AppStoreAgentConnectorRegistry(this).availableTargets(),
                selection = AgentModelSelectionSettings.selection(this, conversationId),
                localProfiles = LocalModelRuntimeSettings.activeProfiles(this)
            )
        }.getOrNull()
        handler.post {
            if (content != null && navigationContentGate.isCurrent(generation) && featurePage.visibility == View.VISIBLE) {
                renderAgentModelSelectionPage(content)
            }
        }
    }
}

private fun MainActivity.renderAgentModelSelectionPage(content: AgentModelSelectionContent) {
    val conversationId = content.conversationId
    val targets = content.targets
    val selection = content.selection
    val preferredTargetId = AgentModelSelectionPolicy.preferredTargetId(selection, targets)
    val automaticSelected = selection.mode == AgentModelSelectionMode.AUTO || preferredTargetId.isBlank()

    featureContent.removeAllViews()
    featureContent.addView(
        agentModelSelectionRow(
            title = getString(R.string.agent_model_selection_automatic),
            subtitle = getString(R.string.agent_model_selection_automatic_subtitle),
            iconRes = R.drawable.ic_agent_skill,
            iconColor = Color.parseColor("#12BFA4"),
            selected = automaticSelected
        ).apply {
            setOnClickListener {
                AgentModelSelectionSettings.selectAuto(this@renderAgentModelSelectionPage, conversationId)
                refreshAgentConversationHeader()
                renderAgentModelSelectionPage(
                    content.copy(selection = AgentModelSelectionSettings.selection(this@renderAgentModelSelectionPage, conversationId))
                )
            }
        }
    )

    val localProfiles = content.localProfiles
    if (localProfiles.isNotEmpty()) {
        addSectionTitle(getString(R.string.agent_model_selection_local_section))
        localProfiles.forEach { profile ->
            val selected = preferredTargetId == "local-llm" && selection.modelId == profile.id
            featureContent.addView(
                agentModelSelectionRow(
                    title = profile.displayName,
                    subtitle = getString(R.string.agent_model_selection_local_subtitle),
                    iconRes = R.drawable.ic_local_model,
                    iconColor = featureIconColor(R.drawable.ic_local_model),
                    selected = selected
                ).apply {
                    setOnClickListener {
                        LocalModelRuntimeSettings.setSelectedProfile(this@renderAgentModelSelectionPage, profile.id)
                        AgentModelSelectionSettings.selectManual(
                            this@renderAgentModelSelectionPage,
                            conversationId = conversationId,
                            targetId = "local-llm",
                            modelId = profile.id,
                            displayName = profile.displayName
                        )
                        refreshAgentConversationHeader()
                        renderAgentModelSelectionPage(
                            content.copy(selection = AgentModelSelectionSettings.selection(this@renderAgentModelSelectionPage, conversationId))
                        )
                    }
                }
            )
        }
    }

    val agentTargets = AgentModelSelectionPolicy.selectableAgentTargets(targets)
    if (agentTargets.isNotEmpty()) {
        addSectionTitle(getString(R.string.agent_model_selection_agent_section))
        agentTargets.forEach { target ->
            val agentName = agentModelTargetDisplayName(target)
            val selected = preferredTargetId == target.id
            val agentSubtitle = buildList {
                add(getString(R.string.agent_model_selection_agent_subtitle))
                if (selected && selection.modelId.isNotBlank()) add(selection.modelId)
                if (selected && selection.reasoningEffort != AgentModelReasoningEffort.AUTO) {
                    add(getString(selection.reasoningEffort.labelResource()))
                }
            }.joinToString(" · ")
            featureContent.addView(
                agentModelSelectionRow(
                    title = agentName,
                    subtitle = agentSubtitle,
                    iconRes = controlCenterTargetIcon(target),
                    iconColor = featureIconColor(controlCenterTargetIcon(target)),
                    selected = selected
                ).apply {
                    setOnClickListener {
                        val existingForTarget = AgentModelSelectionSettings.configurationForTarget(
                            this@renderAgentModelSelectionPage,
                            conversationId,
                            target.id
                        )
                        AgentModelSelectionSettings.selectManual(
                            this@renderAgentModelSelectionPage,
                            conversationId = conversationId,
                            targetId = target.id,
                            modelId = target.invocationProfile.normalizedModelId(
                                existingForTarget?.modelId.orEmpty()
                            ),
                            displayName = agentName,
                            reasoningEffort = existingForTarget?.reasoningEffort
                                ?.takeIf { it in target.invocationProfile.reasoningEfforts }
                                ?: target.invocationProfile.reasoningEfforts.firstOrNull()
                                ?: AgentModelReasoningEffort.AUTO
                        )
                        refreshAgentConversationHeader()
                        renderAgentModelSelectionPage(
                            content.copy(selection = AgentModelSelectionSettings.selection(this@renderAgentModelSelectionPage, conversationId))
                        )
                    }
                }
            )
            if (selected && target.invocationProfile.configurable) {
                featureContent.addView(
                    agentModelConfigurationView(
                        conversationId = conversationId,
                        target = target,
                        selection = selection,
                        onChanged = {
                            refreshAgentConversationHeader()
                            renderAgentModelSelectionPage(
                                content.copy(selection = AgentModelSelectionSettings.selection(this@renderAgentModelSelectionPage, conversationId))
                            )
                        }
                    )
                )
            }
        }
    }

    val cloudTargets = targets
        .asSequence()
        .filter { target ->
            target.kind == AgentConnectorKind.MODEL &&
                target.status == AgentConnectorStatus.AVAILABLE &&
                target.id != "local-llm" &&
                target.id != "cloud-models" &&
                target.providerProfile?.modelId?.isNotBlank() == true
        }
        .distinctBy(AgentCallableTarget::id)
        .toList()
    if (cloudTargets.isNotEmpty()) {
        addSectionTitle(getString(R.string.agent_model_selection_cloud_section))
        cloudTargets.forEach { target ->
            val providerProfile = checkNotNull(target.providerProfile)
            val modelName = providerProfile.displayName
                .takeIf { it.isNotBlank() && !it.equals(target.title, ignoreCase = true) }
                ?: modelDisplayLabel(providerProfile.modelId)
            featureContent.addView(
                agentModelSelectionRow(
                    title = modelName,
                    subtitle = target.title,
                    iconRes = providerIcon(providerProfile.providerId.ifBlank { target.title }),
                    iconColor = Color.parseColor(providerColor(providerProfile.providerId.ifBlank { target.title })),
                    selected = preferredTargetId == target.id
                ).apply {
                    setOnClickListener {
                        AgentModelSelectionSettings.selectManual(
                            this@renderAgentModelSelectionPage,
                            conversationId = conversationId,
                            targetId = target.id,
                            modelId = providerProfile.modelId,
                            displayName = modelName
                        )
                        refreshAgentConversationHeader()
                        renderAgentModelSelectionPage(
                            content.copy(selection = AgentModelSelectionSettings.selection(this@renderAgentModelSelectionPage, conversationId))
                        )
                    }
                }
            )
        }
    }
}

internal fun MainActivity.agentModelTargetDisplayName(target: AgentCallableTarget): String = when {
    target.id == "local-llm" -> LocalModelRuntimeSettings.displayProfile(this).displayName
    target.providerProfile?.modelId?.isNotBlank() == true -> modelDisplayLabel(target.providerProfile.modelId)
    else -> target.title
}

internal fun MainActivity.agentModelSelectionRow(
    title: String,
    subtitle: String,
    iconRes: Int,
    iconColor: Int,
    selected: Boolean
): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    isClickable = true
    isFocusable = true
    addView(LinearLayout(this@agentModelSelectionRow).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(4), dp(10), dp(4), dp(10))
        addView(featureIcon(iconRes, iconColor), LinearLayout.LayoutParams(dp(44), dp(44)))
        addView(LinearLayout(this@agentModelSelectionRow).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), 0, dp(8), 0)
            addView(TextView(this@agentModelSelectionRow).apply {
                text = title
                textSize = 15.5f
                setTextColor(getColorCompat(R.color.text_primary))
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            })
            addView(TextView(this@agentModelSelectionRow).apply {
                text = subtitle
                textSize = 12f
                setTextColor(getColorCompat(R.color.text_secondary))
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            })
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        addView(TextView(this@agentModelSelectionRow).apply {
            text = getString(
                if (selected) R.string.agent_model_selection_selected else R.string.common_select
            )
            textSize = 12.5f
            gravity = Gravity.CENTER
            setTextColor(
                getColorCompat(if (selected) R.color.signalasi_green else R.color.text_secondary)
            )
            background = if (selected) GradientDrawable().apply {
                cornerRadius = dp(8).toFloat()
                setColor(adjustAlpha(getColorCompat(R.color.signalasi_green), 0.12f))
            } else null
        }, LinearLayout.LayoutParams(dp(58), dp(34)))
    }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(68)))
    addView(View(this@agentModelSelectionRow).apply {
        setBackgroundColor(adjustAlpha(getColorCompat(R.color.text_secondary), 0.18f))
    }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(1)).apply {
        marginStart = dp(60)
    })
}

private fun MainActivity.agentModelConfigurationView(
    conversationId: String,
    target: AgentCallableTarget,
    selection: AgentModelSelection,
    onChanged: () -> Unit
): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    setPadding(dp(60), 0, dp(4), dp(12))
    val profile = target.invocationProfile
    if (profile.models.isNotEmpty()) {
        addView(LinearLayout(this@agentModelConfigurationView).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            isClickable = true
            isFocusable = true
            setPadding(dp(12), 0, dp(4), 0)
            addView(TextView(this@agentModelConfigurationView).apply {
                text = getString(R.string.agent_model_selection_model)
                textSize = 12.5f
                setTextColor(getColorCompat(R.color.text_secondary))
            }, LinearLayout.LayoutParams(0, dp(48), 1f).apply { gravity = Gravity.CENTER_VERTICAL })
            val selectedModel = profile.models.firstOrNull { it.id == selection.modelId }
                ?: profile.models.firstOrNull { it.id == profile.defaultModelId }
                ?: profile.models.first()
            addView(TextView(this@agentModelConfigurationView).apply {
                text = "${selectedModel.displayName}  ›"
                textSize = 13.5f
                gravity = Gravity.CENTER_VERTICAL or Gravity.END
                setTextColor(getColorCompat(R.color.text_primary))
            }, LinearLayout.LayoutParams(0, dp(48), 1.5f))
            setOnClickListener {
                val labels = profile.models.map { model ->
                    if (model.description.isBlank()) {
                        model.displayName
                    } else {
                        "${model.displayName}\n${model.description}"
                    }
                }.toTypedArray()
                val checked = profile.models.indexOfFirst { it.id == selectedModel.id }.coerceAtLeast(0)
                AlertDialog.Builder(this@agentModelConfigurationView)
                    .setTitle(getString(R.string.agent_model_selection_model))
                    .setSingleChoiceItems(labels, checked) { dialog, which ->
                        AgentModelSelectionSettings.updateAgentConfiguration(
                            this@agentModelConfigurationView,
                            conversationId,
                            profile.models[which].id,
                            selection.reasoningEffort
                        )
                        dialog.dismiss()
                        onChanged()
                    }
                    .setNegativeButton(getString(R.string.common_cancel), null)
                    .show()
            }
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(48)))
    }

    if (profile.reasoningEfforts.isNotEmpty()) {
        addView(TextView(this@agentModelConfigurationView).apply {
            text = getString(R.string.agent_model_selection_reasoning_effort)
            textSize = 12f
            setTextColor(getColorCompat(R.color.text_secondary))
            setPadding(dp(12), dp(8), 0, dp(8))
        })
        val availableEfforts = profile.reasoningEfforts
        val selectedEffort = selection.reasoningEffort
            .takeIf { it in availableEfforts }
            ?: availableEfforts.first()
        addView(LinearLayout(this@agentModelConfigurationView).apply {
            orientation = LinearLayout.HORIZONTAL
            availableEfforts.forEachIndexed { index, effort ->
                addView(TextView(this@agentModelConfigurationView).apply {
                    text = getString(effort.labelResource())
                    textSize = 11.5f
                    gravity = Gravity.CENTER
                    setTextColor(
                        getColorCompat(
                            if (selectedEffort == effort) R.color.signalasi_green
                            else R.color.text_primary
                        )
                    )
                    background = GradientDrawable().apply {
                        cornerRadius = dp(7).toFloat()
                        setColor(
                            if (selectedEffort == effort) {
                                adjustAlpha(getColorCompat(R.color.signalasi_green), 0.12f)
                            } else {
                                adjustAlpha(getColorCompat(R.color.text_secondary), 0.08f)
                            }
                        )
                    }
                    setOnClickListener {
                        AgentModelSelectionSettings.updateAgentConfiguration(
                            this@agentModelConfigurationView,
                            conversationId,
                            profile.normalizedModelId(selection.modelId),
                            effort
                        )
                        onChanged()
                    }
                }, LinearLayout.LayoutParams(0, dp(36), 1f).apply {
                    if (index > 0) marginStart = dp(5)
                })
            }
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(36)).apply {
            marginStart = dp(12)
            marginEnd = dp(4)
        })
    }
    addView(TextView(this@agentModelConfigurationView).apply {
        text = getString(R.string.agent_model_selection_current_session)
        textSize = 11f
        setTextColor(getColorCompat(R.color.text_secondary))
        setPadding(dp(12), dp(8), 0, 0)
    })
}

internal fun AgentModelReasoningEffort.labelResource(): Int = when (this) {
    AgentModelReasoningEffort.AUTO -> R.string.agent_model_selection_effort_auto
    AgentModelReasoningEffort.LOW -> R.string.agent_model_selection_effort_low
    AgentModelReasoningEffort.MEDIUM -> R.string.agent_model_selection_effort_medium
    AgentModelReasoningEffort.HIGH -> R.string.agent_model_selection_effort_high
    AgentModelReasoningEffort.XHIGH -> R.string.agent_model_selection_effort_xhigh
}

internal fun MainActivity.showAgentConversationMultiDelete(showArchived: Boolean) {
    val candidates = agentTranscriptStore.conversations(includeArchived = true).filter { conversation ->
        if (showArchived) {
            conversation.status == AgentConversationStatus.ARCHIVED
        } else {
            conversation.status == AgentConversationStatus.ACTIVE
        }
    }
    if (candidates.isEmpty()) {
        Toast.makeText(this, getString(R.string.agent_session_no_results), Toast.LENGTH_SHORT).show()
        return
    }
    val selected = BooleanArray(candidates.size)
    val labels = candidates.map(::agentConversationDisplayTitle).toTypedArray()
    lateinit var selectionDialog: android.app.AlertDialog
    selectionDialog = android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_session_select_delete))
        .setMultiChoiceItems(labels, selected) { _, which, checked ->
            selected[which] = checked
            val count = selected.count { it }
            selectionDialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE)?.apply {
                isEnabled = count > 0
                text = getString(R.string.agent_session_delete_selected, count)
            }
        }
        .setPositiveButton(getString(R.string.agent_session_delete_selected, 0), null)
        .setNegativeButton(getString(R.string.common_cancel), null)
        .create()
    selectionDialog.setOnShowListener {
        selectionDialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE).apply {
            isEnabled = false
            setOnClickListener {
                val chosen = candidates.filterIndexed { index, _ -> selected[index] }
                if (chosen.isEmpty()) return@setOnClickListener
                android.app.AlertDialog.Builder(this@showAgentConversationMultiDelete)
                    .setTitle(getString(R.string.agent_session_delete_more))
                    .setMessage(getString(R.string.agent_session_delete_selected_confirm, chosen.size))
                    .setPositiveButton(getString(R.string.common_delete)) { _, _ ->
                        chosen.forEach(::deleteAgentConversationData)
                        selectionDialog.dismiss()
                        refreshAgentConversationHeader()
                        clearAgentTranscriptRows()
                        refreshAgentTranscriptWindow()
                        showAgentSessionsPage(showArchived)
                    }
                    .setNegativeButton(getString(R.string.common_cancel), null)
                    .show()
            }
        }
    }
    selectionDialog.show()
}

internal fun MainActivity.deleteAgentConversationData(conversation: AgentConversation) {
    if (conversation.mergedIntoConversationId.isBlank()) {
        val taskIds = agentTranscriptStore.taskIds(conversation.id)
        SignalASIMqttClient.publishAgentConversationDelete(conversation.id, taskIds)
        SQLiteAgentTaskStore(this).delete(taskIds + conversation.id)
    }
    agentTranscriptStore.deleteConversation(conversation.id)
}

internal fun MainActivity.confirmDeleteAgentConversation(conversation: AgentConversation, showArchived: Boolean) {
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_session_delete))
        .setMessage(getString(R.string.agent_session_delete_confirm))
        .setPositiveButton(getString(R.string.common_delete)) { _, _ ->
            deleteAgentConversationData(conversation)
            refreshAgentConversationHeader()
            refreshAgentTranscriptWindow()
            showAgentSessionsPage(showArchived)
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.showAgentConversationActions(conversation: AgentConversation) {
    val actions = mutableListOf<Pair<String, () -> Unit>>()
    actions += getString(R.string.agent_session_rename) to {
        showTextSettingDialog(getString(R.string.agent_session_rename), conversation.title) {
            agentTranscriptStore.renameConversation(conversation.id, it)
            showAgentSessionsPage()
        }
    }
    if (canMergeAgentConversation(conversation)) {
        actions += getString(R.string.agent_session_merge_into_original) to {
            confirmMergeAgentConversation(conversation)
        }
    }
    actions += getString(if (conversation.pinned) R.string.agent_session_unpin else R.string.agent_session_pin) to {
        agentTranscriptStore.setPinned(conversation.id, !conversation.pinned)
        showAgentSessionsPage()
    }
    if (conversation.mergedIntoConversationId.isBlank()) {
        actions += getString(if (conversation.privateMode) R.string.agent_session_standard else R.string.agent_session_private) to {
            agentTranscriptStore.setPrivateMode(conversation.id, !conversation.privateMode)
            showAgentSessionsPage()
        }
        actions += getString(
            if (conversation.trackingPaused) R.string.agent_session_resume_tracking
            else R.string.agent_session_pause_tracking
        ) to {
            agentTranscriptStore.setTrackingPaused(conversation.id, !conversation.trackingPaused)
            showAgentSessionsPage()
        }
    }
    actions += getString(R.string.agent_session_context_policy) to {
        showAgentConversationContextPolicy(conversation)
    }
    actions += getString(R.string.agent_session_summary) to {
        showTextSettingDialog(getString(R.string.agent_session_summary), conversation.summary) {
            agentTranscriptStore.updateSummary(conversation.id, it)
            showAgentSessionsPage()
        }
    }
    actions += getString(R.string.agent_session_details) to {
        showAgentConversationDetails(conversation)
    }
    if (conversation.mergedIntoConversationId.isBlank()) {
        actions += getString(
            if (conversation.status == AgentConversationStatus.ARCHIVED) R.string.agent_session_restore
            else R.string.agent_session_archive
        ) to {
            if (conversation.status == AgentConversationStatus.ARCHIVED) {
                agentTranscriptStore.restoreConversation(conversation.id)
            } else {
                agentTranscriptStore.archiveConversation(conversation.id)
            }
            showAgentSessionsPage()
        }
    }
    actions += getString(R.string.agent_session_delete) to {
        confirmDeleteAgentConversation(conversation, conversation.status == AgentConversationStatus.ARCHIVED)
    }
    actions += getString(R.string.agent_session_delete_more) to {
        showAgentConversationMultiDelete(conversation.status == AgentConversationStatus.ARCHIVED)
    }
    android.app.AlertDialog.Builder(this)
        .setTitle(conversation.title)
        .setItems(actions.map(Pair<String, () -> Unit>::first).toTypedArray()) { _, which ->
            actions[which].second.invoke()
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.canMergeAgentConversation(conversation: AgentConversation): Boolean {
    if (!conversation.createdByAgent || conversation.parentConversationId.isBlank() ||
        conversation.mergedIntoConversationId.isNotBlank()
    ) return false
    val parent = agentTranscriptStore.conversation(conversation.parentConversationId) ?: return false
    return parent.privateMode == conversation.privateMode
}

internal fun MainActivity.confirmMergeAgentConversation(conversation: AgentConversation) {
    val target = agentTranscriptStore.conversation(conversation.parentConversationId)
    if (target == null) {
        Toast.makeText(this, getString(R.string.agent_session_merge_target_missing), Toast.LENGTH_SHORT).show()
        return
    }
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_session_merge_into_original))
        .setMessage(getString(R.string.agent_session_merge_confirm, conversation.title, target.title))
        .setPositiveButton(getString(R.string.agent_session_merge_confirm_action)) { _, _ ->
            val result = agentTranscriptStore.mergeConversationIntoParent(conversation.id)
            if (!result.merged) {
                Toast.makeText(
                    this,
                    getString(agentConversationMergeFailureMessage(result.failure)),
                    Toast.LENGTH_SHORT
                ).show()
                return@setPositiveButton
            }
            val targetId = result.targetConversation?.id.orEmpty()
            agentRuntimeConversationIds.entries.toList()
                .filter { it.value == conversation.id }
                .forEach { agentRuntimeConversationIds[it.key] = targetId }
            agentSessionsDialog?.dismiss()
            resetAgentTranscriptRendering(targetId)
            showMainTab(PAGE_AGENT)
            refreshAgentConversationHeader()
            refreshAgentTranscriptWindow(targetId)
            refreshGlobalAgentCognition()
            Toast.makeText(
                this,
                getString(R.string.agent_session_merge_success, result.copiedEntryCount),
                Toast.LENGTH_SHORT
            ).show()
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.agentConversationMergeFailureMessage(failure: AgentConversationMergeFailure): Int = when (failure) {
    AgentConversationMergeFailure.ALREADY_MERGED -> R.string.agent_session_merge_already_done
    AgentConversationMergeFailure.PRIVACY_MISMATCH -> R.string.agent_session_merge_privacy_mismatch
    else -> R.string.agent_session_merge_unavailable
}

internal fun MainActivity.showAgentConversationContextPolicy(conversation: AgentConversation) {
    val labels = listOf(
        getString(R.string.agent_session_context_minimal),
        getString(R.string.agent_session_context_balanced),
        getString(R.string.agent_session_context_extended)
    )
    val values = listOf("minimal", "balanced", "extended")
    val selected = values.indexOf(conversation.contextPolicy).coerceAtLeast(1)
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_session_context_policy))
        .setSingleChoiceItems(labels.toTypedArray(), selected) { dialog, which ->
            agentTranscriptStore.setContextPolicy(conversation.id, values[which])
            dialog.dismiss()
            showAgentSessionsPage()
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

private data class AgentConversationDetailsContent(
    val metrics: AgentConversationMetrics,
    val contextPreview: AgentConversationContext,
    val sessionTasks: List<AgentTaskRecord>
)

internal fun MainActivity.showAgentConversationDetails(conversation: AgentConversation) {
    showFeaturePage(getString(R.string.agent_session_details))
    setFeatureBackAction { showAgentSessionsPage() }
    featureContent.addView(featureValueRow(
        getString(R.string.navigation_content_loading),
        "",
        R.drawable.ic_agent_history,
        ""
    ))
    val generation = navigationContentGate.begin()
    navigationContentExecutor.execute {
        val content = runCatching {
            AgentConversationDetailsContent(
                metrics = agentTranscriptStore.metrics(conversation.id),
                contextPreview = agentTranscriptStore.context(conversation.id),
                sessionTasks = SQLiteAgentTaskStore(this).forSession(conversation.id)
            )
        }.getOrNull()
        handler.post {
            if (content != null && navigationContentGate.isCurrent(generation) &&
                featurePage.visibility == View.VISIBLE
            ) {
                renderAgentConversationDetails(conversation, content)
            }
        }
    }
}

private fun MainActivity.renderAgentConversationDetails(
    conversation: AgentConversation,
    content: AgentConversationDetailsContent
) {
    val metrics = content.metrics
    val contextPreview = content.contextPreview
    val sessionTasks = content.sessionTasks
    featureContent.removeAllViews()
    featureContent.addView(featureHeroCard(
        conversation.title,
        conversation.selectedModelOrAgent,
        R.drawable.ic_agent_history,
        "#14C66A",
        if (conversation.privateMode) getString(R.string.agent_session_private) else getString(R.string.agent_session_standard)
    ))
    addSectionTitle(getString(R.string.agent_session_details))
    featureContent.addView(featureValueRow(
        getString(R.string.agent_session_turns), "", R.drawable.ic_agent_history, metrics.turnCount.toString()
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.agent_session_tasks), "", R.drawable.ic_agent_node, metrics.taskCount.toString()
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.agent_session_context_tokens), "", R.drawable.ic_protocol_link,
        metrics.estimatedContextTokens.toString()
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.agent_session_input_tokens), "", R.drawable.ic_protocol_link,
        metrics.inputTokens.takeIf { it > 0L }?.toString() ?: "-"
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.agent_session_output_tokens), "", R.drawable.ic_protocol_link,
        metrics.outputTokens.takeIf { it > 0L }?.toString() ?: "-"
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.agent_session_latency), "", R.drawable.ic_protocol_link,
        if (metrics.lastResponseLatencyMillis > 0L) "${metrics.lastResponseLatencyMillis / 1000.0}s" else "-"
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.agent_session_cost), "", R.drawable.ic_security_shield,
        if (metrics.costMicros > 0L) String.format(Locale.US, "$%.6f", metrics.costMicros / 1_000_000.0)
        else getString(R.string.agent_session_cost_unavailable)
    ))
    addSectionTitle(getString(R.string.agent_session_context_preview))
    featureContent.addView(featureRow(
        getString(R.string.agent_session_summary),
        conversation.summary.ifBlank { getString(R.string.agent_session_summary_empty) },
        R.drawable.ic_agent_memory,
        "›"
    ).apply {
        setOnClickListener {
        showTextSettingDialog(getString(R.string.agent_session_summary), conversation.summary) {
            agentTranscriptStore.updateSummary(conversation.id, it)
            showAgentConversationDetails(
                agentTranscriptStore.conversations(includeArchived = true)
                .firstOrNull { item -> item.id == conversation.id } ?: conversation
            )
        }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.agent_session_recent_context),
        getString(R.string.agent_session_context_messages, contextPreview.turns.size),
        R.drawable.ic_protocol_link,
        "›"
    ).apply {
        setOnClickListener {
        android.app.AlertDialog.Builder(this@renderAgentConversationDetails)
            .setTitle(getString(R.string.agent_session_recent_context))
            .setMessage(contextPreview.asPromptBlock())
            .setPositiveButton(android.R.string.ok, null)
            .show()
        }
    })
    addSectionTitle(getString(R.string.agent_session_tasks))
    if (sessionTasks.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.agent_recent_empty), "", R.drawable.ic_agent_history, ""
        ))
    } else {
        sessionTasks.forEachIndexed { index, task ->
            featureContent.addView(agentRecentTaskRow(task, index))
        }
    }
}
