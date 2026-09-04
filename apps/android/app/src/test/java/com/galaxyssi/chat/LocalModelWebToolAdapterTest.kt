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
