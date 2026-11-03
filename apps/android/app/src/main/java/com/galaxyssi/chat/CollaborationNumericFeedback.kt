package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Compact delivery is a projection; the immutable trial remains the source of every case. */
internal object CollaborationNumericFeedback {
    const val MODE = "numeric_cases"
    private const val PAGE_SIZE = 8_000
    private val changes = listOf("improved", "regressed", "error_reduced", "error_increased", "domain_recovered", "domain_failed")
    val filters = listOf("failed", "all", "domain_error") + changes

    fun summary(host: JSONObject): JSONObject = JSONObject(host.toString()).apply {
        getJSONObject("evaluation").apply {
            remove("checks")
            put("case_details_omitted", true)
        }
        optJSONObject("comparison")?.let { comparison ->
            changes.forEach { change ->
                val key = "${change}_case_ids"
                comparison.optJSONArray(key)?.let { comparison.put("${change}_case_count", it.length()); comparison.remove(key) }
            }
            comparison.put("case_ids_omitted", true)
        }
        put("case_feedback", JSONObject().put("mode", MODE).put("case_filter", "failed").put("cursor", "")
            .put("reference", "Use this revision's exact object_id, revision and sha256; keep the same case_filter while paging."))
    }

    fun page(record: JSONObject, input: Map<String, Any?>): JSONObject {
        require(input.keys.all { it in setOf("mode", "object_id", "revision", "sha256", "case_filter", "cursor") }) {
            "Numeric feedback accepts an exact trial reference, case_filter and cursor only"
        }
        require(input["mode"] == MODE && record.getString("kind") == CollaborationNumericModelTrial.KIND) {
            "Numeric feedback requires a saved numeric_model_trial"
        }
        val revision = input["revision"]
        require(input["object_id"] == record.getString("object_id") && input["sha256"] == record.getString("sha256") &&
            revision is Number && revision.toDouble() == record.getInt("revision").toDouble()) {
            "Numeric feedback requires the exact object_id, revision and sha256"
        }
        val filter = input["case_filter"] ?: "failed"
        require(filter is String && filter in filters) { "Unknown numeric case_filter; use ${filters.joinToString()}" }
        val cursor = input["cursor"] ?: ""
        require(cursor is String && cursor.length <= 512) { "Invalid numeric feedback cursor" }
        val hash = record.getString("sha256")
        val offset = if (cursor.isEmpty()) 0 else {
            val saved = runCatching { JSONObject(cursor) }.getOrElse { throw IllegalArgumentException("Invalid numeric feedback cursor", it) }
            require(saved.keys().asSequence().toSet() == setOf("sha256", "case_filter", "offset") &&
                saved.opt("sha256") == hash && saved.opt("case_filter") == filter) { "Numeric feedback cursor belongs to another trial or filter" }
            val position = saved.opt("offset")
            require(position is Number && position.toDouble() == position.toInt().toDouble() && position.toInt() > 0) {
                "Invalid numeric feedback cursor offset"
            }
            position.toInt()
        }
        val host = record.getJSONObject(CollaborationEvolutionContract.HOST)
        val evaluation = host.getJSONObject("evaluation")
        val checks = evaluation.getJSONArray("checks")
        val cases = record.getJSONObject("body").getJSONObject(CollaborationNumericModelTrial.KIND)
            .getJSONObject("validator").getJSONArray("cases")
        require(cases.length() == checks.length()) { "Numeric trial case coverage changed" }
        val comparison = host.optJSONObject("comparison")
        val changedIds = changes.associateWith { change ->
            comparison?.optJSONArray("${change}_case_ids")?.let { ids -> (0 until ids.length()).map(ids::getString).toSet() } ?: emptySet()
        }
        val selected = JSONArray()
        repeat(cases.length()) { index ->
            val case = cases.getJSONObject(index)
            val check = checks.getJSONObject(index)
            require(case.getString("id") == check.getString("id")) { "Numeric trial case order changed" }
            val id = check.getString("id")
            val include = when (filter) {
                "all" -> true
                "failed" -> !check.getBoolean("passed")
                "domain_error" -> check.has("error")
                else -> id in changedIds.getValue(filter)
            }
            if (include) selected.put(JSONObject(case.toString()).put("observed", JSONObject(check.toString()))
                .put("changes", JSONArray(changes.filter { id in changedIds.getValue(it) })))
        }
        val content = JSONObject().put("cases", selected).toString()
        require(offset == 0 || offset < content.length) { "Numeric feedback cursor exceeds this projection" }
        var end = minOf(content.length, offset + PAGE_SIZE)
        if (end < content.length && content[end - 1].isHighSurrogate() && content[end].isLowSurrogate()) end--
        val next = if (end < content.length) JSONObject().put("sha256", hash).put("case_filter", filter).put("offset", end).toString() else JSONObject.NULL
        return JSONObject().put("content", content.substring(offset, end)).put("total_characters", content.length)
            .put("next_cursor", next).put("case_filter", filter).put("matched_case_count", selected.length())
            .put("case_count", cases.length()).put("source_reference", CollaborationResearchCandidates.reference(record))
            .put("spec_sha256", evaluation.getString("spec_sha256")).put("model_sha256", evaluation.getString("model_sha256"))
            .put("has_comparison", comparison != null)
            .put("trust", "host_numeric_replay_projection_not_independent_reference_truth_or_generalization")
            .put("read_guidance", "Concatenate content pages in cursor order to decode cases. Follow next_cursor until null. " +
                "Use mode=workspace for the full immutable trial and model. This projection does not certify evidence comprehension.")
    }
}
