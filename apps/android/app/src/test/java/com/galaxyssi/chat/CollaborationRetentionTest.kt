package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST

class CollaborationRetentionTest {
    internal class Fixture {
        val rows = CollaborationEvolutionTest.Rows()
        val ledger = CollaborationEvidenceLedger(CollaborationEvolutionTest.Rows())
        fun reopen() = CollaborationResearchWorkspace(rows, evidence = ledger::references, evidenceReadCoverage = ledger::requireReadCoverage,
            evidenceOriginal = { a, r -> ledger.read(a, r.getString("evidence_id"), r.getString("sha256")) })
        val f = CollaborationRetentionFixture(reopen(), ledger)
    }
    @Test fun bankFreezesAllCasesAndScopeWithoutGrantingAuthority() {
        val f = Fixture().f; val retained = f.retain(f.study()); val host = retained.suite.getJSONObject(HOST)
        assertEquals(2, host.getJSONArray("anchors").length())
        assertEquals("10", host.getJSONArray("anchors").getJSONObject(0).getString("anchor"))
        assertFalse(host.getBoolean("grants_permissions")); assertFalse(host.getBoolean("automatically_installed"))
    }
    @Test fun incompleteOrRegressedWorkCannotCreateRetainedVersions() {
        for (missing in listOf(true, false)) {
            val f = Fixture().f; val first = f.retain(f.study())
            val bad = f.study(first, editReport = { report -> val rows = report.getJSONArray("measurements")
                if (missing) rows.remove(0) else repeat(rows.length()) { i -> rows.getJSONObject(i).let {
                    if (it.getString("case_id") == "legacy" && it.getString("variant") == "candidate") it.put("value", 0)
                } }
            })
            assertFalse(bad.result.getJSONObject(HOST).getBoolean("eligible_for_retention"))
            assertEquals("rejected", f.lesson(bad).getString("status"))
        }
    }
    @Test fun hiddenCumulativeRegressionFailsEvenWhenRelativeGainPasses() {
        val f = Fixture().f; val first = f.retain(f.study(editPlan = { spec -> spec.getJSONArray("cases").getJSONObject(0).put("tolerance", 1) }))
        val bad = f.study(first, editReport = { report -> val rows = report.getJSONArray("measurements"); repeat(rows.length()) { i ->
            rows.getJSONObject(i).let { if (it.getString("case_id") == "legacy") it.put("value", if (it.getString("variant") == "baseline") 9 else 8) }
        } })
        assertEquals("regressed", bad.result.getJSONObject(HOST).getString("state"))
        val row = bad.result.getJSONObject(HOST).getJSONArray("cases").getJSONObject(0)
        assertEquals("-1", row.getString("gain")); assertEquals("10", row.getString("retained_anchor")); assertFalse(row.getBoolean("retention_passed"))
    }
    @Test fun cannotDropCasesWeakenContractsOrMoveEnvironment() {
        val f = Fixture().f; val first = f.retain(f.study())
        for (field in listOf("missing", "repetitions", "tolerance", "direction", "metric", "dataset", "environment")) {
            val idea = f.idea(f.method("bad-$field")); val spec = f.spec(idea, first); val old = spec.getJSONArray("cases").getJSONObject(0)
            when (field) {
                "missing" -> spec.getJSONArray("cases").remove(0)
                "repetitions" -> old.put(field, 1)
                "tolerance" -> old.put(field, 1)
                "dataset" -> old.put(field, f.ref(first.study.method))
                "environment" -> spec.put(field, "different")
                "direction" -> old.put(field, "minimize")
                else -> old.put(field, "other")
            }
            assertEquals(field, "rejected", f.publish("experiment_plan", spec, "planner").getString("status"))
        }
    }
    @Test fun wrongDatasetHashCannotSupplyRegressionEvidence() {
        val f = Fixture().f
        reject { f.study(editReport = { it.getJSONArray("measurements").getJSONObject(0).put("dataset_sha256", "wrong") }) }
    }
    @Test fun promotionExtendsBankAndRollbackRetainsBothHistoryAndNewCases() {
        val fixture = Fixture(); val f = fixture.f; val first = f.retain(f.study()); val initial = f.accepted(f.select(first))
        val second = f.retain(f.study(first)); val promoted = f.accepted(f.select(second, initial))
        assertEquals(3, second.suite.getJSONObject(HOST).getJSONArray("anchors").length())
        val rolled = f.accepted(f.rollback(promoted, initial))
        assertEquals(3, rolled.getInt("revision")); assertTrue(rolled.getJSONObject(HOST).getBoolean("newer_capabilities_require_revalidation"))
        assertEquals(first.skill.getString("sha256"), rolled.getJSONObject(HOST).getJSONObject("implementation").getString("sha256"))
        assertEquals(second.suite.getString("sha256"), rolled.getJSONObject(HOST).getJSONObject("suite").getString("sha256"))
        val restored = fixture.reopen()
        for (revision in listOf(initial, promoted, rolled)) assertEquals(revision.toString(), restored.read(f.access(), revision.getString("object_id"), revision.getInt("revision"))!!.toString())
        val again = f.accepted(f.rollback(rolled, rolled))
        assertTrue(again.getJSONObject(HOST).getBoolean("newer_capabilities_require_revalidation"))
        assertEquals(first.suite.getString("sha256"), again.getJSONObject(HOST).getJSONObject("restored_suite").getString("sha256"))
    }
    @Test fun promotionAgainstWrongBaselineAndResetBankAreRejected() {
        val f = Fixture().f; val first = f.retain(f.study()); val channel = f.accepted(f.select(first))
        val unrelated = f.retain(f.study())
        assertEquals("rejected", f.select(unrelated, channel).getString("status"))
        val second = f.retain(f.study(first)); val promoted = f.accepted(f.select(second, channel))
        val againstOld = f.retain(f.study(first))
        assertEquals("rejected", f.select(againstOld, promoted).getString("status"))
    }
    @Test fun staleCasWrongOwnerAndUnrelatedRollbackCannotChangeSelection() {
        val f = Fixture().f; val first = f.retain(f.study()); val initial = f.accepted(f.select(first))
        val second = f.retain(f.study(first)); val current = f.accepted(f.select(second, initial))
        assertEquals("rejected", f.select(second, initial).getString("status"))
        val other = f.accepted(f.select(first))
        assertEquals("rejected", f.rollback(current, other).getString("status"))
        assertEquals("rejected", f.publish(CollaborationCapabilityChannel.KIND, JSONObject().put("operation", "rollback")
            .put("reason", "Not the owner").put("target_revision", f.ref(initial)), "outsider", previous = current).getString("status"))
    }
    @Test fun admittedProcedureSurvivesPromotionButNewWorkRequiresActiveSelection() {
        val fixture = Fixture(); val f = fixture.f; val first = f.retain(f.study()); val initial = f.accepted(f.select(first))
        val work = f.work(first, initial); val record = f.record()
        val planned = CollaborationProcedureWork.plan(record, listOf(work), { f.workspace }, f.access())
        val pinned = record.copy(request = record.request.copy(context = record.request.context + (CollaborationProcedureWork.CLAIMS to planned.claims)))
        val second = f.retain(f.study(first)); val current = f.accepted(f.select(second, initial))
        assertEquals(planned.claims, CollaborationProcedureWork.plan(pinned, listOf(work), { fixture.reopen() }, f.access()).claims)
        reject { CollaborationProcedureWork.plan(record, listOf(f.work(first, initial, "new")), { f.workspace }, f.access()) }
        reject { CollaborationProcedureWork.plan(record, listOf(f.work(first, current)), { f.workspace }, f.access()) }
        val newWork = CollaborationProcedureWork.plan(record, listOf(f.work(second, current)), { f.workspace }, f.access())
        assertTrue(CollaborationProcedureWork.context(newWork.work.single()).getValue(CollaborationProcedureWork.TASK).contains(current.getString("sha256")))
    }
    @Test fun admittedWorkflowSurvivesPromotionAndRejectsBindingRemovalOrRelabeling() {
        val f = Fixture().f; val first = f.retain(f.study()); val initial = f.accepted(f.select(first, workflow = true))
        val work = f.workflowWork(first, initial); val record = f.record()
        val planned = CollaborationWorkflowWork.plan(record, listOf(work), { f.workspace }, f.access())
        val pinned = record.copy(request = record.request.copy(context = record.request.context + (CollaborationWorkflowWork.CLAIMS to planned.claims)))
        val second = f.retain(f.study(first)); val current = f.accepted(f.select(second, initial, true))
        assertEquals(planned.claims, CollaborationWorkflowWork.plan(pinned, listOf(work), { f.workspace }, f.access()).claims)
        reject { CollaborationWorkflowWork.plan(record, listOf(f.workflowWork(first, initial, "new")), { f.workspace }, f.access()) }
        reject { CollaborationWorkflowWork.plan(pinned, listOf(f.workflowWork(second, current)), { f.workspace }, f.access()) }
        work.getJSONObject(CollaborationWorkflowWork.FIELD).remove(CollaborationCapabilityChannel.FIELD)
        reject { CollaborationWorkflowWork.plan(pinned, listOf(work), { f.workspace }, f.access()) }
    }
    @Test fun ordinaryWorkDoesNotReadWorkspaceAndOtherGroupCannotResolveSelection() {
        val f = Fixture().f; val first = f.retain(f.study()); val channel = f.accepted(f.select(first))
        reject { CollaborationCapabilityChannel.binding(f.work(first, channel).getJSONObject("procedure_use"), first.skill,
            f.workspace, f.access().copy(groupId = "other"), false) }
        val ordinary = JSONObject().put("id", "plain")
        assertSame(ordinary, CollaborationWorkflowWork.plan(f.record(), listOf(ordinary), { error("No I/O") }, f.access()).work.single())
    }
    @Test fun selectedToolStillUsesSavedCodeSchemaAndRuntimeGuard() {
        val f = CollaborationExecutableToolTest.Fixture(); val release = f.ref(f.release())
        val channel = JSONObject().put("object_id", "channel").put("revision", 1).put("sha256", "selected-hash")
            .put("kind", CollaborationCapabilityChannel.KIND).put(HOST, JSONObject().put("implementation", release)
                .put("state", "selected_scoped_version").put("implementation_kind", CollaborationExecutableTool.RELEASE))
        val request = JSONObject().put("mode", "run").put(CollaborationCapabilityChannel.FIELD, channel)
            .put("parameters", JSONObject().put("values", org.json.JSONArray("[3,1,2]")))
        fun prepare() = CollaborationToolRuntime.prepare(mapOf(CollaborationToolRuntime.INPUT to request.toNativeObject()), f.access()) { ref, kind ->
            if (kind == CollaborationCapabilityChannel.KIND) channel else f.resolve(ref, kind)
        }!!
        val prepared = prepare()
        assertEquals(f.tool.getString("sha256"), prepared.identity.getJSONObject(CollaborationExecutableTool.TOOL).getString("sha256"))
        assertTrue(prepared.identity.has("tested_runtime")); assertFalse(prepared.identity.getBoolean("grants_permissions"))
        request.getJSONObject("parameters").put("values", org.json.JSONArray().put("wrong"))
        reject { prepare() }
        request.put(CollaborationExecutableTool.RELEASE, release)
        reject { prepare() }
    }
    @Test fun staleInnovationEvidenceCannotAuthorizeNewWorkflowExecution() {
        val f = Fixture().f; val first = f.retain(f.study()); val channel = f.accepted(f.select(first, workflow = true))
        val changed = JSONObject(first.study.idea.getJSONObject("body").getJSONObject("innovation").toString()).put("hypothesis", "Different hypothesis")
        f.accepted(f.publish("innovation", changed, "author", previous = first.study.idea))
        reject { CollaborationWorkflowWork.plan(f.record(), listOf(f.workflowWork(first, channel)), { f.workspace }, f.access()) }
        assertEquals("rejected", f.rollback(channel, channel).getString("status"))
    }
    @Test fun failedCommitCannotPartiallyPromoteSelection() {
        val fixture = Fixture(); val f = fixture.f; val first = f.retain(f.study()); val channel = f.accepted(f.select(first))
        val second = f.retain(f.study(first)); fixture.rows.fail = true
        reject { f.select(second, channel) }
        fixture.rows.fail = false
        assertTrue(fixture.reopen().isCurrent(f.access(), channel.getString("object_id"), 1))
        assertNull(fixture.reopen().read(f.access(), channel.getString("object_id"), 2))
    }
    @Test fun minimizedMetricsPreserveOriginalUpperBound() {
        val anchor = JSONObject().put("direction", "minimize").put("anchor", "10").put("tolerance", "0.5")
        assertTrue(CollaborationCapabilityRetention.passes(anchor, java.math.BigDecimal("10.5")))
        assertFalse(CollaborationCapabilityRetention.passes(anchor, java.math.BigDecimal("10.5001")))
    }
    @Test fun feasibilityThresholdCannotBeLostInsideARegressionTolerance() {
        val f = Fixture().f
        val first = f.retain(f.study(editPlan = { it.getJSONArray("cases").put(f.case("required", "feasibility").put("threshold", 10).put("tolerance", 100)) }))
        val bad = f.study(first, editReport = { report -> val samples = report.getJSONArray("measurements"); repeat(samples.length()) { i ->
            samples.getJSONObject(i).let { if (it.getString("case_id") == "required" && it.getString("variant") == "candidate") it.put("value", 9) }
        } })
        assertEquals("regressed", bad.result.getJSONObject(HOST).getString("state"))
        assertEquals("rejected", f.lesson(bad).getString("status"))
    }
    @Test fun directoryAndReceiptsDoNotRepeatTheFullProtectedCaseBank() {
        val f = Fixture().f; val first = f.retain(f.study())
        val item = f.workspace.browseEvolution(f.access()).revisions.single { it.getString("object_id") == first.suite.getString("object_id") }
        assertFalse(item.getJSONObject(HOST).has("anchors")); assertEquals(2, item.getJSONObject(HOST).getInt("protected_case_count"))
        val receipt = f.publish(CollaborationCapabilityRetention.SUITE, JSONObject().put("lesson", f.ref(first.lesson)).put("scope", "Fixture").put("limitations", "Synthetic"))
        val compact = receipt.getJSONArray("revisions").getJSONObject(0).getJSONObject(HOST)
        assertFalse(compact.has("anchors")); assertEquals(2, compact.getInt("protected_case_count"))
        assertEquals(2, f.accepted(receipt).getJSONObject(HOST).getJSONArray("anchors").length())
    }
    private fun reject(action: () -> Unit) = assertNotNull("Expected rejection", runCatching(action).exceptionOrNull())
}
