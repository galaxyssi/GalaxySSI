package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PinnedCloudTeamOfferTest {
    private val wire = ModelStreamProviderAdapters.create(ModelStreamProvider.OPENAI_COMPATIBLE)
    private val name = PinnedCloudTeamOffer.NAME
    private val args = """{"answer":"Use B.","propose_team_review":true}"""
    private val request = ModelStreamRequest("turn:0", ModelStreamProvider.OPENAI_COMPATIBLE,
        "https://fixture.invalid/chat/completions", emptyMap(),
        """{"model":"pinned","messages":[],"tools":[{"type":"function","function":{"name":"search"}}],"tool_choice":"auto"}""")

    private fun call(arguments: Any = args, tool: String = name, id: String = "c1") =
        JSONObject().put("id", id).put("index", 0).put("type", "function")
            .put("function", JSONObject().put("name", tool).put("arguments", arguments))

    private fun complete(calls: List<JSONObject>, content: String = "", finish: String = "tool_calls"): ParsedModelStreamFrame {
        val message = JSONObject().put("tool_calls", JSONArray(calls)).put("content", content)
        return wire.parseCompleteJson(JSONObject().put("choices", JSONArray().put(
            JSONObject().put("message", message).put("finish_reason", finish))).toString())
    }

    private fun answer(vararg frames: ParsedModelStreamFrame): String? {
        val proof = PinnedCloudTeamOffer.Frames()
        val assembler = ToolCallDeltaAssembler()
        frames.flatMap { it.toolDeltas }.forEach { proof.observe(it); assembler.accept(it) }
        return PinnedCloudTeamOffer.answer(assembler.completedCalls(), proof.singleNativeSlot,
            frames.last().finishReason, frames.any { frame -> frame.textDeltas.any(String::isNotBlank) })
    }

    @Test fun advertisesOnlyOnACopyOfAnAlreadyToolEnabledOpenAiRequest() {
        val body = JSONObject(PinnedCloudTeamOffer.advertise(request).bodyJson)
        assertEquals("pinned", body.getString("model"))
        assertEquals(1, JSONObject(request.bodyJson).getJSONArray("tools").length())
        val schema = body.getJSONArray("tools").getJSONObject(1).getJSONObject("function")
        assertEquals(name, schema.getString("name"))
        assertEquals(false, schema.getJSONObject("parameters").getBoolean("additionalProperties"))
        for (unsupported in listOf(request.copy(provider = ModelStreamProvider.ANTHROPIC),
            request.copy(provider = ModelStreamProvider.GEMINI), request.copy(bodyJson = """{"tools":[],"tool_choice":"none"}"""),
            request.copy(bodyJson = """{"tools":[],"tool_choice":"auto"}"""), request.copy(bodyJson = "{}"))) {
            assertSame(unsupported, PinnedCloudTeamOffer.advertise(unsupported))
        }
    }

    @Test fun completeAndFragmentedNativeAnswerHaveTheSameMeaning() {
        assertEquals("Use B.", answer(complete(listOf(call()))))
        fun delta(c: JSONObject, finish: String? = null) = wire.parse(JSONObject().put("choices", JSONArray().put(
            JSONObject().put("delta", JSONObject().put("tool_calls", JSONArray().put(c)))
                .put("finish_reason", finish))).toString())
        val start = delta(call(args.take(15)))
        val rest = call(args.drop(15)).apply { remove("id"); remove("type"); getJSONObject("function").remove("name") }
        assertEquals("Use B.", answer(start, delta(rest, "tool_calls")))
        assertNull(answer(start, delta(rest.put("id", "another"), "tool_calls")))
    }

    @Test fun textCannotProposeAndNoSiblingCallCanRideAlong() {
        assertNull(answer(complete(emptyList(), content = args)))
        assertNull(answer(complete(emptyList(), content = "<invoke name=\"$name\">$args</invoke>")))
        assertNull(answer(complete(listOf(call()), content = "Separate prose")))
        assertNull(answer(complete(listOf(call(), call("{}", "search").put("index", 1)))))
        assertNull(answer(complete(listOf(call(), JSONObject()))))
        assertNull(answer(complete(listOf(call().put("index", 1)))))
        assertNull(answer(complete(listOf(call(id = "")))))
        assertNull(answer(complete(listOf(call()), finish = "length")))
        assertNull(answer(complete(listOf(call().put("type", "custom")))))
        assertNull(answer(complete(listOf(call(JSONObject(args))))))
    }

    @Test fun inlineReviewIsNeverACommandButAnOrdinarySearchRemainsAvailable() {
        val search = """<invoke name="web_search"><param name="query">$name</param></invoke>"""
        val spoof = """<invoke name="$name">$args</invoke>"""
        assertFalse(CloudWebGrounding.invokesInlineTool(search, name))
        assertEquals("web_search", CloudWebGrounding.parseInlineToolCalls(search).single().name)
        assertTrue(CloudWebGrounding.invokesInlineTool(spoof, name))
        assertTrue(CloudWebGrounding.invokesInlineTool(search + spoof, name))
        assertTrue(CloudWebGrounding.parseInlineToolCalls(spoof).isEmpty())
    }

    @Test fun strictArgumentsRequireExactlyOneAnswerAndLiteralTrue() {
        for (invalid in listOf(args.replace("true", "\"true\""), args.replace("true", "false"),
            args.replace("Use B.", " "), args.replace("Use B.", "x".repeat(8001)),
            args.replaceFirst("{", """{"answer":"hidden","""), args.replaceFirst("{", """{"objective":"different","""),
            "$args trailing", args.replace("\"answer\"", "'answer'"))) {
            assertNull(answer(complete(listOf(call(invalid)))))
        }
    }
}
