package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentProviderContinuationTest {
    private val descriptor = AgentNativeToolDescriptor("test.continue", "1.0.0", "Test", "Test",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW)
    private val wire = AgentModelToolWireNames.name(descriptor.id)

    @Test fun allProvidersRoundTripOpaqueStateWithoutExposingItAsAssistantText() {
        for (provider in AgentModelToolProvider.entries) {
            val adapter = AgentModelToolProtocolAdapters.forProvider(provider)
            val response = adapter.decodeResponse(response(provider), listOf(descriptor))
            assertEquals("Visible answer", response.assistantText)
            assertNotNull(response.continuation)
            assertFalse(response.toString().contains("opaque-fixture"))
            val message = history(response)
            val body = adapter.encodeConversation(listOf(message, result(response.toolCalls.single())))
            assertTrue(expectedPayload(provider).similar(assistantPayload(provider, body)))
            assertEquals(descriptor.id, message.toolCalls.single().toolId)
        }
    }

    @Test fun geminiPreservesPartOrderAndOnlyTheOriginalParallelSignaturePlacement() {
        val provider = AgentModelToolProvider.GEMINI
        val payload = expectedPayload(provider)
        payload.getJSONArray("parts").put(JSONObject().put("functionCall", JSONObject()
            .put("id", "second").put("name", wire).put("args", JSONObject().put("operation", "inspect"))))
        val adapter = AgentModelToolProtocolAdapters.forProvider(provider)
        val decoded = adapter.decodeResponse(envelope(provider, payload), listOf(descriptor))
        val encoded = adapter.encodeConversation(listOf(history(decoded)) + decoded.toolCalls.map(::result))
        assertTrue(payload.similar(assistantPayload(provider, encoded)))
        assertFalse(assistantPayload(provider, encoded).getJSONArray("parts").getJSONObject(3).has("thoughtSignature"))
    }

    @Test fun geminiDoesNotInventAProviderCallIdForSignedHistoryOrItsResult() {
        val provider = AgentModelToolProvider.GEMINI
        val payload = expectedPayload(provider)
        payload.getJSONArray("parts").getJSONObject(2).getJSONObject("functionCall").remove("id")
        val adapter = AgentModelToolProtocolAdapters.forProvider(provider)
        val decoded = adapter.decodeResponse(envelope(provider, payload), listOf(descriptor))
        assertTrue(decoded.toolCalls.single().callId.startsWith("gemini_call_"))
        val encoded = adapter.encodeConversation(listOf(history(decoded), result(decoded.toolCalls.single())))
        assertTrue(payload.similar(assistantPayload(provider, encoded)))
        assertFalse(encoded.getJSONArray("contents").getJSONObject(1).getJSONArray("parts").getJSONObject(0)
            .getJSONObject("functionResponse").has("id"))
    }

    @Test fun journalRestoresContinuationAndCommittedEffectsWithoutReexecution() = runBlocking {
        for (provider in AgentModelToolProvider.entries) {
            val adapter = AgentModelToolProtocolAdapters.forProvider(provider)
            val journal = InMemoryAgentModelLoopJournal()
            var executions = 0
            val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(descriptor, AgentNativeToolExecutor {
                executions++
                AgentNativeToolExecutionResult.success(mapOf("observed" to true))
            }))
            val request = request(provider.name)
            try {
                AgentModelToolLoop(AgentModelAdapter {
                    if (it.round == 2) throw CancellationException("Public interruption")
                    adapter.decodeResponse(response(provider), listOf(descriptor))
                }, registry, journal = journal).run(request)
                fail("Expected interruption")
            } catch (_: CancellationException) { }
            val restored = AgentModelToolLoop(AgentModelAdapter {
                assertEquals(2, it.round)
                val message = it.messages.single { message -> message.continuation != null }
                assertTrue(expectedPayload(provider).similar(assistantPayload(provider,
                    adapter.encodeConversation(listOf(message)))))
                AgentModelResponse("Verified existing operation")
            }, registry, journal = journal).run(request)
            assertEquals(AgentModelToolLoopStatus.COMPLETED, restored.status)
            assertEquals(1, executions)
        }
    }

    @Test fun duplicateAdmissionIdsDoNotModifySignedProviderHistoryOrRepeatExecution() = runBlocking {
        for (provider in AgentModelToolProvider.entries) {
            val adapter = AgentModelToolProtocolAdapters.forProvider(provider)
            var executions = 0
            val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(descriptor, AgentNativeToolExecutor {
                executions++; AgentNativeToolExecutionResult.success(mapOf("observed" to true))
            }))
            val outcome = AgentModelToolLoop(AgentModelAdapter {
                if (it.round <= 2) adapter.decodeResponse(response(provider), listOf(descriptor)) else {
                    val rejection = it.messages.last().toolResult!!
                    assertEquals("tool_call_id_reused", rejection.error?.code)
                    assertNotEquals("original-call", rejection.callId)
                    val lastAssistant = it.messages.last { message -> message.role == AgentModelMessageRole.ASSISTANT }
                    val encoded = adapter.encodeConversation(listOf(lastAssistant, it.messages.last()))
                    assertTrue(expectedPayload(provider).similar(assistantPayload(provider, encoded)))
                    assertEquals("original-call", resultId(provider, encoded))
                    AgentModelResponse("Verified rejection")
                }
            }, registry).run(request("admission-${provider.name}"))
            assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
            assertEquals(1, executions)
        }
    }

    @Test fun compactionKeepsCurrentSignedChainAndItsOriginalArguments() {
        val adapter = AgentModelToolProtocolAdapters.gemini()
        val first = adapter.decodeResponse(response(AgentModelToolProvider.GEMINI), listOf(descriptor))
        val messages = listOf(AgentModelMessage.user("Complete the original goal")) + (0..6).flatMap { index ->
            val response = first.copy(toolCalls = first.toolCalls.map { it.copy(callId = "call-$index") },
                continuation = first.continuation?.forHistory(first, first.toolCalls.map { it.copy(callId = "call-$index") }))
            listOf(history(response), result(response.toolCalls.single()).copy(toolResult = result(response.toolCalls.single()).toolResult!!
                .copy(output = mapOf("page" to "public-page ".repeat(2_000)))))
        }
        val compacted = AgentModelContextCompactor.compact(messages,
            ConversationContextBudget(4_096, 1_024, triggerRatio = 0.4, targetRatio = 0.3))
        assertEquals(7, compacted.messages.count { it.continuation != null })
        compacted.messages.filter { it.continuation != null }.forEach {
            assertTrue(expectedPayload(AgentModelToolProvider.GEMINI).similar(
                assistantPayload(AgentModelToolProvider.GEMINI, adapter.encodeConversation(listOf(it)))))
        }
        assertTrue(compacted.compactedEstimatedTokens < compacted.originalEstimatedTokens)
    }

    @Test fun foreignRoutesAndProvidersDoNotReceiveOpaqueContinuation() {
        val gemini = AgentModelToolProtocolAdapters.gemini().decodeResponse(response(AgentModelToolProvider.GEMINI), listOf(descriptor))
        val message = history(gemini.copy(continuation = gemini.continuation!!.bindRoute("route-a")))
        assertSame(message, AgentProviderContinuation.forRoute(listOf(message), "route-a").single())
        val changed = AgentProviderContinuation.forRoute(listOf(message), "route-b").single()
        assertNull(changed.continuation)
        assertEquals(message.toolCalls, changed.toolCalls)
        assertFalse(AgentModelToolProtocolAdapters.anthropic().encodeConversation(listOf(message)).toString().contains("opaque-fixture"))
    }

    @Test fun changingSignedArgumentsOrTextIsRejectedBeforeHttpEncoding() {
        val adapter = AgentModelToolProtocolAdapters.gemini()
        val message = history(adapter.decodeResponse(response(AgentModelToolProvider.GEMINI), listOf(descriptor)))
        val altered = listOf(message.copy(text = "Changed"), message.copy(toolCalls = message.toolCalls.map {
            it.copy(arguments = mapOf("operation" to "other")) }))
        for (candidate in altered) {
            try { adapter.encodeConversation(listOf(candidate)); fail("Expected continuation mismatch") }
            catch (error: AgentModelToolProtocolException) { assertEquals("continuation_history_changed", error.code) }
        }
    }

    @Test fun routeFingerprintSeparatesCredentialsAndConfigurationWithoutStoringSecrets() {
        val provider = AgentModelToolProvider.ANTHROPIC
        fun route(endpoint: String = "https://fixture.invalid/messages", model: String = "fixture-model",
            credential: String = "public-fixture-key-a") = AgentProviderContinuation.routeFingerprint(provider, endpoint, model, credential)
        val original = route()
        assertEquals(original, route())
        val response = AgentModelToolProtocolAdapters.anthropic().decodeResponse(response(provider), listOf(descriptor))
        val continuation = response.continuation!!.bindRoute(original)
        val message = history(response.copy(continuation = continuation))
        for (changed in listOf(route(credential = "public-fixture-key-b"), route(model = "other-model"),
            route(endpoint = "https://other.invalid/messages"), AgentProviderContinuation.routeFingerprint(
                AgentModelToolProvider.OPENAI_COMPATIBLE, "https://fixture.invalid/messages", "fixture-model", "public-fixture-key-a"))) {
            assertNotEquals(original, changed)
            assertNull(AgentProviderContinuation.forRoute(listOf(message), changed).single().continuation)
        }
        assertFalse(AgentNativeJsonCodec.stringify(continuation.record()).contains("public-fixture-key"))
    }

    @Test fun continuationStillHonorsCustomToolCallLimits() {
        val provider = AgentModelToolProvider.GEMINI
        val payload = expectedPayload(provider)
        payload.getJSONArray("parts").put(JSONObject().put("functionCall", JSONObject()
            .put("id", "second").put("name", wire).put("args", JSONObject())))
        val decoded = AgentModelToolProtocolAdapters.gemini().decodeResponse(envelope(provider, payload), listOf(descriptor))
        try {
            AgentModelToolProtocolAdapters.gemini(AgentModelToolProtocolLimits(maxToolCalls = 1)).encodeConversation(listOf(history(decoded)))
            fail("Expected call limit")
        } catch (error: AgentModelToolProtocolException) { assertEquals("oversized_tool_call", error.code) }
    }

    private fun request(id: String) = AgentModelToolLoopRequest.forUserMessage("session", "conversation", "turn", "task", "workspace",
        "Verify the original goal", budget = AgentModelToolLoopBudget(maxRetriesPerCall = 0, enforceCountLimits = false)).copy(loopId = id)
    private fun history(response: AgentModelResponse) = AgentModelMessage(AgentModelMessageRole.ASSISTANT,
        response.assistantText, response.toolCalls, continuation = response.continuation)
    private fun result(call: AgentModelToolCall) = AgentModelMessage(AgentModelMessageRole.TOOL,
        toolResult = AgentModelToolResultContent(call.callId, call.toolId, "succeeded", mapOf("observed" to true)))
    private fun response(provider: AgentModelToolProvider) = envelope(provider, expectedPayload(provider))
    private fun envelope(provider: AgentModelToolProvider, payload: JSONObject): String = when (provider) {
        AgentModelToolProvider.OPENAI_COMPATIBLE -> JSONObject().put("choices", JSONArray().put(JSONObject().put("message", payload)))
        AgentModelToolProvider.ANTHROPIC -> JSONObject().put("content", payload.getJSONArray("content"))
        AgentModelToolProvider.GEMINI -> JSONObject().put("candidates", JSONArray().put(JSONObject().put("content", payload)))
    }.toString()

    private fun expectedPayload(provider: AgentModelToolProvider): JSONObject {
        val args = JSONObject().put("operation", "inspect")
        return when (provider) {
            AgentModelToolProvider.OPENAI_COMPATIBLE -> JSONObject().put("role", "assistant").put("content", "Visible answer")
                .put("reasoning_content", "opaque-fixture").put("tool_calls", JSONArray().put(JSONObject().put("id", "original-call")
                    .put("type", "function").put("function", JSONObject().put("name", wire).put("arguments", args.toString()))))
            AgentModelToolProvider.ANTHROPIC -> JSONObject().put("role", "assistant").put("content", JSONArray()
                .put(JSONObject().put("type", "thinking").put("thinking", "opaque-fixture").put("signature", "signed-fixture"))
                .put(JSONObject().put("type", "redacted_thinking").put("data", "opaque-fixture"))
                .put(JSONObject().put("type", "text").put("text", "Visible answer"))
                .put(JSONObject().put("type", "tool_use").put("id", "original-call").put("name", wire).put("input", args)))
            AgentModelToolProvider.GEMINI -> JSONObject().put("role", "model").put("parts", JSONArray()
                .put(JSONObject().put("thought", true).put("text", "opaque-fixture").put("thoughtSignature", "signed-thought"))
                .put(JSONObject().put("text", "Visible answer"))
                .put(JSONObject().put("thoughtSignature", "signed-call").put("functionCall", JSONObject()
                    .put("id", "original-call").put("name", wire).put("args", args))))
        }
    }

    private fun assistantPayload(provider: AgentModelToolProvider, body: JSONObject): JSONObject =
        body.getJSONArray(if (provider == AgentModelToolProvider.GEMINI) "contents" else "messages").getJSONObject(0)
    private fun resultId(provider: AgentModelToolProvider, body: JSONObject): String = when (provider) {
        AgentModelToolProvider.OPENAI_COMPATIBLE -> body.getJSONArray("messages").getJSONObject(1).getString("tool_call_id")
        AgentModelToolProvider.ANTHROPIC -> body.getJSONArray("messages").getJSONObject(1).getJSONArray("content").getJSONObject(0).getString("tool_use_id")
        AgentModelToolProvider.GEMINI -> body.getJSONArray("contents").getJSONObject(1).getJSONArray("parts").getJSONObject(0).getJSONObject("functionResponse").getString("id")
    }
}
