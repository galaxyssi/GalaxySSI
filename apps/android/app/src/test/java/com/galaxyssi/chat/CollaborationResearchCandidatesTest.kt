package com.galaxyssi.chat

import java.util.concurrent.Callable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationResearchCandidatesTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        var rejectWrite = false
        override fun read(key: String) = data[key]
        override fun commit(values: Map<String, String>) {
            check(!rejectWrite) { "Storage unavailable" }
            data.putAll(values)
        }
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
    }

    private class Fixture {
        val rows = Rows()
        var allowed = true
        val ledger = CollaborationEvidenceLedger(Rows(), { allowed })
        val workspace = CollaborationResearchWorkspace(rows, { allowed }, ledger::references)
        val reader = access("reader", round = 20)
        val observation = ledger.record(access("tool", round = 0), "experiment-1", "test", "{}", "{\"value\":17}", 1, 2)
        fun publish(who: CollaborationWorkspaceAccess, vararg items: JSONObject) = workspace.publish(who, raw(*items), 100)
        fun create(id: String = "a", who: CollaborationWorkspaceAccess = access("author")): JSONObject =
            ref(publish(who, candidate(id)))
        fun saved(ref: JSONObject) = requireNotNull(workspace.read(reader, ref.getString("object_id"), ref.getInt("revision")))
        fun evolution(target: JSONObject, operation: String = "revise", content: String = "Improved") =
            candidate("ignored", operation, content).put("object_id", target.getString("object_id"))
                .put("base_revision", target.getInt("revision")).put("parents", JSONArray().put(target))
                .put("observations", JSONArray().put(observation))
        fun event(id: String, operation: String, vararg targets: JSONObject): JSONObject = JSONObject()
            .put("id", id).put("kind", "candidate_event").put("title", "Evidence-backed $operation")
            .put("observations", JSONArray().put(observation)).put("body", JSONObject().put("candidate_event", JSONObject()
                .put("operation", operation).put("targets", JSONArray(targets.toList())).put("criterion", "Accuracy")
                .put("check", "Compare the saved output to the prediction").put("rationale", "The original output distinguishes the alternatives")
                .put("outcome", when (operation) { "compare" -> "inconclusive"; "challenge" -> "refuted"; else -> "supported" })
                .put("correction", "Change the assumption and repeat the discriminating check").put("unresolved", JSONArray())))
    }

    @Test fun independentCandidatesWithSameLocalIdStayDistinctAndHidden() {
        val f = Fixture()
        val a = f.create(who = access("alice"))
        val b = f.create(who = access("bob"))
        assertNotEquals(a.getString("object_id"), b.getString("object_id"))
        assertNull(f.workspace.read(access("bob"), a.getString("object_id"), 1))
        assertEquals(1, f.workspace.browse(access("bob")).revisions.size)
        assertEquals(2, f.workspace.browse(f.reader).revisions.size)
        assertEquals("requires_independent_review", a.getJSONObject("host_candidate").getString("verification_state"))
    }

    @Test fun compareChallengeReviseCombineRetireRemainInWorkspaceRecallHistory() {
        val f = Fixture()
        val a = f.create(who = access("alice"))
        val b = f.create(who = access("bob"))
        val comparison = ref(f.publish(access("comparer", round = 2), f.event("comparison", "compare", a, b)))
        val challenge = ref(f.publish(access("critic", round = 2), f.event("challenge", "challenge", a)))
        val revised = ref(f.publish(access("editor", round = 3), f.evolution(a).put("resolves", JSONArray().put(challenge))))
        val combination = candidate("combined", "combine").put("parents", JSONArray().put(revised).put(b))
            .put("observations", JSONArray().put(f.observation))
        val combined = ref(f.publish(access("combiner", round = 4), combination))
        val retired = ref(f.publish(access("retirer", round = 5), f.evolution(b, "retire", "Original")))
        assertEquals("retired", retired.getJSONObject("host_candidate").getString("status"))
        assertEquals(a.getString("sha256"), f.saved(revised).getString("previous_sha256"))
        assertEquals(challenge.getString("sha256"), f.saved(revised).getJSONArray("resolves").getJSONObject(0).getString("sha256"))
        assertEquals(2, f.saved(combined).getJSONArray("parents").length())
        assertEquals("Original", f.saved(b).getJSONObject("body").getString("content"))
        assertEquals("member_reported_not_verified", f.saved(comparison).getString("evidence_state"))
        assertEquals(5, f.workspace.browse(f.reader).revisions.size)
    }

    @Test fun newRevisionInvalidatesExactReviewWithoutDestroyingIt() {
        val f = Fixture()
        val a = f.create()
        val review = ref(f.publish(access("reviewer", round = 2), f.event("review", "review", a)))
        assertTrue(f.workspace.candidateReviewApplies(f.reader, review))
        val originalReview = f.saved(review).toString()
        val second = ref(f.publish(access("editor", round = 3), f.evolution(a)))
        assertFalse(f.workspace.candidateReviewApplies(f.reader, review))
        assertEquals(originalReview, f.saved(review).toString())
        assertEquals("requires_independent_review", second.getJSONObject("host_candidate").getString("verification_state"))
        val directory = f.workspace.browse(f.reader).revisions.single { it.getString("object_id") == review.getString("object_id") }
        assertEquals("stale_or_isolated", directory.getString("review_applicability"))
        val fresh = ref(f.publish(access("reviewer-2", round = 4), f.event("review-2", "review", second)))
        assertTrue(f.workspace.candidateReviewApplies(f.reader, fresh))
    }

    @Test fun comparisonAndCombinationRetainMoreThanEightExactOriginals() {
        val f = Fixture()
        val originals = (0 until 12).map { f.create("route-$it", access("author-$it")) }
        val comparison = ref(f.publish(access("comparer", round = 2), f.event("compare-many", "compare", *originals.toTypedArray())))
        assertEquals(12, f.saved(comparison).getJSONArray("parents").length())
        val combined = ref(f.publish(access("combiner", round = 3), candidate("combined", "combine")
            .put("parents", JSONArray(originals)).put("observations", JSONArray().put(f.observation))))
        assertEquals(12, f.saved(combined).getJSONArray("parents").length())
        originals.forEach { assertEquals("Original", f.saved(it).getJSONObject("body").getString("content")) }
    }

    @Test fun retirementIsTerminalAndInvalidatesReviewButRetainsOriginal() {
        val f = Fixture()
        val a = f.create()
        val review = ref(f.publish(access("reviewer", round = 2), f.event("review", "review", a)))
        val retired = ref(f.publish(access("retirer", round = 3), f.evolution(a, "retire", "Original")))
        assertEquals("ineligible_retired", retired.getJSONObject("host_candidate").getString("verification_state"))
        assertFalse(f.workspace.candidateReviewApplies(f.reader, review))
        rejected(f.publish(access("resurrect", round = 4), f.evolution(retired)))
        rejected(f.publish(access("late-review", round = 4), f.event("late", "review", retired)))
        assertEquals("Original", f.saved(a).getJSONObject("body").getString("content"))
    }

    @Test fun priorAndAncestorContributorsCannotReviewCombination() {
        val f = Fixture()
        val a = f.create(who = access("alice"))
        val b = f.create(who = access("bob"))
        val revised = ref(f.publish(access("editor", round = 2), f.evolution(a)))
        val combined = ref(f.publish(access("combiner", round = 3), candidate("combined", "combine")
            .put("parents", JSONArray().put(revised).put(b)).put("observations", JSONArray().put(f.observation))))
        listOf("alice", "bob", "editor", "combiner").forEachIndexed { index, person ->
            rejected(f.publish(access("review-$index", person, 4), f.event("review-$index", "review", combined)))
        }
        assertTrue(f.workspace.candidateReviewApplies(f.reader,
            ref(f.publish(access("independent", round = 4), f.event("independent", "review", combined)))))
    }

    @Test fun hostIdentityAndVerificationMetadataCannotBeForged() {
        val f = Fixture()
        val item = candidate("a").put("host_candidate", JSONObject().put("status", "verified").put("contributors", JSONArray()))
            .put("person_id", "someone-else").put("evidence_state", "verified")
        val a = ref(f.publish(access("author"), item))
        assertEquals("author", f.saved(a).getString("person_id"))
        assertEquals("member_reported_not_verified", f.saved(a).getString("evidence_state"))
        rejected(f.publish(access("another-node", "author", 2), f.event("self", "review", a)))
    }

    @Test fun majorityComparisonsNeverVerifyCandidateOrChangeItsHead() {
        val f = Fixture()
        val a = f.create(who = access("alice"))
        val b = f.create(who = access("bob"))
        val original = f.saved(a).toString()
        repeat(9) { index ->
            val event = f.event("compare-$index", "compare", a, b)
            event.getJSONObject("body").getJSONObject("candidate_event").put("votes", 999).put("winner", a)
            ref(f.publish(access("comparer-$index", round = 2), event))
        }
        assertEquals(original, f.saved(a).toString())
        val forged = f.event("truth", "compare", a, b)
        forged.getJSONObject("body").getJSONObject("candidate_event").put("outcome", "majority_verified")
        rejected(f.publish(access("vote", round = 2), forged))
        assertTrue(f.workspace.isCurrent(f.reader, a.getString("object_id"), 1))
    }

    @Test fun fabricatedMissingAndCrossGroupEvidenceRejectEntirePublication() {
        val f = Fixture()
        val a = f.create()
        val foreign = f.ledger.record(access("foreign", round = 0).copy(groupId = "other"), "foreign", "test", "{}", "{}", 1, 2)
        val receipts = listOf(JSONObject(f.observation.toString()).put("sha256", "0".repeat(64)),
            JSONObject(f.observation.toString()).put("evidence_id", "0".repeat(64)), foreign)
        receipts.forEachIndexed { index, receipt ->
            rejected(f.publish(access("bad-$index", round = 2), candidate("unrelated-$index"),
                f.evolution(a).put("observations", JSONArray().put(receipt))))
        }
        assertEquals(1, f.workspace.browse(f.reader).revisions.size)
    }

    @Test fun failedEvidenceCanExplainFailureButCannotSupportIndependentReview() {
        val f = Fixture()
        val a = f.create()
        val failed = f.ledger.record(access("failed", round = 0), "failed", "test", "{}", "{\"status\":\"failed\"}", 1, 2)
        ref(f.publish(access("critic", round = 2), f.event("failure", "challenge", a).put("observations", JSONArray().put(failed))))
        rejected(f.publish(access("reviewer", round = 2), f.event("review", "review", a).put("observations", JSONArray().put(failed))))
        val audit = f.ledger.record(access("audit", round = 0), "audit", ResearchEvidenceAudit.TOOL, "{}", "{}", 1, 2)
        rejected(f.publish(access("audit-user", round = 2), f.event("audit", "challenge", a).put("observations", JSONArray().put(audit))))
    }

    @Test fun allEvolutionOperationsNeedEvidenceAndSubstantiveReasons() {
        val f = Fixture()
        val a = f.create()
        val b = f.create(who = access("bob"))
        val operations = listOf(f.evolution(a), f.evolution(a, "retire", "Original"),
            candidate("combined", "combine").put("parents", JSONArray().put(a).put(b)),
            f.event("compare", "compare", a, b), f.event("challenge", "challenge", a), f.event("review", "review", a))
        operations.forEachIndexed { index, item ->
            item.remove("observations")
            rejected(f.publish(access("no-evidence-$index", round = 2), item))
        }
        val noReason = f.evolution(a)
        noReason.getJSONObject("body").getJSONObject("candidate").put("rationale", " ")
        rejected(f.publish(access("no-reason", round = 2), noReason))
    }

    @Test fun malformedVersionOrHashCannotChooseAnotherParent() {
        val f = Fixture()
        val a = f.create()
        listOf<Any>(1.5, "1", 0, -1, 4294967297L).forEachIndexed { index, version ->
            val target = JSONObject(a.toString()).put("revision", version)
            rejected(f.publish(access("bad-version-$index", round = 2), f.event("event-$index", "review", target)))
        }
        val wrongHash = JSONObject(a.toString()).put("sha256", "0".repeat(64))
        rejected(f.publish(access("bad-hash", round = 2), f.evolution(a).put("parents", JSONArray().put(wrongHash))))
        val noHash = JSONObject(a.toString()).apply { remove("sha256") }
        rejected(f.publish(access("no-hash", round = 2), f.evolution(a).put("parents", JSONArray().put(noHash))))
        rejected(f.publish(access("fraction-base", round = 2), f.evolution(a).put("base_revision", 1.5)))
    }

    @Test fun isolatedAndStaleTargetsCannotBeComparedChallengedOrReviewed() {
        val f = Fixture()
        val a = f.create()
        val b = f.create(who = access("bob"))
        listOf("compare", "challenge", "review").forEach { op ->
            val targets = if (op == "compare") arrayOf(a, b) else arrayOf(a)
            rejected(f.publish(access("isolated-$op"), f.event("isolated-$op", op, *targets)))
        }
        ref(f.publish(access("editor", round = 2), f.evolution(a)))
        listOf("compare", "challenge", "review").forEach { op ->
            val targets = if (op == "compare") arrayOf(a, b) else arrayOf(a)
            rejected(f.publish(access("stale-$op", round = 3), f.event("stale-$op", op, *targets)))
        }
    }

    @Test fun dependencyVisibilityAllowsReviewWithoutOpeningIndependentWork() {
        val f = Fixture()
        val a = f.create()
        val reviewer = access("reviewer").copy(dependencyNodes = setOf("author"))
        val review = ref(f.publish(reviewer, f.event("review", "review", a)))
        assertTrue(f.workspace.candidateReviewApplies(reviewer, review))
        assertNull(f.workspace.read(access("independent"), review.getString("object_id"), 1))
    }

    @Test fun samePublicationTargetMutationRejectsAtomicallyInEitherOrder() {
        repeat(2) { order ->
            val f = Fixture()
            val a = f.create()
            val review = f.event("review", "review", a)
            val update = f.evolution(a)
            val items = if (order == 0) arrayOf(update, review) else arrayOf(review, update)
            rejected(f.publish(access("editor", round = 2), *items))
            assertTrue(f.workspace.isCurrent(f.reader, a.getString("object_id"), 1))
            assertEquals(1, f.workspace.browse(f.reader).revisions.size)
        }
    }

    @Test fun exactReplayAfterReopenDoesNotDuplicateHistoryAndChangedReplayFails() {
        val f = Fixture()
        val a = f.create()
        val who = access("reviewer", round = 2)
        val input = raw(f.event("review", "review", a))
        val result = f.workspace.publish(who, input, 123)
        val snapshot = f.rows.data.toMap()
        val reopened = CollaborationResearchWorkspace(f.rows, evidence = f.ledger::references)
        assertEquals(result.toString(), reopened.publish(who, input, 999).toString())
        assertEquals(snapshot, f.rows.data)
        rejected(reopened.publish(who, raw(f.event("changed", "review", a))))
        assertEquals(snapshot, f.rows.data)
    }

    @Test fun failedAtomicCommitLeavesNoCandidateOrEventAndCanRetry() {
        val f = Fixture()
        val a = f.create()
        val before = f.rows.data.toMap()
        val who = access("reviewer", round = 2)
        val input = raw(candidate("parallel"), f.event("review", "review", a))
        f.rows.rejectWrite = true
        assertTrue(runCatching { f.workspace.publish(who, input) }.isFailure)
        assertEquals(before, f.rows.data)
        f.rows.rejectWrite = false
        assertEquals("recorded", f.workspace.publish(who, input).getString("status"))
        assertEquals(3, f.workspace.browse(f.reader).revisions.size)
    }

    @Test fun concurrentRevisionsHaveExactlyOneWinnerAndPreserveOriginal() {
        val f = Fixture()
        val a = f.create()
        val ready = CountDownLatch(2)
        val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(2)
        try {
            val futures = (1..2).map { index -> executor.submit(Callable {
                ready.countDown()
                check(start.await(5, TimeUnit.SECONDS))
                f.publish(access("editor-$index", round = 2), f.evolution(a, content = "Revision $index")).getString("status")
            }) }
            assertTrue(ready.await(5, TimeUnit.SECONDS))
            start.countDown()
            assertEquals(listOf("recorded", "rejected"), futures.map { it.get(10, TimeUnit.SECONDS) }.sorted())
            assertEquals("Original", f.saved(a).getJSONObject("body").getString("content"))
            assertEquals(2, f.workspace.browse(f.reader).revisions.single().getInt("revision"))
        } finally { start.countDown(); executor.shutdownNow() }
    }

    @Test fun criteriaCannotBeWeakenedAndRetirementCannotRewriteContent() {
        val f = Fixture()
        val a = f.create()
        val weak = f.evolution(a)
        weak.getJSONObject("body").getJSONObject("candidate").put("criteria", JSONArray().put("Easier"))
        rejected(f.publish(access("weak", round = 2), weak))
        rejected(f.publish(access("rewrite", round = 2), f.evolution(a, "retire", "Different content")))
        val review = f.event("unsupported", "review", a)
        review.getJSONObject("body").getJSONObject("candidate_event").put("unresolved", JSONArray().put("Unmet requirement"))
        rejected(f.publish(access("reviewer", round = 2), review))
    }

    @Test fun duplicateCombinationAndUnrelatedResolvedChallengeAreRejected() {
        val f = Fixture()
        val a = f.create()
        val b = f.create(who = access("bob"))
        rejected(f.publish(access("combiner", round = 2), candidate("combined", "combine")
            .put("parents", JSONArray().put(a).put(a)).put("observations", JSONArray().put(f.observation))))
        val challenge = ref(f.publish(access("critic", round = 2), f.event("challenge", "challenge", b)))
        rejected(f.publish(access("editor", round = 3), f.evolution(a).put("resolves", JSONArray().put(challenge))))
    }

    @Test fun eventsCannotBeRewrittenAndRejectionsReplayWithoutNewRows() {
        val f = Fixture()
        val a = f.create()
        val event = ref(f.publish(access("critic", round = 2), f.event("challenge", "challenge", a)))
        val who = access("reviser", round = 3)
        val input = raw(f.event("ignored", "review", a).put("object_id", event.getString("object_id")).put("base_revision", 1))
        val result = f.workspace.publish(who, input)
        rejected(result)
        val before = f.rows.data.toMap()
        assertEquals(result.toString(), f.workspace.publish(who, input).toString())
        assertEquals(before, f.rows.data)
        assertEquals("challenge", f.saved(event).getJSONObject("host_candidate_event").getString("operation"))
    }

    @Test fun revocationAndCrossGroupReadsCannotExposeCandidatesOrReviews() {
        val f = Fixture()
        val a = f.create()
        val review = ref(f.publish(access("reviewer", round = 2), f.event("review", "review", a)))
        assertFalse(f.workspace.candidateReviewApplies(f.reader.copy(groupId = "other"), review))
        f.allowed = false
        assertFalse(f.workspace.candidateReviewApplies(f.reader, review))
        assertTrue(f.workspace.browse(f.reader).revisions.isEmpty())
        val before = f.rows.data.toMap()
        rejected(f.publish(access("late", round = 3), candidate("late")))
        assertEquals(before, f.rows.data)
    }

    @Test fun hiddenRevisionKeepsVisiblePredecessorButDoesNotMakeReviewApplicable() {
        val f = Fixture()
        val a = f.create(who = access("author", round = 0))
        val review = ref(f.publish(access("reviewer", round = 1), f.event("review", "review", a)))
        ref(f.publish(access("editor", round = 2), f.evolution(a)))
        val peer = access("peer", round = 2)
        val visible = f.workspace.browse(peer).revisions.single { it.getString("object_id") == a.getString("object_id") }
        assertEquals(1, visible.getInt("revision"))
        assertFalse(f.workspace.candidateReviewApplies(peer, review))
    }

    @Test fun tamperedRevisionAndHeadFailClosed() {
        val f = Fixture()
        val a = f.create()
        val headKey = f.rows.data.keys.single { it.contains(":head:") }
        val head = JSONObject(f.rows.data.getValue(headKey)).put("title", "Corrupted head")
        f.rows.data[headKey] = head.toString()
        rejected(f.publish(access("editor", round = 2), f.evolution(a)))
        val revisionKey = f.rows.data.keys.single { it.contains(":revision:") }
        f.rows.data[revisionKey] = JSONObject(f.rows.data.getValue(revisionKey)).put("title", "Tampered").toString()
        assertTrue(runCatching { f.saved(a) }.isFailure)
        assertTrue(runCatching { f.workspace.browse(f.reader) }.isFailure)
    }

    @Test fun fullOriginalAndPagedCandidateEventsSurviveReopen() {
        val f = Fixture()
        val content = "Full original evidence. ".repeat(1000)
        val a = ref(f.publish(access("author"), candidate("a", content = content)))
        repeat(24) { index -> ref(f.publish(access("critic-$index", round = 2), f.event("challenge-$index", "challenge", a))) }
        val reopened = CollaborationResearchWorkspace(f.rows, evidence = f.ledger::references)
        assertEquals(content, reopened.read(f.reader, a.getString("object_id"), 1)!!.getJSONObject("body").getString("content"))
        val ids = mutableSetOf<String>()
        var cursor = ""
        do {
            val page = reopened.browse(f.reader, cursor, 4)
            page.revisions.forEach { assertTrue(ids.add(it.getString("object_id"))) }
            cursor = page.next.orEmpty()
        } while (cursor.isNotEmpty())
        assertEquals(25, ids.size)
    }

    @Test fun malformedLinkArraysAreNotSilentlyDropped() {
        val f = Fixture()
        listOf("parents", "resolves", "observations").forEachIndexed { index, key ->
            rejected(f.publish(access("malformed-$index"), candidate("a").put(key, "not-an-array")))
        }
        assertTrue(f.workspace.browse(f.reader).revisions.isEmpty())
    }

    @Test fun legacyParentWithoutHashGetsExactHostDigestAndForgedHashIsRejected() {
        val f = Fixture()
        val a = f.create()
        fun artifact(id: String, parent: JSONObject) = JSONObject().put("id", id).put("kind", "artifact")
            .put("title", "Existing protocol delivery").put("body", JSONObject().put("content", "A reported document"))
            .put("parents", JSONArray().put(parent))
        val legacy = JSONObject().put("object_id", a.getString("object_id")).put("revision", 1)
        val delivery = ref(f.publish(access("delivery", round = 2), artifact("delivery", legacy)))
        assertEquals(a.getString("sha256"), f.saved(delivery).getJSONArray("parents").getJSONObject(0).getString("sha256"))
        rejected(f.publish(access("forged", round = 2), artifact("forged", legacy.put("sha256", "0".repeat(64)))))
        assertFalse(f.saved(delivery).has("host_candidate"))
    }

    @Test fun negativeReviewApplicabilityIsNotACompletionVerdict() {
        val f = Fixture()
        val a = f.create()
        val negative = f.event("negative", "review", a)
        negative.getJSONObject("body").getJSONObject("candidate_event").put("outcome", "refuted")
            .put("unresolved", JSONArray().put("Prediction does not match output"))
        val review = ref(f.publish(access("reviewer", round = 2), negative))
        assertTrue(f.workspace.candidateReviewApplies(f.reader, review))
        assertEquals("refuted", f.saved(review).getJSONObject("body").getJSONObject("candidate_event").getString("outcome"))
        assertEquals("member_reported_not_verified", f.saved(a).getString("evidence_state"))
        assertFalse(f.workspace.candidateReviewApplies(f.reader, JSONObject(review.toString()).put("sha256", "0".repeat(64))))
    }

    @Test fun eventsRejectDuplicateTargetsAndParentsThatHideOtherInputs() {
        val f = Fixture()
        val a = f.create()
        val b = f.create(who = access("bob"))
        rejected(f.publish(access("duplicate", round = 2), f.event("duplicate", "compare", a, a)))
        rejected(f.publish(access("unrelated", round = 2), f.event("unrelated", "review", a).put("parents", JSONArray().put(b))))
        val event = ref(f.publish(access("exact", round = 2), f.event("exact", "review", a).put("parents", JSONArray().put(a))))
        assertEquals(a.getString("sha256"), f.saved(event).getJSONArray("parents").getJSONObject(0).getString("sha256"))
    }

    @Test fun simultaneousCombinationAndParentRevisionCannotPublishStaleLineage() {
        val f = Fixture()
        val a = f.create()
        val b = f.create(who = access("bob"))
        val combination = candidate("combined", "combine").put("parents", JSONArray().put(a).put(b))
            .put("observations", JSONArray().put(f.observation))
        rejected(f.publish(access("editor", round = 2), combination, f.evolution(a)))
        assertEquals(2, f.workspace.browse(f.reader).revisions.size)
        assertTrue(f.workspace.isCurrent(f.reader, a.getString("object_id"), 1))
    }

    @Test fun combinationMustInheritAllParentCriteria() {
        val f = Fixture()
        val a = f.create()
        val second = candidate("b")
        second.getJSONObject("body").getJSONObject("candidate").getJSONArray("criteria").put("Cost")
        val b = ref(f.publish(access("bob"), second))
        val combination = candidate("combined", "combine").put("parents", JSONArray().put(a).put(b))
            .put("observations", JSONArray().put(f.observation))
        rejected(f.publish(access("weak-combine", round = 2), combination))
        combination.getJSONObject("body").getJSONObject("candidate").getJSONArray("criteria").put("Cost")
        ref(f.publish(access("complete-combine", round = 2), combination))
    }

    @Test fun corruptReviewHeadCannotRemainApplicable() {
        val f = Fixture()
        val a = f.create()
        val review = ref(f.publish(access("reviewer", round = 2), f.event("review", "review", a)))
        assertTrue(f.workspace.candidateReviewApplies(f.reader, review))
        val headKey = f.rows.data.keys.single { it.endsWith(":head:${review.getString("object_id")}") }
        f.rows.data[headKey] = JSONObject(f.rows.data.getValue(headKey)).put("title", "Corrupted review head").toString()
        assertFalse(f.workspace.candidateReviewApplies(f.reader, review))
    }

    companion object {
        private fun access(node: String, person: String = node, round: Long = 1) =
            CollaborationWorkspaceAccess("group", "run", "turn", round, node, person)
        private fun candidate(id: String, operation: String = "propose", content: String = "Original") = JSONObject()
            .put("id", id).put("kind", "candidate").put("title", "Candidate $id")
            .put("body", JSONObject().put("content", content).put("candidate", JSONObject().put("operation", operation)
                .put("rationale", "Specific evidence-backed reasoning").put("criteria", JSONArray().put("Accuracy"))))
        private fun raw(vararg items: JSONObject) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
            .put("summary", "Substantive research").put("candidates", JSONArray()).put("findings", JSONArray())
            .put("workspace", JSONArray(items.toList())).toString()
        private fun ref(result: JSONObject): JSONObject {
            assertEquals(result.toString(), "recorded", result.getString("status"))
            return result.getJSONArray("revisions").getJSONObject(0)
        }
        private fun rejected(result: JSONObject) = assertEquals(result.toString(), "rejected", result.getString("status"))
    }
}
