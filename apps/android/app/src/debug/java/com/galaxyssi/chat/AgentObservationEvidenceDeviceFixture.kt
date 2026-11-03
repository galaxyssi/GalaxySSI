package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Only two real read-only calls; faults are synthetic copies, never writes to device or user task state. */
internal object AgentObservationEvidenceDeviceFixture {
    fun run(read: () -> JSONObject): JSONObject {
        val tool = AgentAndroidSystemNativeTools.AUDIO_STATUS
        val first = read()
        check(first.optString("status") == "succeeded")
        val maximum = first.getJSONObject("output").getJSONObject("streams").getJSONObject("music").getInt("max")
        val outcome = AgentObservedOutcome("media-capability", tool, mapOf("/streams/music/stream" to "music"),
            mapOf("/streams/music/max" to maximum))
        val requirements = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false, outcomes = listOf(outcome))
        fun action(id: String, evidence: String, status: AgentActionStatus = AgentActionStatus.COMPLETED) =
            AgentAction(id, AgentActionKind.CALL_NATIVE_TOOL, tool, AgentRisk.LOW, status,
                "Read-only evidence fixture", mapOf("tool_id" to tool), evidence = evidence)
        val original = action("original-read", first.toString())
        val cases = mutableListOf<String>()
        check(AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements, listOf(original)).isEmpty())
        cases += "real_receipt_accepted"
        val failure = action("synthetic-failure", "", AgentActionStatus.FAILED)
        check(AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements, listOf(original, failure)).isNotEmpty())
        cases += "latest_failed_read_blocks_old_success"
        val missing = action("synthetic-incomplete", "{}")
        check(AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements, listOf(original, missing)).isNotEmpty())
        cases += "missing_identity_blocks_old_success"
        val unverified = JSONObject(first.toString()).put("metadata", JSONObject().put("business_success_verified", false))
        check(AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements,
            listOf(original, action("synthetic-unverified", unverified.toString()))).isNotEmpty())
        cases += "envelope_uncertainty_is_preserved"
        val after = outcome.copy(afterToolId = "galaxyssi.fixture.never.executed")
        check(AgentObservedOutcomeEvidence.diagnose(after, listOf(original))?.optString("code") == "required_action_not_observed")
        cases += "imagined_effect_does_not_count"
        val second = read()
        check(second.optString("status") == "succeeded")
        val repaired = action("fresh-read", second.toString())
        check(AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements, listOf(original, failure, repaired)).isEmpty())
        cases += "fresh_real_read_restores_verified_completion"
        check(first.getJSONObject("receipt").getString("invocation_id") != second.getJSONObject("receipt").getString("invocation_id"))
        cases += "repair_uses_new_read_receipt"
        return JSONObject().put("passed", true).put("cases", JSONArray(cases))
            .put("real_read_calls", 2).put("mutations", 0).put("synthetic_faults", true)
            .put("first_receipt", first.getJSONObject("receipt")).put("fresh_receipt", second.getJSONObject("receipt"))
    }
}
