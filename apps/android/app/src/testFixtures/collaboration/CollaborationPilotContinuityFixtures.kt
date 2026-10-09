package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Local fixtures only; real research inputs are supplied outside the repository. */
internal object CollaborationPilotContinuityFixtures {
    val protocolHash = "a".repeat(64)
    val reportHash = "b".repeat(64)
    fun input(study: String = "fixture", phase: Int = 1, retain: Boolean = true) = JSONObject()
        .put("format", CollaborationAdaptivePilotPlan.FORMAT).put("pilot_id", "$study-$phase")
        .put("device_model", "fixture-phone").put("target_id", "fixture:codex")
        .put("model_id", "fixture-model").put("reasoning_effort", "high")
        .put("tool_scope", CollaborationRemotePilotPlan.TOOL_SCOPE).put("goal", "Independent new task $phase")
        .put("trial_timeout_ms", 1000).put("maximum_dispatches", 2)
        .put("members", JSONArray().put(JSONObject().put("id", "lead").put("name", "Lead").put("role", "Coordinator"))
            .put(JSONObject().put("id", "peer").put("name", "Peer").put("role", "Researcher")))
        .put("continuity", JSONObject().put("study_id", study).put("phase", phase)
            .put("previous_report_sha256", if (phase == 1) "" else reportHash).put("retain_history", retain))

    fun plan(input: JSONObject = input()) = CollaborationAdaptivePilotPlan.from(input, 2, 1000)

    fun report(lease: CollaborationPilotContinuity.Lease) = JSONObject().put("pilot_id", lease.pilotId)
        .put("protocol_sha256", lease.protocolSha256).put("conversation_id", lease.groupId)
        .put("run_id", "adaptive-pilot-${lease.pilotId}").put("turn_id", "turn-adaptive-pilot-${lease.pilotId}")
        .put("finished", true).put("cleanup_confirmed", true).put("milestone_archive_complete", true)
        .put("durable_control", "STOP").put("pending_remote_owners", JSONArray()).put("test_verdict", "failed")

    fun workflow() = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Synthetic method candidate")
        .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(JSONObject()
            .put("id", "fixture-method").put("kind", CollaborationWorkflowMethod.KIND).put("title", "Immutable index")
            .put("body", JSONObject().put("content", "Synthetic unverified method; not evidence of learning")
                .put(CollaborationWorkflowMethod.KIND, JSONObject().put("purpose", "Avoid repeated parsing").put("domain", "fixture")
                    .put("bottleneck", "Repeated scans").put("change_rationale", "Reuse an immutable index")
                    .put("applies_when", "Identical immutable corpus").put("avoid_when", "Mutable corpus")
                    .put("risks", "Stale data").put("expected_gain", "Less repeated work").put("falsifier", "Missing fields")
                    .put("dimensions", JSONArray().put("retrieval")).put("roles", JSONArray().put("researcher"))
                    .put("inputs", JSONArray().put("corpus")).put("steps", JSONArray().put(JSONObject()
                        .put("id", "inspect").put("role", "researcher").put("stage", "VERIFY")
                        .put("assignment", "Check corpus identity before using the index").put("depends_on", JSONArray())))))))
}
