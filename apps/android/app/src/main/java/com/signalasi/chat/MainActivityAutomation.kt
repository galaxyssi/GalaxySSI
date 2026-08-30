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

internal fun MainActivity.showAutomationFeaturePage() {
    val proactiveStore = AgentProactiveTaskStore(this)
    val proactiveTasks = proactiveStore.tasks()
    val remoteProactiveEvents = AgentRemoteProactiveEventStore(this).recent(30)
    val workflows = SharedPreferencesAgentWorkflowStore(this).list()
    val schedules = AgentWorkflowScheduleStore(this).list()
    val triggers = AgentWorkflowTriggerStore(this).list()
    val recentExecutions = AgentWorkflowExecutionHistoryStore(this).recent()
    val templates = AgentWorkflowTemplates.all
    showFeaturePage(getString(R.string.automation_title))
    featureContent.addView(featureHeroCard(
        getString(R.string.automation_hero_title),
        getString(R.string.automation_hero_subtitle),
        R.drawable.ic_automation_line,
        "#FFB020",
        getString(R.string.count_items, proactiveTasks.size + workflows.size)
    ))
    addSectionTitle(getString(R.string.automation_proactive_tasks))
    featureContent.addView(featureRow(
        getString(R.string.automation_new_proactive_task),
        getString(R.string.automation_new_proactive_task_subtitle),
        R.drawable.ic_automation_line,
        getString(R.string.common_create)
    ).apply {
        setOnClickListener { showProactiveTaskEditor(newProactiveTaskDraft()) }
    })
    if (proactiveTasks.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.automation_no_proactive_tasks),
            getString(R.string.automation_no_proactive_tasks_subtitle),
            R.drawable.ic_automation_line,
            ""
        ))
    } else {
        proactiveTasks.forEach { task ->
            featureContent.addView(featureRow(
                task.name,
                proactiveTaskSubtitle(task),
                R.drawable.ic_automation_line,
                proactiveRunStatusLabel(task.lastStatus)
            ).apply {
                setOnClickListener { showProactiveTaskDetails(task.taskId) }
            })
        }
    }
    if (remoteProactiveEvents.isNotEmpty()) {
        addSectionTitle(getString(R.string.automation_remote_activity))
        remoteProactiveEvents.forEach { event ->
            val status = runCatching {
                AgentProactiveRunStatus.valueOf(event.status.uppercase(Locale.ROOT))
            }.getOrDefault(AgentProactiveRunStatus.QUEUED)
            featureContent.addView(featureRow(
                event.desktopName.ifBlank { getString(R.string.automation_remote_desktop) },
                listOfNotNull(
                    event.taskId.takeIf(String::isNotBlank),
                    event.detail.takeIf(String::isNotBlank),
                    automationTime(event.timestampMillis)
                ).joinToString("\n"),
                R.drawable.ic_agent_history,
                proactiveRunStatusLabel(status)
            ))
        }
    }
    addSectionTitle(getString(R.string.automation_saved_workflows))
    if (workflows.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.automation_no_workflows),
            getString(R.string.automation_create_workflow_hint),
            R.drawable.ic_send_plane,
            ""
        ))
    } else {
        workflows.forEach { workflow ->
            featureContent.addView(featureRow(
                workflow.name,
                workflow.goal,
                R.drawable.ic_send_plane,
                getString(R.string.automation_run)
            ).apply {
                setOnClickListener { openAgentWorkflow("run workflow ${workflow.name}") }
            })
        }
    }
    addSectionTitle(getString(R.string.automation_schedules))
    if (schedules.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.automation_no_schedules),
            getString(R.string.automation_schedule_hint),
            R.drawable.ic_protocol_link,
            ""
        ))
    } else {
        schedules.forEach { schedule ->
            featureContent.addView(featureRow(
                schedule.workflowName,
                automationScheduleSubtitle(schedule),
                R.drawable.ic_protocol_link,
                getString(R.string.status_enabled)
            ).apply {
                setOnClickListener { openAgentWorkflow("cancel schedule ${schedule.workflowName}") }
            })
        }
    }
    addSectionTitle(getString(R.string.automation_event_triggers))
    if (triggers.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.automation_no_event_triggers),
            getString(R.string.automation_event_trigger_hint),
            R.drawable.ic_protocol_link,
            ""
        ))
    } else {
        triggers.forEach { trigger ->
            featureContent.addView(featureRow(
                trigger.workflowName,
                automationTriggerSubtitle(trigger),
                R.drawable.ic_protocol_link,
                getString(R.string.common_delete)
            ).apply {
                setOnClickListener { openAgentWorkflow("delete trigger ${trigger.id}") }
            })
        }
    }
    addSectionTitle(getString(R.string.automation_recent_executions))
    if (recentExecutions.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.automation_no_recent_executions),
            getString(R.string.automation_run_command_hint),
            R.drawable.ic_security_shield,
            ""
        ))
    } else {
        recentExecutions.forEach { execution ->
            featureContent.addView(featureRow(
                execution.workflowName,
                automationExecutionSubtitle(execution),
                R.drawable.ic_security_shield,
                getString(
                    R.string.automation_run_status,
                    automationExecutionStatusLabel(execution.status)
                )
            ))
        }
    }
    addSectionTitle(getString(R.string.automation_templates))
    templates.forEach { template ->
        featureContent.addView(featureRow(
            template.name,
            template.goal,
            R.drawable.ic_agent_node,
            getString(R.string.automation_run)
        ).apply {
            setOnClickListener { openAgentWorkflow("run template ${template.name}") }
        })
    }
}

internal fun MainActivity.newProactiveTaskDraft(): AgentProactiveTask {
    val defaultTarget = AppStoreAgentConnectorRegistry(this).availableTargets()
        .firstOrNull { it.status == AgentConnectorStatus.AVAILABLE }
        ?.id
        ?: "codex"
    return AgentProactiveTask(
        name = getString(R.string.automation_new_proactive_task),
        trigger = AgentProactiveTrigger(
            kind = AgentProactiveTriggerKind.MANUAL,
            timeZone = java.time.ZoneId.systemDefault().id
        ),
        action = AgentProactiveAction(
            kind = AgentProactiveActionKind.AGENT,
            targetId = defaultTarget
        )
    )
}

internal fun MainActivity.showProactiveTaskEditor(task: AgentProactiveTask) {
    showFeaturePage(getString(R.string.automation_proactive_editor_title))
    setFeatureBackAction { showAutomationFeaturePage() }
    featureContent.addView(featureHeroCard(
        task.name,
        getString(R.string.automation_proactive_tasks_subtitle),
        R.drawable.ic_automation_line,
        "#FFB020",
        proactiveTriggerLabel(task.trigger.kind)
    ))
    addSectionTitle(getString(R.string.section_plan))
    featureContent.addView(featureRow(
        getString(R.string.automation_proactive_name),
        task.name,
        R.drawable.ic_automation_line,
        getString(R.string.common_edit)
    ).apply {
        setOnClickListener {
            showTextSettingDialog(getString(R.string.automation_proactive_name), task.name) { value ->
                showProactiveTaskEditor(task.copy(name = value.ifBlank { task.name }))
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.automation_proactive_trigger),
        proactiveTriggerDescription(task.trigger),
        R.drawable.ic_protocol_link,
        proactiveTriggerLabel(task.trigger.kind)
    ).apply {
        setOnClickListener {
            val options = AgentProactiveTriggerKind.entries.map(::proactiveTriggerLabel)
            showChoiceDialog(
                getString(R.string.automation_proactive_trigger),
                options,
                proactiveTriggerLabel(task.trigger.kind)
            ) { selected ->
                val kind = AgentProactiveTriggerKind.entries.first {
                    proactiveTriggerLabel(it) == selected
                }
                showProactiveTaskEditor(task.copy(trigger = proactiveTriggerForKind(task, kind)))
            }
        }
    })
    when (task.trigger.kind) {
        AgentProactiveTriggerKind.CRON -> {
            featureContent.addView(featureRow(
                getString(R.string.automation_proactive_schedule),
                getString(R.string.automation_proactive_cron_hint),
                R.drawable.ic_protocol_link,
                task.trigger.cron
            ).apply {
                setOnClickListener {
                    showTextSettingDialog(
                        getString(R.string.automation_proactive_schedule),
                        task.trigger.cron
                    ) { value ->
                        showProactiveTaskEditor(task.copy(trigger = task.trigger.copy(cron = value)))
                    }
                }
            })
            featureContent.addView(featureRow(
                getString(R.string.automation_proactive_time_zone),
                task.trigger.timeZone,
                R.drawable.ic_protocol_link,
                getString(R.string.common_edit)
            ).apply {
                setOnClickListener {
                    showTextSettingDialog(
                        getString(R.string.automation_proactive_time_zone),
                        task.trigger.timeZone
                    ) { value ->
                        showProactiveTaskEditor(task.copy(trigger = task.trigger.copy(timeZone = value)))
                    }
                }
            })
        }
        AgentProactiveTriggerKind.INTERVAL,
        AgentProactiveTriggerKind.GOAL_CHECKPOINT -> {
            featureContent.addView(featureRow(
                getString(R.string.automation_proactive_schedule),
                proactiveTriggerDescription(task.trigger),
                R.drawable.ic_protocol_link,
                task.trigger.intervalSeconds.toString()
            ).apply {
                setOnClickListener {
                    showTextSettingDialog(
                        getString(R.string.automation_proactive_schedule),
                        task.trigger.intervalSeconds.toString()
                    ) { value ->
                        val seconds = value.toLongOrNull()?.coerceAtLeast(
                            AgentProactiveTrigger.MIN_INTERVAL_SECONDS
                        ) ?: task.trigger.intervalSeconds
                        showProactiveTaskEditor(
                            task.copy(trigger = task.trigger.copy(intervalSeconds = seconds))
                        )
                    }
                }
            })
        }
        AgentProactiveTriggerKind.WEBHOOK -> featureContent.addView(featureRow(
            getString(R.string.automation_proactive_schedule),
            getString(R.string.automation_proactive_webhook_hint),
            R.drawable.ic_protocol_link,
            task.trigger.webhookId
        ))
        AgentProactiveTriggerKind.MANUAL -> Unit
    }
    addSectionTitle(getString(R.string.automation_proactive_action))
    featureContent.addView(featureRow(
        getString(R.string.automation_proactive_action),
        proactiveActionDescription(task.action),
        R.drawable.ic_agent_node,
        proactiveActionLabel(task.action.kind)
    ).apply {
        setOnClickListener {
            val options = AgentProactiveActionKind.entries.map(::proactiveActionLabel)
            showChoiceDialog(
                getString(R.string.automation_proactive_action),
                options,
                proactiveActionLabel(task.action.kind)
            ) { selected ->
                val kind = AgentProactiveActionKind.entries.first {
                    proactiveActionLabel(it) == selected
                }
                showProactiveTaskEditor(task.copy(action = proactiveActionForKind(task, kind)))
            }
        }
    })
    if (task.action.kind == AgentProactiveActionKind.SUBAGENT_TEAM) {
        featureContent.addView(featureRow(
            getString(R.string.automation_proactive_team),
            task.action.team.joinToString("\n") {
                "${it.role.name.lowercase(Locale.ROOT)}:${it.agentId}"
            },
            R.drawable.ic_agent_node,
            getString(R.string.common_edit)
        ).apply {
            setOnClickListener {
                val initial = task.action.team.joinToString("\n") {
                    "${it.role.name.lowercase(Locale.ROOT)}:${it.agentId}"
                }
                showTextSettingDialog(
                    getString(R.string.automation_proactive_team),
                    initial
                ) { value ->
                    runCatching { parseProactiveTeam(value) }
                        .onSuccess { team ->
                            showProactiveTaskEditor(task.copy(action = task.action.copy(team = team)))
                        }
                        .onFailure { error ->
                            Toast.makeText(
                                this@showProactiveTaskEditor,
                                getString(
                                    R.string.automation_proactive_invalid,
                                    error.message.orEmpty()
                                ),
                                Toast.LENGTH_LONG
                            ).show()
                        }
                }
            }
        })
    } else {
        featureContent.addView(featureRow(
            getString(R.string.automation_proactive_target),
            proactiveTargetTitle(task.action),
            proactiveActionIcon(task.action.kind),
            getString(R.string.common_edit)
        ).apply {
            setOnClickListener { chooseProactiveTarget(task) }
        })
    }
    if (task.action.kind != AgentProactiveActionKind.WORKFLOW) {
        featureContent.addView(featureRow(
            getString(R.string.automation_proactive_prompt),
            task.action.prompt.ifBlank { getString(R.string.common_empty) },
            R.drawable.ic_send_plane,
            getString(R.string.common_edit)
        ).apply {
            setOnClickListener {
                showTextSettingDialog(
                    getString(R.string.automation_proactive_prompt),
                    task.action.prompt
                ) { value ->
                    showProactiveTaskEditor(task.copy(action = task.action.copy(prompt = value)))
                }
            }
        })
    }
    if (task.action.kind == AgentProactiveActionKind.NATIVE_TOOL) {
        featureContent.addView(featureRow(
            getString(R.string.automation_proactive_arguments),
            task.action.argumentsJson,
            R.drawable.ic_agent_control,
            getString(R.string.common_edit)
        ).apply {
            setOnClickListener {
                showTextSettingDialog(
                    getString(R.string.automation_proactive_arguments),
                    task.action.argumentsJson
                ) { value ->
                    runCatching { JSONObject(value) }
                        .onSuccess {
                            showProactiveTaskEditor(
                                task.copy(action = task.action.copy(argumentsJson = it.toString()))
                            )
                        }
                        .onFailure {
                            Toast.makeText(
                                this@showProactiveTaskEditor,
                                getString(R.string.automation_proactive_invalid, it.message.orEmpty()),
                                Toast.LENGTH_LONG
                            ).show()
                        }
                }
            }
        })
    }
    featureContent.addView(featureRow(
        getString(R.string.automation_proactive_delivery),
        proactiveDeliveryLabel(task.action.deliveryMode),
        R.drawable.ic_send_plane,
        proactiveDeliveryLabel(task.action.deliveryMode)
    ).apply {
        setOnClickListener {
            val values = listOf("store", "notify", "mobile")
            val options = values.map(::proactiveDeliveryLabel)
            showChoiceDialog(
                getString(R.string.automation_proactive_delivery),
                options,
                proactiveDeliveryLabel(task.action.deliveryMode)
            ) { selected ->
                val value = values.first { proactiveDeliveryLabel(it) == selected }
                showProactiveTaskEditor(task.copy(action = task.action.copy(deliveryMode = value)))
            }
        }
    })
    addSectionTitle(getString(R.string.device_custom_section_safety))
    featureContent.addView(featureRow(
        getString(R.string.automation_proactive_retry),
        task.policy.retryBackoffSeconds.toString(),
        R.drawable.ic_agent_history,
        task.policy.maxAttempts.toString()
    ).apply {
        setOnClickListener {
            showTextSettingDialog(
                getString(R.string.automation_proactive_retry),
                task.policy.maxAttempts.toString()
            ) { value ->
                val attempts = value.toIntOrNull()?.coerceIn(1, 12) ?: task.policy.maxAttempts
                showProactiveTaskEditor(task.copy(policy = task.policy.copy(maxAttempts = attempts)))
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.automation_proactive_concurrency),
        getString(R.string.automation_proactive_tasks_subtitle),
        R.drawable.ic_agent_node,
        task.policy.maxConcurrency.toString()
    ).apply {
        setOnClickListener {
            showTextSettingDialog(
                getString(R.string.automation_proactive_concurrency),
                task.policy.maxConcurrency.toString()
            ) { value ->
                val count = value.toIntOrNull()?.coerceIn(1, 16) ?: task.policy.maxConcurrency
                showProactiveTaskEditor(task.copy(policy = task.policy.copy(maxConcurrency = count)))
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.automation_proactive_network),
        proactiveNetworkLabel(task.policy.network),
        R.drawable.ic_protocol_link,
        proactiveNetworkLabel(task.policy.network)
    ).apply {
        setOnClickListener {
            val values = listOf("any", "unmetered", "offline")
            val options = values.map(::proactiveNetworkLabel)
            showChoiceDialog(
                getString(R.string.automation_proactive_network),
                options,
                proactiveNetworkLabel(task.policy.network)
            ) { selected ->
                val value = values.first { proactiveNetworkLabel(it) == selected }
                showProactiveTaskEditor(task.copy(policy = task.policy.copy(network = value)))
            }
        }
    })
    featureContent.addView(featureSwitchRow(
        getString(R.string.automation_proactive_charging),
        getString(R.string.automation_proactive_tasks_subtitle),
        R.drawable.ic_protocol_link,
        task.policy.requiresCharging
    ).apply {
        setOnClickListener {
            showProactiveTaskEditor(
                task.copy(policy = task.policy.copy(requiresCharging = !task.policy.requiresCharging))
            )
        }
    })
    featureContent.addView(featureSwitchRow(
        getString(R.string.automation_proactive_enabled),
        getString(R.string.automation_proactive_tasks_subtitle),
        R.drawable.ic_automation_line,
        task.enabled
    ).apply {
        setOnClickListener { showProactiveTaskEditor(task.copy(enabled = !task.enabled)) }
    })
    addSectionTitle(getString(R.string.section_actions))
    featureContent.addView(featureRow(
        getString(R.string.common_save),
        getString(R.string.automation_proactive_save_subtitle),
        R.drawable.ic_import,
        getString(R.string.common_save)
    ).apply {
        setOnClickListener {
            runCatching {
                AgentProactiveTaskScheduler.save(
                    this@showProactiveTaskEditor,
                    task.copy(
                        revision = task.revision + if (
                            AgentProactiveTaskStore(this@showProactiveTaskEditor).task(task.taskId) == null
                        ) 0 else 1,
                        updatedAtMillis = System.currentTimeMillis()
                    )
                )
            }.onSuccess {
                Toast.makeText(
                    this@showProactiveTaskEditor,
                    getString(R.string.automation_proactive_saved),
                    Toast.LENGTH_SHORT
                ).show()
                showProactiveTaskDetails(task.taskId)
            }.onFailure { error ->
                Toast.makeText(
                    this@showProactiveTaskEditor,
                    getString(R.string.automation_proactive_invalid, error.message.orEmpty()),
                    Toast.LENGTH_LONG
                ).show()
            }
        }
    })
}

internal fun MainActivity.showProactiveTaskDetails(taskId: String) {
    val store = AgentProactiveTaskStore(this)
    val task = store.task(taskId) ?: return showAutomationFeaturePage()
    val runs = store.runs(taskId, limit = 50)
    showFeaturePage(getString(R.string.automation_proactive_details_title))
    setFeatureBackAction { showAutomationFeaturePage() }
    featureContent.addView(featureHeroCard(
        task.name,
        proactiveTaskSubtitle(task),
        R.drawable.ic_automation_line,
        if (task.enabled) "#14C66A" else "#8E8E93",
        proactiveRunStatusLabel(task.lastStatus)
    ))
    addSectionTitle(getString(R.string.section_actions))
    featureContent.addView(featureRow(
        getString(R.string.automation_proactive_run_now),
        getString(R.string.automation_proactive_run_now_subtitle),
        R.drawable.ic_send_plane,
        getString(R.string.automation_run)
    ).apply {
        setOnClickListener {
            runCatching { AgentProactiveTaskScheduler.triggerNow(this@showProactiveTaskDetails, taskId) }
                .onSuccess { showProactiveTaskDetails(taskId) }
                .onFailure {
                    Toast.makeText(
                        this@showProactiveTaskDetails,
                        getString(R.string.automation_proactive_invalid, it.message.orEmpty()),
                        Toast.LENGTH_LONG
                    ).show()
                }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.automation_proactive_edit),
        getString(R.string.automation_proactive_tasks_subtitle),
        R.drawable.ic_agent_control,
        getString(R.string.common_edit)
    ).apply {
        setOnClickListener { showProactiveTaskEditor(task) }
    })
    featureContent.addView(featureSwitchRow(
        getString(R.string.automation_proactive_enabled),
        proactiveTriggerDescription(task.trigger),
        R.drawable.ic_automation_line,
        task.enabled
    ).apply {
        setOnClickListener {
            AgentProactiveTaskScheduler.save(this@showProactiveTaskDetails, task.copy(enabled = !task.enabled))
            showProactiveTaskDetails(taskId)
        }
    })
    addSectionTitle(getString(R.string.automation_proactive_runs))
    if (runs.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.automation_proactive_no_runs),
            getString(R.string.automation_proactive_run_now_subtitle),
            R.drawable.ic_agent_history,
            ""
        ))
    } else {
        runs.forEach { run ->
            featureContent.addView(featureRow(
                proactiveRunStatusLabel(run.status),
                proactiveRunSubtitle(run),
                R.drawable.ic_agent_history,
                if (run.status.terminal) "" else getString(R.string.common_cancel)
            ).apply {
                if (!run.status.terminal) {
                    setOnClickListener {
                        AgentProactiveTaskExecutor.cancel(this@showProactiveTaskDetails, run.runId)
                        showProactiveTaskDetails(taskId)
                    }
                }
            })
        }
    }
    addSectionTitle(getString(R.string.security_section_danger))
    featureContent.addView(featureRow(
        getString(R.string.automation_proactive_delete),
        getString(R.string.automation_proactive_delete_confirm),
        R.drawable.ic_delete,
        getString(R.string.common_delete)
    ).apply {
        setOnClickListener {
            AlertDialog.Builder(this@showProactiveTaskDetails)
                .setMessage(getString(R.string.automation_proactive_delete_confirm))
                .setPositiveButton(getString(R.string.common_delete)) { _, _ ->
                    AgentProactiveTaskScheduler.cancel(this@showProactiveTaskDetails, taskId)
                    Toast.makeText(
                        this@showProactiveTaskDetails,
                        getString(R.string.automation_proactive_deleted),
                        Toast.LENGTH_SHORT
                    ).show()
                    showAutomationFeaturePage()
                }
                .setNegativeButton(getString(R.string.common_cancel), null)
                .show()
        }
    })
}

internal fun MainActivity.proactiveTriggerForKind(
    task: AgentProactiveTask,
    kind: AgentProactiveTriggerKind
): AgentProactiveTrigger = when (kind) {
    AgentProactiveTriggerKind.MANUAL -> AgentProactiveTrigger(kind)
    AgentProactiveTriggerKind.CRON -> AgentProactiveTrigger(
        kind = kind,
        cron = "0 9 * * *",
        timeZone = java.time.ZoneId.systemDefault().id
    )
    AgentProactiveTriggerKind.INTERVAL -> AgentProactiveTrigger(
        kind = kind,
        intervalSeconds = 3_600L,
        timeZone = java.time.ZoneId.systemDefault().id
    )
    AgentProactiveTriggerKind.GOAL_CHECKPOINT -> AgentProactiveTrigger(
        kind = kind,
        intervalSeconds = 3_600L,
        goalId = task.taskId,
        timeZone = java.time.ZoneId.systemDefault().id
    )
    AgentProactiveTriggerKind.WEBHOOK -> AgentProactiveTrigger(
        kind = kind,
        webhookId = task.taskId,
        timeZone = java.time.ZoneId.systemDefault().id
    )
}

internal fun MainActivity.proactiveActionForKind(
    task: AgentProactiveTask,
    kind: AgentProactiveActionKind
): AgentProactiveAction {
    val agentId = AppStoreAgentConnectorRegistry(this).availableTargets()
        .firstOrNull { it.status == AgentConnectorStatus.AVAILABLE }
        ?.id
        ?: "codex"
    return when (kind) {
        AgentProactiveActionKind.AGENT -> task.action.copy(
            kind = kind,
            targetId = agentId,
            team = emptyList()
        )
        AgentProactiveActionKind.SUBAGENT_TEAM -> task.action.copy(
            kind = kind,
            targetId = "",
            team = listOf(
                AgentProactiveTeamMember(agentId, AgentProactiveTeamRole.LEAD)
            )
        )
        AgentProactiveActionKind.WORKFLOW -> task.action.copy(
            kind = kind,
            targetId = SharedPreferencesAgentWorkflowStore(this).list().firstOrNull()?.id
                ?: "missing-workflow",
            team = emptyList()
        )
        AgentProactiveActionKind.NATIVE_TOOL -> task.action.copy(
            kind = kind,
            targetId = MobileNativeAgent(this).nativeToolCatalog().firstOrNull()?.id
                ?: "signalasi.device.status",
            argumentsJson = "{}",
            team = emptyList()
        )
    }
}

internal fun MainActivity.chooseProactiveTarget(task: AgentProactiveTask) {
    val targets = when (task.action.kind) {
        AgentProactiveActionKind.AGENT -> AppStoreAgentConnectorRegistry(this).availableTargets()
            .map { it.id to "${it.title} · ${it.id}" }
        AgentProactiveActionKind.WORKFLOW -> SharedPreferencesAgentWorkflowStore(this).list()
            .map { it.id to "${it.name} · ${it.id}" }
        AgentProactiveActionKind.NATIVE_TOOL -> MobileNativeAgent(this).nativeToolCatalog()
            .map { it.id to "${it.title} · ${it.id}" }
        AgentProactiveActionKind.SUBAGENT_TEAM -> emptyList()
    }.distinctBy { it.first }
    if (targets.isEmpty()) {
        showTextSettingDialog(
            getString(R.string.automation_proactive_target),
            task.action.targetId
        ) { value ->
            showProactiveTaskEditor(task.copy(action = task.action.copy(targetId = value)))
        }
        return
    }
    val current = targets.firstOrNull { it.first == task.action.targetId }?.second ?: targets.first().second
    showChoiceDialog(
        getString(R.string.automation_proactive_target),
        targets.map { it.second },
        current
    ) { selected ->
        val id = targets.first { it.second == selected }.first
        showProactiveTaskEditor(task.copy(action = task.action.copy(targetId = id)))
    }
}

internal fun MainActivity.parseProactiveTeam(value: String): List<AgentProactiveTeamMember> {
    val members = value.lineSequence().map(String::trim).filter(String::isNotBlank).map { line ->
        val values = line.split(":", limit = 2)
        require(values.size == 2) { getString(R.string.automation_proactive_team_hint) }
        val role = AgentProactiveTeamRole.valueOf(values[0].trim().uppercase(Locale.ROOT))
        AgentProactiveTeamMember(values[1].trim(), role)
    }.toList()
    require(members.count { it.role == AgentProactiveTeamRole.LEAD } == 1) {
        getString(R.string.automation_proactive_team_hint)
    }
    return members
}

internal fun MainActivity.proactiveTaskSubtitle(task: AgentProactiveTask): String = listOfNotNull(
    proactiveTriggerDescription(task.trigger),
    task.nextRunAtMillis.takeIf { it > 0L }?.let {
        getString(R.string.automation_proactive_next, automationTime(it))
    },
    getString(R.string.automation_proactive_last_status, proactiveRunStatusLabel(task.lastStatus))
).joinToString("\n")

internal fun MainActivity.proactiveRunSubtitle(run: AgentProactiveRun): String = listOfNotNull(
    automationTime(run.scheduledForMillis),
    getString(R.string.automation_proactive_attempt, run.attempt),
    run.resultSummary.trim().takeIf(String::isNotBlank)
).joinToString("\n")

internal fun MainActivity.proactiveTriggerDescription(trigger: AgentProactiveTrigger): String = when (trigger.kind) {
    AgentProactiveTriggerKind.MANUAL -> proactiveTriggerLabel(trigger.kind)
    AgentProactiveTriggerKind.CRON -> "${trigger.cron} · ${trigger.timeZone}"
    AgentProactiveTriggerKind.INTERVAL,
    AgentProactiveTriggerKind.GOAL_CHECKPOINT ->
        getString(R.string.automation_proactive_seconds, trigger.intervalSeconds)
    AgentProactiveTriggerKind.WEBHOOK -> getString(R.string.automation_proactive_webhook_hint)
}

internal fun MainActivity.proactiveActionDescription(action: AgentProactiveAction): String = when (action.kind) {
    AgentProactiveActionKind.SUBAGENT_TEAM ->
        action.team.joinToString(", ") { "${it.role.name.lowercase(Locale.ROOT)}:${it.agentId}" }
    else -> proactiveTargetTitle(action)
}

internal fun MainActivity.proactiveTargetTitle(action: AgentProactiveAction): String = when (action.kind) {
    AgentProactiveActionKind.AGENT -> AppStoreAgentConnectorRegistry(this).availableTargets()
        .firstOrNull { it.id == action.targetId }?.title ?: action.targetId
    AgentProactiveActionKind.WORKFLOW -> SharedPreferencesAgentWorkflowStore(this)
        .findById(action.targetId)?.name ?: action.targetId
    AgentProactiveActionKind.NATIVE_TOOL -> action.targetId
    AgentProactiveActionKind.SUBAGENT_TEAM -> action.team.joinToString(", ", transform = AgentProactiveTeamMember::agentId)
}

internal fun MainActivity.proactiveTriggerLabel(kind: AgentProactiveTriggerKind): String = getString(
    when (kind) {
        AgentProactiveTriggerKind.MANUAL -> R.string.automation_proactive_trigger_manual
        AgentProactiveTriggerKind.CRON -> R.string.automation_proactive_trigger_cron
        AgentProactiveTriggerKind.INTERVAL -> R.string.automation_proactive_trigger_interval
        AgentProactiveTriggerKind.GOAL_CHECKPOINT -> R.string.automation_proactive_trigger_goal
        AgentProactiveTriggerKind.WEBHOOK -> R.string.automation_proactive_trigger_webhook
    }
)

internal fun MainActivity.proactiveActionLabel(kind: AgentProactiveActionKind): String = getString(
    when (kind) {
        AgentProactiveActionKind.AGENT -> R.string.automation_proactive_action_agent
        AgentProactiveActionKind.SUBAGENT_TEAM -> R.string.automation_proactive_action_team
        AgentProactiveActionKind.WORKFLOW -> R.string.automation_proactive_action_workflow
        AgentProactiveActionKind.NATIVE_TOOL -> R.string.automation_proactive_action_tool
    }
)

internal fun MainActivity.proactiveActionIcon(kind: AgentProactiveActionKind): Int = when (kind) {
    AgentProactiveActionKind.AGENT,
    AgentProactiveActionKind.SUBAGENT_TEAM -> R.drawable.ic_agent_node
    AgentProactiveActionKind.WORKFLOW -> R.drawable.ic_automation_line
    AgentProactiveActionKind.NATIVE_TOOL -> R.drawable.ic_agent_control
}

internal fun MainActivity.proactiveDeliveryLabel(value: String): String = getString(
    when (value) {
        "notify" -> R.string.automation_proactive_delivery_notify
        "mobile" -> R.string.automation_proactive_delivery_mobile
        else -> R.string.automation_proactive_delivery_store
    }
)

internal fun MainActivity.proactiveNetworkLabel(value: String): String = getString(
    when (value) {
        "unmetered" -> R.string.automation_proactive_network_unmetered
        "offline" -> R.string.automation_proactive_network_offline
        else -> R.string.automation_proactive_network_any
    }
)

internal fun MainActivity.proactiveRunStatusLabel(status: AgentProactiveRunStatus): String = getString(
    when (status) {
        AgentProactiveRunStatus.QUEUED -> R.string.agent_task_status_queued
        AgentProactiveRunStatus.RUNNING,
        AgentProactiveRunStatus.RETRYING -> R.string.automation_run_status_running
        AgentProactiveRunStatus.WAITING -> R.string.cc_global_status_waiting
        AgentProactiveRunStatus.COMPLETED -> R.string.automation_run_status_completed
        AgentProactiveRunStatus.FAILED -> R.string.automation_run_status_failed
        AgentProactiveRunStatus.CANCELLED -> R.string.automation_run_status_cancelled
        AgentProactiveRunStatus.SKIPPED -> R.string.automation_run_status_skipped
    }
)

internal fun MainActivity.automationTime(timestampMillis: Long): String =
    SimpleDateFormat("MM-dd HH:mm:ss", Locale.getDefault()).format(Date(timestampMillis))

internal fun MainActivity.openAgentWorkflow(command: String) {
    hideFeaturePage()
    showMainTab(PAGE_AGENT)
    prefillAgentGoal(command)
}

internal fun MainActivity.automationScheduleSubtitle(schedule: AgentWorkflowSchedule): String {
    val cadence = when (schedule.kind) {
        AgentWorkflowScheduleKind.DAILY -> "%02d:%02d".format(Locale.US, schedule.hour, schedule.minute)
        AgentWorkflowScheduleKind.INTERVAL -> getString(
            R.string.automation_every_minutes,
            schedule.intervalMinutes
        )
    }
    val next = if (schedule.nextRunAtMillis > 0L) {
        SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date(schedule.nextRunAtMillis))
    } else {
        "-"
    }
    return getString(R.string.automation_schedule_subtitle, cadence, next)
}

internal fun MainActivity.automationTriggerSubtitle(trigger: AgentWorkflowTrigger): String {
    val event = when (trigger.kind) {
        AgentWorkflowTriggerKind.NOTIFICATION_PACKAGE ->
            getString(R.string.automation_trigger_notification_package, trigger.condition)
        AgentWorkflowTriggerKind.NOTIFICATION_TEXT ->
            getString(R.string.automation_trigger_notification_text, trigger.condition)
        AgentWorkflowTriggerKind.POWER_CONNECTED ->
            getString(R.string.automation_trigger_power_connected)
        AgentWorkflowTriggerKind.BATTERY_LOW ->
            getString(R.string.automation_trigger_battery_low)
    }
    val status = getString(if (trigger.enabled) R.string.status_enabled else R.string.common_off)
    return listOf(
        getString(
            R.string.automation_trigger_subtitle,
            event,
            trigger.cooldownMinutes,
            status
        ),
        automationTriggerConditionCountLabel(trigger)
    ).joinToString("\n")
}

internal fun MainActivity.automationTriggerConditionCountLabel(trigger: AgentWorkflowTrigger): String =
    getString(
        R.string.automation_trigger_condition_count,
        trigger.conditions.size
    )

internal fun MainActivity.automationExecutionSubtitle(execution: AgentWorkflowExecutionRecord): String {
    val source = automationExecutionSourceLabel(execution.source)
    val timestamp = execution.completedAtMillis.takeIf { it > 0L }
        ?: execution.startedAtMillis.takeIf { it > 0L }
    val time = timestamp?.let {
        SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date(it))
    } ?: getString(R.string.status_unknown)
    val result = execution.resultSummary.trim()
        .ifBlank { getString(R.string.automation_run_result_empty) }
    return listOf(
        getString(R.string.automation_run_source, source),
        getString(R.string.automation_run_time, time),
        getString(R.string.automation_run_result, result)
    ).joinToString("\n")
}

internal fun MainActivity.automationExecutionSourceLabel(source: AgentWorkflowExecutionSource): String = getString(
    when (source) {
        AgentWorkflowExecutionSource.MANUAL -> R.string.automation_run_source_manual
        AgentWorkflowExecutionSource.SCHEDULE -> R.string.automation_run_source_schedule
        AgentWorkflowExecutionSource.EVENT -> R.string.automation_run_source_event
        AgentWorkflowExecutionSource.PROACTIVE -> R.string.automation_run_source_proactive
    }
)

internal fun MainActivity.automationExecutionStatusLabel(status: AgentWorkflowExecutionStatus): String = getString(
    when (status) {
        AgentWorkflowExecutionStatus.RUNNING -> R.string.automation_run_status_running
        AgentWorkflowExecutionStatus.WAITING_CONFIRMATION ->
            R.string.automation_run_status_waiting_confirmation
        AgentWorkflowExecutionStatus.WAITING_RESPONSE ->
            R.string.automation_run_status_waiting_response
        AgentWorkflowExecutionStatus.COMPLETED -> R.string.automation_run_status_completed
        AgentWorkflowExecutionStatus.SKIPPED -> R.string.automation_run_status_skipped
        AgentWorkflowExecutionStatus.FAILED -> R.string.automation_run_status_failed
        AgentWorkflowExecutionStatus.CANCELLED -> R.string.automation_run_status_cancelled
        AgentWorkflowExecutionStatus.BLOCKED -> R.string.automation_run_status_blocked
    }
)

internal fun MainActivity.showSecurityFeaturePage() {
    val connectorContacts = activePcConnectorContacts()
    val desktops = desktopSecuritySummaries(connectorContacts)
    showFeaturePage(getString(R.string.security_title))
    featureContent.addView(featureHeroCard(getString(R.string.security_privacy_title), getString(R.string.security_privacy_subtitle), R.drawable.ic_security_shield, "#14C66A", getString(R.string.count_devices, desktops.size)))
    addSectionTitle(getString(R.string.security_section_identity))
    val localFingerprint = SignalASICrypto.localIdentitySha256()
    featureContent.addView(featureRow(getString(R.string.security_phone_fingerprint), formatFingerprint(localFingerprint), R.drawable.ic_security_shield, getString(R.string.common_copy)).apply {
        setOnClickListener { copyText(localFingerprint, getString(R.string.security_copied_phone_fingerprint)) }
    })
    featureContent.addView(featureRow(getString(R.string.settings_signalasi_id), SignalASICrypto.localSignalasiId(), R.drawable.ic_protocol_link, getString(R.string.common_copy)).apply {
        setOnClickListener { copyText(SignalASICrypto.localSignalasiId(), getString(R.string.security_copied_signalasi_id)) }
    })
    addSectionTitle(getString(R.string.security_section_paired_devices))
    if (desktops.isEmpty()) {
        featureContent.addView(featureRow(getString(R.string.security_no_paired_pc), getString(R.string.security_no_paired_pc_subtitle), R.drawable.ic_device_node, getString(R.string.security_scan)).apply {
            setOnClickListener {
                scanMode = "security"
                startSecurityScan()
            }
        })
    } else {
        desktops.forEach { device ->
            featureContent.addView(featureRow(
                device.name,
                "${formatFingerprint(device.fingerprint)}\n${getString(R.string.security_last_active, securityTime(device.lastActivityAt))}",
                R.drawable.ic_device_node,
                getString(R.string.security_manage)
            ).apply {
                setOnClickListener { showDesktopSecurityDetail(device) }
            })
        }
    }
    addSectionTitle(getString(R.string.security_section_agent_permissions))
    featureContent.addView(featureRow(getString(R.string.security_on_device_agent_permissions), getString(R.string.security_on_device_agent_permissions_subtitle), R.drawable.ic_agent_node, getString(R.string.common_view)).apply {
        setOnClickListener { showOnDeviceAgentFeaturePage() }
    })
    connectorContacts.take(8).forEach { contact ->
        val name = contact.optString("agent_name").ifBlank { contact.optString("name", "Agent") }
        val status = contact.optString("setup_status").ifBlank { "unknown" }
        val updatedAt = contact.optLong("setup_updated_at", contact.optLong("created_at", 0L))
        featureContent.addView(featureRow(
            name,
            getString(R.string.security_permission_status, securityStatusLabel(status), securityTime(updatedAt)),
            agentIconForKind(contact.optString("agent_kind"), contact.optString("agent_id")),
            securityStatusLabel(status)
        ))
    }
    if (connectorContacts.size > 8) {
        featureContent.addView(featureRow(getString(R.string.security_more_agents), getString(R.string.security_more_agents_subtitle, connectorContacts.size - 8), R.drawable.ic_agent_node, getString(R.string.common_view)))
    }
    addSectionTitle(getString(R.string.security_section_message_protection))
    featureContent.addView(featureRow("Signal Protocol", getString(R.string.security_signal_protocol_subtitle), R.drawable.ic_protocol_link, "v1.0.3"))
    featureContent.addView(featureRow(getString(R.string.security_fingerprint_confirm), getString(R.string.security_fingerprint_confirm_subtitle), R.drawable.ic_security_shield, getString(R.string.status_enabled)))
    featureContent.addView(featureRow(getString(R.string.security_revoke_all_pc), getString(R.string.security_revoke_all_pc_subtitle), R.drawable.ic_delete, getString(R.string.security_manage)).apply {
        setOnClickListener { showRevokeAllPcPairingsPage() }
    })
}

internal fun MainActivity.activePcConnectorContacts(): List<JSONObject> {
    val contacts = AppStore.contacts(this)
    val result = mutableListOf<JSONObject>()
    for (i in 0 until contacts.length()) {
        val contact = contacts.optJSONObject(i) ?: continue
        if (contact.optBoolean("deleted", false) || contact.optString("trust_state") == "deleted") continue
        if (contact.optString("delivery_mode") != "pc_connector") continue
        result.add(contact)
    }
    return result
}

internal fun MainActivity.desktopSecuritySummaries(connectorContacts: List<JSONObject>): List<DesktopSecuritySummary> {
    return connectorContacts
        .groupBy { contact ->
            contact.optString("desktop_id").ifBlank {
                "desktop_${contact.optString("desktop_fingerprint", contact.optString("identity_fingerprint")).take(16)}"
            }
        }
        .map { (desktopId, contacts) ->
            val first = contacts.firstOrNull() ?: JSONObject()
            val fingerprint = first.optString("desktop_fingerprint").ifBlank { first.optString("identity_fingerprint") }
            DesktopSecuritySummary(
                id = desktopId,
                name = first.optString("desktop_name").ifBlank { "PC" },
                fingerprint = fingerprint,
                agentCount = contacts.size,
                lastActivityAt = contacts.maxOfOrNull { it.optLong("setup_updated_at", it.optLong("created_at", 0L)) } ?: 0L,
                agentIds = contacts.flatMapTo(linkedSetOf()) { contact ->
                    listOf(
                        contact.optString("id"),
                        jsonSignalasiId(contact),
                        contact.optString("agent_id")
                    ).filter(String::isNotBlank)
                }
            )
        }
        .sortedBy { it.name.lowercase(Locale.ROOT) }
}

internal fun MainActivity.showDesktopSecurityDetail(device: DesktopSecuritySummary) {
    val agents = activePcConnectorContacts().filter { contact ->
        contact.optString("desktop_id") == device.id ||
            contact.optString("parent_contact") == device.id ||
            contact.optString("id").ifBlank { jsonSignalasiId(contact) }.startsWith("${device.id}:")
    }
    showFeaturePage(getString(R.string.security_device_detail_title))
    setFeatureBackAction { showSecurityFeaturePage() }
    featureContent.addView(featureHeroCard(device.name, getString(R.string.security_verified_desktop_connector), R.drawable.ic_device_node, "#14C66A", getString(R.string.count_items, device.agentCount)))
    addSectionTitle(getString(R.string.security_section_identity))
    featureContent.addView(featureRow("Desktop ID", device.id, R.drawable.ic_protocol_link, getString(R.string.common_copy)).apply {
        setOnClickListener { copyText(device.id, getString(R.string.security_copied_desktop_id)) }
    })
    featureContent.addView(featureRow(getString(R.string.security_desktop_fingerprint), formatFingerprint(device.fingerprint), R.drawable.ic_security_shield, getString(R.string.common_copy)).apply {
        setOnClickListener { copyText(device.fingerprint, getString(R.string.security_copied_desktop_fingerprint)) }
    })
    featureContent.addView(featureRow(getString(R.string.security_last_active_title), securityTime(device.lastActivityAt), R.drawable.ic_protocol_link, ""))
    featureContent.addView(featureRow(
        getString(R.string.device_remote_control),
        getString(R.string.desktop_control_manage_subtitle),
        R.drawable.ic_security_shield,
        getString(if (DesktopRemoteControl.snapshot(this, device.id).authorized) R.string.status_enabled else R.string.security_manage)
    ).apply {
        setOnClickListener {
            DesktopRemoteControl.requestAuthorizations(device.id)
            showDesktopRemoteControlPage(device)
        }
    })
    addSectionTitle("Agent")
    agents.forEach { contact ->
        val name = contact.optString("agent_name").ifBlank { contact.optString("name", "Agent") }
        val status = contact.optString("setup_status").ifBlank { "unknown" }
        featureContent.addView(featureRow(
            name,
            contact.optString("setup_detail").ifBlank { contact.optString("agent_kind") },
            agentIconForKind(contact.optString("agent_kind"), contact.optString("agent_id")),
            securityStatusLabel(status)
        ))
    }
    addSectionTitle(getString(R.string.security_section_danger))
    featureContent.addView(featureRow(getString(R.string.security_revoke_this_pc), getString(R.string.security_revoke_this_pc_subtitle), R.drawable.ic_delete, getString(R.string.security_revoke)).apply {
        setOnClickListener { confirmRevokeDesktop(device) }
    })
}

internal fun MainActivity.confirmRevokeDesktop(device: DesktopSecuritySummary) {
    showFeaturePage(getString(R.string.security_revoke_device_title))
    featureContent.addView(featureHeroCard(device.name, getString(R.string.security_revoke_device_subtitle), R.drawable.ic_delete, "#FF3B30", getString(R.string.common_confirm)))
    featureContent.addView(featureRow(getString(R.string.security_revoke_scope), getString(R.string.count_pc_connector_agents, device.agentCount), R.drawable.ic_agent_node, getString(R.string.security_delete)))
    featureContent.addView(featureRow(getString(R.string.security_desktop_fingerprint), formatFingerprint(device.fingerprint), R.drawable.ic_security_shield, ""))
    featureContent.addView(TextView(this).apply {
        text = getString(R.string.security_revoke_this_pc)
        gravity = Gravity.CENTER
        setTextColor(Color.WHITE)
        textSize = 17f
        background = GradientDrawable().apply {
            cornerRadius = dp(8).toFloat()
            setColor(Color.parseColor("#FF3B30"))
        }
        setOnClickListener {
            if (AppStore.revokeDesktopConnector(this@confirmRevokeDesktop, device.id)) {
                refreshDirectoryContacts()
                Toast.makeText(this@confirmRevokeDesktop, getString(R.string.security_revoked_device, device.name), Toast.LENGTH_LONG).show()
            }
            showSecurityFeaturePage()
        }
    }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(46)).apply {
        topMargin = dp(18)
    })
}

internal fun MainActivity.showRevokeAllPcPairingsPage() {
    showFeaturePage(getString(R.string.security_revoke_all_pc))
    val desktops = desktopSecuritySummaries(activePcConnectorContacts())
    featureContent.addView(featureHeroCard(getString(R.string.security_revoke_all_pc_title), getString(R.string.security_revoke_all_pc_hero_subtitle), R.drawable.ic_delete, "#FF3B30", getString(R.string.count_devices, desktops.size)))
    desktops.forEach { device ->
        featureContent.addView(featureRow(device.name, getString(R.string.security_device_agent_fingerprint_summary, device.agentCount, formatFingerprint(device.fingerprint)), R.drawable.ic_device_node, getString(R.string.security_will_revoke)))
    }
    featureContent.addView(TextView(this).apply {
        text = getString(R.string.security_revoke_all_pc)
        gravity = Gravity.CENTER
        setTextColor(Color.WHITE)
        textSize = 17f
        background = GradientDrawable().apply {
            cornerRadius = dp(8).toFloat()
            setColor(Color.parseColor("#FF3B30"))
        }
        setOnClickListener {
            desktops.forEach { AppStore.revokeDesktopConnector(this@showRevokeAllPcPairingsPage, it.id) }
            refreshDirectoryContacts()
            Toast.makeText(this@showRevokeAllPcPairingsPage, getString(R.string.security_revoked_all_pc), Toast.LENGTH_LONG).show()
            showSecurityFeaturePage()
        }
    }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(46)).apply {
        topMargin = dp(18)
    })
}

internal fun MainActivity.securityStatusLabel(status: String): String = when (status) {
    "ready" -> getString(R.string.status_ready)
    "needs_setup" -> getString(R.string.status_needs_setup)
    "unknown" -> getString(R.string.status_unknown)
    else -> status.ifBlank { getString(R.string.status_unknown) }
}

internal fun MainActivity.securityTime(timestamp: Long): String {
    if (timestamp <= 0L) return getString(R.string.status_unknown)
    return SimpleDateFormat("MM/dd HH:mm", Locale.getDefault()).format(Date(timestamp))
}

internal fun MainActivity.agentIconForKind(kind: String, agentId: String): Int = when {
    agentId == "hermes" -> R.drawable.ic_avatar_hermes
    agentId == "codex" -> R.drawable.logo_codex_product
    agentId == "claude" -> R.drawable.logo_claude_code
    agentId == "openclaw" -> R.drawable.ic_avatar_custom_agent
    kind == "local-model" -> R.drawable.ic_local_model
    else -> R.drawable.ic_agent_node
}

internal fun MainActivity.showProtocolQualityFeaturePage() {
    showFeaturePage(getString(R.string.protocol_quality_title))
    featureContent.addView(featureHeroCard("SignalASI Link", getString(R.string.protocol_quality_hero_subtitle), R.drawable.ic_protocol_link, "#5B6CFF", "v1.0.3"))
    addSectionTitle(getString(R.string.protocol_section_quality))
    featureContent.addView(featureRow(getString(R.string.protocol_delivery_ack), getString(R.string.protocol_delivery_ack_subtitle), R.drawable.ic_send_plane, getString(R.string.common_on)))
    featureContent.addView(featureRow(getString(R.string.protocol_offline_queue), getString(R.string.protocol_offline_queue_subtitle), R.drawable.ic_import, getString(R.string.protocol_badge_enabled)))
    addSectionTitle(getString(R.string.protocol_section_security))
    featureContent.addView(featureRow(getString(R.string.protocol_identity_key), getString(R.string.protocol_identity_key_subtitle), R.drawable.ic_security_shield, getString(R.string.protocol_badge_enabled)))
    featureContent.addView(featureRow(getString(R.string.protocol_session_rotation), getString(R.string.protocol_session_rotation_subtitle), R.drawable.ic_protocol_link, getString(R.string.protocol_badge_enabled)))
}

internal fun MainActivity.showSignalLinkProtocolPage() {
    val transportConnected = SignalASIMqttClient.isConnected()
    val secureSessionReady = transportConnected && SignalASIMqttClient.isSecureReady()
    showFeaturePage("Signal Link Protocol")
    featureContent.addView(featureHeroCard(
        "Signal Link Protocol",
        getString(if (secureSessionReady) R.string.cc_service_link_connected else R.string.cc_service_link_offline),
        R.drawable.ic_protocol_link,
        if (secureSessionReady) "#14C66A" else "#F0A500",
        getString(if (secureSessionReady) R.string.protocol_badge_stable else R.string.status_disconnected)
    ))
    addSectionTitle(getString(R.string.protocol_section_layers))
    featureContent.addView(featureRow(getString(R.string.protocol_identity_layer), getString(R.string.protocol_identity_layer_subtitle), R.drawable.ic_security_shield, getString(R.string.protocol_badge_enabled)))
    featureContent.addView(featureRow(
        getString(R.string.protocol_session_layer),
        getString(R.string.protocol_session_layer_subtitle),
        R.drawable.ic_protocol_link,
        getString(if (secureSessionReady) R.string.protocol_badge_enabled else R.string.status_disconnected)
    ))
    featureContent.addView(featureRow(
        getString(R.string.protocol_transport_layer),
        getString(R.string.protocol_transport_layer_subtitle),
        R.drawable.ic_device_node,
        if (transportConnected) "MQTT" else getString(R.string.status_disconnected)
    ))
    addSectionTitle(getString(R.string.protocol_section_current_endpoint))
    featureContent.addView(featureRow(
        getString(R.string.protocol_pc_endpoint),
        getString(if (secureSessionReady) R.string.cc_service_link_connected else R.string.cc_service_link_offline),
        R.drawable.ic_device_node,
        getString(if (secureSessionReady) R.string.protocol_badge_online else R.string.status_disconnected)
    ))
    val diagnostics = SignalASILinkTransportDiagnostics.snapshot(this)
    addSectionTitle(getString(R.string.protocol_transport_diagnostics))
    featureContent.addView(featureRow(
        getString(R.string.protocol_replay_events),
        getString(R.string.protocol_replay_events_subtitle),
        R.drawable.ic_protocol_link,
        diagnostics.replayCount.toString()
    ))
    featureContent.addView(featureRow(
        getString(R.string.protocol_duplicate_events),
        getString(R.string.protocol_duplicate_events_subtitle),
        R.drawable.ic_device_node,
        diagnostics.duplicateCount.toString()
    ))
    featureContent.addView(featureRow(
        getString(R.string.protocol_old_counter_events),
        getString(R.string.protocol_old_counter_events_subtitle),
        R.drawable.ic_security_shield,
        diagnostics.oldCounterCount.toString()
    ))
    featureContent.addView(featureRow(
        getString(R.string.protocol_transport_failures),
        getString(R.string.protocol_transport_failures_subtitle),
        R.drawable.ic_security_shield,
        diagnostics.failureCount.toString()
    ))
    addSectionTitle(getString(R.string.protocol_recent_transport_events))
    if (diagnostics.recentEvents.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.protocol_no_transport_anomalies),
            getString(R.string.protocol_no_transport_anomalies_subtitle),
            R.drawable.ic_security_shield,
            getString(R.string.protocol_badge_stable)
        ))
    } else {
        diagnostics.recentEvents.take(5).forEach { event ->
            val references = listOf(event.endpointRef, event.messageRef)
                .filter(String::isNotBlank)
                .joinToString(" / ")
                .ifBlank { getString(R.string.status_unknown) }
            featureContent.addView(featureRow(
                protocolDiagnosticEventLabel(event.kind),
                getString(
                    R.string.protocol_transport_event_subtitle,
                    securityTime(event.recordedAtMillis),
                    references
                ),
                R.drawable.ic_protocol_link,
                getString(R.string.protocol_diagnostic_recorded)
            ))
        }
    }
}

internal fun MainActivity.protocolDiagnosticEventLabel(kind: SignalASILinkDiagnosticKind): String = getString(
    when (kind) {
        SignalASILinkDiagnosticKind.ENCRYPTED_REPLAY -> R.string.protocol_event_encrypted_replay
        SignalASILinkDiagnosticKind.PENDING_REPLAY -> R.string.protocol_event_pending_replay
        SignalASILinkDiagnosticKind.DUPLICATE_MESSAGE -> R.string.protocol_event_duplicate_message
        SignalASILinkDiagnosticKind.DUPLICATE_RECEIPT -> R.string.protocol_event_duplicate_receipt
        SignalASILinkDiagnosticKind.OLD_COUNTER -> R.string.protocol_event_old_counter
        SignalASILinkDiagnosticKind.DECRYPT_FAILURE -> R.string.protocol_event_decrypt_failure
        SignalASILinkDiagnosticKind.CHUNK_DUPLICATE -> R.string.protocol_event_chunk_duplicate
        SignalASILinkDiagnosticKind.FRAGMENT_REJECTED -> R.string.protocol_event_fragment_rejected
    }
)

internal fun MainActivity.showAdvancedOptionsFeaturePage() {
    renderControlCenterAdvancedPage()
}
