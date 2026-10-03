package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationCandidateReadCoverageTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        override fun read(key: String) = data[key]
        override fun commit(values: Map<String, String>) { data.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
    }

    private class Fixture {
        val rows = Rows()
        val originals = Rows()
        val ledger = CollaborationEvidenceLedger(originals)
        val workspace get() = CollaborationResearchWorkspace(rows, evidence = ledger::references,
            evidenceReadCoverage = ledger::requireReadCoverage)
        val author = CollaborationWorkspaceAccess("group", "run", "turn", 0, "author", "author")
        val reviewer = author.copy(round = 2, nodeId = "review", personId = "reviewer")
        val inspector = reviewer.copy(round = 10, nodeId = "inspect", personId = "coordinator")
        val source = ledger.record(author, "source", "original_check", "{}",
            JSONObject().put("data", "abc ".repeat(6000)).toString(), 1, 2)
        val candidate = JSONObject().put("id", "route").put("kind", "candidate").put("title", "Route")
            .put("body", JSONObject().put("content", "Original proposal").put("candidate", JSONObject()
                .put("operation", "propose").put("rationale", "An alternative to inspect").put("criteria", JSONArray().put("Accuracy"))))
        val target = workspace.publish(author, raw(candidate)).getJSONArray("revisions").getJSONObject(0)
        fun review(outcome: String = "supported", references: JSONArray = JSONArray().put(source)) = JSONObject()
            .put("id", "review").put("kind", "candidate_event").put("title", "Independent check").put("observations", references)
            .put("body", JSONObject().put("candidate_event", JSONObject().put("operation", "review")
                .put("targets", JSONArray().put(target)).put("criterion", "Accuracy").put("check", "Compare original source")
                .put("rationale", "Documentary assessment only").put("outcome", outcome)
                .put("unresolved", JSONArray().apply { if (outcome != "supported") put("Needs correction") })))
        fun readAll(who: CollaborationWorkspaceAccess = reviewer, ref: JSONObject = source) {
            var offset: Int? = 0
            while (offset != null) offset = ledger.readPage(who, ref.getString("evidence_id"), ref.getString("sha256"), offset)!!.next
        }
        fun task() = JSONObject().put("operation", "review").put("target", target).put("member", reviewer.personId)
            .put("group_id", reviewer.groupId).put("run_id", reviewer.runId).put("turn_id", reviewer.turnId)
            .put("criterion", JSONObject().put("id", "accuracy").put("requirement", "Accuracy").put("verification", "documentary")
                .put("required_observations", JSONArray().put(JSONObject().put("origin", "android_cloud_tool").put("tool", "original_check"))))
    }

    @Test fun browsingOrCitingAnOriginalCannotPublishAnyIndependentVerdict() {
        for (outcome in listOf("supported", "refuted", "not_tested")) {
            val f = Fixture()
            assertTrue(f.ledger.browse(f.reviewer).first.isNotEmpty())
            val result = f.workspace.publish(f.reviewer, raw(f.review(outcome)))
            assertEquals("rejected", result.getString("status"))
            assertTrue(result.getString("reason").contains("not fully served"))
            assertTrue(f.workspace.publicationRevisions(f.inspector, f.reviewer.nodeId).isEmpty())
        }
    }

    @Test fun partialReadDraftCanRepairOnlyAfterAllPagesAreReadInTheSameDispatch() {
        val f = Fixture()
        f.workspace.enrollPublication(f.reviewer, CollaborationResearchStage.VERIFY, f.task())
        val recovery = CollaborationPublicationRecovery(f.workspace, f.reviewer)
        val first = f.ledger.readPage(f.reviewer, f.source.getString("evidence_id"), f.source.getString("sha256"))!!
        assertNotNull(first.next)
        assertFalse(recovery.accept(raw(f.review())))
        assertTrue(recovery.repairing)
        assertTrue(recovery.permitsTool(CollaborationCloudRecall.NAME))
        assertFalse(recovery.permitsTool("run_command"))
        f.readAll()
        assertTrue(CollaborationPublicationRecovery(f.workspace, f.reviewer).accept(raw(f.review())))
        val saved = f.workspace.publicationRevisions(f.inspector, f.reviewer.nodeId).single()
        assertTrue(f.workspace.candidateReviewApplies(f.inspector, CollaborationResearchCandidates.reference(saved)))
        assertTrue(saved.getJSONArray("host_observations").getJSONObject(0)
            .getJSONObject(CollaborationEvidenceReadCoverage.FIELD).getBoolean("complete"))
    }

    @Test fun anotherDispatchOrMemberCannotDonateItsReadCoverage() {
        for (other in listOf("node", "person", "round", "turn", "run")) {
            val f = Fixture()
            val reader = when (other) {
                "node" -> f.reviewer.copy(nodeId = "another")
                "person" -> f.reviewer.copy(personId = "another")
                "round" -> f.reviewer.copy(round = 3)
                "turn" -> f.reviewer.copy(turnId = "another")
                else -> f.reviewer.copy(runId = "another", turnId = "another")
            }
            f.readAll(reader)
            val spoofed = f.ledger.references(reader, JSONArray().put(f.source))
            assertEquals("rejected", f.workspace.publish(f.reviewer, raw(f.review(references = spoofed))).getString("status"))
        }
    }

    @Test fun desktopPreparedButUnconfirmedPagesDoNotCount() {
        val f = Fixture()
        var offset: Int? = 0
        while (offset != null) offset = f.ledger.readPage(f.reviewer, f.source.getString("evidence_id"),
            f.source.getString("sha256"), offset, recordCoverage = false)!!.next
        f.workspace.enrollPublication(f.reviewer, CollaborationResearchStage.VERIFY, f.task())
        assertFalse(CollaborationPublicationRecovery(f.workspace, f.reviewer).accept(raw(f.review())))
        offset = 0
        while (offset != null) {
            val page = f.ledger.readPage(f.reviewer, f.source.getString("evidence_id"), f.source.getString("sha256"),
                offset, recordCoverage = false)!!
            f.ledger.confirmPage(f.reviewer, f.source.getString("evidence_id"), f.source.getString("sha256"), offset,
                MqttImmutableContent.sha256(page.content))
            offset = page.next
        }
        assertTrue(CollaborationPublicationRecovery(f.workspace, f.reviewer).accept(raw(f.review())))
    }

    @Test fun everyCitedOriginalMustBeCoveredAndMixedPublicationIsAtomic() {
        val f = Fixture()
        f.readAll()
        val second = f.ledger.record(f.author, "second", "original_check", "{}", "second original", 3, 4)
        val unrelated = JSONObject().put("id", "unrelated").put("kind", "proposal").put("title", "Retain atomically")
            .put("body", JSONObject().put("content", "Must not commit when review fails"))
        assertEquals("rejected", f.workspace.publish(f.reviewer,
            raw(unrelated, f.review(references = JSONArray().put(f.source).put(second)))).getString("status"))
        assertEquals(1, f.workspace.browse(f.inspector).revisions.size)
    }

    @Test fun ownObservedToolResultIsAllowedButDoesNotReplaceUnreadPeerEvidence() {
        val f = Fixture()
        val own = f.ledger.record(f.reviewer, "own", "read_original", "{}", "{\"status\":\"returned\"}", 3, 4)
        val refs = JSONArray().put(f.source).put(own)
        f.workspace.enrollPublication(f.reviewer, CollaborationResearchStage.VERIFY, f.task())
        assertFalse(CollaborationPublicationRecovery(f.workspace, f.reviewer).accept(raw(f.review(references = refs))))
        f.readAll()
        assertTrue(CollaborationPublicationRecovery(f.workspace, f.reviewer).accept(raw(f.review(references = refs))))
    }

    @Test fun validatorAbsenceFailsClosedEvenWithCompleteCoverage() {
        val f = Fixture()
        f.readAll()
        val workspace = CollaborationResearchWorkspace(f.rows, evidence = f.ledger::references)
        assertEquals("rejected", workspace.publish(f.reviewer, raw(f.review())).getString("status"))
    }

    @Test fun lateReadsCannotRetroactivelyQualifyLegacyReviewOrItsRepairBasis() {
        val f = Fixture()
        // Reproduce a pre-fix publication that retained a citation without requiring original-page reads.
        val legacy = CollaborationResearchWorkspace(f.rows, evidence = f.ledger::references, evidenceReadCoverage = { _, _ -> })
        val draft = raw(f.review("refuted"))
        val ref = legacy.publish(f.reviewer, draft, candidateTask = f.task()).getJSONArray("revisions").getJSONObject(0)
        val original = f.workspace.read(f.inspector, ref.getString("object_id"), 1)!!.toString()
        f.readAll()
        assertFalse(f.workspace.candidateReviewApplies(f.inspector, ref))
        assertThrows(IllegalArgumentException::class.java) { f.workspace.publicationRevisions(f.inspector, f.reviewer.nodeId) }
        assertThrows(IllegalArgumentException::class.java) { f.workspace.replayCandidateTask(f.reviewer, f.task()) }
        assertThrows(IllegalArgumentException::class.java) { f.workspace.publish(f.reviewer, draft, candidateTask = f.task()) }
        val repair = JSONObject(f.candidate.toString()).put("object_id", f.target.getString("object_id")).put("base_revision", 1)
            .put("parents", JSONArray().put(f.target)).put("observations", JSONArray().put(f.source)).apply {
                getJSONObject("body").getJSONObject("candidate").put("operation", "revise").put("basis", ref)
            }
        assertEquals("rejected", f.workspace.publish(f.inspector.copy(nodeId = "repair"), raw(repair)).getString("status"))
        assertEquals(original, f.workspace.read(f.inspector, ref.getString("object_id"), 1)!!.toString())
        assertTrue(f.workspace.isCurrent(f.inspector, f.target.getString("object_id"), 1))
    }

    @Test fun completeCoverageSurvivesStoreReopenAndMissingOriginalCannotReplay() {
        val f = Fixture()
        f.readAll()
        val raw = raw(f.review())
        val ref = f.workspace.publish(f.reviewer, raw, candidateTask = f.task()).getJSONArray("revisions").getJSONObject(0)
        val reopened = CollaborationEvidenceLedger(f.originals)
        val workspace = CollaborationResearchWorkspace(f.rows, evidence = reopened::references, evidenceReadCoverage = reopened::requireReadCoverage)
        assertTrue(workspace.candidateReviewApplies(f.inspector, ref))
        assertNotNull(workspace.replayCandidateTask(f.reviewer, f.task()))
        f.originals.data.keys.filter { ":observation:" in it }.toList().forEach(f.originals.data::remove)
        assertFalse(workspace.candidateReviewApplies(f.inspector, ref))
        assertThrows(IllegalArgumentException::class.java) { workspace.replayCandidateTask(f.reviewer, f.task()) }
    }

    companion object {
        private fun raw(vararg items: JSONObject) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
            .put("summary", "Fixture only").put("candidates", JSONArray()).put("findings", JSONArray())
            .put("workspace", JSONArray(items.toList())).toString()
    }
}
