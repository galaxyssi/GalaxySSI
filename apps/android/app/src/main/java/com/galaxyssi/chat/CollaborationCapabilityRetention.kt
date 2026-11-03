package com.galaxyssi.chat

import java.math.BigDecimal
import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.LESSON
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.PLAN
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.RESULT
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text
import com.galaxyssi.chat.CollaborationEvolutionExperiment.decimal

/** Immutable task bank with original measured anchors, not a moving baseline that can slowly forget. */
internal object CollaborationCapabilityRetention {
    const val SUITE = "capability_suite"
    const val FIELD = "retention_suite"

    fun suite(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        text(value, "scope"); text(value, "limitations")
        val lesson = exact(value.getJSONObject("lesson"), setOf(LESSON))
        require(lesson.getJSONObject(HOST).getString("state") == "eligible_for_scoped_reuse") { "Protect an independently retained capability, not an unverified proposal" }
        CollaborationInnovationValidation.checkRecord(lesson, exact)
        val plan = exact(lesson.getJSONObject(HOST).getJSONObject("plan"), setOf(PLAN))
        val result = exact(lesson.getJSONObject(HOST).getJSONObject("result"), setOf(RESULT))
        val spec = plan.getJSONObject("body").getJSONObject(PLAN)
        val previous = value.optJSONObject("previous_suite")?.let { exact(it, setOf(SUITE)) }
        if (previous != null) require(CollaborationResearchCandidates.same(spec.getJSONObject(FIELD), previous)) {
            "Extend a bank only with an experiment that passed the exact previous bank"
        }
        val old = previous?.getJSONObject(HOST)?.getJSONArray("anchors")?.let { a ->
            (0 until a.length()).associate { a.getJSONObject(it).getString("id") to a.getJSONObject(it) }
        }.orEmpty()
        val measured = objects(result.getJSONObject(HOST), "cases").associateBy { it.getString("case_id") }
        val anchors = objects(spec, "cases").map { case ->
            val row = measured.getValue(case.getString("id"))
            require(row.getString("state") == "passed") { "Only fully measured passing cases can become protected capabilities" }
            val dataset = exact(case.getJSONObject("dataset"), setOf("artifact"))
            old[case.getString("id")] ?: JSONObject().put("id", case.getString("id"))
                .put("metric", case.getString("metric")).put("direction", case.getString("direction"))
                .put("dataset", CollaborationResearchCandidates.reference(dataset)).put("repetitions", case.getInt("repetitions"))
                .put("tolerance", decimal(case, "tolerance").toPlainString()).put("anchor", decimal(row, "candidate_mean").toPlainString())
                .put("source_result", CollaborationResearchCandidates.reference(result))
                .apply { if (case.getString("purpose") == "feasibility") put("threshold", decimal(case, "threshold").toPlainString()) }
        }
        require(anchors.map { it.getString("id") }.containsAll(old.keys)) { "A capability bank cannot drop previous cases" }
        return JSONObject().put("state", "protected_measured_cases").put("lesson", CollaborationResearchCandidates.reference(lesson))
            .put("environment", spec.getString("environment")).put("budget_unit", spec.getString("budget_unit"))
            .put("domain", lesson.getJSONObject(HOST).getString("domain")).put("anchors", JSONArray(anchors))
            .put("grants_permissions", false).apply { previous?.let { put("previous_suite", CollaborationResearchCandidates.reference(it)) } }
    }

    fun plan(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject? {
        if (!value.has(FIELD)) return null
        val ref = value.getJSONObject(FIELD)
        val suite = exact(ref, setOf(SUITE))
        CollaborationInnovationValidation.checkRecord(suite, exact)
        val host = suite.getJSONObject(HOST)
        val idea = exact(value.getJSONObject("innovation"), setOf(CollaborationEvolutionContract.IDEA))
        require(idea.getJSONObject("body").getJSONObject(CollaborationEvolutionContract.IDEA).getString("domain") == host.getString("domain")) {
            "Retention bank belongs to a different domain; validate transfer separately"
        }
        require(value.getString("environment") == host.getString("environment") && value.getString("budget_unit") == host.getString("budget_unit")) {
            "Retention environment/accounting changed; validate a separate scope instead of silently moving the baseline"
        }
        val cases = objects(value, "cases").associateBy { it.getString("id") }
        objects(host, "anchors").forEach { anchor ->
            val case = requireNotNull(cases[anchor.getString("id")]) { "Missing protected case: ${anchor.getString("id")}" }
            require(case.getString("purpose") == "regression" && case.getString("metric") == anchor.getString("metric") &&
                case.getString("direction") == anchor.getString("direction") &&
                CollaborationResearchCandidates.same(case.getJSONObject("dataset"), anchor.getJSONObject("dataset")) &&
                case.getInt("repetitions") >= anchor.getInt("repetitions") && decimal(case, "tolerance") <= decimal(anchor, "tolerance")) {
                "Protected case ${anchor.getString("id")} changed or weakened; preserve dataset, metric, direction, repetitions and tolerance"
            }
        }
        return CollaborationResearchCandidates.reference(suite)
    }

    fun passes(anchor: JSONObject, candidate: BigDecimal): Boolean {
        val maximize = anchor.getString("direction") == "maximize"
        val retained = if (maximize) candidate >= decimal(anchor, "anchor") - decimal(anchor, "tolerance")
            else candidate <= decimal(anchor, "anchor") + decimal(anchor, "tolerance")
        val feasible = !anchor.has("threshold") || if (maximize) candidate >= decimal(anchor, "threshold") else candidate <= decimal(anchor, "threshold")
        return retained && feasible
    }
}
