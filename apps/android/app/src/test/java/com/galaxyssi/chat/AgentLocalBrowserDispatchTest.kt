package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentLocalBrowserDispatchTest {
    private val id = AgentLocalDispatchIdentity(42, "local-llm", "conversation", "ui-turn", "native-task", "action")
    private val screen = ScreenContext("Public", pageTitle = "Public")
    private val action = AgentAction(id.actionId, AgentActionKind.CALL_CONNECTOR, "Public model", AgentRisk.LOW,
        AgentActionStatus.RUNNING, "Public action")
    private val pending = AgentActionResult(id.actionId, true, "Waiting", mapOf("source_message_id" to "42",
        "contact_id" to id.contactId, "awaiting_response" to "true"))
    private val session = AgentSessionSnapshot(id.taskId, AgentPhase.WAITING_RESPONSE, "Public goal", screen,
        AgentPlan("Public goal", screen, emptyList(), listOf(action)).addCheckpoint(
            AgentExecutionContinuity.checkpointBefore(action, screen, 1)), emptyList(), pending, updatedAtMillis = 1)
    private val dispatch = AgentLocalBrowserDispatch(id, "ui-turn", "ui-run-session", "Public model", 1,
        planBinding = checkNotNull(AgentLocalBrowserDispatchPolicy.planBinding(session, id.actionId)))
    private val workspace = AgentWorkspace(dispatch.runWorkspaceId, dispatch.runSessionId, id.conversationId,
        id.turnId, status = AgentWorkspaceStatus.WAITING_RESPONSE)
    private fun owns(workspace: AgentWorkspace? = this.workspace, session: AgentSessionSnapshot? = this.session,
        dispatch: AgentLocalBrowserDispatch = this.dispatch, pendingOnly: Boolean = true) =
        AgentLocalBrowserDispatchPolicy.owns(dispatch, workspace, session, pendingOnly)
    private fun record() = dispatch.scope.let { scope ->
        val browserScope = "a".repeat(64)
        AgentBrowserUserRequest(AgentBrowserUserRequest.key(browserScope, "browser"), "generation", browserScope,
            scope.session, scope.conversation, scope.turn, scope.caller, scope.workspace, "browser", "page",
            state = "returned", taskId = scope.task, modelLoopId = scope.loop,
            runWorkspaceId = dispatch.runWorkspaceId, runSessionId = dispatch.runSessionId, localDispatchId = dispatch.key)
    }

    @Test fun `native task and supervised turn are distinct and source bound`() {
        assertTrue(owns())
        assertNotEquals(id.taskId, workspace.taskId)
        assertFalse(owns(session = session.copy(sessionId = id.turnId)))
        listOf("source_message_id" to "43", "contact_id" to "other", "awaiting_response" to "false").forEach {
            assertFalse(owns(session = session.copy(lastActionResult = pending.copy(metadata = pending.metadata + it))))
        }
        assertFalse(owns(session = session.copy(lastActionResult = pending.copy(actionId = "other"))))
    }

    @Test fun `initial executing dispatch can bind but cannot yet recover as pending`() {
        val executing = session.copy(phase = AgentPhase.EXECUTING, lastActionResult = null)
        assertTrue(owns(session = executing, pendingOnly = false))
        assertFalse(owns(session = executing))
        assertFalse(owns(session = executing.copy(currentPlan = session.currentPlan!!.copy(actions = emptyList())), pendingOnly = false))
        assertFalse(owns(session = executing.copy(phase = AgentPhase.PLANNING), pendingOnly = false))
        val changed = session.currentPlan!!.copy(actions = listOf(action.copy(parameters = mapOf("prompt" to "other"))))
        assertFalse(owns(session = session.copy(currentPlan = changed)))
        assertFalse(owns(session = session.copy(currentPlan = session.currentPlan!!.copy(planId = "other"))))
    }

    @Test fun `cancel deleted terminal and explicit pause never revive`() {
        assertFalse(owns(workspace = null))
        assertFalse(owns(session = null))
        assertFalse(owns(workspace = workspace.copy(cancellationRequested = true)))
        AgentWorkspaceStatus.entries.filter { it.isTerminal }.forEach { assertFalse(owns(workspace = workspace.copy(status = it))) }
        listOf(AgentPhase.COMPLETED, AgentPhase.CANCELLED, AgentPhase.FAILED).forEach { assertFalse(owns(session = session.copy(phase = it))) }
        assertFalse(owns(session = session.copy(lastActionResult = pending.copy(actionId = "agent-paused"))))
        listOf("delivered", "cancelled").forEach { assertFalse(owns(dispatch = dispatch.copy(state = it))) }
    }

    @Test fun `every browser return identity field is fenced`() {
        val original = record()
        assertTrue(AgentLocalBrowserDispatchPolicy.matches(dispatch, original))
        listOf(original.copy(localDispatchId = "other"), original.copy(modelLoopId = "other"),
            original.copy(sessionId = "other"), original.copy(conversationId = "other"), original.copy(turnId = "other"),
            original.copy(taskId = "other"), original.copy(workspaceId = "other"), original.copy(callerId = "other"),
            original.copy(runWorkspaceId = "other"), original.copy(runSessionId = "other"),
            original.copy(actionPlanBinding = "other"), original.copy(collaborationSourceMessageId = 42))
            .forEach { assertFalse(AgentLocalBrowserDispatchPolicy.matches(dispatch, it)) }
        assertEquals(original, AgentBrowserUserRequest.fromJson(original.toJson()))
        assertFalse(original.permitsSameGeneration(original.copy(localDispatchId = "other")))
    }

    @Test fun `waiting is host event state not model text or a periodic heartbeat`() {
        fun event(stage: String) = AgentWorkspaceEvent(kind = AgentTaskEventKinds.PROGRESS,
            payloadJson = """{"stage":"$stage"}""")
        val waiting = workspace.copy(eventJournal = listOf(event("local_model.loop_waiting")))
        assertTrue(AgentLocalBrowserDispatchPolicy.isWaiting(waiting))
        assertFalse(AgentLocalBrowserDispatchPolicy.isWaiting(workspace.copy(eventJournal = listOf(
            AgentWorkspaceEvent(kind = AgentTaskEventKinds.PROGRESS, message = "local_model.loop_waiting")))))
        assertFalse(AgentLocalBrowserDispatchPolicy.isWaiting(waiting.copy(eventJournal = waiting.eventJournal +
            event("local_model.model_requested"))))
        val liveness = AgentTaskLivenessPolicy().evaluate(waiting, Long.MAX_VALUE / 2)
        assertEquals(AgentTaskLivenessState.HEALTHY, liveness.state)
        assertEquals(1, waiting.eventJournal.size)
    }
}
