package com.galaxyssi.chat

import android.app.AlertDialog
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView

internal fun MainActivity.collaborationTranscriptRow(
    entry: AgentTranscriptEntry, metadata: CollaborationTranscriptMetadata, showStageInHeader: Boolean = true
): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    layoutParams = ViewGroup.LayoutParams(-1, -2)
    setPadding(0, dp(6), 0, dp(6))
    addView(collaborationMemberRow(CollaborationMember(id = metadata.memberId, name = metadata.name,
        agentId = metadata.memberId, providerLabel = metadata.provider,
        role = listOf(metadata.role, if (showStageInHeader) collaborationStageLabel(metadata.researchStage) else "")
            .filter(String::isNotBlank).joinToString(" · ")), compact = true,
        replyAtMillis = if (metadata.current) metadata.updatedAtMillis else CollaborationReplyTiming.replyAt(metadata, entry.timestampMillis)))
    if (metadata.result) addView(agentAssistantTranscriptRow(entry.copy(role = AgentTranscriptRole.ASSISTANT)),
        LinearLayout.LayoutParams(-1, -2))

    val stateKey = "collaboration:${metadata.traceTurnId}"
    val details = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        visibility = if (agentResponseSectionExpansion[stateKey] == true) View.VISIBLE else View.GONE
        addView(TextView(context).apply {
            text = metadata.details.ifBlank { if (metadata.result) "" else entry.text }
            textSize = 13f
            setTextColor(getColorCompat(R.color.text_secondary))
            setPadding(0, dp(4), 0, dp(8))
            setTextIsSelectable(true)
        })
        addView(agentResearchTraceRow(entry.copy(turnId = metadata.traceTurnId), if (metadata.result) entry.text else ""))
    }
    val status = LinearLayout(context).apply statusRow@ {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = dp(44)
        val statusLabel = collaborationCurrentMemberLabel(metadata)
        addView(TextView(context).apply {
            text = statusLabel
            textSize = 13f
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
            setTextColor(getColorCompat(R.color.text_secondary))
        }, if (metadata.result) LinearLayout.LayoutParams(-2, -2) else LinearLayout.LayoutParams(0, -2, 1f))
        val time = CollaborationTimeTextView(context).apply {
            tag = "collaboration-process-time"
            textSize = 13f
            maxLines = 1
            setTextColor(getColorCompat(R.color.text_secondary))
            compoundDrawablePadding = dp(8)
            bindTime(CollaborationReplyTiming.isTicking(metadata)) { now ->
                val value = CollaborationReplyTiming.elapsedMillis(metadata, entry.timestampMillis, now)?.let { elapsed ->
                    getString(R.string.collaboration_process_duration, agentProcessedDuration(elapsed))
                }.orEmpty()
                this@statusRow.contentDescription = "${metadata.name}: $statusLabel $value, " + getString(if (details.visibility == View.VISIBLE)
                    R.string.research_trace_collapse else R.string.research_trace_expand)
                value
            }
        }
        addView(time, LinearLayout.LayoutParams(-2, -2).apply { marginStart = dp(8) })
        fun updateIcon(expanded: Boolean) {
            val chevron = getDrawable(R.drawable.ic_chevron_down)?.mutate()?.apply {
                setBounds(0, 0, dp(18), dp(18))
                setTint(getColorCompat(R.color.text_secondary))
            }
            time.setCompoundDrawablesRelative(null, null, chevron, null)
            contentDescription = "${metadata.name}: $statusLabel ${time.text}, " + getString(if (expanded)
                R.string.research_trace_collapse else R.string.research_trace_expand)
        }
        updateIcon(details.visibility == View.VISIBLE)
        setOnClickListener {
            val expanded = details.visibility != View.VISIBLE
            agentResponseSectionExpansion[stateKey] = expanded
            details.visibility = if (expanded) View.VISIBLE else View.GONE
            updateIcon(expanded)
        }
        setOnLongClickListener {
            agentRoutingExecutor.execute {
                val snapshot = globalSuperAgentRuntime.agentTeamSnapshot(metadata.runId)
                val actionable = snapshot != null && (!snapshot.state.isTerminal || snapshot.paused ||
                    snapshot.state == AgentTeamExecutionState.INTERRUPTED)
                val choices = buildList {
                    add(R.string.collaboration_view_process)
                    if (actionable) {
                        add(if (snapshot?.paused == true || snapshot?.goalDisposition == "blocked") R.string.collaboration_resume_team else R.string.collaboration_pause_team)
                        add(R.string.collaboration_stop_team)
                    }
                }
                runOnUiThread {
                    if (isFinishing || isDestroyed) return@runOnUiThread
                    AlertDialog.Builder(this@collaborationTranscriptRow)
                        .setItems(choices.map { getString(it) }.toTypedArray()) { _, index ->
                            agentRoutingExecutor.execute {
                                when (choices[index]) {
                                    R.string.collaboration_pause_team -> globalSuperAgentRuntime.pauseAgentTeam(metadata.runId)
                                    R.string.collaboration_resume_team -> globalSuperAgentRuntime.resumeAgentTeam(metadata.runId)
                                    R.string.collaboration_stop_team -> globalSuperAgentRuntime.cancelAgentTeam(metadata.runId)
                                    else -> runOnUiThread { if (!isFinishing && !isDestroyed && snapshot != null) showAgentTeamDetails(snapshot) }
                                }
                            }
                        }.show()
                }
            }
            true
        }
    }
    addView(status)
    addView(details)
}

internal fun android.content.Context.collaborationCurrentMemberLabel(metadata: CollaborationTranscriptMetadata): String = when {
    metadata.result -> getString(R.string.collaboration_view_process)
    metadata.status == AgentSubagentStatus.SUCCEEDED -> getString(R.string.agent_team_state_succeeded)
    metadata.status == AgentSubagentStatus.CANCELLED -> getString(R.string.collaboration_cancelled)
    metadata.paused -> getString(R.string.collaboration_team_paused)
    metadata.goalDisposition == "blocked" -> getString(R.string.collaboration_goal_blocked)
    metadata.status == AgentSubagentStatus.QUEUED && metadata.dependencies.isNotBlank() ->
        getString(R.string.collaboration_waiting_members, metadata.dependencies)
    metadata.status == AgentSubagentStatus.QUEUED -> getString(if (metadata.waiting)
        R.string.collaboration_waiting_dependencies else R.string.collaboration_queued)
    metadata.status == AgentSubagentStatus.FAILED -> getString(R.string.collaboration_failed_status)
    metadata.status == AgentSubagentStatus.SKIPPED -> getString(R.string.collaboration_skipped)
    metadata.connectionState == "waiting" -> getString(R.string.collaboration_connection_lost)
    metadata.connectionState == "reconciling" -> getString(R.string.collaboration_connection_reconciling)
    metadata.connectionState == "evidence_sync" -> metadata.summary.ifBlank { getString(R.string.collaboration_evidence_transfer) }
    metadata.connectionState == "delivering" -> getString(R.string.conversation_status_delivering)
    metadata.connectionState == "remote_paused" -> getString(R.string.collaboration_team_paused)
    metadata.connectionState == "remote_queued" -> getString(R.string.collaboration_queued)
    metadata.summary.isNotBlank() -> metadata.summary.lineSequence().first().take(180)
    metadata.primary -> getString(R.string.collaboration_synthesizing)
    else -> getString(R.string.collaboration_running)
}

internal fun MainActivity.collaborationStageLabel(stage: String): String = when (stage) {
    "BRIEF" -> R.string.collaboration_stage_brief
    "EXPLORE" -> R.string.collaboration_stage_explore
    "CHALLENGE" -> R.string.collaboration_stage_challenge
    "REVISE" -> R.string.collaboration_stage_revise
    "COMBINE" -> R.string.collaboration_stage_combine
    "VERIFY" -> R.string.collaboration_stage_verify
    "EXECUTE" -> R.string.collaboration_stage_execute
    "REPAIR" -> R.string.collaboration_stage_repair
    "RECHECK" -> R.string.collaboration_stage_recheck
    "DELIVER" -> R.string.collaboration_stage_deliver
    else -> null
}?.let(::getString) ?: stage
