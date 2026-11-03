package com.galaxyssi.chat

import com.galaxyssi.chat.CollaborationExecutableTool.RECEIPT
import com.galaxyssi.chat.CollaborationExecutableTool.RELEASE
import com.galaxyssi.chat.CollaborationExecutableTool.TEST
import com.galaxyssi.chat.CollaborationExecutableTool.TOOL
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationCandidateRecallTest {
    private fun entries(page: JSONObject) = page.getJSONArray("records").let { a -> (0 until a.length()).map(a::getJSONObject) }
    private fun request(f: CollaborationExecutableToolTest.Fixture) = JSONObject().put(CollaborationToolRuntime.INPUT,
        JSONObject().put("mode", "test").put(TEST, CollaborationResearchCandidates.reference(f.plan)))
    private fun output(f: CollaborationExecutableToolTest.Fixture, passed: Boolean): JSONObject {
        val report = f.report()
        if (!passed) report.getJSONArray("results").getJSONObject(0).put("output", JSONArray("[3,1,2]"))
        return JSONObject().put("status", if (passed) "succeeded" else "failed")
            .put("output", JSONObject(f.finish(report = report).output))
    }
    private fun save(f: CollaborationExecutableToolTest.Fixture, id: String = "failed-test", result: JSONObject = output(f, false),
                     input: JSONObject = request(f), origin: CollaborationEvidenceOrigin = CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL) =
        f.ledger.record(f.access("tester", 3), id, AgentOnDeviceRuntimeTools.EXECUTE, input.toString(), result.toString(), 30, 31, origin)

    @Test fun newTaskFindsUnreleasedCandidateAndItsFailedTestsWithoutOldConversation() {
        val f = CollaborationExecutableToolTest.Fixture()
        val observed = save(f)
        val future = f.access().copy(runId = "new-run", turnId = "new-turn", round = 0)
        val before = f.rows.data.toMap()
        val workspace = f.reopen()
        val matches = entries(workspace.searchCapabilities(future, "sort"))
        for (kind in listOf(TOOL, TEST)) {
            val found = matches.single { it.getString("kind") == kind }
            assertEquals("candidate_requires_testing_and_independent_release", found.getString("reuse_status"))
            assertFalse(found.getBoolean("grants_permissions"))
            val selector = found.getJSONObject("usage_recall")
            val history = workspace.methodHistory(future, selector)
            val row = entries(history).single()
            assertEquals(kind, history.getString("subject_kind"))
            assertEquals(observed.getString("sha256"), row.getString("sha256"))
            assertFalse(row.getBoolean("runtime_reported_passed"))
            assertFalse(row.getBoolean("grants_execution"))
            val ref = row.getJSONObject("read_original")
            val original = f.ledger.read(future, ref.getString("evidence_id"), ref.getString("sha256"))!!
            val checks = JSONObject(original.getString("output_json")).getJSONObject("output").getJSONObject(RECEIPT)
                .getJSONObject("evaluation").getJSONArray("checks")
            assertEquals("[1,2,3]", checks.getJSONObject(0).getJSONArray("expected").toString())
            assertEquals("[3,1,2]", checks.getJSONObject(0).getJSONArray("actual").toString())
        }
        assertEquals(before, f.rows.data)
        assertTrue(matches.none { it.getString("kind") == RELEASE })
    }

    @Test fun preExecutionRejectionBelongsToTestPlanNotAnUnresolvedSource() {
        val f = CollaborationExecutableToolTest.Fixture()
        save(f, result = JSONObject().put("status", "failed").put("error", JSONObject().put("code", "runtime_unavailable")))
        val workspace = f.reopen()
        val plan = entries(workspace.methodHistory(f.access(), f.plan)).single()
        assertEquals("requested_test_plan", plan.getString("subject_binding"))
        assertFalse(plan.getBoolean("runtime_report_available"))
        assertTrue(plan.isNull("runtime_reported_passed"))
        assertTrue(entries(workspace.methodHistory(f.access(), f.tool)).isEmpty())
    }

    @Test fun successfulTestsAreHistoryNotAutomaticReleaseOrNewExecution() {
        val f = CollaborationExecutableToolTest.Fixture()
        val result = output(f, true).put("receipt", JSONObject().put("replayed", true)
            .put("invocation_id", "replay").put("original_invocation_id", "original"))
        repeat(3) { save(f, "same", result) }
        val row = entries(f.reopen().methodHistory(f.access(), f.tool)).single()
        assertTrue(row.getBoolean("runtime_reported_passed"))
        assertTrue(row.getBoolean("replayed"))
        assertTrue(row.isNull("quality_effect"))
        assertEquals("original", row.getString("original_invocation_id"))
        assertTrue(runCatching { f.prepare(JSONObject().put("mode", "run").put(RELEASE, f.tool)
            .put("parameters", JSONObject().put("values", JSONArray()))) }.isFailure)
    }

    @Test fun mismatchedRuntimePlanSourceAndModeCannotInventCandidateHistory() {
        for (field in listOf(TEST, TOOL, "mode")) {
            val f = CollaborationExecutableToolTest.Fixture()
            val result = output(f, false)
            val receipt = result.getJSONObject("output").getJSONObject(RECEIPT)
            if (field == "mode") receipt.put(field, "run") else receipt.getJSONObject(field).put("sha256", "0".repeat(64))
            save(f, result = result)
            assertTrue(entries(f.reopen().methodHistory(f.access(), f.tool)).isEmpty())
            if (field != TOOL) assertTrue(entries(f.reopen().methodHistory(f.access(), f.plan)).isEmpty())
        }
        val f = CollaborationExecutableToolTest.Fixture()
        for (origin in listOf(CollaborationEvidenceOrigin.ANDROID_CLOUD_TOOL, CollaborationEvidenceOrigin.DESKTOP_CODEX_TOOL))
            save(f, origin.name, origin = origin)
        assertTrue(entries(f.reopen().methodHistory(f.access(), f.tool)).isEmpty())
    }

    @Test fun testsAndSourceMustBeVisibleSeparatelyAndExpectedAnswersAreNotSearchTerms() {
        val f = CollaborationExecutableToolTest.Fixture()
        val spec = JSONObject(f.spec.toString()).put("purpose", "quasarneedle transformation")
            .put("source", "def run(parameters):\n    return 'secretcodeword'\n")
        val source = f.ref(f.publish("new-source", TOOL, spec, "new-author", 5))
        val planSpec = JSONObject(f.planSpec.toString()).put(TOOL, source)
        planSpec.getJSONArray("cases").getJSONObject(0).put("expected", "secretanswerword")
        val publication = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Scoped synthetic test")
            .put("workspace", JSONArray().put(JSONObject().put("id", "new-plan").put("kind", TEST).put("title", "new-plan")
                .put("body", JSONObject().put(TEST, planSpec))))
        val plan = f.ref(f.workspace.publish(f.access("new-author", 5, "new-plan").copy(dependencyNodes = setOf("new-source")),
            publication.toString()))
        val blind = f.access("peer", 5).copy(dependencyNodes = setOf("new-plan"))
        assertNotNull(f.workspace.read(blind, plan.getString("object_id"), 1))
        assertNull(f.workspace.read(blind, source.getString("object_id"), 1))
        assertTrue(entries(f.workspace.searchCapabilities(blind, "quasarneedle")).isEmpty())
        val allowed = blind.copy(dependencyNodes = blind.dependencyNodes + "new-source")
        val matches = entries(f.workspace.searchCapabilities(allowed, "quasarneedle"))
        val found = matches.single { it.getString("kind") == TEST }
        assertEquals(source.getString("sha256"), found.getJSONArray("linked_sources").getJSONObject(0).getJSONObject("source").getString("sha256"))
        assertFalse(found.getJSONArray("linked_sources").getJSONObject(0).getBoolean("complete_read"))
        for (query in listOf("secretcodeword", "secretanswerword")) assertTrue(entries(f.workspace.searchCapabilities(allowed, query)).isEmpty())
    }

    @Test fun linkedTestMetadataRequiresExactSourceKindAndDigest() {
        val f = CollaborationExecutableToolTest.Fixture()
        val plan = f.resolve(f.plan, TEST)
        val source = f.resolve(f.tool, TOOL)
        for (change in listOf<(JSONObject) -> Unit>({ it.put("sha256", "changed") }, { it.put("kind", "artifact") })) {
            assertNull(CollaborationCapabilityRecall.match(plan, CollaborationCapabilityRecall.query("stable")) {
                JSONObject(source.toString()).apply(change)
            })
        }
    }

    @Test fun pagedCandidateHistoryPreservesIsolationAndQueryIdentity() {
        val f = CollaborationExecutableToolTest.Fixture()
        repeat(43) { save(f, "case-$it") }
        val workspace = f.reopen()
        val peer = f.access("peer", 3)
        val hidden = workspace.methodHistory(peer, f.tool)
        assertTrue(entries(hidden).isEmpty())
        assertFalse(hidden.getBoolean("scan_complete"))
        val allowed = peer.copy(dependencyNodes = setOf("tester"))
        var page = workspace.methodHistory(allowed, f.tool)
        val cursor = page.getString("next_cursor")
        assertTrue(runCatching { workspace.methodHistory(allowed, f.plan, cursor) }.isFailure)
        assertTrue(runCatching { workspace.methodHistory(peer, f.tool, cursor) }.isFailure)
        val observed = mutableSetOf<String>()
        do {
            entries(page).forEach { assertTrue(observed.add(it.getString("evidence_id"))) }
            if (page.isNull("next_cursor")) break
            page = f.reopen().methodHistory(allowed, f.tool, page.getString("next_cursor"))
        } while (true)
        assertEquals(43, observed.size)
        assertTrue(runCatching { workspace.methodHistory(allowed.copy(groupId = "other"), f.tool) }.isFailure)
        val denied = CollaborationResearchWorkspace(f.rows, accessAuthorized = { false }, toolExperience = { _, _, _ -> error("No read") })
        assertTrue(runCatching { denied.methodHistory(allowed, f.tool) }.isFailure)
    }

    @Test fun callerCannotRelabelCandidateAsReleasedByAddingKind() {
        val f = CollaborationExecutableToolTest.Fixture()
        save(f)
        val page = f.reopen().methodHistory(f.access(), JSONObject(f.tool.toString()).put("kind", RELEASE))
        assertEquals(TOOL, page.getString("subject_kind"))
        assertEquals("runtime_resolved_candidate", entries(page).single().getString("subject_binding"))
    }
}
