package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentManagedBrowserOwnerTest {
    private val member = AgentTeamMember("local-provider", AgentDeliveryMode.RESPOND, role = "Researcher",
        objective = "Original assignment", instanceId = "member")
    private val request = AgentRunRequest("conversation", "turn", "task", runId = "supervisor", goal = "Original goal",
        idempotencyKey = "original-key")
    private val checkpoint = AgentTeamExecutionCheckpoint(AgentTeamDefinition("team", member.agentId, listOf(member),
        primaryInstanceId = member.memberId), request, emptyMap(), 1)
    private val record = AgentManagedResponseRecord(stableAgentTeamMemberRunId(request.runId, member.memberId),
        request.runId, member.agentId, member.deliveryMode,
        AgentTeamDispatchIds.sourceMessageId("member:${request.idempotencyKey}:${member.memberId}"),
        "local-llm", request.conversationId, request.messageId, request.taskId)
    private val id = AgentLocalDispatchIdentity(record.sourceMessageId, record.contactId, record.conversationId,
        record.turnId, record.taskId, "team-${record.ownerRunId}")
    private val owner = checkNotNull(AgentManagedBrowserOwner.capture(id, record, checkpoint))
    private val snapshot = AgentTeamExecutionSnapshot(request.runId, "team", request.conversationId, request.taskId,
        member.agentId, request.goal, AgentTeamVisibilityMode.BACKGROUND, AgentTeamExecutionState.RUNNING,
        listOf(AgentTeamMemberSnapshot(member.agentId, member.role, member.deliveryMode, AgentSubagentStatus.RUNNING,
            instanceId = member.memberId)), primaryInstanceId = member.memberId)
    private fun decide(record: AgentManagedResponseRecord? = this.record, checkpoint: AgentTeamExecutionCheckpoint? = this.checkpoint,
        snapshot: AgentTeamExecutionSnapshot? = this.snapshot, control: AgentTeamUserControl = AgentTeamUserControl.RUN) =
        AgentManagedBrowserOwner.decide(owner, id, record, checkpoint, snapshot, control)

    @Test fun capturesTheExactMemberAndCanRecoverAnInterruptedParentWithoutDispatchingItAgain() {
        assertEquals(owner, AgentManagedBrowserOwner.fromJson(owner.toJson()))
        assertEquals(AgentManagedBrowserState.READY, decide())
        assertEquals(AgentManagedBrowserState.READY, decide(snapshot = snapshot.copy(state = AgentTeamExecutionState.INTERRUPTED)))
    }

    @Test fun missingOrForeignLedgerIdentityCannotAuthorizeAnyRecovery() {
        assertEquals(AgentManagedBrowserState.UNVERIFIED, decide(record = null))
        listOf(record.copy(sourceMessageId = record.sourceMessageId + 1), record.copy(contactId = "other"),
            record.copy(conversationId = "other"), record.copy(turnId = "other"), record.copy(taskId = "other"),
            record.copy(ownerRunId = "other"), record.copy(supervisorRunId = "other")).forEach {
            assertEquals(AgentManagedBrowserState.UNVERIFIED, decide(record = it, control = AgentTeamUserControl.STOP))
        }
    }

    @Test fun providerAndDeliveryModeArePartOfTheImmutableAssignment() {
        assertNull(AgentManagedBrowserOwner.capture(id, record.copy(agentId = "other"), checkpoint))
        assertNull(AgentManagedBrowserOwner.capture(id, record.copy(deliveryMode = AgentDeliveryMode.OBSERVE), checkpoint))
        assertNull(AgentManagedBrowserOwner.capture(id.copy(actionId = "ordinary-parent-action"), record, checkpoint))
        assertNull(AgentManagedBrowserOwner.capture(id, record, checkpoint.copy(request = request.copy(idempotencyKey = "new-key"))))
    }

    @Test fun changedGoalObjectiveDependenciesAndMemberContextRevokeTheOldAssignment() {
        assertEquals(AgentManagedBrowserState.OBSOLETE, decide(checkpoint = checkpoint.copy(request = request.copy(goal = "New goal"))))
        listOf(member.copy(objective = "New assignment"), member.copy(role = "Other role"),
            member.copy(dependsOnAgentIds = setOf("new-dependency")), member.copy(context = mapOf("version" to "new"))).forEach {
            assertEquals(AgentManagedBrowserState.OBSOLETE,
                decide(checkpoint = checkpoint.copy(definition = checkpoint.definition.copy(members = listOf(it)))))
        }
    }

    @Test fun pausePreservesOwnershipAndStopIsDistinctFromInferenceFailure() {
        assertEquals(AgentManagedBrowserState.PAUSED, decide(control = AgentTeamUserControl.PAUSE))
        assertEquals(AgentManagedBrowserState.PAUSED, decide(snapshot = snapshot.copy(paused = true)))
        assertEquals(AgentManagedBrowserState.STOPPED, decide(control = AgentTeamUserControl.STOP))
        assertEquals(AgentManagedBrowserState.UNVERIFIED, decide(checkpoint = null))
        assertEquals(AgentManagedBrowserState.UNVERIFIED, decide(snapshot = null))
    }

    @Test fun anAlreadyDeliveredMemberCanNeverInferAgainEvenIfItsParentCheckpointIsGone() {
        listOf(AgentManagedResponseState.COMPLETED, AgentManagedResponseState.APPLIED).forEach {
            assertEquals(AgentManagedBrowserState.DELIVERED, decide(record = record.copy(state = it),
                checkpoint = null, snapshot = null, control = AgentTeamUserControl.STOP))
        }
    }

    @Test fun terminalRemovedAndNotYetRunningMembersCannotResume() {
        assertEquals(AgentManagedBrowserState.OBSOLETE, decide(snapshot = snapshot.copy(members = emptyList())))
        assertEquals(AgentManagedBrowserState.OBSOLETE, decide(snapshot = snapshot.copy(state = AgentTeamExecutionState.SUCCEEDED)))
        assertEquals(AgentManagedBrowserState.OBSOLETE, decide(snapshot = snapshot.copy(members = listOf(snapshot.members[0]
            .copy(status = AgentSubagentStatus.SUCCEEDED)))))
        assertEquals(AgentManagedBrowserState.UNVERIFIED, decide(snapshot = snapshot.copy(members = listOf(snapshot.members[0]
            .copy(status = AgentSubagentStatus.QUEUED)))))
        assertEquals(AgentManagedBrowserState.UNVERIFIED, decide(snapshot = snapshot.copy(taskId = "other")))
    }

    @Test fun memberBrowserWakeNeedsBothTheManagedOwnerAndItsDispatchAndCannotRetagAGeneration() {
        val dispatch = AgentLocalBrowserDispatch(id, "", "", "Public model", 1, managedOwner = owner)
        val scope = dispatch.scope
        val context = AgentNativeToolInvocationContext(sessionId = scope.session, conversationId = scope.conversation,
            turnId = scope.turn, callerId = scope.caller, collaborationSourceMessageId = id.sourceMessageId,
            attributes = mapOf("task_id" to scope.task, "workspace_id" to scope.workspace))
        val browserScope = AgentInteractiveBrowserTools.scope(context)
        val browser = AgentBrowserUserRequest(AgentBrowserUserRequest.key(browserScope, "browser"), "generation", browserScope,
            scope.session, scope.conversation, scope.turn, scope.caller, scope.workspace, "browser", "page", state = "returned",
            taskId = scope.task, modelLoopId = scope.loop, localDispatchId = dispatch.key,
            collaborationSourceMessageId = id.sourceMessageId, managedOwnerRunId = owner.ownerRunId)
        assertTrue(browser.pendingRunWake)
        assertTrue(AgentLocalBrowserDispatchPolicy.matches(dispatch, browser))
        assertFalse(browser.copy(localDispatchId = "").pendingRunWake)
        assertFalse(browser.copy(managedOwnerRunId = "").pendingRunWake)
        assertFalse(browser.permitsSameGeneration(browser.copy(managedOwnerRunId = "other")))
        listOf(browser.copy(managedOwnerRunId = "other"), browser.copy(collaborationSourceMessageId = null),
            browser.copy(runWorkspaceId = "ordinary-parent")).forEach { assertFalse(AgentLocalBrowserDispatchPolicy.matches(dispatch, it)) }
    }
}
