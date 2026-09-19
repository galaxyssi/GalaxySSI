package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AdaptiveResearchTest {
    private val body = (0 until 240).joinToString("\n") { "Paragraph $it: original evidence and counterevidence. ".repeat(4) }
    private fun document(text: String = body) = AgentWebIntelligenceDocument(
        "https://example.org/paper", "Original paper", text, "text/html", AgentNativeJsonCodec.sha256(text),
        1, Long.MAX_VALUE, emptyList(), emptyMap(), floatArrayOf())

    private fun result(offset: Int, text: String = body) = AgentWebEvidencePack.attach(
        mapOf("operation" to "fetch", "status" to "completed", "documents" to listOf(
            AgentWebReadingWindow.document(document(text), mapOf("offset" to offset, "length" to 8000)))), 2)
    private fun output(offset: Int) = AgentNativeJsonCodec.stringify(result(offset))

    @Test fun longBodyCanBeReadInOrderWithoutDroppingOrRepeatingPassages() {
        var offset = 0
        val collected = StringBuilder()
        do {
            val item = JSONObject(output(offset)).getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0)
            val window = item.getJSONObject("reading_window")
            assertEquals(offset, window.getInt("offset"))
            collected.append(item.getString("excerpt"))
            offset = window.getInt("end_offset")
            assertEquals(body.length, window.getInt("total_chars"))
            assertEquals(offset == body.length, window.isNull("next_offset"))
        } while (offset < body.length)
        assertEquals(body, collected.toString())
    }

    @Test fun deliberateReadingWindowSurvivesPromptProjectionAndBoundedEncoding() {
        val encoded = CloudWebGrounding.boundedModelJson(result(8000))
        val projected = CloudEvidencePromptLedger("counterevidence").project(encoded)
        val item = JSONObject(projected).getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0)
        assertEquals(body.substring(8000, 16000), item.getString("excerpt"))
        assertEquals(8000, item.getJSONObject("reading_window").getInt("offset"))
    }

    @Test fun changedDocumentVersionIsExplicitAndOutOfRangeOffsetIsBounded() {
        val record = AgentWebReadingWindow.document(document("changed"),
            mapOf("offset" to 100_000, "document_sha256" to "old"))
        val window = record["reading_window"] as Map<*, *>
        assertEquals(true, window["version_changed"])
        assertEquals(7, window["offset"])
        assertEquals("not_independently_verified", window["semantic_verification"])
        assertNull(window["next_offset"])
    }

    @Test fun readingWindowDoesNotSplitSupplementaryUnicodeCharacters() {
        val text = "a".repeat(7999) + "\uD83D\uDE00" + "tail"
        val first = JSONObject(AgentNativeJsonCodec.stringify(result(0, text)))
            .getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0)
        assertEquals(7999, first.getJSONObject("reading_window").getInt("next_offset"))
        val second = JSONObject(AgentNativeJsonCodec.stringify(result(7999, text)))
            .getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0)
        assertEquals(text, first.getString("excerpt") + second.getString("excerpt"))
    }

    @Test fun nextPageIsProgressButRepeatingTheSamePageConverges() {
        val progress = CloudWebToolLoopProgress()
        repeat(5) { assertFalse(progress.observeEvidenceBatch(listOf(output(it * 8000)))) }
        assertFalse(progress.observeEvidenceBatch(listOf(output(32000))))
        assertFalse(progress.observeEvidenceBatch(listOf(output(32000))))
        assertTrue(progress.observeEvidenceBatch(listOf(output(32000))))
    }

    @Test fun reserveReadingTimeEvenWhenSearchHasManySubquestions() {
        assertEquals(60_000L, AgentWebReadingWindow.searchAllowance(120_000, 60_000))
        assertEquals(15_000L, AgentWebReadingWindow.searchAllowance(30_000, 60_000))
        assertEquals(1_000L, AgentWebReadingWindow.searchAllowance(2_000, 60_000))
    }

    @Test fun multilingualPlanKeepsPurposeAndSubquestionWithoutInventingQueries() {
        val plan = AgentWebResearchPlanCodec.decode("research", listOf(
            mapOf("query" to "primary record", "subquestion" to "mechanism", "language" to "en"),
            mapOf("query" to "original local record", "subquestion" to "field results", "language" to "zh")))
        assertEquals(listOf("en", "zh"), plan.map { it.language })
        assertEquals("mechanism", plan.first().publicValue()["subquestion"])
        assertEquals(100, AgentWebResearchPlanCodec.decode("research", (1..120).map { "query $it" }).size)
    }

    @Test fun retrievalCoverageDoesNotClaimSemanticVerification() {
        val coverage = CloudResearchCoverage()
        coverage.observe(JSONObject(output(0)))
        assertTrue(coverage.guidance().contains("1/1"))
        assertTrue(coverage.guidance().contains("next_offset=8000"))
        assertTrue(coverage.guidance().contains("not claim verification"))
    }

    @Test fun deepDraftWithSnippetOnlyCitationsRequestsBodyReadingButSimpleLookupDoesNot() {
        val source = """{"evidence_pack":{"items":[{"url":"https://example.org/paper","evidence_level":"discovery_snippet"}]}}"""
        val coverage = CloudResearchCoverage()
        coverage.observe(JSONObject(source))
        val answer = "A finding [paper](https://example.org/paper)"
        assertNull(coverage.readingReview(answer))
        coverage.observe(JSONObject(source).put("operation", "research"))
        assertTrue(coverage.readingReview(answer)!!.contains("Read the decisive original bodies"))
        coverage.observe(JSONObject(output(0)))
        assertNull(coverage.readingReview(answer))
    }
}
