package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal object CollaborationArtifactProbeFixture {
    fun input(artifact: CollaborationPilotArtifact, id: String = "probe-fixture") = JSONObject()
        .put("format", "galaxyssi.artifact-transfer-probe.v1").put("pilot_id", id)
        .put("target_id", artifact.source["target_id"]).put("model_id", artifact.source["model_id"])
        .put("reasoning_effort", artifact.source["reasoning_effort"]).put("tool_scope", CollaborationRemotePilotPlan.TOOL_SCOPE)
        .put("trial_timeout_ms", 60_000).put("sources", JSONArray().put(JSONObject().put("id", "source-a")
            .put("source", artifact.source.json()).put("reference", artifact.reference.json())))
        .put("slots", JSONArray(listOf("available", "withheld").map { JSONObject().put("id", it)
            .put("case_id", "new-target").put("source_id", "source-a").put("condition", it)
            .put("prompt", "New synthetic task: return the count of the supplied three records.") }))

    fun execution(bound: CollaborationArtifactProbePlan.Bound, token: String): AgentTeamMemberExecutionContext {
        val group = "probe-group-$token"
        val run = "probe-run-$token"
        val member = bound.definition(group, run).members.single()
        return AgentTeamMemberExecutionContext(member, AgentRunRequest(group, "turn-$token", "task-$run", runId = "owner-$token",
            parentRunId = run, goal = bound.slot.prompt, idempotencyKey = "$run:probe"),
            AgentSubagentContextHandoff("ambient memory must not appear", emptyList(), 0, 60_000, false), 0, AgentSubagentProvenance())
    }

    fun action(bound: CollaborationArtifactProbePlan.Bound, execution: AgentTeamMemberExecutionContext) =
        AgentAction("probe", AgentActionKind.CALL_CONNECTOR, "Fixture", AgentRisk.LOW, AgentActionStatus.RUNNING,
            "fixture", parameters = mapOf("connector_id" to bound.targetId, "agent_model_id" to bound.selection.modelId,
                "manual_model_id" to bound.selection.modelId, "agent_reasoning_effort" to bound.selection.reasoningEffort.wireValue,
                "manual_target_locked" to "true", MANAGED_AGENT_TEAM_ACTION_PARAMETER to "true", "agent_instance_id" to "probe",
                "_galaxyssi_conversation_id" to execution.request.conversationId, "_galaxyssi_turn_id" to execution.request.messageId,
                "_galaxyssi_task_id" to execution.request.taskId, "idempotency_key" to execution.request.idempotencyKey, "prompt" to "unused"))
}
