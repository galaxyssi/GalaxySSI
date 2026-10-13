package com.galaxyssi.chat

import java.util.Base64
import org.json.JSONObject

/** Incremental, invocation-local index over the canonical history already owned by the loop. */
internal class AgentModelHistoryReader(private val request: AgentModelToolLoopRequest) {
    private data class Entry(val record: Int, val call: AgentModelToolCall?, val result: AgentModelToolResultContent) {
        fun value(): AgentNativeJsonObject = mapOf("record" to record, "arguments" to call?.arguments,
            "observation" to result.toModelJsonValue())
    }
    private val owner = AgentNativeJsonCodec.sha256(listOf(request.sessionId, request.conversationId,
        request.turnId, request.taskId, request.workspaceId, request.callerId, request.loopId,
        request.collaborationSourceMessageId))
    private val messages = mutableListOf<AgentModelMessage>()
    private val calls = mutableMapOf<String, AgentModelToolCall>()
    private val entries = mutableListOf<Entry>()
    private val prefixes = mutableListOf(owner)

    @Synchronized
    fun read(context: AgentNativeToolInvocationContext, input: AgentNativeJsonObject,
        source: List<AgentModelMessage>): AgentNativeToolExecutionResult {
        if (listOf(context.sessionId, context.conversationId, context.turnId, context.callerId,
                context.attributes["task_id"], context.attributes["workspace_id"], context.attributes["model_loop_id"].orEmpty(),
                context.collaborationSourceMessageId) != listOf(request.sessionId, request.conversationId, request.turnId,
                request.callerId, request.taskId, request.workspaceId, request.loopId, request.collaborationSourceMessageId))
            return fail("model_history_owner_changed", "History belongs only to the current task and model loop.")
        if (messages.size > source.size || messages.indices.any { messages[it] !== source[it] }) {
            messages.clear(); calls.clear(); entries.clear(); prefixes.clear(); prefixes += owner
        }
        for (index in messages.size until source.size) {
            val message = source[index]
            message.toolCalls.forEach { calls[it.callId] = it }
            message.toolResult?.takeUnless { it.toolId == AgentModelHistoryTools.ID }?.let { result ->
                val entry = Entry(index, calls[result.callId], result)
                entries += entry
                prefixes += AgentNativeJsonCodec.sha256(listOf(prefixes.last(), entry.value()))
            }
            messages += message
        }
        val record = (input["record"] as? Number)?.toLong()
        return if (record != null) detail(record, input) else page(input)
    }

    private fun page(input: AgentNativeJsonObject): AgentNativeToolExecutionResult {
        if (input.keys.any { it in setOf("path", "offset", "length") })
            return fail("model_history_record_required", "Choose a record from a history page before reading its detail.")
        val tool = input["tool_id"]?.toString().orEmpty()
        val failures = input["failures_only"] == true
        val query = AgentNativeJsonCodec.sha256(listOf(tool, failures))
        val cursor = input["cursor"]?.toString()?.let { encoded ->
            runCatching {
                require(encoded.length <= 1024)
                JSONObject(String(Base64.getUrlDecoder().decode(encoded), Charsets.UTF_8)).also {
                    require(it.getString("owner") == owner && it.getString("query") == query)
                    val end = it.getInt("end")
                    val after = it.getInt("after")
                    require(end in 1..entries.size && after in 0 until end)
                    require(it.getString("prefix") == prefixes[end])
                }
            }.getOrElse { return fail("model_history_cursor_invalid", "Restart history lookup, or reuse its original task and filters.") }
        }
        val end = cursor?.getInt("end") ?: entries.size
        val after = cursor?.getInt("after") ?: -1
        fun matches(entry: Entry) = (tool.isBlank() || entry.result.toolId == tool) &&
            (!failures || entry.result.error != null || entry.result.status in setOf("failed", "rejected", "cancelled", "timeout"))
        if (after >= 0 && !matches(entries[after]))
            return fail("model_history_cursor_invalid", "The cursor does not belong to these filters.")
        val limit = (input["limit"] as? Number)?.toInt()?.coerceIn(1, 20) ?: 10
        val found = (after + 1 until end).asSequence().filter { matches(entries[it]) }.take(limit + 1).toList()
        val selected = found.take(limit)
        val output = flags().apply {
            put("snapshot_observations", end)
            put("entries", selected.map { index -> this@AgentModelHistoryReader.entries[index].let { entry -> mapOf(
                "record" to entry.record, "call_id" to entry.result.callId, "tool_id" to entry.result.toolId,
                "status" to entry.result.status, "invocation_id" to entry.result.invocationId,
                "message_preview" to entry.result.message.take(256),
                "message_truncated" to (entry.result.message.length > 256), "error_code" to entry.result.error?.code) } })
            if (found.size > selected.size) put("next_cursor", Base64.getUrlEncoder().withoutPadding().encodeToString(
                AgentNativeJsonCodec.stringify(mapOf("owner" to owner, "query" to query, "end" to end,
                    "after" to selected.last(), "prefix" to prefixes[end])).toByteArray(Charsets.UTF_8)))
        }
        return AgentNativeToolExecutionResult.success(output, "Historical observations read; no current external state checked")
    }

    private fun detail(record: Long, input: AgentNativeJsonObject): AgentNativeToolExecutionResult {
        if (input.keys.any { it in setOf("cursor", "tool_id", "failures_only", "limit") })
            return fail("model_history_modes_mixed", "Use either a history page or a single record detail.")
        val entry = entries.binarySearchBy(record) { it.record.toLong() }.takeIf { it >= 0 }?.let(entries::get)
            ?: return fail("model_history_record_missing", "The record is not an observation in this loop.")
        val path = input["path"]?.toString().orEmpty()
        val value = runCatching { AgentToolInspectionTools.select(entry.value(), path) }.getOrElse {
            return fail("model_history_path_missing", "Choose an existing JSON Pointer in the historical record.") }
        val text = if (value is String) value else AgentNativeJsonCodec.stringify(value)
        val offset = (input["offset"] as? Number)?.toLong() ?: 0L
        if (offset < 0 || offset > text.length || offset in 1 until text.length.toLong() &&
            text[offset.toInt()].isLowSurrogate() && text[offset.toInt() - 1].isHighSurrogate())
            return fail("model_history_offset_invalid", "Use the exact next_offset returned for this record and path.")
        val start = offset.toInt()
        val length = (input["length"] as? Number)?.toInt()?.coerceIn(2, 8192) ?: 4096
        var end = minOf(text.length.toLong(), offset + length).toInt()
        if (end < text.length && end > start && text[end - 1].isHighSurrogate() && text[end].isLowSurrogate()) end--
        return AgentNativeToolExecutionResult.success(flags().apply {
            put("record", record); put("path", path); put("offset", offset); put("text", text.substring(start, end))
            put("encoding", if (value is String) "text" else "json"); put("total_characters", text.length)
            put("sha256", AgentNativeJsonCodec.sha256(text)); put("truncated", end < text.length)
            if (end < text.length) put("next_offset", end)
        }, "Historical detail read; re-observe external state before deciding on a repeated mutation")
    }

    private fun flags() = linkedMapOf<String, Any?>("historical_only" to true, "external_state_observed" to false,
        "target_executed" to false, "completion_verified" to false)
    private fun fail(code: String, message: String) = AgentModelHistoryTools.failure(code, message)
}
