package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking

internal fun MainActivity.routeCollaborationFollowup(
    conversationId: String,
    turnId: String,
    goal: String,
    cancelled: () -> Boolean,
    continueNewTask: () -> Unit
) {
    agentRoutingExecutor.execute {
        if (cancelled()) return@execute
        val outcome = runCatching {
            val active = globalSuperAgentRuntime.agentTeamSnapshots().firstOrNull { snapshot ->
                snapshot.conversationId == conversationId && !snapshot.state.isTerminal &&
                    snapshot.members.any { it.collaborationGroupId == conversationId }
            } ?: return@runCatching null
            val selected = AgentTurnMentionRegistry.peek(turnId).mapTo(hashSetOf()) { it.instanceId }
            val recipients = active.members.filter {
                (it.memberId in selected || it.personId in selected) && it.canReceiveTeamMessage(active.state)
            }.groupBy { it.personId }.values.map { stages ->
                stages.firstOrNull { it.status == AgentSubagentStatus.RUNNING } ?: stages.first()
            }
            var delivered = 0
            var queued = 0
            runBlocking {
                recipients.forEach { recipient ->
                    if (cancelled()) return@forEach
                    val result = globalSuperAgentRuntime.sendAgentTeamMessage(active.supervisorRunId, recipient.memberId, goal)
                    if (result.state == AgentTeamMessageState.PENDING) queued++ else delivered++
                }
            }
            if (recipients.isEmpty()) getString(R.string.collaboration_member_finished)
            else getString(R.string.collaboration_update_receipt, delivered, queued)
        }
        val receipt = outcome.getOrElse { getString(R.string.collaboration_update_failed) }
        if (receipt == null) {
            runOnUiThread { if (!isFinishing && !isDestroyed && !cancelled()) continueNewTask() }
            return@execute
        }
        agentTranscriptStore.append(AgentTranscriptRole.ASSISTANT, receipt,
            dedupeKey = "collaboration-update:$turnId", conversationId = conversationId, turnId = turnId, taskId = turnId)
        AgentTurnMentionRegistry.remove(turnId)
        AgentTurnAttachmentRegistry.remove(turnId)
        runOnUiThread {
            pendingAgentReplyIndicators.remove(turnId)
            if (!isFinishing && !isDestroyed) refreshAgentTranscriptWindow(conversationId)
        }
    }
}
