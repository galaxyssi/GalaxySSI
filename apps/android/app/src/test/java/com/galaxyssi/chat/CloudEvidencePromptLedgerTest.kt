package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CloudEvidencePromptLedgerTest {
    @Test fun emptySearchDropsRoutingDiagnosticsButRetainsFailures() {
        val raw = JSONObject().put("operation", "search").put("status", "failed")
            .put("receipts", JSONArray().put(JSONObject().put("error_code", "engine_timeout").put("retryable", true)))
            .put("metadata", JSONObject().put("source_health", JSONArray().put("diagnostics"))
                .put("circuits_skipped", JSONArray().put("diagnostics")).put("profile", "fast")).toString()
        val value = JSONObject(CloudEvidencePromptLedger().project(raw))
        assertEquals("failed", value.getString("status"))
        assertEquals("engine_timeout", value.getJSONArray("receipts").getJSONObject(0).getString("error_code"))
        assertFalse(value.getJSONObject("metadata").has("source_health"))
        assertEquals("fast", value.getJSONObject("metadata").getString("profile"))
    }

    @Test fun retrievalTimestampAndJsonOrderingDoNotDuplicateTheSameEvidence() {
        val first = fixture("An unchanged source.")
        val changed = JSONObject(first).apply {
            getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0)
                .put("retrieved_at_millis", 99L)
        }.toString()
        val ledger = CloudEvidencePromptLedger()
        ledger.project(first)
        val item = JSONObject(ledger.project(changed)).getJSONObject("evidence_pack")
            .getJSONArray("items").getJSONObject(0)
        assertEquals("e1", item.getString("evidence_ref"))
        assertEquals(99L, item.getLong("retrieved_at_millis"))
        assertFalse(item.has("excerpt"))
    }

    @Test fun requestWideProjectionRebalancesEarlierResultsWithoutChangingOriginals() {
        val ledger = CloudEvidencePromptLedger("battery benchmark")
        val outputs = (0 until 24).map { index -> fixture(
            "Navigation and unrelated background. ".repeat(100) +
                "\nBattery benchmark measured 42 hours; the previous claim was incorrect.\n" +
                "More unrelated background. ".repeat(100),
            url = "https://source$index.example/report") }
        val before = outputs.toList()
        var projected = emptyList<String>()
        ledger.bind(outputs) { projected = it }
        ledger.refresh()
        val excerpts = projected.map { JSONObject(it).getJSONObject("evidence_pack")
            .getJSONArray("items").getJSONObject(0).getString("excerpt") }
        assertTrue(excerpts.sumOf { it.length } <= 16_000)
        assertTrue(excerpts.all { "42 hours" in it })
        assertEquals(before, outputs)
        val firstPass = projected
        ledger.refresh()
        assertEquals(firstPass, projected)
        assertTrue(projected.sumOf { it.length } < outputs.sumOf { it.length } / 2)
    }

    @Test fun newRevisionsAndPublicationDatesAreNotDeduplicated() {
        val ledger = CloudEvidencePromptLedger()
        val original = fixture("Initial result.")
        ledger.project(original)
        for (field in listOf("content_sha256", "published_at")) {
            val changed = JSONObject(original).apply {
                getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0)
                    .put(field, if (field == "content_sha256") "f".repeat(64) else "2026-09-12")
            }.toString()
            assertTrue(JSONObject(ledger.project(changed)).getJSONObject("evidence_pack")
                .getJSONArray("items").getJSONObject(0).has("excerpt"))
        }
    }

    @Test fun preservesEvidenceAndRemovesOnlyModelSideRedundancy() {
        val original = fixture()
        val ledger = CloudEvidencePromptLedger()
        val first = ledger.project(original)
        val pack = JSONObject(first).getJSONObject("evidence_pack")
        val item = pack.getJSONArray("items").getJSONObject(0)
        assertEquals("https://one.example/report", item.getString("url"))
        assertTrue(item.has("content_sha256"))
        assertTrue(item.has("excerpt"))
        assertFalse(pack.getJSONObject("verification").has("citation_manifest"))
        assertTrue(JSONObject(original).getJSONObject("evidence_pack").getJSONObject("verification").has("citation_manifest"))
        assertTrue(CloudWebGrounding.citationValidation("[source](https://one.example/report)", listOf("web_search" to original)).valid)
        assertTrue(first.length < original.length)
    }

    @Test fun exactEvidenceIsReferencedAcrossToolRoundsWithoutDroppingNewEvidence() {
        val ledger = CloudEvidencePromptLedger()
        val first = ledger.project(fixture())
        val second = ledger.project(fixture())
        val items = JSONObject(second).getJSONObject("evidence_pack").getJSONArray("items")
        assertEquals("e1", items.getJSONObject(0).getString("evidence_ref"))
        assertFalse(items.getJSONObject(0).has("excerpt"))
        val changed = JSONObject(ledger.project(fixture("Changed conclusion and counterexample.")))
            .getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0)
        assertEquals("Changed conclusion and counterexample.", changed.getString("excerpt"))
        assertTrue(second.length < first.length / 2)
        println("evidence_fixture original=${fixture().length} first=${first.length} repeat=${second.length}")
    }

    @Test fun aNewRequestNeverReferencesAnotherRequestsEvidence() {
        val encoded = fixture()
        CloudEvidencePromptLedger().project(encoded)
        val fresh = JSONObject(CloudEvidencePromptLedger().project(encoded)).getJSONObject("evidence_pack")
        assertTrue(fresh.getJSONArray("items").getJSONObject(0).has("excerpt"))
    }

    @Test fun preservesFailedSourceAndConflictingEvidence() {
        val encoded = JSONObject(fixture()).apply {
            getJSONObject("evidence_pack").put("receipts", JSONArray().put(JSONObject()
                .put("status", "failed").put("retryable", false).put("error_code", "verification_required")
                .put("duration_millis", 999)))
        }.toString()
        val result = JSONObject(CloudEvidencePromptLedger().project(encoded)).getJSONObject("evidence_pack")
        val receipt = result.getJSONArray("receipts").getJSONObject(0)
        assertFalse(receipt.getBoolean("retryable"))
        assertEquals("verification_required", receipt.getString("error_code"))
        assertTrue(result.has("conflict_review"))
    }

    @Test fun unstructuredAndErrorToolsRemainIntact() {
        for (value in listOf("plain error", "{\"status\":\"failed\"}")) {
            assertEquals(value, CloudEvidencePromptLedger().project(value))
        }
    }

    @Test fun requestBreakdownSeparatesFixedSchemasFromConversationEvidence() {
        val tools = CloudWebGrounding.openAiTools()
        val messages = JSONArray().put(JSONObject().put("role", "user").put("content", "New question"))
            .put(JSONObject().put("role", "tool").put("content", fixture()))
        val body = JSONObject().put("tools", tools).put("messages", messages)
        val breakdown = CloudRequestSizeBreakdown.measure(body, "messages")
        assertEquals(tools.toString().length, breakdown["tool_schema_chars"])
        assertEquals(messages.toString().length, breakdown["conversation_chars"])
        assertEquals(messages.getJSONObject(1).toString().length, breakdown["tool_result_chars"])
        println("fixed_web_tool_schema_chars=${tools.toString().length} tool_count=${tools.length()}")
    }

    private fun fixture(
        text: String = "A source-backed technical observation. ".repeat(50),
        url: String = "https://one.example/report"
    ): String {
        val pack = AgentWebEvidencePack.build("topic", "completed", listOf(mapOf(
            "url" to url, "title" to "Report", "content" to text,
            "content_sha256" to AgentNativeJsonCodec.sha256(text), "retrieved_at_millis" to 1L
        )), emptyList(), emptyList(), 1L)
        return AgentNativeJsonCodec.stringify(mapOf("status" to "completed", "operation" to "search", "evidence_pack" to pack))
    }
}
