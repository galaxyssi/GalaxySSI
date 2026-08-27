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

internal fun MainActivity.showLocalModelFeaturePage() {
    val profile = LocalModelRuntimeSettings.displayProfile(this)
    val profiles = LocalModelManager.profiles(this)
    val qnnProfiles = profiles.filter {
        it.preferredAccelerator == LocalModelAcceleratorKind.VENDOR_SDK
    }
    val otherProfiles = profiles.filterNot { it in qnnProfiles }
    val contextTokens = LocalModelRuntimeSettings.contextTokens(this)
    val modelInstalled = LocalModelManager.isInstalled(this, profile)
    val estimate = LocalModelRuntimeEstimator.estimate(
        LocalModelRuntimeRequest(
            profile = profile,
            requestedContextTokens = contextTokens,
            modelFileBytes = profile.expectedModelFileBytes,
            modelFilePresent = modelInstalled,
            requireModelFile = true
        ),
        LocalModelDeviceSnapshotDetector.capture(this)
    )
    val accelerators = LocalModelAcceleratorDetector.detect(this)
    showFeaturePage(getString(R.string.local_model_title))
    featureContent.addView(localModelStatusCard(profile, estimate))
    addSectionTitle(getString(R.string.local_model_qnn_section))
    featureContent.addView(TextView(this).apply {
        text = getString(R.string.local_model_qnn_catalog_subtitle)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 12.5f
        setPadding(dp(2), 0, dp(2), dp(10))
    })
    qnnProfiles.forEach { candidate ->
        featureContent.addView(localModelProfileRow(candidate))
    }
    addSectionTitle(getString(R.string.local_model_section_manage))
    featureContent.addView(featureRow(
        getString(R.string.local_model_search_title),
        getString(R.string.local_model_search_subtitle),
        R.drawable.ic_agent_knowledge,
        getString(R.string.local_model_search_action)
    ).apply {
        setOnClickListener { showLocalModelSearchPage() }
    })
    featureContent.addView(featureRow(
        getString(R.string.local_model_qnn_import_title),
        getString(R.string.local_model_qnn_import_subtitle),
        R.drawable.ic_import,
        getString(R.string.local_model_qnn_import_action)
    ).apply {
        setOnClickListener { selectLocalQnnPackage() }
    })
    otherProfiles.forEach { candidate ->
        featureContent.addView(localModelProfileRow(candidate))
    }
    featureContent.addView(featureValueRow(
        getString(R.string.local_model_context_window),
        getString(R.string.local_model_context_window_subtitle),
        R.drawable.ic_agent_history,
        getString(R.string.local_model_context_tokens, contextTokens)
    ).apply {
        setOnClickListener {
            val choices = listOf(2_048, 4_096, 8_192, 16_384, 32_768)
            val labels = choices.map { getString(R.string.local_model_context_tokens, it) }
            showChoiceDialog(
                getString(R.string.local_model_context_window),
                labels,
                getString(R.string.local_model_context_tokens, contextTokens)
            ) { selected ->
                labels.indexOf(selected).takeIf { it >= 0 }?.let { index ->
                    LocalModelRuntimeSettings.setContextTokens(this@showLocalModelFeaturePage, choices[index])
                }
                showLocalModelFeaturePage()
            }
        }
    })
    if (profile.visionCapable) {
        featureContent.addView(featureValueRow(
            getString(R.string.local_model_vision),
            getString(R.string.local_model_multimodal_runtime_detail),
            R.drawable.ic_import,
            getString(R.string.local_model_text_only)
        ))
    }
    addSectionTitle(getString(R.string.local_model_preflight_section))
    featureContent.addView(featureValueRow(
        getString(R.string.local_model_file_estimate),
        profile.quantizationLabel,
        R.drawable.ic_local_model,
        formatBytes(estimate.modelFileBytes)
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.local_model_kv_cache),
        getString(
            R.string.local_model_kv_cache_subtitle,
            estimate.recommendedContextTokens
        ),
        R.drawable.ic_agent_memory,
        formatBytes(estimate.kvCacheBytes)
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.local_model_safe_memory),
        getString(R.string.local_model_safe_memory_subtitle),
        R.drawable.ic_agent_memory,
        getString(
            R.string.local_model_memory_required_value,
            formatBytes(estimate.totalRequiredBytes),
            formatBytes(estimate.safeMemoryBudgetBytes)
        )
    ))
    if (LocalModelQnnMemoryPolicy.appliesTo(profile)) {
        Lfm25QnnDeploymentStore(this).installedManifest()?.let { manifest ->
            featureContent.addView(featureValueRow(
                getString(R.string.local_model_qnn_context_status),
                getString(
                    R.string.local_model_qnn_context_status_subtitle,
                    manifest.qairtVersion,
                    manifest.maximumContextTokens
                ),
                R.drawable.ic_security_shield,
                getString(R.string.local_model_qnn_precompiled)
            ))
            featureContent.addView(featureValueRow(
                getString(R.string.local_model_qnn_profiled_peak),
                getString(R.string.local_model_qnn_profiled_peak_subtitle),
                R.drawable.ic_agent_memory,
                formatBytes(manifest.profiledPeakBytes)
            ))
            featureContent.addView(featureValueRow(
                getString(R.string.local_model_qnn_spill_fill),
                getString(R.string.local_model_qnn_spill_fill_subtitle),
                R.drawable.ic_agent_memory,
                formatBytes(manifest.spillFillBufferBytes)
            ))
        }
    }
    featureContent.addView(featureValueRow(
        getString(R.string.local_model_threads),
        getString(
            R.string.local_model_threads_subtitle,
            estimate.device.cpuCoreCount
        ),
        R.drawable.ic_local_model,
        estimate.recommendedThreads.toString()
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.local_model_temperature),
        localModelThermalDetail(estimate.device),
        R.drawable.ic_resource_battery,
        localModelThermalValue(estimate.device)
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.local_model_battery),
        getString(
            if (estimate.device.charging) {
                R.string.local_model_battery_charging
            } else {
                R.string.local_model_battery_not_charging
            }
        ),
        R.drawable.ic_resource_battery,
        estimate.device.batteryPercent?.let { "$it%" }
            ?: getString(R.string.status_unknown)
    ))
    featureContent.addView(featureRow(
        getString(R.string.local_model_refresh_preflight),
        getString(R.string.local_model_refresh_preflight_subtitle),
        R.drawable.ic_agent_history,
        getString(R.string.voice_provider_recheck_action)
    ).apply {
        setOnClickListener { showLocalModelFeaturePage() }
    })
    addSectionTitle(getString(R.string.local_model_acceleration_section))
    LocalModelAcceleratorKind.entries.forEach { kind ->
        val capability = accelerators[kind]
        featureContent.addView(featureValueRow(
            localModelAcceleratorTitle(kind),
            getString(
                R.string.local_model_accelerator_detail,
                capability.hardwareEvidence,
                capability.runtimeEvidence
            ),
            if (kind == LocalModelAcceleratorKind.CPU) {
                R.drawable.ic_local_model
            } else {
                R.drawable.ic_agent_memory
            },
            localModelAcceleratorStatus(capability.state)
        ))
    }
    addSectionTitle(getString(R.string.local_model_section_permissions))
    featureContent.addView(featureValueRow(getString(R.string.on_device_agent_microphone), "", R.drawable.ic_agent_node, getString(R.string.permission_allowed)))
    featureContent.addView(featureValueRow(getString(R.string.on_device_agent_camera), "", R.drawable.ic_scan, getString(R.string.permission_allowed)))
    featureContent.addView(featureValueRow(getString(R.string.local_model_location), "", R.drawable.ic_device_node, getString(R.string.permission_while_using_allowed)))
    featureContent.addView(featureValueRow(getString(R.string.local_model_notification_permission), "", R.drawable.ic_agent_node, getString(R.string.permission_allowed)))
    addSectionTitle(getString(R.string.local_model_section_privacy_storage))
    featureContent.addView(featureValueRow(
        getString(R.string.local_model_offline_mode),
        getString(R.string.local_model_offline_mode_subtitle),
        R.drawable.ic_security_shield,
        getString(R.string.common_enabled)
    ))
    featureContent.addView(featureStorageRow())
    localModelDownloadRefresh.run()
}

internal fun MainActivity.localModelProfileRow(profile: LocalModelRuntimeProfile): View {
    val subtitleView = TextView(this).apply {
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 12f
        maxLines = 2
        ellipsize = TextUtils.TruncateAt.END
    }
    val actionView = TextView(this).apply {
        setTextColor(getColorCompat(R.color.signalasi_green))
        textSize = 12.5f
        gravity = Gravity.CENTER_VERTICAL or Gravity.END
        maxLines = 1
    }
    val enabledSwitch = Switch(this).apply {
        showText = false
        visibility = View.GONE
        contentDescription = getString(R.string.local_model_enable_action)
    }
    val progressView = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
        max = 100
        progressTintList = android.content.res.ColorStateList.valueOf(getColorCompat(R.color.signalasi_green))
        progressBackgroundTintList = android.content.res.ColorStateList.valueOf(Color.parseColor("#E5E7EB"))
        visibility = View.GONE
    }
    val binding = LocalModelRowBinding(
        profile,
        subtitleView,
        actionView,
        enabledSwitch,
        progressView
    )
    localModelRowBindings[profile.id] = binding
    return LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        isClickable = true
        isFocusable = true
        setPadding(dp(14), dp(10), dp(14), dp(9))
        background = getDrawable(R.drawable.glass_card_background)
        addView(LinearLayout(this@localModelProfileRow).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(featureIcon(R.drawable.ic_local_model, featureIconColor(R.drawable.ic_local_model)))
            addView(LinearLayout(this@localModelProfileRow).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(12), 0, dp(8), 0)
                addView(TextView(this@localModelProfileRow).apply {
                    text = profile.displayName
                    setTextColor(getColorCompat(R.color.text_primary))
                    textSize = 15f
                    setTypeface(typeface, android.graphics.Typeface.BOLD)
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                })
                addView(subtitleView)
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            addView(LinearLayout(this@localModelProfileRow).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL or Gravity.END
                addView(actionView, LinearLayout.LayoutParams(0, dp(36), 1f))
                addView(enabledSwitch, LinearLayout.LayoutParams(dp(52), dp(40)).apply {
                    leftMargin = dp(4)
                })
            }, LinearLayout.LayoutParams(dp(126), dp(40)))
        })
        addView(progressView, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(4)
        ).apply {
            topMargin = dp(7)
            leftMargin = dp(56)
        })
        minimumHeight = dp(72)
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(9) }
        setOnClickListener { handleLocalModelRowClick(profile) }
        setOnLongClickListener {
            if (LocalModelManager.isInstalled(this@localModelProfileRow, profile)) {
                showDeleteLocalModelDialog(profile)
                true
            } else {
                false
            }
        }
        updateLocalModelRow(binding, LocalModelManager.state(this@localModelProfileRow, profile))
    }
}

internal fun MainActivity.updateLocalModelRow(binding: LocalModelRowBinding, state: LocalModelDownloadState) {
    val profile = binding.profile
    val parameterLabel = if (profile.parameterCountBillions % 1.0 == 0.0) {
        profile.parameterCountBillions.toInt().toString()
    } else {
        String.format(Locale.US, "%.1f", profile.parameterCountBillions)
    }
    binding.subtitle.text = buildString {
        append(getString(
            R.string.local_model_size_and_quantization,
            formatBytes(profile.expectedModelFileBytes),
            profile.quantizationLabel,
            parameterLabel
        ))
        if (profile.isQwen17Qnn) {
            append("\n")
            append(getString(R.string.local_model_qwen_automatic_thinking))
        } else if (profile.id == LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN.id) {
            append("\n")
            append(getString(R.string.local_model_gemma_reasoning_role))
        } else if (LocalModelQnnMemoryPolicy.appliesTo(profile)) {
            append("\n")
            append(getString(R.string.local_model_qnn_lfm_memory_profile))
        } else if (profile.defaultNoThink) {
            append("\n")
            append(getString(R.string.local_model_default_no_think))
        }
        if (state.state == LocalModelInstallState.FAILED && state.detail.isNotBlank()) {
            append("\n")
            append(state.detail)
        }
    }
    binding.action.text = localModelActionLabel(profile, state)
    val installed = state.state == LocalModelInstallState.READY
    val enabled = installed && LocalModelRuntimeSettings.isProfileEnabled(this, profile)
    binding.action.setTextColor(getColorCompat(
        if (installed) {
            R.color.text_secondary
        } else {
            R.color.signalasi_green
        }
    ))
    binding.enabledSwitch.setOnCheckedChangeListener(null)
    binding.enabledSwitch.visibility = if (installed) View.VISIBLE else View.GONE
    binding.enabledSwitch.isEnabled = installed
    binding.enabledSwitch.isChecked = enabled
    binding.enabledSwitch.contentDescription = getString(
        if (enabled) R.string.local_model_disable_action else R.string.local_model_enable_action
    )
    binding.enabledSwitch.setOnCheckedChangeListener { _, checked ->
        if (checked != LocalModelRuntimeSettings.isProfileEnabled(this, profile)) {
            setLocalModelProfileEnabled(profile, checked)
        }
    }
    val showProgress = state.state in setOf(
        LocalModelInstallState.QUEUED,
        LocalModelInstallState.DOWNLOADING,
        LocalModelInstallState.PAUSED,
        LocalModelInstallState.VERIFYING,
        LocalModelInstallState.INSTALLING
    )
    binding.progress.visibility = if (showProgress) View.VISIBLE else View.GONE
    binding.progress.isIndeterminate = state.state in setOf(
        LocalModelInstallState.QUEUED,
        LocalModelInstallState.VERIFYING,
        LocalModelInstallState.INSTALLING
    )
    binding.progress.progress = state.progressPercent
}

internal fun MainActivity.localModelActionLabel(
    profile: LocalModelRuntimeProfile,
    state: LocalModelDownloadState
): String = when (state.state) {
    LocalModelInstallState.NOT_INSTALLED -> getString(R.string.local_model_download_action)
    LocalModelInstallState.QUEUED -> getString(R.string.local_model_download_queued)
    LocalModelInstallState.DOWNLOADING -> "${state.progressPercent}%"
    LocalModelInstallState.PAUSED -> getString(R.string.local_model_resume_action)
    LocalModelInstallState.VERIFYING -> getString(R.string.local_model_download_verifying)
    LocalModelInstallState.INSTALLING -> getString(R.string.local_model_download_installing)
    LocalModelInstallState.READY -> getString(
        if (LocalModelRuntimeSettings.isProfileEnabled(this, profile)) {
            R.string.local_model_enabled
        } else {
            R.string.local_model_download_ready
        }
    )
    LocalModelInstallState.FAILED -> getString(R.string.common_retry)
}

internal fun MainActivity.handleLocalModelRowClick(profile: LocalModelRuntimeProfile) {
    when (LocalModelManager.state(this, profile).state) {
        LocalModelInstallState.NOT_INSTALLED,
        LocalModelInstallState.PAUSED,
        LocalModelInstallState.FAILED -> requestLocalModelDownload(profile)
        LocalModelInstallState.QUEUED,
        LocalModelInstallState.DOWNLOADING -> {
            LocalModelManager.pause(this, profile)
            handler.postDelayed(localModelDownloadRefresh, 150L)
        }
        LocalModelInstallState.VERIFYING,
        LocalModelInstallState.INSTALLING -> Unit
        LocalModelInstallState.READY -> {
            setLocalModelProfileEnabled(
                profile,
                enabled = !LocalModelRuntimeSettings.isProfileEnabled(this, profile)
            )
        }
    }
}

internal fun MainActivity.setLocalModelProfileEnabled(
    profile: LocalModelRuntimeProfile,
    enabled: Boolean
) {
    LocalModelRuntimeSettings.setProfileEnabled(this, profile, enabled)
    if (!enabled) {
        cloudExecutor.execute {
            LocalModelInferenceRuntime.unloadIfSelected(profile.id)
        }
    }
    showLocalModelFeaturePage()
}

internal fun MainActivity.requestLocalModelDownload(profile: LocalModelRuntimeProfile, allowMetered: Boolean = false) {
    try {
        LocalModelManager.start(this, profile, allowMetered)
        handler.post(localModelDownloadRefresh)
    } catch (_: LocalModelMeteredConfirmationRequired) {
        AlertDialog.Builder(this)
            .setTitle(R.string.local_model_metered_title)
            .setMessage(getString(
                R.string.local_model_metered_message,
                profile.displayName,
                formatBytes(profile.expectedModelFileBytes)
            ))
            .setNegativeButton(R.string.common_cancel, null)
            .setPositiveButton(R.string.common_confirm) { _, _ ->
                requestLocalModelDownload(profile, allowMetered = true)
            }
            .show()
    } catch (error: LocalModelInsufficientStorage) {
        AlertDialog.Builder(this)
            .setTitle(R.string.local_model_download_failed)
            .setMessage(getString(
                R.string.local_model_download_storage_error,
                formatBytes(error.requiredBytes),
                formatBytes(error.availableBytes)
            ))
            .setPositiveButton(android.R.string.ok, null)
            .show()
    } catch (error: Throwable) {
        Toast.makeText(
            this,
            getString(R.string.local_model_search_error, error.message.orEmpty()),
            Toast.LENGTH_LONG
        ).show()
    }
}

internal fun MainActivity.showDeleteLocalModelDialog(profile: LocalModelRuntimeProfile) {
    AlertDialog.Builder(this)
        .setTitle(R.string.local_model_delete_action)
        .setMessage(profile.displayName)
        .setNegativeButton(R.string.common_cancel, null)
        .setPositiveButton(R.string.common_delete) { _, _ ->
            runCatching { LocalModelManager.delete(this, profile) }
                .onFailure { error ->
                    Toast.makeText(this, error.message.orEmpty(), Toast.LENGTH_LONG).show()
                }
            showLocalModelFeaturePage()
        }
        .show()
}

internal fun MainActivity.showLocalModelSearchPage() {
    localModelSearchGeneration.incrementAndGet()
    showFeaturePage(getString(R.string.local_model_search_title))
    setFeatureBackAction { showLocalModelFeaturePage() }
    featureContent.addView(TextView(this).apply {
        text = getString(R.string.local_model_search_subtitle)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 13f
        setPadding(dp(4), 0, dp(4), dp(12))
    })
    val input = EditText(this).apply {
        hint = getString(R.string.local_model_search_hint)
        setSingleLine(true)
        textSize = 15f
        inputType = InputType.TYPE_CLASS_TEXT
        imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH
        setPadding(dp(14), 0, dp(12), 0)
        background = getDrawable(R.drawable.glass_card_background)
    }
    val searchButton = TextView(this).apply {
        text = getString(R.string.local_model_search_action)
        gravity = Gravity.CENTER
        setTextColor(Color.WHITE)
        textSize = 14f
        setTypeface(typeface, android.graphics.Typeface.BOLD)
        background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(10).toFloat()
            setColor(getColorCompat(R.color.signalasi_green))
        }
    }
    val results = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
    }
    val submit = {
        val query = input.text?.toString().orEmpty().trim()
        if (query.length >= 2) performLocalModelSearch(query, results)
    }
    featureContent.addView(LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(input, LinearLayout.LayoutParams(0, dp(52), 1f))
        addView(searchButton, LinearLayout.LayoutParams(dp(76), dp(44)).apply {
            leftMargin = dp(8)
        })
    }, LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT
    ).apply { bottomMargin = dp(14) })
    featureContent.addView(results)
    searchButton.setOnClickListener { submit() }
    input.setOnEditorActionListener { _, actionId, _ ->
        if (actionId == android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH) {
            submit()
            true
        } else {
            false
        }
    }
    input.requestFocus()
}

internal fun MainActivity.performLocalModelSearch(query: String, container: LinearLayout) {
    val generation = localModelSearchGeneration.incrementAndGet()
    container.removeAllViews()
    container.addView(localModelMessageRow(getString(R.string.local_model_searching)))
    cloudExecutor.execute {
        val result = runCatching {
            HuggingFaceModelSearch(
                preferChinaSource = LocalModelManager.preferChinaMirror(this)
            ).search(query)
        }
        handler.post {
            if (generation != localModelSearchGeneration.get()) return@post
            container.removeAllViews()
            result.onSuccess { models ->
                if (models.isEmpty()) {
                    container.addView(localModelMessageRow(getString(R.string.local_model_search_empty)))
                } else {
                    models.forEach { model ->
                        container.addView(featureRow(
                            model.displayName,
                            getString(
                                R.string.local_model_repository_downloads,
                                model.author,
                                compactCount(model.downloads)
                            ) + " · ${model.source.displayName}",
                            R.drawable.ic_local_model,
                            getString(R.string.common_select)
                        ).apply {
                            setOnClickListener { showLocalModelArtifactPage(model) }
                        })
                    }
                }
            }.onFailure { error ->
                container.addView(localModelMessageRow(getString(
                    R.string.local_model_search_error,
                    error.message.orEmpty()
                )))
            }
        }
    }
}

internal fun MainActivity.showLocalModelArtifactPage(model: HuggingFaceModelResult) {
    val generation = localModelSearchGeneration.incrementAndGet()
    showFeaturePage(model.displayName)
    setFeatureBackAction { showLocalModelSearchPage() }
    featureContent.addView(TextView(this).apply {
        text = getString(R.string.local_model_artifact_subtitle)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 13f
        setPadding(dp(4), 0, dp(4), dp(12))
    })
    val container = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    container.addView(localModelMessageRow(getString(R.string.local_model_artifact_loading)))
    featureContent.addView(container)
    cloudExecutor.execute {
        val result = runCatching {
            HuggingFaceModelSearch(
                preferChinaSource = LocalModelManager.preferChinaMirror(this)
            ).artifacts(model)
        }
        handler.post {
            if (generation != localModelSearchGeneration.get()) return@post
            container.removeAllViews()
            result.onSuccess { artifacts ->
                if (artifacts.isEmpty()) {
                    container.addView(localModelMessageRow(getString(R.string.local_model_artifact_empty)))
                } else {
                    artifacts.forEach { artifact ->
                        val parameterLabel = if (artifact.parameterCountBillions % 1.0 == 0.0) {
                            artifact.parameterCountBillions.toInt().toString()
                        } else {
                            String.format(Locale.US, "%.1f", artifact.parameterCountBillions)
                        }
                        container.addView(featureRow(
                            artifact.fileName.removeSuffix(".gguf").replace('_', ' '),
                            getString(
                                R.string.local_model_size_and_quantization,
                                formatBytes(artifact.sizeBytes),
                                artifact.quantization,
                                parameterLabel
                            ),
                            R.drawable.ic_local_model,
                            getString(R.string.local_model_download_action)
                        ).apply {
                            setOnClickListener {
                                val profile = LocalModelCatalog.addHubArtifact(this@showLocalModelArtifactPage, artifact)
                                showLocalModelFeaturePage()
                                requestLocalModelDownload(profile)
                            }
                        })
                    }
                }
            }.onFailure { error ->
                container.addView(localModelMessageRow(getString(
                    R.string.local_model_search_error,
                    error.message.orEmpty()
                )))
            }
        }
    }
}

internal fun MainActivity.localModelMessageRow(message: String): View = TextView(this).apply {
    text = message
    setTextColor(getColorCompat(R.color.text_secondary))
    textSize = 13f
    gravity = Gravity.CENTER
    setPadding(dp(16), dp(24), dp(16), dp(24))
}

internal fun MainActivity.compactCount(value: Long): String = when {
    value >= 1_000_000L -> String.format(Locale.US, "%.1fM", value / 1_000_000.0)
    value >= 1_000L -> String.format(Locale.US, "%.1fK", value / 1_000.0)
    else -> value.toString()
}

internal fun MainActivity.showDeviceFeaturePage(returnToContacts: Boolean = false) {
    val homeAssistant = HomeAssistantSettingsStore.load(this)
    val customDevices = CustomDeviceConnectorStore(this).list()
    val pairedDesktopCount = desktopSecuritySummaries(activePcConnectorContacts()).size
    val desktopOnline = pairedDesktopCount > 0 && SignalASIMqttClient.isConnected()
    val visibleDeviceCount = 1 + customDevices.size +
        (if (pairedDesktopCount > 0) pairedDesktopCount else 0) +
        (if (homeAssistant.configured) 1 else 0)
    showFeaturePage(getString(R.string.device_management_title))
    if (returnToContacts) {
        setFeatureBackAction {
            hideFeaturePage()
            showConversationHub(ConversationHubTab.CONTACTS)
        }
    }
    featureContent.addView(featureHeroCard(getString(R.string.device_management_title), getString(R.string.device_management_subtitle), R.drawable.ic_device_node, "#5B6CFF", getString(R.string.count_devices, visibleDeviceCount)))
    addSectionTitle(getString(R.string.section_my_devices))
    featureContent.addView(featureRow("Phone Agent", getString(R.string.device_phone_agent_subtitle), R.drawable.ic_device_node, getString(R.string.status_online)))
    featureContent.addView(featureRow(
        "PC Agent",
        getString(R.string.device_pc_agent_subtitle),
        R.drawable.ic_device_node,
        getString(
            when {
                desktopOnline -> R.string.status_online
                pairedDesktopCount > 0 -> R.string.status_disconnected
                else -> R.string.status_needs_setup
            }
        )
    ))
    featureContent.addView(featureRow(
        getString(R.string.device_home_assistant),
        getString(R.string.device_home_assistant_subtitle),
        R.drawable.ic_device_node,
        getString(if (homeAssistant.configured) R.string.device_home_assistant_configured else R.string.device_home_assistant_not_configured)
    ))
    customDevices.forEach { connector ->
        featureContent.addView(featureRow(
            connector.name,
            connector.transport.name.replace('_', ' '),
            R.drawable.ic_device_node,
            getString(if (connector.configured) R.string.status_enabled else R.string.common_needs_setup)
        ).apply {
            setOnClickListener { showCustomDeviceConnectorEditor(connector, returnToContacts) }
        })
    }
    featureContent.addView(featureRow(
        getString(R.string.device_custom_add),
        getString(R.string.device_custom_add_subtitle),
        R.drawable.ic_device_node,
        "+"
    ).apply {
        setOnClickListener {
            showCustomDeviceConnectorEditor(
                CustomDeviceConnector(
                    name = getString(R.string.device_custom_default_name),
                    transport = CustomDeviceTransport.HTTP_REST,
                    endpoint = ""
                ),
                returnToContacts
            )
        }
    })
    addSectionTitle(getString(R.string.device_home_assistant))
    featureContent.addView(featureRow(getString(R.string.device_home_assistant), getString(R.string.device_home_assistant_subtitle), R.drawable.ic_security_shield, onOffLabel(homeAssistant.enabled)).apply {
        setOnClickListener {
            HomeAssistantSettingsStore.setEnabled(this@showDeviceFeaturePage, !homeAssistant.enabled)
            showDeviceFeaturePage(returnToContacts)
        }
    })
    featureContent.addView(featureRow(getString(R.string.device_home_assistant_url), homeAssistant.baseUrl.ifBlank { getString(R.string.device_home_assistant_url_subtitle) }, R.drawable.ic_protocol_link, getString(R.string.common_edit)).apply {
        setOnClickListener {
            showTextSettingDialog(getString(R.string.device_home_assistant_url), homeAssistant.baseUrl) {
                HomeAssistantSettingsStore.setBaseUrl(this@showDeviceFeaturePage, it)
                showDeviceFeaturePage(returnToContacts)
            }
        }
    })
    featureContent.addView(featureRow(getString(R.string.device_home_assistant_token), maskedSecret(homeAssistant.accessToken).ifBlank { getString(R.string.device_home_assistant_token_subtitle) }, R.drawable.ic_security_shield, getString(R.string.common_edit)).apply {
        setOnClickListener {
            showTextSettingDialog(getString(R.string.device_home_assistant_token), homeAssistant.accessToken) {
                HomeAssistantSettingsStore.setAccessToken(this@showDeviceFeaturePage, it)
                showDeviceFeaturePage(returnToContacts)
            }
        }
    })
    featureContent.addView(featureRow(getString(R.string.device_home_assistant_default_entity), homeAssistant.defaultEntityId.ifBlank { getString(R.string.device_home_assistant_default_entity_subtitle) }, R.drawable.ic_device_node, getString(R.string.common_edit)).apply {
        setOnClickListener {
            showTextSettingDialog(getString(R.string.device_home_assistant_default_entity), homeAssistant.defaultEntityId) {
                HomeAssistantSettingsStore.setDefaultEntityId(this@showDeviceFeaturePage, it)
                showDeviceFeaturePage(returnToContacts)
            }
        }
    })
    addSectionTitle(getString(R.string.section_device_capabilities))
    featureContent.addView(featureRow(
        getString(R.string.device_file_sync),
        getString(R.string.device_file_sync_subtitle),
        R.drawable.ic_import,
        getString(if (desktopOnline) R.string.status_enabled else R.string.status_needs_setup)
    ))
    featureContent.addView(featureRow(
        getString(R.string.device_remote_control),
        getString(R.string.device_remote_control_subtitle),
        R.drawable.ic_security_shield,
        getString(
            when {
                pairedDesktopCount == 0 -> R.string.status_needs_setup
                desktopSecuritySummaries(activePcConnectorContacts()).any {
                    DesktopRemoteControl.snapshot(this, it.id).authorized
                } -> R.string.status_enabled
                else -> R.string.status_protected
            }
        )
    ).apply {
        setOnClickListener { showDesktopControlPicker() }
    })
}

internal fun MainActivity.desktopControlDevices(): List<DesktopSecuritySummary> {
    val fromContacts = desktopSecuritySummaries(activePcConnectorContacts()).associateBy { it.id }.toMutableMap()
    SignalASILinkProtocol.allServerLinks(this).filter { it.paired }.forEach { link ->
        fromContacts.putIfAbsent(
            link.desktopId,
            DesktopSecuritySummary(
                id = link.desktopId,
                name = link.desktopName,
                fingerprint = link.desktopFingerprint,
                agentCount = 0,
                lastActivityAt = 0L,
                agentIds = emptySet()
            )
        )
    }
    return fromContacts.values.sortedBy { it.name.lowercase(Locale.ROOT) }
}

internal fun MainActivity.showDesktopControlPicker() {
    val devices = desktopControlDevices()
    if (devices.size == 1) {
        DesktopRemoteControl.requestAuthorizations(devices.single().id)
        showDesktopRemoteControlPage(devices.single())
        return
    }
    showFeaturePage(getString(R.string.desktop_control_title))
    setFeatureBackAction { showDeviceFeaturePage() }
    featureContent.addView(featureHeroCard(
        getString(R.string.desktop_control_title),
        getString(R.string.desktop_control_picker_subtitle),
        R.drawable.ic_device_node,
        "#2878FF",
        getString(R.string.count_devices, devices.size)
    ))
    addSectionTitle(getString(R.string.desktop_control_computers))
    if (devices.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.security_no_paired_pc),
            getString(R.string.security_no_paired_pc_subtitle),
            R.drawable.ic_device_node,
            getString(R.string.security_scan)
        ).apply {
            setOnClickListener {
                scanMode = "security"
                startSecurityScan()
            }
        })
    } else {
        devices.forEach { device ->
            val snapshot = DesktopRemoteControl.snapshot(this, device.id)
            featureContent.addView(featureRow(
                device.name,
                formatFingerprint(device.fingerprint),
                R.drawable.ic_device_node,
                getString(
                    when {
                        snapshot.authorized -> R.string.status_enabled
                        snapshot.pending -> R.string.desktop_control_pending
                        else -> R.string.security_manage
                    }
                )
            ).apply {
                setOnClickListener {
                    DesktopRemoteControl.requestAuthorizations(device.id)
                    showDesktopRemoteControlPage(device)
                }
            })
        }
    }
}

internal fun MainActivity.showDesktopRemoteControlPage(device: DesktopSecuritySummary) {
    val snapshot = DesktopRemoteControl.snapshot(this, device.id)
    showFeaturePage(getString(R.string.desktop_control_title), device.id)
    activeDesktopControlId = device.id
    activeDesktopPerceptionId = null
    setFeatureBackAction { showDesktopControlPicker() }
    featureContent.addView(featureHeroCard(
        device.name,
        getString(R.string.desktop_control_trusted_subtitle),
        R.drawable.ic_device_node,
        when {
            snapshot.authorized -> "#14C66A"
            snapshot.pending -> "#F0A500"
            else -> "#8A939B"
        },
        getString(
            when {
                snapshot.authorized -> R.string.desktop_control_authorized
                snapshot.pending -> R.string.desktop_control_pending
                !snapshot.fullDesktopExecutor -> R.string.desktop_control_repair_executor_required
                !snapshot.enabled -> R.string.desktop_control_executor_off
                else -> R.string.desktop_control_not_authorized
            }
        )
    ))

    addSectionTitle(getString(R.string.desktop_control_surfaces))
    val surfaceCatalog = snapshot.surfaceCatalog
    featureContent.addView(featureRow(
        surfaceCatalog?.targetTitle
            ?.takeIf(String::isNotBlank)
            ?: getString(R.string.desktop_control_surface_select),
        surfaceCatalog?.let {
            getString(
                R.string.desktop_control_surface_summary,
                it.targetBounds.width,
                it.targetBounds.height,
                it.displays.size,
                it.windows.size
            )
        } ?: getString(R.string.desktop_control_surface_select_subtitle),
        R.drawable.ic_agent_screen,
        getString(
            if (surfaceCatalog == null) {
                R.string.desktop_control_surface_load
            } else {
                R.string.desktop_control_surface_change
            }
        )
    ).apply {
        isEnabled = snapshot.authorized
        alpha = if (snapshot.authorized) 1f else 0.5f
        setOnClickListener {
            if (surfaceCatalog == null) {
                if (!DesktopRemoteControl.requestSurfaces(device.id)) {
                    Toast.makeText(
                        this@showDesktopRemoteControlPage,
                        getString(R.string.desktop_control_request_failed),
                        Toast.LENGTH_SHORT
                    ).show()
                }
            } else {
                showDesktopSurfaceDialog(device, surfaceCatalog)
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_surface_refresh),
        getString(R.string.desktop_control_surface_refresh_subtitle),
        R.drawable.ic_import,
        getString(R.string.desktop_control_surface_refresh_action)
    ).apply {
        isEnabled = snapshot.authorized
        alpha = if (snapshot.authorized) 1f else 0.5f
        setOnClickListener {
            if (!DesktopRemoteControl.requestSurfaces(device.id)) {
                Toast.makeText(
                    this@showDesktopRemoteControlPage,
                    getString(R.string.desktop_control_request_failed),
                    Toast.LENGTH_SHORT
                ).show()
            }
        }
    })

    addSectionTitle(getString(R.string.desktop_control_live_display))
    val screenshotFrame = FrameLayout(this).apply {
        background = GradientDrawable().apply {
            cornerRadius = dp(8).toFloat()
            setColor(Color.parseColor("#11161C"))
        }
        clipToOutline = true
    }
    val screenshotView = DesktopRemoteScreenView(this).apply {
        setScreenContentDescription(getString(R.string.desktop_control_screen_content_description))
    }
    activeDesktopScreenView = screenshotView
    screenshotFrame.addView(screenshotView, FrameLayout.LayoutParams(
        FrameLayout.LayoutParams.MATCH_PARENT,
        FrameLayout.LayoutParams.MATCH_PARENT
    ))
    val placeholder = TextView(this).apply {
        text = getString(
            when {
                snapshot.authorized -> R.string.desktop_control_tap_refresh
                !snapshot.fullDesktopExecutor -> R.string.desktop_control_repair_executor_required
                else -> R.string.desktop_control_authorization_required
            }
        )
        gravity = Gravity.CENTER
        setTextColor(Color.parseColor("#AAB3BD"))
        textSize = 14f
    }
    activeDesktopScreenPlaceholder = placeholder
    screenshotFrame.addView(placeholder, FrameLayout.LayoutParams(
        FrameLayout.LayoutParams.MATCH_PARENT,
        FrameLayout.LayoutParams.MATCH_PARENT
    ))
    snapshot.screenshot?.let { screenshot ->
        android.graphics.BitmapFactory.decodeByteArray(
            screenshot.jpegBytes,
            0,
            screenshot.jpegBytes.size
        )?.let(screenshotView::setScreenshot)
        placeholder.visibility = View.GONE
    }
    if (snapshot.authorized) {
        screenshotView.onImageTap = tap@ { xRatio, yRatio ->
            val latest = DesktopRemoteControl.snapshot(this, device.id).screenshot
                ?: return@tap
            val x = (xRatio * latest.originalWidth).roundToInt()
                .coerceIn(0, latest.originalWidth - 1)
            val y = (yRatio * latest.originalHeight).roundToInt()
                .coerceIn(0, latest.originalHeight - 1)
            if (DesktopRemoteControl.click(
                    device.id,
                    x,
                    y,
                    latest.originalWidth,
                    latest.originalHeight
                )
            ) {
                Toast.makeText(
                    this@showDesktopRemoteControlPage,
                    getString(R.string.desktop_control_click_sent, x, y),
                    Toast.LENGTH_SHORT
                ).show()
            }
        }
    }
    featureContent.addView(screenshotFrame, LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        dp(432)
    ).apply {
        topMargin = dp(2)
    })
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_refresh_screen),
        snapshot.screenshot?.let {
            getString(
                R.string.desktop_control_screen_metadata,
                it.originalWidth,
                it.originalHeight,
                it.jpegBytes.size / 1024f,
                securityTime(it.capturedAt)
            )
        }.orEmpty().ifBlank { getString(R.string.desktop_control_refresh_screen_subtitle) },
        R.drawable.ic_import,
        getString(R.string.common_view)
    ).apply {
        isEnabled = snapshot.authorized
        alpha = if (snapshot.authorized) 1f else 0.5f
        setOnClickListener {
            if (DesktopRemoteControl.requestScreenshot(device.id)) {
                Toast.makeText(this@showDesktopRemoteControlPage, getString(R.string.desktop_control_request_sent), Toast.LENGTH_SHORT).show()
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_stream_title),
        getString(R.string.desktop_control_stream_subtitle),
        R.drawable.ic_agent_screen,
        if (snapshot.streamFps > 0) {
            getString(R.string.desktop_control_stream_rate, snapshot.streamFps)
        } else {
            getString(R.string.common_off)
        }
    ).apply {
        isEnabled = snapshot.authorized
        alpha = if (snapshot.authorized) 1f else 0.5f
        setOnClickListener {
            val labels = arrayOf(
                getString(R.string.common_off),
                getString(R.string.desktop_control_stream_rate, 1),
                getString(R.string.desktop_control_stream_rate, 2),
                getString(R.string.desktop_control_stream_rate, 3)
            )
            android.app.AlertDialog.Builder(this@showDesktopRemoteControlPage)
                .setTitle(getString(R.string.desktop_control_stream_dialog_title))
                .setSingleChoiceItems(
                    labels,
                    snapshot.streamFps.coerceIn(0, DESKTOP_SCREENSHOT_STREAM_MAX_FPS)
                ) { dialog, selected ->
                    if (selected == 0) {
                        DesktopRemoteControl.stopScreenshotStream(device.id)
                    } else {
                        DesktopRemoteControl.startScreenshotStream(device.id, selected)
                    }
                    dialog.dismiss()
                    showDesktopRemoteControlPage(device)
                }
                .setNegativeButton(getString(R.string.common_cancel), null)
                .show()
        }
    })

    featureContent.addView(featureRow(
        getString(R.string.desktop_perception_title),
        snapshot.perception?.let {
            getString(
                R.string.desktop_perception_summary,
                it.uiElementCount,
                it.ocrCharacterCount,
                securityTime(it.capturedAt)
            )
        } ?: getString(R.string.desktop_perception_subtitle),
        R.drawable.ic_agent_screen,
        getString(
            if (snapshot.perception == null) {
                R.string.desktop_perception_capture_action
            } else {
                R.string.common_view
            }
        )
    ).apply {
        isEnabled = snapshot.authorized
        alpha = if (snapshot.authorized) 1f else 0.5f
        setOnClickListener {
            if (snapshot.perception == null) {
                if (DesktopRemoteControl.requestPerception(device.id)) {
                    Toast.makeText(
                        this@showDesktopRemoteControlPage,
                        getString(R.string.desktop_control_request_sent),
                        Toast.LENGTH_SHORT
                    ).show()
                } else {
                    Toast.makeText(
                        this@showDesktopRemoteControlPage,
                        getString(R.string.desktop_control_request_failed),
                        Toast.LENGTH_SHORT
                    ).show()
                }
            } else {
                showDesktopPerceptionPage(device)
            }
        }
    })

    if (snapshot.lastActionSummary.isNotBlank()) {
        featureContent.addView(featureRow(
            getString(R.string.desktop_control_latest_action),
            if (snapshot.lastActionSummary == "desktop_action_receipt_unverified") {
                getString(R.string.desktop_control_receipt_unverified)
            } else {
                snapshot.lastActionSummary
            },
            R.drawable.ic_agent_history,
            desktopControlStatusLabel(snapshot.lastActionStatus)
        ))
    }

    addSectionTitle(getString(R.string.desktop_control_active_runs))
    if (snapshot.activeRuns.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.desktop_control_no_active_runs),
            getString(R.string.desktop_control_no_active_runs_subtitle),
            R.drawable.ic_agent_history,
            getString(R.string.status_ready)
        ))
    } else {
        snapshot.activeRuns.forEach { run ->
            val title = run.prompt
                .replace(Regex("\\s+"), " ")
                .trim()
                .ifBlank { getString(R.string.agent_task_details_title) }
                .take(48)
            val subtitle = run.currentStep.ifBlank {
                getString(
                    when (run.status) {
                        "paused" -> R.string.desktop_control_run_paused
                        "takeover" -> R.string.desktop_control_run_takeover
                        else -> R.string.agent_task_status_running
                    }
                )
            }
            featureContent.addView(featureRow(
                title,
                subtitle,
                R.drawable.ic_agent_history,
                getString(
                    when (run.status) {
                        "paused" -> R.string.desktop_control_run_paused
                        "takeover" -> R.string.desktop_control_run_takeover
                        else -> R.string.agent_task_status_running
                    }
                )
            ).apply {
                isEnabled = snapshot.authorized
                alpha = if (snapshot.authorized) 1f else 0.5f
                setOnClickListener {
                    showDesktopRunActions(device, run)
                }
            })
        }
    }

    addSectionTitle(getString(R.string.desktop_control_actions))
    featureContent.addView(desktopControlButtonRow(
        getString(R.string.desktop_control_scroll_up) to { DesktopRemoteControl.scroll(device.id, 480) },
        getString(R.string.desktop_control_scroll_down) to { DesktopRemoteControl.scroll(device.id, -480) },
        enabled = snapshot.authorized
    ))
    featureContent.addView(desktopControlButtonRow(
        getString(R.string.desktop_control_next_window) to {
            DesktopRemoteControl.windowSwitch(device.id)
        },
        getString(R.string.desktop_control_previous_window) to {
            DesktopRemoteControl.windowSwitch(device.id, previous = true)
        },
        enabled = snapshot.authorized
    ))
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_type_text),
        getString(R.string.desktop_control_type_text_subtitle),
        R.drawable.ic_protocol_link,
        getString(R.string.common_edit)
    ).apply {
        isEnabled = snapshot.authorized
        alpha = if (snapshot.authorized) 1f else 0.5f
        setOnClickListener {
            showTextSettingDialog(getString(R.string.desktop_control_type_text), "") { text ->
                if (!DesktopRemoteControl.typeText(device.id, text)) {
                    Toast.makeText(this@showDesktopRemoteControlPage, getString(R.string.desktop_control_request_failed), Toast.LENGTH_SHORT).show()
                }
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_select_file),
        getString(R.string.desktop_control_select_file_subtitle),
        R.drawable.ic_rich_file,
        getString(R.string.common_select)
    ).apply {
        isEnabled = snapshot.authorized
        alpha = if (snapshot.authorized) 1f else 0.5f
        setOnClickListener {
            showTextSettingDialog(
                getString(R.string.desktop_control_select_file),
                ""
            ) { path ->
                if (!DesktopRemoteControl.selectFile(device.id, path)) {
                    Toast.makeText(
                        this@showDesktopRemoteControlPage,
                        getString(R.string.desktop_control_request_failed),
                        Toast.LENGTH_SHORT
                    ).show()
                }
            }
        }
    })

    addSectionTitle(getString(R.string.desktop_control_authorization))
    val desktopFingerprint = snapshot.desktopFingerprint.ifBlank { device.fingerprint }
    featureContent.addView(featureRow(
        getString(R.string.security_desktop_fingerprint),
        formatFingerprint(desktopFingerprint),
        R.drawable.ic_security_shield,
        getString(R.string.common_copy)
    ).apply {
        isEnabled = desktopFingerprint.isNotBlank()
        setOnClickListener {
            copyText(desktopFingerprint, getString(R.string.security_copied_desktop_fingerprint))
        }
    })
    addSectionTitle(getString(R.string.desktop_control_authorized_apps))
    if (snapshot.authorizations.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.desktop_control_no_authorized_apps),
            getString(R.string.desktop_control_no_authorized_apps_subtitle),
            R.drawable.signalasi_mark,
            ""
        ))
    }
    snapshot.authorizations.forEach { authorization ->
        val timeSummary = when {
            authorization.grantedAt > 0L && authorization.lastUsedAt > 0L -> getString(
                R.string.desktop_control_granted_and_used,
                securityTime(authorization.grantedAt),
                securityTime(authorization.lastUsedAt)
            )
            authorization.grantedAt > 0L -> getString(
                R.string.desktop_control_granted_at,
                securityTime(authorization.grantedAt)
            )
            else -> getString(R.string.desktop_control_never_used)
        }
        featureContent.addView(featureRow(
            authorization.appName.ifBlank {
                authorization.phoneName.ifBlank { getString(R.string.desktop_control_this_phone) }
            },
            listOf(
                listOf(
                    authorization.appPlatform.ifBlank { "Android" },
                    formatFingerprint(authorization.phoneFingerprint)
                ).filter { it.isNotBlank() }.joinToString(" · "),
                timeSummary
            )
                .filter { it.isNotBlank() }
                .joinToString("\n"),
            R.drawable.signalasi_mark,
            desktopControlStatusLabel(authorization.status)
        ).apply {
            setOnClickListener {
                showDesktopAuthorizationRecordPage(device, authorization)
            }
        })
    }
    addSectionTitle(getString(R.string.desktop_control_recent_activity))
    if (snapshot.recentReceipts.isEmpty() && snapshot.recentAudit.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.desktop_control_no_recent_activity),
            "",
            R.drawable.ic_agent_history,
            ""
        ))
    } else {
        snapshot.recentReceipts.take(12).forEach { receipt ->
            featureContent.addView(featureRow(
                receipt.summary.ifBlank { receipt.toolId },
                getString(
                    R.string.desktop_control_verified_receipt,
                    securityTime(receipt.completedAt),
                    receipt.receiptId.take(8)
                ),
                R.drawable.ic_security_shield,
                desktopControlStatusLabel(receipt.status)
            ).apply {
                setOnClickListener {
                    showDesktopActionReceiptPage(device, receipt)
                }
            })
        }
        snapshot.recentAudit
            .filter { it.eventType != "desktop_action" }
            .take((12 - snapshot.recentReceipts.size).coerceAtLeast(0))
            .forEach { event ->
                featureContent.addView(featureRow(
                    event.summary.ifBlank { event.eventType },
                    securityTime(event.createdAt),
                    R.drawable.ic_agent_history,
                    desktopControlStatusLabel(event.status)
                ))
            }
    }
    featureContent.addView(TextView(this).apply {
        text = getString(R.string.desktop_control_security_footer)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 12f
        setPadding(dp(4), dp(14), dp(4), dp(20))
    })
}

internal fun MainActivity.showDesktopSurfaceDialog(
    device: DesktopSecuritySummary,
    catalog: DesktopSurfaceCatalog
) {
    val labels = mutableListOf<String>()
    val actions = mutableListOf<() -> Boolean>()
    var selectedIndex = -1
    catalog.displays.forEachIndexed { index, display ->
        if (catalog.selection.windowId.isBlank() &&
            catalog.selection.displayId == display.displayId
        ) {
            selectedIndex = labels.size
        }
        labels += getString(
            R.string.desktop_control_surface_display_option,
            index + 1,
            display.name,
            display.bounds.width,
            display.bounds.height
        )
        actions += {
            DesktopRemoteControl.selectDisplay(device.id, display.displayId)
        }
    }
    catalog.windows.forEach { window ->
        if (catalog.selection.windowId == window.windowId) {
            selectedIndex = labels.size
        }
        labels += getString(
            R.string.desktop_control_surface_window_option,
            window.title.ifBlank { getString(R.string.desktop_control_surface_untitled_window) },
            window.bounds.width,
            window.bounds.height
        )
        actions += {
            DesktopRemoteControl.activateWindow(device.id, window.windowId)
        }
    }
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.desktop_control_surface_dialog_title))
        .setSingleChoiceItems(
            labels.toTypedArray(),
            selectedIndex
        ) { dialog, index ->
            val sent = actions.getOrNull(index)?.invoke() == true
            Toast.makeText(
                this@showDesktopSurfaceDialog,
                getString(
                    if (sent) {
                        R.string.desktop_control_request_sent
                    } else {
                        R.string.desktop_control_request_failed
                    }
                ),
                Toast.LENGTH_SHORT
            ).show()
            if (sent) dialog.dismiss()
        }
        .setNegativeButton(R.string.common_cancel, null)
        .show()
}
