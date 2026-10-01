package com.galaxyssi.chat

import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import android.app.AlertDialog

internal fun MainActivity.collaborationTranscriptRow(
    entry: AgentTranscriptEntry, metadata: CollaborationTranscriptMetadata
): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
    setPadding(0, dp(10), 0, dp(6))
    addView(collaborationMemberRow(CollaborationMember(id = metadata.memberId, name = metadata.name,
        agentId = metadata.memberId, providerLabel = metadata.provider, role = metadata.role)))
    if (metadata.result) {
        addView(agentAssistantTranscriptRow(entry.copy(role = AgentTranscriptRole.ASSISTANT)), LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { marginStart = dp(44) })
    } else {
        val stateKey = "collaboration:${entry.dedupeKey}"
        val details = TextView(context).apply {
            text = entry.text
            textSize = 13f
            setTextColor(getColorCompat(R.color.text_secondary))
            setPadding(dp(44), dp(4), dp(12), dp(8))
            visibility = if (agentResponseSectionExpansion[stateKey] == true) View.VISIBLE else View.GONE
        }
        val status = TextView(context).apply {
            textSize = 13f
            gravity = Gravity.CENTER_VERTICAL
            minHeight = dp(44)
            setPadding(dp(44), 0, dp(12), 0)
            setTextColor(getColorCompat(R.color.text_secondary))
            val label = when (metadata.status) {
                AgentSubagentStatus.QUEUED -> if (metadata.waiting) R.string.collaboration_waiting_dependencies
                    else R.string.collaboration_queued
                AgentSubagentStatus.RUNNING -> R.string.collaboration_running
                AgentSubagentStatus.SUCCEEDED -> R.string.collaboration_completed
                AgentSubagentStatus.FAILED -> R.string.collaboration_failed_status
                AgentSubagentStatus.CANCELLED -> R.string.collaboration_cancelled
                AgentSubagentStatus.SKIPPED -> R.string.collaboration_skipped
            }
            text = getString(label)
            fun updateIcons(expanded: Boolean) {
                val icon = getDrawable(when (metadata.status) {
                    AgentSubagentStatus.SUCCEEDED -> R.drawable.ic_agent_progress_complete
                    AgentSubagentStatus.FAILED, AgentSubagentStatus.CANCELLED -> R.drawable.ic_agent_progress_close
                    else -> R.drawable.ic_agent_plan_progress
                })?.mutate()?.apply {
                    setBounds(0, 0, dp(18), dp(18))
                    setTint(getColorCompat(if (metadata.status in setOf(AgentSubagentStatus.RUNNING, AgentSubagentStatus.SUCCEEDED))
                        R.color.composer_send_icon else R.color.text_secondary))
                }
                val chevron = getDrawable(if (expanded) android.R.drawable.arrow_up_float else R.drawable.ic_chevron_down)
                    ?.apply { setBounds(0, 0, dp(18), dp(18)) }
                compoundDrawablePadding = dp(8)
                setCompoundDrawablesRelative(icon, null, chevron, null)
            }
            updateIcons(details.visibility == View.VISIBLE)
            setOnClickListener {
                val expanded = details.visibility != View.VISIBLE
                agentResponseSectionExpansion[stateKey] = expanded
                details.visibility = if (expanded) View.VISIBLE else View.GONE
                updateIcons(expanded)
            }
            setOnLongClickListener {
                val choices = if (metadata.status.isTerminal) listOf(R.string.collaboration_view_process)
                    else listOf(R.string.collaboration_view_process, R.string.collaboration_stop_team)
                AlertDialog.Builder(this@collaborationTranscriptRow)
                    .setItems(choices.map { getString(it) }.toTypedArray()) { _, index ->
                        agentRoutingExecutor.execute {
                            if (index == 0) {
                                val snapshot = globalSuperAgentRuntime.agentTeamSnapshot(metadata.runId)
                                runOnUiThread { if (!isFinishing && !isDestroyed && snapshot != null) showAgentTeamDetails(snapshot) }
                            } else globalSuperAgentRuntime.cancelAgentTeam(metadata.runId)
                        }
                    }.show()
                true
            }
        }
        addView(status)
        addView(details)
    }
}
