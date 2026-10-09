package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationSingleAgentCalibrationTest {
    private fun input() = JSONObject().put("format", CollaborationAdaptivePilotPlan.SINGLE_FORMAT)
        .put("pilot_id", "single-calibration").put("device_model", "SM-G9880")
        .put("target_id", "desktop:codex").put("model_id", "selected-model").put("reasoning_effort", "high")
        .put("tool_scope", CollaborationRemotePilotPlan.TOOL_SCOPE).put("goal", "Solve and verify the supplied task")
        .put("trial_timeout_ms", 600_000).put("maximum_dispatches", 1)
        .put("members", JSONArray().put(JSONObject().put("id", "researcher").put("name", "Researcher").put("role", "Researcher")))
    private fun plan(value: JSONObject = input()) = CollaborationAdaptivePilotPlan.from(value, 12, 600_000)
    private fun reject(block: () -> Unit) = assertNotNull(runCatching(block).exceptionOrNull())

    @Test fun onePersonGetsTheWholeTaskWithoutCoordinatorStagesOrFixedSubtasks() {
        val p = plan()
        val graph = p.definition("group", "run")
        val member = graph.members.single()
        assertTrue(p.singleAgent)
        assertEquals("single_agent", p.executionMode)
        assertEquals(p.goal, member.objective)
        assertEquals(AgentDeliveryMode.RESPOND, member.deliveryMode)
        assertEquals("researcher", member.context[CollaborationResearchWorkflow.PERSON])
        assertNull(CollaborationResearchWorkflow.stage(member))
        assertFalse(CollaborationLiveGraph.enabled(graph))
        assertTrue(p.matchesExecution(member, graph))
        assertFalse(p.matchesExecution(member, graph.copy(members = graph.members + member.copy(instanceId = "extra"))))
        assertFalse(p.matchesExecution(member.copy(objective = "Plan only"), graph))
        assertFalse(p.matchesExecution(member.copy(context = member.context + (CollaborationGoalLoop.ENABLED to "1")), graph))
    }

    @Test fun modeMustBeExplicitAndCannotUseExtraPeopleOrPhoneDispatches() {
        reject { plan(input().put("format", CollaborationAdaptivePilotPlan.FORMAT)) }
        reject { plan(input().put("maximum_dispatches", 2)) }
        reject { plan(input().put("members", JSONArray())) }
        reject { plan(input().apply { getJSONArray("members").put(JSONObject().put("id", "peer").put("name", "Peer").put("role", "Reviewer")) }) }
        reject { plan(input().put("format", "unknown")) }
        reject { plan(input().put("tool_scope", "isolated")) }
    }

    @Test fun selectedModelAndEffortRemainFrozenRatherThanHardcoded() {
        val p = plan(input().put("reasoning_effort", "xhigh"))
        p.requireAppSelection(AgentModelSelection(AgentModelSelectionMode.MANUAL, p.targetId,
            "selected-model", reasoningEffort = AgentModelReasoningEffort.XHIGH))
        reject { p.requireAppSelection(AgentModelSelection()) }
        assertEquals("selected-model", p.definition("group", "run").members.single().context["collaboration_model_id"])
    }

    @Test fun singleExecutionIsNotArtificiallySplitAndItsReturnIsNotGoalAcceptance() = runBlocking {
        val p = plan()
        val store = InMemoryAgentTeamExecutionStore()
        val request = AgentRunRequest("group", "turn", "task", runId = "run", goal = p.goal, idempotencyKey = "run")
        val guard = CollaborationAdaptivePilotAdmission(p, "group", "run", "turn", 100, { 1 },
            { store.deliveryCheckpoint("run") }, {})
        var calls = 0
        val worker = object : AgentTeamMemberWorker {
            override suspend fun execute(context: AgentTeamMemberExecutionContext): AgentSubagentOutput {
                guard.prepare(context)
                calls++
                assertEquals(p.goal, context.member.objective)
                return AgentSubagentOutput("A synthetic delivered answer; not proof of scientific success")
            }
            override suspend fun sendMessage(member: AgentTeamMember, runId: String, message: AgentControlMessage) = Unit
        }
        AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 1)).use { runtime ->
            val runner = CollaborationAdaptivePilotRunner(store, runtime, guard, singleAgent = true)
            assertEquals("single_agent_returned_goal_unverified", runner.run(p.definition("group", "run"), request, worker))
        }
        assertEquals(1, calls)
        assertNotEquals("achieved", store.snapshot("run")!!.goalDisposition)
    }

    @Test fun singleAdmissionPreservesPromptButRejectsMissingTaskBeforeIo() {
        val p = plan()
        val definition = p.definition("group", "run")
        val member = definition.members.single()
        val request = AgentRunRequest("group", "turn", "task", runId = "run", goal = p.goal, idempotencyKey = "run")
        val store = InMemoryAgentTeamExecutionStore().also { it.create(definition, request) }
        val context = AgentTeamMemberExecutionContext(member, request.copy(parentRunId = "run",
            runId = stableAgentTeamMemberRunId("run", member.memberId), idempotencyKey = "run:${member.memberId}"),
            AgentSubagentContextHandoff("", emptyList(), 0, 60_000, false), 0, AgentSubagentProvenance())
        val records = mutableListOf<JSONObject>()
        val guard = CollaborationAdaptivePilotAdmission(p, "group", "run", "turn", 100, { 1 },
            { store.deliveryCheckpoint("run") }, records::add)
        guard.prepare(context)
        val action = AgentAction("action", AgentActionKind.CALL_CONNECTOR, "Selected", AgentRisk.LOW,
            AgentActionStatus.RUNNING, "fixture", parameters = mapOf("connector_id" to p.targetId,
                "agent_model_id" to p.selection.modelId, "manual_model_id" to p.selection.modelId,
                "agent_reasoning_effort" to "high", "manual_target_locked" to "true", MANAGED_AGENT_TEAM_ACTION_PARAMETER to "true",
                "agent_instance_id" to member.memberId, "_galaxyssi_conversation_id" to "group", "_galaxyssi_turn_id" to "turn",
                "_galaxyssi_task_id" to "task", "idempotency_key" to context.request.idempotencyKey, "prompt" to "missing task"))
        reject { guard.admit(action) }
        assertEquals(0, guard.count())
        val complete = action.copy(parameters = action.parameters + ("prompt" to "Original task: ${p.goal}"))
        assertSame(complete, guard.admit(complete))
        assertEquals("single_agent", records.single().getString("execution_mode"))
        reject { guard.admit(complete) }
    }

    private fun report(): JSONObject {
        val text = "Synthetic result"
        return JSONObject().put("execution_mode", "single_agent").put("test_scope", "execution_delivery_only")
            .put("status", "single_agent_returned_goal_unverified").put("finished", true).put("cleanup_confirmed", true)
            .put("pending_remote_owners", JSONArray()).put("active_conversation_preserved", true)
            .put("goal_verified_by_external_evaluator", false).put("scientific_capability_gain_proven", false)
            .put("phone_dispatches", JSONArray().put(JSONObject().put("node_id", "researcher")))
            .put("worker_results", JSONArray().put(JSONObject().put("node_id", "researcher").put("content", text)
                .put("content_sha256", CollaborationRemotePilotDispatch.sha256(text.toByteArray()))))
            .put("rounds", JSONArray().put(JSONObject().put("state", "SUCCEEDED").put("goal_disposition", "")))
    }

    @Test fun deliveryPassExplicitlyLeavesScientificAcceptanceToExternalEvaluation() {
        CollaborationAdaptivePilotVerdict.evaluate(report()).requirePassed()
        for (field in listOf("goal_verified_by_external_evaluator", "scientific_capability_gain_proven"))
            assertFalse(CollaborationAdaptivePilotVerdict.evaluate(report().put(field, true)).passed)
        for (status in listOf("host_goal_accepted", "interrupted_or_failed", "running"))
            assertFalse(CollaborationAdaptivePilotVerdict.evaluate(report().put("status", status)).passed)
        assertFalse(CollaborationAdaptivePilotVerdict.evaluate(report().put("test_scope", "host_goal_acceptance")).passed)
        assertFalse(CollaborationAdaptivePilotVerdict.evaluate(report().put("worker_results", JSONArray())).passed)
        assertFalse(CollaborationAdaptivePilotVerdict.evaluate(report().put("execution_mode", "unknown")).passed)
        val changed = report().apply { getJSONArray("rounds").getJSONObject(0).put("goal_disposition", "achieved") }
        assertFalse(CollaborationAdaptivePilotVerdict.evaluate(changed).passed)
    }
}
