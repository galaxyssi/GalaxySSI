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

internal fun MainActivity.showDesktopPerceptionPage(device: DesktopSecuritySummary) {
    val remote = DesktopRemoteControl.snapshot(this, device.id)
    val perception = remote.perception
    showFeaturePage(getString(R.string.desktop_perception_detail), device.id)
    activeDesktopControlId = device.id
    activeDesktopPerceptionId = device.id
    setFeatureBackAction { showDesktopRemoteControlPage(device) }

    featureContent.addView(featureHeroCard(
        perception?.activeWindowTitle
            ?.takeIf(String::isNotBlank)
            ?.take(90)
            ?: getString(R.string.desktop_perception_empty),
        perception?.let {
            getString(
                R.string.desktop_perception_capture_summary,
                securityTime(it.capturedAt),
                it.durationMillis,
                it.preferredGrounding
            )
        } ?: getString(R.string.desktop_perception_subtitle),
        R.drawable.ic_agent_screen,
        if (perception == null) "#8A939B" else "#14C66A",
        getString(
            if (perception == null) {
                R.string.desktop_perception_unavailable
            } else {
                R.string.desktop_perception_available
            }
        )
    ))
    featureContent.addView(featureRow(
        getString(R.string.desktop_perception_refresh),
        getString(R.string.desktop_perception_refresh_subtitle),
        R.drawable.ic_import,
        getString(R.string.desktop_perception_refresh_action)
    ).apply {
        isEnabled = remote.authorized
        alpha = if (remote.authorized) 1f else 0.5f
        setOnClickListener {
            if (!DesktopRemoteControl.requestPerception(device.id)) {
                Toast.makeText(
                    this@showDesktopPerceptionPage,
                    getString(R.string.desktop_control_request_failed),
                    Toast.LENGTH_SHORT
                ).show()
            }
        }
    })
    if (perception == null) {
        featureContent.addView(TextView(this).apply {
            text = getString(R.string.desktop_perception_evidence_notice)
            setTextColor(getColorCompat(R.color.text_secondary))
            textSize = 12f
            setPadding(dp(4), dp(12), dp(4), dp(20))
        })
        return
    }

    addSectionTitle(getString(R.string.desktop_perception_layers))
    featureContent.addView(featureRow(
        getString(R.string.desktop_perception_screenshot_layer),
        getString(R.string.desktop_perception_screenshot_subtitle),
        R.drawable.ic_agent_screen,
        desktopPerceptionLayerLabel(perception.screenshotStatus)
    ))
    featureContent.addView(featureRow(
        getString(R.string.desktop_perception_ui_tree),
        perception.uiTreeError.ifBlank {
            getString(
                R.string.desktop_perception_ui_tree_summary,
                perception.uiElementCount,
                getString(
                    if (perception.uiTreeTruncated) {
                        R.string.desktop_perception_truncated
                    } else {
                        R.string.desktop_perception_complete
                    }
                )
            )
        },
        R.drawable.ic_agent_control,
        desktopPerceptionLayerLabel(perception.uiTreeStatus)
    ))
    featureContent.addView(featureRow(
        getString(R.string.desktop_perception_ocr),
        perception.ocrError.ifBlank {
            getString(
                R.string.desktop_perception_ocr_summary,
                perception.ocrCharacterCount,
                perception.ocrLineCount,
                getString(
                    if (perception.ocrTruncated) {
                        R.string.desktop_perception_truncated
                    } else {
                        R.string.desktop_perception_complete
                    }
                )
            )
        },
        R.drawable.ic_agent_memory,
        desktopPerceptionLayerLabel(perception.ocrStatus)
    ))

    addSectionTitle(getString(R.string.desktop_perception_recognized_text))
    featureContent.addView(TextView(this).apply {
        text = perception.ocrText.ifBlank {
            getString(R.string.desktop_perception_no_text)
        }
        setTextColor(getColorCompat(R.color.text_primary))
        textSize = 14f
        setTextIsSelectable(true)
        setPadding(dp(14), dp(12), dp(14), dp(12))
        background = getDrawable(R.drawable.glass_card_background)
    }, LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT
    ).apply {
        bottomMargin = dp(12)
    })

    addSectionTitle(getString(R.string.desktop_perception_ui_elements))
    val visibleElements = perception.uiElements
        .asSequence()
        .filter { !it.offscreen && (it.name.isNotBlank() || it.actions.isNotEmpty()) }
        .take(40)
        .toList()
    if (visibleElements.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.desktop_perception_no_elements),
            "",
            R.drawable.ic_agent_control,
            ""
        ))
    } else {
        visibleElements.forEach { element ->
            val elementTitle = element.name
                .takeIf(String::isNotBlank)
                ?: element.controlType
                .takeIf(String::isNotBlank)
                ?: element.id
            val details = buildList {
                add(getString(
                    R.string.desktop_perception_element_bounds,
                    element.controlType.ifBlank { element.className },
                    element.left,
                    element.top,
                    element.width,
                    element.height
                ))
                element.actions.takeIf { it.isNotEmpty() }
                    ?.joinToString(" · ")
                    ?.let(::add)
            }.joinToString("\n")
            featureContent.addView(featureRow(
                elementTitle.take(120),
                details,
                R.drawable.ic_agent_control,
                if (element.actions.isEmpty()) {
                    ""
                } else {
                    getString(
                        R.string.desktop_perception_element_actions,
                        element.actions.size
                    )
                }
            ))
        }
    }
    featureContent.addView(TextView(this).apply {
        text = getString(R.string.desktop_perception_evidence_notice)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 12f
        setPadding(dp(4), dp(12), dp(4), dp(20))
    })
}

internal fun MainActivity.desktopPerceptionLayerLabel(status: String): String = getString(
    when (status) {
        "available" -> R.string.desktop_perception_available
        "disabled" -> R.string.desktop_perception_disabled
        else -> R.string.desktop_perception_unavailable
    }
)

internal fun MainActivity.showDesktopAuthorizationRecordPage(
    device: DesktopSecuritySummary,
    authorization: DesktopControlAuthorization
) {
    showFeaturePage(getString(R.string.desktop_control_authorization_detail))
    activeDesktopControlId = device.id
    setFeatureBackAction { showDesktopRemoteControlPage(device) }
    val active = authorization.status == "active"
    featureContent.addView(featureHeroCard(
        authorization.appName.ifBlank {
            authorization.phoneName.ifBlank { getString(R.string.desktop_control_this_phone) }
        },
        getString(
            R.string.desktop_control_authorization_app_subtitle,
            authorization.appPlatform.ifBlank { "Android" }
        ),
        R.drawable.signalasi_mark,
        if (active) "#14C66A" else "#8A939B",
        desktopControlStatusLabel(authorization.status)
    ))

    addSectionTitle(getString(R.string.security_section_identity))
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_app_instance_id),
        authorization.appInstanceId,
        R.drawable.ic_protocol_link,
        getString(R.string.common_copy)
    ).apply {
        isEnabled = authorization.appInstanceId.isNotBlank()
        setOnClickListener {
            copyText(
                authorization.appInstanceId,
                getString(R.string.desktop_control_copied_app_instance_id)
            )
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.settings_identity_fingerprint),
        formatFingerprint(authorization.phoneFingerprint),
        R.drawable.ic_settings_fingerprint,
        getString(R.string.common_copy)
    ).apply {
        isEnabled = authorization.phoneFingerprint.isNotBlank()
        setOnClickListener {
            copyText(
                authorization.phoneFingerprint,
                getString(R.string.security_copied_phone_fingerprint)
            )
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_authorization_id),
        authorization.authorizationId,
        R.drawable.ic_security_shield,
        getString(R.string.common_copy)
    ).apply {
        setOnClickListener {
            copyText(
                authorization.authorizationId,
                getString(R.string.desktop_control_copied_authorization_id)
            )
        }
    })

    addSectionTitle(getString(R.string.desktop_control_permission_scope))
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_access_profile),
        getString(
            if (authorization.accessProfile == SignalASILinkProtocol.ACCESS_DESKTOP_EXECUTOR) {
                R.string.pairing_access_full
            } else {
                R.string.pairing_access_restricted
            }
        ),
        R.drawable.ic_security_shield,
        desktopControlStatusLabel(authorization.status)
    ))
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_allowed_actions),
        desktopControlAllowedActions(authorization.allowedTools),
        R.drawable.ic_agent_control,
        getString(R.string.count_items, authorization.allowedTools.size)
    ))
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_grant_source),
        getString(
            if (authorization.grantSource == "pairing_qr") {
                R.string.desktop_control_grant_source_pairing
            } else {
                R.string.status_unknown
            }
        ),
        R.drawable.ic_scan,
        ""
    ))

    addSectionTitle(getString(R.string.desktop_control_authorization_history))
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_granted_time),
        securityTime(authorization.grantedAt),
        R.drawable.ic_agent_history,
        ""
    ))
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_last_used_time),
        if (authorization.lastUsedAt > 0L) {
            securityTime(authorization.lastUsedAt)
        } else {
            getString(R.string.desktop_control_never_used)
        },
        R.drawable.ic_agent_history,
        ""
    ))
    if (!active && authorization.revokedAt > 0L) {
        featureContent.addView(featureRow(
            getString(R.string.desktop_control_revoked_time),
            securityTime(authorization.revokedAt),
            R.drawable.ic_delete,
            getString(R.string.desktop_control_revoked)
        ))
    }

    if (active) {
        addSectionTitle(getString(R.string.security_section_danger))
        featureContent.addView(featureRow(
            getString(R.string.desktop_control_revoke),
            getString(R.string.desktop_control_revoke_subtitle),
            R.drawable.ic_delete,
            getString(R.string.security_revoke)
        ).apply {
            setOnClickListener {
                AlertDialog.Builder(this@showDesktopAuthorizationRecordPage)
                    .setTitle(getString(R.string.desktop_control_revoke))
                    .setMessage(getString(R.string.desktop_control_revoke_confirm))
                    .setPositiveButton(getString(R.string.security_revoke)) { _, _ ->
                        if (DesktopRemoteControl.revoke(device.id, authorization.authorizationId)) {
                            Toast.makeText(
                                this@showDesktopAuthorizationRecordPage,
                                getString(R.string.desktop_control_revoke_sent),
                                Toast.LENGTH_SHORT
                            ).show()
                        }
                    }
                    .setNegativeButton(getString(R.string.common_cancel), null)
                    .show()
            }
        })
    }
}

internal fun MainActivity.desktopControlAllowedActions(tools: List<String>): String {
    val labels = tools.map(::desktopControlActionLabel).distinct()
    return labels.joinToString(" · ").ifBlank { getString(R.string.status_unknown) }
}

internal fun MainActivity.desktopControlActionLabel(tool: String): String = getString(
    when (tool) {
        DesktopRemoteControl.SCREENSHOT -> R.string.desktop_control_action_view_screen
        DesktopRemoteControl.PERCEIVE -> R.string.desktop_control_action_perceive
        DesktopRemoteControl.CLICK_XY -> R.string.desktop_control_action_click
        DesktopRemoteControl.TYPE_TEXT -> R.string.desktop_control_action_type
        DesktopRemoteControl.HOTKEY -> R.string.desktop_control_action_hotkey
        DesktopRemoteControl.SCROLL -> R.string.desktop_control_action_scroll
        DesktopRemoteControl.WINDOW_SWITCH -> R.string.desktop_control_action_window_switch
        DesktopRemoteControl.FILE_SELECT -> R.string.desktop_control_action_file_select
        DesktopRemoteControl.SURFACE_LIST -> R.string.desktop_control_action_surface_list
        DesktopRemoteControl.SURFACE_SELECT -> R.string.desktop_control_action_surface_select
        DesktopRemoteControl.WINDOW_ACTIVATE -> R.string.desktop_control_action_window_activate
        else -> R.string.status_unknown
    }
)

internal fun MainActivity.showDesktopActionReceiptPage(
    device: DesktopSecuritySummary,
    receipt: DesktopControlReceipt
) {
    showFeaturePage(getString(R.string.desktop_control_receipt_detail))
    activeDesktopControlId = device.id
    setFeatureBackAction { showDesktopRemoteControlPage(device) }
    val succeeded = receipt.status == "succeeded"
    featureContent.addView(featureHeroCard(
        receipt.summary.ifBlank { desktopControlActionLabel(receipt.toolId) },
        getString(
            R.string.desktop_control_receipt_verified_by,
            receipt.signerId
        ),
        R.drawable.ic_security_shield,
        if (succeeded) "#14C66A" else "#D45454",
        desktopControlStatusLabel(receipt.status)
    ))

    addSectionTitle(getString(R.string.desktop_control_receipt_who))
    featureContent.addView(featureRow(
        receipt.controllerName.ifBlank { getString(R.string.desktop_control_this_phone) },
        listOf(
            receipt.controllerPlatform,
            formatFingerprint(receipt.controllerFingerprint)
        ).filter { it.isNotBlank() }.joinToString(" · "),
        R.drawable.signalasi_mark,
        getString(R.string.desktop_control_receipt_verified)
    ).apply {
        isEnabled = receipt.controllerFingerprint.isNotBlank()
        setOnClickListener {
            copyText(
                receipt.controllerFingerprint,
                getString(R.string.security_copied_phone_fingerprint)
            )
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_app_instance_id),
        receipt.controllerAppInstanceId,
        R.drawable.ic_protocol_link,
        getString(R.string.common_copy)
    ).apply {
        isEnabled = receipt.controllerAppInstanceId.isNotBlank()
        setOnClickListener {
            copyText(
                receipt.controllerAppInstanceId,
                getString(R.string.desktop_control_copied_app_instance_id)
            )
        }
    })

    addSectionTitle(getString(R.string.desktop_control_receipt_what))
    featureContent.addView(featureRow(
        desktopControlActionLabel(receipt.toolId),
        receipt.summary,
        R.drawable.ic_agent_control,
        desktopControlStatusLabel(receipt.status)
    ))
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_receipt_task),
        listOf(receipt.taskId, receipt.actionId)
            .filter { it.isNotBlank() }
            .joinToString("\n"),
        R.drawable.ic_agent_history,
        ""
    ))

    addSectionTitle(getString(R.string.desktop_control_receipt_when))
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_receipt_started),
        securityTime(receipt.startedAt),
        R.drawable.ic_agent_history,
        ""
    ))
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_receipt_completed),
        securityTime(receipt.completedAt),
        R.drawable.ic_agent_history,
        agentTraceDuration(receipt.durationMillis)
    ))

    addSectionTitle(getString(R.string.desktop_control_receipt_result))
    featureContent.addView(featureRow(
        getString(R.string.desktop_control_receipt_outcome),
        receipt.summary,
        if (succeeded) R.drawable.ic_security_shield else R.drawable.ic_info_outline,
        desktopControlStatusLabel(receipt.status)
    ))
    if (receipt.errorCode.isNotBlank()) {
        featureContent.addView(featureRow(
            getString(R.string.desktop_control_receipt_error),
            receipt.errorCode,
            R.drawable.ic_info_outline,
            getString(
                if (receipt.errorRetryable) {
                    R.string.desktop_control_receipt_retryable
                } else {
                    R.string.desktop_control_receipt_not_retryable
                }
            )
        ))
    }

    addSectionTitle(getString(R.string.desktop_control_receipt_evidence))
    desktopControlReceiptDigestRow(
        getString(R.string.desktop_control_receipt_id),
        receipt.receiptId,
        getString(R.string.desktop_control_copied_receipt_id)
    )
    desktopControlReceiptDigestRow(
        getString(R.string.desktop_control_receipt_request_digest),
        receipt.requestSha256,
        getString(R.string.desktop_control_copied_request_digest)
    )
    desktopControlReceiptDigestRow(
        getString(R.string.desktop_control_receipt_input_digest),
        receipt.inputSha256,
        getString(R.string.desktop_control_copied_input_digest)
    )
    desktopControlReceiptDigestRow(
        getString(R.string.desktop_control_receipt_output_digest),
        receipt.outputSha256,
        getString(R.string.desktop_control_copied_output_digest)
    )
    if (receipt.evidenceSha256.isNotBlank()) {
        desktopControlReceiptDigestRow(
            getString(R.string.desktop_control_receipt_visual_evidence),
            receipt.evidenceSha256,
            getString(R.string.desktop_control_copied_evidence_digest)
        )
    }
}

internal fun MainActivity.desktopControlReceiptDigestRow(
    title: String,
    digest: String,
    copiedMessage: String
) {
    featureContent.addView(featureRow(
        title,
        formatFingerprint(digest),
        R.drawable.ic_security_shield,
        getString(R.string.common_copy)
    ).apply {
        isEnabled = digest.isNotBlank()
        setOnClickListener { copyText(digest, copiedMessage) }
    })
}

internal fun MainActivity.desktopControlButtonRow(
    left: Pair<String, () -> Boolean>,
    right: Pair<String, () -> Boolean>,
    enabled: Boolean
): View = LinearLayout(this).apply {
    orientation = LinearLayout.HORIZONTAL
    gravity = Gravity.CENTER_VERTICAL
    addView(desktopControlActionButton(left.first, enabled, left.second), LinearLayout.LayoutParams(
        0,
        dp(44),
        1f
    ).apply { marginEnd = dp(5) })
    addView(desktopControlActionButton(right.first, enabled, right.second), LinearLayout.LayoutParams(
        0,
        dp(44),
        1f
    ).apply { marginStart = dp(5) })
}

internal fun MainActivity.desktopControlActionButton(
    label: String,
    enabled: Boolean,
    action: () -> Boolean
): TextView = TextView(this).apply {
    text = label
    gravity = Gravity.CENTER
    textSize = 14f
    setTextColor(Color.parseColor(if (enabled) "#1677E8" else "#9AA3AC"))
    background = GradientDrawable().apply {
        cornerRadius = dp(8).toFloat()
        setColor(Color.parseColor("#F2F6FE"))
        setStroke(dp(1), Color.parseColor("#DCE8F8"))
    }
    isEnabled = enabled
    setOnClickListener {
        if (!action()) {
            Toast.makeText(this@desktopControlActionButton, getString(R.string.desktop_control_request_failed), Toast.LENGTH_SHORT).show()
        }
    }
}

internal fun MainActivity.desktopControlStatusLabel(status: String): String = getString(
    when (status) {
        "active", "succeeded" -> R.string.status_enabled
        "pending", "sending", "running" -> R.string.desktop_control_pending
        "revoked" -> R.string.desktop_control_revoked
        "failed", "unverified" -> R.string.agent_task_status_failed
        else -> R.string.status_unknown
    }
)

internal fun MainActivity.showDesktopRunActions(
    device: DesktopSecuritySummary,
    run: DesktopRunSummary
) {
    val labels = mutableListOf<String>()
    val actions = mutableListOf<() -> Boolean>()
    if (run.pausable) {
        labels += getString(R.string.desktop_control_run_pause)
        actions += { DesktopRemoteControl.pauseTask(device.id, run.taskId) }
    }
    if (run.takeoverAvailable) {
        labels += getString(R.string.desktop_control_run_takeover_action)
        actions += { DesktopRemoteControl.takeOverTask(device.id, run.taskId) }
    }
    if (run.takeoverActive) {
        labels += getString(R.string.desktop_control_run_release_action)
        actions += { DesktopRemoteControl.releaseTask(device.id, run.taskId) }
    }
    if (run.resumable) {
        labels += getString(R.string.desktop_control_run_continue)
        actions += { DesktopRemoteControl.continueTask(device.id, run.taskId) }
    }
    if (labels.isEmpty()) return
    android.app.AlertDialog.Builder(this)
        .setTitle(
            run.prompt.replace(Regex("\\s+"), " ").trim()
                .ifBlank { getString(R.string.agent_task_details_title) }
                .take(64)
        )
        .setItems(labels.toTypedArray()) { dialog, index ->
            val sent = actions.getOrNull(index)?.invoke() == true
            Toast.makeText(
                this,
                getString(
                    if (sent) {
                        R.string.desktop_control_request_sent
                    } else {
                        R.string.desktop_control_request_failed
                    }
                ),
                Toast.LENGTH_SHORT
            ).show()
            dialog.dismiss()
        }
        .setNegativeButton(R.string.common_cancel, null)
        .show()
}

internal fun MainActivity.handleDesktopRemoteControlEvent(json: JSONObject?): Boolean {
    val payload = json ?: return false
    if (payload.optString("type") !in setOf(
            "desktop_control_authorizations",
            "desktop_control_authorization_changed",
            "desktop_executor_event",
            "desktop_action_receipt",
            "agent_task_event"
        )
    ) return false
    val desktopId = payload.optString("desktop_id")
    if (desktopId.isNotBlank() && activeDesktopControlId == desktopId && featurePage.visibility == View.VISIBLE) {
        val streamFrame = payload.optString("type") == "desktop_action_receipt" &&
            payload.optJSONObject("output")?.optBoolean("stream_frame", false) == true
        if (streamFrame && updateActiveDesktopScreenshot(desktopId)) return true
        desktopControlDevices().firstOrNull { it.id == desktopId }?.let { device ->
            if (activeDesktopPerceptionId == desktopId) {
                showDesktopPerceptionPage(device)
            } else {
                showDesktopRemoteControlPage(device)
            }
        }
    }
    return true
}

internal fun MainActivity.updateActiveDesktopScreenshot(desktopId: String): Boolean {
    val view = activeDesktopScreenView ?: return false
    val screenshot = DesktopRemoteControl.snapshot(this, desktopId).screenshot ?: return false
    val bitmap = android.graphics.BitmapFactory.decodeByteArray(
        screenshot.jpegBytes,
        0,
        screenshot.jpegBytes.size
    ) ?: return false
    view.setScreenshot(bitmap, preserveTransform = true)
    activeDesktopScreenPlaceholder?.visibility = View.GONE
    return true
}

internal fun MainActivity.showCustomDeviceConnectorEditor(
    connector: CustomDeviceConnector,
    returnToContacts: Boolean = false
) {
    showFeaturePage(getString(R.string.device_custom_editor_title))
    setFeatureBackAction { showDeviceFeaturePage(returnToContacts) }
    featureContent.addView(featureHeroCard(
        connector.name,
        getString(R.string.device_custom_editor_subtitle),
        R.drawable.ic_device_node,
        "#14C66A",
        connector.transport.name.replace('_', ' ')
    ))
    addSectionTitle(getString(R.string.device_custom_section_connection))
    featureContent.addView(featureRow(getString(R.string.device_custom_name), connector.name, R.drawable.ic_device_node, getString(R.string.common_edit)).apply {
        setOnClickListener {
            showTextSettingDialog(getString(R.string.device_custom_name), connector.name) {
                showCustomDeviceConnectorEditor(connector.copy(name = it), returnToContacts)
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.device_custom_transport),
        getString(R.string.device_custom_transport_subtitle),
        R.drawable.ic_protocol_link,
        connector.transport.name.replace('_', ' ')
    ).apply {
        setOnClickListener {
            val options = CustomDeviceTransport.entries.map { it.name.replace('_', ' ') }
            showChoiceDialog(getString(R.string.device_custom_transport), options, connector.transport.name.replace('_', ' ')) { selected ->
                showCustomDeviceConnectorEditor(connector.copy(transport = CustomDeviceTransport.valueOf(selected.replace(' ', '_'))), returnToContacts)
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.device_custom_endpoint),
        connector.endpoint.ifBlank { getString(R.string.device_custom_endpoint_subtitle) },
        R.drawable.ic_protocol_link,
        getString(R.string.common_edit)
    ).apply {
        setOnClickListener {
            showTextSettingDialog(getString(R.string.device_custom_endpoint), connector.endpoint) {
                showCustomDeviceConnectorEditor(connector.copy(endpoint = it), returnToContacts)
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.device_custom_target),
        connector.commandTarget.ifBlank { getString(R.string.device_custom_target_subtitle) },
        R.drawable.ic_device_node,
        getString(R.string.common_edit)
    ).apply {
        setOnClickListener {
            showTextSettingDialog(getString(R.string.device_custom_target), connector.commandTarget) {
                showCustomDeviceConnectorEditor(connector.copy(commandTarget = it), returnToContacts)
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.device_custom_username),
        connector.username.ifBlank { getString(R.string.common_empty) },
        R.drawable.ic_agent_node,
        getString(R.string.common_edit)
    ).apply {
        setOnClickListener {
            showTextSettingDialog(getString(R.string.device_custom_username), connector.username) {
                showCustomDeviceConnectorEditor(connector.copy(username = it), returnToContacts)
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.device_custom_token),
        maskedSecret(connector.authToken).ifBlank { getString(R.string.common_empty) },
        R.drawable.ic_security_shield,
        getString(R.string.common_edit)
    ).apply {
        setOnClickListener {
            showTextSettingDialog(getString(R.string.device_custom_token), connector.authToken) {
                showCustomDeviceConnectorEditor(connector.copy(authToken = it), returnToContacts)
            }
        }
    })
    addSectionTitle(getString(R.string.device_custom_section_safety))
    featureContent.addView(featureRow(
        getString(R.string.device_custom_risk),
        getString(R.string.device_custom_risk_subtitle),
        R.drawable.ic_security_shield,
        connector.risk.name
    ).apply {
        setOnClickListener {
            val options = listOf(AgentRisk.LOW, AgentRisk.MEDIUM, AgentRisk.HIGH).map { it.name }
            showChoiceDialog(getString(R.string.device_custom_risk), options, connector.risk.name) { selected ->
                showCustomDeviceConnectorEditor(connector.copy(risk = AgentRisk.valueOf(selected)), returnToContacts)
            }
        }
    })
    featureContent.addView(featureSwitchRow(
        getString(R.string.device_custom_enabled),
        getString(R.string.device_custom_enabled_subtitle),
        R.drawable.ic_device_node,
        connector.enabled
    ).apply {
        setOnClickListener { showCustomDeviceConnectorEditor(connector.copy(enabled = !connector.enabled), returnToContacts) }
    })
    addSectionTitle(getString(R.string.section_actions))
    featureContent.addView(featureRow(
        getString(R.string.common_save),
        getString(R.string.device_custom_save_subtitle),
        R.drawable.ic_import,
        getString(R.string.common_save)
    ).apply {
        setOnClickListener {
            if (connector.name.isBlank() || connector.endpoint.isBlank()) {
                Toast.makeText(this@showCustomDeviceConnectorEditor, getString(R.string.device_custom_required), Toast.LENGTH_SHORT).show()
            } else {
                CustomDeviceConnectorStore(this@showCustomDeviceConnectorEditor).upsert(connector)
                showDeviceFeaturePage(returnToContacts)
            }
        }
    })
    if (CustomDeviceConnectorStore(this).find(connector.id) != null) {
        featureContent.addView(featureRow(
            getString(R.string.common_delete),
            getString(R.string.device_custom_delete_subtitle),
            R.drawable.ic_security_shield,
            getString(R.string.common_delete)
        ).apply {
            setOnClickListener {
                CustomDeviceConnectorStore(this@showCustomDeviceConnectorEditor).delete(connector.id)
                showDeviceFeaturePage(returnToContacts)
            }
        })
    }
}

internal fun MainActivity.maskedSecret(value: String): String = when {
    value.isBlank() -> ""
    value.length <= 8 -> "****"
    else -> "${value.take(4)}****${value.takeLast(4)}"
}
