package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationAdaptivePilotTest {
    private fun input() = JSONObject().put("format", CollaborationAdaptivePilotPlan.FORMAT).put("pilot_id", "adaptive-1")
        .put("target_id", "desktop:codex").put("model_id", "gpt-6-astra").put("reasoning_effort", "high")
        .put("tool_scope", CollaborationRemotePilotPlan.TOOL_SCOPE).put("goal", "Diagnose and verify a synthetic update failure")
        .put("trial_timeout_ms", 600_000).put("maximum_dispatches", 8).put("members", JSONArray().put(
            JSONObject().put("id", "lead").put("name", "Turing").put("role", "Coordinator")).put(
            JSONObject().put("id", "peer").put("name", "Hopper").put("role", "Researcher")))
    private fun plan(value: JSONObject = input()) = CollaborationAdaptivePilotPlan.from(value, 12, 600_000)
    private fun request(plan: CollaborationAdaptivePilotPlan) = AgentRunRequest("group", "turn", "task", runId = "root", goal = plan.goal, idempotencyKey = "root")
    private fun execution(plan: CollaborationAdaptivePilotPlan, member: AgentTeamMember = plan.definition("group", "root").members.first()) =
        AgentTeamMemberExecutionContext(member, request(plan).copy(runId = stableAgentTeamMemberRunId("root", member.memberId), parentRunId = "root",
            idempotencyKey = "root:${member.memberId}"), AgentSubagentContextHandoff("", emptyList(), 0, 60_000, false), 0, AgentSubagentProvenance())
    private fun action(context: AgentTeamMemberExecutionContext) = AgentAction("action", AgentActionKind.CALL_CONNECTOR,
        "Codex", AgentRisk.LOW, AgentActionStatus.RUNNING, "fixture", parameters = mapOf(
            "connector_id" to "desktop:codex", "agent_model_id" to "gpt-6-astra", "manual_model_id" to "gpt-6-astra",
            "agent_reasoning_effort" to "high", "manual_target_locked" to "true", MANAGED_AGENT_TEAM_ACTION_PARAMETER to "true",
            "agent_instance_id" to context.member.memberId, "_galaxyssi_conversation_id" to "group", "_galaxyssi_turn_id" to "turn",
            "_galaxyssi_task_id" to "task", "idempotency_key" to context.request.idempotencyKey, "prompt" to "Production prompt: unchanged"))
    private fun guard(plan: CollaborationAdaptivePilotPlan, store: AgentTeamExecutionStore, now: () -> Long = { 1L }, persist: (JSONObject) -> Unit = {}) =
        CollaborationAdaptivePilotAdmission(plan, "group", "root", "turn", 100L, now, { store.deliveryCheckpoint("root") }, persist)
    private fun store(plan: CollaborationAdaptivePilotPlan) = InMemoryAgentTeamExecutionStore().also { it.create(plan.definition("group", "root"), request(plan)) }
    private fun reject(block: () -> Unit) = assertNotNull(runCatching(block).exceptionOrNull())

    @Test fun initialGraphUsesProductionCoordinatorRatherThanFixedThreeNodeWork() {
        val p = plan(); val graph = p.definition("group", "root")
        assertTrue(CollaborationResearchWorkflow.isResearch(graph.members))
        assertTrue(CollaborationLiveGraph.enabled(graph))
        assertEquals(listOf("lead"), graph.members.filter { it.deliveryMode != AgentDeliveryMode.IGNORE }.map { it.memberId })
        assertTrue(graph.members.none { CollaborationGoalLoop.WORK_ID in it.context })
        assertTrue(graph.members.all { it.context[CollaborationGoalLoop.ENABLED] == "1" })
        assertFalse(graph.members.any { it.memberId in setOf("draft", "review", "final") })
    }

    @Test fun modelAndEffortAreProtocolSelectionsNotProductionDefaults() {
        val p = plan(input().put("model_id", "future-model").put("reasoning_effort", "xhigh"))
        p.requireAppSelection(AgentModelSelection(AgentModelSelectionMode.MANUAL, p.targetId, "future-model", reasoningEffort = AgentModelReasoningEffort.XHIGH))
        assertTrue(p.definition("group", "root").members.all { it.context["collaboration_model_id"] == "future-model" })
        reject { p.requireAppSelection(AgentModelSelection()) }
    }

    @Test fun experimentCannotSupplyHiddenAnswersFixedStepsOrExceedItsAuthorization() {
        for (key in listOf("answer_key", "steps", "permissions")) reject { plan(input().put(key, "injected")) }
        reject { plan(input().put("maximum_dispatches", 13)) }
        reject { plan(input().put("trial_timeout_ms", 600_001)) }
        reject { plan(input().put("maximum_dispatches", "8")) }
        reject { plan(input().put("goal", "x".repeat(60_001))) }
        reject { plan(input().put("pilot_id", "../escape")) }
        reject { plan(input().put("tool_scope", "closed_book")) }
        val duplicate = input(); duplicate.getJSONArray("members").getJSONObject(1).put("id", "lead")
        reject { plan(duplicate) }
    }

    @Test fun productionActionPromptAndRemoteIdentityAreUnmodified() {
        val p = plan(); val s = store(p); val entries = mutableListOf<JSONObject>(); val g = guard(p, s, persist = entries::add)
        val execution = execution(p); g.prepare(execution); val action = action(execution)
        assertSame(action, g.admit(action))
        assertEquals(1, entries.size); assertFalse(entries.single().getBoolean("prompt_replaced_by_harness"))
        assertEquals("lead", entries.single().getString("node_id"))
        assertFalse(entries.single().has("prompt"))
        reject { g.admit(action) }; reject { g.prepare(execution) }
    }

    @Test fun missingOrStaleGraphAndIncorrectIdentityAreRejectedBeforeIo() {
        val p = plan(); val execution = execution(p)
        reject { guard(p, InMemoryAgentTeamExecutionStore()).prepare(execution) }
        val changes = listOf(execution.copy(member = execution.member.copy(objective = "Changed")),
            execution.copy(request = execution.request.copy(parentRunId = "other")),
            execution.copy(request = execution.request.copy(runId = "not-the-stable-owner")),
            execution.copy(handoff = execution.handoff.copy(truncated = true)))
        changes.forEach { changed -> reject { guard(p, store(p)).prepare(changed) } }
        for (field in listOf("connector_id", "agent_model_id", "manual_model_id", "agent_reasoning_effort", "agent_instance_id", "_galaxyssi_conversation_id")) {
            val g = guard(p, store(p)); g.prepare(execution)
            reject { g.admit(action(execution).let { it.copy(parameters = it.parameters + (field to "wrong")) }) }
            assertEquals(0, g.count())
        }
    }

    @Test fun failedPersistenceConsumesReservationAndDeadlineClosesNewDispatches() {
        val p = plan(); val e = execution(p); val g = guard(p, store(p), persist = { error("disk failure") })
        g.prepare(e); reject { g.admit(action(e)) }; assertEquals(1, g.count()); reject { g.admit(action(e)) }
        var now = 1L; val timed = guard(p, store(p), now = { now }); timed.prepare(e); now = 100L
        reject { timed.admit(action(e)) }; assertEquals(0, timed.count())
        val closed = guard(p, store(p)); closed.close(); reject { closed.prepare(e) }
    }

    @Test fun concurrentDuplicateCanReserveOnlyOneDispatch() {
        val p = plan(input().put("maximum_dispatches", 1)); val s = store(p); val g = guard(p, s)
        val e = execution(p); g.prepare(e)
        val pool = Executors.newFixedThreadPool(4)
        try {
            val results = pool.invokeAll(List(16) { Callable { runCatching { g.admit(action(e)) }.isSuccess } })
            assertEquals(1, results.count { it.get(5, TimeUnit.SECONDS) })
            assertEquals(1, g.count()); assertTrue(g.exhausted())
        } finally { pool.shutdownNow() }
    }

    @Test fun changedParentContractAndIgnoredRosterAreNotDispatchable() {
        val p = plan(); val s = store(p); val g = guard(p, s); val e = execution(p)
        g.prepare(e)
        s.remove("root")
        s.create(p.definition("group", "root"), request(p).copy(goal = "A different goal"))
        reject { g.admit(action(e)) }; assertEquals(0, g.count())
        val roster = p.definition("group", "root").members.single { it.deliveryMode == AgentDeliveryMode.IGNORE }
        reject { guard(p, store(p)).prepare(execution(p, roster)) }
    }

    @Test fun productionLoopChoosesAndRevisesWorkInsteadOfStoppingAfterThreeNodes() = runBlocking {
        val p = plan(input().put("maximum_dispatches", 6)); val s = InMemoryAgentTeamExecutionStore()
        val g = guard(p, s); val assignments = mutableListOf<String>(); val checkpoints = mutableListOf<Long>()
        var coordinations = 0
        val worker = object : AgentTeamMemberWorker {
            override suspend fun execute(context: AgentTeamMemberExecutionContext): AgentSubagentOutput {
                g.prepare(context); g.admit(action(context)); assignments += context.member.objective
                val report = if (context.member.deliveryMode == AgentDeliveryMode.RESPOND) {
                    val stage = coordinations++
                    assessment(if (stage == 0) listOf(work("inspect", "Inspect actual installation and running version"))
                        else if (stage == 1) listOf(work("repair", "Repair only the diagnosed synthetic stale launcher"),
                            work("verify", "Verify update, preserved settings and repeat launch", "repair")) else emptyList()).toString()
                } else "Observed local fixture evidence, not a scientific capability result"
                return AgentSubagentOutput(report)
            }
            override suspend fun sendMessage(member: AgentTeamMember, runId: String, message: AgentControlMessage) = Unit
        }
        AgentTeamExecutionRuntime(s, AgentSubagentLimits(maxConcurrency = 1)).use { runtime ->
            val runner = CollaborationAdaptivePilotRunner(s, runtime, g, checkpoint = { _, cp ->
                checkpoints += cp.request.context[CollaborationGoalLoop.ROUND]?.toString()?.toLongOrNull() ?: 0L
            })
            assertEquals("phone_dispatch_envelope_reached", runner.run(p.definition("group", "root"), request(p), worker))
        }
        assertEquals(6, g.count()); assertEquals(listOf(0L, 1L, 2L), checkpoints)
        assertTrue(assignments.any { it.contains("stale launcher") })
        assertTrue(assignments.any { it.contains("preserved settings") })
        assertTrue(s.snapshot("root")!!.goalDisposition != "achieved")
    }

    private fun work(id: String, assignment: String, dependency: String? = null) = JSONObject().put("id", id).put("member", "peer")
        .put("stage", "VERIFY").put("assignment", assignment).put("depends_on", JSONArray(listOfNotNull(dependency)))
    private fun assessment(work: List<JSONObject>) = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Synthetic coordination")
        .put("decision", "continue").put("criteria", JSONArray().put(JSONObject().put("id", "updated").put("requirement", "Verified working update")
            .put("status", "open").put("evidence", JSONArray()))).put("work", JSONArray(work)).put("blockers", JSONArray())
}
