package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Developer-authored data and corrections, never evidence of autonomous learning. */
internal object CollaborationNumericFeedbackFixture {
    const val SQUARE = """{"op":"mul","args":[{"variable":"x"},{"variable":"x"}]}"""
    fun raw(id: String, count: Int = 120, model: String = """{"constant":0}""", previous: JSONObject? = null): String {
        val cases = JSONArray()
        repeat(count) { index ->
            val x = index - count / 2
            cases.put(JSONObject().put("id", "case-$index").put("input", JSONObject().put("x", x))
                .put("expected", x.toLong() * x).put("absolute_tolerance", 0))
        }
        val value = JSONObject().put("purpose", "Synthetic numeric feedback integration")
            .put("reference_basis", "Developer-authored squares, not external observations")
            .put("limitations", "Fixture only, no capability gain")
            .put("validator", JSONObject().put("id", "numeric_model_cases.v1").put("variables", JSONArray().put("x")).put("cases", cases))
            .put("computation", JSONObject().put("validator_id", "numeric_model_cases.v1").put("model", JSONObject(model)))
        previous?.let { value.put("previous_trial", it) }
        val item = JSONObject().put("id", id).put("kind", CollaborationNumericModelTrial.KIND).put("title", id)
            .put("body", JSONObject().put("content", "Synthetic trial").put(CollaborationNumericModelTrial.KIND, value))
            .put("parents", JSONArray().apply { previous?.let(::put) })
        return JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Synthetic host replay")
            .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(item)).toString()
    }
    fun input(ref: JSONObject, filter: String = "failed", cursor: String = "") = mapOf(
        "mode" to CollaborationNumericFeedback.MODE, "object_id" to ref.getString("object_id"),
        "revision" to ref.getInt("revision"), "sha256" to ref.getString("sha256"), "case_filter" to filter, "cursor" to cursor)
}
