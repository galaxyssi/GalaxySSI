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

internal fun MainActivity.showAgentRecentTasksPage() {
    val state = mobileNativeAgent.snapshot()
    val teams = globalSuperAgentRuntime.agentTeamSnapshots().take(20)
    showFeaturePage(getString(R.string.cc_tasks_title))
    if (state.recentTasks.isEmpty() && teams.isEmpty()) {
        featureContent.addView(agentRecentEmptyRow())
        return
    }
    if (state.recentTasks.isNotEmpty()) {
        addSectionTitle(getString(R.string.agent_section_recent_tasks))
        state.recentTasks.take(20).forEachIndexed { index, task ->
            featureContent.addView(agentRecentTaskRow(task, index))
        }
    }
    if (teams.isNotEmpty()) {
        addSectionTitle(getString(R.string.agent_team_section_title))
        teams.forEach { team ->
            featureContent.addView(featureRow(
                title = team.goal.ifBlank { team.teamId },
                subtitle = getString(
                    R.string.agent_team_summary,
                    team.members.count { it.deliveryMode != AgentDeliveryMode.IGNORE },
                    agentTeamStateText(team.state)
                ),
                iconRes = R.drawable.ic_agent_history,
                action = getString(R.string.agent_team_details_action)
            ).apply { setOnClickListener { showAgentTeamDetails(team) } })
        }
    }
}

internal fun MainActivity.showAgentTeamDetails(team: AgentTeamExecutionSnapshot) {
    val projection = AgentTeamProgressPolicy.project(team, expanded = true)
    showFeaturePage(getString(R.string.agent_team_details_title))
    setFeatureBackAction { showAgentRecentTasksPage() }
    val activeMembers = projection.members.filter { it.deliveryMode != AgentDeliveryMode.IGNORE }
    val working = activeMembers.count { it.status == AgentSubagentStatus.RUNNING }
    featureContent.addView(featureHeroCard(
        title = team.goal.ifBlank { getString(R.string.agent_team_details_title) },
        subtitle = getString(
            R.string.agent_team_live_summary,
            activeMembers.size,
            working,
            agentTeamStateText(team.state)
        ),
        iconRes = R.drawable.ic_agent_node,
        colorHex = "#16A085",
        badge = if (team.state.isTerminal) {
            agentTeamStateText(team.state)
        } else {
            getString(R.string.agent_team_live_badge)
        }
    ))

    addSectionTitle(getString(R.string.agent_team_members_label))
    activeMembers.forEach { member ->
        val memberTitle = if (member.memberId == member.agentId) {
            member.agentId
        } else {
            member.memberId
        }
        val subtitle = listOf(
            member.role,
            agentTeamMemberStateText(member.status),
            member.errorMessage.take(120)
        ).filter(String::isNotBlank).joinToString(" · ")
        featureContent.addView(featureRow(
            title = memberTitle,
            subtitle = subtitle,
            iconRes = R.drawable.ic_avatar_ai_agent,
            action = if (!team.state.isTerminal) getString(R.string.agent_team_message_action) else ""
        ).apply {
            if (!team.state.isTerminal) {
                setOnClickListener { showAgentTeamMessageComposer(team, member) }
            }
        })
    }

    val messages = globalSuperAgentRuntime.agentTeamMessages(team.supervisorRunId)
    if (messages.isNotEmpty()) {
        addSectionTitle(getString(R.string.agent_team_messages_label))
        messages.takeLast(20).forEach { message ->
            featureContent.addView(featureRow(
                title = getString(
                    R.string.agent_team_message_route,
                    message.fromInstanceId,
                    message.toInstanceId.ifBlank { getString(R.string.agent_team_everyone) }
                ),
                subtitle = message.text,
                iconRes = R.drawable.ic_composer_send_plane,
                action = when (message.state) {
                    AgentTeamMessageState.PENDING -> getString(R.string.agent_team_message_pending)
                    AgentTeamMessageState.DELIVERED -> getString(R.string.agent_team_message_delivered)
                    AgentTeamMessageState.ACKNOWLEDGED -> getString(R.string.agent_team_message_acknowledged)
                }
            ))
        }
    }

    if (projection.finalOutput.isNotBlank()) {
        addSectionTitle(getString(R.string.agent_team_result_label))
        featureContent.addView(featureRow(
            title = getString(R.string.agent_team_single_answer),
            subtitle = projection.finalOutput,
            iconRes = R.drawable.ic_agent_history,
            action = ""
        ))
    }
}

internal fun MainActivity.showAgentTeamMessageComposer(
    team: AgentTeamExecutionSnapshot,
    member: AgentTeamMemberSnapshot
) {
    val input = EditText(this).apply {
        hint = getString(R.string.agent_team_message_hint)
        minLines = 3
        maxLines = 6
        setPadding(dp(16), dp(12), dp(16), dp(12))
        background = getDrawable(R.drawable.agent_input_shell_background)
    }
    val dialog = android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_team_message_title, member.memberId))
        .setView(input)
        .setNegativeButton(getString(R.string.common_cancel), null)
        .setPositiveButton(getString(R.string.agent_team_message_send), null)
        .create()
    dialog.setOnShowListener {
        dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            val text = input.text.toString().trim()
            if (text.isBlank()) return@setOnClickListener
            dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE).isEnabled = false
            thread(name = "signalasi-team-message") {
                val result = runCatching {
                    runBlocking {
                        globalSuperAgentRuntime.sendAgentTeamMessage(
                            team.supervisorRunId,
                            member.memberId,
                            text
                        )
                    }
                }
                runOnUiThread {
                    result.onSuccess {
                        dialog.dismiss()
                        val refreshed = globalSuperAgentRuntime.agentTeamSnapshot(team.supervisorRunId)
                        showAgentTeamDetails(refreshed ?: team)
                    }.onFailure { error ->
                        dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE).isEnabled = true
                        Toast.makeText(
                            this@showAgentTeamMessageComposer,
                            error.message ?: getString(R.string.agent_team_message_failed),
                            Toast.LENGTH_LONG
                        ).show()
                    }
                }
            }
        }
    }
    dialog.show()
}

internal fun MainActivity.agentTeamStateText(state: AgentTeamExecutionState): String = getString(when (state) {
    AgentTeamExecutionState.QUEUED -> R.string.agent_team_state_queued
    AgentTeamExecutionState.RUNNING -> R.string.agent_team_state_running
    AgentTeamExecutionState.SUCCEEDED -> R.string.agent_team_state_succeeded
    AgentTeamExecutionState.COMPLETED_WITH_FAILURES -> R.string.agent_team_state_completed_with_failures
    AgentTeamExecutionState.FAILED -> R.string.agent_team_state_failed
    AgentTeamExecutionState.CANCELLED -> R.string.agent_team_state_cancelled
    AgentTeamExecutionState.INTERRUPTED -> R.string.agent_team_state_interrupted
})

internal fun MainActivity.agentTeamMemberStateText(state: AgentSubagentStatus): String = getString(when (state) {
    AgentSubagentStatus.QUEUED -> R.string.agent_team_state_queued
    AgentSubagentStatus.RUNNING -> R.string.agent_team_state_running
    AgentSubagentStatus.SUCCEEDED -> R.string.agent_team_state_succeeded
    AgentSubagentStatus.FAILED -> R.string.agent_team_state_failed
    AgentSubagentStatus.CANCELLED -> R.string.agent_team_state_cancelled
    AgentSubagentStatus.SKIPPED -> R.string.agent_team_member_state_skipped
})

internal fun MainActivity.showCapabilityLibraryPage(selectedKind: AgentCapabilityCatalogKind) {
    SignalASIMqttClient.requestCapabilityManifestRefresh()
    showFeaturePage(getString(R.string.agent_capability_library_title))
    setFeatureBackAction()
    val items = marketplaceItems()
    val installedCount = items.count {
        it.installState in setOf(
            AgentMarketplaceInstallState.BUILT_IN,
            AgentMarketplaceInstallState.INSTALLED
        )
    } + AgentDesktopMarketplaceStore.list(this).count {
        it.installState in setOf(
            AgentMarketplaceInstallState.BUILT_IN,
            AgentMarketplaceInstallState.INSTALLED
        )
    }
    featureContent.addView(featureHeroCard(
        getString(R.string.agent_capability_library_title),
        getString(R.string.agent_capability_library_subtitle),
        R.drawable.ic_agent_skill,
        when (selectedKind) {
            AgentCapabilityCatalogKind.NATIVE_TOOL -> "#14C66A"
            AgentCapabilityCatalogKind.MCP -> "#2979FF"
            AgentCapabilityCatalogKind.AUTOMATION -> "#7C4DFF"
        },
        installedCount.toString()
    ))
    addCapabilityLibraryTabs(selectedKind)
    when (selectedKind) {
        AgentCapabilityCatalogKind.NATIVE_TOOL -> renderNativeToolMarketplace()
        AgentCapabilityCatalogKind.MCP -> renderMcpCapabilityLibrary()
        AgentCapabilityCatalogKind.AUTOMATION -> renderAutomationMarketplace()
    }
}

internal fun MainActivity.marketplaceItems(): List<AgentMarketplaceItem> =
    AgentDefaultCapabilityCatalog.marketplaceItems(
        nativeTools = mobileNativeAgent.nativeToolCatalog(),
        installedMcp = agentMcpRegistry.list(),
        installedAutomations = agentSkillRuntime.list()
    )

internal fun MainActivity.returnToCapabilityLibrary(kind: AgentCapabilityCatalogKind) {
    if (controlCenterBackStack.lastOrNull()?.route == ControlCenterRoute.MCP) controlCenterBackStack.removeLast()
    openControlCenterDestination(
        ControlCenterDestination(ControlCenterRoute.MCP, capabilityKindPayload(kind)),
        pushCurrent = false
    )
}

internal fun MainActivity.addCapabilityLibraryTabs(selectedKind: AgentCapabilityCatalogKind) {
    val row = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        setPadding(dp(3), dp(3), dp(3), dp(3))
        background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(10).toFloat()
            setColor(Color.parseColor("#EEF1F5"))
        }
    }
    listOf(
        AgentCapabilityCatalogKind.NATIVE_TOOL to getString(R.string.agent_marketplace_tools),
        AgentCapabilityCatalogKind.MCP to getString(R.string.agent_mcp_title),
        AgentCapabilityCatalogKind.AUTOMATION to getString(R.string.agent_marketplace_automations)
    ).forEach { (kind, label) ->
        val selected = kind == selectedKind
        row.addView(TextView(this).apply {
            text = label
            gravity = Gravity.CENTER
            textSize = 14f
            setTypeface(typeface, if (selected) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL)
            setTextColor(getColorCompat(if (selected) R.color.text_primary else R.color.text_secondary))
            background = if (selected) GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(8).toFloat()
                setColor(Color.WHITE)
                setStroke(1, Color.parseColor("#DDE3EA"))
            } else null
            setOnClickListener {
                if (!selected) {
                    openControlCenterDestination(
                        ControlCenterDestination(ControlCenterRoute.MCP, capabilityKindPayload(kind)),
                        pushCurrent = false
                    )
                }
            }
        }, LinearLayout.LayoutParams(0, dp(40), 1f))
    }
    featureContent.addView(row, LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        dp(46)
    ).apply { bottomMargin = dp(14) })
}

internal fun MainActivity.renderNativeToolMarketplace() {
    val items = marketplaceItems().filter { it.kind == AgentCapabilityCatalogKind.NATIVE_TOOL }
    val ready = items.filter {
        it.installState == AgentMarketplaceInstallState.BUILT_IN
    }
    val attention = items.filterNot {
        it.installState == AgentMarketplaceInstallState.BUILT_IN
    }
    addSectionTitle(getString(R.string.agent_capability_installed))
    ready.forEach { item ->
        featureContent.addView(featureRow(
            item.name,
            listOf(item.summary, marketplaceLifecycleSummary(item)).filter(String::isNotBlank).joinToString(" · "),
            R.drawable.ic_agent_control,
            getString(R.string.agent_marketplace_built_in)
        ).apply {
            setOnClickListener {
                showNativeToolDetailPage(item.id)
                setFeatureBackAction {
                    returnToCapabilityLibrary(AgentCapabilityCatalogKind.NATIVE_TOOL)
                }
            }
        })
    }
    if (attention.isNotEmpty()) {
        addSectionTitle(getString(R.string.agent_marketplace_needs_attention))
        attention.forEach { item ->
            featureContent.addView(featureRow(
                item.name,
                listOf(item.summary, marketplaceLifecycleSummary(item)).filter(String::isNotBlank).joinToString(" · "),
                R.drawable.ic_agent_control,
                marketplaceStateLabel(item.installState)
            ).apply {
                setOnClickListener {
                    showNativeToolDetailPage(item.id)
                    setFeatureBackAction {
                        returnToCapabilityLibrary(AgentCapabilityCatalogKind.NATIVE_TOOL)
                    }
                }
            })
        }
    }
    renderPairedDesktopMarketplace(AgentCapabilityCatalogKind.NATIVE_TOOL)
}

internal fun MainActivity.renderMcpCapabilityLibrary() {
    featureContent.addView(featureRow(
        getString(R.string.agent_mcp_add_remote),
        getString(R.string.agent_mcp_add_remote_subtitle),
        R.drawable.ic_protocol_link,
        getString(R.string.agent_capability_add)
    ).apply { setOnClickListener { showRemoteMcpSetupPage() } })
    featureContent.addView(featureRow(
        getString(R.string.agent_mcp_install_package),
        getString(R.string.agent_mcp_install_package_subtitle),
        R.drawable.ic_import,
        getString(R.string.common_select)
    ).apply { setOnClickListener { openMcpPackagePicker() } })

    val installed = agentMcpRegistry.list()
    addSectionTitle(getString(R.string.agent_capability_installed))
    if (installed.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.agent_mcp_empty),
            getString(R.string.agent_mcp_empty_subtitle),
            R.drawable.ic_agent_skill,
            ""
        ))
    } else {
        installed.forEach { connection ->
            featureContent.addView(featureRow(
                connection.displayName,
                mcpConnectionSubtitle(connection),
                R.drawable.ic_agent_skill,
                mcpConnectionStatus(connection)
            ).apply { setOnClickListener { showMcpConnectionDetailPage(connection.id) } })
        }
    }

    addSectionTitle(getString(R.string.agent_capability_recommended))
    val marketplaceById = marketplaceItems()
        .filter { it.kind == AgentCapabilityCatalogKind.MCP }
        .associateBy { it.id }
    AgentDefaultCapabilityCatalog.mcpEntries.forEach { entry ->
        val connection = installed.firstOrNull { it.catalogId == entry.id }
        val marketplaceItem = marketplaceById[entry.id]
        featureContent.addView(featureRow(
            entry.name,
            listOf(
                localizedMcpSummary(entry),
                marketplaceItem?.let(::marketplaceLifecycleSummary).orEmpty()
            ).filter(String::isNotBlank).joinToString(" · "),
            R.drawable.ic_agent_skill,
            when {
                connection != null -> mcpConnectionStatus(connection)
                entry.requiresPackage -> getString(R.string.agent_capability_install)
                else -> getString(R.string.agent_capability_add)
            }
        ).apply {
            setOnClickListener {
                when {
                    connection != null -> showMcpConnectionDetailPage(connection.id)
                    entry.requiresPackage -> openMcpPackagePicker()
                    else -> showRemoteMcpSetupPage(entry)
                }
            }
        })
    }
    renderPairedDesktopMarketplace(AgentCapabilityCatalogKind.MCP)
}

internal fun MainActivity.renderAutomationMarketplace() {
    featureContent.addView(featureRow(
        getString(R.string.agent_skill_install_local),
        getString(R.string.agent_skill_install_local_subtitle),
        R.drawable.ic_import,
        getString(R.string.common_select)
    ).apply {
        setOnClickListener {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/zip"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/zip", "application/octet-stream"))
            }, REQUEST_IMPORT_SKILL)
        }
    })
    val installations = agentSkillRuntime.list()
        .groupBy { it.id }
        .values
        .mapNotNull { versions -> versions.maxByOrNull { skillVersionParts(it.version) } }
        .sortedBy { it.manifest.title.lowercase(Locale.ROOT) }
    addSectionTitle(getString(R.string.agent_capability_installed))
    if (installations.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.agent_skills_empty),
            getString(R.string.agent_skills_empty_subtitle),
            R.drawable.ic_agent_skill,
            ""
        ))
    } else {
        installations.forEach { installation ->
            val state = getString(if (installation.enabled) R.string.agent_skill_enabled else R.string.agent_skill_disabled)
            val marketItem = marketplaceItems().firstOrNull { it.id == installation.id }
            featureContent.addView(featureRow(
                installation.manifest.title,
                listOf(
                    installation.manifest.description,
                    "v${installation.version}",
                    marketItem?.let(::marketplaceLifecycleSummary).orEmpty(),
                    getString(R.string.agent_skill_uses, installation.useCount)
                )
                    .filter(String::isNotBlank).joinToString(" · "),
                R.drawable.ic_agent_skill,
                state
            ).apply { setOnClickListener { showAgentSkillDetailPage(installation.id, installation.version) } })
        }
    }

    val installedIds = installations.mapTo(mutableSetOf()) { it.id }
    val nativeTools = mobileNativeAgent.nativeToolCatalog().mapTo(mutableSetOf()) { it.id }
    addSectionTitle(getString(R.string.agent_capability_recommended))
    AgentDefaultCapabilityCatalog.skillEntries.forEach { entry ->
        val dependency = AgentCapabilityDependencyResolver.resolve(entry, agentMcpRegistry.list(), nativeTools)
        val installed = entry.id in installedIds
        featureContent.addView(featureRow(
            entry.name,
            localizedSkillSummary(entry, dependency),
            R.drawable.ic_agent_skill,
            when {
                installed -> getString(R.string.agent_capability_added)
                dependency.available -> getString(R.string.agent_capability_add)
                else -> getString(R.string.agent_capability_requires_setup)
            }
        ).apply {
            setOnClickListener {
                when {
                    installed -> installations.firstOrNull { it.id == entry.id }
                        ?.let { showAgentSkillDetailPage(it.id, it.version) }
                    !dependency.available -> {
                        Toast.makeText(this@renderAutomationMarketplace, getString(R.string.agent_skill_dependency_missing), Toast.LENGTH_LONG).show()
                        openControlCenterDestination(
                            ControlCenterDestination(ControlCenterRoute.MCP, CAPABILITY_KIND_MCP),
                            pushCurrent = false
                        )
                    }
                    else -> runCatching { agentSkillRuntime.install(entry.manifest) }
                        .onSuccess { showAgentSkillDetailPage(it.id, it.version) }
                        .onFailure { Toast.makeText(this@renderAutomationMarketplace, it.message ?: getString(R.string.agent_skill_install_failed), Toast.LENGTH_LONG).show() }
                }
            }
        })
    }
    renderPairedDesktopMarketplace(AgentCapabilityCatalogKind.AUTOMATION)
}

internal fun MainActivity.renderPairedDesktopMarketplace(kind: AgentCapabilityCatalogKind) {
    val remoteItems = AgentDesktopMarketplaceStore.list(this, kind)
    if (remoteItems.isEmpty()) return
    addSectionTitle(getString(R.string.agent_marketplace_paired_desktops))
    remoteItems.forEach { item ->
        featureContent.addView(featureRow(
            item.name,
            listOf(
                item.desktopName,
                item.summary,
                desktopMarketplaceLifecycleSummary(item)
            ).filter(String::isNotBlank).joinToString(" · "),
            when (kind) {
                AgentCapabilityCatalogKind.NATIVE_TOOL -> R.drawable.ic_agent_control
                AgentCapabilityCatalogKind.MCP -> R.drawable.ic_agent_skill
                AgentCapabilityCatalogKind.AUTOMATION -> R.drawable.ic_agent_history
            },
            when {
                item.revoked -> getString(R.string.agent_marketplace_access_revoked)
                item.updateAvailable -> getString(R.string.agent_marketplace_update)
                else -> marketplaceStateLabel(item.installState)
            }
        ))
    }
}

internal fun MainActivity.marketplaceLifecycleSummary(item: AgentMarketplaceItem): String = buildList {
    add(getString(R.string.agent_marketplace_version, item.availableVersion))
    if (item.capabilities.isNotEmpty()) {
        add(getString(R.string.agent_marketplace_capability_count, item.capabilities.size))
    }
    if (item.permissionDiff.added.isNotEmpty()) {
        add(getString(R.string.agent_marketplace_new_permission_count, item.permissionDiff.added.size))
    } else if (item.permissions.isNotEmpty()) {
        add(getString(R.string.agent_marketplace_permission_count, item.permissions.size))
    }
    if (item.rollbackVersions.isNotEmpty()) {
        add(getString(R.string.agent_marketplace_rollback_count, item.rollbackVersions.size))
    }
}.joinToString(" · ")

internal fun MainActivity.desktopMarketplaceLifecycleSummary(item: AgentDesktopMarketplaceItem): String = buildList {
    val version = if (item.installedVersion.isNotBlank() && item.installedVersion != item.availableVersion) {
        "${item.installedVersion} → ${item.availableVersion}"
    } else {
        item.availableVersion
    }
    add(getString(R.string.agent_marketplace_version, version))
    if (item.capabilities.isNotEmpty()) {
        add(getString(R.string.agent_marketplace_capability_count, item.capabilities.size))
    }
    if (item.permissionDiff.added.isNotEmpty()) {
        add(getString(R.string.agent_marketplace_new_permission_count, item.permissionDiff.added.size))
    }
    if (item.rollbackVersions.isNotEmpty()) {
        add(getString(R.string.agent_marketplace_rollback_count, item.rollbackVersions.size))
    }
}.joinToString(" · ")

internal fun MainActivity.showRemoteMcpSetupPage(entry: AgentMcpCatalogEntry? = null) {
    showFeaturePage(getString(R.string.agent_mcp_add_remote))
    setFeatureBackAction { returnToCapabilityLibrary(AgentCapabilityCatalogKind.MCP) }
    featureContent.addView(featureHeroCard(
        entry?.name ?: getString(R.string.agent_mcp_custom_server),
        entry?.let(::localizedMcpSummary) ?: getString(R.string.agent_mcp_custom_server_subtitle),
        R.drawable.ic_agent_skill,
        "#2979FF",
        getString(R.string.agent_mcp_remote_badge)
    ))
    val nameInput = capabilityTextInput(
        getString(R.string.agent_mcp_server_name),
        entry?.name.orEmpty(),
        getString(R.string.agent_mcp_server_name_hint)
    )
    val endpointInput = capabilityTextInput(
        getString(R.string.agent_mcp_server_url),
        entry?.defaultEndpoint.orEmpty(),
        "https://example.com/mcp"
    )
    val profiles = entry?.authProfiles ?: listOf(
        AgentMcpAuthProfile(AgentMcpAuthMethod.NONE),
        AgentMcpAuthProfile(AgentMcpAuthMethod.BEARER_TOKEN),
        AgentMcpAuthProfile(AgentMcpAuthMethod.API_KEY),
        AgentMcpAuthProfile(AgentMcpAuthMethod.USERNAME_PASSWORD),
        AgentMcpAuthProfile(AgentMcpAuthMethod.OAUTH2, supportsRefresh = true),
        AgentMcpAuthProfile(AgentMcpAuthMethod.DEVICE_CODE),
        AgentMcpAuthProfile(AgentMcpAuthMethod.DYNAMIC)
    )
    addCapabilityFormLabel(getString(R.string.agent_mcp_auth_method))
    val authSpinner = Spinner(this).apply {
        adapter = ArrayAdapter(
            this@showRemoteMcpSetupPage,
            android.R.layout.simple_spinner_dropdown_item,
            profiles.map { mcpAuthMethodLabel(it.method) }
        )
        background = getDrawable(R.drawable.glass_card_background)
        setPadding(dp(12), 0, dp(12), 0)
    }
    featureContent.addView(authSpinner, LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        dp(52)
    ).apply { bottomMargin = dp(14) })
    featureContent.addView(capabilityPrimaryButton(getString(R.string.agent_mcp_continue)) {
        runCatching {
            val profile = profiles[authSpinner.selectedItemPosition.coerceIn(profiles.indices)]
            agentMcpRegistry.addRemote(
                displayName = nameInput.text.toString(),
                endpoint = endpointInput.text.toString(),
                authProfile = profile,
                catalogId = entry?.id.orEmpty()
            )
        }.onSuccess { connection ->
            if (connection.authProfile.method == AgentMcpAuthMethod.NONE) {
                showMcpConnectionDetailPage(connection.id)
            } else {
                agentMcpRegistry.beginAuthentication(connection.id)
                showMcpAuthenticationPage(connection.id)
            }
        }.onFailure { error ->
            Toast.makeText(this@showRemoteMcpSetupPage, error.message ?: getString(R.string.agent_mcp_add_failed), Toast.LENGTH_LONG).show()
        }
    })
}

internal fun MainActivity.showMcpAuthenticationPage(connectionId: String) {
    val connection = agentMcpRegistry.get(connectionId) ?: return showCapabilityLibraryPage(AgentCapabilityCatalogKind.MCP)
    val step = connection.currentAuthStep ?: return showMcpConnectionDetailPage(connectionId)
    showFeaturePage(getString(R.string.agent_mcp_sign_in))
    setFeatureBackAction { showMcpConnectionDetailPage(connectionId) }
    featureContent.addView(featureHeroCard(
        connection.displayName,
        step.description.ifBlank { getString(R.string.agent_mcp_sign_in_subtitle) },
        R.drawable.ic_security_shield,
        "#2979FF",
        getString(R.string.agent_mcp_step_count, connection.authStepIndex + 1, connection.authProfile.steps.size)
    ))
    if (connection.authProfile.authorizationUrl.isNotBlank()) {
        featureContent.addView(featureRow(
            getString(R.string.agent_mcp_open_authorization),
            connection.authProfile.authorizationUrl,
            R.drawable.ic_protocol_link,
            getString(R.string.common_open)
        ).apply {
            setOnClickListener { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(connection.authProfile.authorizationUrl))) }
        })
    }
    val inputs = linkedMapOf<String, View>()
    step.fields.forEach { field ->
        addCapabilityFormLabel(field.label)
        val input: View = when (field.type) {
            AgentMcpAuthFieldType.SELECT -> Spinner(this).apply {
                adapter = ArrayAdapter(this@showMcpAuthenticationPage, android.R.layout.simple_spinner_dropdown_item, field.options)
                background = getDrawable(R.drawable.glass_card_background)
                setPadding(dp(12), 0, dp(12), 0)
            }
            AgentMcpAuthFieldType.CHECKBOX -> CheckBox(this).apply {
                text = field.placeholder.ifBlank { field.label }
                setTextColor(getColorCompat(R.color.text_primary))
            }
            else -> EditText(this).apply {
                hint = field.placeholder
                textSize = 15f
                setTextColor(getColorCompat(R.color.text_primary))
                setHintTextColor(getColorCompat(R.color.text_secondary))
                setSingleLine(true)
                setPadding(dp(14), 0, dp(14), 0)
                inputType = when (field.type) {
                    AgentMcpAuthFieldType.PASSWORD,
                    AgentMcpAuthFieldType.API_KEY -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                    AgentMcpAuthFieldType.PHONE -> InputType.TYPE_CLASS_PHONE
                    AgentMcpAuthFieldType.EMAIL -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
                    AgentMcpAuthFieldType.OTP,
                    AgentMcpAuthFieldType.TOTP -> InputType.TYPE_CLASS_NUMBER
                    AgentMcpAuthFieldType.URL -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
                    else -> InputType.TYPE_CLASS_TEXT
                }
                background = getDrawable(R.drawable.glass_card_background)
            }
        }
        inputs[field.id] = input
        featureContent.addView(input, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(52)
        ).apply { bottomMargin = dp(12) })
    }
    featureContent.addView(capabilityPrimaryButton(getString(R.string.agent_mcp_continue)) {
        val values = inputs.mapValues { (_, view) ->
            when (view) {
                is EditText -> view.text.toString()
                is Spinner -> view.selectedItem?.toString().orEmpty()
                is CheckBox -> view.isChecked.toString()
                else -> ""
            }
        }
        thread(name = "signalasi-mcp-auth") {
            val result = runCatching {
                runBlocking {
                    AgentMcpAuthenticationCoordinator(
                        agentMcpRegistry
                    ).submitStep(connectionId, values)
                }
            }
            runOnUiThread {
                result.onSuccess { updated ->
                    if (updated.authState == AgentMcpAuthState.AUTHENTICATED) showMcpConnectionDetailPage(connectionId)
                    else showMcpAuthenticationPage(connectionId)
                }.onFailure {
                    Toast.makeText(this@showMcpAuthenticationPage, it.message ?: getString(R.string.agent_mcp_auth_failed), Toast.LENGTH_LONG).show()
                }
            }
        }
    })
}

internal fun MainActivity.showMcpConnectionDetailPage(connectionId: String) {
    val connection = agentMcpRegistry.get(connectionId) ?: return showCapabilityLibraryPage(AgentCapabilityCatalogKind.MCP)
    val marketplaceItem = marketplaceItems().firstOrNull {
        it.kind == AgentCapabilityCatalogKind.MCP && it.id == connection.catalogId
    }
    showFeaturePage(connection.displayName)
    setFeatureBackAction { returnToCapabilityLibrary(AgentCapabilityCatalogKind.MCP) }
    featureContent.addView(featureHeroCard(
        connection.displayName,
        mcpConnectionSubtitle(connection),
        R.drawable.ic_agent_skill,
        if (connection.isCallable(System.currentTimeMillis())) "#14C66A" else "#F0A500",
        mcpConnectionStatus(connection)
    ))
    marketplaceItem?.let { item ->
        featureContent.addView(featureRow(
            getString(R.string.agent_marketplace_release),
            getString(
                R.string.agent_marketplace_release_detail,
                item.installedVersion.ifBlank { item.availableVersion },
                item.availableVersion
            ),
            R.drawable.ic_info_outline,
            if (item.updateAvailable) getString(R.string.agent_marketplace_update)
            else getString(R.string.agent_marketplace_current)
        ))
        featureContent.addView(featureRow(
            getString(R.string.agent_marketplace_capabilities_permissions),
            (item.capabilities + item.permissions.map { it.title }).joinToString("\n"),
            R.drawable.ic_security_shield,
            getString(
                R.string.agent_marketplace_capability_permission_count,
                item.capabilities.size,
                item.permissions.size
            )
        ))
    }
    if (connection.transport == AgentMcpTransportKind.LOCAL_STDIO) {
        val runtime = agentMcpPackageRepository.get(connection.id)?.localRuntime
        featureContent.addView(featureRow(
            getString(R.string.agent_mcp_runtime),
            runtime?.let { getString(R.string.agent_mcp_runtime_value, it.language.wireValue) }
                ?: getString(R.string.badge_unavailable),
            R.drawable.ic_local_model,
            getString(R.string.agent_mcp_local_package_badge)
        ))
    } else {
        featureContent.addView(featureRow(
            getString(R.string.agent_mcp_endpoint),
            connection.endpoint,
            R.drawable.ic_protocol_link,
            ""
        ))
    }
    featureContent.addView(featureRow(
        getString(R.string.agent_mcp_auth_method),
        mcpAuthMethodLabel(connection.authProfile.method),
        R.drawable.ic_security_shield,
        mcpAuthStateLabel(connection.effectiveAuthState(System.currentTimeMillis()))
    ).apply {
        setOnClickListener {
            if (connection.authProfile.method != AgentMcpAuthMethod.NONE) {
                agentMcpRegistry.beginAuthentication(connectionId)
                showMcpAuthenticationPage(connectionId)
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.agent_mcp_permission_policy),
        getString(R.string.agent_mcp_permission_policy_subtitle),
        R.drawable.ic_security_shield,
        mcpPermissionModeLabel(connection.permissionMode)
    ).apply {
        setOnClickListener { showMcpPermissionModeDialog(connectionId) }
    })
    featureContent.addView(featureRow(
        getString(R.string.agent_mcp_tools),
        connection.toolIds.joinToString(" · ").ifBlank { getString(R.string.agent_mcp_tools_not_discovered) },
        R.drawable.ic_agent_skill,
        connection.toolIds.size.toString()
    ))
    val audits = EncryptedAgentMcpAuditStore(this).list(connectionId, 20)
    addCapabilityFormLabel(getString(R.string.agent_mcp_recent_activity))
    if (audits.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.agent_mcp_no_activity),
            getString(R.string.agent_mcp_no_activity_subtitle),
            R.drawable.ic_info_outline,
            ""
        ))
    } else {
        audits.forEach { audit ->
            featureContent.addView(featureRow(
                audit.toolName,
                getString(
                    R.string.agent_mcp_audit_detail,
                    mcpRiskLabel(audit.risk),
                    mcpAuditStatusLabel(audit.status),
                    audit.source,
                    audit.permissions.joinToString(" · "),
                    AgentNativeJsonCodec.stringify(audit.parameterPreview)
                ),
                R.drawable.ic_protocol_link,
                getString(R.string.agent_mcp_audit_duration, audit.durationMillis)
            ))
        }
    }
    featureContent.addView(featureRow(
        getString(R.string.agent_mcp_test_connection),
        connection.lastError.ifBlank { getString(R.string.agent_mcp_test_connection_subtitle) },
        R.drawable.ic_info_outline,
        getString(R.string.common_test)
    ).apply { setOnClickListener { testMcpConnection(connectionId) } })
    featureContent.addView(featureRow(
        getString(
            if (connection.enabled) R.string.agent_marketplace_access_active
            else R.string.agent_marketplace_access_revoked
        ),
        getString(R.string.agent_marketplace_revoke_access_subtitle),
        R.drawable.ic_agent_control,
        getString(
            if (connection.enabled) R.string.agent_marketplace_revoke
            else R.string.agent_marketplace_restore_access
        )
    ).apply {
        setOnClickListener {
            agentMcpRegistry.setEnabled(connectionId, !connection.enabled)
            showMcpConnectionDetailPage(connectionId)
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.agent_mcp_remove),
        getString(R.string.agent_mcp_remove_subtitle),
        R.drawable.ic_delete,
        getString(R.string.common_delete)
    ).apply {
        setOnClickListener {
            AlertDialog.Builder(this@showMcpConnectionDetailPage)
                .setTitle(getString(R.string.agent_mcp_remove))
                .setMessage(connection.displayName)
                .setNegativeButton(getString(R.string.common_cancel), null)
                .setPositiveButton(getString(R.string.common_delete)) { _, _ ->
                    AgentMcpClientManager(this@showMcpConnectionDetailPage, agentMcpRegistry, agentMcpPackageRepository).close(connectionId)
                    agentMcpPackageRepository.delete(connectionId)
                    agentMcpRegistry.delete(connectionId)
                    EncryptedAgentMcpAuditStore(this@showMcpConnectionDetailPage).clear(connectionId)
                    showCapabilityLibraryPage(AgentCapabilityCatalogKind.MCP)
                }.show()
        }
    })
}

internal fun MainActivity.showMcpPermissionModeDialog(connectionId: String) {
    val connection = agentMcpRegistry.get(connectionId) ?: return
    val modes = arrayOf(
        AgentMcpPermissionMode.ASK_FOR_CHANGES,
        AgentMcpPermissionMode.READ_ONLY,
        AgentMcpPermissionMode.TRUSTED,
        AgentMcpPermissionMode.DISABLED
    )
    AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_mcp_permission_policy))
        .setSingleChoiceItems(
            modes.map(::mcpPermissionModeLabel).toTypedArray(),
            modes.indexOf(connection.permissionMode)
        ) { dialog, index ->
            agentMcpRegistry.setPermissionMode(connectionId, modes[index])
            dialog.dismiss()
            showMcpConnectionDetailPage(connectionId)
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.testMcpConnection(connectionId: String) {
    Toast.makeText(this, getString(R.string.agent_mcp_testing), Toast.LENGTH_SHORT).show()
    thread(name = "signalasi-mcp-test") {
        val result = runCatching {
            runBlocking { AgentMcpClientManager(this@testMcpConnection, agentMcpRegistry, agentMcpPackageRepository).listTools(connectionId) }
        }
        runOnUiThread {
            result.onSuccess {
                Toast.makeText(this, getString(R.string.agent_mcp_test_success, it.size), Toast.LENGTH_SHORT).show()
            }.onFailure {
                Toast.makeText(this, it.message ?: getString(R.string.agent_mcp_test_failed), Toast.LENGTH_LONG).show()
            }
            showMcpConnectionDetailPage(connectionId)
        }
    }
}

internal fun MainActivity.openMcpPackagePicker() {
    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = "application/zip"
        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/zip", "application/octet-stream", "application/vnd.signalasi.mcp"))
    }, REQUEST_IMPORT_MCP_PACKAGE)
}

internal fun MainActivity.importAgentMcpPackageFromUri(uri: Uri) {
    val inspection = runCatching {
        contentResolver.openInputStream(uri)?.use { AgentMcpPackageInstaller().inspect(it) }
            ?: error("Unable to open MCP package")
    }.getOrElse { error ->
        Toast.makeText(this, error.message ?: getString(R.string.agent_mcp_package_invalid), Toast.LENGTH_LONG).show()
        return
    }
    val manifest = inspection.manifest
    val details = buildString {
        append(manifest.description)
        if (manifest.transport == AgentMcpTransportKind.LOCAL_STDIO) {
            manifest.localRuntime?.let { runtime ->
                append("\n\n").append(getString(R.string.agent_mcp_runtime)).append(": ")
                append(getString(R.string.agent_mcp_runtime_value, runtime.language.wireValue))
            }
        } else {
            append("\n\n").append(getString(R.string.agent_mcp_tools)).append(":\n")
            manifest.tools.take(12).forEach { append("• ").append(it.title).append('\n') }
        }
        append("\n").append(getString(if (inspection.integrityVerified) R.string.agent_mcp_integrity_verified else R.string.agent_mcp_integrity_unsigned))
    }
    AlertDialog.Builder(this)
        .setTitle("${manifest.name} · v${manifest.version}")
        .setMessage(details.trim())
        .setNegativeButton(getString(R.string.common_cancel), null)
        .setPositiveButton(getString(R.string.agent_capability_install)) { _, _ ->
            runCatching {
                agentMcpPackageRepository.save(inspection)
                agentMcpRegistry.installPackage(manifest, inspection.packageSha256)
            }.onSuccess { connection ->
                if (connection.authProfile.method == AgentMcpAuthMethod.NONE) {
                    showMcpConnectionDetailPage(connection.id)
                } else {
                    agentMcpRegistry.beginAuthentication(connection.id)
                    showMcpAuthenticationPage(connection.id)
                }
            }.onFailure { error ->
                agentMcpPackageRepository.delete(manifest.id)
                Toast.makeText(this, error.message ?: getString(R.string.agent_mcp_install_failed), Toast.LENGTH_LONG).show()
            }
        }.show()
}

internal fun MainActivity.capabilityTextInput(label: String, value: String, hintValue: String): EditText {
    addCapabilityFormLabel(label)
    return EditText(this).apply {
        setText(value)
        hint = hintValue
        textSize = 15f
        setTextColor(getColorCompat(R.color.text_primary))
        setHintTextColor(getColorCompat(R.color.text_secondary))
        setSingleLine(true)
        setPadding(dp(14), 0, dp(14), 0)
        background = getDrawable(R.drawable.glass_card_background)
        featureContent.addView(this, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(52)
        ).apply { bottomMargin = dp(12) })
    }
}

internal fun MainActivity.addCapabilityFormLabel(label: String) {
    featureContent.addView(TextView(this).apply {
        text = label
        textSize = 12f
        setTextColor(getColorCompat(R.color.text_secondary))
        setPadding(dp(4), dp(3), 0, dp(6))
    })
}

internal fun MainActivity.capabilityPrimaryButton(label: String, action: () -> Unit): TextView = TextView(this).apply {
    text = label
    gravity = Gravity.CENTER
    textSize = 15f
    setTypeface(typeface, android.graphics.Typeface.BOLD)
    setTextColor(Color.WHITE)
    background = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = dp(10).toFloat()
        setColor(getColorCompat(R.color.signalasi_green))
    }
    setOnClickListener { action() }
    layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(50)).apply {
        topMargin = dp(5)
        bottomMargin = dp(14)
    }
}

internal fun MainActivity.mcpConnectionSubtitle(connection: AgentMcpConnection): String = listOf(
    if (connection.distribution == AgentMcpDistribution.LOCAL_PACKAGE) getString(R.string.agent_mcp_local_package_badge) else getString(R.string.agent_mcp_remote_badge),
    mcpAuthMethodLabel(connection.authProfile.method),
    connection.lastError.takeIf(String::isNotBlank)
).filterNotNull().joinToString(" · ")

internal fun MainActivity.mcpConnectionStatus(connection: AgentMcpConnection): String = when {
    !connection.enabled -> getString(R.string.status_disabled)
    connection.state == AgentMcpConnectionState.CONNECTED -> getString(R.string.status_connected)
    connection.effectiveAuthState(System.currentTimeMillis()) in setOf(
        AgentMcpAuthState.NOT_CONFIGURED,
        AgentMcpAuthState.CHALLENGE_REQUIRED,
        AgentMcpAuthState.REAUTHENTICATION_REQUIRED,
        AgentMcpAuthState.ERROR
    ) -> getString(R.string.agent_capability_requires_setup)
    connection.state == AgentMcpConnectionState.ERROR -> getString(R.string.agent_mcp_status_error)
    else -> getString(R.string.status_ready)
}

internal fun MainActivity.mcpAuthMethodLabel(method: AgentMcpAuthMethod): String = getString(when (method) {
    AgentMcpAuthMethod.NONE -> R.string.agent_mcp_auth_none
    AgentMcpAuthMethod.BEARER_TOKEN -> R.string.agent_mcp_auth_token
    AgentMcpAuthMethod.API_KEY -> R.string.agent_mcp_auth_api_key
    AgentMcpAuthMethod.USERNAME_PASSWORD -> R.string.agent_mcp_auth_password
    AgentMcpAuthMethod.OAUTH2 -> R.string.agent_mcp_auth_oauth
    AgentMcpAuthMethod.DEVICE_CODE -> R.string.agent_mcp_auth_device_code
    AgentMcpAuthMethod.DYNAMIC -> R.string.agent_mcp_auth_dynamic
})

internal fun MainActivity.mcpAuthStateLabel(state: AgentMcpAuthState): String = getString(when (state) {
    AgentMcpAuthState.NOT_REQUIRED -> R.string.agent_mcp_auth_not_required
    AgentMcpAuthState.AUTHENTICATED -> R.string.agent_mcp_auth_authenticated
    AgentMcpAuthState.REFRESHING -> R.string.agent_mcp_auth_refreshing
    AgentMcpAuthState.REAUTHENTICATION_REQUIRED -> R.string.agent_mcp_auth_reauth_required
    AgentMcpAuthState.ERROR -> R.string.agent_mcp_status_error
    else -> R.string.agent_capability_requires_setup
})

internal fun MainActivity.mcpPermissionModeLabel(mode: AgentMcpPermissionMode): String = getString(when (mode) {
    AgentMcpPermissionMode.ASK_FOR_CHANGES -> R.string.agent_mcp_permission_ask
    AgentMcpPermissionMode.READ_ONLY -> R.string.agent_mcp_permission_read_only
    AgentMcpPermissionMode.TRUSTED -> R.string.agent_mcp_permission_trusted
    AgentMcpPermissionMode.DISABLED -> R.string.status_disabled
})

internal fun MainActivity.mcpRiskLabel(risk: String): String = getString(when (risk) {
    AgentMcpToolRisk.LOW.wireValue -> R.string.agent_mcp_risk_low
    AgentMcpToolRisk.HIGH.wireValue -> R.string.agent_mcp_risk_high
    else -> R.string.agent_mcp_risk_medium
})

internal fun MainActivity.mcpAuditStatusLabel(status: String): String = getString(when (status) {
    "succeeded" -> R.string.agent_mcp_audit_succeeded
    "denied" -> R.string.agent_mcp_audit_denied
    else -> R.string.agent_mcp_audit_failed
})

internal fun MainActivity.localizedMcpSummary(entry: AgentMcpCatalogEntry): String = getString(when (entry.id) {
    "signalasi.mcp.github" -> R.string.agent_mcp_catalog_github
    "signalasi.mcp.notion" -> R.string.agent_mcp_catalog_notion
    "signalasi.mcp.home_assistant" -> R.string.agent_mcp_catalog_home_assistant
    "signalasi.mcp.relay_controller" -> R.string.agent_mcp_catalog_relay
    else -> R.string.agent_mcp_custom_server_subtitle
})

internal fun MainActivity.localizedSkillSummary(
    entry: AgentSkillCatalogEntry,
    dependency: AgentCapabilityDependencyStatus
): String {
    val summary = getString(when (entry.id) {
        "signalasi.catalog.deep-research" -> R.string.agent_skill_catalog_research
        "signalasi.catalog.device-health" -> R.string.agent_skill_catalog_device_health
        "signalasi.catalog.github-triage" -> R.string.agent_skill_catalog_github
        "signalasi.catalog.notion-brief" -> R.string.agent_skill_catalog_notion
        "signalasi.catalog.smart-home-routine" -> R.string.agent_skill_catalog_smart_home
        else -> R.string.agent_skills_subtitle
    })
    return if (dependency.available) summary else "$summary · ${getString(R.string.agent_skill_dependency_missing)}"
}

internal fun MainActivity.showAgentSkillDetailPage(id: String, version: String) {
    val installation = agentSkillRuntime.get(id, version)
        ?: return showCapabilityLibraryPage(AgentCapabilityCatalogKind.AUTOMATION)
    val manifest = installation.manifest
    showFeaturePage(manifest.title)
    setFeatureBackAction { returnToCapabilityLibrary(AgentCapabilityCatalogKind.AUTOMATION) }
    featureContent.addView(featureHeroCard(
        manifest.title,
        manifest.description.ifBlank { manifest.instructions.take(180) },
        R.drawable.ic_agent_node,
        "#14C66A",
        "v${manifest.version}"
    ))
    featureContent.addView(featureRow(
        getString(if (installation.enabled) R.string.agent_skill_enabled else R.string.agent_skill_disabled),
        manifest.source,
        R.drawable.ic_agent_control,
        getString(if (installation.enabled) R.string.common_disable else R.string.common_enable)
    ).apply {
        setOnClickListener {
            if (installation.enabled) agentSkillRuntime.disable(id, version) else agentSkillRuntime.enable(id, version)
            showAgentSkillDetailPage(id, version)
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.agent_skill_auto_invoke),
        manifest.triggerExamples.take(3).joinToString(" · "),
        R.drawable.ic_protocol_link,
        getString(if (installation.autoInvoke) R.string.status_enabled else R.string.status_disabled)
    ).apply {
        setOnClickListener {
            agentSkillRuntime.setAutoInvoke(id, version, !installation.autoInvoke)
            showAgentSkillDetailPage(id, version)
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.agent_skill_workflow),
        manifest.steps.joinToString(" → ") { it.toolId },
        R.drawable.ic_agent_history,
        manifest.steps.size.toString()
    ))
    featureContent.addView(featureRow(
        getString(R.string.agent_skill_permissions),
        (manifest.permissions + manifest.nativeTools).joinToString("\n"),
        R.drawable.ic_security_shield,
        manifest.permissions.size.toString()
    ))
    val versions = agentSkillRuntime.list().filter { it.id == id }.sortedByDescending { skillVersionParts(it.version) }
    featureContent.addView(featureRow(
        getString(R.string.agent_skill_versions),
        versions.joinToString(" · ") { "v${it.version}" },
        R.drawable.ic_agent_history,
        versions.size.toString()
    ).apply {
        setOnClickListener {
            val labels = versions.map { "v${it.version}${if (it.version == version) " · current" else ""}" }
            android.app.AlertDialog.Builder(this@showAgentSkillDetailPage)
                .setTitle(getString(R.string.agent_skill_versions))
                .setItems(labels.toTypedArray()) { _, index -> showAgentSkillDetailPage(id, versions[index].version) }
                .setNegativeButton(getString(R.string.common_cancel), null)
                .show()
        }
    })
    val previousVersion = versions.firstOrNull {
        skillVersionParts(it.version) < skillVersionParts(version)
    }
    if (previousVersion != null) {
        featureContent.addView(featureRow(
            getString(R.string.agent_marketplace_rollback),
            getString(
                R.string.agent_marketplace_rollback_detail,
                version,
                previousVersion.version
            ),
            R.drawable.ic_agent_history,
            getString(R.string.agent_marketplace_restore)
        ).apply {
            setOnClickListener {
                AlertDialog.Builder(this@showAgentSkillDetailPage)
                    .setTitle(R.string.agent_marketplace_rollback)
                    .setMessage(
                        getString(
                            R.string.agent_marketplace_rollback_confirm,
                            manifest.title,
                            previousVersion.version
                        )
                    )
                    .setNegativeButton(R.string.common_cancel, null)
                    .setPositiveButton(R.string.agent_marketplace_restore) { _, _ ->
                        runCatching {
                            AgentSkillVersionManager(agentSkillRuntime).rollback(id, version)
                        }.onSuccess { restored ->
                            showAgentSkillDetailPage(restored.id, restored.version)
                        }.onFailure { error ->
                            Toast.makeText(
                                this@showAgentSkillDetailPage,
                                error.message ?: getString(R.string.agent_marketplace_rollback_failed),
                                Toast.LENGTH_LONG
                            ).show()
                        }
                    }
                    .show()
            }
        })
    }
    featureContent.addView(featureRow(
        getString(R.string.agent_skill_run_test),
        getString(R.string.agent_skill_test_passed),
        R.drawable.ic_agent_screen,
        getString(R.string.common_view)
    ).apply {
        setOnClickListener {
            val result = agentSkillRuntime.validate(manifest)
            Toast.makeText(
                this@showAgentSkillDetailPage,
                if (result.isValid) getString(R.string.agent_skill_test_passed)
                else result.issues.joinToString("; ") { it.message },
                Toast.LENGTH_LONG
            ).show()
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.agent_skill_export),
        getString(R.string.agent_skill_export_subtitle),
        R.drawable.ic_export,
        getString(R.string.common_export)
    ).apply {
        setOnClickListener {
            pendingExportSkill = id to version
            val safeTitle = manifest.title.replace(Regex("[^a-zA-Z0-9._-]+"), "-")
                .trim('-').ifBlank { "signalasi-skill" }
            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/zip"
                putExtra(Intent.EXTRA_TITLE, "$safeTitle-v${manifest.version}.skill.zip")
            }, REQUEST_EXPORT_SKILL)
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.agent_skill_uninstall),
        "${manifest.title} v${manifest.version}",
        R.drawable.ic_delete,
        getString(R.string.common_delete)
    ).apply {
        setOnClickListener {
            android.app.AlertDialog.Builder(this@showAgentSkillDetailPage)
                .setTitle(getString(R.string.agent_skill_uninstall))
                .setMessage("${manifest.title} v${manifest.version}")
                .setNegativeButton(getString(R.string.common_cancel), null)
                .setPositiveButton(getString(R.string.common_delete)) { _, _ ->
                    agentSkillRuntime.delete(id, version)
                    showCapabilityLibraryPage(AgentCapabilityCatalogKind.AUTOMATION)
                }.show()
        }
    })
}

internal fun MainActivity.capabilityKindPayload(kind: AgentCapabilityCatalogKind): String =
    when (kind) {
        AgentCapabilityCatalogKind.NATIVE_TOOL -> CAPABILITY_KIND_NATIVE_TOOL
        AgentCapabilityCatalogKind.MCP -> CAPABILITY_KIND_MCP
        AgentCapabilityCatalogKind.AUTOMATION -> CAPABILITY_KIND_AUTOMATION
    }

internal fun MainActivity.marketplaceStateLabel(state: AgentMarketplaceInstallState): String = getString(
    when (state) {
        AgentMarketplaceInstallState.BUILT_IN -> R.string.agent_marketplace_built_in
        AgentMarketplaceInstallState.AVAILABLE -> R.string.agent_capability_install
        AgentMarketplaceInstallState.INSTALLED -> R.string.agent_capability_added
        AgentMarketplaceInstallState.NEEDS_SETUP -> R.string.agent_capability_requires_setup
        AgentMarketplaceInstallState.UNAVAILABLE -> R.string.cc_status_unavailable
    }
)

internal fun MainActivity.skillVersionParts(version: String): String = version.split('.')
    .joinToString(".") { (it.toIntOrNull() ?: 0).toString().padStart(8, '0') }

internal fun MainActivity.importAgentSkillFromUri(uri: Uri) {
    val bytes = runCatching {
        contentResolver.openInputStream(uri)?.use { input ->
            val output = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(16 * 1024)
            var total = 0
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                total += count
                require(total <= AgentSkillPackageInstaller.MAX_PACKAGE_BYTES) { "Skill package is too large" }
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        } ?: error("Unable to open Skill package")
    }.getOrElse { error ->
        Toast.makeText(this, error.message ?: getString(R.string.agent_skill_install_failed), Toast.LENGTH_LONG).show()
        return
    }
    val installer = AgentSkillPackageInstaller(agentSkillRuntime)
    val inspection = runCatching { installer.inspect(bytes.inputStream()) }.getOrElse { error ->
        Toast.makeText(this, error.message ?: getString(R.string.agent_skill_install_failed), Toast.LENGTH_LONG).show()
        return
    }
    val manifest = inspection.manifest
    val current = agentSkillRuntime.list()
        .filter { it.id == manifest.id }
        .maxByOrNull { skillVersionParts(it.version) }
    val currentPermissions = current?.manifest?.let {
        it.permissions + it.nativeTools
    }.orEmpty().toSet()
    val nextPermissions = (manifest.permissions + manifest.nativeTools).toSet()
    val addedPermissions = (nextPermissions - currentPermissions).sorted()
    val removedPermissions = (currentPermissions - nextPermissions).sorted()
    val details = buildString {
        append(manifest.description.ifBlank { manifest.instructions.take(220) })
        append("\n\n").append(getString(R.string.agent_skill_workflow)).append(":\n")
        manifest.nativeTools.forEach { append("• ").append(it).append('\n') }
        append('\n').append(getString(R.string.agent_skill_permissions)).append(":\n")
        if (manifest.permissions.isEmpty()) append("• None\n") else manifest.permissions.forEach { append("• ").append(it).append('\n') }
        if (current != null) {
            append('\n').append(getString(R.string.agent_marketplace_permission_changes)).append(":\n")
            if (addedPermissions.isEmpty() && removedPermissions.isEmpty()) {
                append("• ").append(getString(R.string.agent_marketplace_no_permission_changes)).append('\n')
            } else {
                addedPermissions.forEach { append("• + ").append(it).append('\n') }
                removedPermissions.forEach { append("• − ").append(it).append('\n') }
            }
        }
        append('\n').append(if (inspection.integrityVerified) getString(R.string.agent_skill_integrity_verified) else getString(R.string.agent_skill_integrity_unsigned))
    }
    android.app.AlertDialog.Builder(this)
        .setTitle("${manifest.title} · v${manifest.version}")
        .setMessage(details.trim())
        .setNegativeButton(getString(R.string.common_cancel), null)
        .setPositiveButton(getString(R.string.agent_skill_install)) { _, _ ->
            runCatching { installer.install(bytes.inputStream(), allowUnsignedLocalPackage = true) }
                .onSuccess { showAgentSkillDetailPage(it.id, it.version) }
                .onFailure { Toast.makeText(this, it.message ?: getString(R.string.agent_skill_install_failed), Toast.LENGTH_LONG).show() }
        }.show()
}

internal fun MainActivity.exportAgentSkillToUri(uri: Uri) {
    val target = pendingExportSkill
    pendingExportSkill = null
    val installation = target?.let { agentSkillRuntime.get(it.first, it.second) }
    if (installation == null) {
        Toast.makeText(this, getString(R.string.agent_skill_export_failed, "Skill not found"), Toast.LENGTH_LONG).show()
        return
    }
    runCatching {
        val archive = AgentSkillPackageExporter.export(installation.manifest)
        contentResolver.openOutputStream(uri, "w")?.use { it.write(archive) }
            ?: error("Unable to open export destination")
    }.onSuccess {
        Toast.makeText(this, getString(R.string.agent_skill_export_success), Toast.LENGTH_LONG).show()
    }.onFailure { error ->
        Toast.makeText(
            this,
            getString(R.string.agent_skill_export_failed, error.message ?: error.javaClass.simpleName),
            Toast.LENGTH_LONG
        ).show()
    }
}
