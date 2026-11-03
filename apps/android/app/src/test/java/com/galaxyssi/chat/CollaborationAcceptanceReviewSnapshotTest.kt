package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.TreeMap
import java.util.TreeSet
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class CollaborationAcceptanceReviewSnapshotTest {
    private class Rows(seed: Map<String, String>) : CollaborationWorkspaceRows {
        val data = TreeMap(seed)
        val commits = mutableListOf<Map<String, String>>()
        var lastRemoval: Set<String> = emptySet()
        var emptyPages = 0
        var afterRead: ((String) -> Unit)? = null
        override fun read(key: String): String? = data[key].also { afterRead?.invoke(key) }
        override fun commit(values: Map<String, String>) {
            commits.add(values.toMap())
            data.putAll(values)
        }
        override fun mutate(values: Map<String, String>, removeKeys: Collection<String>) {
            lastRemoval = removeKeys.toSet()
            removeKeys.forEach { data.remove(it) }
            commit(values)
        }
        override fun page(prefix: String, after: String, limit: Int): List<String> =
            data.tailMap(maxOf(prefix, after), after < prefix).keys.asSequence()
                .takeWhile { it.startsWith(prefix) }.take(limit).toList().also { if (it.isEmpty()) emptyPages++ }
    }

    private class Harness {
        val f = CollaborationGoalAcceptanceTest.Fixture(reviewKind = CollaborationReviewContract.KIND)
        val rows = Rows(f.rows.data)
        var authorized = true
        val memberIds = mutableSetOf(f.access.personId)
        val accessAuthorized: (CollaborationWorkspaceAccess) -> Boolean = { scope ->
            scope.groupId == f.access.groupId && scope.personId.isNotBlank() && scope.personId in memberIds
        }
        val workspace = CollaborationResearchWorkspace(rows, { authorized }, f.ledger::references, accessAuthorized)
        val access = f.access.copy(round = 100)
        val report = f.assessment()
        var prior = f.prior
        var dispatch = 0
        val tokenKey get() = rows.data.keys.single { it.startsWith("mutation:") }
        fun saved(ref: JSONObject): JSONObject = requireNotNull(workspace.read(access, ref.getString("object_id"), ref.getInt("revision")))
        fun key(ref: JSONObject, head: Boolean = false): String = rows.data.keys.single {
            it.endsWith(if (head) "head:${ref.getString("object_id")}" else "revision:${ref.getString("object_id")}:${ref.getInt("revision")}")
        }
        fun raw(item: JSONObject) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Snapshot fixture")
            .put("candidates", JSONArray()).put("findings", JSONArray()).put("questions", JSONArray())
            .put("workspace", JSONArray().put(item)).toString()
        fun publish(item: JSONObject, person: String = "peer", who: CollaborationWorkspaceAccess = access.copy(round = 10)): JSONObject {
            val result = workspace.publish(who.copy(personId = person, nodeId = "snapshot-${++dispatch}"), raw(item), 20)
            assertEquals(result.toString(), "recorded", result.optString("status"))
            return result.getJSONArray("revisions").getJSONObject(0)
        }
        fun body(semantic: Boolean, verdict: String = "supported", target: JSONObject = if (semantic) f.mapping else f.delivery): JSONObject {
            val field = if (semantic) CollaborationSemanticGoalCoverage.REVIEW else CollaborationReviewContract.KIND
            val check = if (semantic) f.coverageReviewBody(target) else
                JSONObject(saved(f.review).getJSONObject("body").getJSONObject(field).toString()).put("target", target)
            check.put("verdict", verdict).put("unresolved", if (verdict == "supported") JSONArray() else JSONArray().put("Required work remains"))
            return JSONObject().put(field, check)
        }
        fun review(semantic: Boolean = false, verdict: String = "refuted", previous: JSONObject? = null,
                   who: CollaborationWorkspaceAccess = access.copy(round = 10), body: JSONObject = body(semantic, verdict)): JSONObject {
            val target = if (semantic) f.mapping else f.delivery
            return publish(f.item("dissent-${dispatch + 1}", CollaborationReviewContract.KIND, body)
                .put("parents", JSONArray().put(target)).apply {
                    if (previous != null) put("object_id", previous.getString("object_id")).put("base_revision", previous.getInt("revision"))
                }, who = who)
        }
        fun bindings() = buildSet {
            add(CollaborationAcceptanceReviewSnapshot.Binding.of(report.getJSONObject("goal_coverage").getJSONObject("mapping"),
                CollaborationSemanticGoalCoverage.REVIEW))
            val criteria = report.getJSONArray("criteria")
            repeat(criteria.length()) {
                val item = criteria.getJSONObject(it)
                add(CollaborationAcceptanceReviewSnapshot.Binding.of(item.getJSONObject("delivery"), CollaborationReviewContract.KIND,
                    item.getString("id"), item.getString("requirement")))
            }
        }
        fun snapshot() = workspace.acceptanceReviewSnapshot(access, bindings())
        fun evaluate(store: CollaborationWorkspaceRows = rows, who: CollaborationWorkspaceAccess = access) =
            CollaborationGoalAcceptance(if (store === rows) workspace else
                CollaborationResearchWorkspace(store, { authorized }, accessAuthorized = accessAuthorized), f.ledger)
                .evaluate(who, report.toString(), prior, f.goal, 30)

        fun multipleCriteria(count: Int) {
            val criteria = report.getJSONArray("criteria")
            val preserved = JSONArray(prior)
            for (index in 2..count) {
                val id = "criterion-$index"
                val criterion = JSONObject(f.criterion.toString()).put("id", id)
                preserved.put(criterion)
                val reviewBody = body(false)
                reviewBody.getJSONObject(CollaborationReviewContract.KIND).put("criterion_id", id)
                val review = publish(f.item("review-$index", CollaborationReviewContract.KIND, reviewBody)
                    .put("parents", JSONArray().put(f.delivery)), person = "reviewer-$index")
                criteria.put(JSONObject(criterion.toString()).put("status", "met").put("delivery", f.delivery).put("review", review)
                    .put("evidence", JSONArray().put("workspace:" + f.delivery.getString("object_id"))))
            }
            prior = preserved.toString()
            val ids = JSONArray((0 until criteria.length()).map { criteria.getJSONObject(it).getString("id") })
            val mappingBody = f.mappingBody().put("criteria_sha256", CollaborationSemanticGoalCoverage.criteriaHash(preserved))
            val segments = mappingBody.getJSONArray("segments")
            repeat(segments.length()) { segments.getJSONObject(it).put("criterion_ids", ids) }
            val mapping = publish(f.item("mapping-revision", "artifact", JSONObject().put(CollaborationSemanticGoalCoverage.MAPPING, mappingBody))
                .put("object_id", f.mapping.getString("object_id")).put("base_revision", 1), person = "mapper")
            val check = f.coverageReviewBody(mapping)
            val reviewed = check.getJSONArray("segments")
            repeat(reviewed.length()) { reviewed.getJSONObject(it).put("criterion_ids", ids) }
            val review = publish(f.item("multicriterion-coverage", CollaborationReviewContract.KIND,
                JSONObject().put(CollaborationSemanticGoalCoverage.REVIEW, check)).put("parents", JSONArray().put(mapping)),
                person = "coverage-reviewer", who = access.copy(round = 11))
            report.getJSONObject("goal_coverage").put("mapping", mapping).put("review", review)
        }
    }

    /** Ordered key fixture: O(log M + page size), with payload generation only for requested rows. */
    private class PagedRows(private val h: Harness, val count: Int, private val pageSize: Int = 100) : CollaborationWorkspaceRows by h.rows {
        private val prefix = h.key(h.f.delivery, true).substringBefore("head:")
        private val template = h.saved(h.f.delivery).toString()
        private val directory = TreeSet<String>().apply {
            addAll(h.rows.data.keys.filter { it.startsWith(prefix + "head:") })
            repeat(count) { add(prefix + "head:" + (it + 1).toString(16).padStart(64, '0')) }
        }
        var pages = 0
        var ends = 0
        var syntheticReads = 0
        var maximumLimit = 0
        var lastId = ""
        var lastValue = ""
        override fun page(prefix: String, after: String, limit: Int): List<String> {
            require(prefix == this.prefix + "head:")
            pages++
            maximumLimit = maxOf(maximumLimit, limit)
            return directory.tailSet(after, false).asSequence().take(minOf(pageSize, limit)).toList().also { if (it.isEmpty()) ends++ }
        }
        override fun read(key: String): String? {
            h.rows.read(key)?.let { return it }
            val id = when {
                key.startsWith(prefix + "head:") -> key.removePrefix(prefix + "head:")
                key.startsWith(prefix + "revision:") && key.endsWith(":1") -> key.removePrefix(prefix + "revision:").removeSuffix(":1")
                else -> return null
            }
            val index = id.toIntOrNull(16) ?: return null
            if (index !in 1..count || id != index.toString(16).padStart(64, '0')) return null
            syntheticReads++
            if (lastId != id) {
                val saved = JSONObject(template).put("object_id", id)
                saved.remove("sha256")
                saved.put("sha256", AgentNativeJsonCodec.sha256(saved.toString()))
                lastId = id
                lastValue = saved.toString()
            }
            return lastValue
        }
    }

    @Test fun manyCriteriaAndCoverageShareOneUnboundedPagedScan() {
        listOf(1, 8).forEach { count ->
            val h = Harness()
            h.multipleCriteria(count)
            val rows = PagedRows(h, 4101, pageSize = 7)
            val receipt = h.evaluate(rows)
            assertTrue(receipt.feedback, receipt.accepted)
            assertEquals(1, rows.ends)
            assertEquals(2 * rows.count, rows.syntheticReads)
            assertEquals(100, rows.maximumLimit)
            assertTrue(rows.pages > 580)
            val again = h.evaluate(rows)
            assertTrue(again.feedback, again.accepted)
            assertEquals(2, rows.ends)
            assertEquals(4 * rows.count, rows.syntheticReads)
        }
    }

    @Test fun lateDissentOnOneOfManyBindingsIsNotSkipped() {
        val h = Harness()
        h.multipleCriteria(8)
        val body = h.body(false, "refuted")
        body.getJSONObject(CollaborationReviewContract.KIND).put("criterion_id", "criterion-8")
        h.review(body = body)
        val rows = PagedRows(h, 4101)
        val receipt = h.evaluate(rows)
        assertFalse(receipt.accepted)
        assertTrue(receipt.feedback, receipt.feedback.startsWith("criterion-8: a current typed review"))
        assertEquals(1, rows.ends)
        assertEquals(2 * rows.count, rows.syntheticReads)
    }

    @Test fun headsAndTokenCommitTogetherButReplayAndRejectionDoNotInvalidate() {
        val h = Harness()
        val item = h.f.item("atomic", "artifact", JSONObject().put("content", "New work"))
        val access = h.access.copy(nodeId = "atomic", personId = "author")
        val raw = h.raw(item)
        val old = h.rows.data[h.tokenKey]
        assertEquals("recorded", h.workspace.publish(access, raw).getString("status"))
        val write = h.rows.commits.last()
        assertTrue(write.keys.any { it.contains(":head:") })
        assertTrue(write.containsKey(h.tokenKey))
        assertNotEquals(old, h.rows.data[h.tokenKey])
        val snapshot = h.snapshot()
        val commits = h.rows.commits.size
        assertEquals("recorded", h.workspace.publish(access, raw).getString("status"))
        assertEquals(commits, h.rows.commits.size)
        assertEquals("rejected", h.workspace.publish(access, h.raw(item.put("title", "Changed"))).getString("status"))
        assertTrue(h.workspace.withAcceptanceFence(snapshot) { true })
    }

    @Test fun mutationAfterTheScanCannotIssueSuccessfulReceipt() {
        listOf(false, true).forEach { semantic ->
            val h = Harness()
            var inserted = false
            val observedKey = h.key(h.f.delivery)
            h.rows.afterRead = { key ->
                if (h.rows.emptyPages > 0 && key == observedKey) {
                    h.rows.afterRead = null
                    h.review(semantic)
                    inserted = true
                }
            }
            val receipt = h.evaluate()
            assertTrue(inserted)
            assertFalse(receipt.accepted)
            assertTrue(receipt.feedback, receipt.feedback.contains("Workspace changed during acceptance"))
            assertFalse(h.evaluate().accepted)
        }
    }

    @Test fun anotherWorkspaceInstanceAndNewRevisionInvalidateTheSamePersistedFence() {
        val h = Harness()
        val review = h.review(verdict = "supported")
        val snapshot = h.snapshot()
        val other = CollaborationResearchWorkspace(h.rows)
        val item = h.f.item("revised-review", CollaborationReviewContract.KIND, h.body(false, "refuted"))
            .put("object_id", review.getString("object_id")).put("base_revision", 1).put("parents", JSONArray().put(h.f.delivery))
        val result = other.publish(h.access.copy(round = 11, nodeId = "other-instance", personId = "peer"), h.raw(item))
        assertEquals("recorded", result.getString("status"))
        assertThrows(IllegalArgumentException::class.java) { h.workspace.withAcceptanceFence(snapshot) { error("Stale receipt") } }
        val rejected = h.evaluate()
        assertFalse(rejected.accepted)
        assertTrue(rejected.feedback, rejected.feedback.contains("current typed review retains dissent"))
    }

    @Test fun dependencySetIsFrozenForTheEntireSnapshot() {
        val h = Harness()
        val hidden = h.review(who = h.access)
        val node = h.workspace.read(h.access.copy(round = 101), hidden.getString("object_id"), 1)!!.getString("node_id")
        val dependencies = mutableSetOf<String>()
        val snapshot = h.workspace.acceptanceReviewSnapshot(h.access.copy(dependencyNodes = dependencies), h.bindings())
        dependencies.add(node)
        assertTrue(snapshot.access.dependencyNodes.isEmpty())
        val binding = CollaborationAcceptanceReviewSnapshot.Binding.of(h.f.delivery, CollaborationReviewContract.KIND,
            "document", h.f.criterion.getString("requirement"))
        assertEquals(1, snapshot.reviews(binding).size)
        assertTrue(h.workspace.withAcceptanceFence(snapshot) { true })
        assertFalse(h.evaluate(who = h.access.copy(dependencyNodes = dependencies)).accepted)
    }

    @Test fun concurrentWriterBetweenPagesInvalidatesAndFilteringDoesNotHoldTheLock() {
        val h = Harness()
        var attempted = false
        val error = assertThrows(IllegalArgumentException::class.java) {
            h.workspace.currentAcceptanceReviews(h.access, h.f.delivery) {
                if (!attempted) {
                    attempted = true
                    val failure = AtomicReference<Throwable?>()
                    val worker = Thread { runCatching {
                        h.publish(h.f.item("concurrent", "artifact", JSONObject().put("content", "Concurrent work")))
                    }.onFailure(failure::set) }
                    worker.start()
                    worker.join(5000)
                    assertFalse("Directory filtering must release the workspace lock", worker.isAlive)
                    failure.get()?.let { throw it }
                }
                true
            }
        }
        assertTrue(attempted)
        assertTrue(error.message, error.message!!.contains("Workspace changed during acceptance"))
    }

    @Test fun finalFenceHoldsLockThroughReceiptAndChecksCurrentAuthorization() {
        val h = Harness()
        val snapshot = h.snapshot()
        val attempted = CountDownLatch(1)
        val published = CountDownLatch(1)
        val failure = AtomicReference<Throwable?>()
        val worker = Thread {
            attempted.countDown()
            runCatching { h.publish(h.f.item("fenced", "artifact", JSONObject().put("content", "Later work"))) }
                .onFailure(failure::set)
            published.countDown()
        }
        val receipt = h.workspace.withAcceptanceFence(snapshot) {
            worker.start()
            assertTrue(attempted.await(5, TimeUnit.SECONDS))
            assertFalse("Publishing must wait until receipt construction releases the fence", published.await(100, TimeUnit.MILLISECONDS))
            "receipt"
        }
        worker.join(5000)
        assertFalse(worker.isAlive)
        failure.get()?.let { throw it }
        assertEquals("receipt", receipt)
        var issued = false
        assertThrows(IllegalArgumentException::class.java) { h.workspace.withAcceptanceFence(snapshot) { issued = true } }
        assertFalse(issued)
        val fresh = h.snapshot()
        h.rows.afterRead = { key ->
            if (key == h.tokenKey) {
                h.rows.afterRead = null
                h.authorized = false
            }
        }
        assertThrows(IllegalArgumentException::class.java) { h.workspace.withAcceptanceFence(fresh) { issued = true } }
        assertFalse(issued)
    }

    @Test fun removeAndRecreateCannotABAIncludingLegacyGroupsWithoutTokens() {
        listOf(false, true).forEach { legacy ->
            val h = Harness()
            val tokenKey = h.tokenKey
            if (legacy) h.rows.data.remove(tokenKey)
            val snapshot = h.snapshot()
            val original = h.saved(h.f.delivery)
            h.workspace.removeGroup(h.access.groupId)
            val removedToken = h.rows.data[tokenKey]
            assertNotNull(removedToken)
            assertFalse(h.rows.lastRemoval.contains(tokenKey))
            assertEquals(setOf(tokenKey), h.rows.data.keys)
            val author = h.access.copy(personId = original.getString("person_id"), nodeId = original.getString("node_id"),
                round = original.getLong("round"))
            val result = h.workspace.publish(author, h.raw(h.f.item("delivery", "artifact", original.getJSONObject("body"))),
                original.getLong("recorded_at"))
            assertEquals("recorded", result.getString("status"))
            assertEquals(h.f.delivery.getString("sha256"), result.getJSONArray("revisions").getJSONObject(0).getString("sha256"))
            assertNotEquals(removedToken, h.rows.data[tokenKey])
            assertThrows(IllegalArgumentException::class.java) { h.workspace.withAcceptanceFence(snapshot) { error("Stale receipt") } }
        }
    }

    @Test fun memberRevocationDuringEvaluationRejectsWithoutGroupRemovalOrWorkspaceMutation() {
        val h = Harness()
        assertTrue(h.evaluate().accepted)
        val token = h.rows.data[h.tokenKey]
        var revoked = false
        val deliveryKey = h.key(h.f.delivery)
        h.rows.emptyPages = 0
        h.rows.afterRead = { key ->
            if (h.rows.emptyPages > 0 && key == deliveryKey) {
                h.rows.afterRead = null
                h.memberIds.remove(h.access.personId)
                revoked = true
            }
        }
        val receipt = h.evaluate()
        assertTrue(revoked)
        assertTrue(h.authorized)
        assertEquals(token, h.rows.data[h.tokenKey])
        assertFalse(receipt.accepted)
        assertTrue(receipt.feedback, receipt.feedback.contains("Acceptance member access was removed"))
        assertNotNull(h.saved(h.f.delivery))
        h.memberIds.add(h.access.personId)
        val restored = h.evaluate()
        assertTrue(restored.feedback, restored.accepted)
    }

    @Test fun snapshotChecksMembershipAtEntryAndDuringScanWithoutChangingHistoricalReads() {
        listOf(false, true).forEach { duringScan ->
            val h = Harness()
            if (duringScan) h.rows.afterRead = { key ->
                if (key.contains(":head:")) {
                    h.rows.afterRead = null
                    h.memberIds.clear()
                }
            } else h.memberIds.clear()
            val error = assertThrows(IllegalArgumentException::class.java) { h.snapshot() }
            assertTrue(error.message, error.message!!.contains("Acceptance member access was removed"))
            assertTrue(h.authorized)
            assertEquals(0, h.rows.emptyPages)
            assertNotNull(h.workspace.read(h.access.copy(turnId = "later-turn"), h.f.delivery.getString("object_id"), 1))
        }
    }

    @Test fun finalFenceRechecksExactPersonMembershipBeforeIssuingReceipt() {
        val h = Harness()
        val snapshot = h.snapshot()
        h.rows.afterRead = { key ->
            if (key == h.tokenKey) {
                h.rows.afterRead = null
                h.memberIds.clear()
            }
        }
        var issued = false
        val error = assertThrows(IllegalArgumentException::class.java) {
            h.workspace.withAcceptanceFence(snapshot) { issued = true }
        }
        assertFalse(issued)
        assertTrue(h.authorized)
        assertTrue(error.message, error.message!!.contains("Acceptance member access was removed"))
        h.memberIds.add(h.access.personId)
        listOf("", "not-a-member").forEach { person ->
            assertThrows(IllegalArgumentException::class.java) {
                h.workspace.acceptanceReviewSnapshot(h.access.copy(personId = person), h.bindings())
            }
        }
    }

    @Test fun snapshotIsWorkspaceAndScopeBoundAndDoesNotShareMutableReviewObjects() {
        val h = Harness()
        val snapshot = h.snapshot()
        val binding = CollaborationAcceptanceReviewSnapshot.Binding.of(h.f.delivery, CollaborationReviewContract.KIND,
            "document", h.f.criterion.getString("requirement"))
        snapshot.reviews(binding).single().getJSONObject("body").getJSONObject(CollaborationReviewContract.KIND).put("verdict", "refuted")
        assertEquals("supported", snapshot.reviews(binding).single().getJSONObject("body").getJSONObject(CollaborationReviewContract.KIND).getString("verdict"))
        assertThrows(IllegalArgumentException::class.java) {
            CollaborationResearchWorkspace(h.rows).withAcceptanceFence(snapshot) { error("Foreign snapshot") }
        }
        h.publish(h.f.item("other-group", "artifact", JSONObject().put("content", "Unrelated work")),
            who = h.access.copy(groupId = "other-group"))
        assertTrue(h.workspace.withAcceptanceFence(snapshot) { true })
    }

    @Test fun isolatedNewDissentIsNotConsumedButHiddenSettlementCannotEraseVisibleDissent() {
        listOf(false, true).forEach { semantic ->
            val h = Harness()
            val hidden = h.review(semantic, who = h.access)
            assertTrue(h.evaluate().feedback, h.evaluate().accepted)
            val node = h.workspace.read(h.access.copy(round = 101), hidden.getString("object_id"), 1)!!.getString("node_id")
            assertFalse(h.evaluate(who = h.access.copy(dependencyNodes = setOf(node))).accepted)
            assertFalse(h.evaluate(who = h.access.copy(round = 101)).accepted)

            val other = Harness()
            val dissent = other.review(semantic)
            other.review(semantic, "supported", dissent, who = other.access)
            val receipt = other.evaluate()
            assertFalse(receipt.accepted)
            assertTrue(receipt.feedback, receipt.feedback.contains("newer isolated revision"))
            assertTrue(other.evaluate(who = other.access.copy(round = 101)).accepted)
        }
    }

    @Test fun staleUnrelatedAndRecommendationOnlyReviewsDoNotContaminateTheIndex() {
        val h = Harness()
        val unrelated = h.body(false, "refuted")
        unrelated.getJSONObject(CollaborationReviewContract.KIND).put("criterion_id", "unrelated")
        h.review(body = unrelated)
        val stale = h.body(false, "refuted", JSONObject(h.f.delivery.toString()).put("sha256", "0".repeat(64)))
        h.review(body = stale)
        h.review(who = h.access.copy(runId = "historical-run", turnId = "historical-turn", round = 10))
        h.publish(h.f.item("optional", "decision", JSONObject().put("recommendations", JSONArray().put("Improve formatting"))))
        assertTrue(h.evaluate().feedback, h.evaluate().accepted)
    }

    @Test fun corruptionMissingHistoryAndCrossGroupRowsFailClosed() {
        listOf("missing-history", "tampered-history", "cross-group", "hidden-head", "bad-token").forEach { fault ->
            val h = Harness()
            val first = h.review()
            val second = h.review(verdict = "supported", previous = first,
                who = if (fault == "hidden-head") h.access else h.access.copy(round = 11))
            when (fault) {
                "missing-history" -> h.rows.data.remove(h.key(first))
                "bad-token" -> h.rows.data[h.tokenKey] = "broken-token"
                else -> {
                    val ref = if (fault == "hidden-head") second else first
                    val key = h.key(ref, head = fault == "hidden-head")
                    val value = JSONObject(h.rows.data.getValue(key)).put("person_id", "tampered")
                    if (fault == "cross-group") {
                        value.put("group_id", "other-group").remove("sha256")
                        value.put("sha256", AgentNativeJsonCodec.sha256(value.toString()))
                    }
                    h.rows.data[key] = value.toString()
                }
            }
            assertFalse(fault, h.evaluate().accepted)
        }
    }

    @Test fun storageFailureAndNonAdvancingPagesAreNotSuccessfulAcceptance() {
        listOf(false, true).forEach { corruptPage ->
            val h = Harness()
            val paged = PagedRows(h, 4101)
            val broken = object : CollaborationWorkspaceRows by paged {
                override fun page(prefix: String, after: String, limit: Int): List<String> {
                    if (paged.pages == 20) {
                        if (corruptPage) return listOf(after)
                        error("Storage unavailable during acceptance snapshot")
                    }
                    return paged.page(prefix, after, limit)
                }
            }
            val receipt = h.evaluate(broken)
            assertFalse(receipt.accepted)
            assertTrue(receipt.feedback, receipt.feedback.contains(if (corruptPage) "non-advancing" else "Storage unavailable"))
        }
    }
}
