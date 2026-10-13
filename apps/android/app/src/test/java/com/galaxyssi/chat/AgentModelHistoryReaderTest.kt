package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject

class AgentModelHistoryReaderTest {
    private val request = AgentModelToolLoopRequest("session", "conversation", "turn", "task", "workspace",
        messages = listOf(AgentModelMessage.user("Public history test")), loopId = "history-loop")
    private val context = AgentNativeToolInvocationContext(sessionId = request.sessionId,
        conversationId = request.conversationId, turnId = request.turnId, callerId = request.callerId,
        attributes = mapOf("task_id" to request.taskId, "workspace_id" to request.workspaceId, "model_loop_id" to request.loopId))
    private fun history(count: Int): List<AgentModelMessage> = request.messages + (0 until count).flatMap { index ->
        listOf(AgentModelMessage(AgentModelMessageRole.ASSISTANT, text = "Assistant note $index",
            toolCalls = listOf(AgentModelToolCall("call-$index", "public.read", mapOf("index" to index))),
            providerRoute = "private-route-never-disclosed"),
            AgentModelMessage(AgentModelMessageRole.TOOL, toolResult = AgentModelToolResultContent(
                "call-$index", "public.read", "succeeded", mapOf("body" to "public value $index"),
                invocationId = "invocation-$index"))) }
    private fun rows(result: AgentNativeToolExecutionResult) = result.output["entries"] as List<*>

    @Test fun allObservationsArePagedInOrderAndNewResultsDoNotShiftTheSnapshot() {
        val source = history(53).toMutableList()
        val reader = AgentModelHistoryReader(request)
        var input: AgentNativeJsonObject = mapOf("limit" to 7)
        val records = mutableListOf<Int>()
        do {
            val result = reader.read(context, input, source)
            assertTrue(result.isSuccess)
            assertEquals(53, result.output["snapshot_observations"])
            assertTrue(rows(result).size <= 7)
            records += rows(result).map { (it as Map<*, *>)["record"] as Int }
            if (input["cursor"] == null) source += history(1).last().copy(toolResult =
                history(1).last().toolResult!!.copy(callId = "later", invocationId = "later"))
            input = result.output["next_cursor"]?.let { mapOf("limit" to 7, "cursor" to it) } ?: emptyMap()
        } while (input.isNotEmpty())
        assertEquals((0 until 53).map { 2 + it * 2 }, records)
        assertEquals(54, reader.read(context, emptyMap(), source).output["snapshot_observations"])
    }

    @Test fun reconstructedReaderCanUseTheSameCursorButChangedEvidenceCannot() {
        val source = history(3)
        val cursor = AgentModelHistoryReader(request).read(context, mapOf("limit" to 1), source).output["next_cursor"]
        assertTrue(AgentModelHistoryReader(request).read(context, mapOf("cursor" to cursor), history(3)).isSuccess)
        val changed = source.toMutableList().apply { this[2] = this[2].copy(toolResult = this[2].toolResult!!.copy(message = "changed")) }
        assertEquals("model_history_cursor_invalid", AgentModelHistoryReader(request).read(context, mapOf("cursor" to cursor), changed).error?.code)
    }

    @Test fun detailChunksReassembleLargeUnicodeWithoutTruncatingTheTail() {
        val text = ("\u516c\u5f00\ud83d\ude80" + "e\u0301").repeat(2_000)
        val source = history(1).toMutableList().apply { this[2] = this[2].copy(toolResult = this[2].toolResult!!.copy(
            output = mapOf("body" to text))) }
        val reader = AgentModelHistoryReader(request)
        var offset = 0
        val joined = StringBuilder()
        do {
            val result = reader.read(context, mapOf("record" to 2, "path" to "/observation/output/body", "offset" to offset, "length" to 17), source)
            assertTrue(result.isSuccess)
            assertEquals("text", result.output["encoding"])
            val chunk = result.output["text"] as String
            assertTrue(chunk.length <= 17)
            assertFalse(chunk.first().isLowSurrogate())
            assertFalse(chunk.last().isHighSurrogate())
            joined.append(chunk)
            offset = result.output["next_offset"] as? Int ?: -1
        } while (offset >= 0)
        assertEquals(text, joined.toString())
    }

    @Test fun onlyExactHostScopeCanReadAndCursorsCannotCrossScopesOrFilters() {
        val reader = AgentModelHistoryReader(request)
        val source = history(3)
        for (foreign in listOf(context.copy(sessionId = "foreign"), context.copy(conversationId = "foreign"),
            context.copy(turnId = "foreign"), context.copy(callerId = "foreign"), context.copy(collaborationSourceMessageId = 4),
            context.copy(attributes = context.attributes + ("task_id" to "foreign")),
            context.copy(attributes = context.attributes + ("workspace_id" to "foreign")),
            context.copy(attributes = context.attributes + ("model_loop_id" to "foreign")))) {
            val result = reader.read(foreign, emptyMap(), source)
            assertEquals("model_history_owner_changed", result.error?.code)
            assertTrue(result.output.isEmpty())
        }
        val cursor = reader.read(context, mapOf("limit" to 1), source).output["next_cursor"]
        assertEquals("model_history_cursor_invalid", reader.read(context,
            mapOf("cursor" to cursor, "failures_only" to true), source).error?.code)
        val nextRequest = request.copy(turnId = "next")
        assertEquals("model_history_cursor_invalid", AgentModelHistoryReader(nextRequest).read(context.copy(turnId = "next"),
            mapOf("cursor" to cursor), source).error?.code)
    }

    @Test fun nestedHistoryResultsAndPrivateProviderStateAreNotDisclosed() {
        val initial = history(1).toMutableList()
        val assistant = initial[1]
        initial[1] = assistant.copy(continuation = AgentProviderContinuation.capture(
            AgentModelToolProvider.OPENAI_COMPATIBLE,
            JSONObject().put("reasoning_content", "opaque-provider-private-state"),
            AgentModelResponse(assistant.text, assistant.toolCalls)))
        val source = initial + AgentModelMessage(AgentModelMessageRole.TOOL,
            toolResult = AgentModelToolResultContent("history", AgentModelHistoryTools.ID, "succeeded", mapOf("private" to "nested")))
        val reader = AgentModelHistoryReader(request)
        assertEquals(1, reader.read(context, emptyMap(), source).output["snapshot_observations"])
        val detail = reader.read(context, mapOf("record" to 2), source)
        assertFalse(detail.output.toString().contains("private-route"))
        assertFalse(detail.output.toString().contains("opaque-provider-private-state"))
        assertFalse(detail.output.toString().contains("Assistant note"))
        assertTrue(detail.output.toString().contains("public value"))
        assertEquals(false, detail.output["external_state_observed"])
        assertEquals(false, detail.output["completion_verified"])
        assertEquals("model_history_record_missing", reader.read(context, mapOf("record" to 3), source).error?.code)
    }

    @Test fun failureFiltersIncludeRejectedCallsAndReturnExactErrorDetails() {
        val source = history(2).toMutableList().apply { this[4] = this[4].copy(toolResult = this[4].toolResult!!.copy(
            status = "rejected", error = AgentNativeToolError("public_error", "Inspect actual state", false, mapOf("detail" to "proof")))) }
        val reader = AgentModelHistoryReader(request)
        val page = reader.read(context, mapOf("failures_only" to true, "tool_id" to "public.read"), source)
        assertEquals(1, rows(page).size)
        val detail = reader.read(context, mapOf("record" to 4, "path" to "/observation/error/details/detail"), source)
        assertEquals("proof", detail.output["text"])
        assertTrue(rows(reader.read(context, mapOf("tool_id" to "absent"), source)).isEmpty())
    }

    @Test fun malformedCursorsModesPathsAndOffsetsReturnActionableNonterminalErrors() {
        val reader = AgentModelHistoryReader(request)
        val source = history(2)
        for (cursor in listOf("invalid", "a".repeat(1025), "e30"))
            assertEquals("model_history_cursor_invalid", reader.read(context, mapOf("cursor" to cursor), source).error?.code)
        for ((input, code) in listOf(mapOf("offset" to 1) to "model_history_record_required",
            mapOf("record" to 1) to "model_history_record_missing", mapOf("record" to 2, "limit" to 1) to "model_history_modes_mixed",
            mapOf("record" to 2, "path" to "/missing") to "model_history_path_missing",
            mapOf("record" to 2, "offset" to Long.MAX_VALUE) to "model_history_offset_invalid")) {
            val result = reader.read(context, input, source)
            assertEquals(code, result.error?.code)
            assertEquals(false, result.error?.details?.get("goal_terminal"))
        }
    }

    @Test fun aStandaloneToolCannotAcquireHistoryAndSchemaRejectsForeignSelectors() {
        val registry = AgentNativeToolRegistry().register(AgentModelHistoryTools.definition())
        assertEquals("model_history_not_bound", registry.invoke(AgentModelHistoryTools.ID, emptyMap()).error?.code)
        assertFalse(registry.invoke(AgentModelHistoryTools.ID, mapOf("conversation_id" to "foreign")).isSuccess)
        assertFalse(AgentModelHistoryTools.definition().descriptor.requiresEffectClaim)
    }
}
