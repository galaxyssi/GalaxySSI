package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Never advance past a journal entry that was not delivered in full. */
internal object HealthCareVisitFollowUpObservation {
    fun compact(source: JSONObject, budget: Int, preserveReceipt: Boolean): String = runCatching {
        if (source.toString().length <= budget) return source.toString()
        val result = JSONObject(source.toString())
        if (!preserveReceipt) result.remove("_observation_receipt")
        if (result.toString().length <= budget) return result.toString()
        val rows = source.optJSONArray("items")
        if (rows == null) {
            result.remove("text"); result.put("field_done", false).put("next_offset", source.getInt("offset"))
                .put("error", "followup_chunk_not_delivered").put("retry_requires_larger_budget", true)
        } else {
            val shown = JSONArray()
            result.put("items", shown).put("done", false).put("truncated", true)
                .put("next", source.opt("page_start") ?: JSONObject.NULL)
            for (i in 0 until rows.length()) {
                val row = rows.getJSONObject(i)
                shown.put(row); result.put("next", row.getInt("revision"))
                if (result.toString().length > budget) { shown.remove(shown.length() - 1); break }
            }
            if (shown.length() > 0) {
                result.put("next", if (shown.length() == rows.length()) source.opt("next") ?: JSONObject.NULL
                    else shown.getJSONObject(shown.length() - 1).getInt("revision"))
                    .put("done", shown.length() == rows.length() && source.optBoolean("done"))
            } else if (rows.length() > 0) {
                val entry = rows.getJSONObject(0)
                result.put("next", source.opt("page_start") ?: JSONObject.NULL).put("error", "followup_entry_requires_chunks")
                    .put("entry_revision", entry.getInt("revision"))
                    .put("fields", JSONArray(HealthCareVisitFollowUpTool.fields.filter { entry.optString(it).isNotEmpty() }))
                    .put("kind", entry.getString("kind")).put("needs_review", entry.getBoolean("needs_review"))
                    .put("decision", entry.opt("decision") ?: JSONObject.NULL)
                    .put("source_review_required", entry.getBoolean("source_review_required"))
                    .put("resulting_state", entry.getString("resulting_state"))
            }
        }
        result.toString().takeIf { it.length <= budget } ?: failure(budget)
    }.getOrElse { failure(budget) }
    private fun failure(budget: Int) = "{\"error\":\"followup_not_delivered\",\"retry_requires_larger_budget\":true}"
        .takeIf { it.length <= budget } ?: if (budget >= 2) "{}" else ""
}
