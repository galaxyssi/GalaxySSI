package com.galaxyssi.chat

/** Rebuild missing receive intents from dispatched journal nodes, never from provider/name guesses. */
internal object AgentTeamReplyRecovery {
    fun awaitsResult(team: AgentTeamExecutionSnapshot, checkpoint: AgentTeamExecutionCheckpoint,
        record: AgentManagedResponseRecord, control: AgentTeamUserControl): Boolean {
        if (control != AgentTeamUserControl.RUN || team.paused || team.state != AgentTeamExecutionState.INTERRUPTED ||
            record.state != AgentManagedResponseState.PENDING) return false
        val execution = CollaborationLateResult.execution(checkpoint, record) ?: return false
        return checkpoint.request.runId == team.supervisorRunId && checkpoint.request.taskId == team.taskId &&
            record.turnId == checkpoint.request.messageId && record.sourceMessageId ==
            AgentTeamDispatchIds.sourceMessageId("member:${execution.request.idempotencyKey}") &&
            team.members.any { it.memberId == execution.member.memberId && it.status == AgentSubagentStatus.RUNNING }
    }

    fun awaitsResult(context: android.content.Context, delivery: AgentPendingDelivery): Boolean {
        val record = EncryptedAgentManagedResponseLedger(context).pendingOwner(delivery) ?: return false
        val store = EncryptedAgentTeamExecutionStore(context)
        val team = store.snapshot(record.supervisorRunId) ?: return false
        val checkpoint = store.deliveryCheckpoint(record.supervisorRunId) ?: return false
        return awaitsResult(team, checkpoint, record, AgentTeamDurableControl(context).get(record.supervisorRunId))
    }

    fun restore(team: AgentTeamExecutionSnapshot, checkpoint: AgentTeamExecutionCheckpoint,
        ledger: AgentManagedResponseLedger, control: AgentTeamUserControl,
        wasNotDispatched: (String) -> Boolean,
        binding: (AgentTeamMember, Long) -> AgentPendingDelivery?): Int {
        if (control != AgentTeamUserControl.RUN || team.paused || team.state != AgentTeamExecutionState.INTERRUPTED ||
            checkpoint.request.runId != team.supervisorRunId || checkpoint.request.conversationId != team.conversationId ||
            checkpoint.request.taskId != team.taskId) return 0
        return team.members.count { node ->
            if (node.status != AgentSubagentStatus.RUNNING || node.deliveryMode == AgentDeliveryMode.IGNORE) return@count false
            val owner = stableAgentTeamMemberRunId(team.supervisorRunId, node.memberId)
            if (wasNotDispatched(owner) || ledger.findOwner(owner) != null) return@count false
            val member = checkpoint.definition.members.singleOrNull { it.memberId == node.memberId && it.agentId == node.agentId }
                ?: return@count false
            val source = AgentTeamDispatchIds.sourceMessageId("member:${checkpoint.request.idempotencyKey}:${node.memberId}")
            val wire = binding(member, source) ?: return@count false
            if (wire.sourceMessageId != source || wire.contactId.isBlank() || wire.taskId.isBlank() ||
                wire.conversationId != checkpoint.request.conversationId || wire.turnId != checkpoint.request.messageId ||
                wire.recoverySuccessorSourceMessageId > 0) return@count false
            ledger.register(AgentManagedResponseRecord(owner, team.supervisorRunId, member.agentId, member.deliveryMode,
                source, wire.contactId, wire.conversationId, wire.turnId, wire.taskId,
                createdAtMillis = node.executionStartedAtMillis.takeIf { it > 0 } ?: team.createdAtMillis))
            true
        }
    }
}
