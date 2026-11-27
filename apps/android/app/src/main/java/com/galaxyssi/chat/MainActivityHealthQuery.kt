package com.galaxyssi.chat

import android.content.Intent
import android.view.inputmethod.InputMethodManager
import android.view.View
import java.util.UUID

private fun labMode(entry: AgentTranscriptEntry): HealthAgentLabIntent? {
    if (entry.sourceConversationId.isNotBlank() || entry.role != AgentTranscriptRole.ASSISTANT ||
        !entry.dedupeKey.startsWith(HealthAgentLab.marker) || !HealthProfilePolicy.uuid(entry.turnId)) return null
    return HealthAgentLabIntent.entries.firstOrNull { entry.dedupeKey == "${HealthAgentLab.marker}${it.name}:${entry.turnId}" }
}

private fun MainActivity.openLocalLabs(chat: String, mode: HealthAgentLabIntent, anchor: Long, supplement: String = "") {
    if (isFinishing || isDestroyed || agentTranscriptStore.activeConversation().id != chat) return
    startActivity(Intent(this, HealthAgentLabActivity::class.java).putExtra("chat", chat).putExtra("mode", mode.name)
        .putExtra("anchor", anchor).putExtra("supplement", supplement))
}

internal fun MainActivity.localHealthAnswerLink(entry: AgentTranscriptEntry): View? {
    val mode = labMode(entry) ?: return null
    return HealthCenterViews(this).command(R.string.health_agent_open_results) {
        openLocalLabs(entry.conversationId, mode, entry.timestampMillis)
    }
}

internal fun MainActivity.offerPrivateLabQuery(chat: String, goal: String): Boolean {
    if (HealthAgentLab.intent(goal, false) == null) return false
    android.app.AlertDialog.Builder(this).setMessage(R.string.health_agent_group_notice)
        .setNegativeButton(android.R.string.cancel, null)
        .setPositiveButton(R.string.health_agent_open_private) { _, _ ->
            if (agentTranscriptStore.activeConversation().id == chat && agentGoalInput.text.toString().trim() == goal) {
                createAgentConversation()
                submitLocalHealthQuery(agentTranscriptStore.activeConversation().id, goal)
            }
        }.show()
    return true
}

internal fun MainActivity.submitLocalHealthQuery(chat: String, goal: String): Boolean {
    val last = agentTranscriptWindow.takeIf { it.conversationId == chat }?.entries?.lastOrNull { it.role != AgentTranscriptRole.PROCESS }
    val previous = last?.let(::labMode)
    val mode = HealthAgentLab.intent(goal, previous != null) ?: return false
    val follow = mode in setOf(HealthAgentLabIntent.NOTE, HealthAgentLabIntent.REMIND)
    val anchor = if (follow && last != null) last.timestampMillis else System.currentTimeMillis()
    agentGoalInput.setText("")
    agentGoalInput.clearFocus()
    getSystemService(InputMethodManager::class.java)?.hideSoftInputFromWindow(agentGoalInput.windowToken, 0)
    if (!follow) {
        val turn = UUID.randomUUID().toString()
        val label = getString(if (mode == HealthAgentLabIntent.ABNORMAL) R.string.health_agent_question else R.string.health_agent_question_all)
        val answer = getString(R.string.health_agent_open_results)
        // Only a navigation link enters history. Measurement values, notes and source IDs never enter a provider prompt.
        agentSubmissionExecutor.execute {
            agentTranscriptStore.append(AgentTranscriptRole.USER, label, timestampMillis = anchor, conversationId = chat, turnId = turn)
            agentTranscriptStore.append(AgentTranscriptRole.ASSISTANT, answer, "${HealthAgentLab.marker}${mode.name}:$turn",
                timestampMillis = anchor + 1, conversationId = chat, turnId = turn)
            runOnUiThread { if (!isDestroyed && agentTranscriptStore.activeConversation().id == chat) refreshAgentTranscriptWindow(chat) }
        }
    }
    openLocalLabs(chat, mode, anchor, if (follow) goal else "")
    return true
}
