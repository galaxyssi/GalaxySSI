package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Trimming an observation must advance only past measurements actually delivered to the model. */
internal object HealthCareHistoryObservation {
    const val PROTOCOL = "galaxyssi.health-history.v1"
    fun compact(value: String, budget: Int, preserveReceipt: Boolean = false): String? {
        val source = runCatching { JSONObject(value) }.getOrNull() ?: return null
        if (source.optString("protocol") != PROTOCOL) return null
        return runCatching { compactSource(source, budget, preserveReceipt) }.getOrElse {
            failure("invalid_health_history_observation", budget)
        }
    }
    private fun failure(code: String, budget: Int): String = JSONObject().put("error", code).put("truncated", true)
        .toString().takeIf { it.length <= budget } ?: if (budget >= 2) "{}" else ""
    private fun compactSource(source: JSONObject, budget: Int, preserveReceipt: Boolean): String {
        if (source.toString().length <= budget) return source.toString()
        val rows = source.optJSONObject("history")?.optJSONArray("samples") ?: JSONArray()
        val shown = JSONArray()
        val history = JSONObject().put("samples", shown).put("has_earlier", true).put("stability_verified", false)
        val out = JSONObject().put("protocol", PROTOCOL).put("input_version", source.getString("input_version"))
            .put("metric", source.getString("metric")).put("page_start", source.opt("page_start") ?: JSONObject.NULL)
            .put("history", history).put("done", false).put("truncated", true).put("stability_verified", false)
        source.optJSONObject("_observation_receipt")?.let { receipt -> out.put("_observation_receipt", if (preserveReceipt) receipt else
            JSONObject().apply { listOf("invocation_id", "tool_id", "status").forEach { put(it, receipt.optString(it)) } }) }
        fun next(sample: JSONObject) = JSONObject().put("before_time", sample.getLong("measured_at"))
            .put("before_id", sample.getJSONObject("record").getString("id"))
        for (i in 0 until rows.length()) {
            val row = rows.getJSONObject(i)
            shown.put(row); out.put("next", next(row))
            if (out.toString().length > budget) { shown.remove(shown.length() - 1); break }
        }
        if (shown.length() > 0) {
            out.put("next", next(shown.getJSONObject(shown.length() - 1)))
            if (shown.length() == rows.length()) {
                out.put("next", source.opt("next") ?: JSONObject.NULL).put("done", source.optBoolean("done"))
                history.put("has_earlier", !source.optBoolean("done"))
            }
            return out.toString().takeIf { it.length <= budget } ?: failure("health_history_not_delivered", budget)
        }
        // Do not advance the source cursor when not even one complete row fits.
        out.remove("history"); out.put("next", source.opt("page_start") ?: JSONObject.NULL)
        out.put("error", "history_not_delivered_context_budget").put("read_again", true)
        if (!preserveReceipt) out.remove("_observation_receipt")
        return out.toString().takeIf { it.length <= budget } ?: failure("health_history_not_delivered", budget)
    }
}
