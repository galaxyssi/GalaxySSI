package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** A bounded observation resumes after the last complete entry, including a scope-redacted entry. */
internal object HealthCareFeedbackObservation {
    const val PROTOCOL = "galaxyssi.health-feedback.v1"
    fun compact(source: JSONObject, budget: Int, preserveReceipt: Boolean): String = runCatching {
        if (source.toString().length <= budget) return source.toString()
        val rows = source.getJSONArray("items")
        val shown = JSONArray()
        val result = JSONObject().put("protocol", PROTOCOL).put("items", shown)
            .put("input_version", source.getString("input_version")).put("revision", source.getInt("revision"))
            .put("page_start", source.opt("page_start") ?: JSONObject.NULL)
            .put("next", source.opt("page_start") ?: JSONObject.NULL).put("done", false).put("truncated", true)
            .put("health_improvement_verified", false)
        source.optJSONObject("_observation_receipt")?.let { receipt -> result.put("_observation_receipt", if (preserveReceipt) receipt else
            JSONObject().apply { listOf("invocation_id", "tool_id", "status").forEach { put(it, receipt.optString(it)) } }) }
        for (i in 0 until rows.length()) {
            val row = rows.getJSONObject(i)
            shown.put(row); result.put("next", row.getInt("revision"))
            if (result.toString().length > budget) { shown.remove(shown.length() - 1); break }
        }
        if (shown.length() == 0 && rows.length() > 0) {
            result.remove("items"); result.put("next", source.opt("page_start") ?: JSONObject.NULL)
                .put("error", "feedback_not_delivered_context_budget").put("read_again", true)
                .put("retry_requires_larger_budget", true)
            if (!preserveReceipt) result.remove("_observation_receipt")
        } else {
            result.put("next", if (shown.length() == rows.length()) source.opt("next") ?: JSONObject.NULL
                else shown.getJSONObject(shown.length() - 1).getInt("revision"))
            result.put("done", shown.length() == rows.length() && source.optBoolean("done"))
        }
        result.toString().takeIf { it.length <= budget } ?: failure(budget)
    }.getOrElse { failure(budget) }
    private fun failure(budget: Int) = "{\"error\":\"health_feedback_not_delivered\",\"truncated\":true}".takeIf { it.length <= budget }
        ?: if (budget >= 2) "{}" else ""
}
