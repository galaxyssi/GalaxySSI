package com.galaxyssi.chat

import org.json.JSONObject

/** Observed facts only: no retry threshold or host-selected recovery strategy. */
internal object CollaborationPublicationProblem {
    fun observe(raw: String, receipt: JSONObject, previous: JSONObject?): JSONObject {
        val text = raw.trim().let { if (it.startsWith("```")) it.substringAfter('\n').removeSuffix("```").trim() else it }
        val parsed = runCatching { JSONObject(text) }.getOrNull()
        val schemaValid = parsed != null && CollaborationResearchArtifact.decode(raw) != null
        val previousReceipt = previous?.optJSONObject("receipt")
        val changed = previousReceipt == null || previousReceipt.optString("status") != receipt.optString("status") ||
            previousReceipt.optString("reason") != receipt.optString("reason")
        return JSONObject().put("component", "PublicationValidator")
            .put("json_parse_status", if (parsed != null) "accepted" else "rejected")
            .put("artifact_schema_valid", schemaValid)
            .put("failure_phase", when {
                receipt.optString("status") == "recorded" -> "none"
                parsed == null -> "json_parsing"
                !schemaValid -> "artifact_schema"
                else -> "workspace_contract"
            }).put("reported_constraint", receipt.optString("reason"))
            .put("draft_preserved", true)
            .put("progress", JSONObject().put("has_previous_attempt", previous != null)
                .put("draft_changed", previous == null || previous.optString("raw_sha256") != AgentNativeJsonCodec.sha256(raw))
                .put("validator_feedback_changed", changed)
                .put("scientific_progress", "not_assessed_by_format_validator"))
            .put("observed_counts", JSONObject().apply {
                listOf("candidates", "findings", "memory", "workspace").forEach { key ->
                    parsed?.optJSONArray(key)?.let { put(key, it.length()) }
                }
            })
    }
}
