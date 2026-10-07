package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationEvidenceReadCoverageTest {
    private class Fixture(size: Int = 25_000) {
        val rows = CollaborationGoalAcceptanceTest.Rows()
        var allowed = true
        val ledger = CollaborationEvidenceLedger(rows) { allowed }
        val author = CollaborationWorkspaceAccess("group", "run", "turn", 1, "author", "author")
        val reader = author.copy(round = 2, nodeId = "review", personId = "reviewer")
        val ref = ledger.record(author, "invocation", "web_fetch", "{}", JSONObject().put("text", "x".repeat(size)).toString(), 1, 2)
        val id = ref.getString("evidence_id")
        val hash = ref.getString("sha256")
        val source get() = ledger.read(reader, id, hash)!!
        fun page(offset: Int, who: CollaborationWorkspaceAccess = reader) = ledger.readPage(who, id, hash, offset)!!
        fun reference(who: CollaborationWorkspaceAccess = reader, store: CollaborationEvidenceLedger = ledger) =
            store.references(who, JSONArray().put(ref)).getJSONObject(0)
        fun coverage(who: CollaborationWorkspaceAccess = reader) = reference(who).getJSONObject(CollaborationEvidenceReadCoverage.FIELD)
        fun all(who: CollaborationWorkspaceAccess = reader) {
            var offset: Int? = 0
            while (offset != null) offset = page(offset, who).next
        }
        fun accepts(ref: JSONObject = reference(), who: CollaborationWorkspaceAccess = reader) = runCatching {
            CollaborationEvidenceReadCoverage.requireComplete(ref, CollaborationEvidenceReadCoverage.identity(who), source)
        }.isSuccess
    }

    @Test fun browseReadAndCitationAreNotOriginalPageConsumption() {
        val f = Fixture()
        assertEquals(1, f.ledger.browse(f.reader).first.size)
        assertNotNull(f.source)
        assertFalse(f.coverage().getBoolean("complete"))
        assertFalse(f.accepts())
        assertEquals(1, f.rows.data.size)
    }

    @Test fun undeliveredRemotePageCannotCertifyAReviewAndConfirmationIsExactAndDurable() {
        val f = Fixture(100)
        val page = f.ledger.readPage(f.reader, f.id, f.hash, recordCoverage = false)!!
        assertFalse(page.coverage.getBoolean("complete"))
        assertFalse(f.accepts())
        assertEquals(1, f.rows.data.size)
        assertTrue(runCatching { f.ledger.confirmPage(f.reader, f.id, f.hash, 0, "0".repeat(64)) }.isFailure)
        assertFalse(f.accepts())
        val hash = MqttImmutableContent.sha256(page.content)
        assertTrue(f.ledger.confirmPage(f.reader, f.id, f.hash, 0, hash)!!.getBoolean("complete"))
        val stored = f.rows.data.toMap()
        assertTrue(CollaborationEvidenceLedger(f.rows).confirmPage(f.reader, f.id, f.hash, 0, hash)!!.getBoolean("complete"))
        assertEquals(stored, f.rows.data)
        assertTrue(f.accepts())
        assertFalse(f.coverage(f.reader.copy(nodeId = "another-review")).getBoolean("complete"))
    }

    @Test fun confirmedLastPageDoesNotCountLostPagesOrBypassRevocation() {
        val f = Fixture()
        f.ledger.readPage(f.reader, f.id, f.hash, 0, recordCoverage = false)
        val last = f.ledger.readPage(f.reader, f.id, f.hash, 24_000, recordCoverage = false)!!
        val hash = MqttImmutableContent.sha256(last.content)
        f.allowed = false
        assertNull(f.ledger.confirmPage(f.reader, f.id, f.hash, 24_000, hash))
        f.allowed = true
        val confirmed = f.ledger.confirmPage(f.reader, f.id, f.hash, 24_000, hash)!!
        assertEquals(last.content.length, confirmed.getInt("covered_characters"))
        assertEquals(0, confirmed.getInt("first_missing_offset"))
        assertFalse(f.accepts())
    }

    @Test fun finalPageAndEndOffsetDoNotHideMissingMiddlePages() {
        val f = Fixture()
        val length = f.source.toString().length
        f.page(length)
        assertFalse(f.accepts())
        assertEquals(1, f.rows.data.size)
        f.page(0)
        val last = f.page(24_000)
        assertNull(last.next)
        assertEquals(8_000, last.coverage.getInt("first_missing_offset"))
        assertFalse(f.accepts())
        f.page(16_000)
        assertFalse(f.accepts())
        f.page(8_000)
        assertTrue(f.accepts())
        assertTrue(f.coverage().isNull("first_missing_offset"))
    }

    @Test fun overlappingRepeatedAndOutOfOrderPagesMergeWithoutGrowingHistory() {
        val f = Fixture()
        listOf(16_000, 0, 7_000, 14_000, 21_000, 0, 7_000).forEach { f.page(it) }
        assertTrue(f.accepts())
        assertEquals(f.source.toString().length, f.coverage().getInt("covered_characters"))
        val original = f.rows.data.toMap()
        repeat(20) { f.page(0) }
        assertEquals(original, f.rows.data)
        assertEquals(2, f.rows.data.size)
    }

    @Test fun partialCoverageSurvivesStoreRecreationAndOnlyMissingPagesAreNeeded() {
        val f = Fixture()
        val first = f.page(0)
        val reopened = CollaborationEvidenceLedger(f.rows)
        val before = f.reference(store = reopened).getJSONObject(CollaborationEvidenceReadCoverage.FIELD)
        assertFalse(before.getBoolean("complete"))
        var offset = first.next
        while (offset != null) offset = reopened.readPage(f.reader, f.id, f.hash, offset)!!.next
        assertTrue(f.accepts(f.reference(store = CollaborationEvidenceLedger(f.rows))))
    }

    @Test fun coverageIsBoundToEveryDispatchIdentityComponentNotJustMemberName() {
        val f = Fixture()
        f.all()
        val ref = f.reference()
        listOf(f.reader.copy(groupId = "other"), f.reader.copy(runId = "other"), f.reader.copy(turnId = "other"),
            f.reader.copy(round = 3), f.reader.copy(nodeId = "other"), f.reader.copy(personId = "other")).forEach {
            assertFalse(it.toString(), f.accepts(ref, it))
        }
        assertFalse(f.coverage(f.reader.copy(nodeId = "same-person-new-dispatch")).getBoolean("complete"))
        assertFalse(f.coverage(f.reader.copy(personId = "another-person")).getBoolean("complete"))
    }

    @Test fun missingHashDifferentSourceAndForgedReadCoverageCannotPass() {
        val f = Fixture()
        f.all()
        val valid = f.reference()
        listOf("evidence_id", "sha256").forEach { field ->
            val forged = JSONObject(valid.toString())
            forged.getJSONObject(CollaborationEvidenceReadCoverage.FIELD).put(field, "0".repeat(64))
            assertFalse(f.accepts(forged))
        }
        val different = f.reader.copy(nodeId = "other")
        val forgedInput = JSONObject(f.ref.toString()).put(CollaborationEvidenceReadCoverage.FIELD,
            valid.getJSONObject(CollaborationEvidenceReadCoverage.FIELD))
        val sanitized = f.ledger.references(different, JSONArray().put(forgedInput)).getJSONObject(0)
        assertFalse(f.accepts(sanitized, different))
        assertNull(f.ledger.readPage(f.reader, f.id, "0".repeat(64)))
    }

    @Test fun citationSnapshotsAreImmutableSoLaterPagesCannotRetroactivelyCertifyReview() {
        val f = Fixture()
        val before = f.reference()
        f.all()
        assertFalse(f.accepts(before))
        assertTrue(f.accepts())
    }

    @Test fun ownExecutionIsDistinctFromAnotherDispatchReadingIt() {
        val f = Fixture()
        val own = f.reference(f.author)
        assertEquals("same_dispatch_execution", own.getJSONObject(CollaborationEvidenceReadCoverage.FIELD).getString("mode"))
        assertTrue(f.accepts(own, f.author))
        assertFalse(f.accepts(own, f.author.copy(nodeId = "other")))
        assertFalse(f.accepts())
    }

    @Test fun fullyConfirmedAuthorReadRemainsVisibleInFrozenCitationAfterRecreation() {
        val f = Fixture(100)
        val before = f.reference(f.author)
        val page = f.ledger.readPage(f.author, f.id, f.hash, recordCoverage = false)!!
        assertFalse(page.coverage.getBoolean("complete"))
        assertEquals("same_dispatch_execution", f.coverage(f.author).getString("mode"))
        assertFalse(f.coverage(f.author).getBoolean("complete"))
        f.ledger.confirmPage(f.author, f.id, f.hash, 0, MqttImmutableContent.sha256(page.content))

        val after = f.reference(f.author, CollaborationEvidenceLedger(f.rows))
        val coverage = after.getJSONObject(CollaborationEvidenceReadCoverage.FIELD)
        assertEquals("scoped_pages", coverage.getString("mode"))
        assertTrue(coverage.getBoolean("complete"))
        assertEquals(f.author.nodeId, coverage.getJSONObject("reader").getString("node_id"))
        assertTrue(f.accepts(after, f.author))
        assertFalse(f.accepts(after, f.reader))
        assertEquals("same_dispatch_execution", before.getJSONObject(CollaborationEvidenceReadCoverage.FIELD).getString("mode"))
        assertFalse(before.getJSONObject(CollaborationEvidenceReadCoverage.FIELD).getBoolean("complete"))
        assertFalse(f.coverage(f.reader).getBoolean("complete"))
    }

    @Test fun partialAuthorReadPreservesOwnershipWithoutClaimingFullOriginalDelivery() {
        val f = Fixture()
        val page = f.ledger.readPage(f.author, f.id, f.hash, recordCoverage = false)!!
        f.ledger.confirmPage(f.author, f.id, f.hash, 0, MqttImmutableContent.sha256(page.content))
        val partial = f.coverage(f.author)
        assertEquals("same_dispatch_execution", partial.getString("mode"))
        assertFalse(partial.getBoolean("complete"))
        assertEquals(8_000, partial.getInt("covered_characters"))
        assertEquals(8_000, partial.getInt("first_missing_offset"))
        assertTrue(f.accepts(f.reference(f.author), f.author))
        assertFalse(f.accepts())
        f.all(f.author)
        assertEquals("scoped_pages", f.coverage(f.author).getString("mode"))
        assertTrue(f.accepts(f.reference(f.author), f.author))
    }

    @Test fun authorCannotCopyAnotherDispatchsFullReadIntoItsOwnCitation() {
        val f = Fixture(100)
        f.all(f.reader)
        val forged = JSONObject(f.ref.toString()).put(CollaborationEvidenceReadCoverage.FIELD, f.coverage(f.reader))
        val sanitized = f.ledger.references(f.author, JSONArray().put(forged)).getJSONObject(0)
            .getJSONObject(CollaborationEvidenceReadCoverage.FIELD)
        assertEquals("same_dispatch_execution", sanitized.getString("mode"))
        assertFalse(sanitized.getBoolean("complete"))
        assertEquals(0, sanitized.getInt("covered_characters"))
    }

    @Test fun mixedOwnAndPeerReferencesStillRequireOriginalPeerPages() {
        val f = Fixture()
        val own = f.ledger.record(f.reader, "review-read", "collaboration_recall", "{}", "{}", 3, 4)
        fun references() = f.ledger.references(f.reader, JSONArray().put(f.ref).put(own))
        fun validate(refs: JSONArray) = repeat(refs.length()) { index ->
            val ref = refs.getJSONObject(index)
            val source = f.ledger.read(f.reader, ref.getString("evidence_id"), ref.getString("sha256"))!!
            CollaborationEvidenceReadCoverage.requireComplete(ref, CollaborationEvidenceReadCoverage.identity(f.reader), source)
        }
        assertTrue(runCatching { validate(references()) }.isFailure)
        f.all()
        val refs = references()
        validate(refs)
        assertEquals("scoped_pages", refs.getJSONObject(0).getJSONObject(CollaborationEvidenceReadCoverage.FIELD).getString("mode"))
        assertEquals("same_dispatch_execution", refs.getJSONObject(1).getJSONObject(CollaborationEvidenceReadCoverage.FIELD).getString("mode"))
    }

    @Test fun invalidOffsetsAndIsolatedOrRevokedAccessDoNotCreateCoverage() {
        val f = Fixture()
        val original = f.rows.data.toMap()
        listOf(-1, Int.MAX_VALUE, f.source.toString().length + 1).forEach { assertTrue(runCatching { f.page(it) }.isFailure) }
        assertNull(f.ledger.readPage(f.reader.copy(round = 1), f.id, f.hash))
        f.allowed = false
        assertNull(f.ledger.readPage(f.reader, f.id, f.hash))
        assertTrue(runCatching { f.reference() }.isFailure)
        assertEquals(original, f.rows.data)
    }

    @Test fun ordinaryHistoryRecallStillReadsButCannotAttestToAMembersReview() {
        val f = Fixture()
        val unbound = f.reader.copy(nodeId = "", personId = "")
        val page = f.page(0, unbound)
        assertTrue(page.content.isNotBlank())
        assertEquals("unattributed", page.coverage.getString("mode"))
        val citation = f.reference(unbound)
        assertFalse(f.accepts(citation))
        assertEquals(1, f.rows.data.size)
    }

    @Test fun citationLookupDoesNotScanUnrelatedHistory() {
        val f = Fixture()
        f.all()
        repeat(10_000) { f.rows.data["unrelated:$it"] = "historical record" }
        f.rows.reads = 0
        val citation = f.reference()
        assertEquals(2, f.rows.reads)
        assertTrue(f.accepts(citation))
    }

    @Test fun corruptedCoverageFailsClosedAndSourceRemainsIntact() {
        val f = Fixture()
        f.page(0)
        val key = f.rows.data.keys.single { it.contains(":read:") }
        val envelope = JSONObject(f.rows.data.getValue(key))
        envelope.put("payload", envelope.getString("payload").replace("8000", "9999"))
        f.rows.data[key] = envelope.toString()
        assertTrue(runCatching { f.reference() }.isFailure)
        assertTrue(runCatching { f.page(8_000) }.isFailure)
        assertEquals("returned", f.source.getString("status"))
    }

    @Test fun failedCoverageWriteDoesNotReturnCertifiedPageOrChangeOriginalObservation() {
        val f = Fixture()
        val failing = object : CollaborationWorkspaceRows by f.rows {
            override fun commit(values: Map<String, String>) { error("Fixture storage unavailable") }
        }
        val ledger = CollaborationEvidenceLedger(failing)
        assertTrue(runCatching { ledger.readPage(f.reader, f.id, f.hash) }.isFailure)
        assertEquals(1, f.rows.data.size)
        assertEquals("returned", f.source.getString("status"))
        assertFalse(f.accepts())
        f.all()
        assertTrue(f.accepts())
    }

    @Test fun pagesDoNotSplitUnicodeSurrogatePairs() {
        val f = Fixture(0)
        val ref = f.ledger.record(f.author, "unicode", "web_fetch", "{}", JSONObject()
            .put("text", "\uD83D\uDE00".repeat(9_000)).toString(), 1, 2)
        val id = ref.getString("evidence_id")
        val source = f.ledger.read(f.reader, id)!!.toString()
        val low = source.indices.first { it > 0 && Character.isLowSurrogate(source[it]) && Character.isHighSurrogate(source[it - 1]) }
        assertTrue(runCatching { f.ledger.readPage(f.reader, id, offset = low) }.isFailure)
        val output = StringBuilder()
        var offset: Int? = 0
        while (offset != null) {
            val page = f.ledger.readPage(f.reader, id, offset = offset)!!
            assertFalse(Character.isHighSurrogate(page.content.last()))
            assertFalse(Character.isLowSurrogate(page.content.first()))
            output.append(page.content)
            offset = page.next
        }
        assertEquals(source, output.toString())
    }
}
