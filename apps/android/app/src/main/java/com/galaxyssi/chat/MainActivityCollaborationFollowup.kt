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
            val active = globalSuperAgentRuntime.agentTeamSnapshots().filter { snapshot ->
                snapshot.conversationId == conversationId && (!snapshot.state.isTerminal || snapshot.paused ||
                    snapshot.state == AgentTeamExecutionState.INTERRUPTED) &&
                    snapshot.members.any { it.collaborationGroupId == conversationId }
            }.maxWithOrNull(compareBy<AgentTeamExecutionSnapshot> {
                it.members.any { member -> member.researchStage.isNotBlank() }
            }.thenBy { it.createdAtMillis }) ?: return@runCatching null
            when (AgentTeamControlIntent.parse(goal)) {
                AgentTeamUserControl.PAUSE -> {
                    globalSuperAgentRuntime.pauseAgentTeam(active.supervisorRunId)
                    return@runCatching getString(R.string.collaboration_team_paused)
                }
                AgentTeamUserControl.STOP -> {
                    globalSuperAgentRuntime.cancelAgentTeam(active.supervisorRunId)
                    return@runCatching getString(R.string.collaboration_cancelled)
                }
                AgentTeamUserControl.RUN -> if (active.paused || active.goalDisposition == "blocked") {
                    globalSuperAgentRuntime.resumeAgentTeam(active.supervisorRunId)
                    return@runCatching getString(R.string.collaboration_team_resumed)
                }
                null -> Unit
            }
            val group = requireNotNull(CollaborationGroupStore(this).load(conversationId))
            val respondents = CollaborationFollowupPolicy.respondents(group, goal, AgentTurnMentionRegistry.peek(turnId))
            val selected = respondents.mapTo(hashSetOf()) { it.instanceId }
            val recipients = active.members.filter {
                (it.memberId in selected || it.personId in selected) && it.canReceiveTeamMessage(active.state)
            }.groupBy { it.personId }.values.map { stages ->
                stages.firstOrNull { it.status == AgentSubagentStatus.RUNNING } ?: stages.first()
            }.ifEmpty { if (active.goalDisposition in setOf("continue", "blocked"))
                active.members.filter { it.memberId == active.primaryMemberId } else emptyList() }
            runBlocking {
                recipients.forEach { recipient ->
                    if (cancelled()) return@forEach
                    globalSuperAgentRuntime.sendAgentTeamMessage(active.supervisorRunId, recipient.memberId, goal)
                }
            }
            if (active.goalDisposition == "blocked" && recipients.isNotEmpty())
                globalSuperAgentRuntime.resumeAgentTeam(active.supervisorRunId)
            if (cancelled()) return@execute
            val base = agentContextBeforeTurn[turnId]
                ?: agentTranscriptStore.context(conversationId, excludeTurnId = turnId)
            agentContextBeforeTurn[turnId] = CollaborationFollowupPolicy.context(base, active)
            AgentTurnMentionRegistry.put(turnId, respondents)
            null
        }
        val receipt = outcome.getOrElse { it.message?.takeIf(String::isNotBlank)
            ?: getString(R.string.collaboration_update_failed) }
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
