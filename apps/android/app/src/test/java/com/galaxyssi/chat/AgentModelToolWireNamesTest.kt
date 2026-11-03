package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentModelToolWireNamesTest {
    @Test fun escapingDistinguishesNativeSeparatorsAndIsStableAcrossThousandIds() {
        assertEquals("phone__browser__open", AgentModelToolWireNames.name("phone.browser.open"))
        assertNotEquals(AgentModelToolWireNames.name("a.b"), AgentModelToolWireNames.name("a_b"))
        assertNotEquals(AgentModelToolWireNames.name("a_b"), AgentModelToolWireNames.name("a_ub"))
        val ids = (0 until 1_000).map { index ->
            "phone" + listOf(".", "_", "-")[index % 3] + "a".repeat(index % 90 + 1) + ".tool$index"
        }
        val names = ids.map(AgentModelToolWireNames::name)
        assertEquals(ids.size, names.toSet().size)
        assertEquals(names, ids.map(AgentModelToolWireNames::name))
        assertTrue(names.all { SAFE_NAME.matches(it) })
    }

    @Test fun longIdsUseDistinctBoundedNamesWithoutChangingNativeContracts() {
        val ids = listOf("phone." + "a".repeat(90) + ".read", "phone." + "a".repeat(90) + ".write")
        val catalog = ids.map(::descriptor)
        val before = catalog.map { AgentNativeJsonCodec.stringify(it.catalogValue()) }
        assertNotEquals(AgentModelToolWireNames.name(ids[0]), AgentModelToolWireNames.name(ids[1]))
        for (provider in AgentModelToolProvider.entries) {
            val tools = AgentModelToolProtocolAdapters.forProvider(provider).encodeToolCatalog(catalog)
            assertEquals(ids.map(AgentModelToolWireNames::name), declarationNames(provider, tools))
            assertTrue(declarationNames(provider, tools).all { SAFE_NAME.matches(it) })
        }
        assertEquals(before, catalog.map { AgentNativeJsonCodec.stringify(it.catalogValue()) })
    }

    @Test fun aliasResponsesResolveToOriginalNativeIdentityAndArgumentsForEveryProvider() {
        val id = "phone.browser.open"
        val arguments = JSONObject().put("tool_id", "phone.browser.inspect").put("name", "untrusted.value")
        for (provider in AgentModelToolProvider.entries) {
            val adapter = AgentModelToolProtocolAdapters.forProvider(provider)
            for (name in listOf(id, AgentModelToolWireNames.name(id))) {
                val call = adapter.decodeResponse(response(provider, name, arguments), listOf(descriptor(id))).toolCalls.single()
                assertEquals(id, call.toolId)
                assertEquals("1.2.3", call.toolVersion)
                assertEquals("original-call", call.callId)
                assertEquals("phone.browser.inspect", call.arguments["tool_id"])
                assertEquals("untrusted.value", call.arguments["name"])
            }
        }
    }

    @Test fun historicalCallsAndGeminiResponsesUseSameAliasWithoutRewritingEvidence() {
        val id = "phone.browser.inspect"
        val alias = AgentModelToolWireNames.name(id)
        val call = AgentModelToolCall("original-call", id, mapOf("tool_id" to id, "name" to "page.name"))
        val result = AgentModelToolResultContent("original-call", id, "succeeded", mapOf("name" to "page.name"))
        val history = listOf(AgentModelMessage(AgentModelMessageRole.ASSISTANT, toolCalls = listOf(call)),
            AgentModelMessage(AgentModelMessageRole.TOOL, toolResult = result))
        for (provider in AgentModelToolProvider.entries) {
            val body = AgentModelToolProtocolAdapters.forProvider(provider).encodeConversation(history)
            val function: JSONObject
            val evidence: JSONObject
            when (provider) {
                AgentModelToolProvider.OPENAI_COMPATIBLE -> {
                    val messages = body.getJSONArray("messages")
                    function = messages.getJSONObject(0).getJSONArray("tool_calls").getJSONObject(0).getJSONObject("function")
                    assertEquals(id, JSONObject(function.getString("arguments")).getString("tool_id"))
                    assertEquals("original-call", messages.getJSONObject(1).getString("tool_call_id"))
                    evidence = JSONObject(messages.getJSONObject(1).getString("content"))
                }
                AgentModelToolProvider.ANTHROPIC -> {
                    val messages = body.getJSONArray("messages")
                    function = messages.getJSONObject(0).getJSONArray("content").getJSONObject(0)
                    assertEquals(id, function.getJSONObject("input").getString("tool_id"))
                    val block = messages.getJSONObject(1).getJSONArray("content").getJSONObject(0)
                    assertEquals("original-call", block.getString("tool_use_id"))
                    evidence = JSONObject(block.getString("content"))
                }
                AgentModelToolProvider.GEMINI -> {
                    val contents = body.getJSONArray("contents")
                    function = contents.getJSONObject(0).getJSONArray("parts").getJSONObject(0).getJSONObject("functionCall")
                    assertEquals(id, function.getJSONObject("args").getString("tool_id"))
                    val reply = contents.getJSONObject(1).getJSONArray("parts").getJSONObject(0).getJSONObject("functionResponse")
                    assertEquals(alias, reply.getString("name"))
                    assertEquals("original-call", reply.getString("id"))
                    evidence = reply.getJSONObject("response")
                }
            }
            assertEquals(alias, function.getString("name"))
            assertEquals(id, evidence.getString("tool_id"))
            assertEquals("page.name", evidence.getJSONObject("output").getString("name"))
        }
        assertEquals(id, history[0].toolCalls.single().toolId)
        assertEquals(id, history[1].toolResult?.toolId)
    }

    @Test fun undisclosedAliasesAndCanonicalIdsRemainUnavailable() {
        for (provider in AgentModelToolProvider.entries) {
            val adapter = AgentModelToolProtocolAdapters.forProvider(provider)
            for (name in listOf("phone.hidden.read", AgentModelToolWireNames.name("phone.hidden.read"))) {
                expectError("unknown_tool") {
                    adapter.decodeResponse(response(provider, name, JSONObject()), listOf(descriptor("phone.visible.read")))
                }
            }
        }
    }

    @Test fun ambiguousCanonicalFallbackIsRejectedRegardlessOfCatalogOrder() {
        val longId = "phone." + "a".repeat(90) + ".read"
        for (ids in listOf(listOf("a_b", "a_ub"), listOf(longId, AgentModelToolWireNames.name(longId)))) {
            for (ordered in listOf(ids, ids.reversed())) {
                for (provider in AgentModelToolProvider.entries) {
                    expectError("ambiguous_tool_name") {
                        AgentModelToolProtocolAdapters.forProvider(provider).encodeToolCatalog(ordered.map(::descriptor))
                    }
                }
            }
        }
    }

    @Test fun malformedHistoricalNativeIdsProduceProtocolErrors() {
        for (provider in AgentModelToolProvider.entries) {
            val adapter = AgentModelToolProtocolAdapters.forProvider(provider)
            expectError("malformed_tool_call") {
                adapter.encodeConversation(listOf(AgentModelMessage(AgentModelMessageRole.ASSISTANT,
                    toolCalls = listOf(AgentModelToolCall("call", "bad name")))))
            }
        }
    }

    private fun descriptor(id: String) = AgentNativeToolDescriptor(id, "1.2.3", "Public tool", "Public contract",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW)

    private fun declarationNames(provider: AgentModelToolProvider, tools: JSONArray): List<String> {
        val array = if (provider == AgentModelToolProvider.GEMINI) tools.getJSONObject(0).getJSONArray("functionDeclarations") else tools
        return (0 until array.length()).map { index ->
            val item = array.getJSONObject(index)
            (if (provider == AgentModelToolProvider.OPENAI_COMPATIBLE) item.getJSONObject("function") else item).getString("name")
        }
    }

    private fun response(provider: AgentModelToolProvider, name: String, args: JSONObject): String {
        val body = when (provider) {
            AgentModelToolProvider.OPENAI_COMPATIBLE -> {
                val call = JSONObject().put("id", "original-call").put("type", "function")
                    .put("function", JSONObject().put("name", name).put("arguments", args.toString()))
                val message = JSONObject().put("tool_calls", JSONArray().put(call))
                JSONObject().put("choices", JSONArray().put(JSONObject().put("message", message)))
            }
            AgentModelToolProvider.ANTHROPIC -> {
                val call = JSONObject().put("type", "tool_use").put("id", "original-call").put("name", name).put("input", args)
                JSONObject().put("content", JSONArray().put(call))
            }
            AgentModelToolProvider.GEMINI -> {
                val call = JSONObject().put("id", "original-call").put("name", name).put("args", args)
                val content = JSONObject().put("parts", JSONArray().put(JSONObject().put("functionCall", call)))
                JSONObject().put("candidates", JSONArray().put(JSONObject().put("content", content)))
            }
        }
        return body.toString()
    }

    private fun expectError(code: String, action: () -> Unit) {
        try { action(); fail("Expected $code") }
        catch (error: AgentModelToolProtocolException) { assertEquals(code, error.code) }
    }

    private companion object { val SAFE_NAME = Regex("[a-zA-Z0-9_-]{1,64}") }
}
