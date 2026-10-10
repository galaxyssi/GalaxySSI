package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationToolExperienceTest {
    private val release = JSONObject().put("object_id", "a".repeat(64)).put("revision", 1).put("sha256", "b".repeat(64))
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "worker", "author")
    private fun request(ref: JSONObject = release) = JSONObject().put("collaboration_tool", JSONObject()
        .put("mode", "run").put("tool_release", ref).put("parameters", JSONObject().put("value", 7)))
    private fun output(passed: Boolean = true, replayed: Boolean = false) = JSONObject()
        .put("status", if (passed) "succeeded" else "failed").put("receipt", JSONObject()
            .put("invocation_id", "native-call").put("original_invocation_id", if (replayed) "original-call" else JSONObject.NULL)
            .put("replayed", replayed))
        .put("output", JSONObject().put("collaboration_tool_receipt", JSONObject().put("tool_release", release).put("passed", passed)))
    private fun save(ledger: CollaborationEvidenceLedger, id: String = "call", input: JSONObject = request(), result: JSONObject = output(),
                     origin: CollaborationEvidenceOrigin = CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL,
                     tool: String = AgentOnDeviceRuntimeTools.EXECUTE) = ledger.record(access, id, tool, input.toString(), result.toString(), 1, 2, origin)
    private fun entries(page: JSONObject) = page.getJSONArray("records").let { a -> (0 until a.length()).map(a::getJSONObject) }

    @Test fun oldOriginalsAreQueryableAfterReopenWithoutMigrationOrNewWrites() {
        val rows = CollaborationEvolutionTest.Rows(); val ledger = CollaborationEvidenceLedger(rows)
        val ref = save(ledger); val before = rows.data.toMap()
        val future = access.copy(runId = "future", turnId = "future", round = 0)
        val page = CollaborationEvidenceLedger(rows).toolHistory(future, release)
        val result = entries(page).single()
        assertEquals(before, rows.data)
        assertEquals(ref.getString("evidence_id"), result.getString("evidence_id"))
        assertTrue(result.getBoolean("runtime_reported_passed")); assertTrue(result.isNull("quality_effect"))
        assertFalse(result.has("parameters")); assertFalse(result.has("content"))
        val read = result.getJSONObject("read_original")
        assertEquals("evidence", read.getString("mode"))
        assertEquals(request().toString(), ledger.read(future, read.getString("evidence_id"), read.getString("sha256"))!!.getString("input_json"))
        assertFalse(ledger.readPage(future, read.getString("evidence_id"), read.getString("sha256"), recordCoverage = false)!!.coverage.getBoolean("complete"))
    }

    @Test fun rejectionBeforeRuntimeAndReplaysAreNotReportedAsNewSuccessfulExecutions() {
        val ledger = CollaborationEvidenceLedger(CollaborationEvolutionTest.Rows())
        save(ledger, "failed", result = JSONObject().put("status", "failed").put("error", JSONObject().put("code", "invalid_input")))
        save(ledger, "replayed", result = output(replayed = true))
        val rows = entries(ledger.toolHistory(access, release))
        val failed = rows.single { it.getString("native_status") == "failed" }
        assertFalse(failed.getBoolean("runtime_report_available")); assertTrue(failed.isNull("runtime_reported_passed"))
        assertEquals("requested_release", failed.getString("release_binding"))
        val replay = rows.single { it.optBoolean("replayed") }
        assertEquals("original-call", replay.getString("original_invocation_id"))
        assertTrue(replay.isNull("quality_effect"))
    }

    @Test fun cloudClaimsOtherToolsTestsAndDifferentReleasesAreExcluded() {
        val ledger = CollaborationEvidenceLedger(CollaborationEvolutionTest.Rows())
        save(ledger, "cloud", origin = CollaborationEvidenceOrigin.ANDROID_CLOUD_TOOL)
        save(ledger, "desktop", origin = CollaborationEvidenceOrigin.DESKTOP_CODEX_TOOL)
        save(ledger, "other-tool", tool = "web_fetch")
        save(ledger, "test", input = request().apply { getJSONObject("collaboration_tool").put("mode", "test") })
        save(ledger, "version", input = request(JSONObject(release.toString()).put("revision", 2)))
        save(ledger, "different", input = request(JSONObject(release.toString()).put("sha256", "c".repeat(64))))
        assertTrue(entries(ledger.toolHistory(access, release)).isEmpty())
    }

    @Test fun channelNeedsExactRuntimeResolvedVersionAndMatchingChannel() {
        val ledger = CollaborationEvidenceLedger(CollaborationEvolutionTest.Rows())
        val channel = JSONObject(release.toString()).put("object_id", "c".repeat(64))
        val input = request().apply { getJSONObject("collaboration_tool").remove("tool_release")
            getJSONObject("collaboration_tool").put("capability_channel", channel) }
        save(ledger, "unresolved", input, JSONObject().put("status", "failed"))
        save(ledger, "mismatch", input, output())
        save(ledger, "resolved", input, output().apply { getJSONObject("output").getJSONObject("collaboration_tool_receipt").put("capability_channel", channel) })
        assertEquals("runtime_resolved_channel_release", entries(ledger.toolHistory(access, release)).single().getString("release_binding"))
    }

    @Test fun isolationRevocationAndQueryBoundCursorsSurvivePagination() {
        val rows = CollaborationEvolutionTest.Rows(); var allowed = true
        val ledger = CollaborationEvidenceLedger(rows) { allowed }
        repeat(43) { save(ledger, "call-$it") }
        val peer = access.copy(personId = "peer", nodeId = "peer")
        val hidden = ledger.toolHistory(peer, release)
        assertTrue(entries(hidden).isEmpty()); assertFalse(hidden.isNull("next_cursor"))
        val cursor = hidden.getString("next_cursor")
        for (changed in listOf(peer.copy(pinnedReads = setOf("new")), peer.copy(dependencyNodes = setOf("worker")), peer.copy(turnId = "new")))
            assertTrue(runCatching { ledger.toolHistory(changed, release, cursor) }.isFailure)
        assertTrue(runCatching { ledger.toolHistory(peer, JSONObject(release.toString()).put("revision", 2), cursor) }.isFailure)
        assertTrue(entries(ledger.toolHistory(access.copy(groupId = "other"), release)).isEmpty())
        val reader = peer.copy(dependencyNodes = setOf("worker"))
        var page = ledger.toolHistory(reader, release); val ids = mutableSetOf<String>()
        do {
            entries(page).forEach { assertTrue(ids.add(it.getString("evidence_id"))) }
            if (page.isNull("next_cursor")) break
            page = ledger.toolHistory(reader, release, page.getString("next_cursor"))
        } while (true)
        assertEquals(43, ids.size)
        allowed = false
        assertTrue(runCatching { ledger.toolHistory(reader, release) }.isFailure)
    }

    @Test fun emptyUnrelatedPagesContinueToLaterVisibleToolExperience() {
        val rows = CollaborationEvolutionTest.Rows(); val ledger = CollaborationEvidenceLedger(rows)
        repeat(25) { save(ledger, "other-$it", origin = CollaborationEvidenceOrigin.ANDROID_CLOUD_TOOL) }
        val page = ledger.toolHistory(access, release)
        assertTrue(entries(page).isEmpty()); assertFalse(page.getBoolean("scan_complete"))
        assertTrue(ledger.toolHistory(access, release, page.getString("next_cursor")).getBoolean("scan_complete"))
        for (cursor in listOf("bad", "{}", "x".repeat(513))) assertTrue(runCatching { ledger.toolHistory(access, release, cursor) }.isFailure)
    }

    @Test fun corruptedEvidenceIsNotReturnedAndRepeatedObservationIsIdempotent() {
        val rows = CollaborationEvolutionTest.Rows(); val ledger = CollaborationEvidenceLedger(rows)
        repeat(3) { save(ledger) }
        assertEquals(1, entries(ledger.toolHistory(access, release)).size)
        val key = rows.data.keys.single { it.contains(":observation:") }
        rows.data[key] = JSONObject(rows.data.getValue(key)).put("sha256", "0".repeat(64)).toString()
        assertTrue(runCatching { ledger.toolHistory(access, release) }.isFailure)
    }

    @Test fun capabilityDiscoveryAndWorkspaceHistoryUseSameExactReleaseWithoutGrantingExecution() {
        val f = CollaborationExecutableToolTest.Fixture(); val release = f.ref(f.release())
        val reference = CollaborationResearchCandidates.reference(release)
        val future = f.access().copy(runId = "future", turnId = "future", round = 0)
        val workspace = CollaborationResearchWorkspace(f.rows, toolExperience = f.ledger::toolHistory)
        val matches = entries(workspace.searchCapabilities(future, "sort"))
        val found = matches.single { it.getString("kind") == CollaborationExecutableTool.RELEASE }
        assertEquals("method_history", found.getJSONObject("usage_recall").getString("mode"))
        assertEquals(reference.getString("sha256"), found.getJSONObject("usage_recall").getString("sha256"))
        assertEquals("original_native_tool_observation", workspace.methodHistory(future, reference).getString("record_kind"))
        assertTrue(entries(workspace.methodHistory(future, reference)).isEmpty())
        assertTrue(runCatching { workspace.methodHistory(future, JSONObject(reference.toString()).put("sha256", "d".repeat(64))) }.isFailure)
        val denied = CollaborationResearchWorkspace(f.rows, accessAuthorized = { false }, toolExperience = { _, _, _ -> error("Must not query") })
        assertTrue(runCatching { denied.methodHistory(future, reference) }.isFailure)
    }
}
