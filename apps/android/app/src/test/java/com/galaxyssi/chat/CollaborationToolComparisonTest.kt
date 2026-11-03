package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationExecutableTool.TEST
import com.galaxyssi.chat.CollaborationExecutableTool.TOOL
import com.galaxyssi.chat.CollaborationExecutableTool.RECEIPT

class CollaborationToolComparisonTest {
    private class Fixture {
        val f = CollaborationExecutableToolTest.Fixture()
        val candidateTool = f.ref(f.publish("sort-v2", TOOL, JSONObject(f.spec.toString())
            .put("source", "def run(parameters):\n    return sorted(set(parameters['values']))\n"), "author", 1))
        val candidateSpec = JSONObject(f.planSpec.toString()).put(TOOL, candidateTool)
        val candidatePlan = f.ref(f.publish("candidate-tests", TEST, candidateSpec, "reviewer", 2))
        val candidatePrepared = f.prepare(JSONObject().put("mode", "test").put(TEST, candidatePlan))
        val baselineReport = f.report().apply { getJSONArray("results").getJSONObject(0).put("output", JSONArray("[3,1,2]")) }
        val candidateReport = f.report().apply { getJSONArray("results").getJSONObject(2).put("output", JSONArray("[-1,2]")) }
        val baseline = f.observed(f.finish(report = baselineReport), "baseline")
        val candidate = f.observed(f.finish(candidatePrepared, candidateReport), "candidate")
        fun value() = JSONObject().put("purpose", "Compare sorting repairs without hiding lost duplicate handling")
            .put("baseline", JSONObject().put(TEST, f.plan).put("observation", baseline))
            .put("candidate", JSONObject().put(TEST, candidatePlan).put("observation", candidate))
            .put("interpretation", "One target fixed, one old capability lost; choose a further repair")
            .put("limitations", "Synthetic disclosed cases; not general correctness or causal learning")
        fun compare(value: JSONObject = value(), reads: Boolean = true, refs: JSONArray = JSONArray().put(baseline).put(candidate)): JSONObject {
            if (reads) repeat(refs.length()) { index ->
                val ref = refs.getJSONObject(index)
                var offset: Int? = 0
                while (offset != null) offset = f.ledger.readPage(f.access("reviewer", 5, "comparison"),
                    ref.getString("evidence_id"), ref.getString("sha256"), offset)!!.next
            }
            return f.publish("comparison", CollaborationToolComparison.KIND, value, "reviewer", 5, refs)
        }
    }

    @Test fun reportsBothRepairAndRegressionAndRestoresOriginalChecks() {
        val x = Fixture()
        val ref = x.f.ref(x.compare())
        val host = ref.getJSONObject(HOST)
        assertEquals(3, host.getInt("case_count"))
        val counts = host.getJSONObject("counts")
        assertEquals(1, counts.getInt("improved"))
        assertEquals(1, counts.getInt("regressed"))
        assertEquals(1, counts.getInt("both_passed"))
        assertEquals(0, counts.getInt("both_failed"))
        assertTrue(host.getBoolean("source_changed"))
        assertFalse(host.getBoolean("candidate_all_passed"))
        assertFalse(host.getBoolean("capability_gain_verified"))
        assertFalse(host.getBoolean("automatically_adopted"))
        assertTrue(host.isNull("causal_contribution"))
        val saved = x.f.reopen().read(x.f.access().copy(runId = "future", turnId = "future", round = 0),
            ref.getString("object_id"), ref.getInt("revision"))!!
        val regression = saved.getJSONObject(HOST).getJSONArray("cases").getJSONObject(2)
        assertEquals("regression", regression.getString("purpose"))
        assertEquals("[-1,2]", regression.getJSONObject("candidate").getJSONArray("actual").toString())
        assertEquals("[-1,2,2]", regression.getJSONObject("candidate").getJSONArray("expected").toString())
    }

    @Test fun correctFirstMethodHasNoManufacturedImprovement() {
        val x = Fixture()
        val before = x.f.observed(x.f.finish(), "before-pass")
        val after = x.f.observed(x.f.finish(x.candidatePrepared, x.f.report()), "after-pass")
        val value = x.value().apply {
            getJSONObject("baseline").put("observation", before)
            getJSONObject("candidate").put("observation", after)
        }
        val host = x.f.ref(x.compare(value, refs = JSONArray().put(before).put(after))).getJSONObject(HOST)
        assertEquals(0, host.getJSONObject("counts").getInt("improved"))
        assertEquals(3, host.getJSONObject("counts").getInt("both_passed"))
        assertFalse(host.getBoolean("capability_gain_verified"))
    }

    @Test fun caseErrorIsRetainedAsFailureRatherThanDropped() {
        val x = Fixture()
        val report = x.f.report()
        report.getJSONArray("results").getJSONObject(0).apply { remove("output"); put("error", "KeyError: values") }
        val observed = x.f.observed(x.f.finish(x.candidatePrepared, report), "exception")
        val value = x.value().apply { getJSONObject("candidate").put("observation", observed) }
        val ref = x.f.ref(x.compare(value, refs = JSONArray().put(x.baseline).put(observed)))
        assertFalse(ref.getJSONObject(HOST).has("cases"))
        assertNull(x.f.workspace.read(x.f.access(), ref.getString("object_id"), ref.getInt("revision")))
        val host = x.f.resolve(ref, CollaborationToolComparison.KIND, x.f.access("reviewer", 5, "comparison")).getJSONObject(HOST)
        assertEquals(1, host.getJSONObject("counts").getInt("both_failed"))
        assertEquals("KeyError: values", host.getJSONArray("cases").getJSONObject(0).getJSONObject("candidate").getString("error"))
    }

    @Test fun changedExpectedValueOrCasePurposeCannotManufactureGain() {
        for (field in listOf("expected", "purpose", "input", "reason")) {
            val x = Fixture()
            val spec = JSONObject(x.candidateSpec.toString())
            val row = spec.getJSONArray("cases").getJSONObject(0)
            when (field) {
                "expected" -> row.put(field, JSONArray("[3,1,2]"))
                "purpose" -> row.put(field, "edge")
                "input" -> row.put(field, JSONObject().put("values", JSONArray("[1,2,3]")))
                else -> row.put(field, "Changed declared reason")
            }
            if (field == "purpose") spec.getJSONArray("cases").getJSONObject(1).put("purpose", "target")
            val plan = x.f.ref(x.f.publish("changed-plan", TEST, spec, "reviewer", 2))
            val prepared = x.f.prepare(JSONObject().put("mode", "test").put(TEST, plan))
            val observation = x.f.observed(x.f.finish(prepared, x.f.report()), "changed")
            val value = x.value().put("candidate", JSONObject().put(TEST, plan).put("observation", observation))
            assertEquals(field, "rejected", x.compare(value, refs = JSONArray().put(x.baseline).put(observation)).getString("status"))
        }
    }

    @Test fun changedOracleOrRuntimeIsNotAComparableTest() {
        val x = Fixture()
        val runtimeReport = x.f.report().apply { getJSONObject("runtime").put("machine", "different") }
        val observation = x.f.observed(x.f.finish(x.candidatePrepared, runtimeReport), "different-runtime")
        val value = x.value().apply { getJSONObject("candidate").put("observation", observation) }
        assertEquals("rejected", x.compare(value, refs = JSONArray().put(x.baseline).put(observation)).getString("status"))
        val y = Fixture()
        val plan = y.f.ref(y.f.publish("changed-oracle", TEST, JSONObject(y.candidateSpec.toString()).put("oracle_basis", "New answer source"), "reviewer", 2))
        val prepared = y.f.prepare(JSONObject().put("mode", "test").put(TEST, plan))
        val other = y.f.observed(y.f.finish(prepared, y.f.report()), "changed-oracle")
        assertEquals("rejected", y.compare(y.value().put("candidate", JSONObject().put(TEST, plan).put("observation", other)),
            refs = JSONArray().put(y.baseline).put(other)).getString("status"))
    }

    @Test fun noComparisonWithoutBothCitationsAndCompleteReads() {
        assertEquals("rejected", Fixture().let { it.compare(reads = false) }.getString("status"))
        val x = Fixture()
        assertEquals("rejected", x.compare(refs = JSONArray().put(x.candidate)).getString("status"))
    }

    @Test fun sameReceiptCannotBeCountedTwice() {
        val x = Fixture()
        val value = x.value().put("candidate", JSONObject().put(TEST, x.f.plan).put("observation", x.baseline))
        assertEquals("rejected", x.compare(value).getString("status"))
    }

    @Test fun cannotTrustSelfReportedChecksOrPassedFlag() {
        val x = Fixture()
        val result = x.f.finish(x.candidatePrepared, x.candidateReport)
        val output = JSONObject(result.output)
        output.getJSONObject(RECEIPT).put("passed", true)
        val observation = x.f.observed(result.copy(output = output.toNativeObject()), "forged-passed")
        val value = x.value().apply { getJSONObject("candidate").put("observation", observation) }
        assertEquals("rejected", x.compare(value, refs = JSONArray().put(x.baseline).put(observation)).getString("status"))
    }

    @Test fun rejectsWrongPlanDigestAndArbitraryShellText() {
        val x = Fixture()
        val value = x.value().apply { getJSONObject("candidate").getJSONObject(TEST).put("sha256", "wrong") }
        assertEquals("rejected", x.compare(value).getString("status"))
        val y = Fixture()
        val shell = y.f.observed(y.f.finish(y.candidatePrepared), "shell", toolId = "exec_command")
        assertEquals("rejected", y.compare(y.value().apply { getJSONObject("candidate").put("observation", shell) },
            refs = JSONArray().put(y.baseline).put(shell)).getString("status"))
    }

    @Test fun incompleteTestRunIsNotZeroFailedCases() {
        for (nonzero in listOf(true, false)) {
            val x = Fixture()
            val report = x.f.report().apply { if (!nonzero) getJSONArray("results").remove(0) }
            val observation = x.f.observed(x.f.finish(x.candidatePrepared, report, if (nonzero) 1 else 0), "incomplete")
            assertEquals("rejected", x.compare(x.value().apply { getJSONObject("candidate").put("observation", observation) },
                refs = JSONArray().put(x.baseline).put(observation)).getString("status"))
        }
    }

    @Test fun comparisonReplayDoesNotExecuteOrAddAnotherObservation() {
        val x = Fixture()
        assertEquals(x.compare().toString(), x.compare().toString())
    }

    @Test fun comparisonIsBrowsableInBothDirectoriesWithoutTreatingSidesAsFlatReferences() {
        val x = Fixture()
        val ref = x.f.ref(x.compare())
        val access = x.f.access("reviewer", 5, "comparison")
        for (page in listOf(x.f.reopen().browse(access), x.f.reopen().browseEvolution(access))) {
            val entry = page.revisions.single { it.getString("object_id") == ref.getString("object_id") }
            assertEquals("inspect_scope_before_reuse", entry.getString("evolution_applicability"))
            assertFalse(entry.getJSONObject(HOST).has("cases"))
        }
    }

    @Test fun missingCurrentHeadOnEitherSideKeepsHistoricalComparisonAndOriginalEvidence() {
        repeat(4) { index ->
            val x = Fixture()
            val comparison = x.f.ref(x.compare())
            val selected = listOf(x.f.tool, x.f.plan, x.candidateTool, x.candidatePlan)[index]
            val head = x.f.rows.data.keys.single { it.endsWith("head:${selected.getString("object_id")}") }
            x.f.rows.data.remove(head)
            val access = x.f.access("reviewer", 7, "browse")
            for (page in listOf(x.f.reopen().browse(access), x.f.reopen().browseEvolution(access))) {
                val entry = page.revisions.single { it.getString("object_id") == comparison.getString("object_id") }
                assertEquals("historical_requires_revalidation", entry.getString("evolution_applicability"))
                assertEquals(1, entry.getJSONObject(HOST).getJSONObject("counts").getInt("regressed"))
            }
            assertNotNull(x.f.reopen().read(access, comparison.getString("object_id"), comparison.getInt("revision")))
        }
    }

    @Test fun ancestryChecksExactKindsAndEveryToolAndPlanOnBothSides() {
        val x = Fixture()
        val ref = x.f.ref(x.compare())
        val record = x.f.resolve(ref, CollaborationToolComparison.KIND, x.f.access("reviewer", 5, "comparison"))
        val wanted = listOf(x.f.tool, x.f.plan, x.candidateTool, x.candidatePlan)
        val seen = mutableSetOf<String>()
        CollaborationInnovationValidation.checkRecord(record) { linked, kinds ->
            seen += linked.getString("object_id")
            x.f.resolve(linked, kinds.single())
        }
        assertEquals(wanted.map { it.getString("object_id") }.toSet(), seen)
        for (missing in wanted) {
            assertTrue(runCatching {
                CollaborationInnovationValidation.checkRecord(record) { linked, kinds ->
                    require(linked.getString("object_id") != missing.getString("object_id")) { "Unavailable fixture dependency" }
                    x.f.resolve(linked, kinds.single())
                }
            }.isFailure)
        }
    }

    @Test fun historicalExecutionCannotBeRelabeledAsThisGoalsTest() {
        val x = Fixture()
        val revision = JSONObject().put("group_id", "group").put("run_id", "other-run").put("turn_id", "other-turn")
            .put("host_observations", JSONArray().put(x.baseline).put(x.candidate))
        val failure = runCatching { CollaborationToolComparison.evaluate(x.value(), revision,
            { ref, kinds -> x.f.resolve(ref, kinds.single()) },
            { ref -> x.f.ledger.read(x.f.access(), ref.getString("evidence_id"), ref.getString("sha256")) }, {}) }.exceptionOrNull()
        assertTrue(failure?.message.orEmpty().contains("this goal"))
    }

    @Test fun cachedEvaluationIsNotAReplacementForActualOutputs() {
        val x = Fixture()
        val result = x.f.finish(x.candidatePrepared, x.candidateReport)
        val output = JSONObject(result.output)
        output.getJSONObject(RECEIPT).put("evaluation", JSONObject().put("passed", true).put("checks", JSONArray()))
        val observed = x.f.observed(result.copy(output = output.toNativeObject()), "cached-claims")
        val host = x.f.ref(x.compare(x.value().apply { getJSONObject("candidate").put("observation", observed) },
            refs = JSONArray().put(x.baseline).put(observed))).getJSONObject(HOST)
        assertEquals(1, host.getJSONObject("counts").getInt("regressed"))
    }
}
