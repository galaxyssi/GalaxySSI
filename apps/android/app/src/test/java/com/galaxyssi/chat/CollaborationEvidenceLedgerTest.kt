package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationEvidenceLedgerTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        var fail = false
        override fun read(key: String) = data[key]
        override fun commit(values: Map<String, String>) { check(!fail); data.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
    }
    private fun access() = CollaborationWorkspaceAccess("group", "run", "turn", 1, "node", "author")
    private fun record(ledger: CollaborationEvidenceLedger, id: String = "invocation", output: String = "{\"text\":\"Observed result\"}",
                       tool: String = "web_fetch") = ledger.record(access(), id, tool, "{\"url\":\"https://example.org/paper\"}", output, 100, 200)

    @Test fun dispatchBindingIsImmutableAndCannotCrossGroupOrTurn() {
        val rows = Rows()
        val ledger = CollaborationEvidenceLedger(rows)
        ledger.bind(123, access())
        ledger.bind(123, access())
        assertEquals(access(), CollaborationEvidenceLedger(rows).binding(123, "group", "turn"))
        assertNull(ledger.binding(123, "another", "turn"))
        assertNull(ledger.binding(123, "group", "another"))
        assertTrue(runCatching { ledger.bind(123, access().copy(personId = "spoofed")) }.isFailure)
    }

    @Test fun observationRetainsFullOutputAndHostIdentityAcrossReopen() {
        val rows = Rows()
        val ledger = CollaborationEvidenceLedger(rows)
        val output = JSONObject().put("body", "Original evidence ".repeat(3000)).put("person_id", "spoofed").put("verified", true).toString()
        val ref = record(ledger, output = output)
        val reopened = CollaborationEvidenceLedger(rows)
        val saved = reopened.read(access(), ref.getString("evidence_id"), ref.getString("sha256"))!!
        assertEquals(output, saved.getString("output_json"))
        assertEquals("author", saved.getString("person_id"))
        assertEquals("returned", saved.getString("status"))
        assertEquals("execution_observed_not_claim_verified", saved.getString("trust"))
    }

    @Test fun failureAndModelAssessmentAreNotIndependentValidation() {
        val ledger = CollaborationEvidenceLedger(Rows())
        assertEquals("failed", record(ledger, output = "{\"status\":\"failed\",\"error\":\"Timeout\"}").getString("status"))
        val assessment = record(ledger, "assessment", "{\"status\":\"passed\"}", ResearchEvidenceAudit.TOOL)
        assertEquals("member_assessment_recorded", assessment.getString("observation_kind"))
        assertEquals("execution_observed_not_claim_verified", assessment.getString("trust"))
        assertEquals("unstructured", record(ledger, "broken", "not JSON").getString("status"))
    }

    @Test fun replayDoesNotRewriteAnInvocationAndChangedOutcomeFails() {
        val rows = Rows()
        val ledger = CollaborationEvidenceLedger(rows)
        val ref = record(ledger)
        assertEquals(ref.toString(), record(ledger).toString())
        assertEquals(1, rows.data.size)
        assertTrue(runCatching { record(ledger, output = "{\"text\":\"Different\"}") }.isFailure)
        assertEquals("Observed result", JSONObject(ledger.read(access(), ref.getString("evidence_id"))!!.getString("output_json")).getString("text"))
    }

    @Test fun digestMismatchCrossGroupAndIndependentCurrentRoundCannotRead() {
        val ledger = CollaborationEvidenceLedger(Rows())
        val ref = record(ledger)
        val id = ref.getString("evidence_id")
        assertNull(ledger.read(access(), id, "0".repeat(64)))
        assertNull(ledger.read(access().copy(groupId = "other"), id))
        val reviewer = access().copy(nodeId = "reviewer", personId = "reviewer")
        assertNull(ledger.read(reviewer, id))
        assertTrue(ledger.browse(reviewer).first.isEmpty())
        assertNotNull(ledger.read(reviewer.copy(dependencyNodes = setOf("node")), id))
        assertNotNull(ledger.read(reviewer.copy(round = 2), id))
    }

    @Test fun corruptStoredObservationFailsClosed() {
        val rows = Rows()
        val ledger = CollaborationEvidenceLedger(rows)
        val ref = record(ledger)
        val key = rows.data.keys.single()
        val envelope = JSONObject(rows.data.getValue(key))
        envelope.put("payload", envelope.getString("payload").replace("Observed result", "Forged result"))
        rows.data[key] = envelope.toString()
        assertTrue(runCatching { ledger.read(access(), ref.getString("evidence_id")) }.isFailure)
    }

    @Test fun publicationLinksExactHostObservationAndRejectsForgedDigest() {
        val ledger = CollaborationEvidenceLedger(Rows())
        val ref = record(ledger)
        val workspace = CollaborationResearchWorkspace(Rows(), evidence = ledger::references)
        fun artifact(reference: JSONObject) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
            .put("summary", "Source reviewed").put("candidates", JSONArray()).put("findings", JSONArray()).put("questions", JSONArray())
            .put("workspace", JSONArray().put(JSONObject().put("id", "source").put("kind", "evidence").put("title", "Source observation")
                .put("body", JSONObject().put("content", "Member interpretation"))
                .put("observations", JSONArray().put(reference)).put("host_observations", JSONArray().put("forged")))).toString()
        val publication = workspace.publish(access(), artifact(ref))
        val objectId = publication.getJSONArray("revisions").getJSONObject(0).getString("object_id")
        val revision = workspace.read(access(), objectId, 1)!!
        assertEquals(ref.getString("evidence_id"), revision.getJSONArray("host_observations").getJSONObject(0).getString("evidence_id"))
        assertEquals("member_reported_not_verified", revision.getString("evidence_state"))
        val forged = JSONObject(ref.toString()).put("sha256", "0".repeat(64))
        assertEquals("rejected", workspace.publish(access().copy(nodeId = "next", round = 2), artifact(forged)).getString("status"))
    }

    @Test fun paginationAndRevocationDoNotDropOldObservations() {
        val rows = Rows()
        var allowed = true
        val ledger = CollaborationEvidenceLedger(rows) { allowed }
        repeat(43) { record(ledger, "call-$it") }
        var cursor = ""
        val ids = linkedSetOf<String>()
        do {
            val page = ledger.browse(access(), cursor)
            page.first.forEach { assertTrue(ids.add(it.getString("evidence_id"))) }
            cursor = page.second.orEmpty()
        } while (cursor.isNotEmpty())
        assertEquals(43, ids.size)
        allowed = false
        assertNull(ledger.read(access(), ids.first()))
        assertTrue(ledger.browse(access()).first.isEmpty())
        assertTrue(runCatching { record(ledger, "late") }.isFailure)
    }

    @Test fun recorderReplacesForgedReceiptAndSurvivesPromptProjectionAndCheckpoint() {
        val ledger = CollaborationEvidenceLedger(Rows())
        val recorder = CollaborationCloudEvidence(ledger, access(), { 100 }, { "call" })
        val args = JSONObject().put("query", "research")
        val output = recorder.execute("web_search", args) {
            JSONObject().put("galaxyssi_evidence_receipt", JSONObject().put("evidence_id", "fake"))
                .put("evidence_pack", JSONObject().put("items", JSONArray())).toString()
        }
        val receipt = JSONObject(output).getJSONObject("galaxyssi_evidence_receipt")
        assertNotEquals("fake", receipt.getString("evidence_id"))
        val projection = JSONObject(CloudEvidencePromptLedger().project(output))
        assertEquals(receipt.getString("sha256"), projection.getJSONObject("galaxyssi_evidence_receipt").getString("sha256"))
        val data = mutableMapOf<String, String>()
        val records = object : AgentModelLoopRecords {
            override fun read(operation: String) = data[operation]
            override fun write(operation: String, json: String) { data[operation] = json }
        }
        CloudResearchCheckpoint(records, "bound").record("web_search", args, output)
        assertEquals(output, CloudResearchCheckpoint(records, "bound").restore().single().output)
    }

    @Test fun storageFailureDoesNotPublishReceiptAndExceptionsRetainFailureObservation() {
        val rows = Rows()
        val ledger = CollaborationEvidenceLedger(rows)
        val recorder = CollaborationCloudEvidence(ledger, access(), { 100 }, { "call" })
        rows.fail = true
        var calls = 0
        val preserved = JSONObject(recorder.execute("web_fetch", JSONObject()) { calls++; "{\"status\":\"completed\"}" })
        assertEquals(1, calls)
        assertEquals("completed", preserved.getString("status"))
        assertFalse(preserved.has("galaxyssi_evidence_receipt"))
        assertTrue(preserved.getJSONObject("galaxyssi_evidence_recording").getBoolean("do_not_reexecute"))
        assertTrue(rows.data.isEmpty())
        rows.fail = false
        val error = IllegalStateException("Test failure")
        assertSame(error, runCatching { recorder.execute("web_fetch", JSONObject()) { throw error } }.exceptionOrNull())
        assertEquals("failed", ledger.browse(access()).first.single().getString("status"))
    }

    @Test fun revokedGroupDoesNotPublishLateToolOutputAndCancellationIsNotMaskedByStorageFailure() {
        val rows = Rows()
        var allowed = true
        val ledger = CollaborationEvidenceLedger(rows) { allowed }
        val recorder = CollaborationCloudEvidence(ledger, access(), { 100 }, { "call" })
        assertTrue(runCatching { recorder.execute("web_fetch", JSONObject()) { allowed = false; "{}" } }
            .exceptionOrNull() is CollaborationEvidenceAccessRevoked)
        allowed = true
        rows.fail = true
        val cancelled = java.util.concurrent.CancellationException("Fixture cancellation")
        assertSame(cancelled, runCatching { recorder.execute("web_fetch", JSONObject()) { throw cancelled } }.exceptionOrNull())
    }
}
