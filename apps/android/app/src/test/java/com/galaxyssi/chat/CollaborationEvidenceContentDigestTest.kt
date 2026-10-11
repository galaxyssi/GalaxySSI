package com.galaxyssi.chat

import java.security.MessageDigest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationEvidenceContentDigestTest {
    private val author = CollaborationWorkspaceAccess("group", "run", "turn", 1, "author", "author")
    private val reader = author.copy(round = 2, nodeId = "review", personId = "reviewer")
    private fun bytesHash(content: String) = MessageDigest.getInstance("SHA-256")
        .digest(content.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it.toInt() and 255) }

    @Test fun digestEncodingAndOffsetUnitAreExplicitForEscapesAndUnicode() {
        val rows = CollaborationGoalAcceptanceTest.Rows()
        val source = JSONObject().put("evidence_id", "evidence").put("sha256", "identity")
        val content = "\u8bc1\u636e\n\"quoted\"\\path\r\n\t\uD83D\uDE00"
        val coverage = CollaborationEvidenceReadCoverage.record(rows, "fixture:", reader, source, content, 0, content.length)
        assertEquals("galaxyssi_json_string_utf8_v1", coverage.getString("content_sha256_encoding"))
        assertEquals(AgentNativeJsonCodec.sha256(content), coverage.getString("content_sha256"))
        assertEquals(bytesHash(content), coverage.getString("content_utf8_sha256"))
        assertNotEquals(coverage.getString("content_sha256"), coverage.getString("content_utf8_sha256"))
        assertEquals("complete_evidence_content", coverage.getString("content_digest_scope"))
        assertEquals("utf16_code_units", coverage.getString("offset_unit"))
        assertEquals(content.length, coverage.getInt("total_characters"))
        assertNotEquals(content.toByteArray(Charsets.UTF_8).size, coverage.getInt("total_characters"))
        assertNotEquals(content.codePointCount(0, content.length), coverage.getInt("total_characters"))
    }

    @Test fun everyPageDescribesFullContentDigestWithoutClaimingUnreadPages() {
        val rows = CollaborationGoalAcceptanceTest.Rows()
        val ledger = CollaborationEvidenceLedger(rows)
        val ref = ledger.record(author, "invocation", "tool", "{}", JSONObject()
            .put("text", "\u8bc1\u636e\n\"quoted\"\\\uD83D\uDE00".repeat(1_000)).toString(), 1, 2)
        val id = ref.getString("evidence_id")
        val content = ledger.read(reader, id)!!.toString()
        val completeHash = bytesHash(content)
        val joined = StringBuilder()
        var offset: Int? = 0
        var pages = 0
        while (offset != null) {
            val page = ledger.readPage(reader, id, offset = offset)!!
            assertEquals(completeHash, page.coverage.getString("content_utf8_sha256"))
            assertNotEquals(bytesHash(page.content), completeHash)
            assertEquals(page.next == null, page.coverage.getBoolean("complete"))
            joined.append(page.content)
            offset = page.next
            pages++
        }
        assertTrue(pages > 1)
        assertEquals(content, joined.toString())
        assertEquals(completeHash, bytesHash(joined.toString()))
        val citation = ledger.references(reader, JSONArray().put(ref)).getJSONObject(0)
        CollaborationEvidenceReadCoverage.requireComplete(citation, CollaborationEvidenceReadCoverage.identity(reader), JSONObject(content))
    }

    @Test fun reopenedLegacyCoverageIsNotRewrittenOrInvalidatedByDigestMetadata() {
        val rows = CollaborationGoalAcceptanceTest.Rows()
        val ledger = CollaborationEvidenceLedger(rows)
        val ref = ledger.record(author, "invocation", "tool", "{}", "{\"answer\":42}", 1, 2)
        val id = ref.getString("evidence_id")
        ledger.readPage(reader, id)
        val stored = rows.data.toMap()
        val envelope = JSONObject(stored.entries.single { it.key.contains(":read:") }.value)
        val legacy = JSONObject(envelope.getString("payload"))
        assertFalse(legacy.has("content_utf8_sha256"))
        assertFalse(legacy.has("content_sha256_encoding"))
        val reopened = CollaborationEvidenceLedger(rows)
        val citation = reopened.references(reader, JSONArray().put(ref)).getJSONObject(0)
        val coverage = citation.getJSONObject(CollaborationEvidenceReadCoverage.FIELD)
        val source = reopened.read(reader, id)!!
        assertEquals(bytesHash(source.toString()), coverage.getString("content_utf8_sha256"))
        assertTrue(coverage.getBoolean("complete"))
        listOf("content_utf8_sha256", "content_sha256_encoding", "content_digest_scope", "offset_unit").forEach(coverage::remove)
        CollaborationEvidenceReadCoverage.requireComplete(citation, CollaborationEvidenceReadCoverage.identity(reader), source)
        assertEquals(stored, rows.data)
        coverage.put("content_sha256", "0".repeat(64)).put("content_utf8_sha256", bytesHash(source.toString()))
        assertTrue(runCatching { CollaborationEvidenceReadCoverage.requireComplete(citation,
            CollaborationEvidenceReadCoverage.identity(reader), source) }.isFailure)
    }

    @Test fun fileDigestDoesNotGrantReadCoverageOrAttribution() {
        val rows = CollaborationGoalAcceptanceTest.Rows()
        val ledger = CollaborationEvidenceLedger(rows)
        val ref = ledger.record(author, "invocation", "tool", "{}", "{}", 1, 2)
        val id = ref.getString("evidence_id")
        val notConfirmed = ledger.readPage(reader, id, recordCoverage = false)!!
        assertEquals(bytesHash(notConfirmed.content), notConfirmed.coverage.getString("content_utf8_sha256"))
        assertFalse(notConfirmed.coverage.getBoolean("complete"))
        val unbound = ledger.readPage(reader.copy(nodeId = "", personId = ""), id)!!
        assertEquals("unattributed", unbound.coverage.getString("mode"))
        assertFalse(unbound.coverage.getBoolean("complete"))
        assertEquals(1, rows.data.size)
    }
}
