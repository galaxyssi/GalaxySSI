package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST

class CollaborationTransferTest {
    private class Fixture {
        val base = CollaborationProcedureTest.Fixture()
        val workspace = base.workspace
        val source = base.skill()
        fun access(person: String = "reader", round: Long = 20) = base.access(person, round)
        fun publish(id: String, kind: String, body: JSONObject, round: Long, person: String = id,
                    refs: JSONArray = JSONArray(), parents: JSONArray = JSONArray()): JSONObject {
            val raw = base.raw(id, kind, body, refs)
            raw.getJSONArray("workspace").getJSONObject(0).put("parents", parents)
            return workspace.publish(access(person, round).copy(nodeId = id), raw.toString(), round * 100)
        }
        fun saved(receipt: JSONObject): JSONObject {
            assertEquals(receipt.toString(), "recorded", receipt.optString("status"))
            return receipt.getJSONArray("revisions").getJSONObject(0)
        }
        val calibration = saved(publish("calibration", "artifact", JSONObject(), 7, "data"))
        val heldOut = saved(publish("held-out", "artifact", JSONObject(), 7, "data"))
        val regression = saved(publish("source-cases", "artifact", JSONObject(), 7, "data"))
        fun studySpec() = JSONObject().put("source", source).put("source_domain", "retrieval").put("target_domain", "analysis")
            .put("mode", "cross_domain").put("target_task", "Analyze a new table")
            .put("abstract_strategy", "Separate parsing from repeated checks").put("proposed_method", "Parse once and validate each table field")
            .put("rationale", "Both tasks reuse immutable inputs").put("risks", "Different types").put("falsifier", "More errors")
            .put("limitations", "Synthetic test only").put("alternatives", JSONArray().put("Reparse every field"))
            .put("calibration_data", JSONArray().put(calibration)).put("mappings", JSONArray().put(JSONObject()
                .put("source_element", "Documents").put("target_element", "Table rows").put("invariant", "Immutable inputs")
                .put("adaptation", "Validate field types").put("breaks_when", "Input changes")))
        val study = saved(publish("study", "transfer_study", studySpec(), 8))
        fun ideaSpec() = JSONObject(base.workspace.read(access(), base.experiment.innovation.getString("object_id"), 1)!!
            .getJSONObject("body").getJSONObject("innovation").toString()).put("origin", "transfer").put("domain", "analysis")
            .put("transfer_conditions", "Immutable typed rows").put("transfer_study", study)
        val idea = saved(publish("adaptation", "innovation", ideaSpec(), 9, parents = JSONArray().put(study)))
        fun planSpec(): JSONObject {
            val cases = JSONArray()
            for ((id, purpose) in listOf("target" to "target", "transfer" to "transfer", "old" to "regression")) {
                cases.put(JSONObject(base.experiment.spec.getJSONArray("cases").getJSONObject(0).toString())
                    .put("id", id).put("purpose", purpose).put("domain", if (purpose == "regression") "retrieval" else "analysis")
                    .put("dataset", if (purpose == "regression") regression else heldOut)
                    .put("partition", if (purpose == "regression") "regression" else "held_out"))
            }
            return JSONObject(base.experiment.spec.toString()).put("innovation", idea).put("transfer_study", study).put("cases", cases)
        }
        val spec = planSpec()
        val plan = saved(publish("transfer-plan", "experiment_plan", spec, 10))
        fun report(): JSONObject {
            val rows = JSONArray()
            val cases = spec.getJSONArray("cases")
            repeat(cases.length()) { n -> val case = cases.getJSONObject(n)
                for (variant in listOf("baseline", "candidate")) repeat(2) { rep ->
                    rows.put(JSONObject().put("case_id", case.getString("id")).put("variant", variant)
                        .put("variant_sha256", (if (variant == "baseline") base.experiment.baseline else idea).getString("sha256"))
                        .put("metric", "score").put("value", if (variant == "baseline") 10 else 12).put("repetition", rep + 1)
                        .put("budget_used", 50).put("dataset_sha256", case.getJSONObject("dataset").getString("sha256"))
                        .put("domain", case.getString("domain")))
                }
            }
            return JSONObject().put("format", CollaborationEvolutionExperiment.FORMAT).put("plan_sha256", plan.getString("sha256"))
                .put("environment", "fixture-v1").put("budget_unit", "operations").put("measurements", rows)
        }
        var observation: JSONObject? = null
        fun result(change: (JSONObject) -> Unit = {}): JSONObject {
            observation = base.experiment.ledger.record(access("trial-author", 11), "transfer-trial", "benchmark", "{}",
                report().apply(change).toString(), 1100, 1101, CollaborationEvidenceOrigin.ANDROID_CLOUD_TOOL)
            read("analyst", 12)
            return publish("transfer-result", "experiment_result", JSONObject().put("plan", plan).put("interpretation", "Fixture result")
                .put("limitations", "No real model comparison"), 12, "analyst", JSONArray().put(observation))
        }
        fun read(person: String, round: Long, node: String = "transfer-result") {
            val ref = observation!!
            var offset: Int? = 0
            while (offset != null) offset = base.experiment.ledger.readPage(access(person, round).copy(nodeId = node),
                ref.getString("evidence_id"), ref.getString("sha256"), offset)!!.next
        }
        fun lesson(result: JSONObject, decision: String = "retain", method: String = "Parse once and validate each table field", person: String = "independent"): JSONObject {
            val node = "transfer-lesson-$person-$decision"
            read(person, 13, node)
            return publish(node, "capability_lesson", JSONObject().put("result", result).put("decision", decision)
                .put("rationale", "Inspect originals").put("applies_when", "Immutable tables").put("avoid_when", "Input changes")
                .put("procedure", method).put("transfer_test", "Revalidate other domains").put("rollback", base.experiment.baseline),
                13, person, JSONArray().put(observation))
        }
        fun skill(lesson: JSONObject) = saved(publish("target-skill", "procedure_skill", base.spec().put("lesson", lesson), 14))
        fun changeSource() {
            val old = workspace.read(access(), base.experiment.innovation.getString("object_id"), 1)!!
            val input = base.raw("source-change", "innovation", old.getJSONObject("body").getJSONObject("innovation").put("risks", "Changed environment"))
            input.getJSONArray("workspace").getJSONObject(0).put("object_id", old.getString("object_id")).put("base_revision", 1)
            saved(workspace.publish(access("inventor", 16).copy(nodeId = "source-change"), input.toString(), 1600))
        }
        fun changeDataset() {
            val input = base.raw("data-change", "artifact", JSONObject())
            input.getJSONArray("workspace").getJSONObject(0).put("object_id", heldOut.getString("object_id")).put("base_revision", 1)
                .getJSONObject("body").put("content", "Changed target fixture")
            saved(workspace.publish(access("data", 16).copy(nodeId = "data-change"), input.toString(), 1600))
        }
    }

    @Test fun transferCreatesNewScopedSkillAndReusesItAfterReopen() {
        val f = Fixture(); val result = f.saved(f.result()); val lesson = f.saved(f.lesson(result)); val skill = f.skill(lesson)
        assertEquals("analysis", skill.getJSONObject(HOST).getString("domain"))
        assertEquals(f.study.getString("sha256"), skill.getJSONObject(HOST).getJSONObject("transfer_study").getString("sha256"))
        val later = f.access().copy(runId = "next-task", turnId = "next-turn", round = 0)
        val work = f.base.work(skill).apply { getJSONObject("procedure_use").put("domain", "analysis") }
        val admitted = CollaborationProcedureWork.plan(f.base.record(), listOf(work), { f.base.experiment.workspace() }, later)
        val binding = JSONObject(CollaborationProcedureWork.context(admitted.work.single()).getValue(CollaborationProcedureWork.TASK))
        assertEquals("Parse once and validate each table field", binding.getString("method"))
        assertFalse(binding.getBoolean("grants_permissions"))
        assertFalse(f.study.getJSONObject(HOST).getBoolean("transfer_verified"))
    }

    @Test fun oldSkillCannotBeUsedInNewDomainWithoutTransferExperiment() {
        val f = Fixture(); val work = f.base.work(f.source).apply { getJSONObject("procedure_use").put("domain", "analysis") }
        assertTrue(runCatching { CollaborationProcedureWork.plan(f.base.record(), listOf(work), { f.workspace }, f.access()) }
            .exceptionOrNull()!!.message!!.contains("transfer adaptation"))
    }

    @Test fun missingDomainCannotInheritAValidatedLabel() {
        val f = Fixture(); val work = f.base.work(f.source).apply { getJSONObject("procedure_use").remove("domain") }
        assertTrue(runCatching { CollaborationProcedureWork.plan(f.base.record(), listOf(work), { f.workspace }, f.access()) }.isFailure)
    }

    @Test fun invalidSourceScopeAndMissingAdaptationAreRejected() {
        val changes = listOf<(JSONObject) -> Unit>({ it.put("source_domain", "unrelated") }, { it.put("target_domain", "retrieval") },
            { it.put("mappings", JSONArray()) }, { it.getJSONArray("mappings").getJSONObject(0).remove("breaks_when") },
            { it.getJSONObject("source").put("sha256", "a".repeat(64)) })
        changes.forEach { change -> val f = Fixture()
            assertEquals("rejected", f.publish("bad-study", "transfer_study", f.studySpec().apply(change), 9).getString("status")) }
    }

    @Test fun transferIdeaMustBindTargetAndStudyParent() {
        val f = Fixture()
        assertEquals("rejected", f.publish("wrong-domain", "innovation", f.ideaSpec().put("domain", "retrieval"), 9,
            parents = JSONArray().put(f.study)).getString("status"))
        assertEquals("rejected", f.publish("wrong-parent", "innovation", f.ideaSpec(), 9, parents = JSONArray().put(f.source)).getString("status"))
    }

    @Test fun calibrationIdentityWrongPartitionMissingTransferAndWrongDomainRejectPlan() {
        val changes = listOf<(JSONObject) -> Unit>(
            { it.getJSONArray("cases").getJSONObject(0).put("dataset", it.getJSONObject("calibration-fixture")); it.remove("calibration-fixture") },
            { it.getJSONArray("cases").getJSONObject(1).put("partition", "training") },
            { it.getJSONArray("cases").getJSONObject(2).put("domain", "analysis") },
            { it.getJSONArray("cases").remove(1) }, { it.remove("transfer_study") })
        changes.forEach { change -> val f = Fixture(); val spec = f.planSpec().put("calibration-fixture", f.calibration).apply(change)
            spec.remove("calibration-fixture")
            assertEquals("rejected", f.publish("bad-plan", "experiment_plan", spec, 10).getString("status")) }
    }

    @Test fun measurementDatasetAndDomainCannotBeSubstituted() {
        for (field in listOf("dataset_sha256", "domain")) {
            val f = Fixture(); val rejected = f.result { it.getJSONArray("measurements").getJSONObject(0).put(field, "different") }
            assertEquals("rejected", rejected.getString("status")); assertTrue(rejected.getString("reason").contains("dataset/domain"))
        }
    }

    @Test fun narrowImprovementDoesNotHideNegativeTransferAndNegativeLessonSurvives() {
        val f = Fixture(); val result = f.saved(f.result { json -> val rows = json.getJSONArray("measurements")
            repeat(rows.length()) { val row = rows.getJSONObject(it)
                if (row.getString("case_id") == "transfer" && row.getString("variant") == "candidate") row.put("value", 9) }
        })
        assertEquals("transfer_not_demonstrated", result.getJSONObject(HOST).getString("state"))
        assertFalse(result.getJSONObject(HOST).getBoolean("eligible_for_retention"))
        assertEquals("rejected", f.lesson(result).getString("status"))
        assertEquals("reject", f.saved(f.lesson(result, decision = "reject", person = "negative-reviewer")).getJSONObject(HOST).getString("state"))
    }

    @Test fun partialTransferCannotBecomeRetainedSkill() {
        val f = Fixture(); val result = f.saved(f.result { it.getJSONArray("measurements").remove(4) })
        assertEquals("incomplete", result.getJSONObject(HOST).getString("state"))
        assertEquals("rejected", f.lesson(result).getString("status"))
    }

    @Test fun changedMethodAndSelfReviewCannotBeRetained() {
        val f = Fixture(); val result = f.saved(f.result())
        assertTrue(f.lesson(result, method = "A different method").getString("reason").contains("tested adapted method"))
        assertTrue(f.lesson(result, person = "study").getString("reason").contains("independent"))
    }

    @Test fun updatedSourceBlocksAdmissionButDoesNotEraseResults() {
        val f = Fixture(); val result = f.saved(f.result()); val skill = f.skill(f.saved(f.lesson(result))); f.changeSource()
        assertTrue(runCatching { CollaborationProceduralMemory.current(f.workspace, f.access(), skill) }.isFailure)
        assertNotNull(f.workspace.read(f.access(), result.getString("object_id"), 1))
        assertEquals("historical_requires_revalidation", f.workspace.browseEvolution(f.access()).revisions
            .single { it.getString("object_id") == skill.getString("object_id") }.getString("evolution_applicability"))
    }

    @Test fun changedDatasetPreventsOldTransferPromotionAndKeepsHistory() {
        val f = Fixture(); f.changeDataset(); val result = f.saved(f.result())
        assertFalse(result.getJSONObject(HOST).getBoolean("targets_current_at_publication"))
        assertFalse(result.getJSONObject(HOST).getBoolean("eligible_for_retention"))
        assertEquals("rejected", f.lesson(result).getString("status"))
        assertEquals("reject", f.saved(f.lesson(result, decision = "reject", person = "negative-reviewer")).getJSONObject(HOST).getString("state"))
    }

    @Test fun sourceAndStudyStayGroupScoped() {
        val f = Fixture()
        assertNull(f.workspace.read(f.access().copy(groupId = "other"), f.study.getString("object_id"), 1))
        assertTrue(runCatching { CollaborationProceduralMemory.current(f.workspace, f.access().copy(groupId = "other"), f.source) }.isFailure)
    }

    @Test fun changedDatasetAlsoInvalidatesAnAlreadyRetainedTransferSkill() {
        val f = Fixture(); val result = f.saved(f.result()); val skill = f.skill(f.saved(f.lesson(result)))
        f.changeDataset()
        assertTrue(runCatching { CollaborationProceduralMemory.current(f.workspace, f.access(), skill) }.isFailure)
        assertNotNull(f.workspace.read(f.access(), skill.getString("object_id"), 1))
    }

    @Test fun sameDomainCrossTaskTransferStillRequiresExplicitMapping() {
        val f = Fixture()
        val study = f.saved(f.publish("same-domain", "transfer_study", f.studySpec().put("mode", "cross_task")
            .put("target_domain", "retrieval"), 9))
        assertEquals("transfer_hypothesis_unverified", study.getJSONObject(HOST).getString("state"))
    }

    @Test fun laterTransferKeepsTheOriginalSourceLineage() {
        val f = Fixture(); val skill = f.skill(f.saved(f.lesson(f.saved(f.result()))))
        val study = f.saved(f.publish("next-domain", "transfer_study", f.studySpec().put("source", skill)
            .put("source_domain", "analysis").put("target_domain", "statistics"), 15))
        f.changeSource()
        assertEquals("historical_requires_revalidation", f.workspace.browseEvolution(f.access()).revisions
            .single { it.getString("object_id") == study.getString("object_id") }.getString("evolution_applicability"))
        assertNotNull(f.workspace.read(f.access(), study.getString("object_id"), 1))
    }

    @Test fun originalFailureCanInspireAnUnverifiedAdaptation() {
        val f = Fixture(); val reader = f.access("failure-author", 8).copy(nodeId = "failure-note")
        val observation = f.base.experiment.ledger.record(f.access("executor", 7), "failed-transfer-source", "fixture", "{}",
            "{\"error\":\"input changed\"}", 700, 701, CollaborationEvidenceOrigin.ANDROID_CLOUD_TOOL)
        var offset: Int? = 0
        while (offset != null) offset = f.base.experiment.ledger.readPage(reader, observation.getString("evidence_id"), observation.getString("sha256"), offset)!!.next
        val failure = f.saved(f.publish("failure-note", "failure_experience", JSONObject("""{
            "observed_issue":"Input changed","interpretation":"Possibly stale cache","uncertainty":"Cause not established",
            "applies_when":"Mutable data","avoid_repetition":"Check input version","reconsider_when":"Inputs are immutable",
            "recovery_options":["Version the inputs","Reparse"]}"""), 8, "failure-author", JSONArray().put(observation)))
        val study = f.saved(f.publish("failure-adaptation", "transfer_study", f.studySpec().put("source", failure), 9))
        assertEquals("failure_experience", study.getJSONObject(HOST).getString("source_kind"))
        assertFalse(study.getJSONObject(HOST).getBoolean("transfer_verified"))
        assertFalse(failure.getJSONObject(HOST).getBoolean("cause_verified"))
    }

    @Test fun ordinaryExperimentsDoNotRequireTransferGainForOriginalDomainRetention() {
        val f = CollaborationEvolutionTest.Fixture(CollaborationEvolutionTest()) { spec ->
            spec.getJSONArray("cases").put(JSONObject(spec.getJSONArray("cases").getJSONObject(0).toString()).put("id", "other").put("purpose", "transfer")) }
        f.trial(f.report { report -> val rows = report.getJSONArray("measurements"); repeat(rows.length()) {
            val row = rows.getJSONObject(it); if (row.getString("case_id") == "other") row.put("value", 10) } })
        assertEquals("recorded", f.publishResult().getString("status"))
        assertTrue(f.result!!.getJSONObject(HOST).getBoolean("eligible_for_retention"))
    }
}
