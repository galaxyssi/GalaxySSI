package com.galaxyssi.chat

import org.json.JSONObject

/** Monotonic observations include test overhead; they are not network-only latency. */
internal fun businessPhaseTiming(replyMs: Long, assessmentStartMs: Long, assessmentEndMs: Long,
                                 checksEndMs: Long, artifactTurn: Boolean, assessment: JSONObject): JSONObject {
    require(replyMs >= 0 && assessmentStartMs >= replyMs && assessmentEndMs >= assessmentStartMs && checksEndMs >= assessmentEndMs)
    val result = JSONObject().put("schema", 1).put("clock", "elapsed_realtime")
        .put("reply_terminal_ms", replyMs)
        .put("assessment_started_ms", assessmentStartMs)
        .put("assessment_completed_ms", assessmentEndMs)
        .put("assessment_duration_ms", assessmentEndMs - assessmentStartMs)
        .put("ui_check_ms", checksEndMs - assessmentEndMs)
        .put("observed_end_to_end_ms", checksEndMs)
        .put("artifacts_present_ms", JSONObject.NULL)
        .put("artifact_presence_wait_ms", JSONObject.NULL)
        .put("artifact_audit_ms", JSONObject.NULL)
        .put("save_verification_ms", JSONObject.NULL)
        .put("artifacts_verified_ms", JSONObject.NULL)
    if (artifactTurn && assessment.has("artifact_presence_wait_ms")) {
        val wait = assessment.getLong("artifact_presence_wait_ms")
        val save = assessment.getLong("save_verification_ms")
        val duration = assessmentEndMs - assessmentStartMs
        require(wait in 0..duration && save in 0..(duration - wait))
        result.put("artifact_presence_wait_ms", wait).put("artifact_audit_ms", duration - wait)
            .put("save_verification_ms", save)
        if (assessment.optBoolean("all_artifacts_present")) result.put("artifacts_present_ms", assessmentStartMs + wait)
        if (assessment.optBoolean("correct") && assessment.optBoolean("all_artifacts_verified")) {
            result.put("artifacts_verified_ms", assessmentEndMs)
        }
    }
    return result
}
