package com.galaxyssi.chat

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
import com.galaxyssi.chat.GalaxySSIMqttClient.Listener
import com.galaxyssi.chat.ui.AgentComposerUiPolicy
import com.galaxyssi.chat.ui.AppleHoldToTalkController
import com.galaxyssi.chat.ui.VoiceWaveformView
import com.galaxyssi.chat.voice.TranscriptHypothesis
import com.galaxyssi.chat.voice.VoiceFailure
import com.galaxyssi.chat.voice.VoiceFeatureFlags
import com.galaxyssi.chat.voice.VoiceInteractionCommand
import com.galaxyssi.chat.voice.VoiceInteractionCoordinator
import com.galaxyssi.chat.voice.VoiceInteractionCoordinatorRegistry
import com.galaxyssi.chat.voice.VoiceInteractionEvent
import com.galaxyssi.chat.voice.VoiceInteractionPhase
import com.galaxyssi.chat.voice.VoiceRouteDecision
import com.galaxyssi.chat.voice.VoiceRouteKind
import com.galaxyssi.chat.voice.VoiceSessionConfig
import com.galaxyssi.chat.voice.VoiceTtsRequest
import com.galaxyssi.chat.voice.VoiceTtsRequestRegistry
import com.galaxyssi.chat.voice.audio.AdaptiveEndpointConfig
import com.galaxyssi.chat.voice.audio.AndroidPcmRecorder
import com.galaxyssi.chat.voice.audio.DirectPcmFramePacket
import com.galaxyssi.chat.voice.audio.EndpointReason
import com.galaxyssi.chat.voice.audio.PcmCaptureConfig
import com.galaxyssi.chat.voice.audio.PcmSnapshot
import com.galaxyssi.chat.voice.audio.PcmStopReason
import com.galaxyssi.chat.voice.audio.PcmWaveFileAdapter
import com.galaxyssi.chat.voice.audio.VadDecision
import com.galaxyssi.chat.voice.audio.VoiceAudioHub
import com.galaxyssi.chat.voice.audio.VoiceAudioHubListener
import com.galaxyssi.chat.voice.asr.AsrNetworkType
import com.galaxyssi.chat.voice.asr.AsrProviderSelector
import com.galaxyssi.chat.voice.asr.AsrSessionConfig
import com.galaxyssi.chat.voice.asr.VoiceRecognitionPreference
import com.galaxyssi.chat.voice.asr.online.CachingRealtimeAsrCredentialSource
import com.galaxyssi.chat.voice.asr.online.HttpRealtimeAsrCredentialSource
import com.galaxyssi.chat.voice.asr.online.OnlineAsrCompletion
import com.galaxyssi.chat.voice.asr.online.OnlineRealtimeAsrTurn
import com.galaxyssi.chat.voice.asr.online.RealtimeAsrPreconnector
import com.galaxyssi.chat.voice.asr.online.RealtimeAsrProvider
import com.galaxyssi.chat.voice.asr.online.RealtimeAsrTurnAction
import com.galaxyssi.chat.voice.asr.remote.RemoteWhisperNodeClient
import com.galaxyssi.chat.voice.asr.remote.RemoteWhisperNodeRegistry
import com.galaxyssi.chat.voice.asr.remote.RemoteWhisperRoutingPolicy
import com.galaxyssi.chat.voice.asr.remote.GalaxySSILinkRemoteWhisperTransport
import com.galaxyssi.chat.voice.asr.local.AbortReason
import com.galaxyssi.chat.voice.asr.local.AsrConfig as HighAccuracyAsrConfig
import com.galaxyssi.chat.voice.asr.local.AsrEvent as HighAccuracyAsrEvent
import com.galaxyssi.chat.voice.asr.local.AsrPerformanceMode
import com.galaxyssi.chat.voice.asr.local.DefaultWhisperDecodeScheduler
import com.galaxyssi.chat.voice.asr.local.HighAccuracyAsrResult
import com.galaxyssi.chat.voice.asr.local.AsrTranscriptCompletenessPolicy
import com.galaxyssi.chat.voice.asr.local.HighAccuracyLocalAsrController
import com.galaxyssi.chat.voice.asr.local.HighAccuracyLocalAsrTurn
import com.galaxyssi.chat.voice.asr.local.LiveWhisperTranscriptionSession
import com.galaxyssi.chat.voice.asr.local.LiveWhisperTranscriptUpdate
import com.galaxyssi.chat.voice.asr.local.NativeWhisperCode
import com.galaxyssi.chat.voice.asr.local.LargeTurboQnnModelAction
import com.galaxyssi.chat.voice.asr.local.LargeTurboQnnModelManager
import com.galaxyssi.chat.voice.asr.local.LargeTurboQnnModelStatus
import com.galaxyssi.chat.voice.asr.local.QnnAsrEligibility
import com.galaxyssi.chat.voice.asr.local.QnnModelDownloadNetworkPolicy
import com.galaxyssi.chat.voice.asr.local.QnnWhisperPackageManager
import com.galaxyssi.chat.voice.asr.local.QnnWhisperPackageStatus
import com.galaxyssi.chat.voice.asr.local.WhisperDecodeScheduler
import com.galaxyssi.chat.voice.asr.local.largeTurboQnnModelAction
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkManager
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkDeferredException
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkProgress
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkRecord
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkStage
import com.galaxyssi.chat.voice.benchmark.WhisperProviderChoice
import com.galaxyssi.chat.voice.benchmark.WhisperUserVoiceMode
import com.galaxyssi.chat.voice.correction.AndroidVoiceExecutionRecordStore
import com.galaxyssi.chat.voice.correction.CorrectionDecision
import com.galaxyssi.chat.voice.correction.DefaultVoiceCommandRiskClassifier
import com.galaxyssi.chat.voice.correction.TranscriptDiff
import com.galaxyssi.chat.voice.correction.VoiceCommandRisk
import com.galaxyssi.chat.voice.correction.VoiceCorrectionContextRecord
import com.galaxyssi.chat.voice.correction.VoiceCorrectionJournal
import com.galaxyssi.chat.voice.correction.VoiceExecutionLedger
import com.galaxyssi.chat.voice.correction.VoiceEntityType
import com.galaxyssi.chat.voice.correction.VoiceSecondPassCoordinator
import com.galaxyssi.chat.voice.correction.VoiceSecondPassRequest
import com.galaxyssi.chat.voice.correction.VoiceSecondPassResult
import com.galaxyssi.chat.voice.correction.VoiceSecondPassTriggerPolicy
import com.galaxyssi.chat.voice.audio.VoiceAudioSession
import com.galaxyssi.chat.voice.audio.VoiceAudioSessionConfig
import com.galaxyssi.chat.voice.agent.VoiceAgentEvent
import com.galaxyssi.chat.voice.agent.VoiceAgentRunBridge
import com.galaxyssi.chat.voice.agent.VoiceAgentRunListener
import com.galaxyssi.chat.voice.agent.VoiceAgentRunSnapshot
import com.galaxyssi.chat.voice.agent.VoiceAgentRunState
import com.galaxyssi.chat.voice.agent.VoiceAgentRunUpdate
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTelemetry
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTraceContext
import com.galaxyssi.chat.voice.metrics.VoiceTraceEvents
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import com.galaxyssi.chat.voice.model.WhisperCertificationLevel
import com.galaxyssi.chat.voice.model.WhisperMemoryAdmissionPolicy
import com.galaxyssi.chat.voice.model.WhisperModelFamily
import com.galaxyssi.chat.voice.model.WhisperModelFallbackPolicy
import com.galaxyssi.chat.voice.reliability.AndroidVoiceReliabilityController
import com.galaxyssi.chat.voice.reliability.VoicePipelineFeature
import com.galaxyssi.chat.voice.reliability.VoicePerformanceHealth
import com.galaxyssi.chat.voice.reliability.VoiceResourceMode
import com.galaxyssi.chat.voice.reliability.VoiceWorkloadProfile
import com.galaxyssi.chat.voice.modelstream.ModelStreamCancelReason
import com.galaxyssi.chat.voice.modelstream.CommittedSpeechChunk
import com.galaxyssi.chat.voice.modelstream.DefaultSentenceCommitter
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
import com.galaxyssi.chat.voice.modelstream.ModelStreamUiMerger
import com.galaxyssi.chat.voice.modelstream.ModelStreamUiUpdate
import com.galaxyssi.chat.voice.modelstream.ModelUsage
import com.galaxyssi.chat.voice.modelstream.SentenceCommitter
import com.galaxyssi.chat.voice.tts.BargeInActions
import com.galaxyssi.chat.voice.tts.BargeInController
import com.galaxyssi.chat.voice.tts.BargeInTaskKind
import com.galaxyssi.chat.voice.tts.ProgressiveTtsUtteranceRegistry
import com.galaxyssi.chat.voice.tts.ProgressiveTtsUtteranceRequest
import com.galaxyssi.chat.voice.tts.TtsCancelReason
import com.galaxyssi.chat.voice.tts.TtsChunkPlayback
import com.galaxyssi.chat.voice.tts.TtsChunkPlaybackCallbacks
import com.galaxyssi.chat.voice.tts.TtsChunkPlayer
import com.galaxyssi.chat.voice.tts.TtsChunkScheduler
import com.galaxyssi.chat.voice.tts.TtsChunkSchedulerCallbacks
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

internal fun MainActivity.renderAgentActionQueue(state: AgentUiState) {
    agentActionQueueList.removeAllViews()
    val actions = state.plan?.actions.orEmpty()
    if (actions.isEmpty()) {
        agentActionQueueList.addView(agentActionQueueEmptyRow())
        return
    }
    actions.forEachIndexed { index, action ->
        agentActionQueueList.addView(agentActionQueueRow(action, index))
    }
}

internal fun MainActivity.renderAgentRequirements(state: AgentUiState) {
    agentRequirementList.removeAllViews()
    val requirements = state.plan?.requiredPermissions.orEmpty()
    if (requirements.isEmpty()) {
        agentRequirementList.addView(agentRequirementsEmptyRow())
        return
    }
    requirements.forEachIndexed { index, requirement ->
        agentRequirementList.addView(agentRequirementRow(requirement, index))
    }
}

internal fun MainActivity.renderAgentPlanContext(state: AgentUiState) {
    agentPlanContextList.removeAllViews()
    val plan = state.plan
    if (plan == null) {
        agentPlanContextList.addView(agentPlanContextEmptyRow())
        return
    }

    val routeLabel = listOfNotNull(
        plan.route.kind.name.lowercase(Locale.US).replace('_', ' '),
        plan.route.targetTitle.ifBlank { plan.selectedAgentOrModel }.ifBlank { null }
    ).joinToString(" / ")
    val rows = listOf(
        R.string.agent_plan_context_goal to state.currentGoal.ifBlank { plan.goal },
        R.string.agent_plan_context_planner to plan.plannerProfile.ifBlank { "rule-based-local" },
        R.string.agent_plan_context_route to routeLabel.ifBlank { plan.selectedAgentOrModel.ifBlank { "-" } },
        R.string.agent_plan_context_reason to plan.routeRationale.ifBlank { "-" },
        R.string.agent_plan_context_expected to plan.expectedResult.ifBlank { "-" },
        R.string.agent_plan_context_rollback to plan.rollbackStrategy.ifBlank { "-" },
        R.string.agent_plan_context_revision to getString(
            R.string.agent_plan_context_revision_value,
            plan.revision,
            plan.replanCount
        ),
        R.string.agent_plan_context_checkpoints to plan.checkpoints.count {
            it.status == AgentCheckpointStatus.ACTIVE
        }.toString(),
        R.string.agent_plan_context_tool_graph to getString(
            R.string.agent_plan_context_tool_graph_value,
            plan.toolGraphDepth(),
            plan.actionHistory.size
        ),
        R.string.agent_plan_context_tool_budget to getString(
            R.string.agent_plan_context_tool_budget_value,
            AgentAutonomyGuard.completedToolCalls(plan),
            mobileNativeAgent.modelPlannerSettings().maxToolCalls
        ),
        R.string.agent_plan_context_timeout to getString(R.string.agent_plan_context_timeout_value, plan.timeoutSeconds)
    )
    rows.forEachIndexed { index, row ->
        agentPlanContextList.addView(agentPlanContextRow(getString(row.first), row.second, index))
    }
}

internal fun MainActivity.renderAgentVerification(state: AgentUiState) {
    agentVerificationList.removeAllViews()
    val results = state.plan?.verificationResults.orEmpty().takeLast(4).asReversed()
    if (results.isEmpty()) {
        agentVerificationList.addView(agentVerificationEmptyRow())
        return
    }
    results.forEachIndexed { index, result ->
        agentVerificationList.addView(agentVerificationRow(result, index))
    }
}

internal fun MainActivity.renderAgentAuditTrail(state: AgentUiState) {
    agentAuditTrailList.removeAllViews()
    val events = state.auditTrail.takeLast(6).asReversed()
    if (events.isEmpty()) {
        agentAuditTrailList.addView(agentAuditEmptyRow())
        return
    }
    events.forEachIndexed { index, entry ->
        agentAuditTrailList.addView(agentAuditRow(entry, index))
    }
}

internal fun MainActivity.agentToolboxEmptyRow(): View {
    return TextView(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(48)
        )
        setBackgroundResource(R.drawable.agent_step_background)
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(14), 0, dp(14), 0)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 13f
        text = getString(R.string.agent_toolbox_empty)
    }
}

internal fun MainActivity.agentVerificationEmptyRow(): View {
    return TextView(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(48)
        )
        setBackgroundResource(R.drawable.agent_step_background)
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(14), 0, dp(14), 0)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 13f
        text = getString(R.string.agent_verification_empty)
    }
}

internal fun MainActivity.agentPlanContextEmptyRow(): View {
    return TextView(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(48)
        )
        setBackgroundResource(R.drawable.agent_step_background)
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(14), 0, dp(14), 0)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 13f
        text = getString(R.string.agent_plan_context_empty)
    }
}

internal fun MainActivity.agentActionQueueEmptyRow(): View {
    return TextView(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(48)
        )
        setBackgroundResource(R.drawable.agent_step_background)
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(14), 0, dp(14), 0)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 13f
        text = getString(R.string.agent_action_queue_empty)
    }
}

internal fun MainActivity.agentRequirementsEmptyRow(): View {
    return TextView(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(48)
        )
        setBackgroundResource(R.drawable.agent_step_background)
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(14), 0, dp(14), 0)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 13f
        text = getString(R.string.agent_requirements_empty)
    }
}

internal fun MainActivity.agentRecentEmptyRow(): View {
    return TextView(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(54)
        )
        setBackgroundResource(R.drawable.agent_step_background)
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(14), 0, dp(14), 0)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 14f
        text = getString(R.string.agent_recent_empty)
    }
}

internal fun MainActivity.agentAuditEmptyRow(): View {
    return TextView(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(48)
        )
        setBackgroundResource(R.drawable.agent_step_background)
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(14), 0, dp(14), 0)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 13f
        text = getString(R.string.agent_audit_empty)
    }
}

internal fun MainActivity.agentToolboxRow(tool: AgentSystemTool, index: Int): View {
    val statusColor = when (tool.risk) {
        AgentRisk.LOW -> getColorCompat(R.color.wechat_green)
        AgentRisk.MEDIUM -> getColorCompat(R.color.galaxyssi_green)
        AgentRisk.HIGH,
        AgentRisk.BLOCKED -> getColorCompat(R.color.unread_red)
    }
    val example = tool.examples.firstOrNull().orEmpty()
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setBackgroundResource(R.drawable.agent_step_background)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            if (index > 0) topMargin = dp(8)
        }
        if (example.isNotBlank()) {
            setOnClickListener { prefillAgentGoal(example) }
        }

        addView(TextView(this@agentToolboxRow).apply {
            layoutParams = LinearLayout.LayoutParams(dp(9), dp(9)).apply {
                marginEnd = dp(12)
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(statusColor)
            }
        })

        addView(LinearLayout(this@agentToolboxRow).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            addView(TextView(this@agentToolboxRow).apply {
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 13f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                text = tool.title
            })
            addView(TextView(this@agentToolboxRow).apply {
                setTextColor(getColorCompat(R.color.text_secondary))
                textSize = 11f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                text = example.ifBlank { tool.kind.name.lowercase(Locale.US).replace('_', ' ') }
            })
        })

        addView(TextView(this@agentToolboxRow).apply {
            setTextColor(statusColor)
            textSize = 12f
            setTypeface(null, android.graphics.Typeface.BOLD)
            text = getString(
                R.string.agent_toolbox_meta,
                tool.kind.name.lowercase(Locale.US).replace('_', ' '),
                tool.risk.name.lowercase(Locale.US)
            )
        })
    }
}

internal fun MainActivity.agentPlanContextRow(title: String, value: String, index: Int): View {
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setBackgroundResource(R.drawable.agent_step_background)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            if (index > 0) topMargin = dp(8)
        }

        addView(TextView(this@agentPlanContextRow).apply {
            layoutParams = LinearLayout.LayoutParams(dp(82), ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                marginEnd = dp(10)
            }
            setTextColor(getColorCompat(R.color.text_secondary))
            textSize = 12f
            setTypeface(null, android.graphics.Typeface.BOLD)
            text = title
        })

        addView(TextView(this@agentPlanContextRow).apply {
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            setTextColor(getColorCompat(R.color.text_primary))
            textSize = 13f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            text = value
        })
    }
}

internal fun MainActivity.agentVerificationRow(result: AgentVerificationResult, index: Int): View {
    val statusColor = if (result.success) getColorCompat(R.color.wechat_green) else getColorCompat(R.color.unread_red)
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setBackgroundResource(R.drawable.agent_step_background)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            if (index > 0) topMargin = dp(8)
        }

        addView(TextView(this@agentVerificationRow).apply {
            layoutParams = LinearLayout.LayoutParams(dp(9), dp(9)).apply {
                marginEnd = dp(12)
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(statusColor)
            }
        })

        addView(LinearLayout(this@agentVerificationRow).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)

            addView(TextView(this@agentVerificationRow).apply {
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 13f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                text = result.observedTitle.ifBlank { result.observedApp.ifBlank { "-" } }
            })

            addView(TextView(this@agentVerificationRow).apply {
                setTextColor(getColorCompat(R.color.text_secondary))
                textSize = 11f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                text = getString(
                    R.string.agent_verification_meta,
                    result.observedApp.ifBlank { "-" },
                    result.visibleTextCount,
                    result.clickableNodeCount
                )
            })

            if (result.recoveryDecision != AgentRecoveryDecision.NOT_NEEDED) {
                addView(TextView(this@agentVerificationRow).apply {
                    setTextColor(
                        getColorCompat(
                            if (result.recoveryDecision == AgentRecoveryDecision.RETRY_SUCCEEDED) {
                                R.color.wechat_green
                            } else {
                                R.color.text_secondary
                            }
                        )
                    )
                    textSize = 11f
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    text = getString(
                        R.string.agent_verification_recovery,
                        recoveryDecisionLabel(result.recoveryDecision),
                        result.recoveryAttemptCount
                    )
                })
            }

            addView(TextView(this@agentVerificationRow).apply {
                setTextColor(getColorCompat(R.color.text_secondary))
                textSize = 11f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                text = getString(
                    R.string.agent_verification_observation,
                    observationDecisionLabel(result.observationDecision),
                    result.observationSampleCount,
                    result.observationDurationMillis
                )
            })

            if (result.evidence.isNotBlank()) {
                addView(TextView(this@agentVerificationRow).apply {
                    setTextColor(getColorCompat(R.color.text_secondary))
                    textSize = 11f
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    text = result.evidence
                })
            }
        })

        addView(TextView(this@agentVerificationRow).apply {
            setTextColor(statusColor)
            textSize = 12f
            setTypeface(null, android.graphics.Typeface.BOLD)
            text = getString(
                if (result.success) R.string.agent_verification_success else R.string.agent_verification_failed
            )
        })

        addView(TextView(this@agentVerificationRow).apply {
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                marginStart = dp(8)
            }
            setTextColor(getColorCompat(R.color.text_secondary))
            textSize = 11f
            text = getString(R.string.agent_audit_meta, agentAuditAge(result.timestampMillis))
        })
    }
}

internal fun MainActivity.observationDecisionLabel(decision: AgentObservationDecision): String = getString(
    when (decision) {
        AgentObservationDecision.ACTION_FAILED -> R.string.agent_observation_action_failed
        AgentObservationDecision.NO_CHANGE_REQUIRED -> R.string.agent_observation_no_change_required
        AgentObservationDecision.CHANGED_AND_STABLE -> R.string.agent_observation_changed_stable
        AgentObservationDecision.CHANGED_BUT_UNSTABLE -> R.string.agent_observation_changed_unstable
        AgentObservationDecision.TIMED_OUT -> R.string.agent_observation_timed_out
    }
)

internal fun MainActivity.recoveryDecisionLabel(decision: AgentRecoveryDecision): String = getString(
    when (decision) {
        AgentRecoveryDecision.NOT_NEEDED -> R.string.agent_recovery_not_needed
        AgentRecoveryDecision.RETRY_SUCCEEDED -> R.string.agent_recovery_succeeded
        AgentRecoveryDecision.RETRY_FAILED -> R.string.agent_recovery_failed
        AgentRecoveryDecision.MANUAL_REQUIRED -> R.string.agent_recovery_manual_required
    }
)

internal fun MainActivity.agentRecentTaskRow(task: AgentTaskRecord, index: Int): View {
    val statusText = agentTaskStatusText(task)
    val execution = AgentExecutionPresentationPolicy.location(task)
    val statusColor = when {
        task.blocked -> getColorCompat(R.color.unread_red)
        task.phase == AgentPhase.COMPLETED -> getColorCompat(R.color.wechat_green)
        task.phase == AgentPhase.FAILED -> getColorCompat(R.color.unread_red)
        task.phase == AgentPhase.CANCELLED -> getColorCompat(R.color.text_secondary)
        task.phase == AgentPhase.PAUSED -> getColorCompat(R.color.text_secondary)
        else -> getColorCompat(R.color.galaxyssi_green)
    }
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setBackgroundResource(R.drawable.agent_step_background)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            if (index > 0) topMargin = dp(8)
        }

        addView(TextView(this@agentRecentTaskRow).apply {
            layoutParams = LinearLayout.LayoutParams(dp(28), dp(28)).apply {
                marginEnd = dp(10)
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(statusColor)
            }
            gravity = Gravity.CENTER
            setTextColor(getColorCompat(R.color.white))
            textSize = 12f
            setTypeface(null, android.graphics.Typeface.BOLD)
            text = "${index + 1}"
        })

        addView(LinearLayout(this@agentRecentTaskRow).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)

            addView(TextView(this@agentRecentTaskRow).apply {
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 14f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                text = task.goal
            })

            addView(TextView(this@agentRecentTaskRow).apply {
                setTextColor(getColorCompat(R.color.text_secondary))
                textSize = 12f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                text = listOf(
                    agentExecutionHostText(execution.locationKind),
                    agentExecutionRuntimeText(execution.runtimeKind),
                    execution.locationName,
                    task.risk.name.lowercase(Locale.US)
                ).filter(String::isNotBlank).joinToString(" \u00b7 ")
            })
        })

        addView(TextView(this@agentRecentTaskRow).apply {
            setTextColor(statusColor)
            textSize = 12f
            setTypeface(null, android.graphics.Typeface.BOLD)
            text = statusText
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            marginStart = dp(8)
        })
        addView(ImageButton(this@agentRecentTaskRow).apply {
            setImageResource(R.drawable.ic_more_horizontal)
            imageTintList = android.content.res.ColorStateList.valueOf(
                getColorCompat(R.color.text_secondary)
            )
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(dp(7), dp(7), dp(7), dp(7))
            background = null
            contentDescription = getString(R.string.agent_task_center_actions)
            setOnClickListener { anchor -> showAgentTaskCenterMenu(task, anchor) }
        }, LinearLayout.LayoutParams(dp(36), dp(36)).apply {
            marginStart = dp(4)
        })
        isClickable = true
        isFocusable = true
        setOnClickListener { showAgentTaskDetails(task) }
    }
}

internal fun MainActivity.showAgentTaskDetails(task: AgentTaskRecord) {
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_task_detail_title))
        .setMessage(agentTaskDetailText(task))
        .setPositiveButton(android.R.string.ok, null)
        .show()
}

internal fun MainActivity.agentTaskDetailText(task: AgentTaskRecord): String {
    val execution = AgentExecutionPresentationPolicy.location(task)
    return buildString {
        appendLine(task.goal)
        appendLine()
        appendLine("${getString(R.string.agent_task_detail_status)}: ${agentTaskStatusText(task)}")
        appendLine(
            "${getString(R.string.agent_task_detail_execution)}: " +
                listOf(
                    agentExecutionHostText(execution.locationKind),
                    agentExecutionRuntimeText(execution.runtimeKind),
                    execution.locationName
                ).filter(String::isNotBlank).joinToString(" \u00b7 ")
        )
        appendLine("${getString(R.string.agent_task_detail_route)}: ${task.routeKind.name.lowercase(Locale.US).replace('_', ' ')}")
        appendLine("${getString(R.string.agent_task_detail_target)}: ${task.targetTitle.ifBlank { "-" }}")
        appendLine("${getString(R.string.agent_task_detail_risk)}: ${task.risk.name.lowercase(Locale.US)}")
        appendLine("${getString(R.string.agent_task_detail_updated)}: ${listTime(task.updatedAtMillis)}")
        if (task.result.isNotBlank()) {
            appendLine()
            appendLine(getString(R.string.agent_task_detail_result))
            appendLine(task.result)
        }
        if (task.verification.isNotBlank()) {
            appendLine()
            appendLine(getString(R.string.agent_task_detail_verification))
            append(task.verification)
        }
        if (task.outputFiles.isNotEmpty()) {
            appendLine()
            appendLine(getString(R.string.agent_task_detail_files))
            append(task.outputFiles.joinToString("\n"))
        }
        if (task.executionLog.isNotEmpty()) {
            appendLine()
            appendLine(getString(R.string.agent_task_detail_timeline))
            append(task.executionLog.joinToString("\n"))
        }
    }.trim()
}

internal fun MainActivity.showAgentTaskCenterMenu(task: AgentTaskRecord, anchor: View) {
    val actions = AgentTaskCenterPolicy.actions(task)
    PopupMenu(this, anchor).apply {
        actions.forEachIndexed { order, action ->
            menu.add(0, action.ordinal, order, agentTaskCenterActionLabel(action))
        }
        setOnMenuItemClickListener { item ->
            actions.firstOrNull { it.ordinal == item.itemId }?.let { action ->
                handleAgentTaskCenterAction(task, action)
                true
            } ?: false
        }
        show()
    }
}

internal fun MainActivity.agentTaskCenterActionLabel(action: AgentTaskCenterAction): String =
    getString(when (action) {
        AgentTaskCenterAction.RETRY -> R.string.common_retry
        AgentTaskCenterAction.COPY -> R.string.common_copy
        AgentTaskCenterAction.VIEW_LOG -> R.string.agent_task_center_view_log
        AgentTaskCenterAction.DELETE -> R.string.agent_task_center_delete
    })

internal fun MainActivity.handleAgentTaskCenterAction(
    task: AgentTaskRecord,
    action: AgentTaskCenterAction
) {
    when (action) {
        AgentTaskCenterAction.RETRY -> retryAgentTask(task)
        AgentTaskCenterAction.COPY -> {
            getSystemService(ClipboardManager::class.java).setPrimaryClip(
                ClipData.newPlainText(
                    getString(R.string.agent_task_detail_title),
                    agentTaskDetailText(task)
                )
            )
            Toast.makeText(
                this,
                getString(R.string.agent_task_center_copied),
                Toast.LENGTH_SHORT
            ).show()
        }
        AgentTaskCenterAction.VIEW_LOG -> showAgentTaskLog(task)
        AgentTaskCenterAction.DELETE -> confirmDeleteAgentTask(task)
    }
}

internal fun MainActivity.retryAgentTask(task: AgentTaskRecord) {
    if (!AgentTaskCenterPolicy.isReusableGoal(task.goal)) {
        Toast.makeText(
            this,
            getString(R.string.agent_task_center_retry_unavailable),
            Toast.LENGTH_SHORT
        ).show()
        return
    }
    val destination = agentTranscriptStore.resolveMergedConversationId(task.sessionId)
    if (
        destination != null &&
        agentTranscriptStore.conversation(destination) != null
    ) {
        openAgentConversation(destination)
    } else {
        showMainTab(PAGE_AGENT)
        createAgentConversation()
    }
    agentGoalInput.setText(task.goal)
    agentGoalInput.setSelection(agentGoalInput.text.length)
    agentGoalInput.post { submitAgentGoal() }
}

internal fun MainActivity.showAgentTaskLog(task: AgentTaskRecord) {
    val log = task.executionLog
        .takeIf(List<String>::isNotEmpty)
        ?.joinToString("\n")
        ?: getString(R.string.agent_task_center_log_empty)
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_task_center_log_title))
        .setMessage(log)
        .setPositiveButton(android.R.string.ok, null)
        .show()
}

internal fun MainActivity.confirmDeleteAgentTask(task: AgentTaskRecord) {
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_task_center_delete_title))
        .setMessage(getString(R.string.agent_task_center_delete_message, task.goal))
        .setPositiveButton(getString(R.string.common_delete)) { _, _ ->
            val deleted = agentTaskCenter.deleteTask(task.taskId)
            Toast.makeText(
                this,
                getString(
                    if (deleted) {
                        R.string.agent_task_center_deleted
                    } else {
                        R.string.agent_task_center_delete_failed
                    }
                ),
                Toast.LENGTH_SHORT
            ).show()
            renderAgentRecentTasks(mobileNativeAgent.snapshot())
            showAgentRecentTasksPage()
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.agentRequirementRow(requirement: AgentPermissionRequirement, index: Int): View {
    val statusColor = if (requirement.granted) getColorCompat(R.color.wechat_green) else getColorCompat(R.color.unread_red)
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setBackgroundResource(R.drawable.agent_step_background)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            if (index > 0) topMargin = dp(8)
        }

        addView(TextView(this@agentRequirementRow).apply {
            layoutParams = LinearLayout.LayoutParams(dp(9), dp(9)).apply {
                marginEnd = dp(12)
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(statusColor)
            }
        })

        addView(LinearLayout(this@agentRequirementRow).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            addView(TextView(this@agentRequirementRow).apply {
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 13f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                text = requirement.title
            })
            addView(TextView(this@agentRequirementRow).apply {
                setTextColor(getColorCompat(R.color.text_secondary))
                textSize = 11f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                text = requirement.id
            })
        })

        addView(TextView(this@agentRequirementRow).apply {
            setTextColor(statusColor)
            textSize = 12f
            setTypeface(null, android.graphics.Typeface.BOLD)
            text = getString(if (requirement.granted) R.string.agent_requirement_granted else R.string.agent_requirement_missing)
        })
    }
}

internal fun MainActivity.agentActionQueueRow(action: AgentAction, index: Int): View {
    val statusColor = agentActionStatusColor(action.status)
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setBackgroundResource(R.drawable.agent_step_background)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            if (index > 0) topMargin = dp(8)
        }

        addView(TextView(this@agentActionQueueRow).apply {
            layoutParams = LinearLayout.LayoutParams(dp(28), dp(28)).apply {
                marginEnd = dp(10)
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(statusColor)
            }
            gravity = Gravity.CENTER
            setTextColor(getColorCompat(R.color.white))
            textSize = 12f
            setTypeface(null, android.graphics.Typeface.BOLD)
            text = "${index + 1}"
        })

        addView(LinearLayout(this@agentActionQueueRow).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)

            addView(TextView(this@agentActionQueueRow).apply {
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 14f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                text = action.description.ifBlank { action.kind.name.lowercase(Locale.US) }
            })

            addView(TextView(this@agentActionQueueRow).apply {
                setTextColor(getColorCompat(R.color.text_secondary))
                textSize = 12f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                text = getString(
                    R.string.agent_action_queue_meta,
                    action.target.ifBlank { action.kind.name.lowercase(Locale.US) },
                    action.risk.name.lowercase(Locale.US)
                )
            })

            if (action.dependencyIds().isNotEmpty()) {
                addView(TextView(this@agentActionQueueRow).apply {
                    setTextColor(getColorCompat(R.color.text_secondary))
                    textSize = 11f
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    text = getString(
                        R.string.agent_action_queue_dependencies,
                        action.dependencyIds().size,
                        action.outputSourceIds().size
                    )
                })
            }

            if (action.result.isNotBlank()) {
                addView(TextView(this@agentActionQueueRow).apply {
                    setTextColor(getColorCompat(R.color.text_secondary))
                    textSize = 11f
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    text = getString(R.string.agent_action_queue_result, action.result)
                })
            }
        })

        addView(TextView(this@agentActionQueueRow).apply {
            setTextColor(statusColor)
            textSize = 12f
            setTypeface(null, android.graphics.Typeface.BOLD)
            text = action.status.name.lowercase(Locale.US).replace('_', ' ')
        })
        if (action.status in setOf(
                AgentActionStatus.PROPOSED,
                AgentActionStatus.PENDING_CONFIRMATION
            )
        ) {
            setOnClickListener { showAgentPlanActionEditMenu(action) }
        }
    }
}

internal fun MainActivity.showAgentPlanActionEditMenu(action: AgentAction) {
    val labels = arrayOf(
        getString(R.string.agent_plan_edit_action),
        getString(R.string.agent_plan_move_up),
        getString(R.string.agent_plan_move_down),
        getString(R.string.agent_plan_remove_action)
    )
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_plan_edit_title))
        .setItems(labels) { _, which ->
            when (which) {
                0 -> showAgentPlanActionInputDialog(action)
                1 -> runAgentOperationAsync { mobileNativeAgent.movePendingAction(action.id, -1) }
                2 -> runAgentOperationAsync { mobileNativeAgent.movePendingAction(action.id, 1) }
                3 -> confirmRemoveAgentPlanAction(action)
            }
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.showAgentPlanActionInputDialog(action: AgentAction) {
    val descriptionInput = EditText(this).apply {
        hint = getString(R.string.agent_plan_action_description)
        setText(action.description)
        selectAll()
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        minLines = 2
    }
    val inputKey = AgentPlanEditor.inputKey(action)
    val actionInput = inputKey?.let {
        EditText(this).apply {
            hint = getString(R.string.agent_plan_action_input)
            setText(AgentPlanEditor.inputValue(action))
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            minLines = 3
        }
    }
    val container = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(20), dp(8), dp(20), 0)
        addView(descriptionInput, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))
        actionInput?.let { input ->
            addView(input, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(12) })
        }
    }
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_plan_edit_action))
        .setView(container)
        .setPositiveButton(getString(R.string.common_save)) { _, _ ->
            runAgentOperationAsync {
                mobileNativeAgent.updatePendingAction(
                    action.id,
                    descriptionInput.text?.toString().orEmpty(),
                    actionInput?.text?.toString().orEmpty()
                )
            }
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.confirmRemoveAgentPlanAction(action: AgentAction) {
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_plan_remove_action))
        .setMessage(getString(R.string.agent_plan_remove_action_message, action.description))
        .setPositiveButton(getString(R.string.common_delete)) { _, _ ->
            runAgentOperationAsync { mobileNativeAgent.removePendingAction(action.id) }
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.agentActionStatusColor(status: AgentActionStatus): Int = when (status) {
    AgentActionStatus.COMPLETED -> getColorCompat(R.color.wechat_green)
    AgentActionStatus.FAILED,
    AgentActionStatus.BLOCKED -> getColorCompat(R.color.unread_red)
    AgentActionStatus.RUNNING -> getColorCompat(R.color.galaxyssi_green)
    AgentActionStatus.WAITING_RESPONSE -> getColorCompat(R.color.galaxyssi_green)
    else -> getColorCompat(R.color.text_secondary)
}

internal fun MainActivity.agentAuditRow(entry: AgentAuditEntry, index: Int): View {
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setBackgroundResource(R.drawable.agent_step_background)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            if (index > 0) topMargin = dp(8)
        }

        addView(TextView(this@agentAuditRow).apply {
            layoutParams = LinearLayout.LayoutParams(dp(9), dp(9)).apply {
                marginEnd = dp(12)
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(getColorCompat(R.color.wechat_green))
            }
        })

        addView(LinearLayout(this@agentAuditRow).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)

            addView(TextView(this@agentAuditRow).apply {
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 13f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                text = entry.event.name.lowercase(Locale.US).replace('_', ' ')
            })

            addView(TextView(this@agentAuditRow).apply {
                setTextColor(getColorCompat(R.color.text_secondary))
                textSize = 11f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                text = entry.detail.ifBlank { "-" }
            })
        })

        addView(TextView(this@agentAuditRow).apply {
            setTextColor(getColorCompat(R.color.text_secondary))
            textSize = 11f
            text = getString(R.string.agent_audit_meta, agentAuditAge(entry.timestampMillis))
        })
    }
}

internal fun MainActivity.agentAuditAge(timestampMillis: Long): String {
    val deltaSeconds = ((System.currentTimeMillis() - timestampMillis).coerceAtLeast(0L) / 1000L)
    return when {
        deltaSeconds < 60 -> "${deltaSeconds}s"
        deltaSeconds < 3600 -> "${deltaSeconds / 60}m"
        deltaSeconds < 86_400 -> "${deltaSeconds / 3600}h"
        else -> "${deltaSeconds / 86_400}d"
    }
}

internal fun MainActivity.renderAgentScreenDetails(screen: ScreenContext) {
    agentScreenDetailList.removeAllViews()
    if (!screen.isAccessibilityEnabled && !ScreenPerceptionState.hasRecentVisualCapture()) {
        agentScreenDetailList.addView(agentScreenEmptyRow(getString(R.string.agent_screen_disabled)))
        return
    }

    val query = agentScreenSearchInput.text?.toString()?.trim().orEmpty()
    val normalizedQuery = query.lowercase(Locale.US)
    val visibleTexts = screen.visibleTexts
        .filter { matchesScreenQuery(it, normalizedQuery) }
        .take(5)
    val selectedTextMatches = screen.selectedText.isNotBlank() &&
        matchesScreenQuery(screen.selectedText, normalizedQuery)
    val focusedInputField = screen.focusedInputField?.takeIf { field ->
        matchesScreenQuery(field.label, normalizedQuery) ||
            matchesScreenQuery(field.viewId, normalizedQuery) ||
            matchesScreenQuery(field.className, normalizedQuery)
    }
    val actions = screen.clickableElements
        .filter { matchesScreenQuery(it.label, normalizedQuery) || matchesScreenQuery(it.viewId, normalizedQuery) }
        .take(5)
    val fields = screen.inputFields
        .filter { matchesScreenQuery(it.label, normalizedQuery) || matchesScreenQuery(it.viewId, normalizedQuery) }
        .take(5)
    val scrollRegions = screen.scrollableRegions
        .filter { matchesScreenQuery(it.label, normalizedQuery) || matchesScreenQuery(it.viewId, normalizedQuery) }
        .take(5)
    val clipboardMatches = screen.clipboard.hasText && (
        normalizedQuery.isBlank() ||
            matchesScreenQuery(screen.clipboard.preview, normalizedQuery) ||
            matchesScreenQuery(screen.clipboard.textHash, normalizedQuery) ||
            screen.clipboard.sensitiveFlags.any { matchesScreenQuery(it, normalizedQuery) }
        )
    val notificationItems = screen.notifications.items
        .filter { item ->
            matchesScreenQuery(item.packageName, normalizedQuery) ||
                matchesScreenQuery(item.title, normalizedQuery) ||
                matchesScreenQuery(item.textPreview, normalizedQuery) ||
                item.sensitiveFlags.any { matchesScreenQuery(it, normalizedQuery) }
        }
        .take(3)
    val showNotificationAccessRow = !screen.notifications.hasAccess && normalizedQuery.isBlank()
    val notificationsMatch = notificationItems.isNotEmpty() || showNotificationAccessRow
    val deviceStatusMatches = normalizedQuery.isBlank() ||
        matchesScreenQuery(screen.deviceStatus.network, normalizedQuery) ||
        matchesScreenQuery(screen.deviceStatus.batteryPercent.toString(), normalizedQuery) ||
        matchesScreenQuery(screen.deviceStatus.freeStorageMb.toString(), normalizedQuery)
    val launchableApps = screen.installedApps
        .filter { app ->
            matchesScreenQuery(app.label, normalizedQuery) ||
                matchesScreenQuery(app.packageName, normalizedQuery)
        }
        .take(if (normalizedQuery.isBlank()) 4 else 8)

    val hasAny = selectedTextMatches || focusedInputField != null || clipboardMatches || notificationsMatch || deviceStatusMatches || launchableApps.isNotEmpty() || visibleTexts.isNotEmpty() || actions.isNotEmpty() || fields.isNotEmpty() || scrollRegions.isNotEmpty()
    agentScreenDetailList.addView(agentScreenSummaryRow(screen))
    if (!hasAny) {
        agentScreenDetailList.addView(agentScreenEmptyRow(getString(R.string.agent_screen_empty)))
        return
    }
    if (selectedTextMatches) {
        addScreenTextSection(getString(R.string.agent_screen_selected_text), listOf(screen.selectedText))
    }
    focusedInputField?.let {
        addScreenElementSection(getString(R.string.agent_screen_focused_input), listOf(it), AgentScreenCommandKind.TYPE)
    }
    if (clipboardMatches) {
        addScreenClipboardSection(screen.clipboard)
    }
    if (notificationsMatch) {
        addScreenNotificationSection(notificationItems, showNotificationAccessRow)
    }
    if (deviceStatusMatches) {
        addScreenDeviceStatusSection(screen.deviceStatus)
    }
    if (screen.visualScene.available) {
        agentScreenDetailList.addView(agentScreenSectionTitle(getString(R.string.agent_screen_visual_grounding)))
        agentScreenDetailList.addView(agentVisualSummaryRow(screen.visualScene))
    }
    addScreenInstalledAppsSection(launchableApps)
    addScreenTextSection(getString(R.string.agent_screen_texts), visibleTexts)
    addScreenElementSection(getString(R.string.agent_screen_actions), actions, AgentScreenCommandKind.TAP)
    addScreenElementSection(getString(R.string.agent_screen_fields), fields, AgentScreenCommandKind.TYPE)
    addScreenElementSection(getString(R.string.agent_screen_scrollable_regions), scrollRegions, AgentScreenCommandKind.SCROLL)
}

internal fun MainActivity.matchesScreenQuery(value: String, normalizedQuery: String): Boolean =
    normalizedQuery.isBlank() || value.lowercase(Locale.US).contains(normalizedQuery)

internal fun MainActivity.addScreenTextSection(title: String, items: List<String>) {
    if (items.isEmpty()) return
    agentScreenDetailList.addView(agentScreenSectionTitle(title))
    items.forEach { item ->
        agentScreenDetailList.addView(agentScreenTextRow(item))
    }
}

internal fun MainActivity.addScreenClipboardSection(clipboard: ClipboardContext) {
    agentScreenDetailList.addView(agentScreenSectionTitle(getString(R.string.agent_screen_clipboard)))
    agentScreenDetailList.addView(agentClipboardRow(clipboard))
}

internal fun MainActivity.addScreenNotificationSection(items: List<AgentNotificationItem>, showAccessRow: Boolean) {
    agentScreenDetailList.addView(agentScreenSectionTitle(getString(R.string.agent_screen_notifications)))
    if (showAccessRow) {
        agentScreenDetailList.addView(agentScreenEmptyRow(getString(R.string.agent_screen_notifications_locked)))
    }
    items.forEach { item ->
        agentScreenDetailList.addView(agentNotificationRow(item))
    }
}

internal fun MainActivity.addScreenDeviceStatusSection(status: AgentDeviceStatusContext) {
    agentScreenDetailList.addView(agentScreenSectionTitle(getString(R.string.agent_screen_device_status)))
    agentScreenDetailList.addView(agentDeviceStatusRow(status))
}

internal fun MainActivity.addScreenInstalledAppsSection(apps: List<InstalledAppInfo>) {
    if (apps.isEmpty()) return
    agentScreenDetailList.addView(agentScreenSectionTitle(getString(R.string.agent_screen_launchable_apps)))
    apps.forEach { app ->
        agentScreenDetailList.addView(agentInstalledAppRow(app))
    }
}

internal fun MainActivity.addScreenElementSection(
    title: String,
    items: List<ScreenElement>,
    commandKind: AgentScreenCommandKind
) {
    if (items.isEmpty()) return
    agentScreenDetailList.addView(agentScreenSectionTitle(title))
    items.forEach { item ->
        agentScreenDetailList.addView(agentScreenElementRow(item, commandKind))
    }
}

internal fun MainActivity.agentClipboardRow(clipboard: ClipboardContext): View {
    val summary = if (clipboard.sensitiveFlags.isNotEmpty()) {
        getString(R.string.agent_screen_clipboard_sensitive, clipboard.textLength)
    } else {
        getString(
            R.string.agent_screen_clipboard_summary,
            clipboard.textLength,
            clipboard.preview.ifBlank { clipboard.textHash.ifBlank { "-" } }
        )
    }
    return TextView(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(6) }
        setBackgroundResource(R.drawable.agent_step_background)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        setTextColor(getColorCompat(R.color.text_primary))
        textSize = 13f
        maxLines = 2
        ellipsize = android.text.TextUtils.TruncateAt.END
        text = summary
        setOnClickListener { prefillAgentGoal("paste clipboard") }
    }
}

internal fun MainActivity.agentNotificationRow(item: AgentNotificationItem): View {
    val title = item.title.ifBlank { item.packageName.ifBlank { "-" } }
    val baseDetail = if (item.sensitiveFlags.isNotEmpty()) {
        getString(R.string.agent_screen_notification_sensitive, item.packageName.ifBlank { "-" })
    } else {
        getString(
            R.string.agent_screen_notification_summary,
            item.category.ifBlank { item.packageName.ifBlank { "-" } },
            item.textPreview.ifBlank { title }
        )
    }
    val replyAvailable = item.canReply && item.sensitiveFlags.isEmpty()
    val detail = if (replyAvailable) {
        "$baseDetail\n${getString(R.string.agent_screen_notification_reply_available)}"
    } else {
        baseDetail
    }
    return LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundResource(R.drawable.agent_step_background)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(6) }
        setOnClickListener {
            if (replyAvailable) {
                prefillAgentGoal("reply notification ${item.packageName} :: ")
            } else {
                prefillAgentGoal("read notifications")
            }
        }

        addView(TextView(this@agentNotificationRow).apply {
            setTextColor(getColorCompat(R.color.text_primary))
            textSize = 13f
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
            text = title
        })
        addView(TextView(this@agentNotificationRow).apply {
            setTextColor(getColorCompat(R.color.text_secondary))
            textSize = 11f
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
            text = detail
        })
    }
}

internal fun MainActivity.agentDeviceStatusRow(status: AgentDeviceStatusContext): View {
    val power = if (status.powerSaveMode) "power save" else if (status.charging) "charging" else "battery"
    return TextView(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(6) }
        setBackgroundResource(R.drawable.agent_step_background)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        setTextColor(getColorCompat(R.color.text_primary))
        textSize = 13f
        maxLines = 2
        ellipsize = android.text.TextUtils.TruncateAt.END
        text = getString(
            R.string.agent_screen_device_status_summary,
            status.batteryPercent,
            power,
            status.network,
            status.freeStorageMb
        )
        setOnClickListener { prefillAgentGoal("device status") }
    }
}

internal fun MainActivity.agentInstalledAppRow(app: InstalledAppInfo): View {
    return LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundResource(R.drawable.agent_step_background)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(6) }
        setOnClickListener { prefillAgentGoal("open ${app.label}") }

        addView(TextView(this@agentInstalledAppRow).apply {
            setTextColor(getColorCompat(R.color.text_primary))
            textSize = 13f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            text = app.label
        })
        addView(TextView(this@agentInstalledAppRow).apply {
            setTextColor(getColorCompat(R.color.text_secondary))
            textSize = 11f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            text = getString(R.string.agent_screen_launchable_app_summary, app.packageName, "open")
        })
    }
}

internal fun MainActivity.agentScreenSummaryRow(screen: ScreenContext): View {
    val pageTitle = screen.pageTitle.ifBlank { screen.foregroundApp }
    val ageSeconds = maxOf(0L, screen.snapshotAgeMillis / 1000L)
    return TextView(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(44)
        )
        setBackgroundResource(R.drawable.agent_step_background)
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(14), 0, dp(14), 0)
        setTextColor(getColorCompat(R.color.text_primary))
        textSize = 14f
        maxLines = 1
        ellipsize = android.text.TextUtils.TruncateAt.END
        text = getString(R.string.agent_screen_summary, pageTitle, ageSeconds)
    }
}

internal fun MainActivity.agentScreenSectionTitle(title: String): View {
    return TextView(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(10) }
        setPadding(dp(4), 0, dp(4), dp(4))
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 12f
        setTypeface(null, android.graphics.Typeface.BOLD)
        text = title
    }
}

internal fun MainActivity.agentScreenTextRow(value: String): View {
    return TextView(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(6) }
        setBackgroundResource(R.drawable.agent_step_background)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        setTextColor(getColorCompat(R.color.text_primary))
        textSize = 13f
        maxLines = 2
        ellipsize = android.text.TextUtils.TruncateAt.END
        text = value
        setOnClickListener {
            prefillAgentGoal("save note $value")
        }
    }
}

internal fun MainActivity.agentScreenElementRow(item: ScreenElement, commandKind: AgentScreenCommandKind): View {
    val label = item.label.ifBlank { item.viewId.ifBlank { item.className } }
    val commandTarget = item.viewId.takeIf { item.origin == AgentElementOrigin.VISUAL_OCR && it.isNotBlank() }
        ?: label
    return LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundResource(R.drawable.agent_step_background)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(6) }
        setOnClickListener {
            prefillAgentGoal(agentScreenCommand(commandTarget, commandKind))
        }

        addView(TextView(this@agentScreenElementRow).apply {
            setTextColor(getColorCompat(R.color.text_primary))
            textSize = 13f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            text = label
        })
        addView(TextView(this@agentScreenElementRow).apply {
            setTextColor(getColorCompat(R.color.text_secondary))
            textSize = 11f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            text = getString(
                R.string.agent_screen_element_grounding,
                item.bounds.ifBlank { "-" },
                elementOriginLabel(item.origin),
                visualRoleLabel(item.visualRole),
                (item.confidence * 100).toInt().coerceIn(0, 100)
            )
        })
    }
}

internal fun MainActivity.agentVisualSummaryRow(scene: AgentVisualScene): View = TextView(this).apply {
    layoutParams = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    ).apply { bottomMargin = dp(6) }
    setBackgroundResource(R.drawable.agent_step_background)
    setPadding(dp(14), dp(10), dp(14), dp(10))
    setTextColor(getColorCompat(R.color.text_primary))
    textSize = 13f
    text = getString(
        R.string.agent_screen_visual_summary,
        scene.modelProfile,
        scene.elements.size,
        scene.actionCandidateCount,
        scene.inputCandidateCount
    )
}

internal fun MainActivity.elementOriginLabel(origin: AgentElementOrigin): String = getString(
    when (origin) {
        AgentElementOrigin.ACCESSIBILITY -> R.string.agent_screen_origin_accessibility
        AgentElementOrigin.VISUAL_OCR -> R.string.agent_screen_origin_visual
        AgentElementOrigin.FUSED -> R.string.agent_screen_origin_fused
    }
)

internal fun MainActivity.visualRoleLabel(role: AgentVisualRole): String = getString(
    when (role) {
        AgentVisualRole.TITLE -> R.string.agent_visual_role_title
        AgentVisualRole.BUTTON -> R.string.agent_visual_role_button
        AgentVisualRole.INPUT -> R.string.agent_visual_role_input
        AgentVisualRole.NAVIGATION -> R.string.agent_visual_role_navigation
        AgentVisualRole.LIST_ITEM -> R.string.agent_visual_role_list_item
        AgentVisualRole.TEXT -> R.string.agent_visual_role_text
        AgentVisualRole.UNKNOWN -> R.string.agent_visual_role_unknown
    }
)

internal fun MainActivity.agentScreenCommand(label: String, kind: AgentScreenCommandKind): String = when (kind) {
    AgentScreenCommandKind.TAP -> "tap $label"
    AgentScreenCommandKind.TYPE -> "type text into $label"
    AgentScreenCommandKind.SCROLL -> "swipe up"
}

internal fun MainActivity.prefillAgentGoal(command: String) {
    agentGoalInput.setText(command)
    agentGoalInput.setSelection(agentGoalInput.text?.length ?: 0)
    agentGoalInput.requestFocus()
    getSystemService(InputMethodManager::class.java).showSoftInput(agentGoalInput, InputMethodManager.SHOW_IMPLICIT)
}

internal fun MainActivity.agentScreenEmptyRow(message: String): View {
    return TextView(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(48)
        ).apply { topMargin = dp(8) }
        setBackgroundResource(R.drawable.agent_step_background)
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(14), 0, dp(14), 0)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 13f
        text = message
    }
}

internal fun MainActivity.agentTaskStatusText(task: AgentTaskRecord): String = when {
    task.blocked -> getString(R.string.agent_recent_status_blocked)
    task.phase == AgentPhase.COMPLETED -> getString(R.string.agent_recent_status_done)
    task.phase == AgentPhase.FAILED -> getString(R.string.agent_recent_status_failed)
    task.phase == AgentPhase.CANCELLED -> getString(R.string.agent_recent_status_cancelled)
    task.phase == AgentPhase.PAUSED -> getString(R.string.agent_recent_status_paused)
    task.phase == AgentPhase.EXECUTING ||
        task.phase == AgentPhase.VERIFYING ||
        task.phase == AgentPhase.PLANNING ||
        task.phase == AgentPhase.WAITING_RESPONSE ||
        task.phase == AgentPhase.WAITING_CONFIRMATION -> getString(R.string.agent_recent_status_running)
    else -> task.phase.name.lowercase(Locale.US)
}
