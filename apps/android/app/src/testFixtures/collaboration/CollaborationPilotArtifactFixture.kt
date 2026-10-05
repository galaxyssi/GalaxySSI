package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Local deterministic worker only: no model, transport, tool, or user conversation access. */
internal object CollaborationPilotArtifactFixture {
    fun plan(id: String = "artifact-fixture") = CollaborationRemotePilotPlan.from(JSONObject()
        .put("format", "galaxyssi.remote-collaboration-pilot.v1").put("pilot_id", id)
        .put("target_id", "fixture:codex").put("model_id", "test-artifact-model").put("reasoning_effort", "high")
        .put("tool_scope", CollaborationRemotePilotPlan.TOOL_SCOPE).put("trial_timeout_ms", 60_000)
        .put("slots", JSONArray(listOf("single", "team").map { JSONObject().put("id", it).put("case_id", "fixture")
            .put("arm", it).put("prompt", "Synthetic artifact persistence check; not an efficacy experiment.") })), 6)

    data class Result(val source: CollaborationPilotArtifact.Source, val snapshot: AgentTeamExecutionSnapshot,
                      val dispatches: JSONArray, val truncated: Boolean) {
        fun capture() = CollaborationPilotArtifact.capture(source, snapshot, dispatches, truncated)
    }

    suspend fun execute(plan: CollaborationRemotePilotPlan, slot: CollaborationRemotePilotPlan.Slot,
                        store: AgentTeamExecutionStore = InMemoryAgentTeamExecutionStore()): Result {
        val run = "fixture-${plan.id}-${slot.id}"
        val group = "group-$run"
        val turn = "turn-$run"
        val definition = plan.definition(slot, group, run)
        val entries = JSONArray()
        val guard = CollaborationRemotePilotDispatch(plan, definition, group, run, turn, Long.MAX_VALUE, { 1 }) { entries.put(it) }
        val runtime = AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 1,
            maxContextChars = 60_000, maxOutputChars = 24_000))
        try {
            val result = runtime.start(definition, AgentRunRequest(group, turn, "task-$run", runId = run,
                goal = slot.prompt, idempotencyKey = run), AgentTeamMemberWorker { ctx ->
                guard.prepare(ctx)
                guard.admit(AgentAction("fixture-${ctx.member.memberId}", AgentActionKind.CALL_CONNECTOR,
                    "Fixture", AgentRisk.LOW, AgentActionStatus.RUNNING, "local synthetic worker", parameters = mapOf(
                        "connector_id" to plan.targetId, "agent_model_id" to plan.selection.modelId,
                        "manual_model_id" to plan.selection.modelId, "agent_reasoning_effort" to plan.selection.reasoningEffort.wireValue,
                        "manual_target_locked" to "true", MANAGED_AGENT_TEAM_ACTION_PARAMETER to "true",
                        "agent_instance_id" to ctx.member.memberId, "_galaxyssi_conversation_id" to group,
                        "_galaxyssi_turn_id" to turn, "_galaxyssi_task_id" to ctx.request.taskId,
                        "idempotency_key" to ctx.request.idempotencyKey, "prompt" to "unused")))
                AgentSubagentOutput("  synthetic-${ctx.member.memberId}\n\u7ed3\u679c\n")
            }).await()
            return Result(CollaborationPilotArtifact.Source.of(plan, slot, group, run, turn, "a".repeat(64)),
                result.snapshot, entries, result.subagentResult.results.any { it.outputTruncated })
        } finally { guard.close(); runtime.close() }
    }
}
