package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentBrowserActionPlanTest {
    private val screen = ScreenContext("Fixture", pageTitle = "Fixture")
    private val action = AgentAction("handoff-action", AgentActionKind.CALL_NATIVE_TOOL, "browser", AgentRisk.LOW,
        AgentActionStatus.RUNNING, "Return browser control after user interaction", mapOf(
            "tool_id" to AgentInteractiveBrowserTools.ACT,
            "input_json" to """{"operation":"request_user_control","session_id":"browser","page_id":"page"}""",
            INTERNAL_CONVERSATION_ID to "conversation", INTERNAL_TURN_ID to "turn"))
    private val connector = AgentAction("reason", AgentActionKind.CALL_CONNECTOR, "Codex fixture", AgentRisk.LOW,
        AgentActionStatus.COMPLETED, "Reason about observations", mapOf("connector_task_mode" to
            PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE, "connector_id" to "fixture", "model" to "chosen-model",
            "reasoning_effort" to "high", "manual_target_locked" to "true"))
    private val target = AgentCallableTarget("fixture", "Codex fixture", AgentConnectorKind.AGENT,
        AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.CHAT, AgentCapability.REASONING))
    private val plan = AgentPlan("Public fixture", screen, emptyList(), listOf(action), planId = "plan",
        revision = 7, actionHistory = listOf(connector), plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE)
        .addCheckpoint(AgentExecutionContinuity.checkpointBefore(action, screen, 7))
    private val workspace = AgentWorkspace("run", "owner", "conversation", "turn", status = AgentWorkspaceStatus.RUNNING)
    private val attributes = AgentBrowserActionPlanPolicy.attributes("session", plan, action)
    private val context = AgentNativeToolInvocationContext(sessionId = "session", conversationId = "conversation",
        turnId = "turn", callerId = AgentBrowserActionPlanPolicy.CALLER,
        attributes = attributes + mapOf("workspace_id" to AgentWorkspaceScope.id("conversation", "session"), "task_id" to "turn"))
    private val scope = AgentInteractiveBrowserTools.scope(context)
    private val record = AgentBrowserUserRequest(AgentBrowserUserRequest.key(scope, "browser"), "generation", scope,
        "session", "conversation", "turn", context.callerId, context.attributes.getValue("workspace_id"), "browser", "page",
        "handoff", "returned", taskId = "turn", actionPlanId = "plan", actionPlanRevision = 7,
        actionId = action.id, actionPlanBinding = attributes.getValue("action_plan_binding"))
    private fun session(plan: AgentPlan = this.plan) = AgentSessionSnapshot("session", AgentPhase.EXECUTING,
        plan.goal, screen, plan, emptyList(), null, executionLoopSnapshot = AgentExecutionLoop.create().also {
            it.start("turn", AgentExecutionLoopBudget()) }.snapshot, processInstanceId = AgentProcessIdentity.instanceId,
        updatedAtMillis = 1)
    private fun bound() = AgentBrowserRunRecoveryPolicy.bind(record, listOf(workspace)) { session() }

    @Test fun `ActionPlan handoff binds without inventing a native model loop`() {
        val bound = bound()
        assertEquals("run", bound.runWorkspaceId)
        assertEquals("owner", bound.runSessionId)
        assertEquals("", bound.modelLoopId)
        assertEquals("", bound.runPlanningBinding)
        assertEquals(AgentLongTaskRecoveryMode.BROWSER_ACTION_EVENT,
            AgentBrowserRunRecoveryPolicy.decision(bound, workspace, session(), emptySet())?.mode)
        assertEquals(bound, AgentBrowserUserRequest.fromJson(bound.toJson()))
    }

    @Test fun `plan id cannot substitute for the actual task and turn`() {
        assertEquals(record.copy(taskId = "plan"), AgentBrowserRunRecoveryPolicy.bind(record.copy(taskId = "plan"),
            listOf(workspace)) { session() })
        assertFalse(AgentBrowserRunRecoveryPolicy.matches(bound().copy(taskId = "plan"), workspace, session()))
    }

    @Test fun `different action arguments revision checkpoint or browser cannot consume an event`() {
        val changed = listOf(plan.copy(revision = 8), plan.copy(planId = "other"),
            plan.copy(actions = listOf(action.copy(parameters = action.parameters + ("input_json" to "{}")))),
            plan.addCheckpoint(AgentExecutionContinuity.checkpointBefore(action, screen, 7)))
        changed.forEach { assertNull(AgentBrowserActionPlanPolicy.action(record, session(it))) }
        listOf(record.copy(pageId = "other"), record.copy(browserSessionId = "other"), record.copy(actionId = "other"),
            record.copy(actionPlanRevision = 8), record.copy(actionPlanBinding = "other"), record.copy(callerId = "other"),
            record.copy(scope = "other"), record.copy(modelLoopId = "other-loop"),
            record.copy(collaborationSourceMessageId = 101)).forEach {
            assertNull(AgentBrowserActionPlanPolicy.action(it, session()))
        }
    }

    @Test fun `ambiguous runs and a missing node checkpoint remain unbound`() {
        assertEquals(record, AgentBrowserRunRecoveryPolicy.bind(record, listOf(workspace, workspace.copy(workspaceId = "other"))) { session() })
        assertTrue(AgentBrowserActionPlanPolicy.attributes("session", plan.copy(checkpoints = emptyList()), action).isEmpty())
        assertTrue(AgentBrowserActionPlanPolicy.attributes("session", plan.copy(plannerProfile = "other", actionHistory = emptyList()), action).isEmpty())
    }

    @Test fun `receipt must match exact generation and original action`() {
        val receipt = AgentActionResult(action.id, true, "Dispatch receipt", mapOf("native_tool_id" to AgentInteractiveBrowserTools.ACT,
            "native_tool_output" to AgentNativeJsonCodec.stringify(mapOf("durable_resume_available" to true,
                "host_wait_key" to record.key, "host_wait_generation" to record.generation))))
        assertEquals(record, AgentBrowserActionPlanPolicy.receiptRecord(receipt) { record })
        assertNull(AgentBrowserActionPlanPolicy.receiptRecord(receipt) { record.copy(generation = "new") })
        assertNull(AgentBrowserActionPlanPolicy.receiptRecord(receipt.copy(actionId = "other")) { record })
        assertNull(AgentBrowserActionPlanPolicy.receiptRecord(receipt.copy(success = false)) { record })
    }

    @Test fun `observation never asserts authentication and preserves original evidence`() {
        val original = action.copy(result = "Original native receipt", evidence = "immutable output")
        val observed = AgentBrowserActionPlanPolicy.observe(record, original)
        assertTrue(observed.result.contains("\"authentication_verified\":false"))
        assertTrue(observed.result.contains("\"requires_observation\":true"))
        assertTrue(observed.result.contains(original.result))
        assertTrue(observed.evidence.endsWith(original.evidence))
        assertEquals(observed, AgentBrowserActionPlanPolicy.observe(record, observed))
        assertFalse(AgentBrowserActionPlanPolicy.observed(record.copy(generation = "other"), observed))
    }

    @Test fun `interrupted host is unconfirmed not an authentication failure`() {
        for (code in listOf("browser_host_restarted", "browser_runtime_exited", "browser_runtime_replaced")) {
            val interrupted = record.copy(state = "interrupted", interruptionCode = code)
            val observed = AgentBrowserActionPlanPolicy.observe(interrupted, action)
            assertTrue(observed.result.contains("browser_control_interrupted"))
            assertTrue(observed.result.contains(code))
            assertTrue(observed.result.contains("\"control_owner\":\"unknown\""))
            assertTrue(observed.result.contains("\"goal_terminal\":false"))
        }
        assertThrows(IllegalArgumentException::class.java) { AgentBrowserActionPlanPolicy.observe(record.copy(state = "active"), action) }
    }

    @Test fun `return retires stale proposed mutations and consults the same configured provider`() {
        val stale = action.copy(id = "stale-proposal", status = AgentActionStatus.PENDING_CONFIRMATION)
        val original = plan.copy(actions = listOf(action, stale))
        val observed = AgentBrowserActionPlanPolicy.observe(record, action)
        val next = AgentBrowserActionPlanPolicy.continuation(original, record, observed,
            AgentRequest(plan.goal, screen, targets = listOf(target), memories = emptyList(),
                runtimeContext = AgentRuntimeContextBuilder.build("session", plan.goal, screen,
                    PermissionMode.FULL_ACCESS, false, false, emptyList(), emptyList())))
        assertEquals(8, next.revision)
        assertEquals(2, next.actions.size)
        assertEquals(observed, next.actions.first())
        val reviewer = next.actions.last()
        assertTrue(reviewer.isSupervisedProjectConnector())
        listOf("connector_id", "model", "reasoning_effort", "manual_target_locked").forEach {
            assertEquals(connector.parameters[it], reviewer.parameters[it])
        }
        assertEquals(action.id, reviewer.parameters["use_outputs_from"])
        val dispatched = next.materializeToolInput(reviewer, allowOutputHandoff = true)
        assertTrue(dispatched.parameters.getValue("prompt").contains("browser_control_returned"))
        assertTrue(dispatched.parameters.getValue("prompt").contains("\"authentication_verified\":false"))
        assertEquals(AgentActionStatus.ROLLED_BACK, next.actionHistory.single { it.id == stale.id }.status)
        assertNotNull(AgentBrowserActionPlanPolicy.action(record, session(next)))
        assertEquals(1, (next.actionHistory + next.actions).count { it.id == observed.id })
        assertTrue(next.validation.issues.toString(), next.validation.valid)
    }

    @Test fun `completed dependency chain keeps its exact dispatched parameters`() {
        val earlier = action.copy(id = "observe-page", status = AgentActionStatus.COMPLETED,
            parameters = action.parameters + mapOf("tool_id" to AgentInteractiveBrowserTools.OBSERVE,
                "input_json" to """{"operation":"observe"}"""))
        val dependent = action.copy(parameters = action.parameters + ("depends_on" to earlier.id))
        val original = plan.copy(actions = listOf(connector, earlier, dependent), actionHistory = emptyList(), checkpoints = emptyList())
            .addCheckpoint(AgentExecutionContinuity.checkpointBefore(dependent, screen, 7))
        val boundRecord = record.copy(actionPlanBinding = AgentBrowserActionPlanPolicy.attributes("session", original,
            dependent).getValue("action_plan_binding"))
        val observed = AgentBrowserActionPlanPolicy.observe(boundRecord, dependent)
        val next = AgentBrowserActionPlanPolicy.continuation(original, boundRecord, observed,
            AgentRequest(plan.goal, screen, targets = listOf(target), memories = emptyList(),
                runtimeContext = AgentRuntimeContextBuilder.build("session", plan.goal, screen,
                    PermissionMode.FULL_ACCESS, false, false, listOf(target), emptyList())))
        assertEquals(listOf(connector, earlier, observed), next.actions.take(3))
        assertTrue(next.actions.last().isSupervisedProjectConnector())
        assertEquals(4, next.actions.size)
        assertEquals(observed.id, next.actions.last().outputSourceIds().first())
        val dispatched = next.materializeToolInput(next.actions.last(), allowOutputHandoff = true)
        assertTrue(dispatched.parameters.getValue("prompt").contains("browser_control_returned"))
        assertTrue(next.validation.issues.toString(), next.validation.valid)
        assertNotNull(AgentBrowserActionPlanPolicy.action(boundRecord, session(next)))
    }

    @Test fun `committed observation remains bindable after another revision but unobserved old events do not`() {
        val observed = AgentBrowserActionPlanPolicy.observe(record, action)
        val advanced = plan.copy(revision = 9, actions = emptyList(), actionHistory = listOf(connector, observed.ensurePlanRevision(7)))
        assertNotNull(AgentBrowserActionPlanPolicy.action(record, session(advanced)))
        assertNull(AgentBrowserActionPlanPolicy.action(record.copy(generation = "new"), session(advanced)))
        assertNull(AgentBrowserActionPlanPolicy.action(record, session(advanced.copy(actionHistory = listOf(connector, action)))))
    }

    @Test fun `manual pause cancel and active owners suppress ActionPlan recovery`() {
        val bound = bound()
        assertNull(AgentBrowserRunRecoveryPolicy.decision(bound, workspace, session(), setOf(workspace.workspaceId)))
        assertNull(AgentBrowserRunRecoveryPolicy.decision(bound, workspace.copy(cancellationRequested = true), session(), emptySet()))
        assertNull(AgentBrowserRunRecoveryPolicy.decision(bound, workspace, session().copy(lastActionResult =
            AgentActionResult("agent-paused", true, "Paused by user")), emptySet()))
        assertNull(AgentBrowserRunRecoveryPolicy.decision(bound.copy(state = "active"), workspace, session(), emptySet()))
        listOf(AgentPhase.COMPLETED, AgentPhase.CANCELLED, AgentPhase.FAILED).forEach {
            assertNull(AgentBrowserRunRecoveryPolicy.decision(bound, workspace, session().copy(phase = it), emptySet()))
        }
    }

    @Test fun `ActionPlan binding cannot change within a request generation`() {
        listOf(record.copy(actionPlanId = "other"), record.copy(actionPlanRevision = 8), record.copy(actionId = "other"),
            record.copy(actionPlanBinding = "other")).forEach { assertFalse(record.permitsSameGeneration(it)) }
    }
}
