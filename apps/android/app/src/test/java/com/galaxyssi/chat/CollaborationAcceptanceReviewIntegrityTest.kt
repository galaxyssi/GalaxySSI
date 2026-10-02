package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationAcceptanceReviewIntegrityTest {
    private class Harness(val semantic: Boolean) {
        val f = CollaborationGoalAcceptanceTest.Fixture(reviewKind = CollaborationReviewContract.KIND)
        val access get() = f.access.copy(round = 1000)
        val target get() = if (semantic) f.mapping else f.delivery
        val field get() = if (semantic) CollaborationSemanticGoalCoverage.REVIEW else CollaborationReviewContract.KIND
        private var dispatch = 0

        fun saved(ref: JSONObject) = requireNotNull(f.workspace.read(access, ref.getString("object_id"), ref.getInt("revision")))
        fun body(target: JSONObject = this.target, verdict: String = "supported", unresolved: Boolean = false): JSONObject {
            val check = if (semantic) f.coverageReviewBody(target) else
                JSONObject(saved(f.review).getJSONObject("body").getJSONObject(field).toString()).put("target", target)
            check.put("verdict", verdict).put("unresolved", if (unresolved) JSONArray().put("Required constraint is not satisfied") else JSONArray())
            if (semantic && verdict != "supported") {
                check.getJSONArray("segments").getJSONObject(0).put("verdict", verdict)
                    .put("unresolved", if (unresolved) JSONArray().put("Source constraint remains omitted") else JSONArray())
            }
            return JSONObject().put(field, check)
        }
        fun item(id: String, body: JSONObject, target: JSONObject = this.target, previous: JSONObject? = null) =
            f.item(id, CollaborationReviewContract.KIND, body).put("parents", JSONArray().put(target)).apply {
                if (previous != null) put("object_id", previous.getString("object_id")).put("base_revision", previous.getInt("revision"))
            }
        fun publish(item: JSONObject, person: String = "dissenter", who: CollaborationWorkspaceAccess = access.copy(round = 10)): JSONObject =
            f.workspace.publish(who.copy(nodeId = "integrity-${++dispatch}", personId = person),
                JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Integrity fixture")
                    .put("candidates", JSONArray()).put("findings", JSONArray()).put("questions", JSONArray())
                    .put("workspace", JSONArray().put(item)).toString())
        fun recorded(item: JSONObject, person: String = "dissenter", who: CollaborationWorkspaceAccess = access.copy(round = 10)): JSONObject {
            val result = publish(item, person, who)
            assertEquals(result.toString(), "recorded", result.optString("status"))
            return result.getJSONArray("revisions").getJSONObject(0)
        }
        fun assess(target: JSONObject = this.target, review: JSONObject? = null): CollaborationAcceptanceReceipt {
            val report = JSONObject(f.assessment().toString())
            if (semantic) report.getJSONObject("goal_coverage").put("mapping", target).apply { if (review != null) put("review", review) }
            else report.getJSONArray("criteria").getJSONObject(0).put("delivery", target).apply { if (review != null) put("review", review) }
            return f.evaluate(report.toString(), who = access)
        }
        fun revisionKey(ref: JSONObject) = f.rows.data.keys.single { it.endsWith("revision:${ref.getString("object_id")}:${ref.getInt("revision")}") }
        fun headKey(ref: JSONObject) = f.rows.data.keys.single { it.endsWith("head:${ref.getString("object_id")}") }
    }

    private class PagedRows(val h: Harness, val count: Int, private val returnedPageSize: Int = 100) : CollaborationWorkspaceRows {
        private val prefix = h.headKey(h.target).substringBefore("head:")
        private val template = h.saved(h.f.delivery)
        private val directory = java.util.TreeSet<String>().apply {
            addAll(h.f.rows.data.keys.filter { it.startsWith(prefix + "head:") })
            repeat(count) { add(prefix + "head:" + (it + 1).toString(16).padStart(64, '0')) }
        }
        var pages = 0
        var emptyPages = 0
        var largestRequest = 0
        var syntheticReads = 0
        private var cachedId = ""
        private var cachedValue = ""
        override fun commit(values: Map<String, String>) = error("Read-only paged fixture")
        override fun page(prefix: String, after: String, limit: Int): List<String> {
            require(prefix == this.prefix + "head:")
            pages++
            largestRequest = maxOf(largestRequest, limit)
            return directory.tailSet(after, false).asSequence().take(minOf(limit, returnedPageSize)).toList()
                .also { if (it.isEmpty()) emptyPages++ }
        }
        override fun read(key: String): String? {
            h.f.rows.data[key]?.let { return it }
            val id = when {
                key.startsWith(prefix + "head:") -> key.removePrefix(prefix + "head:")
                key.startsWith(prefix + "revision:") && key.endsWith(":1") -> key.removePrefix(prefix + "revision:").removeSuffix(":1")
                else -> return null
            }
            val index = id.toIntOrNull(16) ?: return null
            if (index !in 1..count || id != index.toString(16).padStart(64, '0')) return null
            syntheticReads++
            if (id == cachedId) return cachedValue
            val value = JSONObject(template.toString()).put("object_id", id)
            value.remove("sha256")
            value.put("sha256", AgentNativeJsonCodec.sha256(value.toString()))
            cachedId = id
            cachedValue = value.toString()
            return cachedValue
        }
    }

    private fun extendReviewHistory(h: Harness, dissent: JSONObject, length: Int, hidden: Boolean) {
        val original = h.saved(dissent)
        val revisionPrefix = h.revisionKey(dissent).removeSuffix("1")
        var previousHash = dissent.getString("sha256")
        var latest = original.toString()
        for (version in 2..length) {
            val value = JSONObject(original.toString()).put("revision", version).put("previous_sha256", previousHash)
                .put("round", if (hidden) h.access.round else 10L).put("node_id", "history-$version")
            if (version == length) value.put("body", h.body())
            value.remove("sha256")
            previousHash = AgentNativeJsonCodec.sha256(value.toString())
            value.put("sha256", previousHash)
            latest = value.toString()
            h.f.rows.data[revisionPrefix + version] = latest
        }
        h.f.rows.data[h.headKey(dissent)] = latest
    }

    @Test fun independentDeliveryAndCoverageStillAccept() {
        listOf(false, true).forEach { semantic ->
            val h = Harness(semantic)
            val receipt = h.assess()
            assertTrue(receipt.feedback, receipt.accepted)
        }
    }

    @Test fun ancestorAuthorCannotReviewARepublishedObject() {
        listOf(false, true).forEach { semantic ->
            val h = Harness(semantic)
            val originalAuthor = h.saved(h.target).getString("person_id")
            val copy = h.recorded(h.f.item("copied-target", "artifact", h.saved(h.target).getJSONObject("body"))
                .put("parents", JSONArray().put(h.target)), person = "copy-author")
            val review = h.recorded(h.item("copied-review", h.body(copy), copy), person = originalAuthor, who = h.access.copy(round = 11))
            val receipt = h.assess(copy, review)
            assertFalse(receipt.accepted)
            assertTrue(receipt.feedback, receipt.feedback.contains("ancestor author"))
        }
    }

    @Test fun independentReviewerCanReviewDeclaredDerivationWithSharedAncestors() {
        listOf(false, true).forEach { semantic ->
            val h = Harness(semantic)
            val left = h.recorded(h.f.item("left", "artifact", h.saved(h.target).getJSONObject("body"))
                .put("parents", JSONArray().put(h.target)), "left-author")
            val right = h.recorded(h.f.item("right", "artifact", h.saved(h.target).getJSONObject("body"))
                .put("parents", JSONArray().put(h.target)), "right-author")
            val combined = h.recorded(h.f.item("combined", "artifact", h.saved(h.target).getJSONObject("body"))
                .put("parents", JSONArray().put(left).put(right)), "combiner", h.access.copy(round = 11))
            val review = h.recorded(h.item("combined-review", h.body(combined), combined), "independent", h.access.copy(round = 12))
            val receipt = h.assess(combined, review)
            assertTrue(receipt.feedback, receipt.accepted)
            assertEquals(setOf(h.saved(h.target).getString("person_id"), "left-author", "right-author", "combiner"),
                h.f.workspace.contributorIds(h.access, combined))
        }
    }

    @Test fun previousRevisionParentsRemainPartOfAuthorship() {
        val h = Harness(false)
        val first = h.recorded(h.f.item("derived", "artifact", JSONObject().put("content", "Derived work"))
            .put("parents", JSONArray().put(h.target)), "editor")
        val second = h.recorded(h.f.item("unused", "artifact", JSONObject().put("content", "Revised derived work"))
            .put("object_id", first.getString("object_id")).put("base_revision", 1), "later-editor", h.access.copy(round = 11))
        assertEquals(setOf("author", "editor", "later-editor"), h.f.workspace.contributorIds(h.access, second))
        val review = h.recorded(h.item("derived-review", h.body(second), second), "author", h.access.copy(round = 12))
        assertFalse(h.assess(second, review).accepted)
    }

    @Test fun missingTamperedAndWrongDigestAncestorsFailClosed() {
        listOf("missing", "tampered", "wrong-digest").forEach { fault ->
            val h = Harness(true)
            val parent = JSONObject(h.target.toString())
            if (fault == "wrong-digest") parent.put("sha256", "0".repeat(64))
            val copy = h.recorded(h.f.item("derived", "artifact", h.saved(h.target).getJSONObject("body"))
                .put("parents", JSONArray().put(parent)), "copy-author")
            if (fault == "missing") h.f.rows.data.remove(h.revisionKey(h.target))
            if (fault == "tampered") {
                val original = JSONObject(h.f.rows.data.getValue(h.revisionKey(h.target)))
                original.put("person_id", "hidden-author")
                h.f.rows.data[h.revisionKey(h.target)] = original.toString()
            }
            assertTrue(fault, runCatching { h.f.workspace.contributorIds(h.access, copy) }.isFailure)
        }
    }

    @Test fun ancestryReadsDoNotWidenIndependentOrGroupAccess() {
        val h = Harness(false)
        val parent = h.recorded(h.f.item("isolated-parent", "artifact", JSONObject().put("content", "Private work")),
            "parent-author", h.access.copy(round = 100))
        val parentNode = h.saved(parent).getString("node_id")
        val child = h.recorded(h.f.item("isolated-child", "artifact", JSONObject().put("content", "Derived private work"))
            .put("parents", JSONArray().put(parent)), "child-author", h.access.copy(round = 100, dependencyNodes = setOf(parentNode)))
        val childNode = h.saved(child).getString("node_id")
        val reader = h.access.copy(round = 100, dependencyNodes = setOf(childNode))
        assertNotNull(h.f.workspace.read(reader, child.getString("object_id"), 1))
        assertNull(h.f.workspace.read(reader, parent.getString("object_id"), 1))
        assertTrue(runCatching { h.f.workspace.contributorIds(reader, child) }.isFailure)
        assertTrue(runCatching { h.f.workspace.contributorIds(h.access.copy(groupId = "other-group"), child) }.isFailure)
        assertEquals(setOf("parent-author", "child-author"), h.f.workspace.contributorIds(h.access, child))
    }

    @Test fun negativeAndUntestedReviewsCannotBeCherryPickedAway() {
        listOf(false, true).forEach { semantic ->
            listOf("refuted", "not_tested").forEach { verdict ->
                listOf(false, true).forEach { unresolved ->
                    val h = Harness(semantic)
                    h.recorded(h.item("dissent", h.body(verdict = verdict, unresolved = unresolved)))
                    val receipt = h.assess()
                    assertFalse(receipt.accepted)
                    assertTrue(receipt.feedback, receipt.feedback.contains("current typed review retains dissent"))
                }
            }
        }
    }

    @Test fun supportedWithUnresolvedIssuesCannotBePublishedAsASettlement() {
        listOf(false, true).forEach { semantic ->
            val h = Harness(semantic)
            val dissent = h.recorded(h.item("dissent", h.body(verdict = "refuted", unresolved = true)))
            val result = h.publish(h.item("unused", h.body(unresolved = true), previous = dissent), who = h.access.copy(round = 11))
            assertEquals("rejected", result.getString("status"))
            assertFalse(h.assess().accepted)
        }
    }

    @Test fun sameReviewerCanExplicitlySettleDissentWithoutDeletingHistory() {
        listOf(false, true).forEach { semantic ->
            val h = Harness(semantic)
            val dissent = h.recorded(h.item("dissent", h.body(verdict = "refuted", unresolved = true)))
            assertFalse(h.assess().accepted)
            val settledBody = h.body().put("recommendations", JSONArray().put("Optional presentation improvement"))
            settledBody.getJSONObject(h.field).put("rationale", "Rechecked the preserved target and resolved the recorded objection")
            val settled = h.recorded(h.item("unused", settledBody, previous = dissent), who = h.access.copy(round = 11))
            val receipt = h.assess()
            assertTrue(receipt.feedback, receipt.accepted)
            assertEquals(2, settled.getInt("revision"))
            assertEquals("refuted", h.saved(dissent).getJSONObject("body").getJSONObject(h.field).getString("verdict"))
            assertEquals(dissent.getString("sha256"), h.saved(settled).getString("previous_sha256"))
        }
    }

    @Test fun anotherAuthorOrRetargetedRevisionCannotEraseDissent() {
        listOf(false, true).forEach { semantic ->
            val h = Harness(semantic)
            val dissent = h.recorded(h.item("dissent", h.body(verdict = "refuted", unresolved = true)))
            assertEquals("rejected", h.publish(h.item("unused", h.body(), previous = dissent), person = "lead",
                who = h.access.copy(round = 11)).getString("status"))
            val other = h.recorded(h.f.item("different-target", "artifact", h.saved(h.target).getJSONObject("body")), "another-author")
            assertEquals("rejected", h.publish(h.item("unused", h.body(other), other, dissent),
                who = h.access.copy(round = 11)).getString("status"))
            val switched = if (semantic) JSONObject().put(CollaborationReviewContract.KIND,
                h.saved(h.f.review).getJSONObject("body").getJSONObject(CollaborationReviewContract.KIND)) else
                JSONObject().put(CollaborationSemanticGoalCoverage.REVIEW, h.f.coverageReviewBody(h.f.mapping))
            assertEquals("rejected", h.publish(h.item("unused", switched, previous = dissent),
                who = h.access.copy(round = 11)).getString("status"))
            if (!semantic) listOf("criterion_id", "requirement").forEach { field ->
                val changed = h.body()
                changed.getJSONObject(h.field).put(field, "different")
                assertEquals("rejected", h.publish(h.item("unused", changed, previous = dissent),
                    who = h.access.copy(round = 11)).getString("status"))
            }
            assertFalse(h.assess().accepted)
        }
    }

    @Test fun recommendationsAndUnrelatedTargetsDoNotBecomeBlockers() {
        listOf(false, true).forEach { semantic ->
            val h = Harness(semantic)
            h.recorded(h.item("notes", h.body().put("recommendations", JSONArray().put("Optional follow-up"))))
            h.recorded(h.f.item("recommendations-only", "decision", JSONObject().put("recommendations", JSONArray().put("Optional formatting")))
                .put("parents", JSONArray().put(h.target)))
            val other = h.recorded(h.f.item("other-target", "artifact", h.saved(h.target).getJSONObject("body")), "other-author")
            h.recorded(h.item("other-dissent", h.body(other, "refuted", true), other), who = h.access.copy(round = 11))
            val wrongHash = JSONObject(h.target.toString()).put("sha256", "0".repeat(64))
            h.recorded(h.item("other-hash", h.body(wrongHash, "refuted", true)))
            if (!semantic) {
                val differentCriterion = h.body(verdict = "refuted", unresolved = true)
                differentCriterion.getJSONObject(h.field).put("criterion_id", "different-criterion")
                h.recorded(h.item("different-criterion", differentCriterion))
                val differentRequirement = h.body(verdict = "refuted", unresolved = true)
                differentRequirement.getJSONObject(h.field).put("requirement", "Unrelated requirement")
                h.recorded(h.item("different-requirement", differentRequirement))
            }
            val receipt = h.assess()
            assertTrue(receipt.feedback, receipt.accepted)
        }
    }

    @Test fun reviewsOfOlderTargetRevisionsDoNotBlockRevisedWork() {
        listOf(false, true).forEach { semantic ->
            val h = Harness(semantic)
            h.recorded(h.item("dissent", h.body(verdict = "refuted", unresolved = true)))
            val revised = h.recorded(h.f.item("unused", "artifact", h.saved(h.target).getJSONObject("body"))
                .put("object_id", h.target.getString("object_id")).put("base_revision", 1), "editor")
            val review = h.recorded(h.item("new-review", h.body(revised), revised), "new-reviewer", h.access.copy(round = 11))
            val receipt = h.assess(revised, review)
            assertTrue(receipt.feedback, receipt.accepted)
        }
    }

    @Test fun isolatedAndOtherRunReviewsAreNotExposedAsCurrentConflicts() {
        listOf(false, true).forEach { semantic ->
            val h = Harness(semantic)
            h.recorded(h.item("old-scope", h.body(verdict = "refuted", unresolved = true)),
                who = h.access.copy(runId = "other-run", turnId = "other-turn"))
            val hidden = h.recorded(h.item("isolated", h.body(verdict = "refuted", unresolved = true)), who = h.access)
            assertNull(h.f.workspace.read(h.access, hidden.getString("object_id"), 1))
            assertTrue(h.f.workspace.currentAcceptanceReviews(h.access, h.target).none { it.getString("object_id") == hidden.getString("object_id") })
            assertTrue(h.assess().feedback, h.assess().accepted)
            val visible = h.f.evaluate(who = h.access.copy(round = 1001))
            assertFalse(visible.accepted)
        }
    }

    @Test fun corruptOrMissingCurrentReviewCannotDisappearFromConflictInspection() {
        listOf("revision", "head", "missing").forEach { fault ->
            val h = Harness(true)
            val dissent = h.recorded(h.item("dissent", h.body(verdict = "refuted", unresolved = true)))
            val key = if (fault == "head") h.headKey(dissent) else h.revisionKey(dissent)
            if (fault == "missing") h.f.rows.data.remove(key) else {
                val corrupted = JSONObject(h.f.rows.data.getValue(key))
                corrupted.getJSONObject("body").getJSONObject(h.field).put("verdict", "supported").put("unresolved", JSONArray())
                h.f.rows.data[key] = corrupted.toString()
            }
            assertFalse(fault, h.assess().accepted)
        }
    }

    @Test fun isolatedSettlementCannotHidePreviouslyVisibleDissent() {
        listOf(false, true).forEach { semantic ->
            val h = Harness(semantic)
            val dissent = h.recorded(h.item("dissent", h.body(verdict = "refuted", unresolved = true)))
            h.recorded(h.item("unused", h.body(), previous = dissent), who = h.access)
            val receipt = h.assess()
            assertFalse(receipt.accepted)
            assertTrue(receipt.feedback, receipt.feedback.contains("newer isolated revision"))
            val resolved = h.f.evaluate(who = h.access.copy(round = 1001))
            assertTrue(resolved.feedback, resolved.accepted)
        }
    }

    @Test fun supportedCoverageSettlementMustStillReviewTheCompleteExactMapping() {
        val h = Harness(true)
        val dissent = h.recorded(h.item("dissent", h.body(verdict = "refuted", unresolved = true)))
        val incomplete = h.body()
        incomplete.getJSONObject(h.field).getJSONArray("segments").getJSONObject(0).put("criterion_ids", JSONArray().put("unrelated"))
        h.recorded(h.item("unused", incomplete, previous = dissent), who = h.access.copy(round = 11))
        assertFalse(h.assess().accepted)
    }

    @Test fun settlementCannotDeleteOrRewriteThePreservedDissentRevision() {
        listOf(false, true).forEach { semantic ->
            listOf(false, true).forEach { missing ->
                val h = Harness(semantic)
                val dissent = h.recorded(h.item("dissent", h.body(verdict = "refuted", unresolved = true)))
                h.recorded(h.item("unused", h.body(), previous = dissent), who = h.access.copy(round = 11))
                val key = h.revisionKey(dissent)
                if (missing) h.f.rows.data.remove(key) else {
                    val original = JSONObject(h.f.rows.data.getValue(key)).put("person_id", "replaced-reviewer")
                    original.remove("sha256")
                    original.put("sha256", AgentNativeJsonCodec.sha256(original.toString()))
                    h.f.rows.data[key] = original.toString()
                }
                assertFalse(h.assess().accepted)
            }
        }
    }

    @Test fun exactPriorRevisionChainCannotBeMissingOrRehashedBehindItsChild() {
        listOf(false, true).forEach { missing ->
            val h = Harness(false)
            val second = h.recorded(h.f.item("unused", "artifact", JSONObject().put("content", "Revised work"))
                .put("object_id", h.target.getString("object_id")).put("base_revision", 1), "editor")
            val key = h.revisionKey(h.target)
            if (missing) h.f.rows.data.remove(key) else {
                val original = JSONObject(h.f.rows.data.getValue(key)).put("person_id", "replaced-author")
                original.remove("sha256")
                original.put("sha256", AgentNativeJsonCodec.sha256(original.toString()))
                h.f.rows.data[key] = original.toString()
            }
            assertTrue(runCatching { h.f.workspace.contributorIds(h.access, second) }.isFailure)
        }
    }

    @Test fun historicalAncestorAuthorshipIsRetainedButSameTurnForeignRunsStayIsolated() {
        val h = Harness(false)
        val historical = h.recorded(h.f.item("historical", "artifact", JSONObject().put("content", "Historical contribution")),
            "historical-author", h.access.copy(runId = "old-run", turnId = "old-turn", round = 1))
        val derived = h.recorded(h.f.item("historical-derived", "artifact", JSONObject().put("content", "Current derived result"))
            .put("parents", JSONArray().put(historical)), "current-author")
        assertEquals(setOf("historical-author", "current-author"), h.f.workspace.contributorIds(h.access, derived))
        val review = h.recorded(h.item("historical-self-review", h.body(derived), derived), "historical-author", h.access.copy(round = 11))
        assertFalse(h.assess(derived, review).accepted)
        val foreign = h.recorded(h.f.item("foreign", "artifact", JSONObject().put("content", "Other run")),
            "foreign-author", h.access.copy(runId = "foreign-run", round = 1))
        assertNull(h.f.workspace.read(h.access, foreign.getString("object_id"), 1))
        val rejected = h.publish(h.f.item("foreign-derived", "artifact", JSONObject().put("content", "Invalid derivation"))
            .put("parents", JSONArray().put(foreign)))
        assertEquals("rejected", rejected.getString("status"))
    }

    @Test fun cyclicDeclaredParentsFailClosedEvenWhenStoredDigestsAreValid() {
        val h = Harness(false)
        val saved = h.saved(h.target)
        saved.put("parents", JSONArray().put(JSONObject().put("object_id", h.target.getString("object_id")).put("revision", 1)))
        saved.remove("sha256")
        saved.put("sha256", AgentNativeJsonCodec.sha256(saved.toString()))
        h.f.rows.data[h.revisionKey(h.target)] = saved.toString()
        h.f.rows.data[h.headKey(h.target)] = saved.toString()
        val ref = JSONObject(h.target.toString()).put("sha256", saved.getString("sha256"))
        val error = assertThrows(IllegalArgumentException::class.java) { h.f.workspace.contributorIds(h.access, ref) }
        assertTrue(error.message, error.message!!.contains("cycle"))
    }

    @Test fun deepLegalAncestryBeyond4096IsFullyInspectedWithoutRecursion() {
        val id = "a".repeat(64)
        val hash = "b".repeat(64)
        fun ref(version: Int) = JSONObject().put("object_id", id).put("revision", version).put("sha256", hash)
        val depth = 12000
        var reads = 0
        val authors = CollaborationAcceptanceAncestry.contributors(ref(depth)) { _, version ->
            reads++
            ref(version).put("person_id", if (version == 1) "oldest-author" else "author")
                .put("parents", JSONArray()).put("previous_sha256", if (version > 1) hash else "")
        }
        assertEquals(setOf("oldest-author", "author"), authors)
        assertEquals(depth, reads)
        val missing = assertThrows(IllegalArgumentException::class.java) {
            CollaborationAcceptanceAncestry.contributors(ref(depth)) { _, version ->
                if (version == 1) null else ref(version).put("person_id", "author").put("parents", JSONArray()).put("previous_sha256", hash)
            }
        }
        assertTrue(missing.message, missing.message!!.contains("incomplete"))
    }

    @Test fun broadLegalAncestryBeyond16384DeduplicatesButStillChecksEveryReference() {
        val rootId = "a".repeat(64)
        val hash = "b".repeat(64)
        val count = 17000
        fun ref(id: String) = JSONObject().put("object_id", id).put("revision", 1).put("sha256", hash)
        fun child(index: Int) = index.toString(16).padStart(64, '0')
        val parents = JSONArray((1..count).map { ref(child(it)) }).put(ref(child(1)))
        var reads = 0
        fun read(id: String, version: Int): JSONObject {
            assertEquals(1, version)
            reads++
            return ref(id).put("person_id", if (id == child(count)) "last-author" else "author")
                .put("previous_sha256", "").put("parents", if (id == rootId) parents else JSONArray())
        }
        assertEquals(setOf("author", "last-author"), CollaborationAcceptanceAncestry.contributors(ref(rootId), ::read))
        assertEquals(count + 1, reads)
        parents.put(ref(child(1)).put("sha256", "0".repeat(64)))
        val mismatch = assertThrows(IllegalArgumentException::class.java) {
            CollaborationAcceptanceAncestry.contributors(ref(rootId), ::read)
        }
        assertTrue(mismatch.message, mismatch.message!!.contains("digest changed"))
    }

    @Test fun moreThan10000DirectoryEntriesAllowAcceptanceAndDoNotHideLateDissent() {
        val h = Harness(false)
        fun evaluate(rows: CollaborationWorkspaceRows) = CollaborationGoalAcceptance(CollaborationResearchWorkspace(rows), h.f.ledger)
            .evaluate(h.access, h.f.assessment().toString(), h.f.prior, h.f.goal, 10)
        fun assertSingleScan(rows: PagedRows) {
            val headPrefix = h.headKey(h.target).substringBefore("head:") + "head:"
            val headCount = rows.count + h.f.rows.data.keys.count { it.startsWith(headPrefix) }
            assertEquals(100, rows.largestRequest)
            assertEquals((headCount + 99) / 100 + 1, rows.pages)
            assertEquals(1, rows.emptyPages)
            // Each synthetic object needs one head read and one immutable revision read.
            assertEquals(2 * rows.count, rows.syntheticReads)
        }
        val rows = PagedRows(h, 10001)
        val accepted = evaluate(rows)
        assertTrue(accepted.feedback, accepted.accepted)
        assertSingleScan(rows)

        h.recorded(h.item("paged-dissent", h.body(verdict = "refuted", unresolved = true)))
        val withDissent = PagedRows(h, 10001)
        val rejected = evaluate(withDissent)
        assertFalse(rejected.accepted)
        assertTrue(rejected.feedback, rejected.feedback.contains("current typed review retains dissent"))
        assertSingleScan(withDissent)
    }

    @Test fun shortPagesDoNotMeanEndAndInvalidCursorsAreRejected() {
        val h = Harness(false)
        h.recorded(h.item("short-page-dissent", h.body(verdict = "refuted", unresolved = true)))
        val short = PagedRows(h, 4100, returnedPageSize = 7)
        val reviews = CollaborationResearchWorkspace(short).currentAcceptanceReviews(h.access, h.target)
        assertTrue(reviews.any { it.getJSONObject("body").getJSONObject(h.field).getString("verdict") == "refuted" })
        assertTrue(short.pages > 500)
        assertEquals(1, short.emptyPages)
        listOf("repeat", "duplicate", "descending", "oversized").forEach { fault ->
            val paged = PagedRows(h, 201)
            val invalid = object : CollaborationWorkspaceRows by paged {
                override fun page(prefix: String, after: String, limit: Int): List<String> {
                    val page = paged.page(prefix, after, limit)
                    return when (fault) {
                        "repeat" -> if (after.isEmpty()) page else listOf(after)
                        "duplicate" -> listOf(page.first(), page.first())
                        "descending" -> page.reversed()
                        else -> page + (prefix + "f".repeat(64))
                    }
                }
            }
            assertThrows(IllegalArgumentException::class.java) { CollaborationResearchWorkspace(invalid).currentAcceptanceReviews(h.access, h.target) }
        }
    }

    @Test fun longReviewHistoryHasNoTotalCapAndIsolatedSettlementStillCannotEraseDissent() {
        listOf(false, true).forEach { hidden ->
            val h = Harness(false)
            val dissent = h.recorded(h.item("long-dissent", h.body(verdict = "refuted", unresolved = true)))
            extendReviewHistory(h, dissent, length = 5001, hidden = hidden)
            val receipt = h.assess()
            if (hidden) {
                assertFalse(receipt.accepted)
                assertTrue(receipt.feedback, receipt.feedback.contains("newer isolated revision"))
            } else assertTrue(receipt.feedback, receipt.accepted)
            val visible = h.f.evaluate(who = h.access.copy(round = 1001))
            assertTrue(visible.feedback, visible.accepted)
            h.f.rows.data.remove(h.revisionKey(dissent))
            val missing = h.f.evaluate(who = h.access.copy(round = 1001))
            assertFalse(missing.accepted)
            assertTrue(missing.feedback, missing.feedback.contains("history is incomplete"))
        }
    }

    @Test fun actualStorageFailureAfterManyPagesIsNotSuccessfulAcceptance() {
        val h = Harness(false)
        val paged = PagedRows(h, 5000)
        val unavailable = object : CollaborationWorkspaceRows by paged {
            override fun page(prefix: String, after: String, limit: Int): List<String> {
                check(paged.pages < 42) { "Fixture storage unavailable while inspecting acceptance reviews" }
                return paged.page(prefix, after, limit)
            }
        }
        val receipt = CollaborationGoalAcceptance(CollaborationResearchWorkspace(unavailable), h.f.ledger)
            .evaluate(h.access, h.f.assessment().toString(), h.f.prior, h.f.goal, 10)
        assertFalse(receipt.accepted)
        assertTrue(receipt.feedback, receipt.feedback.contains("Fixture storage unavailable"))
    }
}
