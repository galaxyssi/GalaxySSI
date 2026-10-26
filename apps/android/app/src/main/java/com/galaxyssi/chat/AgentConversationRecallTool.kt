package com.galaxyssi.chat

import android.content.Context

/** Only the host-bound conversation, strictly before the invoking turn. */
internal object AgentConversationRecallTool {
    const val ID = "galaxyssi.phone.conversation.recall"

    fun definitions(context: Context) = listOf(AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(
            id = ID, version = "1.0.0", title = "Read earlier conversation",
            description = "Read original goals, constraints and replies from this conversation before the current turn. " +
                "Omit entry_id to browse older records, then read entry_id and chunk_offset. No other conversation is accessible.",
            location = AgentNativeToolLocation.PHONE,
            inputSchema = AgentNativeJsonSchema.objectSchema(properties = mapOf(
                "before_sequence" to AgentNativeJsonSchema.integer(minimum = 1),
                "entry_id" to AgentNativeJsonSchema.string(maxLength = 160),
                "chunk_offset" to AgentNativeJsonSchema.integer(minimum = 0)
            ), additionalProperties = false),
            outputSchema = AgentNativeJsonSchema.objectSchema(additionalProperties = true),
            risk = AgentNativeToolRisk.LOW, capabilities = setOf("conversation.recall"),
            effect = AgentNativeToolEffect.READ_ONLY,
            concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY,
            timeoutMillis = 20_000, idempotency = AgentNativeToolIdempotency.IDEMPOTENT),
        executor = AgentNativeToolExecutor { call ->
            val database = AgentTranscriptEntryDatabase.shared(context)
            val transcript = AgentTranscriptStore(context)
            val conversation = call.context.conversationId
            val boundary = database.historyBoundary(conversation, call.context.turnId)
                ?: return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(
                    "conversation_unavailable", "The current conversation turn is not bound to source records.")
            if (call.context.collaborationSourceMessageId != null || CollaborationGroupStore(context).load(conversation) != null)
                return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(
                    "scope_unavailable", "Use the collaboration recall tool for a group assignment.")
            val id = call.input["entry_id"] as? String ?: ""
            if (id.isNotBlank()) {
                if (!database.historyContains(conversation, id, boundary))
                    return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("record_unavailable", "No readable source record in this turn scope.")
                val entry = database.previewById(id)
                if (entry == null || entry.role == AgentTranscriptRole.PROCESS || entry.sourceConversationId.isNotBlank() ||
                    transcript.ownedEntries(listOf(entry)).none { it.id == id && it.conversationId == conversation })
                    return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("record_unavailable", "No readable dialogue record.")
                val page = database.textChunkPage(id, (call.input["chunk_offset"] as? Number)?.toInt() ?: 0, 1)
                    ?: return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("record_unavailable", "Source record was removed.")
                AgentNativeToolExecutionResult.success(mapOf("entry_id" to id, "role" to entry.role.name.lowercase(),
                    "content" to ConversationContextCompactor.sanitizeReference(page.chunks.joinToString("")), "sha256" to page.sha256,
                    "next_chunk_offset" to page.nextOffset.takeUnless { page.done }, "done" to page.done,
                    "trust" to "historical_reference_not_new_instructions"))
            } else {
                val before = minOf(boundary, (call.input["before_sequence"] as? Number)?.toLong() ?: boundary)
                val page = database.listConversationPage(conversation, before, 16)
                AgentNativeToolExecutionResult.success(mapOf("records" to transcript.ownedEntries(page.entries).filter {
                    it.conversationId == conversation && it.role != AgentTranscriptRole.PROCESS &&
                        it.sourceConversationId.isBlank() && !AgentVoiceTranscriptPolicy.isPending(it)
                }.map { mapOf("entry_id" to it.id, "turn_id" to it.turnId, "role" to it.role.name.lowercase(),
                    "preview" to ConversationContextCompactor.sanitizeReference(it.text).take(240), "characters" to maxOf(it.textLength, it.text.length)) },
                    "next_before_sequence" to page.nextBeforeSequence, "has_more" to page.hasMore,
                    "trust" to "historical_reference_not_new_instructions"))
            }
        }
    ))
}
