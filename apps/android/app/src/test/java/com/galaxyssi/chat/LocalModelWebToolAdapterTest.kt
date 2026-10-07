package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalModelWebToolAdapterTest {
    @Test
    fun plainConversationAnswerCompletesWithoutHostInjectedToolCall() {
        val response = LocalModelWebToolProtocol.decode("Hello from the local model.", inference())

        assertEquals("Hello from the local model.", response.assistantText)
        assertTrue(response.toolCalls.isEmpty())
    }

    @Test
    fun localModelCanChooseMultipleIndependentWebCalls() {
        val response = LocalModelWebToolProtocol.decode(
            """
            <think>Need independent evidence.</think>
            {
              "answer":"I will compare two sources.",
              "tool_calls":[
                {"id":"search-1","name":"galaxyssi.web.intelligence.search","arguments":{"query":"GalaxySSI release"}},
                {"id":"fetch-1","name":"galaxyssi.web.intelligence.fetch","arguments":{"url":"https://example.com/release"}}
              ]
            }
            """.trimIndent(),
            inference()
        )

        assertEquals(2, response.toolCalls.size)
        assertEquals("galaxyssi.web.intelligence.search", response.toolCalls[0].toolId)
        assertEquals("GalaxySSI release", response.toolCalls[0].arguments["query"])
        assertEquals("https://example.com/release", response.toolCalls[1].arguments["url"])
    }

    @Test
    fun localToolHistoryExposesUnifiedEvidenceForCitationGate() {
        val pack = AgentWebEvidencePack.build(
            query = "fixture",
            status = "completed",
            documents = listOf(
                linkedMapOf(
                    "url" to "https://example.com/report",
                    "title" to "Report",
                    "content" to "Verified body evidence.",
                    "content_sha256" to "a".repeat(64),
                    "retrieved_at_millis" to 1L,
                    "content_type" to "text/html"
                )
            ),
            results = emptyList(),
            receipts = emptyList(),
            generatedAtMillis = 1L
        )
        val messages = listOf(
            AgentModelMessage(
                role = AgentModelMessageRole.TOOL,
                toolResult = AgentModelToolResultContent(
                    callId = "fetch-1",
                    toolId = AgentWebIntelligenceNativeTools.FETCH,
                    status = "completed",
                    output = mapOf("evidence_pack" to pack)
                )
            )
        )

        val encoded = LocalModelWebToolProtocol.encodedEvidence(messages)
        val validation = AgentWebEvidenceVerification.validateAnswer(
            "Supported by [the report](https://example.com/report).",
            encoded
        )
        val fallback = LocalModelWebToolProtocol.verifiedEvidenceFallback(encoded)

        assertTrue(validation.valid)
        assertEquals(1, encoded.size)
        assertTrue(fallback.contains("[Source](https://example.com/report)"))
        assertFalse(fallback.contains("attacker.example"))
    }

    @Test
    fun disclosedLocalCatalogContainsStaticAndDynamicAcquisitionTools() {
        assertTrue(AgentWebIntelligenceNativeTools.SEARCH in LocalModelWebToolProtocol.toolIds)
        assertTrue(AgentWebIntelligenceNativeTools.RESEARCH in LocalModelWebToolProtocol.toolIds)
        assertTrue(AgentWebMediaNativeTools.BROWSER_RENDER in LocalModelWebToolProtocol.toolIds)
        assertTrue(AgentWebMediaNativeTools.WEB_FETCH in LocalModelWebToolProtocol.toolIds)
        assertFalse(AgentWebMediaNativeTools.WEB_DOWNLOAD in LocalModelWebToolProtocol.toolIds)
    }

    @Test
    fun collaborationToolsAreScopedWithoutChangingOrdinaryChat() {
        assertEquals(LocalModelWebToolProtocol.toolIds, LocalModelWebToolProtocol.toolIds(false))
        assertFalse(CollaborationRecallNativeTool.ID in LocalModelWebToolProtocol.toolIds(false))
        assertFalse(CollaborationMilestoneNativeTool.ID in LocalModelWebToolProtocol.toolIds(false))
        assertEquals(setOf(CollaborationRecallNativeTool.ID, CollaborationMilestoneNativeTool.ID),
            LocalModelWebToolProtocol.toolIds(true) - LocalModelWebToolProtocol.toolIds(false))
        assertEquals(setOf(CollaborationRecallNativeTool.ID), LocalModelWebToolProtocol.toolIds(true, repairing = true))
    }

    @Test
    fun nativePublicationUsesTheSameSchema() {
        val schema = AgentNativeJsonSchema(CollaborationMilestoneTool.schema().toNativeObject())
        assertTrue(AgentNativeJsonSchemaValidator.validate(schema, mapOf("mode" to "list")).isValid)
        assertTrue(AgentNativeJsonSchemaValidator.validate(schema, mapOf("mode" to "publish", "milestone_id" to "m1", "artifact" to "{}")).isValid)
        assertFalse(AgentNativeJsonSchemaValidator.validate(schema, mapOf("mode" to "list", "person_id" to "other")).isValid)
        assertFalse(AgentNativeJsonSchemaValidator.validate(schema, mapOf("mode" to "overwrite")).isValid)
    }

    @Test
    fun localProtocolPreservesNestedPublicationAndFinalArtifact() {
        val artifact = org.json.JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
            .put("summary", "A candidate, not a verified result").put("milestones", org.json.JSONArray(listOf("m1"))).toString()
        val raw = org.json.JSONObject().put("answer", "Sharing a candidate").put("tool_calls", org.json.JSONArray()
            .put(org.json.JSONObject().put("id", "publish-1").put("name", CollaborationMilestoneNativeTool.ID)
                .put("arguments", org.json.JSONObject().put("mode", "publish").put("milestone_id", "m1").put("artifact", artifact))))
        val call = LocalModelWebToolProtocol.decode(raw.toString(), inference()).toolCalls.single()
        assertEquals(artifact, call.arguments["artifact"])
        assertEquals(CollaborationMilestoneNativeTool.ID, call.toolId)
        val final = org.json.JSONObject().put("answer", artifact).put("tool_calls", org.json.JSONArray()).toString()
        assertEquals(artifact, LocalModelWebToolProtocol.decode(final, inference()).assistantText)
    }

    @Test
    fun collaborationReceiptsDoNotBecomeVerifiedWebEvidence() {
        val message = AgentModelMessage(role = AgentModelMessageRole.TOOL, toolResult = AgentModelToolResultContent(
            callId = "publish-1", toolId = CollaborationMilestoneNativeTool.ID, status = "succeeded",
            output = mapOf("success" to true, "assignment_completed" to false, "url" to "https://example.com/unverified")))
        assertTrue(LocalModelWebToolProtocol.encodedEvidence(listOf(message)).isEmpty())
        assertFalse(LocalModelWebToolProtocol.systemPrompt(emptyList()).contains(CollaborationMilestoneNativeTool.ID))
    }

    private fun inference() = LocalModelInferenceResult(
        text = "",
        profileId = "test-local",
        backend = "test",
        smeAvailable = false,
        elapsedMillis = 10L,
        promptTokens = 20L,
        generatedTokens = 5L,
        decodeTokensPerSecond = 50.0
    )
}
