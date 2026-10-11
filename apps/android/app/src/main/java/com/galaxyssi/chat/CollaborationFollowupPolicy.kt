package com.galaxyssi.chat

/** Follow-up turns have their own response lifecycle; a mailbox receipt is not an answer. */
internal object CollaborationFollowupPolicy {
    fun respondents(group: CollaborationGroup, goal: String,
                    requested: List<AgentRequestedMember>): List<AgentRequestedMember> {
        val mentioned = CollaborationMentionPolicy.resolve(goal, group.members).map { it.id }.toSet()
        val requestedIds = requested.map { it.instanceId }.toSet()
        val defaultIds = group.requested(emptyList()).map { it.instanceId }.toSet()
        val selected = when {
            mentioned.isNotEmpty() -> mentioned
            requestedIds.isNotEmpty() && requestedIds != defaultIds -> requestedIds
            else -> setOf(group.coordinatorId)
        }
        return group.members.filter { it.id in selected }.map {
            it.requested(group.conversationId).copy(collaborationWorkflow = CollaborationWorkflow.PARALLEL.name)
        }.also { require(it.isNotEmpty()) { "No current collaboration member can answer this turn" } }
    }

    fun context(base: AgentConversationContext, active: AgentTeamExecutionSnapshot): AgentConversationContext {
        require(base.conversationId == active.conversationId)
        return base.copy(summary = listOf(base.summary, buildString {
            appendLine("This is a separate follow-up turn in the same collaboration group.")
            appendLine("Answer the latest user request now using this group's history and saved results.")
            appendLine("The original goal continues independently; do not wait for it or repeat its side effects.")
            appendLine("Distinguish observed results from proposals and unavailable evidence.")
            appendLine("Background run: ${active.supervisorRunId}; state: ${active.state}; paused: ${active.paused}.")
            appendLine("Original goal: ${active.goal.take(4000)}")
            active.members.filter { it.collaborationGroupId == base.conversationId && it.output.isNotBlank() }
                .distinctBy { it.personId }.take(12).forEach {
                    appendLine("${it.displayName} / ${it.status}: ${it.output.take(2000)}")
                }
        }).filter(String::isNotBlank).joinToString("\n\n"))
    }
}
