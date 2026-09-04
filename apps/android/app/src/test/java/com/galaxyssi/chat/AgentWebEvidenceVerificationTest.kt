package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentWebEvidenceVerificationTest {
    @Test
    fun packRecomputesIntegrityAndFlagsCrossDomainNumericConflict() {
        val pack = AgentWebEvidencePack.build(
            query = "launch facts",
            status = "completed",
            documents = listOf(
                document(
                    "https://alpha.example/report",
                    "The launch year is 2026 and tested capacity is 64 GB.",
                    "a".repeat(64)
                ),
                document(
                    "https://beta.example/report",
                    "The launch year is 2026 and tested capacity is 128 GB.",
                    "b".repeat(64)
                )
            ),
            results = emptyList(),
            receipts = emptyList(),
            generatedAtMillis = 1L
        )

        val verification = pack["verification"] as Map<*, *>
        val review = pack["conflict_review"] as Map<*, *>
        val conflicts = review["potential_conflicts"] as List<*>

        assertEquals("verified", verification["status"])
        assertEquals(2, verification["valid_item_count"])
        assertEquals("potential_conflict", review["status"])
        assertEquals(2, review["independent_retrieved_domain_count"])
        assertEquals(1, conflicts.size)
        assertEquals("current_model_required", review["semantic_resolution"])
    }

    @Test
    fun packMarksIdenticalCrossDomainContentAsCorrelatedNotIndependent() {
        val sharedHash = "c".repeat(64)
        val pack = AgentWebEvidencePack.build(
            query = "correlated evidence",
            status = "completed",
            documents = listOf(
                document("https://one.example/story", "The same syndicated report.", sharedHash),
                document("https://two.example/story", "The same syndicated report.", sharedHash)
            ),
            results = emptyList(),
            receipts = emptyList(),
            generatedAtMillis = 2L
        )

        val review = pack["conflict_review"] as Map<*, *>
        val duplicates = review["duplicate_content_groups"] as List<*>
        val duplicate = duplicates.single() as Map<*, *>

        assertEquals(false, duplicate["independent_evidence"])
        assertEquals(2, (duplicate["urls"] as List<*>).size)
    }

    @Test
    fun finalAnswerMustCiteOnlyVerifiedPackUrls() {
        val pack = AgentWebEvidencePack.build(
            query = "fixture",
            status = "completed",
            documents = listOf(document("https://example.com/report", "Verified evidence.", "d".repeat(64))),
            results = emptyList(),
            receipts = emptyList(),
            generatedAtMillis = 3L
        )
        val encoded = AgentNativeJsonCodec.stringify(mapOf("evidence_pack" to pack))
        val result = listOf("web_research" to encoded)

        val valid = AgentWebEvidenceVerification.validateAnswer(
            "The result is supported by [the report](https://example.com/report).",
            result
        )
        val missing = AgentWebEvidenceVerification.validateAnswer("The result is supported.", result)
        val foreign = AgentWebEvidenceVerification.validateAnswer(
            "See [another page](https://attacker.example/report).",
            result
        )

        assertTrue(valid.valid)
        assertEquals("missing_citations", missing.status)
        assertTrue(missing.requiresRepair)
        assertEquals("foreign_citations", foreign.status)
        assertEquals(listOf("https://attacker.example/report"), foreign.invalidCitationUrls)
        assertTrue(AgentWebEvidenceVerification.repairPrompt(missing, result).contains("https://example.com/report"))
    }

    @Test
    fun tamperedCitationIdFailsPackVerification() {
        val pack = AgentWebEvidencePack.build(
            query = "fixture",
            status = "completed",
            documents = listOf(document("https://example.com/report", "Verified evidence.", "e".repeat(64))),
            results = emptyList(),
            receipts = emptyList(),
            generatedAtMillis = 4L
        ).toMutableMap()
        val item = ((pack["items"] as List<*>).single() as Map<*, *>)
            .entries.associate { it.key.toString() to it.value }.toMutableMap()
        item["citation_id"] = "0".repeat(24)
        pack["items"] = listOf(item)

        val verification = AgentWebEvidenceVerification.verify(pack)

        assertEquals("failed", verification["status"])
        assertEquals(1, verification["invalid_item_count"])
        assertFalse((verification["invalid_items"] as List<*>).isEmpty())
    }

    @Test
    fun citationAndManifestHashesMatchTheDesktopFixture() {
        val pack = AgentWebEvidencePack.build(
            query = "fixture",
            status = "completed",
            documents = listOf(
                document(
                    "https://www.example.com/a?utm_source=x&b=2&a=1",
                    "Fixture evidence",
                    "a".repeat(64)
                )
            ),
            results = emptyList(),
            receipts = emptyList(),
            generatedAtMillis = 1L
        )
        val item = (pack["items"] as List<*>).single() as Map<*, *>
        val verification = pack["verification"] as Map<*, *>

        assertEquals("https://example.com/a?a=1&b=2", item["url"])
        assertEquals("2a6252e1a64266545ebcf887", item["citation_id"])
        assertEquals(
            "e8cab87e170d719115ce193ca893dfdaa5a50e2ec880b07045cf93628f54879a",
            verification["citation_manifest_sha256"]
        )
    }

    private fun document(url: String, content: String, contentHash: String): AgentNativeJsonObject = linkedMapOf(
        "url" to url,
        "title" to "Evidence",
        "content" to content,
        "content_sha256" to contentHash,
        "retrieved_at_millis" to 1L,
        "content_type" to "text/html"
    )
}
