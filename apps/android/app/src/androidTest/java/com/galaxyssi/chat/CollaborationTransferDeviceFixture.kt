package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*

/** Local parse-count comparison only. No providers, contact messages or user research are invoked. */
internal object CollaborationTransferDeviceFixture {
    fun verify(context: Context, group: String, source: JSONObject) {
        fun access(person: String, round: Long, node: String = person) =
            CollaborationWorkspaceAccess(group, "transfer-run", "transfer-turn", round, node, person)
        val workspace = CollaborationResearchWorkspace(context)
        val ledger = CollaborationEvidenceLedger(context)
        fun publish(id: String, kind: String, value: JSONObject, person: String, round: Long,
                    parents: JSONArray = JSONArray(), refs: JSONArray = JSONArray()): JSONObject {
            val input = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Local transfer fixture")
                .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(JSONObject()
                    .put("id", id).put("kind", kind).put("title", id).put("parents", parents).put("observations", refs)
                    .put("body", JSONObject().put("content", "Local transfer fixture $id").put(kind, value))))
            return workspace.publish(access(person, round, id), input.toString(), round * 100)
        }
        fun saved(receipt: JSONObject): JSONObject {
            assertEquals(receipt.toString(), "recorded", receipt.optString("status"))
            return receipt.getJSONArray("revisions").getJSONObject(0)
        }
        val calibration = saved(publish("calibration", "artifact", JSONObject().put("rows", JSONArray().put(1).put(2)), "baseline", 1))
        val heldOut = saved(publish("held-out", "artifact", JSONObject().put("rows", JSONArray().put(3).put(5).put(7).put(11)), "baseline", 1))
        val old = saved(publish("old-fixture", "artifact", JSONObject().put("rows", JSONArray().put(2)), "baseline", 1))
        val method = "Parse immutable rows once and validate every value"
        val study = saved(publish("transfer-study", "transfer_study", JSONObject()
            .put("source", source).put("source_domain", "fixture").put("target_domain", "table-fixture").put("mode", "cross_domain")
            .put("target_task", "Validate a table").put("abstract_strategy", "Avoid repeated immutable parsing")
            .put("proposed_method", method).put("rationale", "Repeated reads share data").put("risks", "Mutable input")
            .put("falsifier", "No saved parsing or changed sums").put("limitations", "Synthetic fixture only")
            .put("alternatives", JSONArray().put("Parse on every access")).put("calibration_data", JSONArray().put(calibration))
            .put("mappings", JSONArray().put(JSONObject().put("source_element", "Cached fixture")
                .put("target_element", "Table values").put("invariant", "Immutable input").put("adaptation", "Validate each value")
                .put("breaks_when", "Input mutates"))), "author", 2))
        val ideaSpec = JSONObject("""{"origin":"transfer","hypothesis":"Reuse immutable parsing","mechanism":"Cache parsed rows",
            "difference":"Avoid repeated parsing","prior_art":"Not searched","novelty_scope":"not_checked","falsifier":"No measured gain",
            "domain":"table-fixture","applies_when":"Immutable rows","risks":"Mutability","alternatives":["Measurement error"],
            "transfer_conditions":"Immutable local fixtures","predictions":[{"id":"p1","statement":"Fewer parses with same sum","test":"Paired local operation count"}]}""")
            .put("transfer_study", study)
        val idea = saved(publish("transfer-idea", "innovation", ideaSpec, "author", 3, JSONArray().put(study)))
        val cases = JSONArray()
        for (purpose in listOf("target", "transfer", "regression")) cases.put(JSONObject().put("id", purpose).put("purpose", purpose)
            .put("prediction", "Same checksum with fewer repeated parses").put("metric", "parse_count").put("direction", "minimize")
            .put("minimum_gain", 1).put("tolerance", 0).put("repetitions", 1)
            .put("domain", if (purpose == "regression") "fixture" else "table-fixture")
            .put("partition", if (purpose == "regression") "regression" else "held_out")
            .put("dataset", if (purpose == "regression") old else heldOut))
        val plan = saved(publish("transfer-plan", "experiment_plan", JSONObject().put("innovation", idea).put("baseline", source.getJSONObject("host_evolution").getJSONObject("rollback"))
            .put("prediction_id", "p1").put("method", "Count parsing while comparing exact sums").put("environment", "local-fixture")
            .put("budget_unit", "parse_operations").put("budget_limit", 100).put("report_pointer", "")
            .put("source", JSONObject().put("origin", "android_native_tool").put("tool", "fixture.transfer_benchmark"))
            .put("transfer_study", study).put("cases", cases), "planner", 4))
        val baseline = source.getJSONObject("host_evolution").getJSONObject("rollback")
        fun trial(negative: Boolean): Pair<JSONObject, JSONObject> {
            val rows = JSONArray()
            repeat(cases.length()) { index -> val case = cases.getJSONObject(index)
                val dataRef = case.getJSONObject("dataset")
                val values = workspace.read(access("executor", 5), dataRef.getString("object_id"), dataRef.getInt("revision"))!!
                    .getJSONObject("body").getJSONObject("artifact").getJSONArray("rows").toString()
                val expectedSum = JSONArray(values).let { a -> (0 until a.length()).sumOf(a::getInt) }
                for (variant in listOf("baseline", "candidate")) {
                    var count = 0
                    fun parse() = JSONArray(values).also { count++ }
                    val useCache = variant == "candidate" && !(negative && case.getString("purpose") == "transfer")
                    val cached = if (useCache) parse() else null
                    val length = JSONArray(values).length()
                    val sum = (0 until length).sumOf { (cached ?: parse()).getInt(it) }
                    assertEquals(expectedSum, sum)
                    rows.put(JSONObject().put("case_id", case.getString("id")).put("variant", variant)
                        .put("variant_sha256", (if (variant == "baseline") baseline else idea).getString("sha256"))
                        .put("metric", "parse_count").put("value", count).put("budget_used", count).put("repetition", 1)
                        .put("dataset_sha256", dataRef.getString("sha256")).put("domain", case.getString("domain")))
                }
            }
            val report = JSONObject().put("format", CollaborationEvolutionExperiment.FORMAT).put("plan_sha256", plan.getString("sha256"))
                .put("environment", "local-fixture").put("budget_unit", "parse_operations").put("measurements", rows)
            val tag = if (negative) "negative" else "positive"
            val observation = ledger.record(access("executor", 5, "trial-$tag"), "trial-$tag", "fixture.transfer_benchmark", "{}",
                report.toString(), 500, 501, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
            val reader = access("analyst", 6, "result-$tag")
            readAll(ledger, reader, observation)
            val result = saved(publish("result-$tag", "experiment_result", JSONObject().put("plan", plan)
                .put("interpretation", "Local parse-count measurement").put("limitations", "Not evidence of real-world intelligence"),
                "analyst", 6, refs = JSONArray().put(observation)))
            return result to observation
        }
        val (negative, _) = trial(true)
        assertEquals("transfer_not_demonstrated", negative.getJSONObject("host_evolution").getString("state"))
        assertFalse(negative.getJSONObject("host_evolution").getBoolean("eligible_for_retention"))
        val (result, observation) = trial(false)
        assertEquals("measured_improvement", result.getJSONObject("host_evolution").getString("state"))
        readAll(ledger, access("reviewer", 7, "transfer-lesson"), observation)
        val lesson = saved(publish("transfer-lesson", "capability_lesson", JSONObject().put("result", result).put("decision", "retain")
            .put("rationale", "Check operation count and checksum").put("applies_when", "Immutable synthetic tables").put("avoid_when", "Mutable inputs")
            .put("procedure", method).put("transfer_test", "Revalidate other tasks").put("rollback", baseline),
            "reviewer", 7, refs = JSONArray().put(observation)))
        val skill = saved(publish("transfer-skill", "procedure_skill", JSONObject().put("lesson", lesson).put("name", "Table fixture procedure")
            .put("keywords", JSONArray().put("table")).put("limitations", "Synthetic fixture only").put("inputs", JSONArray()), "reviewer", 8))
        val later = access("reviewer", 0).copy(runId = "future-transfer-task", turnId = "future-transfer-turn")
        val reopened = CollaborationResearchWorkspace(context)
        val retained = CollaborationProceduralMemory.current(reopened, later, skill)
        assertEquals("table-fixture", retained.getJSONObject("host_evolution").getString("domain"))
        assertEquals(study.getString("sha256"), retained.getJSONObject("host_evolution").getJSONObject("transfer_study").getString("sha256"))
        assertNotNull(reopened.read(later, negative.getString("object_id"), 1))
        assertNull(reopened.read(later.copy(groupId = "unrelated-transfer-group"), skill.getString("object_id"), 1))
        val directory = JSONObject(CollaborationCloudRecall.execute(context, later, JSONObject().put("mode", "evolution")))
        assertTrue(directory.toString().contains("transfer_study"))
        assertFalse(retained.getJSONObject("host_evolution").getBoolean("automatically_installed"))
    }

    private fun readAll(ledger: CollaborationEvidenceLedger, access: CollaborationWorkspaceAccess, ref: JSONObject) {
        var offset: Int? = 0
        while (offset != null) offset = ledger.readPage(access, ref.getString("evidence_id"), ref.getString("sha256"), offset)!!.next
    }
}
