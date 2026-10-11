package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.PLAN
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.RESULT
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.LESSON

/** On-demand links to existing immutable comparisons, including negative results. */
internal object CollaborationMethodEvaluations {
    const val VIEW = "evaluations"
    const val TRUST = "host_registered_method_evaluations_not_current_applicability"
    const val SCAN_PAGE = 100
    const val RESULT_PAGE = 12
    private val kinds = setOf(PLAN, RESULT, LESSON)
    const val INSTRUCTIONS = "For a workflow method, mode=method_history with view=evaluations and exact object_id/revision/sha256 " +
        "finds registered comparisons and reviews, including inconclusive, regressed, rejected and earlier experiments. " +
        "Follow next_cursor even after an empty page; read_original opens full workspace records. Compare the original conditions, " +
        "measurements and counterevidence before reusing, revising or rejecting a method. A completed execution is not measured benefit. " +
        "No matching records means unknown evaluated history, not effectiveness. This recall neither adopts a method nor proves causality."

    fun selector(method: JSONObject) = CollaborationResearchCandidates.reference(method)
        .put("mode", "method_history").put("view", VIEW)

    fun page(rows: CollaborationWorkspaceRows, root: String, access: CollaborationWorkspaceAccess,
             method: JSONObject, cursor: String, read: (String, Int) -> JSONObject?): JSONObject {
        val prefix = root + "evolution:"
        val scope = AgentNativeJsonCodec.sha256(JSONArray().put(VIEW).put(access.groupId).put(access.runId).put(access.turnId)
            .put(access.round).put(access.nodeId).put(access.personId).put(JSONArray(access.dependencyNodes.sorted()))
            .put(JSONArray(access.pinnedReads.sorted())).put(method.getString("object_id")).put(method.getInt("revision"))
            .put(method.getString("sha256")).toString())
        require(cursor.length <= 512) { "Method evaluation cursor is too long" }
        val after = if (cursor.isBlank()) "" else {
            val value = runCatching { JSONObject(cursor) }.getOrElse { throw IllegalArgumentException("Invalid method evaluation cursor") }
            require(value.optString("scope") == scope) { "Method or assignment changed; restart without cursor" }
            value.getString("after").also {
                require(it.startsWith(prefix) && it.removePrefix(prefix).matches(Regex("[a-f0-9]{64}"))) {
                    "Invalid method evaluation cursor"
                }
            }
        }
        val keys = rows.page(prefix, after, SCAN_PAGE + 1)
        val records = mutableListOf<JSONObject>()
        val cache = mutableMapOf<Pair<String, Int>, JSONObject?>()
        fun exact(ref: JSONObject, kind: String): JSONObject? {
            val key = ref.getString("object_id") to ref.getInt("revision")
            if (!cache.containsKey(key)) cache[key] = read(key.first, key.second)
            return cache[key]?.takeIf { it.optString("kind") == kind && CollaborationResearchCandidates.same(it, ref) }
        }
        var processed = 0
        for (key in keys.take(SCAN_PAGE)) {
            processed++
            val stored = rows.read(root + "head:" + key.removePrefix(prefix))?.let(::JSONObject) ?: continue
            if (stored.optString("kind") !in kinds || !access.canRead(stored)) continue
            val saved = exact(stored, stored.getString("kind")) ?: continue
            require(saved.toString() == stored.toString()) { "Method evaluation integrity check failed" }
            match(method, saved, ::exact)?.let(records::add)
            if (records.size == RESULT_PAGE) break
        }
        val next = if (processed < keys.size) JSONObject().put("scope", scope).put("after", keys[processed - 1]).toString() else null
        return JSONObject().put("method", CollaborationResearchCandidates.reference(method)).put("view", VIEW)
            .put("trust", TRUST)
            .put("records", JSONArray(records)).put("next_cursor", next ?: JSONObject.NULL).put("scan_complete", next == null)
            .put("snapshot", false).put("coverage", "visible_registered_workflow_comparisons")
            .put("order", "storage_key_not_chronological_or_ranked").put("quality_effect", JSONObject.NULL)
            .put("automatically_adopted", false).put("causality_proven", false)
            .put("guidance", INSTRUCTIONS + " Multiple records may belong to one experiment; do not count them as independent trials. " +
                "This is not a snapshot; rerun without cursor to include concurrent publications. Historical outcomes do not authorize current reuse.")
    }

    private fun match(method: JSONObject, saved: JSONObject, exact: (JSONObject, String) -> JSONObject?): JSONObject? {
        val host = saved.optJSONObject(HOST) ?: return null
        val result = when (saved.getString("kind")) {
            RESULT -> saved
            LESSON -> host.optJSONObject("result")?.let { exact(it, RESULT) } ?: return null
            else -> null
        }
        val plan = if (saved.getString("kind") == PLAN) saved else
            result?.getJSONObject(HOST)?.optJSONObject("plan")?.let { exact(it, PLAN) } ?: return null
        val binding = plan.getJSONObject(HOST).optJSONObject(CollaborationWorkflowMethod.COMPARISON) ?: return null
        val before = exact(binding.getJSONObject("baseline_method"), CollaborationWorkflowMethod.KIND) ?: return null
        val after = exact(binding.getJSONObject("candidate_method"), CollaborationWorkflowMethod.KIND) ?: return null
        val variant = when {
            CollaborationResearchCandidates.same(method, before) -> "baseline"
            CollaborationResearchCandidates.same(method, after) -> "candidate"
            else -> return null
        }
        val dataset = exact(binding.getJSONObject("dataset"), "artifact") ?: return null
        val spec = plan.getJSONObject("body").getJSONObject(PLAN)
        val details = spec.getJSONObject(CollaborationWorkflowMethod.COMPARISON)
        val excerpts = JSONObject()
        val truncated = JSONArray()
        fun excerpt(name: String, value: String) {
            excerpts.put(name, value.take(240))
            if (value.length > 240) truncated.put(name)
        }
        excerpt("environment", spec.getString("environment"))
        listOf("controlled_conditions", "quality_oracle", "cost_accounting", "selection_bias").forEach { excerpt(it, details.getString(it)) }
        val out = CollaborationResearchCandidates.reference(saved).put("kind", saved.getString("kind"))
            .put("title", saved.optString("title").take(160)).put("recorded_at", saved.getLong("recorded_at"))
            .put("method_variant", variant).put("reported_state", host.getString("state"))
            .put("plan", CollaborationResearchCandidates.reference(plan)).put("dataset", CollaborationResearchCandidates.reference(dataset))
            .put("baseline_method", CollaborationResearchCandidates.reference(before)).put("candidate_method", CollaborationResearchCandidates.reference(after))
            .put("read_original", CollaborationResearchCandidates.reference(saved).put("mode", "workspace"))
            .put("excerpts", excerpts).put("truncated_fields", truncated).put("complete_read", false)
            .put("current_applicability_verified", false)
        result?.let {
            val evaluated = it.getJSONObject(HOST)
            val cases = evaluated.getJSONArray("cases")
            val states = (0 until cases.length()).map { index -> cases.getJSONObject(index).getString("state") }.groupingBy { it }.eachCount()
            out.put("result", CollaborationResearchCandidates.reference(it)).put("measured_state", evaluated.getString("state"))
                .put("case_count", cases.length()).put("case_states", JSONObject(states))
                .put("measurement_meaning", "arithmetic_on_observed_reports_not_independent_scientific_validation")
        }
        if (saved.getString("kind") == LESSON) {
            val lesson = saved.getJSONObject("body").getJSONObject(LESSON)
            out.put("review_decision", lesson.getString("decision"))
            listOf("rationale", "applies_when", "avoid_when").forEach { excerpt(it, lesson.getString(it)) }
        }
        return out
    }
}
