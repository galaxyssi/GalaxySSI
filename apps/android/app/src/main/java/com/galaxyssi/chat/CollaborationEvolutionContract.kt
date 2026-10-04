package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Typed learning records share the existing scoped, immutable workspace and evidence ledger. */
internal class CollaborationEvolutionContract(
    private val access: CollaborationWorkspaceAccess,
    private val read: (String, Int) -> JSONObject?,
    private val current: (String, Int) -> Boolean,
    private val changingIds: Set<String>,
    private val original: (JSONObject) -> JSONObject?,
    private val coverage: (JSONObject) -> Unit
) {
    fun validate(head: JSONObject?, revision: JSONObject) {
        val kind = revision.getString("kind")
        if (kind !in KINDS) return
        val body = revision.getJSONObject("body")
        text(body, "content")
        val value = body.getJSONObject(kind)
        require(head == null || kind in setOf(GAP, IDEA)) {
            "$kind is immutable; register new work instead of changing an experiment or learning decision"
        }
        require(head == null || head.getString("person_id") == access.personId) {
            "Only the author may revise a gap or innovation; other members publish a linked alternative"
        }
        val host = when (kind) {
            CollaborationActionPrediction.MODEL -> CollaborationActionPrediction.model(value, revision, { ref, kinds -> exact(ref, kinds) }, coverage)
            CollaborationActionPrediction.FORECAST -> CollaborationActionPrediction.forecast(value) { ref, kinds -> exact(ref, kinds) }.also {
                require(value.getLong("valid_until") >= revision.getLong("recorded_at")) { "Forecast is already expired at publication" }
            }
            CollaborationActionPrediction.OUTCOME -> CollaborationPredictionFeedback.outcome(value, revision,
                { ref, kinds -> exact(ref, kinds, false) }, original, coverage)
            CollaborationActionPrediction.CALIBRATION -> CollaborationPredictionFeedback.calibration(value) { ref, kinds -> exact(ref, kinds, false) }
            GAP -> gap(value)
            CollaborationLearningAgenda.KIND -> CollaborationLearningAgenda.validate(value) { ref, kinds -> exact(ref, kinds) }
            CollaborationProceduralMemory.SKILL -> CollaborationProceduralMemory.skill(value) { ref, kinds -> exact(ref, kinds) }
            CollaborationProceduralMemory.FAILURE -> CollaborationProceduralMemory.failure(value, revision, original, coverage)
            CollaborationTransferStudy.KIND -> CollaborationTransferStudy.validate(value) { ref, kinds -> exact(ref, kinds) }
            CollaborationInnovationValidation.OPPORTUNITY -> CollaborationInnovationValidation.opportunity(value, revision,
                { ref, kinds -> exact(ref, kinds) }, coverage)
            CollaborationInnovationValidation.ASSESSMENT -> CollaborationInnovationValidation.assessment(value, revision, access.personId,
                { ref, kinds -> exact(ref, kinds, value.optString("decision") == "retain") }, original, coverage)
            CollaborationTeamInvention.EXCHANGE -> CollaborationTeamInvention.exchange(value, revision, access.personId,
                { ref, kinds -> exact(ref, kinds) }, coverage)
            CollaborationTeamInvention.SYNTHESIS -> CollaborationTeamInvention.synthesis(value) { ref, kinds -> exact(ref, kinds) }
            CollaborationTeamInvention.EVALUATION -> CollaborationTeamComparison.evaluate(value, revision, access.personId,
                { ref, kinds -> exact(ref, kinds, value.optString("decision") == "retain") }, original, coverage)
            CollaborationCapabilityDiagnosis.DIAGNOSIS -> CollaborationCapabilityDiagnosis.diagnosis(value, revision,
                { ref, kinds -> exact(ref, kinds) }, original, coverage)
            CollaborationCapabilityDiagnosis.PROBE -> CollaborationCapabilityDiagnosis.probe(value, revision,
                { ref, kinds -> exact(ref, kinds, requireCurrent = false) }, original, coverage).apply {
                put("targets_current_at_publication", listOf("diagnosis", "gap").all { field ->
                    val ref = getJSONObject(field)
                    ref.getString("object_id") !in changingIds && current(ref.getString("object_id"), ref.getInt("revision"))
                })
            }
            IDEA -> idea(value, revision, head)
            PLAN -> CollaborationEvolutionExperiment.plan(value) { ref, kinds -> exact(ref, kinds) }
            RESULT -> CollaborationEvolutionExperiment.result(value, revision,
                { ref, kinds -> exact(ref, kinds, requireCurrent = false) }, original, coverage).apply {
                val targetsCurrent = listOf("plan", "innovation", "baseline").all { field ->
                    val ref = getJSONObject(field)
                    ref.getString("object_id") !in changingIds && current(ref.getString("object_id"), ref.getInt("revision"))
                } && runCatching {
                    CollaborationTransferStudy.currentPlan(exact(getJSONObject("plan"), setOf(PLAN))) { ref, kinds -> exact(ref, kinds) }
                    CollaborationInnovationValidation.checkRecord(exact(getJSONObject("plan"), setOf(PLAN))) { ref, kinds -> exact(ref, kinds) }
                    CollaborationInnovationValidation.currentIdea(exact(getJSONObject("innovation"), setOf(IDEA))) { ref, kinds -> exact(ref, kinds) }
                }.isSuccess
                put("targets_current_at_publication", targetsCurrent)
                if (!targetsCurrent) put("eligible_for_retention", false)
            }
            else -> lesson(value, revision)
        }
        revision.put(HOST, host.put("trust", "scoped_learning_not_scientific_certification")
            .put("automatically_installed", false))
    }

    private fun gap(value: JSONObject): JSONObject {
        require(text(value, "category") in CollaborationCapabilityDiagnosis.CATEGORIES) {
            "capability_gap.category must be one of ${CollaborationCapabilityDiagnosis.CATEGORIES.sorted()}"
        }
        listOf("symptom", "needed_capability", "chosen_option", "rationale").forEach { text(value, it) }
        val options = objects(value, "learning_options")
        val ids = options.map { text(it, "id") }
        require(ids.distinct().size == ids.size && value.getString("chosen_option") in ids) {
            "Choose one of the distinct learning_options IDs; the host does not choose a learning strategy"
        }
        options.forEach { option ->
            listOf("action", "expected_gain", "cost", "goal_relevance", "verification").forEach { text(option, it) }
        }
        return JSONObject().put("state", "diagnosis_and_priority_proposed")
    }

    private fun idea(value: JSONObject, revision: JSONObject, head: JSONObject?): JSONObject {
        require(head?.optJSONObject(HOST)?.has(CollaborationTeamInvention.SYNTHESIS) != true || value.optJSONObject(CollaborationTeamInvention.SYNTHESIS) != null) {
            "A team-derived method cannot discard its synthesis lineage when revised"
        }
        val origin = text(value, "origin")
        require(origin in setOf("gap", "contradiction", "limitation", "transfer", "combination")) { "Invalid innovation.origin" }
        listOf("hypothesis", "mechanism", "difference", "prior_art", "falsifier", "domain", "applies_when", "risks")
            .forEach { text(value, it) }
        strings(value, "alternatives")
        val predictions = objects(value, "predictions")
        require(predictions.map { text(it, "id") }.distinct().size == predictions.size) { "Prediction IDs must be unique" }
        predictions.forEach { prediction -> listOf("statement", "test").forEach { text(prediction, it) } }
        val scope = text(value, "novelty_scope")
        require(scope in setOf("not_checked", "searched_scope_only")) {
            "Novelty is not globally provable; use not_checked or searched_scope_only and describe prior_art coverage"
        }
        if (scope == "searched_scope_only") {
            val sources = revision.getJSONArray("host_observations")
            require(sources.length() > 0 && (0 until sources.length()).all {
                sources.getJSONObject(it).let { source -> source.optString("status") == "returned" &&
                    source.optString("observation_kind") == "tool_output_recorded" &&
                    !source.optString("tool").contains("recall", ignoreCase = true) }
            }) { "Searched novelty needs original returned source observations, not a recall of peer claims" }
            coverage(revision)
        }
        val parents = revision.getJSONArray("parents")
        if (origin in setOf("transfer", "combination")) {
            val required = if (origin == "combination") 2 else 1
            require((0 until parents.length()).map { parents.getJSONObject(it).getString("object_id") }.distinct().size >= required) {
                "$origin needs $required distinct preserved parent objects"
            }
            text(value, "transfer_conditions")
        }
        val contributors = sortedSetOf(access.personId)
        head?.optJSONObject(HOST)?.optJSONArray("contributors")?.let { values ->
            repeat(values.length()) { contributors += values.getString(it) }
        }
        repeat(parents.length()) { index ->
            val ref = parents.getJSONObject(index)
            val parent = requireNotNull(read(ref.getString("object_id"), ref.getInt("revision")))
            contributors += parent.getString("person_id")
            parent.optJSONObject(HOST)?.optJSONArray("contributors")?.let { values ->
                repeat(values.length()) { contributors += values.getString(it) }
            }
        }
        return JSONObject().put("state", "hypothesis_unverified").put("novelty", scope).put("contributors", JSONArray(contributors.toList()))
            .put("predictions", predictions.size).put("domain", value.getString("domain"))
            .apply { CollaborationTransferStudy.idea(value, revision) { ref, kinds -> exact(ref, kinds) }?.let { put(CollaborationTransferStudy.KIND, it) } }
            .apply { CollaborationInnovationValidation.idea(value, revision) { ref, kinds -> exact(ref, kinds) }
                ?.let { put(CollaborationInnovationValidation.OPPORTUNITY, it) } }
            .apply { CollaborationTeamInvention.idea(value, revision) { ref, kinds -> exact(ref, kinds) }
                ?.let { put(CollaborationTeamInvention.SYNTHESIS, it) } }
    }

    private fun lesson(value: JSONObject, revision: JSONObject): JSONObject {
        val decision = text(value, "decision")
        require(decision in setOf("retain", "reject", "revise")) { "Learning decision must be retain, reject or revise" }
        val retain = decision == "retain"
        val result = exact(value.getJSONObject("result"), setOf(RESULT), retain)
        val plan = exact(result.getJSONObject("body").getJSONObject(RESULT).getJSONObject("plan"), setOf(PLAN), retain)
        val spec = plan.getJSONObject("body").getJSONObject(PLAN)
        val innovation = exact(spec.getJSONObject("innovation"), setOf(IDEA), retain)
        val baseline = exact(spec.getJSONObject("baseline"), setOf("proposal", "artifact", IDEA), retain)
        listOf("rationale", "applies_when", "avoid_when", "procedure", "transfer_test").forEach { text(value, it) }
        require(CollaborationResearchCandidates.same(value.getJSONObject("rollback"), baseline)) { "Preserve the exact baseline as rollback" }
        if (decision == "retain") {
            require(result.getJSONObject(HOST).optBoolean("eligible_for_retention")) {
                "Retention needs complete target improvement and a passing regression suite; no assertions or missing trials"
            }
            val authors = listOf(innovation, baseline, plan).flatMap { record ->
                listOf(record.getString("person_id")) + record.optJSONObject(HOST)?.optJSONArray("contributors")?.let { array ->
                    (0 until array.length()).map { array.getString(it) }
                }.orEmpty()
            } +
                result.getJSONObject(HOST).getJSONArray("trial_authors").let { array ->
                    (0 until array.length()).map { array.getString(it) }
                }
            require(access.personId !in authors) { "Retention requires an independent member, not an idea/plan/baseline/trial author" }
            val refs = revision.getJSONArray("host_observations")
            val required = result.getJSONArray("host_observations")
            require((0 until required.length()).all { index -> (0 until refs.length()).any {
                refs.getJSONObject(it).optString("evidence_id") == required.getJSONObject(index).getString("evidence_id") &&
                    refs.getJSONObject(it).optString("sha256") == required.getJSONObject(index).getString("sha256")
            } }) { "Retention must cite and read every original experiment observation" }
            coverage(revision)
        }
        return JSONObject().put("state", if (decision == "retain") "eligible_for_scoped_reuse" else decision)
            .put("innovation", CollaborationResearchCandidates.reference(innovation))
            .put("plan", CollaborationResearchCandidates.reference(plan)).put("result", CollaborationResearchCandidates.reference(result))
            .put("rollback", CollaborationResearchCandidates.reference(baseline))
            .put("domain", innovation.getJSONObject("body").getJSONObject(IDEA).getString("domain"))
            .apply { if (retain) CollaborationTransferStudy.retain(plan, value) { ref, kinds -> exact(ref, kinds) }
                ?.let { put(CollaborationTransferStudy.KIND, it) } }
            .apply { if (retain) CollaborationInnovationValidation.retention(value, innovation) { ref, kinds -> exact(ref, kinds) }
                ?.let { put(CollaborationInnovationValidation.ASSESSMENT, it) } }
            .apply { if (retain) CollaborationTeamInvention.retention(value, innovation) { ref, kinds -> exact(ref, kinds) }
                ?.let { put(CollaborationTeamInvention.EVALUATION, it) } }
    }

    private fun exact(ref: JSONObject, kinds: Set<String>, requireCurrent: Boolean = true): JSONObject {
        require(ref.opt("revision") is Int && ref.getInt("revision") > 0) { "Copy an exact integer revision" }
        val saved = requireNotNull(read(text(ref, "object_id"), ref.getInt("revision"))) { "Evolution reference missing or isolated" }
        require(CollaborationResearchCandidates.same(saved, ref) && saved.getString("kind") in kinds) {
            "Evolution reference digest or object kind mismatch"
        }
        require(!requireCurrent || saved.getString("object_id") !in changingIds && current(saved.getString("object_id"), saved.getInt("revision"))) {
            "Evolution target changed; create a new experiment for the current version"
        }
        return saved
    }

    companion object {
        const val GAP = "capability_gap"
        const val IDEA = "innovation"
        const val PLAN = "experiment_plan"
        const val RESULT = "experiment_result"
        const val LESSON = "capability_lesson"
        const val HOST = "host_evolution"
        val KINDS = setOf(GAP, IDEA, PLAN, RESULT, LESSON, CollaborationCapabilityDiagnosis.DIAGNOSIS, CollaborationCapabilityDiagnosis.PROBE,
            CollaborationLearningAgenda.KIND, CollaborationProceduralMemory.SKILL, CollaborationProceduralMemory.FAILURE, CollaborationTransferStudy.KIND,
            CollaborationInnovationValidation.OPPORTUNITY, CollaborationInnovationValidation.ASSESSMENT) + CollaborationTeamInvention.KINDS + CollaborationActionPrediction.KINDS
        fun text(json: JSONObject, key: String): String = (json.opt(key) as? String)?.takeIf(String::isNotBlank)
            ?: throw IllegalArgumentException("$key must be a nonempty string")
        fun objects(json: JSONObject, key: String): List<JSONObject> = json.getJSONArray(key).let { array ->
            require(array.length() > 0) { "$key must not be empty" }
            (0 until array.length()).map(array::getJSONObject)
        }
        fun strings(json: JSONObject, key: String): List<String> = json.getJSONArray(key).let { array ->
            require(array.length() > 0) { "$key must not be empty" }
            (0 until array.length()).map { index -> (array.opt(index) as? String)?.takeIf(String::isNotBlank)
                ?: throw IllegalArgumentException("$key[$index] must be a nonempty string") }
        }
    }
}
