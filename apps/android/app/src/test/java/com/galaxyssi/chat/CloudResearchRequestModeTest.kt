package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.toList
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer

class CloudResearchRequestModeTest {
    private fun request(provider: ModelStreamProvider, endpoint: String = "https://example.org/chat") = ModelStreamRequest(
        "research:round:4", provider, endpoint, mapOf("Authorization" to "test"),
        """{"stream":true,"stream_options":{"include_usage":true},"messages":[{"role":"tool","content":"saved evidence"}],"tools":[{"name":"web_search"}]}"""
    )

    @Test fun completeJsonRetainsEvidenceToolsIdentityAndTimeouts() {
        for (provider in listOf(ModelStreamProvider.OPENAI_COMPATIBLE, ModelStreamProvider.ANTHROPIC)) {
            val input = request(provider)
            val converted = CloudResearchRequestMode.apply(input, false)
            assertEquals(ModelStreamTransport.COMPLETE_JSON, converted.transport)
            assertEquals(input.requestId, converted.requestId)
            assertEquals(input.headers, converted.headers)
            assertEquals(input.readTimeoutMs, converted.readTimeoutMs)
            val json = JSONObject(converted.bodyJson)
            assertFalse(json.getBoolean("stream"))
            assertFalse(json.has("stream_options"))
            assertEquals("saved evidence", json.getJSONArray("messages").getJSONObject(0).getString("content"))
            assertTrue(json.has("tools"))
            assertTrue(JSONObject(input.bodyJson).getBoolean("stream"))
        }
    }

    @Test fun geminiChangesOperationButPreservesKeyAndOtherQueryParameters() {
        val converted = CloudResearchRequestMode.apply(request(ModelStreamProvider.GEMINI,
            "https://example.org/v1/models/test:streamGenerateContent?alt=sse&key=abc%2B123&custom=yes"), false)
        assertTrue(converted.endpoint.contains(":generateContent"))
        assertFalse(converted.endpoint.contains("alt="))
        assertTrue(converted.endpoint.contains("key=abc%2B123"))
        assertTrue(converted.endpoint.contains("custom=yes"))
        assertFalse(JSONObject(converted.bodyJson).has("stream"))
    }

    @Test fun streamingIsUnchanged() {
        val request = request(ModelStreamProvider.OPENAI_COMPATIBLE)
        assertSame(request, CloudResearchRequestMode.apply(request, true))
    }

    @Test fun allCompleteJsonProvidersRetainExecutableToolCalls() = runBlocking {
        val replies = mapOf(
            ModelStreamProvider.OPENAI_COMPATIBLE to """{"choices":[{"message":{"tool_calls":[{"id":"call-1","type":"function","function":{"name":"web_search","arguments":"{\"query\":\"primary record\"}"}}]},"finish_reason":"tool_calls"}]}""",
            ModelStreamProvider.ANTHROPIC to """{"content":[{"type":"tool_use","id":"call-1","name":"web_search","input":{"query":"primary record"}}],"stop_reason":"tool_use"}""",
            ModelStreamProvider.GEMINI to """{"candidates":[{"content":{"parts":[{"functionCall":{"name":"web_search","args":{"query":"primary record"}}}]},"finishReason":"STOP"}]}"""
        )
        MockWebServer().use { server ->
            server.start()
            for ((provider, response) in replies) {
                server.enqueue(MockResponse().setHeader("Content-Type", "application/json").setBody(response))
                val wire = CloudResearchRequestMode.apply(request(provider, server.url("/chat").toString()), false)
                val events = OkHttpCloudModelStreamClient(onTiming = {}).stream(wire).toList()
                assertFalse(events.any { it is ModelStreamEvent.Failed })
                assertEquals(1, events.count { it is ModelStreamEvent.Completed })
                val assembler = ToolCallDeltaAssembler()
                events.filterIsInstance<ModelStreamEvent.ToolCallDelta>().forEach { assembler.accept(it.payload) }
                val call = assembler.completedCalls().single()
                assertEquals("web_search", call.name)
                assertEquals("primary record", JSONObject(call.argumentsJson).getString("query"))
                assertEquals("application/json", server.takeRequest().getHeader("Accept"))
            }
        }
    }
}
