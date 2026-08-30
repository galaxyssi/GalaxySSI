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

internal fun MainActivity.showVoiceAssistantSettingsPage() {
    val config = VoiceAssistantSettings.get(this)
    showFeaturePage(getString(R.string.voice_settings_title))
    featureContent.addView(featureHeroCard(
        getString(R.string.voice_low_power_title),
        getString(R.string.voice_low_power_subtitle),
        R.drawable.ic_input_voice,
        "#00EFDE",
        onOffLabel(config.enabled)
    ))
    voiceHealthRows.clear()
    addSectionTitle(getString(R.string.voice_health_section))
    val health = voiceRealtimeHealth(config)
    VoiceHealthComponent.entries.forEach { component ->
        featureContent.addView(voiceHealthRow(health[component]))
    }
    startVoiceHealthMonitoring()
    addSectionTitle(getString(R.string.voice_section_listening))
    featureContent.addView(featureRow(getString(R.string.voice_low_power_monitor), getString(R.string.voice_low_power_monitor_subtitle), R.drawable.ic_input_voice, onOffLabel(config.enabled)).apply {
        setOnClickListener {
            VoiceAssistantSettings.setEnabled(this@showVoiceAssistantSettingsPage, !config.enabled)
            showVoiceAssistantSettingsPage()
        }
    })
    featureContent.addView(featureRow(getString(R.string.voice_wake_engine), wakeProviderLabel(config.wakeProvider), R.drawable.ic_agent_node, getString(R.string.common_select)).apply {
        setOnClickListener {
            val openWakeWord = getString(R.string.voice_wake_engine_openwakeword)
            val androidAsr = getString(R.string.voice_wake_engine_android_asr)
            showChoiceDialog(getString(R.string.voice_wake_engine), listOf(openWakeWord, androidAsr), wakeProviderLabel(config.wakeProvider)) {
                val provider = if (it == openWakeWord) {
                    VoiceAssistantSettings.WAKE_PROVIDER_OPEN_WAKE_WORD
                } else {
                    VoiceAssistantSettings.WAKE_PROVIDER_ANDROID_ASR
                }
                VoiceAssistantSettings.setWakeProvider(this@showVoiceAssistantSettingsPage, provider)
                showVoiceAssistantSettingsPage()
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.voice_wake_words),
        WakeWordPolicy.WAKE_WORD,
        R.drawable.ic_protocol_link,
        ""
    ))
    featureContent.addView(featureRow(getString(R.string.voice_openwakeword_model), config.wakeModel, R.drawable.ic_protocol_link, getString(R.string.common_select)).apply {
        setOnClickListener {
            showChoiceDialog(getString(R.string.voice_openwakeword_model), VoiceAssistantSettings.SUPPORTED_WAKE_MODELS, config.wakeModel) {
                VoiceAssistantSettings.setWakeModel(this@showVoiceAssistantSettingsPage, it)
                showVoiceAssistantSettingsPage()
            }
        }
    })
    featureContent.addView(featureRow(getString(R.string.voice_wake_threshold), "%.2f".format(Locale.US, config.wakeThreshold), R.drawable.ic_security_shield, getString(R.string.common_edit)).apply {
        setOnClickListener {
            showTextSettingDialog(getString(R.string.voice_wake_threshold), "%.2f".format(Locale.US, config.wakeThreshold)) {
                VoiceAssistantSettings.setWakeThreshold(this@showVoiceAssistantSettingsPage, it.toFloatOrNull() ?: config.wakeThreshold)
                showVoiceAssistantSettingsPage()
            }
        }
    })
    addSectionTitle(getString(R.string.voice_section_asr))
    featureContent.addView(featureRow(
        getString(R.string.voice_asr_provider),
        getString(R.string.voice_asr_provider_local_whisper, WhisperModelManager.model(config.asrModel).displayName),
        R.drawable.ic_agent_node,
        getString(R.string.common_select)
    ).apply {
        setOnClickListener { showAsrProviderPage() }
    })
    featureContent.addView(featureRow(getString(R.string.voice_asr_language), languagePolicyLabel(config.asrLanguage), R.drawable.ic_protocol_link, getString(R.string.common_select)).apply {
        setOnClickListener {
            showLanguagePolicyDialog(getString(R.string.voice_asr_language), config.asrLanguage) {
                VoiceAssistantSettings.setAsrLanguage(this@showVoiceAssistantSettingsPage, it)
                configureAndroidTtsLanguage()
                showVoiceAssistantSettingsPage()
            }
        }
    })

    addSectionTitle(getString(R.string.voice_section_tts))
    featureContent.addView(featureRow(
        getString(R.string.voice_tts_provider),
        ttsProviderLabel(config.ttsProvider),
        R.drawable.ic_send_plane,
        voiceCapabilityStatus(activeTtsCapability(config))
    ).apply {
        setOnClickListener { showTtsProviderPage() }
    })
    featureContent.addView(featureRow(getString(R.string.language_policy_tts_language), languagePolicyLabel(config.ttsLanguage), R.drawable.ic_settings_language, getString(R.string.common_select)).apply {
        setOnClickListener {
            showLanguagePolicyDialog(getString(R.string.language_policy_tts_language), config.ttsLanguage) {
                VoiceAssistantSettings.setTtsLanguage(this@showVoiceAssistantSettingsPage, it)
                configureAndroidTtsLanguage()
                showVoiceAssistantSettingsPage()
            }
        }
    })
    featureContent.addView(featureRow(getString(R.string.voice_microsoft_voice), config.microsoftVoice, R.drawable.ic_protocol_link, getString(R.string.common_edit)).apply {
        setOnClickListener {
            showTextSettingDialog(getString(R.string.voice_microsoft_voice), config.microsoftVoice) {
                VoiceAssistantSettings.setMicrosoftVoice(this@showVoiceAssistantSettingsPage, it)
                showVoiceAssistantSettingsPage()
            }
        }
    })
    featureContent.addView(featureRow(getString(R.string.voice_welcome_text), config.welcomeText, R.drawable.ic_send_plane, getString(R.string.common_edit)).apply {
        setOnClickListener {
            showTextSettingDialog(getString(R.string.voice_welcome_text), config.welcomeText) {
                VoiceAssistantSettings.setWelcomeText(this@showVoiceAssistantSettingsPage, it)
                showVoiceAssistantSettingsPage()
            }
        }
    })
    featureContent.addView(featureRow(getString(R.string.voice_speak_replies), getString(R.string.voice_speak_replies_subtitle), R.drawable.ic_send_plane, onOffLabel(config.speakReplies)).apply {
        setOnClickListener {
            VoiceAssistantSettings.setSpeakReplies(this@showVoiceAssistantSettingsPage, !config.speakReplies)
            showVoiceAssistantSettingsPage()
        }
    })

    addSectionTitle(getString(R.string.voice_section_target))
    featureContent.addView(featureRow(
        getString(R.string.voice_routing_mode),
        getString(R.string.voice_routing_mode_subtitle),
        R.drawable.ic_agent_node,
        voiceRoutingModeLabel(config.routingMode)
    ).apply {
        setOnClickListener {
            val nativeAgent = getString(R.string.voice_routing_native_agent)
            val contactChat = getString(R.string.voice_routing_contact)
            showChoiceDialog(
                getString(R.string.voice_routing_mode),
                listOf(nativeAgent, contactChat),
                voiceRoutingModeLabel(config.routingMode)
            ) { selected ->
                VoiceAssistantSettings.setRoutingMode(
                    this@showVoiceAssistantSettingsPage,
                    if (selected == nativeAgent) VoiceAssistantSettings.ROUTING_MODE_NATIVE_AGENT
                    else VoiceAssistantSettings.ROUTING_MODE_CONTACT
                )
                showVoiceAssistantSettingsPage()
            }
        }
    })
    val targetContact = voiceAssistantTargetContact(config)
    val targetTitle = if (config.routingMode == VoiceAssistantSettings.ROUTING_MODE_NATIVE_AGENT) {
        getString(R.string.voice_stt_target)
    } else {
        getString(R.string.voice_default_target)
    }
    featureContent.addView(featureRow(targetTitle, targetContact.name, R.drawable.hermes_logo, getString(R.string.common_select)).apply {
        setOnClickListener {
            val contacts = storedContacts().filter { contact ->
                if (config.routingMode == VoiceAssistantSettings.ROUTING_MODE_NATIVE_AGENT) {
                    AppStore.usesPcConnectorTunnel(this@showVoiceAssistantSettingsPage, contact.id) &&
                        AppStore.outgoingTopicForContact(this@showVoiceAssistantSettingsPage, contact.id) != null
                } else {
                    AppStore.canCommunicateWith(this@showVoiceAssistantSettingsPage, contact.id)
                }
            }.ifEmpty { listOf(CONTACT_HERMES) }
            val labels = contacts.map { "${it.name} (${it.id})" }
            val current = contacts.indexOfFirst { it.id == targetContact.id }.coerceAtLeast(0)
            android.app.AlertDialog.Builder(this@showVoiceAssistantSettingsPage)
                .setTitle(targetTitle)
                .setSingleChoiceItems(labels.toTypedArray(), current) { dialog, which ->
                    VoiceAssistantSettings.setTargetContact(this@showVoiceAssistantSettingsPage, contacts[which].id)
                    dialog.dismiss()
                    showVoiceAssistantSettingsPage()
                }
                .setNegativeButton(getString(R.string.common_cancel), null)
                .show()
        }
    })
}

internal fun MainActivity.showAsrProviderPage() {
    handler.removeCallbacks(asrModelDownloadPoll)
    val config = VoiceAssistantSettings.get(this)
    val selected = WhisperModelManager.model(config.asrModel)
    val capabilities = voiceProviderCapabilities(config)
    val whisperCapability = capabilities[VoiceProviderCapabilityId.WHISPER_CPP]
    showFeaturePage(getString(R.string.voice_asr_provider))
    setFeatureBackAction { showVoiceAssistantSettingsPage() }
    featureContent.addView(featureHeroCard(
        getString(R.string.voice_asr_local_title),
        getString(R.string.voice_asr_local_subtitle),
        R.drawable.ic_agent_node,
        if (whisperCapability.ready) "#14C66A" else "#D48B18",
        voiceCapabilityStatus(whisperCapability)
    ))
    val onlineRealtimeEnabled = VoiceFeatureFlags.isOnlineRealtimeAsrEnabled(this)
    val remoteWhisperEnabled = VoiceFeatureFlags.isRemoteWhisperNodeEnabled(this)
    if (onlineRealtimeEnabled || remoteWhisperEnabled) {
        addSectionTitle(getString(R.string.voice_asr_recognition_mode_section))
        featureContent.addView(featureRow(
            getString(R.string.voice_asr_recognition_mode_title),
            getString(R.string.voice_asr_recognition_mode_subtitle),
            R.drawable.ic_input_voice,
            voiceRecognitionPreferenceLabel(config.recognitionPreference)
        ).apply {
            setOnClickListener { showVoiceRecognitionPreferenceDialog(config.recognitionPreference) }
        })
    }
    if (onlineRealtimeEnabled) {
        addSectionTitle(getString(R.string.voice_asr_online_privacy_section))
        featureContent.addView(featureSwitchRow(
            getString(R.string.voice_asr_online_allowed_title),
            getString(R.string.voice_asr_online_allowed_subtitle),
            R.drawable.ic_avatar_cloud_model,
            config.onlineAsrPrivacy.allowOnlineVoice && config.onlineAsrPrivacy.allowRawAudioUpload
        ).apply {
            setOnClickListener { toggleOnlineRealtimeAsr(config) }
        })
        featureContent.addView(featureSwitchRow(
            getString(R.string.voice_asr_wifi_only_title),
            getString(R.string.voice_asr_wifi_only_subtitle),
            R.drawable.ic_resource_network,
            config.onlineAsrPrivacy.wifiOnly
        ).apply {
            setOnClickListener {
                VoiceAssistantSettings.setOnlineAsrPrivacy(
                    this@showAsrProviderPage,
                    config.onlineAsrPrivacy.copy(wifiOnly = !config.onlineAsrPrivacy.wifiOnly)
                )
                showAsrProviderPage()
            }
        })
        featureContent.addView(featureSwitchRow(
            getString(R.string.voice_asr_server_delete_title),
            getString(R.string.voice_asr_server_delete_subtitle),
            R.drawable.ic_security_shield,
            config.onlineAsrPrivacy.requestServerDataDeletion
        ).apply {
            setOnClickListener {
                VoiceAssistantSettings.setOnlineAsrPrivacy(
                    this@showAsrProviderPage,
                    config.onlineAsrPrivacy.copy(
                        requestServerDataDeletion = !config.onlineAsrPrivacy.requestServerDataDeletion
                    )
                )
                showAsrProviderPage()
            }
        })
    }
    if (remoteWhisperEnabled) {
        val remoteNode = RemoteWhisperNodeRegistry.best(this)
        addSectionTitle(getString(R.string.voice_asr_remote_section))
        featureContent.addView(featureSwitchRow(
            getString(R.string.voice_asr_remote_allowed_title),
            getString(R.string.voice_asr_remote_allowed_subtitle),
            R.drawable.ic_agent_node,
            config.remoteWhisperAllowed
        ).apply {
            setOnClickListener {
                if (config.remoteWhisperAllowed) {
                    VoiceAssistantSettings.setRemoteWhisperAllowed(this@showAsrProviderPage, false)
                    if (config.recognitionPreference == VoiceRecognitionPreference.REMOTE_NODE) {
                        VoiceAssistantSettings.setRecognitionPreference(
                            this@showAsrProviderPage,
                            VoiceRecognitionPreference.AUTO
                        )
                        VoiceAssistantSettings.setAsrProvider(
                            this@showAsrProviderPage,
                            VoiceAssistantSettings.ASR_PROVIDER_AUTO
                        )
                    }
                    showAsrProviderPage()
                } else {
                    android.app.AlertDialog.Builder(this@showAsrProviderPage)
                        .setTitle(getString(R.string.voice_asr_remote_consent_title))
                        .setMessage(getString(R.string.voice_asr_remote_consent_message))
                        .setNegativeButton(getString(R.string.common_cancel), null)
                        .setPositiveButton(getString(R.string.common_enable)) { _, _ ->
                            VoiceAssistantSettings.setRemoteWhisperAllowed(this@showAsrProviderPage, true)
                            showAsrProviderPage()
                        }
                        .show()
                }
            }
        })
        featureContent.addView(featureRow(
            getString(R.string.voice_asr_remote_node_title),
            remoteNode?.activeProfile?.modelName
                ?: getString(R.string.voice_asr_remote_node_unavailable),
            R.drawable.ic_device_node,
            remoteNode?.desktopName.orEmpty()
        ).apply {
            isClickable = false
            isFocusable = false
        })
    }
    addSectionTitle(getString(R.string.voice_provider_device_capabilities))
    listOf(
        VoiceProviderCapabilityId.WHISPER_CPP to R.drawable.ic_local_model,
        VoiceProviderCapabilityId.ANDROID_SYSTEM_ASR to R.drawable.ic_input_voice,
        VoiceProviderCapabilityId.ANDROID_OFFLINE_ASR to R.drawable.ic_security_shield,
        VoiceProviderCapabilityId.CLOUD_ASR to R.drawable.ic_avatar_cloud_model
    ).forEach { (id, icon) ->
        val capability = capabilities[id]
        featureContent.addView(featureRow(
            voiceCapabilityTitle(id),
            voiceCapabilityDetail(capability),
            icon,
            voiceCapabilityStatus(capability)
        ).apply {
            if (capability.state == VoiceProviderCapabilityState.NEEDS_PERMISSION) {
                setOnClickListener {
                    requestPermissions(
                        arrayOf(android.Manifest.permission.RECORD_AUDIO),
                        REQUEST_CONTROL_CENTER_PERMISSION
                    )
                }
            } else {
                isClickable = false
                isFocusable = false
            }
        })
    }
    if (VoiceFeatureFlags.isWhisperPolicyEngineEnabled(this)) {
        addSectionTitle(getString(R.string.voice_asr_runtime_mode_section))
        featureContent.addView(featureRow(
            getString(R.string.voice_asr_runtime_mode_title),
            getString(R.string.voice_asr_runtime_mode_subtitle),
            R.drawable.ic_settings_model,
            whisperRuntimeModeLabel(config.asrRuntimeMode)
        ).apply {
            setOnClickListener { showWhisperRuntimeModeDialog(config.asrRuntimeMode) }
        })
    }
    var hasActiveDownload = false
    val qnnPackages = QnnWhisperPackageManager.supportedPackages(this)
    val largeTurboState = LargeTurboQnnModelManager.state(this) { showAsrProviderPage() }
    val largeTurboDecision = LargeTurboQnnModelManager.deviceDecision(this)
    val largeTurboSupported = largeTurboDecision.eligibility != QnnAsrEligibility.FALLBACK_REQUIRED
    if (largeTurboSupported || qnnPackages.isNotEmpty()) {
        addSectionTitle(getString(R.string.voice_asr_qnn_section))
    }
    if (largeTurboSupported) {
        hasActiveDownload = hasActiveDownload || LargeTurboQnnModelManager.hasActiveWork()
        val isSelected = config.asrAcceleration == VoiceAssistantSettings.ASR_ACCELERATION_QNN &&
            config.asrModel == LargeTurboQnnModelManager.PROFILE_ID
        val action = largeTurboQnnModelAction(largeTurboState, isSelected, supported = true)
        val lifecycleDetail = when (largeTurboState.status) {
            LargeTurboQnnModelStatus.CHECKING -> getString(R.string.voice_provider_checking)
            LargeTurboQnnModelStatus.NOT_INSTALLED -> getString(R.string.voice_asr_model_download_size)
            LargeTurboQnnModelStatus.DOWNLOADING ->
                getString(R.string.voice_asr_model_progress, largeTurboState.progress)
            LargeTurboQnnModelStatus.PAUSED -> getString(R.string.local_model_download_paused)
            LargeTurboQnnModelStatus.VERIFYING -> getString(R.string.voice_asr_model_verifying)
            LargeTurboQnnModelStatus.INSTALLING -> getString(R.string.voice_asr_model_installing)
            LargeTurboQnnModelStatus.READY -> getString(R.string.voice_asr_qnn_ready)
            LargeTurboQnnModelStatus.FAILED -> getString(
                R.string.voice_asr_model_install_failed,
                largeTurboState.detail.ifBlank { "UNKNOWN" }
            )
        }
        val actionLabel = when (action) {
            LargeTurboQnnModelAction.DOWNLOAD -> getString(R.string.voice_asr_model_download)
            LargeTurboQnnModelAction.RESUME -> getString(R.string.local_model_resume_action)
            LargeTurboQnnModelAction.PAUSE -> getString(R.string.local_model_pause_action)
            LargeTurboQnnModelAction.RETRY -> getString(R.string.common_retry)
            LargeTurboQnnModelAction.USE -> getString(R.string.settings_language_use)
            LargeTurboQnnModelAction.CURRENT -> getString(R.string.section_current)
            LargeTurboQnnModelAction.WAIT -> getString(R.string.voice_provider_checking)
            LargeTurboQnnModelAction.UNSUPPORTED -> ""
        }
        featureContent.addView(featureRow(
            LargeTurboQnnModelManager.manifest.displayName,
            getString(
                R.string.voice_asr_qnn_detail,
                LargeTurboQnnModelManager.sizeLabel(),
                lifecycleDetail
            ),
            R.drawable.ic_local_model,
            actionLabel
        ).apply {
            isClickable = action !in setOf(
                LargeTurboQnnModelAction.CURRENT,
                LargeTurboQnnModelAction.WAIT,
                LargeTurboQnnModelAction.UNSUPPORTED
            )
            isFocusable = isClickable
            if (isClickable) setOnClickListener {
                when (action) {
                    LargeTurboQnnModelAction.PAUSE -> {
                        LargeTurboQnnModelManager.pause(this@showAsrProviderPage) { showAsrProviderPage() }
                        showAsrProviderPage()
                    }
                    LargeTurboQnnModelAction.USE -> {
                        LargeTurboQnnModelManager.select(this@showAsrProviderPage)
                        prepareHighAccuracyAsrIfSelected()
                        Toast.makeText(
                            this@showAsrProviderPage,
                            getString(
                                R.string.voice_asr_model_ready,
                                LargeTurboQnnModelManager.manifest.displayName
                            ),
                            Toast.LENGTH_SHORT
                        ).show()
                        showAsrProviderPage()
                    }
                    LargeTurboQnnModelAction.DOWNLOAD,
                    LargeTurboQnnModelAction.RESUME,
                    LargeTurboQnnModelAction.RETRY -> {
                        startLargeTurboQnnModelDownload()
                    }
                    else -> Unit
                }
            }
            if (largeTurboState.status == LargeTurboQnnModelStatus.READY && !isSelected) {
                setOnLongClickListener {
                    android.app.AlertDialog.Builder(this@showAsrProviderPage)
                        .setTitle(getString(
                            R.string.voice_asr_model_remove_title,
                            LargeTurboQnnModelManager.manifest.displayName
                        ))
                        .setMessage(getString(R.string.voice_asr_qnn_remove_message))
                        .setNegativeButton(getString(R.string.common_cancel), null)
                        .setPositiveButton(getString(R.string.voice_asr_model_remove)) { _, _ ->
                            LargeTurboQnnModelManager.delete(this@showAsrProviderPage) { showAsrProviderPage() }
                            showAsrProviderPage()
                        }
                        .show()
                    true
                }
            }
        })
    }
    if (qnnPackages.isNotEmpty()) {
        qnnPackages.forEach { modelPackage ->
            val state = QnnWhisperPackageManager.state(this, modelPackage)
            val isSelected = config.asrAcceleration == VoiceAssistantSettings.ASR_ACCELERATION_QNN &&
                config.asrQnnPackage == modelPackage.id
            val isActive = state.status == QnnWhisperPackageStatus.DOWNLOADING ||
                state.status == QnnWhisperPackageStatus.VERIFYING
            hasActiveDownload = hasActiveDownload || isActive
            val lifecycleDetail = when (state.status) {
                QnnWhisperPackageStatus.DOWNLOADING ->
                    getString(R.string.voice_asr_model_progress, state.progress)
                QnnWhisperPackageStatus.VERIFYING ->
                    getString(R.string.voice_asr_model_verifying)
                QnnWhisperPackageStatus.READY ->
                    getString(R.string.voice_asr_qnn_ready)
                QnnWhisperPackageStatus.FAILED ->
                    getString(
                        R.string.voice_asr_model_install_failed,
                        state.detail.ifBlank { "UNKNOWN" }
                    )
                QnnWhisperPackageStatus.NOT_INSTALLED ->
                    getString(R.string.voice_asr_model_download_size)
            }
            val subtitle = getString(
                R.string.voice_asr_qnn_detail,
                modelPackage.sizeLabel,
                lifecycleDetail
            )
            val action = when {
                isSelected && state.status == QnnWhisperPackageStatus.READY ->
                    getString(R.string.section_current)
                state.status == QnnWhisperPackageStatus.READY ->
                    getString(R.string.settings_language_use)
                state.status == QnnWhisperPackageStatus.DOWNLOADING ->
                    getString(R.string.voice_asr_model_cancel)
                state.status == QnnWhisperPackageStatus.VERIFYING ->
                    getString(R.string.voice_asr_model_verifying)
                state.status == QnnWhisperPackageStatus.FAILED ->
                    getString(R.string.common_retry)
                else -> getString(R.string.voice_asr_model_download)
            }
            featureContent.addView(featureRow(
                modelPackage.displayName,
                subtitle,
                R.drawable.ic_local_model,
                action
            ).apply {
                isClickable = state.status != QnnWhisperPackageStatus.VERIFYING
                isFocusable = isClickable
                setOnClickListener(if (isClickable) View.OnClickListener {
                    when (state.status) {
                        QnnWhisperPackageStatus.DOWNLOADING -> {
                            android.app.AlertDialog.Builder(this@showAsrProviderPage)
                                .setTitle(getString(R.string.voice_asr_model_cancel_title))
                                .setMessage(getString(
                                    R.string.voice_asr_model_cancel_message,
                                    modelPackage.displayName
                                ))
                                .setNegativeButton(
                                    getString(R.string.voice_asr_model_keep_downloading),
                                    null
                                )
                                .setPositiveButton(getString(R.string.voice_asr_model_cancel)) { _, _ ->
                                    QnnWhisperPackageManager.cancel(this@showAsrProviderPage, modelPackage)
                                    showAsrProviderPage()
                                }
                                .show()
                        }
                        QnnWhisperPackageStatus.READY -> {
                            if (!isSelected) {
                                QnnWhisperPackageManager.select(this@showAsrProviderPage, modelPackage)
                                Toast.makeText(
                                    this@showAsrProviderPage,
                                    getString(
                                        R.string.voice_asr_model_ready,
                                        modelPackage.displayName
                                    ),
                                    Toast.LENGTH_SHORT
                                ).show()
                                ensureWhisperMicrophonePermission()
                            }
                            showAsrProviderPage()
                        }
                        QnnWhisperPackageStatus.NOT_INSTALLED,
                        QnnWhisperPackageStatus.FAILED -> {
                            QnnWhisperPackageManager.enqueue(this@showAsrProviderPage, modelPackage)
                            Toast.makeText(
                                this@showAsrProviderPage,
                                getString(
                                    R.string.voice_asr_model_download_started,
                                    modelPackage.displayName
                                ),
                                Toast.LENGTH_SHORT
                            ).show()
                            handler.post(asrModelDownloadPoll)
                        }
                        QnnWhisperPackageStatus.VERIFYING -> Unit
                    }
                } else null)
                if (state.status == QnnWhisperPackageStatus.READY && !isSelected) {
                    setOnLongClickListener {
                        android.app.AlertDialog.Builder(this@showAsrProviderPage)
                            .setTitle(getString(
                                R.string.voice_asr_model_remove_title,
                                modelPackage.displayName
                            ))
                            .setMessage(getString(R.string.voice_asr_qnn_remove_message))
                            .setNegativeButton(getString(R.string.common_cancel), null)
                            .setPositiveButton(getString(R.string.voice_asr_model_remove)) { _, _ ->
                                QnnWhisperPackageManager.delete(this@showAsrProviderPage, modelPackage)
                                showAsrProviderPage()
                            }
                            .show()
                        true
                    }
                }
            })
        }
    }
    addSectionTitle(getString(R.string.voice_asr_model_section))
    WhisperModelManager.models.forEach { model ->
        val state = WhisperModelManager.downloadState(this, model)
        val available = WhisperModelManager.isAvailable(this, model)
        val isSelected = selected.id == model.id &&
            config.asrAcceleration != VoiceAssistantSettings.ASR_ACCELERATION_QNN
        val benchmarkRecord = if (available && VoiceFeatureFlags.isWhisperAutoBenchmarkEnabled(this)) {
            WhisperBenchmarkManager.current(this, model)
        } else null
        val latestBenchmark = if (available && benchmarkRecord == null &&
            VoiceFeatureFlags.isWhisperAutoBenchmarkEnabled(this)
        ) {
            WhisperBenchmarkManager.latest(this, model)
        } else null
        val benchmarkProgress = whisperBenchmarkProgress[model.id]
        val benchmarkNotice = whisperBenchmarkNotices[model.id]
        val isBenchmarking = benchmarkProgress != null || WhisperBenchmarkManager.isRunning(model.id)
        val isDownloading = state.status == DownloadManager.STATUS_PENDING ||
            state.status == DownloadManager.STATUS_RUNNING ||
            state.status == DownloadManager.STATUS_PAUSED
        if (isDownloading && pendingAsrModelSelection == null) pendingAsrModelSelection = model.id
        hasActiveDownload = hasActiveDownload || isDownloading
        val profileDetail = getString(
            R.string.voice_asr_model_profile_detail,
            model.sizeLabel,
            model.quantization.name
        )
        val sourceDetail = if (model.bundled) {
            getString(R.string.voice_asr_model_bundled)
        } else {
            getString(R.string.voice_asr_model_download_size)
        }
        val lifecycleDetail = when {
            isBenchmarking -> getString(
                R.string.voice_asr_model_benchmark_progress,
                benchmarkProgress?.let(::whisperBenchmarkStageLabel)
                    ?: getString(R.string.voice_asr_model_benchmarking),
                benchmarkProgress?.let { progress ->
                    if (progress.totalSteps <= 0) 0
                    else (progress.completedSteps * 100 / progress.totalSteps).coerceIn(0, 100)
                } ?: 0
            )
            !benchmarkNotice.isNullOrBlank() -> benchmarkNotice
            benchmarkRecord != null -> whisperCertificationLabel(benchmarkRecord.certification.level)
            available && latestBenchmark != null -> getString(R.string.voice_asr_model_benchmark_stale)
            available -> getString(R.string.voice_asr_model_installed_uncertified)
            state.storageState == com.signalasi.chat.voice.model.WhisperModelStorageState.VERIFYING_SIZE ||
                state.storageState == com.signalasi.chat.voice.model.WhisperModelStorageState.VERIFYING_SHA256 ->
                getString(R.string.voice_asr_model_verifying)
            state.storageState == com.signalasi.chat.voice.model.WhisperModelStorageState.ATOMIC_INSTALLING ->
                getString(R.string.voice_asr_model_installing)
            isDownloading && state.progress > 0 ->
                getString(R.string.voice_asr_model_progress, state.progress)
            state.status == DownloadManager.STATUS_FAILED ||
                state.storageState == com.signalasi.chat.voice.model.WhisperModelStorageState.FAILED ->
                getString(
                    R.string.voice_asr_model_install_failed,
                    state.failure?.name ?: state.detail.ifBlank { "UNKNOWN" }
                )
            else -> sourceDetail
        }
        val subtitle = "$profileDetail\n$lifecycleDetail"
        val action = when {
            isBenchmarking -> getString(R.string.voice_asr_model_benchmarking)
            isSelected && available -> getString(R.string.section_current)
            available -> getString(R.string.settings_language_use)
            isDownloading && !model.bundled -> getString(R.string.voice_asr_model_cancel)
            isDownloading -> getString(R.string.voice_asr_model_waiting)
            state.status == DownloadManager.STATUS_FAILED -> getString(R.string.common_retry)
            else -> getString(R.string.voice_asr_model_download)
        }
        featureContent.addView(featureRow(model.displayName, subtitle, R.drawable.ic_local_model, action).apply {
            val canInteract = !isBenchmarking && !(isDownloading && model.bundled)
            isClickable = canInteract
            isFocusable = isClickable
            setOnClickListener(if (canInteract) View.OnClickListener {
                if (isDownloading) {
                    android.app.AlertDialog.Builder(this@showAsrProviderPage)
                        .setTitle(getString(R.string.voice_asr_model_cancel_title))
                        .setMessage(getString(R.string.voice_asr_model_cancel_message, model.displayName))
                        .setNegativeButton(getString(R.string.voice_asr_model_keep_downloading), null)
                        .setPositiveButton(getString(R.string.voice_asr_model_cancel)) { _, _ ->
                            WhisperModelManager.cancel(this@showAsrProviderPage, model)
                            if (pendingAsrModelSelection == model.id) pendingAsrModelSelection = null
                            showAsrProviderPage()
                        }
                        .show()
                } else if (available) {
                    if (!isSelected) {
                        VoiceAssistantSettings.setAsrModel(this@showAsrProviderPage, model.id)
                        Toast.makeText(
                            this@showAsrProviderPage,
                            getString(R.string.voice_asr_model_ready, model.displayName),
                            Toast.LENGTH_SHORT
                        ).show()
                        ensureWhisperMicrophonePermission()
                        showAsrProviderPage()
                    } else if (
                        checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) !=
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        ensureWhisperMicrophonePermission()
                    } else if (VoiceFeatureFlags.isWhisperAutoBenchmarkEnabled(this@showAsrProviderPage)) {
                        if (benchmarkRecord == null) confirmWhisperBenchmark(model)
                        else showWhisperBenchmarkDetails(model, benchmarkRecord)
                    } else {
                        showAsrProviderPage()
                    }
                } else {
                    runCatching { WhisperModelManager.enqueue(this@showAsrProviderPage, model) }
                        .onSuccess {
                            pendingAsrModelSelection = model.id
                            Toast.makeText(this@showAsrProviderPage, getString(R.string.voice_asr_model_download_started, model.displayName), Toast.LENGTH_SHORT).show()
                            handler.post(asrModelDownloadPoll)
                        }
                        .onFailure { error ->
                            showWhisperDownloadFailure(model, error)
                        }
                }
            } else null)
            if (available && !model.bundled && !isSelected) {
                setOnLongClickListener {
                    android.app.AlertDialog.Builder(this@showAsrProviderPage)
                        .setTitle(getString(R.string.voice_asr_model_remove_title, model.displayName))
                        .setMessage(getString(R.string.voice_asr_model_remove_message))
                        .setNegativeButton(getString(R.string.common_cancel), null)
                        .setPositiveButton(getString(R.string.voice_asr_model_remove)) { _, _ ->
                            runCatching { WhisperModelManager.delete(this@showAsrProviderPage, model) }
                                .onSuccess {
                                    WhisperBenchmarkManager.remove(this@showAsrProviderPage, model)
                                    showAsrProviderPage()
                                }
                                .onFailure {
                                    Toast.makeText(
                                        this@showAsrProviderPage,
                                        getString(R.string.voice_asr_model_install_failed, it.message.orEmpty()),
                                        Toast.LENGTH_LONG
                                    ).show()
                                }
                        }
                        .show()
                    true
                }
            }
        })
    }
    featureContent.addView(TextView(this).apply {
        text = getString(R.string.voice_asr_model_mirror_note)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 12f
        setPadding(dp(4), dp(4), dp(4), dp(18))
    })
    if (hasActiveDownload) handler.postDelayed(asrModelDownloadPoll, 1_000L)
}

internal fun MainActivity.showVoiceRecognitionPreferenceDialog(current: VoiceRecognitionPreference) {
    val values = buildList {
        addAll(listOf(
        VoiceRecognitionPreference.AUTO,
        VoiceRecognitionPreference.ONLINE_FAST,
        VoiceRecognitionPreference.LOCAL_PRIVATE,
        VoiceRecognitionPreference.LOCAL_HIGH_ACCURACY
        ))
        val config = VoiceAssistantSettings.get(this@showVoiceRecognitionPreferenceDialog)
        if (VoiceFeatureFlags.isRemoteWhisperNodeEnabled(this@showVoiceRecognitionPreferenceDialog) &&
            config.remoteWhisperAllowed &&
            RemoteWhisperNodeRegistry.best(this@showVoiceRecognitionPreferenceDialog) != null
        ) add(VoiceRecognitionPreference.REMOTE_NODE)
    }
    val labels = values.map(::voiceRecognitionPreferenceLabel).toTypedArray()
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.voice_asr_recognition_mode_title))
        .setSingleChoiceItems(labels, values.indexOf(current).coerceAtLeast(0)) { dialog, which ->
            val selected = values[which]
            VoiceAssistantSettings.setRecognitionPreference(this, selected)
            VoiceAssistantSettings.setAsrProvider(
                this,
                when (selected) {
                    VoiceRecognitionPreference.ONLINE_FAST -> VoiceAssistantSettings.ASR_PROVIDER_ONLINE_REALTIME
                    VoiceRecognitionPreference.LOCAL_PRIVATE,
                    VoiceRecognitionPreference.LOCAL_HIGH_ACCURACY ->
                        VoiceAssistantSettings.ASR_PROVIDER_LOCAL_WHISPER
                    VoiceRecognitionPreference.REMOTE_NODE ->
                        VoiceAssistantSettings.ASR_PROVIDER_REMOTE_WHISPER
                    else -> VoiceAssistantSettings.ASR_PROVIDER_AUTO
                }
            )
            VoiceAssistantSettings.setRecognitionPreference(this, selected)
            dialog.dismiss()
            showAsrProviderPage()
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.voiceRecognitionPreferenceLabel(value: VoiceRecognitionPreference): String = getString(
    when (value) {
        VoiceRecognitionPreference.AUTO -> R.string.voice_asr_mode_auto
        VoiceRecognitionPreference.ONLINE_FAST -> R.string.voice_asr_mode_online_fast
        VoiceRecognitionPreference.LOCAL_PRIVATE -> R.string.voice_asr_mode_local_private
        VoiceRecognitionPreference.LOCAL_HIGH_ACCURACY -> R.string.voice_asr_mode_local_accurate
        VoiceRecognitionPreference.REMOTE_NODE -> R.string.voice_asr_mode_remote_node
    }
)

internal fun MainActivity.toggleOnlineRealtimeAsr(config: VoiceAssistantConfig) {
    val enabled = config.onlineAsrPrivacy.allowOnlineVoice && config.onlineAsrPrivacy.allowRawAudioUpload
    if (enabled) {
        VoiceAssistantSettings.setOnlineAsrPrivacy(
            this,
            config.onlineAsrPrivacy.copy(allowOnlineVoice = false, allowRawAudioUpload = false)
        )
        showAsrProviderPage()
        return
    }
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.voice_asr_online_consent_title))
        .setMessage(getString(R.string.voice_asr_online_consent_message))
        .setNegativeButton(getString(R.string.common_cancel), null)
        .setPositiveButton(getString(R.string.common_enable)) { _, _ ->
            VoiceAssistantSettings.setOnlineAsrPrivacy(
                this,
                config.onlineAsrPrivacy.copy(allowOnlineVoice = true, allowRawAudioUpload = true)
            )
            showAsrProviderPage()
        }
        .show()
}

internal fun MainActivity.startLargeTurboQnnModelDownload() {
    val begin: (QnnModelDownloadNetworkPolicy) -> Unit = { policy ->
        LargeTurboQnnModelManager.enqueue(this, policy) { showAsrProviderPage() }
        Toast.makeText(
            this,
            getString(
                R.string.voice_asr_model_download_started,
                LargeTurboQnnModelManager.manifest.displayName
            ),
            Toast.LENGTH_SHORT
        ).show()
        handler.post(asrModelDownloadPoll)
        showAsrProviderPage()
    }
    when (currentAsrNetworkType()) {
        AsrNetworkType.WIFI -> begin(QnnModelDownloadNetworkPolicy.WIFI_ONLY)
        AsrNetworkType.MOBILE -> android.app.AlertDialog.Builder(this)
            .setTitle(getString(R.string.voice_asr_model_mobile_title))
            .setMessage(getString(
                R.string.voice_asr_model_mobile_message,
                LargeTurboQnnModelManager.manifest.displayName,
                LargeTurboQnnModelManager.sizeLabel()
            ))
            .setNegativeButton(getString(R.string.common_cancel), null)
            .setPositiveButton(getString(R.string.voice_asr_model_mobile_continue)) { _, _ ->
                begin(QnnModelDownloadNetworkPolicy.ANY_VALIDATED_NETWORK)
            }
            .show()
        AsrNetworkType.OTHER_VALIDATED -> begin(QnnModelDownloadNetworkPolicy.ANY_VALIDATED_NETWORK)
        AsrNetworkType.OFFLINE -> Toast.makeText(
            this,
            getString(R.string.voice_asr_model_network_error),
            Toast.LENGTH_LONG
        ).show()
    }
}

internal fun MainActivity.showWhisperRuntimeModeDialog(current: WhisperUserVoiceMode) {
    val modes = listOf(
        WhisperUserVoiceMode.AUTOMATIC,
        WhisperUserVoiceMode.FAST,
        WhisperUserVoiceMode.POWER_SAVER,
        WhisperUserVoiceMode.ACCURATE,
        WhisperUserVoiceMode.PRIVACY,
        WhisperUserVoiceMode.MANUAL
    )
    val labels = modes.map(::whisperRuntimeModeLabel).toTypedArray()
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.voice_asr_runtime_mode_title))
        .setSingleChoiceItems(labels, modes.indexOf(current).coerceAtLeast(0)) { dialog, which ->
            VoiceAssistantSettings.setAsrRuntimeMode(this, modes[which])
            dialog.dismiss()
            showAsrProviderPage()
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.confirmWhisperBenchmark(model: WhisperModel) {
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.voice_asr_model_benchmark_title, model.displayName))
        .setMessage(getString(R.string.voice_asr_model_benchmark_message))
        .setNegativeButton(getString(R.string.common_cancel), null)
        .setPositiveButton(getString(R.string.voice_asr_model_benchmark_start)) { _, _ ->
            startWhisperBenchmark(model, force = true)
        }
        .show()
}

internal fun MainActivity.ensureWhisperMicrophonePermission() {
    if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) return
    requestPermissions(
        arrayOf(android.Manifest.permission.RECORD_AUDIO),
        REQUEST_CONTROL_CENTER_PERMISSION
    )
}

internal fun MainActivity.startWhisperBenchmark(model: WhisperModel, force: Boolean) {
    if (WhisperBenchmarkManager.isRunning(model.id)) return
    whisperBenchmarkNotices.remove(model.id)
    whisperBenchmarkProgress[model.id] = WhisperBenchmarkProgress(
        WhisperBenchmarkStage.VERIFYING,
        completedSteps = 0,
        totalSteps = 1
    )
    if (featurePage.visibility == View.VISIBLE) showAsrProviderPage()
    voiceAssistantScope.launch {
        val outcome = runCatching {
            WhisperBenchmarkManager.benchmark(this@startWhisperBenchmark, model, force) { progress ->
                whisperBenchmarkProgress[model.id] = progress
                scheduleWhisperBenchmarkRefresh()
            }
        }
        whisperBenchmarkProgress.remove(model.id)
        handler.post {
            if (isFinishing || isDestroyed) return@post
            outcome.onSuccess { record ->
                whisperBenchmarkNotices.remove(model.id)
                Toast.makeText(
                    this@startWhisperBenchmark,
                    getString(R.string.voice_asr_model_benchmark_complete, model.displayName),
                    Toast.LENGTH_SHORT
                ).show()
                if (featurePage.visibility == View.VISIBLE) showAsrProviderPage()
                showWhisperBenchmarkDetails(model, record)
            }.onFailure { error ->
                if (error is CancellationException) {
                    if (featurePage.visibility == View.VISIBLE) showAsrProviderPage()
                    return@onFailure
                }
                val message = if (error is WhisperBenchmarkDeferredException) {
                    getString(R.string.voice_asr_model_benchmark_deferred)
                } else {
                    error.message.orEmpty().ifBlank { error.javaClass.simpleName }
                }
                whisperBenchmarkNotices[model.id] = message
                Log.w("SignalASIWhisper", "Benchmark failed for ${model.id}: $message", error)
                Toast.makeText(
                    this@startWhisperBenchmark,
                    getString(R.string.voice_asr_model_benchmark_failed, message),
                    Toast.LENGTH_LONG
                ).show()
                if (featurePage.visibility == View.VISIBLE) showAsrProviderPage()
            }
        }
    }
}

internal fun MainActivity.scheduleWhisperBenchmarkRefresh() {
    if (!whisperBenchmarkRefreshScheduled.compareAndSet(false, true)) return
    handler.postDelayed({
        whisperBenchmarkRefreshScheduled.set(false)
        if (!isFinishing && !isDestroyed && featurePage.visibility == View.VISIBLE &&
            featureTitle.text == getString(R.string.voice_asr_provider)
        ) {
            showAsrProviderPage()
        }
    }, 350L)
}

internal fun MainActivity.showWhisperBenchmarkDetails(model: WhisperModel, record: WhisperBenchmarkRecord) {
    val certification = record.certification
    val recommendation = whisperCertificationLabel(certification.level)
    val coldLoadP95 = percentileWhisperLong(
        record.measurements.filter { it.loadKind == com.signalasi.chat.voice.benchmark.WhisperBenchmarkLoadKind.COLD }
            .map { it.loadDurationMs }
    )
    val hotLoadP95 = percentileWhisperLong(
        record.measurements.filter { it.loadKind == com.signalasi.chat.voice.benchmark.WhisperBenchmarkLoadKind.HOT }
            .map { it.loadDurationMs }
    )
    val firstPartialP95 = percentileWhisperLong(
        record.measurements.map { it.firstPartialLatencyMs }.filter { it > 0L }
    )
    val finalTailP95 = percentileWhisperLong(
        record.measurements.map { it.finalTailLatencyMs }.filter { it > 0L }
    )
    val peakRss = record.measurements.maxOfOrNull { it.peakRssBytes } ?: 0L
    val peakNative = record.measurements.maxOfOrNull { it.peakNativeAllocatedBytes } ?: 0L
    val body = buildString {
        append(getString(
            R.string.voice_asr_model_benchmark_metrics,
            certification.warmRtfP50,
            certification.warmRtfP95,
            formatWhisperBytes(certification.peakPssBytes),
            certification.recommendedThreadCount,
            certification.maxThermalStatus,
            certification.abortLatencyMsP95
        ))
        append("\n")
        append(getString(
            R.string.voice_asr_model_benchmark_latency_metrics,
            coldLoadP95,
            hotLoadP95,
            firstPartialP95,
            finalTailP95
        ))
        append("\n")
        append(getString(
            R.string.voice_asr_model_benchmark_memory_metrics,
            formatWhisperBytes(peakRss),
            formatWhisperBytes(peakNative)
        ))
        append("\n\n")
        append(getString(R.string.voice_asr_model_benchmark_recommendation, recommendation))
        certification.failureReason?.takeIf(String::isNotBlank)?.let { reason ->
            append("\n")
            append(getString(R.string.voice_asr_model_benchmark_failure_reason, reason))
        }
    }
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.voice_asr_model_benchmark_details_title, model.displayName))
        .setMessage(body)
        .setNegativeButton(android.R.string.ok, null)
        .setPositiveButton(getString(R.string.voice_asr_model_retest)) { _, _ ->
            confirmWhisperBenchmark(model)
        }
        .show()
}

internal fun MainActivity.percentileWhisperLong(values: List<Long>): Long {
    if (values.isEmpty()) return 0L
    val sorted = values.sorted()
    return sorted[((sorted.lastIndex * 0.95) + 0.5).toInt().coerceIn(0, sorted.lastIndex)]
}

internal fun MainActivity.whisperRuntimeModeLabel(mode: WhisperUserVoiceMode): String = getString(when (mode) {
    WhisperUserVoiceMode.AUTOMATIC -> R.string.voice_asr_runtime_mode_automatic
    WhisperUserVoiceMode.MANUAL -> R.string.voice_asr_runtime_mode_manual
    WhisperUserVoiceMode.FAST -> R.string.voice_asr_runtime_mode_fast
    WhisperUserVoiceMode.POWER_SAVER -> R.string.voice_asr_runtime_mode_power_saver
    WhisperUserVoiceMode.ACCURATE -> R.string.voice_asr_runtime_mode_accurate
    WhisperUserVoiceMode.PRIVACY -> R.string.voice_asr_runtime_mode_privacy
})

internal fun MainActivity.whisperCertificationLabel(level: WhisperCertificationLevel): String = getString(when (level) {
    WhisperCertificationLevel.UNTESTED -> R.string.voice_asr_model_installed_uncertified
    WhisperCertificationLevel.REALTIME -> R.string.voice_asr_model_certified_realtime
    WhisperCertificationLevel.FINAL -> R.string.voice_asr_model_certified_final
    WhisperCertificationLevel.SECOND_PASS -> R.string.voice_asr_model_certified_second_pass
    WhisperCertificationLevel.REMOTE_RECOMMENDED -> R.string.voice_asr_model_remote_recommended
    WhisperCertificationLevel.UNSUPPORTED -> R.string.voice_asr_model_unsupported
})

internal fun MainActivity.whisperBenchmarkStageLabel(progress: WhisperBenchmarkProgress): String = getString(
    when (progress.detail) {
        "loading_model" -> R.string.voice_asr_benchmark_stage_loading
        "decoding_audio" -> R.string.voice_asr_benchmark_stage_decoding
        else -> when (progress.stage) {
            WhisperBenchmarkStage.VERIFYING -> R.string.voice_asr_benchmark_stage_verifying
            WhisperBenchmarkStage.CHECKING_DEVICE -> R.string.voice_asr_benchmark_stage_device
            WhisperBenchmarkStage.SEARCHING_THREADS -> R.string.voice_asr_benchmark_stage_threads
            WhisperBenchmarkStage.STABILITY -> R.string.voice_asr_benchmark_stage_stability
            WhisperBenchmarkStage.CANCELLATION -> R.string.voice_asr_benchmark_stage_cancellation
            WhisperBenchmarkStage.CERTIFYING -> R.string.voice_asr_benchmark_stage_certifying
            WhisperBenchmarkStage.COMPLETE -> R.string.voice_asr_benchmark_stage_complete
        }
    }
)

internal fun MainActivity.showWhisperDownloadFailure(model: WhisperModel, error: Throwable) {
    when (error) {
        is WhisperMeteredDownloadConfirmationRequired -> {
            android.app.AlertDialog.Builder(this)
                .setTitle(getString(R.string.voice_asr_model_mobile_title))
                .setMessage(getString(R.string.voice_asr_model_mobile_message, model.displayName, model.sizeLabel))
                .setNegativeButton(getString(R.string.common_cancel), null)
                .setPositiveButton(getString(R.string.voice_asr_model_mobile_continue)) { _, _ ->
                    runCatching { WhisperModelManager.enqueue(this, model, allowMetered = true) }
                        .onSuccess {
                            pendingAsrModelSelection = model.id
                            handler.post(asrModelDownloadPoll)
                            showAsrProviderPage()
                        }
                        .onFailure {
                            Toast.makeText(this, getString(R.string.voice_asr_model_download_failed), Toast.LENGTH_LONG).show()
                        }
                }
                .show()
        }
        is WhisperDownloadUnavailableException -> {
            val message = if (error.decision == com.signalasi.chat.voice.model.WhisperDownloadDecision.INSUFFICIENT_SPACE) {
                getString(
                    R.string.voice_asr_model_space_error,
                    formatWhisperBytes(error.requiredBytes),
                    formatWhisperBytes(error.availableBytes)
                )
            } else {
                getString(R.string.voice_asr_model_network_error)
            }
            Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        }
        else -> Toast.makeText(this, getString(R.string.voice_asr_model_download_failed), Toast.LENGTH_LONG).show()
    }
}

internal fun MainActivity.formatWhisperBytes(value: Long): String {
    if (value < 0L) return "--"
    val gib = 1_073_741_824.0
    val mib = 1_048_576.0
    return if (value >= gib) {
        String.format(java.util.Locale.US, "%.1f GiB", value / gib)
    } else {
        String.format(java.util.Locale.US, "%.1f MiB", value / mib)
    }
}

internal fun MainActivity.showTtsProviderPage() {
    val config = VoiceAssistantSettings.get(this)
    val capabilities = voiceProviderCapabilities(config)
    val active = activeTtsCapability(config, capabilities)
    showFeaturePage(getString(R.string.voice_tts_provider))
    setFeatureBackAction { showVoiceAssistantSettingsPage() }
    featureContent.addView(featureHeroCard(
        ttsProviderLabel(config.ttsProvider),
        getString(R.string.voice_tts_provider_subtitle),
        R.drawable.ic_send_plane,
        if (active.ready) "#6B5CE7" else "#D48B18",
        voiceCapabilityStatus(active)
    ))
    addSectionTitle(getString(R.string.voice_provider_device_capabilities))
    listOf(
        VoiceAssistantSettings.PROVIDER_ANDROID to VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS,
        VoiceAssistantSettings.PROVIDER_MICROSOFT_EDGE to VoiceProviderCapabilityId.MICROSOFT_EDGE_TTS
    ).forEach { (provider, capabilityId) ->
        val capability = capabilities[capabilityId]
        val selected = config.ttsProvider == provider
        val action = when {
            selected -> getString(R.string.section_current)
            capability.ready -> getString(R.string.settings_language_use)
            else -> voiceCapabilityStatus(capability)
        }
        featureContent.addView(featureRow(
            voiceCapabilityTitle(capabilityId),
            voiceCapabilityDetail(capability),
            R.drawable.ic_send_plane,
            action
        ).apply {
            isClickable = capability.ready && !selected
            isFocusable = isClickable
            setOnClickListener(if (isClickable) View.OnClickListener {
                VoiceAssistantSettings.setTtsProvider(this@showTtsProviderPage, provider)
                showTtsProviderPage()
            } else null)
        })
    }
    addSectionTitle(getString(R.string.voice_provider_device_check))
    featureContent.addView(featureRow(
        getString(R.string.language_policy_tts_language),
        languagePolicyLabel(config.ttsLanguage),
        R.drawable.ic_settings_language,
        voiceCapabilityStatus(capabilities[VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS])
    ).apply {
        setOnClickListener {
            showLanguagePolicyDialog(
                getString(R.string.language_policy_tts_language),
                config.ttsLanguage
            ) {
                VoiceAssistantSettings.setTtsLanguage(this@showTtsProviderPage, it)
                configureAndroidTtsLanguage()
                showTtsProviderPage()
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.voice_provider_recheck),
        getString(R.string.voice_provider_recheck_subtitle),
        R.drawable.ic_agent_history,
        getString(R.string.voice_provider_recheck_action)
    ).apply {
        setOnClickListener { showTtsProviderPage() }
    })
}

internal fun MainActivity.voiceProviderCapabilities(
    config: VoiceAssistantConfig = VoiceAssistantSettings.get(this)
): VoiceProviderCapabilitySnapshot {
    val engineCount = if (androidTtsInitialized) {
        runCatching { androidTts?.engines?.size ?: 0 }.getOrDefault(0)
    } else {
        0
    }
    val languageTag = LanguagePolicySettings.resolve(config.ttsLanguage)
    val languageSupported = androidTtsReady && runCatching {
        val locale = Locale.forLanguageTag(languageTag)
        (androidTts?.isLanguageAvailable(locale) ?: TextToSpeech.LANG_NOT_SUPPORTED) >=
            TextToSpeech.LANG_AVAILABLE
    }.getOrDefault(false)
    return VoiceProviderCapabilityDetector.detect(
        context = this,
        config = config,
        ttsInitialized = androidTtsInitialized,
        ttsReady = androidTtsReady,
        ttsEngineCount = engineCount,
        ttsLanguageSupported = languageSupported
    )
}

internal fun MainActivity.activeTtsCapability(
    config: VoiceAssistantConfig,
    capabilities: VoiceProviderCapabilitySnapshot = voiceProviderCapabilities(config)
): VoiceProviderCapability = capabilities[
    if (config.ttsProvider == VoiceAssistantSettings.PROVIDER_ANDROID) {
        VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS
    } else {
        VoiceProviderCapabilityId.MICROSOFT_EDGE_TTS
    }
]

internal fun MainActivity.voiceRealtimeHealth(
    config: VoiceAssistantConfig = VoiceAssistantSettings.get(this)
): VoiceRealtimeHealthSnapshot = VoiceRealtimeHealthDetector.detect(
    context = this,
    config = config,
    capabilities = voiceProviderCapabilities(config)
)

internal fun MainActivity.voiceHealthRow(entry: VoiceHealthEntry): View {
    val row = featureRow(
        voiceHealthTitle(entry.component),
        voiceHealthDetail(entry),
        when (entry.component) {
            VoiceHealthComponent.WAKE_WORD -> R.drawable.ic_input_voice
            VoiceHealthComponent.ASR -> R.drawable.ic_agent_node
            VoiceHealthComponent.TTS -> R.drawable.ic_send_plane
        },
        voiceHealthStatus(entry.state)
    ) as LinearLayout
    val textGroup = row.getChildAt(1) as LinearLayout
    val subtitle = textGroup.getChildAt(1) as TextView
    val status = row.getChildAt(2) as TextView
    status.layoutParams = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.WRAP_CONTENT,
        dp(34)
    ).apply {
        marginStart = dp(6)
    }
    status.minWidth = dp(72)
    status.setPadding(dp(4), 0, dp(4), 0)
    voiceHealthRows[entry.component] = VoiceHealthRowBinding(subtitle, status)
    updateVoiceHealthBinding(entry, voiceHealthRows.getValue(entry.component))
    row.setOnClickListener {
        when (entry.component) {
            VoiceHealthComponent.WAKE_WORD -> refreshVoiceHealthRows()
            VoiceHealthComponent.ASR -> showAsrProviderPage()
            VoiceHealthComponent.TTS -> showTtsProviderPage()
        }
    }
    return row
}

internal fun MainActivity.startVoiceHealthMonitoring() {
    handler.removeCallbacks(voiceHealthRefresh)
    refreshVoiceHealthRows()
    handler.postDelayed(voiceHealthRefresh, 2_000L)
}

internal fun MainActivity.refreshVoiceHealthRows() {
    if (voiceHealthRows.isEmpty()) return
    val snapshot = voiceRealtimeHealth()
    snapshot.entries.forEach { entry ->
        voiceHealthRows[entry.component]?.let { binding ->
            updateVoiceHealthBinding(entry, binding)
        }
    }
}

internal fun MainActivity.updateVoiceHealthBinding(
    entry: VoiceHealthEntry,
    binding: VoiceHealthRowBinding
) {
    binding.subtitle.text = voiceHealthDetail(entry)
    binding.status.text = voiceHealthStatus(entry.state)
    binding.status.setTextColor(
        when (entry.state) {
            VoiceHealthState.ACTIVE,
            VoiceHealthState.HEALTHY,
            VoiceHealthState.READY -> getColorCompat(R.color.signalasi_green)
            VoiceHealthState.DEGRADED,
            VoiceHealthState.BLOCKED -> Color.parseColor("#D48B18")
            VoiceHealthState.CHECKING,
            VoiceHealthState.DISABLED -> getColorCompat(R.color.text_secondary)
        }
    )
}

internal fun MainActivity.voiceHealthSurfaceVisible(): Boolean =
    isFeaturePageInitialized() &&
        featurePage.visibility == View.VISIBLE &&
        featureTitle.text == getString(R.string.voice_settings_title) &&
        voiceHealthRows.isNotEmpty()

internal fun MainActivity.voiceHealthTitle(component: VoiceHealthComponent): String = getString(
    when (component) {
        VoiceHealthComponent.WAKE_WORD -> R.string.voice_health_wake
        VoiceHealthComponent.ASR -> R.string.voice_health_asr
        VoiceHealthComponent.TTS -> R.string.voice_health_tts
    }
)

internal fun MainActivity.voiceHealthStatus(state: VoiceHealthState): String = getString(
    when (state) {
        VoiceHealthState.ACTIVE -> R.string.voice_health_active
        VoiceHealthState.HEALTHY -> R.string.voice_health_healthy
        VoiceHealthState.READY -> R.string.voice_health_ready
        VoiceHealthState.CHECKING -> R.string.voice_health_checking
        VoiceHealthState.DEGRADED -> R.string.voice_health_degraded
        VoiceHealthState.BLOCKED -> R.string.voice_health_action_needed
        VoiceHealthState.DISABLED -> R.string.voice_health_disabled
    }
)

internal fun MainActivity.voiceHealthDetail(entry: VoiceHealthEntry): String {
    val detail = when (entry.state) {
        VoiceHealthState.ACTIVE -> getString(
            R.string.voice_health_active_detail,
            voiceHealthAge(entry.runtime.startedAtMillis)
        )
        VoiceHealthState.HEALTHY -> getString(
            R.string.voice_health_success_detail,
            voiceHealthAge(entry.runtime.lastSuccessAtMillis)
        )
        VoiceHealthState.READY -> getString(R.string.voice_health_ready_detail)
        VoiceHealthState.CHECKING -> getString(R.string.voice_provider_checking_detail)
        VoiceHealthState.DEGRADED -> getString(
            R.string.voice_health_failure_detail,
            entry.runtime.lastFailureReason.ifBlank {
                getString(R.string.voice_health_runtime_failure)
            }
        )
        VoiceHealthState.BLOCKED -> voiceHealthIssueDetail(entry.issue)
        VoiceHealthState.DISABLED -> getString(R.string.voice_health_disabled_detail)
    }
    return getString(R.string.voice_health_provider_detail, entry.provider, detail)
}

internal fun MainActivity.voiceHealthIssueDetail(issue: VoiceHealthIssue): String = getString(
    when (issue) {
        VoiceHealthIssue.MICROPHONE_MISSING ->
            R.string.voice_capability_microphone_missing
        VoiceHealthIssue.PERMISSION_REQUIRED ->
            R.string.voice_capability_microphone_permission
        VoiceHealthIssue.RUNTIME_MISSING ->
            R.string.voice_health_runtime_missing
        VoiceHealthIssue.MODEL_MISSING ->
            R.string.voice_health_model_missing
        VoiceHealthIssue.NETWORK_REQUIRED ->
            R.string.voice_capability_network_required
        VoiceHealthIssue.LANGUAGE_UNSUPPORTED ->
            R.string.voice_health_language_unsupported
        VoiceHealthIssue.CHECKING ->
            R.string.voice_provider_checking_detail
        VoiceHealthIssue.PROVIDER_UNAVAILABLE ->
            R.string.voice_health_provider_unavailable
        VoiceHealthIssue.RECENT_FAILURE ->
            R.string.voice_health_runtime_failure
        VoiceHealthIssue.DISABLED ->
            R.string.voice_health_disabled_detail
        VoiceHealthIssue.NONE ->
            R.string.voice_health_ready_detail
    }
)

internal fun MainActivity.voiceHealthAge(timestampMillis: Long): String {
    if (timestampMillis <= 0L) return getString(R.string.voice_health_now)
    val seconds = ((System.currentTimeMillis() - timestampMillis).coerceAtLeast(0L) / 1_000L)
    return when {
        seconds < 1L -> getString(R.string.voice_health_now)
        seconds < 60L -> getString(R.string.voice_health_seconds, seconds)
        seconds < 3_600L -> getString(R.string.voice_health_minutes, seconds / 60L)
        else -> getString(R.string.voice_health_hours, seconds / 3_600L)
    }
}

internal fun MainActivity.wakeRuntimeChannel(
    config: VoiceAssistantConfig = VoiceAssistantSettings.get(this)
): VoiceRuntimeChannel =
    if (config.wakeProvider == VoiceAssistantSettings.WAKE_PROVIDER_ANDROID_ASR) {
        VoiceRuntimeChannel.ANDROID_WAKE_ASR
    } else {
        VoiceRuntimeChannel.OPEN_WAKE_WORD
    }

internal fun MainActivity.voiceCapabilityTitle(id: VoiceProviderCapabilityId): String = getString(
    when (id) {
        VoiceProviderCapabilityId.WHISPER_CPP -> R.string.voice_asr_local_title
        VoiceProviderCapabilityId.ANDROID_SYSTEM_ASR -> R.string.voice_asr_system_title
        VoiceProviderCapabilityId.ANDROID_OFFLINE_ASR -> R.string.voice_asr_offline_title
        VoiceProviderCapabilityId.CLOUD_ASR -> R.string.voice_asr_cloud_title
        VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS -> R.string.voice_tts_android
        VoiceProviderCapabilityId.MICROSOFT_EDGE_TTS -> R.string.voice_tts_microsoft
    }
)

internal fun MainActivity.voiceCapabilityStatus(capability: VoiceProviderCapability): String = getString(
    when (capability.state) {
        VoiceProviderCapabilityState.READY -> R.string.voice_provider_ready
        VoiceProviderCapabilityState.CHECKING -> R.string.voice_provider_checking
        VoiceProviderCapabilityState.NEEDS_PERMISSION -> R.string.voice_provider_permission_required
        VoiceProviderCapabilityState.NEEDS_DOWNLOAD -> R.string.voice_provider_download_required
        VoiceProviderCapabilityState.NEEDS_NETWORK -> R.string.voice_provider_network_required
        VoiceProviderCapabilityState.UNAVAILABLE -> R.string.voice_provider_unavailable
    }
)

internal fun MainActivity.voiceCapabilityTone(capability: VoiceProviderCapability): ControlCenterTone =
    when (capability.state) {
        VoiceProviderCapabilityState.READY -> ControlCenterTone.GREEN
        VoiceProviderCapabilityState.CHECKING -> ControlCenterTone.NEUTRAL
        VoiceProviderCapabilityState.NEEDS_PERMISSION,
        VoiceProviderCapabilityState.NEEDS_DOWNLOAD,
        VoiceProviderCapabilityState.NEEDS_NETWORK -> ControlCenterTone.AMBER
        VoiceProviderCapabilityState.UNAVAILABLE -> ControlCenterTone.NEUTRAL
    }

internal fun MainActivity.voiceCapabilityDetail(capability: VoiceProviderCapability): String = getString(
    when (capability.reason) {
        VoiceProviderCapabilityReason.READY -> when (capability.id) {
            VoiceProviderCapabilityId.WHISPER_CPP -> R.string.voice_asr_whisper_ready_detail
            VoiceProviderCapabilityId.ANDROID_SYSTEM_ASR -> R.string.voice_asr_system_ready_detail
            VoiceProviderCapabilityId.ANDROID_OFFLINE_ASR -> R.string.voice_asr_offline_ready_detail
            VoiceProviderCapabilityId.CLOUD_ASR -> R.string.voice_asr_cloud_ready_detail
            VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS -> R.string.voice_tts_system_ready_detail
            VoiceProviderCapabilityId.MICROSOFT_EDGE_TTS -> R.string.voice_tts_cloud_ready_detail
        }
        VoiceProviderCapabilityReason.CHECKING -> R.string.voice_provider_checking_detail
        VoiceProviderCapabilityReason.MICROPHONE_MISSING ->
            R.string.voice_capability_microphone_missing
        VoiceProviderCapabilityReason.MICROPHONE_PERMISSION_REQUIRED ->
            R.string.voice_capability_microphone_permission
        VoiceProviderCapabilityReason.WHISPER_RUNTIME_MISSING ->
            R.string.voice_capability_whisper_runtime_missing
        VoiceProviderCapabilityReason.WHISPER_MODEL_MISSING ->
            R.string.voice_capability_whisper_model_missing
        VoiceProviderCapabilityReason.SYSTEM_RECOGNIZER_MISSING ->
            R.string.voice_capability_system_asr_missing
        VoiceProviderCapabilityReason.OFFLINE_RECOGNIZER_MISSING ->
            R.string.voice_capability_offline_asr_missing
        VoiceProviderCapabilityReason.ONLINE_AUDIO_PERMISSION_REQUIRED ->
            R.string.voice_capability_online_audio_permission
        VoiceProviderCapabilityReason.CREDENTIAL_BROKER_REQUIRED ->
            R.string.voice_capability_credential_broker_required
        VoiceProviderCapabilityReason.NETWORK_REQUIRED ->
            R.string.voice_capability_network_required
        VoiceProviderCapabilityReason.TTS_ENGINE_MISSING ->
            R.string.voice_capability_tts_engine_missing
        VoiceProviderCapabilityReason.TTS_LANGUAGE_UNSUPPORTED ->
            R.string.voice_capability_tts_language_unsupported
    },
    when (capability.reason) {
        VoiceProviderCapabilityReason.READY ->
            if (capability.id == VoiceProviderCapabilityId.WHISPER_CPP) {
                capability.metadata["model_name"].orEmpty()
            } else if (capability.id == VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS) {
                capability.metadata["engine_count"].orEmpty()
            } else {
                ""
            }
        VoiceProviderCapabilityReason.WHISPER_MODEL_MISSING ->
            capability.metadata["model_name"].orEmpty()
        VoiceProviderCapabilityReason.TTS_LANGUAGE_UNSUPPORTED ->
            languagePolicyLabel(capability.metadata["language"].orEmpty())
        else -> ""
    }
)

internal fun MainActivity.wakeProviderLabel(provider: String): String =
    if (provider == VoiceAssistantSettings.WAKE_PROVIDER_ANDROID_ASR) getString(R.string.voice_wake_engine_android_asr) else getString(R.string.voice_wake_engine_openwakeword)

internal fun MainActivity.ttsProviderLabel(provider: String): String =
    if (provider == VoiceAssistantSettings.PROVIDER_ANDROID) getString(R.string.voice_tts_android) else getString(R.string.voice_tts_microsoft)

internal fun MainActivity.voiceRoutingModeLabel(mode: String): String =
    if (mode == VoiceAssistantSettings.ROUTING_MODE_CONTACT) {
        getString(R.string.voice_routing_contact)
    } else {
        getString(R.string.voice_routing_native_agent)
    }

internal fun MainActivity.onOffLabel(enabled: Boolean): String =
    getString(if (enabled) R.string.common_on else R.string.common_off)

internal fun MainActivity.showTextSettingDialog(title: String, initial: String, onSave: (String) -> Unit) {
    val input = EditText(this).apply {
        setText(initial)
        selectAll()
        minLines = if (initial.length > 40) 3 else 1
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        setPadding(dp(18), dp(10), dp(18), dp(10))
    }
    android.app.AlertDialog.Builder(this)
        .setTitle(title)
        .setView(input)
        .setPositiveButton(getString(R.string.common_save)) { _, _ -> onSave(input.text?.toString()?.trim().orEmpty()) }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.showChoiceDialog(title: String, options: List<String>, current: String, onChoose: (String) -> Unit) {
    val selected = options.indexOf(current).coerceAtLeast(0)
    android.app.AlertDialog.Builder(this)
        .setTitle(title)
        .setSingleChoiceItems(options.toTypedArray(), selected) { dialog, which ->
            onChoose(options[which])
            dialog.dismiss()
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}
