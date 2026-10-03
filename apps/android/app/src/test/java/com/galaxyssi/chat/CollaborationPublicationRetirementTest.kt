package com.galaxyssi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationPublicationRetirementTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        var fail = false
        override fun read(key: String) = data[key]
        override fun commit(values: Map<String, String>) { check(!fail); data.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
    }
    private class Fixture {
        val rows = Rows()
        val evidence = Rows()
        val f = CandidateRuntimeFixture(rows, evidence)
        val store = InMemoryAgentTeamExecutionStore().apply { candidateWorkspace = { f.workspace } }
        val staged = runBlocking { CandidateReviewReassignmentFixture.seed(store, f) }
        val next = CandidateReviewReassignmentFixture.replacement(staged)
        val old = staged.definition.members.single { it.memberId == task(next).getJSONObject("review_reassignment").getString("node_id") }
        fun task(member: AgentTeamMember) = JSONObject(member.context.getValue(CollaborationCandidateEvolution.TASK))
        fun access(member: AgentTeamMember) = f.access.copy(nodeId = member.memberId,
            personId = task(member).getString("member"), dependencyNodes = member.dependsOnAgentIds)
        fun claim(workspace: CollaborationResearchWorkspace = f.workspace) =
            workspace.enrollPublication(access(next), CollaborationResearchStage.VERIFY, task(next))
        fun reopen() = CandidateRuntimeFixture(rows, evidence).workspace
    }

    @Test fun retirementAndEnrollmentCommitTogetherAndAreIdempotent() {
        val f = Fixture()
        val before = f.rows.data.toMap()
        f.rows.fail = true
        assertThrows(IllegalStateException::class.java) { f.claim() }
        assertEquals(before, f.rows.data)
        f.rows.fail = false
        f.claim()
        val committed = f.rows.data.toMap()
        assertEquals(2, committed.size - before.size)
        f.claim(f.reopen())
        assertEquals(committed, f.rows.data)
        assertNotNull(f.reopen().publicationContract(f.access(f.next)))
        assertThrows(IllegalArgumentException::class.java) { f.reopen().requirePublicationActive(f.access(f.old)) }
    }

    @Test fun validLateResultCannotPublishWithOrWithoutCandidateMetadataButIsAuditedOnce() {
        val f = Fixture()
        val raw = f.f.draft(f.old)
        f.claim()
        f.f.execute(f.next)
        val workspace = f.reopen()
        val receipt = workspace.publish(f.access(f.old), raw, candidateTask = f.task(f.old))
        assertTrue(receipt.getBoolean("retired"))
        assertEquals("rejected", receipt.getString("status"))
        val count = f.rows.data.size
        assertEquals(receipt.toString(), workspace.publish(f.access(f.old), raw).toString())
        assertEquals(receipt.toString(), workspace.submitPublication(f.access(f.old), raw).toString())
        assertEquals(count, f.rows.data.size)
        assertTrue(workspace.publicationRevisions(f.access(f.old), f.old.memberId).isEmpty())
        assertEquals(raw, workspace.publicationCheckpoint(f.access(f.old))!!.getString("raw"))
        assertEquals(1, workspace.publicationRevisions(f.access(f.next), f.next.memberId).size)
        assertTrue(f.staged.completed.getValue(f.old.memberId).output.contains("no accepted workspace publication"))
        workspace.publish(f.access(f.old), "$raw\n")
        val withAnotherReply = f.rows.data.toMap()
        workspace.publish(f.access(f.old), raw)
        assertEquals(withAnotherReply, f.rows.data)
        assertEquals(2, workspace.publicationCheckpoint(f.access(f.old))!!.getLong("sequence"))
    }

    @Test fun oldPublicationWinningFirstPreventsRetirementAndKeepsItImmutable() {
        val f = Fixture()
        f.f.execute(f.old)
        val before = f.rows.data.toMap()
        assertThrows(IllegalArgumentException::class.java) { f.claim() }
        assertEquals(before, f.rows.data)
        assertTrue(f.rows.data.keys.none { ":retirement:" in it })
        assertNotNull(f.f.workspace.replayCandidateTask(f.access(f.old), f.task(f.old)))
    }

    @Test fun concurrentOldPublicationAndHandoffHaveExactlyOneWinner() {
        repeat(12) {
            val f = Fixture()
            val raw = f.f.draft(f.old)
            val start = CountDownLatch(1)
            val pool = Executors.newFixedThreadPool(2)
            try {
                val claim = pool.submit<Boolean> { start.await(); runCatching { f.claim() }.isSuccess }
                val old = pool.submit<JSONObject> { start.await(); f.f.workspace.publish(f.access(f.old), raw, candidateTask = f.task(f.old)) }
                start.countDown()
                val owned = claim.get(10, TimeUnit.SECONDS)
                val result = old.get(10, TimeUnit.SECONDS)
                assertEquals(owned, result.optBoolean("retired"))
                assertEquals(!owned, result.optString("status") == "recorded")
                if (owned) {
                    f.f.execute(f.next)
                    assertEquals(1, f.f.workspace.publicationRevisions(f.access(f.next), f.next.memberId).size)
                }
            } finally { pool.shutdownNow(); assertTrue(pool.awaitTermination(10, TimeUnit.SECONDS)) }
        }
    }

    @Test fun retiredRepairSessionCannotLoopOrResumeProviderWork() {
        val f = Fixture()
        val repair = CollaborationPublicationRecovery(f.f.workspace, f.access(f.old))
        f.claim()
        assertThrows(IllegalArgumentException::class.java) { repair.permitsTool(CollaborationCloudRecall.NAME) }
        assertThrows(IllegalStateException::class.java) { repair.accept(f.f.draft(f.old)) }
        assertThrows(IllegalArgumentException::class.java) { CollaborationPublicationRecovery(f.reopen(), f.access(f.old)) }
        assertThrows(IllegalArgumentException::class.java) { f.reopen().replayCandidateTask(f.access(f.old), f.task(f.old)) }
        assertThrows(IllegalArgumentException::class.java) {
            f.reopen().enrollPublication(f.access(f.old), CollaborationResearchStage.VERIFY, f.task(f.old))
        }
    }

    @Test fun anotherSuccessorCannotStealAnAlreadyCommittedHandoff() {
        val f = Fixture()
        f.claim()
        val before = f.rows.data.toMap()
        assertThrows(IllegalArgumentException::class.java) {
            f.f.workspace.enrollPublication(f.access(f.next).copy(nodeId = "competing-successor"), CollaborationResearchStage.VERIFY, f.task(f.next))
        }
        assertEquals(before, f.rows.data)
        f.f.execute(f.next)
    }

    @Test fun replacementNeedsItsExactContractAndCannotBypassEnrollment() {
        val f = Fixture()
        assertEquals("rejected", f.f.workspace.publish(f.access(f.next), f.f.draft(f.next), candidateTask = f.task(f.next)).getString("status"))
        assertTrue(f.f.workspace.publicationRevisions(f.access(f.next), f.next.memberId).isEmpty())
        f.claim()
        val changed = f.task(f.next).put("member", "other")
        assertEquals("rejected", f.f.workspace.submitPublication(f.access(f.next), "not an artifact").getString("status"))
        assertThrows(IllegalArgumentException::class.java) {
            f.f.workspace.enrollPublication(f.access(f.next).copy(personId = "other"), CollaborationResearchStage.VERIFY, changed)
        }
        assertEquals("recorded", f.f.workspace.submitPublication(f.access(f.next), f.f.draft(f.next)).getString("status"))
    }

    @Test fun claimRejectsCrossTurnContractChangesAndRevokedAccess() {
        val f = Fixture()
        val before = f.rows.data.toMap()
        listOf<(JSONObject) -> Unit>(
            { it.put("turn_id", "another-turn") },
            { it.getJSONObject("criterion").put("id", "changed") },
            { it.getJSONObject("review_reassignment").put("node_id", f.next.memberId) },
            { it.put("operation", "revise") }
        ).forEach { change ->
            assertThrows(Exception::class.java) {
                f.f.workspace.enrollPublication(f.access(f.next), CollaborationResearchStage.VERIFY, f.task(f.next).also(change))
            }
            assertEquals(before, f.rows.data)
        }
        val revoked = CollaborationResearchWorkspace(f.rows, accessAuthorized = { false })
        assertThrows(IllegalArgumentException::class.java) { f.claim(revoked) }
        assertEquals(before, f.rows.data)
    }

    @Test fun corruptRetirementOrMissingContractFailsClosed() {
        listOf("retirement", "contract").forEach { kind ->
            val f = Fixture(); f.claim()
            if (kind == "retirement") {
                val key = f.rows.data.keys.single { ":retirement:" in it }
                f.rows.data[key] = f.rows.data.getValue(key).replace("Publish a review", "Tampered review")
            } else {
                val key = f.rows.data.keys.single { it.endsWith(":contract") && it.contains(AgentNativeJsonCodec.sha256("${f.f.access.runId}:${f.next.memberId}")) }
                f.rows.data.remove(key)
            }
            val before = f.rows.data.toMap()
            assertTrue(runCatching { f.reopen().publish(f.access(f.old), "late response") }.isFailure)
            assertEquals(before, f.rows.data)
        }
    }

    @Test fun handoffCanContinueAsAChainWithoutRevivingRetiredWriters() {
        val f = Fixture(); f.claim()
        val third = f.access(f.next).copy(nodeId = "third-review")
        val thirdTask = f.task(f.next).put("review_reassignment", JSONObject().put("node_id", f.next.memberId).put("reason", "Correct another unpublished review"))
        f.f.workspace.enrollPublication(third, CollaborationResearchStage.VERIFY, thirdTask)
        assertTrue(f.reopen().publish(f.access(f.old), f.f.draft(f.old)).getBoolean("retired"))
        assertTrue(f.reopen().publish(f.access(f.next), f.f.draft(f.next)).getBoolean("retired"))
        f.reopen().requirePublicationActive(third)
        assertNotNull(f.reopen().publicationContract(third))
    }
}
