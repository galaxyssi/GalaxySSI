package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Keep entire replies and resume after the last delivered row, never after a truncated answer. */
internal object HealthCareQuestionObservation {
    const val PROTOCOL = "galaxyssi.health-questions.v1"
    fun compact(source: JSONObject, budget: Int, preserveReceipt: Boolean): String { return runCatching {
        if (source.toString().length <= budget) return source.toString()
        val rows = source.getJSONArray("items")
        val shown = JSONArray()
        val result = JSONObject().put("protocol", PROTOCOL).put("items", shown)
            .put("question_version", source.getString("question_version"))
            .put("page_start", source.opt("page_start") ?: JSONObject.NULL)
            .put("next", source.opt("page_start") ?: JSONObject.NULL).put("done", false).put("truncated", true)
        source.optJSONObject("_observation_receipt")?.let { receipt -> result.put("_observation_receipt", if (preserveReceipt) receipt else
            JSONObject().apply { listOf("invocation_id", "tool_id", "status").forEach { put(it, receipt.optString(it)) } }) }
        for (i in 0 until rows.length()) {
            val row = rows.getJSONObject(i)
            shown.put(row); result.put("next", row.getString("id"))
            if (result.toString().length > budget) { shown.remove(shown.length() - 1); break }
        }
        if (shown.length() == 0 && rows.length() > 0) {
            result.remove("items"); result.put("next", source.opt("page_start") ?: JSONObject.NULL)
                .put("error", "question_not_delivered_context_budget").put("read_again", true)
                .put("retry_requires_larger_budget", true)
            if (!preserveReceipt) result.remove("_observation_receipt")
        } else {
            result.put("next", if (shown.length() == rows.length()) source.opt("next") ?: JSONObject.NULL
                else shown.getJSONObject(shown.length() - 1).getString("id"))
            result.put("done", shown.length() == rows.length() && source.optBoolean("done"))
        }
        result.toString().takeIf { it.length <= budget } ?: failure(budget)
    }.getOrElse { failure(budget) } }
    private fun failure(budget: Int) = "{\"error\":\"health_questions_not_delivered\",\"truncated\":true}".takeIf { it.length <= budget }
        ?: if (budget >= 2) "{}" else ""
}
