package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Pure draft diagnostics using the same parser as final assessment admission. */
internal object CollaborationAssessmentPreflight {
    const val MODE = "validate_assessment"
    const val INSTRUCTIONS = "Before returning an uncertain goal-assessment draft, call collaboration_publish " +
        "with mode=validate_assessment and artifact=<exact JSON string>. It checks JSON fields and qualified validator " +
        "specifications without publishing or ending this assignment. Repair reported fields in this same turn. " +
        "It does NOT check preserved criteria, task graphs, permissions, evidence or goal acceptance; final admission still applies."

    fun inspect(raw: String): JSONObject {
        val checked = CollaborationAssessmentValidation.inspect(raw)
        return JSONObject().put("success", true).put("status", "returned")
            .put("schema_valid", checked.assessment != null)
            .put("json_syntax", when {
                checked.syntaxValid -> "valid"
                checked.failure?.code == "json_nesting_exceeded" -> "unverified"
                else -> "invalid"
            })
            .put("draft_sha256", MqttImmutableContent.sha256(raw))
            .put("failure", checked.failure?.json() ?: JSONObject.NULL)
            .put("checked", JSONArray(listOf("assessment_fields", "qualified_validator_specification")))
            .put("not_checked", JSONArray(listOf("preserved_contract", "work_graph", "permissions", "evidence", "goal_acceptance")))
            .put("committed", false).put("goal_accepted", false).put("assignment_completed", false)
            .put("next_action", if (checked.assessment == null)
                "Repair the reported field in the draft and check again; no plan or artifact was submitted."
            else "Return the required assessment when ready; final admission and evidence checks still apply.")
    }
}
