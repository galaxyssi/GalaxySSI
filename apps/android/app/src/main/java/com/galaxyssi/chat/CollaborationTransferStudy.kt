package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.IDEA
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.strings
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** Transfer is an explicit hypothesis with new measurements, not inherited source-domain success. */
internal object CollaborationTransferStudy {
    const val KIND = "transfer_study"
    private val SOURCES = setOf(CollaborationProceduralMemory.SKILL, CollaborationProceduralMemory.FAILURE)

    fun source(ref: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        val first = exact(ref, SOURCES)
        val pending = ArrayDeque<JSONObject>().apply { add(first) }
        val seen = hashSetOf<String>()
        while (pending.isNotEmpty()) {
            val saved = pending.removeFirst()
            if (!seen.add(saved.getString("sha256"))) continue
            if (saved.getString("kind") == CollaborationProceduralMemory.SKILL) {
                val host = saved.getJSONObject(HOST)
                CollaborationProceduralMemory.TARGETS.forEach { field -> exact(host.getJSONObject(field), when (field) {
                    "lesson" -> setOf(CollaborationEvolutionContract.LESSON)
                    "innovation" -> setOf(IDEA)
                    "plan" -> setOf(CollaborationEvolutionContract.PLAN)
                    "result" -> setOf(CollaborationEvolutionContract.RESULT)
                    else -> setOf("artifact", "proposal", IDEA)
                }) }
                host.optJSONObject(KIND)?.let { transfer ->
                    val study = exact(transfer, setOf(KIND))
                    val calibration = study.getJSONObject(HOST).getJSONArray("calibration_data")
                    repeat(calibration.length()) { exact(calibration.getJSONObject(it), setOf("artifact")) }
                    val plan = exact(host.getJSONObject("plan"), setOf(CollaborationEvolutionContract.PLAN))
                    objects(plan.getJSONObject("body").getJSONObject(CollaborationEvolutionContract.PLAN), "cases")
                        .forEach { exact(it.getJSONObject("dataset"), setOf("artifact")) }
                    pending.add(exact(study.getJSONObject("body").getJSONObject(KIND).getJSONObject("source"), SOURCES))
                }
            }
        }
        return first
    }

    fun validate(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        val source = source(value.getJSONObject("source"), exact)
        val sourceDomain = text(value, "source_domain")
        val targetDomain = text(value, "target_domain")
        source.getJSONObject(HOST).optString("domain").takeIf(String::isNotBlank)?.let {
            require(sourceDomain == it) { "source_domain must match the saved source scope" }
        }
        require(text(value, "mode") in setOf("cross_task", "cross_domain")) { "Transfer mode must be cross_task or cross_domain" }
        require(value.getString("mode") != "cross_domain" || sourceDomain != targetDomain) { "Cross-domain transfer requires distinct declared domains" }
        listOf("target_task", "abstract_strategy", "proposed_method", "rationale", "risks", "falsifier", "limitations").forEach { text(value, it) }
        strings(value, "alternatives")
        objects(value, "mappings").forEach { mapping ->
            listOf("source_element", "target_element", "invariant", "adaptation", "breaks_when").forEach { text(mapping, it) }
        }
        val calibration = value.getJSONArray("calibration_data")
        val data = JSONArray()
        val seen = hashSetOf<String>()
        repeat(calibration.length()) { index ->
            val saved = exact(calibration.getJSONObject(index), setOf("artifact"))
            require(seen.add(saved.getString("object_id"))) { "Duplicate calibration artifact" }
            data.put(CollaborationResearchCandidates.reference(saved))
        }
        return JSONObject().put("state", "transfer_hypothesis_unverified").put("source", CollaborationResearchCandidates.reference(source))
            .put("source_domain", sourceDomain).put("target_domain", targetDomain).put("calibration_data", data)
            .put("source_kind", source.getString("kind")).put("transfer_verified", false)
    }

    fun current(ref: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        val study = exact(ref, setOf(KIND))
        source(study.getJSONObject("body").getJSONObject(KIND).getJSONObject("source"), exact)
        val data = study.getJSONObject(HOST).getJSONArray("calibration_data")
        repeat(data.length()) { exact(data.getJSONObject(it), setOf("artifact")) }
        return study
    }

    fun idea(value: JSONObject, revision: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject? {
        val ref = value.optJSONObject(KIND) ?: return null
        require(value.getString("origin") == "transfer") { "A transfer study must be attached to a transfer innovation" }
        val study = current(ref, exact)
        require(value.getString("domain") == study.getJSONObject(HOST).getString("target_domain")) { "Innovation domain differs from transfer target" }
        val parents = revision.getJSONArray("parents")
        require((0 until parents.length()).any { CollaborationResearchCandidates.same(study, parents.getJSONObject(it)) }) {
            "Preserve the exact transfer study as an innovation parent"
        }
        return CollaborationResearchCandidates.reference(study)
    }

    fun plan(value: JSONObject, idea: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject? {
        val innovation = idea.getJSONObject("body").getJSONObject(IDEA)
        if (innovation.getString("origin") != "transfer") {
            require(!value.has(KIND)) { "Transfer experiments need a transfer innovation" }
            return null
        }
        require(innovation.has(KIND)) { "A transfer experiment needs a typed transfer_study; source success does not validate another domain" }
        val study = current(innovation.getJSONObject(KIND), exact)
        require(CollaborationResearchCandidates.same(study, value.getJSONObject(KIND))) { "Experiment must use the innovation's exact transfer study" }
        val host = study.getJSONObject(HOST)
        val calibration = host.getJSONArray("calibration_data")
        val calibrationIds = (0 until calibration.length()).map { calibration.getJSONObject(it).getString("object_id") }.toSet()
        val cases = objects(value, "cases")
        require(cases.any { it.getString("purpose") == "transfer" } && cases.any { it.getString("purpose") == "regression" }) {
            "Transfer retention requires held-out transfer and source-regression cases, not only target improvement"
        }
        cases.forEach { case ->
            val data = exact(case.getJSONObject("dataset"), setOf("artifact"))
            val regression = case.getString("purpose") == "regression"
            require(text(case, "domain") == host.getString(if (regression) "source_domain" else "target_domain")) {
                "Case domain must match its source-regression or target-transfer scope"
            }
            require(text(case, "partition") == if (regression) "regression" else "held_out") { "Target and transfer cases must declare held_out partitions" }
            require(regression || data.getString("object_id") !in calibrationIds) { "Held-out evaluation cannot reuse a calibration artifact" }
        }
        return CollaborationResearchCandidates.reference(study)
    }

    fun currentPlan(plan: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject? {
        val spec = plan.getJSONObject("body").getJSONObject(CollaborationEvolutionContract.PLAN)
        val ref = spec.optJSONObject(KIND) ?: return null
        val study = current(ref, exact)
        objects(spec, "cases").forEach { exact(it.getJSONObject("dataset"), setOf("artifact")) }
        return study
    }

    fun retain(plan: JSONObject, lesson: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject? {
        val study = currentPlan(plan, exact) ?: return null
        require(text(lesson, "procedure") == study.getJSONObject("body").getJSONObject(KIND).getString("proposed_method")) {
            "Retain the tested adapted method exactly; changed procedures need another transfer experiment"
        }
        return CollaborationResearchCandidates.reference(study)
    }

    fun checkRecord(record: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject) {
        val host = record.getJSONObject(HOST)
        when (record.getString("kind")) {
            CollaborationProceduralMemory.SKILL -> source(CollaborationResearchCandidates.reference(record), exact)
            KIND -> current(CollaborationResearchCandidates.reference(record), exact)
            CollaborationEvolutionContract.PLAN -> currentPlan(record, exact)
            else -> {
                host.optJSONObject(KIND)?.let { current(it, exact) }
                host.optJSONObject("plan")?.let { currentPlan(exact(it, setOf(CollaborationEvolutionContract.PLAN)), exact) }
            }
        }
    }

    fun instructions() = """
        Transfer experience deliberately: abstract a prior method or failure into invariants, map them to the new task/domain,
        identify broken assumptions and adapt the method. Publish transfer_study before an origin=transfer innovation and experiment.
        Include target-domain held-out comparisons and source regressions. Keep unsuccessful transfers as evidence, not hidden failures.
        A source skill is not validated in another domain. Declare procedure_use.domain and test adaptation before reusing it there.
        Do not infer real-world or physical success from text review, synthetic fixtures, or declared dataset labels.
    """.trimIndent()

    fun rules() = """
        transfer_study: {source:<exact procedure_skill or failure_experience ref>,source_domain,target_domain,
          mode:"cross_task|cross_domain",target_task,abstract_strategy,proposed_method,rationale,risks,falsifier,limitations,
          alternatives:["different explanation or method"],mappings:[{source_element,target_element,invariant,adaptation,breaks_when}],
          calibration_data:[<exact artifact refs used to develop the adaptation; may be empty>]}.
        Source skill/experiment versions must be current. Failure remedies are hypotheses, not proven successful methods.
        Source domain for failure experiences without a recorded domain is an explicit member declaration, not host-verified taxonomy.
        Save an origin=transfer innovation with domain=target_domain, transfer_study:<exact ref>, and that study in parents.
        Save experiment_plan with the same transfer_study ref. Every case adds domain,dataset:<exact artifact ref>,partition.
        Target and transfer cases use target_domain and partition=held_out; regression cases use source_domain and partition=regression.
        Include target, transfer and source-regression cases at the same preregistered budget. Dataset identity separation is enforced;
        it does not prove unseen contents or sound experimental design. Independent reviewers must inspect artifacts, leakage and confounders.
        Every measurement adds dataset_sha256 and domain matching its registered case. The host still reads original tool observations,
        verifies source/time/plan/variant bindings, computes gains, and stores incomplete, inconclusive or regressed outcomes.
        A failed transfer case prevents retaining a transfer adaptation even if a narrow target improves. Generic experiments without a
        transfer_study may still retain their original-domain result; never claim a failed transfer succeeded.
        A retained transfer capability_lesson must preserve the study's proposed_method exactly. Publish a new procedure_skill from that
        independently retained target-domain lesson; it carries transfer/source lineage. Use it with procedure_use.domain=target_domain.
        A changed source, dataset or target requires revalidation for new admission. Historical results remain intact. No retries/steps cap
        substitutes for evidence, and no transfer record grants new permissions, installs code, or certifies scientific truth.
    """.trimIndent()
}
