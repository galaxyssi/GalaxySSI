package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationResultEvidenceTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        override fun read(key: String) = data[key]
        override fun commit(values: Map<String, String>) { data.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
    }
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "node", "author")
    private fun record(ledger: CollaborationEvidenceLedger, name: String = "call") =
        ledger.record(access, name, "calculate", "{}", "{\"status\":\"success\",\"value\":7}", 1, 2)
    private fun raw(refs: JSONArray = JSONArray(), body: JSONObject = JSONObject().put("content", "A candidate, not yet validated")) =
        JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Candidate result")
            .put("workspace", JSONArray().put(JSONObject().put("id", "candidate").put("kind", "artifact")
                .put("title", "Candidate").put("body", body).put("observations", refs)))

    @Test fun noNewObservationsDoesNotWaitForUnrelatedHistoryOrQueryTheLedger() {
        assertFalse(CollaborationResultEvidence.inspect(raw().toString()).awaiting(
            { error("No need to scan import jobs") }, { error("No required evidence") }))
    }

    @Test fun exactAvailableObservationsReleaseResultWhileOtherImportsRemainPending() {
        val ledger = CollaborationEvidenceLedger(Rows())
        val ref = record(ledger)
        assertFalse(CollaborationResultEvidence.inspect(raw(JSONArray().put(ref)).toString())
            .awaiting({ true }) { ledger.read(access, it) })
    }

    @Test fun missingRequiredObservationWaitsThenReleasesAfterDurableImport() {
        val source = CollaborationEvidenceLedger(Rows())
        val ref = record(source)
        val rows = Rows()
        var phone = CollaborationEvidenceLedger(rows)
        val gate = CollaborationResultEvidence.inspect(raw(JSONArray().put(ref)).toString())
        assertTrue(gate.awaiting({ true }) { phone.read(access, it) })
        assertEquals(ref.toString(), record(phone).toString())
        phone = CollaborationEvidenceLedger(rows)
        assertFalse(gate.awaiting({ true }) { phone.read(access, it) })
    }

    @Test fun endedImportLetsTheValidatorReportMissingEvidenceRatherThanWaitForever() {
        val ref = record(CollaborationEvidenceLedger(Rows()))
        val gate = CollaborationResultEvidence.inspect(raw(JSONArray().put(ref)).toString())
        assertFalse(gate.awaiting({ false }) { error("No pending importer can supply this") })
        val workspace = CollaborationResearchWorkspace(Rows(), evidence = CollaborationEvidenceLedger(Rows())::references)
        val receipt = workspace.publish(access, raw(JSONArray().put(ref)).toString())
        assertEquals("rejected", receipt.getString("status"))
        assertTrue(receipt.getString("reason").contains("missing, changed or isolated"))
    }

    @Test fun wrongDigestReachesValidationWithoutWaitingAndCannotBePublished() {
        val ledger = CollaborationEvidenceLedger(Rows())
        val ref = record(ledger).put("sha256", "0".repeat(64))
        val output = raw(JSONArray().put(ref)).toString()
        assertFalse(CollaborationResultEvidence.inspect(output).awaiting({ true }) { ledger.read(access, it) })
        assertEquals("rejected", CollaborationResearchWorkspace(Rows(), evidence = ledger::references)
            .publish(access, output).getString("status"))
    }

    @Test fun duplicatesAndNestedTypedReceiptsUseTheSameExactLookup() {
        val ref = record(CollaborationEvidenceLedger(Rows()))
        val body = JSONObject().put("probe", JSONObject().put("checks", JSONArray().put(
            JSONObject().put("observation", ref))))
        val gate = CollaborationResultEvidence.inspect(raw(JSONArray().put(ref).put(ref), body).toString())
        val lookedUp = mutableListOf<String>()
        assertTrue(gate.awaiting({ true }) { lookedUp.add(it); null })
        assertEquals(listOf(ref.getString("evidence_id")), lookedUp)
    }

    @Test fun nestedBodyReceiptAloneStillWaitsAndJsonInsideProseDoesNot() {
        val ref = record(CollaborationEvidenceLedger(Rows()))
        val nested = raw(body = JSONObject().put("experiment", JSONObject().put("observation", ref)))
        assertTrue(CollaborationResultEvidence.inspect(nested.toString()).awaiting({ true }) { null })
        val prose = raw(body = JSONObject().put("content", ref.toString()))
        assertFalse(CollaborationResultEvidence.inspect(prose.toString()).awaiting({ true }) { error("Prose is not a receipt") })
    }

    @Test fun invalidArtifactAndInvalidReceiptGoStraightToExistingValidationFeedback() {
        val ref = JSONObject().put("evidence_id", "invented").put("sha256", "invalid")
        val absent = record(CollaborationEvidenceLedger(Rows()))
        listOf("{broken", "Ordinary final Markdown", raw(JSONArray().put(ref)).toString(),
            raw().put("workspace", "invalid").toString(),
            raw(JSONArray().put(absent).put("not an observation")).toString(),
            raw(JSONArray().put(absent).put(JSONObject().put("sha256", "0".repeat(64)))).toString()).forEach { raw ->
            assertFalse(CollaborationResultEvidence.inspect(raw).awaiting({ true }) { error("Invalid receipt") })
        }
    }

    @Test fun fencedArtifactPreservesReferencesButModelOwnedHostMetadataDoesNotAddThem() {
        val ref = record(CollaborationEvidenceLedger(Rows()))
        assertTrue(CollaborationResultEvidence.inspect("```json\n${raw(JSONArray().put(ref))}\n```")
            .awaiting({ true }) { null })
        val metadata = raw().put("remote_evidence_import", ref).put("delivery_receipt", ref)
        assertFalse(CollaborationResultEvidence.inspect(metadata.toString()).awaiting({ true }) { error("Untrusted metadata") })
    }

    @Test fun availableDoesNotRecordModelReadCoverageOrVerifyClaims() {
        val ledger = CollaborationEvidenceLedger(Rows())
        val ref = record(ledger)
        val reviewer = access.copy(nodeId = "reviewer", personId = "reviewer", dependencyNodes = setOf("node"))
        val output = raw(JSONArray().put(ref)).toString()
        assertFalse(CollaborationResultEvidence.inspect(output).awaiting({ true }) { ledger.read(reviewer, it) })
        val workspace = CollaborationResearchWorkspace(Rows(), evidence = ledger::references)
        assertEquals("recorded", workspace.publish(reviewer, output).getString("status"))
        val version = workspace.browse(reviewer).revisions.single()
        val saved = workspace.read(reviewer, version.getString("object_id"), version.getInt("revision"))!!
        assertEquals("member_reported_not_verified", saved.getString("evidence_state"))
        assertThrows(IllegalArgumentException::class.java) { ledger.requireReadCoverage(reviewer, saved) }
    }

    @Test fun isolationAndRevocationRemainMissingEvenIfTheBytesExist() {
        val rows = Rows()
        var allowed = true
        val ledger = CollaborationEvidenceLedger(rows, authorized = { allowed })
        val ref = record(ledger)
        val gate = CollaborationResultEvidence.inspect(raw(JSONArray().put(ref)).toString())
        val other = access.copy(nodeId = "independent", personId = "peer")
        assertTrue(gate.awaiting({ true }) { ledger.read(other, it) })
        assertFalse(gate.awaiting({ true }) { ledger.read(other.copy(dependencyNodes = setOf("node")), it) })
        allowed = false
        assertTrue(gate.awaiting({ true }) { ledger.read(access, it) })
    }

    @Test fun corruptOriginalFailsClosedWithoutHidingStorageFailure() {
        val rows = Rows()
        val ledger = CollaborationEvidenceLedger(rows)
        val ref = record(ledger)
        val key = rows.data.keys.single()
        val envelope = JSONObject(rows.data.getValue(key)).put("sha256", "0".repeat(64))
        rows.data[key] = envelope.toString()
        assertThrows(IllegalStateException::class.java) {
            CollaborationResultEvidence.inspect(raw(JSONArray().put(ref)).toString())
                .awaiting({ true }) { ledger.read(access, it) }
        }
    }
}
