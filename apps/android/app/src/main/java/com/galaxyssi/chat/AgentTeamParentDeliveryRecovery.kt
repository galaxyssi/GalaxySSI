package com.galaxyssi.chat

import android.content.Context

internal object AgentTeamParentDeliveryPolicy {
    fun isLocalTeam(contactId: String): Boolean = contactId.startsWith("agent-team:")

    fun matches(team: AgentTeamExecutionSnapshot, delivery: AgentPendingDelivery): Boolean =
        delivery.sourceMessageId == AgentTeamDispatchIds.sourceMessageId(team.supervisorRunId) &&
            delivery.contactId == AgentTeamDispatchIds.responseContactId(team.teamId) &&
            delivery.conversationId == team.conversationId && delivery.turnId == team.taskId &&
            delivery.taskId == team.taskId

    fun mayRepair(team: AgentTeamExecutionSnapshot, workspace: AgentWorkspace,
        terminal: AgentTerminalDelivery, knownSilenceReason: Boolean): Boolean =
        knownSilenceReason && team.state != AgentTeamExecutionState.CANCELLED &&
            !workspace.cancellationRequested && workspace.status in setOf(AgentWorkspaceStatus.FAILED, AgentWorkspaceStatus.WAITING_RESPONSE) &&
            workspace.workspaceId == team.taskId && workspace.conversationId == team.conversationId &&
            workspace.errorMessage == terminal.reason && terminal.terminalAtMillis >= team.createdAtMillis &&
            matches(team, AgentPendingDelivery(terminal.sourceMessageId, terminal.conversationId,
                terminal.turnId, terminal.taskId, terminal.contactId))
}

/** Repairs only the old remote-silence misclassification of an exact, journal-owned team parent. */
internal class AgentTeamParentDeliveryRecovery(private val context: Context) {
    fun stop(team: AgentTeamExecutionSnapshot) {
        val store = EncryptedAgentWorkspaceStore(context)
        val workspace = store.find(team.taskId) ?: return
        if (workspace.conversationId != team.conversationId || workspace.status.isTerminal) return
        store.upsert(workspace.copy(status = AgentWorkspaceStatus.CANCELLED, cancellationRequested = true),
            expectedRevision = workspace.revision)
        val delivery = AgentPendingDelivery(AgentTeamDispatchIds.sourceMessageId(team.supervisorRunId),
            team.conversationId, team.taskId, team.taskId, AgentTeamDispatchIds.responseContactId(team.teamId))
        AgentTerminalDeliveryStore.mark(context, delivery, context.getString(R.string.collaboration_cancelled))
        AgentPendingDeliveryStore.remove(context, delivery.sourceMessageId)
    }

    fun canResume(team: AgentTeamExecutionSnapshot): Boolean {
        val workspace = EncryptedAgentWorkspaceStore(context).find(team.taskId) ?: return false
        if (workspace.conversationId != team.conversationId || workspace.cancellationRequested ||
            workspace.status == AgentWorkspaceStatus.CANCELLED) return false
        if (workspace.status == AgentWorkspaceStatus.FAILED) return prepare(team)
        val session = SharedPreferencesAgentSessionStore(context, "task:${team.taskId}").load() ?: return false
        val metadata = session.lastActionResult?.metadata.orEmpty()
        if (metadata["team_run_id"] != team.supervisorRunId) return false
        return session.phase == AgentPhase.WAITING_RESPONSE || AgentTeamParentRecoveryPolicy.acceptsLateResult(
            session.phase, metadata, AgentTeamDispatchIds.sourceMessageId(team.supervisorRunId))
    }

    fun prepare(team: AgentTeamExecutionSnapshot): Boolean {
        val source = AgentTeamDispatchIds.sourceMessageId(team.supervisorRunId)
        val contact = AgentTeamDispatchIds.responseContactId(team.teamId)
        val terminal = AgentTerminalDeliveryStore.find(context, source) ?: return true
        val transcript = AgentTranscriptStore(context)
        if (transcript.conversation(team.conversationId) == null) return false
        val workspaceStore = EncryptedAgentWorkspaceStore(context)
        val workspace = workspaceStore.find(team.taskId) ?: return false
        if (workspace.cancellationRequested || workspace.status in setOf(AgentWorkspaceStatus.CANCELLED,
                AgentWorkspaceStatus.PAUSED)) return false
        val languages = listOf("en", "zh-CN").map { tag ->
            val configuration = android.content.res.Configuration(context.resources.configuration)
            configuration.setLocale(java.util.Locale.forLanguageTag(tag))
            context.createConfigurationContext(configuration).getString(R.string.agent_desktop_status_unavailable)
        }
        if (!AgentTeamParentDeliveryPolicy.mayRepair(team, workspace, terminal, terminal.reason in languages)) return false
        val session = SharedPreferencesAgentSessionStore(context, "task:${team.taskId}").load() ?: return false
        val metadata = session.lastActionResult?.metadata.orEmpty()
        if (metadata["team_run_id"] != team.supervisorRunId || metadata["resource_location"] != "distributed" ||
            metadata["source_message_id"]?.toLongOrNull() != source || metadata["contact_id"] != contact ||
            session.phase != AgentPhase.WAITING_RESPONSE) return false
        val delivery = AgentPendingDelivery(source, team.conversationId, team.taskId, team.taskId, contact)
        if (!AgentPendingDeliveryStore.restoreTeamParent(context, delivery)) return false
        // CAS prevents a concurrently issued user stop from being overwritten.
        try {
            workspaceStore.upsert(workspace.copy(status = AgentWorkspaceStatus.WAITING_RESPONSE),
                expectedRevision = workspace.revision)
        } catch (_: AgentWorkspaceRevisionConflictException) { return false }
        if (!AgentTerminalDeliveryStore.removeExact(context, terminal)) return false
        workspaceStore.find(team.taskId)?.takeIf { it.status == AgentWorkspaceStatus.WAITING_RESPONSE &&
            !it.cancellationRequested && it.errorMessage == terminal.reason }?.let { updated ->
            try { workspaceStore.upsert(updated.copy(errorMessage = ""), expectedRevision = updated.revision) }
            catch (_: AgentWorkspaceRevisionConflictException) { /* A newer task state owns the row. */ }
        }
        transcript.deleteByDedupeKey(team.conversationId, AgentDeliveryFailureRecorder.dedupeKey(source))
        return true
    }

    fun committed(team: AgentTeamExecutionSnapshot): Boolean {
        val workspace = EncryptedAgentWorkspaceStore(context).find(team.taskId) ?: return false
        val key = AgentFinalResponseIdentity.dedupeKey(team.taskId)
        return AgentTranscriptStore(context).workspacePreviews(workspace).any {
            it.role == AgentTranscriptRole.ASSISTANT && it.turnId == team.taskId && it.dedupeKey == key &&
                it.text.isNotBlank()
        }
    }
}
