package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.IDEA
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.PLAN
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.RESULT
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.strings
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** Novelty is a scoped judgment; feasibility and value require preregistered observed measurements. */
internal object CollaborationInnovationValidation {
    const val OPPORTUNITY = "innovation_opportunity"
    const val ASSESSMENT = "innovation_assessment"
    private val SOURCE_KINDS = setOf("artifact", "evidence", "counterexample", "proposal", "question", IDEA, RESULT, ASSESSMENT,
        CollaborationEvolutionContract.GAP, CollaborationCapabilityDiagnosis.DIAGNOSIS, CollaborationCapabilityDiagnosis.PROBE,
        CollaborationProceduralMemory.FAILURE, CollaborationTransferStudy.KIND) + CollaborationTeamInvention.KINDS + CollaborationActionPrediction.KINDS

    fun opportunity(value: JSONObject, revision: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject,
                    coverage: (JSONObject) -> Unit): JSONObject {
        require(text(value, "goal_sha256").matches(Regex("[a-f0-9]{64}"))) { "Copy the original host goal_sha256" }
        listOf("criterion_id", "requirement", "question", "unmet_need", "expected_benefit", "constraints", "null_hypothesis",
            "discriminating_test", "uncertainty").forEach { text(value, it) }
        strings(value, "alternative_routes")
        val drivers = objects(value, "drivers")
        require(drivers.map { text(it, "id") }.distinct().size == drivers.size) { "Innovation driver IDs must be distinct" }
        val sources = linkedMapOf<String, JSONObject>()
        drivers.forEach { driver ->
            val kind = text(driver, "kind")
            require(kind in setOf("knowledge_gap", "contradiction", "limitation", "cross_domain")) { "Unknown innovation driver" }
            text(driver, "why"); text(driver, "what_would_change")
            val refs = objects(driver, "sources").map { ref -> exact(ref, SOURCE_KINDS).also { saved ->
                sources[saved.getString("object_id")] = CollaborationResearchCandidates.reference(saved)
            } }
            if (kind == "knowledge_gap") require(refs.any { it.getString("kind") in setOf(
                    CollaborationEvolutionContract.GAP, CollaborationCapabilityDiagnosis.DIAGNOSIS) }) { "Knowledge-gap innovation needs a preserved gap or diagnosis" }
            if (kind == "contradiction") { text(driver, "claim_a"); text(driver, "claim_b") }
            if (kind == "cross_domain") require(refs.any { it.getString("kind") == CollaborationTransferStudy.KIND }) {
                "Cross-domain innovation needs an explicit transfer study"
            }
            refs.filter { it.getString("kind") == CollaborationTransferStudy.KIND }.forEach {
                CollaborationTransferStudy.current(CollaborationResearchCandidates.reference(it), exact)
            }
        }
        if (revision.getJSONArray("host_observations").length() > 0) coverage(revision)
        return JSONObject().put("state", "opportunity_hypothesis").put("basis", JSONArray(sources.values.toList()))
            .put("goal_sha256", value.getString("goal_sha256")).put("criterion_id", value.getString("criterion_id"))
            .put("goal_binding", "declared_until_work_admission").put("claims_verified", false)
    }

    fun currentOpportunity(ref: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        val record = exact(ref, setOf(OPPORTUNITY))
        checkRecord(record, exact)
        return record
    }

    fun idea(value: JSONObject, revision: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject? {
        val ref = value.optJSONObject(OPPORTUNITY) ?: return null
        val opportunity = currentOpportunity(ref, exact)
        require(objects(revision, "parents").any { CollaborationResearchCandidates.same(opportunity, it) }) {
            "Preserve the exact innovation opportunity as a parent"
        }
        return CollaborationResearchCandidates.reference(opportunity)
    }

    fun currentIdea(record: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject) {
        checkRecord(record, exact)
    }

    fun assessment(value: JSONObject, revision: JSONObject, person: String, exact: (JSONObject, Set<String>) -> JSONObject,
                   original: (JSONObject) -> JSONObject?, coverage: (JSONObject) -> Unit): JSONObject {
        val idea = exact(value.getJSONObject("innovation"), setOf(IDEA))
        currentIdea(idea, exact)
        val opportunity = currentOpportunity(idea.getJSONObject("body").getJSONObject(IDEA).getJSONObject(OPPORTUNITY), exact)
        listOf("rationale", "feasibility_scope", "value_scope", "limitations", "next_action").forEach { text(value, it) }
        val decision = text(value, "decision")
        require(decision in setOf("continue", "revise", "reject", "retain")) { "Unknown innovation assessment decision" }
        val blockers = value.getJSONArray("unresolved")
        repeat(blockers.length()) { require(blockers.opt(it) is String && blockers.getString(it).isNotBlank()) { "Unresolved issues must be named" } }
        val observations = revision.getJSONArray("host_observations")
        fun cited(ref: JSONObject): JSONObject {
            require((0 until observations.length()).any { i -> observations.getJSONObject(i).let {
                it.optString("evidence_id") == ref.optString("evidence_id") && it.optString("sha256") == ref.optString("sha256")
            } }) { "Assessment must cite every original novelty/experiment observation" }
            return requireNotNull(original(ref)) { "Original innovation evidence is unavailable or isolated" }
        }
        if (observations.length() > 0) coverage(revision)
        val novelty = value.getJSONObject("novelty")
        val noveltyClaim = text(novelty, "outcome")
        require(noveltyClaim in setOf("unassessed", "known", "distinguished_in_searched_scope", "inconclusive")) {
            "Novelty cannot be globally certified; use a scoped assessment"
        }
        listOf("search_scope", "coverage_gaps", "rationale").forEach { text(novelty, it) }
        val closest = novelty.getJSONArray("closest_work")
        require(noveltyClaim !in setOf("known", "distinguished_in_searched_scope") || closest.length() > 0) {
            "A scoped novelty judgment needs actual closest-work observations, not an empty search claim"
        }
        repeat(closest.length()) { index ->
            val comparison = closest.getJSONObject(index)
            listOf("overlap", "difference", "significance").forEach { text(comparison, it) }
            val observed = cited(comparison.getJSONObject("observation"))
            require(observed.getString("status") == "returned" && observed.getString("observation_kind") == "tool_output_recorded" &&
                !observed.getString("tool").contains("recall", true)) { "Novelty needs returned original sources, not peer/recall claims" }
        }
        val authors = mutableSetOf(idea.getString("person_id"), opportunity.getString("person_id"))
        idea.getJSONObject(HOST).optJSONArray("contributors")?.let { a -> repeat(a.length()) { authors += a.getString(it) } }
        val results = value.getJSONArray("results")
        val savedResults = JSONArray()
        val feasibility = mutableListOf<Boolean>()
        val valueChecks = mutableListOf<Boolean>()
        val unique = hashSetOf<String>()
        repeat(results.length()) { index ->
            val result = exact(results.getJSONObject(index), setOf(RESULT))
            require(unique.add(result.getString("object_id"))) { "Do not count the same result twice" }
            val host = result.getJSONObject(HOST)
            require(CollaborationResearchCandidates.same(idea, host.getJSONObject("innovation"))) { "Assessment result belongs to another idea or revision" }
            val plan = exact(host.getJSONObject("plan"), setOf(PLAN))
            val baseline = exact(host.getJSONObject("baseline"), setOf("artifact", "proposal", IDEA))
            for (authoringRecord in listOf(plan, baseline)) {
                authors += authoringRecord.getString("person_id")
                authoringRecord.optJSONObject(HOST)?.optJSONArray("contributors")?.let { a -> repeat(a.length()) { authors += a.getString(it) } }
            }
            host.getJSONArray("trial_authors").let { a -> repeat(a.length()) { authors += a.getString(it) } }
            val refs = result.getJSONArray("host_observations")
            repeat(refs.length()) { cited(refs.getJSONObject(it)) }
            val cases = objects(plan.getJSONObject("body").getJSONObject(PLAN), "cases").associateBy { it.getString("id") }
            objects(host, "cases").forEach { check ->
                val case = cases.getValue(check.getString("case_id"))
                if (case.getString("purpose") == "feasibility") feasibility += check.getString("state") == "passed" &&
                    host.getString("state") in setOf("measured_improvement", "feasibility_measured", "improved_without_regression_suite") &&
                    host.optBoolean("targets_current_at_publication", true)
                if (case.getString("purpose") == "target" && case.optString("dimension") == "value")
                    valueChecks += check.getString("state") == "passed" && host.getBoolean("eligible_for_retention")
            }
            savedResults.put(CollaborationResearchCandidates.reference(result))
        }
        val feasible = feasibility.isNotEmpty() && feasibility.all { it }
        val useful = valueChecks.isNotEmpty() && valueChecks.all { it }
        val independent = person !in authors
        if (decision == "retain") require(feasible && useful && independent && blockers.length() == 0 &&
            noveltyClaim == "distinguished_in_searched_scope") {
            "Innovation retention needs scoped novelty evidence, passed feasibility thresholds, measured value with regressions, independent review and no unresolved blockers"
        }
        return JSONObject().put("state", if (decision == "retain") "eligible_for_scoped_innovation_use" else decision)
            .put("innovation", CollaborationResearchCandidates.reference(idea)).put(OPPORTUNITY, CollaborationResearchCandidates.reference(opportunity))
            .put("results", savedResults).put("novelty", noveltyClaim).put("novelty_certified", false)
            .put("feasibility_measured", feasible).put("value_measured", useful).put("independent_review", independent)
            .put("meaning", "scoped_evidence_review_not_global_novelty_or_goal_acceptance")
            .apply { if (decision == "retain") CollaborationTeamInvention.retention(value, idea, exact)
                ?.let { put(CollaborationTeamInvention.EVALUATION, it) } }
    }

    fun currentAssessment(ref: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        val record = exact(ref, setOf(ASSESSMENT))
        checkRecord(record, exact)
        return record
    }

    fun retention(value: JSONObject, idea: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject? {
        if (!idea.getJSONObject("body").getJSONObject(IDEA).has(OPPORTUNITY)) return null
        val assessment = currentAssessment(value.getJSONObject(ASSESSMENT), exact)
        require(assessment.getJSONObject(HOST).getString("state") == "eligible_for_scoped_innovation_use" &&
            CollaborationResearchCandidates.same(idea, assessment.getJSONObject(HOST).getJSONObject("innovation"))) {
            "Retain an opportunity-driven method only after its exact innovation assessment passes"
        }
        return CollaborationResearchCandidates.reference(assessment)
    }

    fun checkRecord(record: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject) {
        // Mixed innovation/transfer ancestry can be deep; visit each exact version without recursive stack growth.
        val pending = ArrayDeque<JSONObject>().apply { add(record) }
        val seen = hashSetOf<String>()
        val links = mapOf("innovation" to setOf(IDEA), "plan" to setOf(PLAN), "result" to setOf(RESULT),
            "baseline" to setOf("artifact", "proposal", IDEA), "rollback" to setOf("artifact", "proposal", IDEA),
            "lesson" to setOf(CollaborationEvolutionContract.LESSON),
            OPPORTUNITY to setOf(OPPORTUNITY), ASSESSMENT to setOf(ASSESSMENT), CollaborationTransferStudy.KIND to setOf(CollaborationTransferStudy.KIND),
            "challenge" to setOf(CollaborationTeamInvention.EXCHANGE), CollaborationTeamInvention.SYNTHESIS to setOf(CollaborationTeamInvention.SYNTHESIS),
            CollaborationTeamInvention.EVALUATION to setOf(CollaborationTeamInvention.EVALUATION),
            CollaborationActionPrediction.MODEL to setOf(CollaborationActionPrediction.MODEL),
            CollaborationActionPrediction.FORECAST to setOf(CollaborationActionPrediction.FORECAST),
            CollaborationExecutableTool.TOOL to setOf(CollaborationExecutableTool.TOOL),
            CollaborationExecutableTool.TEST to setOf(CollaborationExecutableTool.TEST),
            CollaborationExecutableTool.RELEASE to setOf(CollaborationExecutableTool.RELEASE),
            CollaborationWorkflowMethod.KIND to setOf(CollaborationWorkflowMethod.KIND),
            CollaborationCapabilityRetention.FIELD to setOf(CollaborationCapabilityRetention.SUITE),
            "previous_suite" to setOf(CollaborationCapabilityRetention.SUITE),
            "suite" to setOf(CollaborationCapabilityRetention.SUITE),
            CollaborationSelfResearch.CYCLE to setOf(CollaborationSelfResearch.CYCLE),
            "previous_method" to setOf(CollaborationWorkflowMethod.KIND),
            "baseline_method" to setOf(CollaborationWorkflowMethod.KIND),
            "candidate_method" to setOf(CollaborationWorkflowMethod.KIND))
        fun enqueue(ref: JSONObject, kinds: Set<String>) { pending.add(exact(ref, kinds)) }
        while (pending.isNotEmpty()) {
            val saved = pending.removeFirst()
            if (!seen.add(saved.getString("object_id") + ":" + saved.getString("sha256"))) continue
            val host = saved.optJSONObject(HOST) ?: continue
            links.forEach { (field, kinds) -> host.optJSONObject(field)?.let { enqueue(it, kinds) } }
            if (saved.getString("kind") == CollaborationSelfResearch.CYCLE) {
                enqueue(host.getJSONObject("opportunity"), setOf(OPPORTUNITY))
                enqueue(host.getJSONObject("diagnosis"), setOf(CollaborationCapabilityDiagnosis.DIAGNOSIS))
                enqueue(host.getJSONObject("gap"), setOf(CollaborationEvolutionContract.GAP))
                enqueue(host.getJSONObject("agenda"), setOf(CollaborationLearningAgenda.KIND))
            }
            if (saved.getString("kind") == PLAN) objects(saved.getJSONObject("body").getJSONObject(PLAN), "cases").forEach {
                it.optJSONObject("dataset")?.let { ref -> enqueue(ref, setOf("artifact")) }
            }
            if (saved.getString("kind") == CollaborationWorkflowMethod.KIND) host.optJSONArray("feedback")?.let { refs ->
                repeat(refs.length()) { enqueue(refs.getJSONObject(it), setOf("artifact", "experiment_result", "capability_diagnosis", "failure_experience", "prediction_outcome")) }
            }
            host.optJSONObject(CollaborationWorkflowMethod.COMPARISON)?.let { binding ->
                listOf("baseline_method", "candidate_method").forEach { enqueue(binding.getJSONObject(it), setOf(CollaborationWorkflowMethod.KIND)) }
                enqueue(binding.getJSONObject("dataset"), setOf("artifact"))
            }
            host.optJSONObject(CollaborationHypothesisTest.FIELD)?.optJSONObject(CollaborationHypothesisTest.PREVIOUS)?.let {
                enqueue(it, setOf(CollaborationActionPrediction.OUTCOME))
            }
            for ((field, kinds) in listOf("basis" to SOURCE_KINDS, "results" to setOf(RESULT), "calibration_data" to setOf("artifact"),
                "prediction_feedback" to setOf(CollaborationActionPrediction.OUTCOME))) {
                host.optJSONArray(field)?.let { refs -> repeat(refs.length()) { enqueue(refs.getJSONObject(it), kinds) } }
            }
            if (saved.getString("kind") == CollaborationTransferStudy.KIND) enqueue(saved.getJSONObject("body")
                .getJSONObject(CollaborationTransferStudy.KIND).getJSONObject("source"), setOf(CollaborationProceduralMemory.SKILL, CollaborationProceduralMemory.FAILURE))
            if (saved.getString("kind") == PLAN && host.has(CollaborationTransferStudy.KIND))
                objects(saved.getJSONObject("body").getJSONObject(PLAN), "cases").forEach { enqueue(it.getJSONObject("dataset"), setOf("artifact")) }
            host.optJSONObject(CollaborationTeamComparison.FIELD)?.let { comparison ->
                comparison.optJSONObject("single_agent")?.let { enqueue(it, setOf("artifact", "proposal", IDEA)) }
                comparison.optJSONObject(CollaborationTeamInvention.SYNTHESIS)?.let { enqueue(it, setOf(CollaborationTeamInvention.SYNTHESIS)) }
                comparison.optJSONArray("datasets")?.let { a -> repeat(a.length()) { enqueue(a.getJSONObject(it), setOf("artifact")) } }
            }
        }
    }
}
