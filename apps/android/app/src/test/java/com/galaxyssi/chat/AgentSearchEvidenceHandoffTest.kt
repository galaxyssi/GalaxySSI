package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentSearchEvidenceHandoffTest {
    private fun evidence(index: Int) = JSONObject()
        .put("protocol", "galaxyssi.web-intelligence.v1")
        .put("query", "camera-$index")
        .put("status", "completed")
        .put("cache", JSONObject().put("diagnostics", "noise".repeat(4_000)))
        .put("evidence_pack", JSONObject().put("items", JSONArray().put(JSONObject()
            .put("title", "Camera $index").put("url", "https://example.org/source/$index")
            .put("media_evidence_level", "discovered_url_not_visually_verified")
            .put("excerpt", "Evidence ".repeat(300))
            .put("images", JSONArray().put(JSONObject().put("url", "https://example.org/photo/$index.jpg"))))))
        .put("metadata", JSONObject().put("health", "noise".repeat(4_000))).toString()

    @Test fun allFourParallelResultsRetainSourcesAndImages() {
        val sources = (1..4).map { index ->
            AgentAction("step$index", AgentActionKind.CALL_NATIVE_TOOL, "Search", AgentRisk.LOW,
                AgentActionStatus.COMPLETED, "Search", evidence = evidence(index))
        }
        val reviewer = AgentAction("review", AgentActionKind.CALL_CONNECTOR, "Model", AgentRisk.LOW,
            AgentActionStatus.PROPOSED, "Review", mapOf("prompt" to "Review.",
                "use_outputs_from" to sources.joinToString(",") { it.id }))
        val plan = AgentPlan("Find cameras", ScreenContext(foregroundApp = "Test", pageTitle = "Search"),
            emptyList(), sources + reviewer)
        val prompt = plan.materializeToolInput(reviewer, true).parameters.getValue("prompt")
        for (index in 1..4) {
            assertTrue(prompt.contains("[step$index]"))
            assertTrue(prompt.contains("https://example.org/photo/$index.jpg"))
            assertTrue(prompt.contains("https://example.org/source/$index"))
        }
        assertFalse(prompt.contains("noise"))
        assertTrue(prompt.length < 12_100)
    }

    @Test fun compactionReturnsWholeJsonNotRawSlices() {
        val text = requireNotNull(AgentWebObservation.compact(evidence(1), 1_000))
        val root = JSONObject(text)
        assertTrue(text.length <= 1_000)
        assertTrue(root.getBoolean("truncated"))
        assertTrue(root.getJSONObject("evidence_pack").getJSONArray("items")
            .getJSONObject(0).getJSONArray("images").getJSONObject(0).getString("url").endsWith(".jpg"))
    }

    @Test fun repeatedCompactionRetainsImageEvidenceInItsFinalBudget() {
        val first = requireNotNull(AgentWebObservation.compact(evidence(4), 2_000))
        val second = requireNotNull(AgentPlannerObservation.sanitize(first, 650))
        val root = JSONObject(second)
        assertTrue(second.length <= 650)
        val item = root.getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0)
        assertEquals("https://example.org/source/4", item.getString("url"))
        assertEquals("https://example.org/photo/4.jpg", item.getJSONArray("images").getJSONObject(0).getString("url"))
    }

    @Test fun unrelatedSearchPageDoesNotCountAsEvidence() {
        fun hit(title: String, excerpt: String = "") = AgentWebIntelligenceRawResult(
            engineId = "bing", rank = 1, title = title, url = "https://example.org/page", excerpt = excerpt)
        assertTrue(AgentSearchResponseQuality.disjoint("EARIN A-3 earbuds", listOf(hit("Office document guide"))))
        assertFalse(AgentSearchResponseQuality.disjoint("EARIN A-3 earbuds", listOf(hit("EARIN product"))))
        assertFalse(AgentSearchResponseQuality.disjoint("car", listOf(hit("Automobile guide"))))
    }

    @Test fun nativeHistoryAndPersistencePreserveSearchEvidenceBeforePlannerCompression() {
        val result = AgentActionResult("search", true, "Search completed", mapOf("native_tool_output" to evidence(2)))
        val recorded = AgentNativeActionObservation.evidence(result, 12_000)
        val saved = AgentSessionPersistencePolicy.compactActionText(recorded)
        val recovered = AgentRecoveryObservationEvidence.compactOriginEvidence(saved, 1_024)
        listOf(recorded, saved, recovered).forEach { JSONObject(it) }
        val action = AgentAction("search", AgentActionKind.CALL_NATIVE_TOOL, "Search", AgentRisk.LOW,
            AgentActionStatus.COMPLETED, "Search", result = result.message, evidence = recovered)
        val observation = requireNotNull(AgentPlannerObservation.from(action, 650))
        val item = JSONObject(observation).getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0)
        assertEquals("https://example.org/photo/2.jpg", item.getJSONArray("images").getJSONObject(0).getString("url"))
        assertEquals("discovered_url_not_visually_verified", item.getString("media_evidence_level"))
    }

    @Test fun failureEventIsAnOutcomeButProgressIsNot() {
        val event = JSONObject().put("type", "agent_task_event").put("source_message_id", "77")
            .put("contact_id", "codex").put("conversation_id", "conversation")
            .put("turn_id", "turn").put("task_id", "task").put("task_status", "timed_out")
            .put("execution_generation", 2).put("status_seq", 9)
        val response = requireNotNull(AgentRemoteOutcomeCodec.terminalFailureEvent(event, "Codex task stalled"))
        assertTrue(response.remoteFailure)
        assertFalse(response.success)
        assertEquals(2L, response.executionGeneration)
        assertNull(AgentRemoteOutcomeCodec.terminalFailureEvent(event.put("task_status", "running"), "progress"))
        assertNull(AgentRemoteOutcomeCodec.terminalFailureEvent(event.put("task_status", "completed"), ""))
    }
}
