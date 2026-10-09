package com.galaxyssi.chat

import android.content.Context

internal object CollaborationRecallNativeTool {
    const val ID = "galaxyssi.phone.collaboration.recall"

    fun definitions(context: Context): List<AgentNativeToolDefinition> = listOf(AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(
            id = ID, version = "1.7.0", title = context.getString(R.string.collaboration_recall_title),
            description = context.getString(R.string.collaboration_recall_description) + " " + CollaborationPeerUpdates.INSTRUCTIONS,
            location = AgentNativeToolLocation.PHONE,
            inputSchema = AgentNativeJsonSchema.objectSchema(properties = mapOf(
                "query" to AgentNativeJsonSchema.string(maxLength = 1000),
                "mode" to AgentNativeJsonSchema.string(maxLength = 16),
                "work_id" to AgentNativeJsonSchema.string(maxLength = 160),
                "topic" to AgentNativeJsonSchema.string(maxLength = 32),
                "case_filter" to AgentNativeJsonSchema.string(maxLength = 32),
                "cursor" to AgentNativeJsonSchema.string(maxLength = 512),
                "section" to AgentNativeJsonSchema.string(maxLength = 512),
                "record_id" to AgentNativeJsonSchema.string(maxLength = 64),
                "object_id" to AgentNativeJsonSchema.string(maxLength = 64),
                "evidence_id" to AgentNativeJsonSchema.string(maxLength = 64),
                "sha256" to AgentNativeJsonSchema.string(maxLength = 64),
                "revision" to AgentNativeJsonSchema.integer(minimum = 1),
                "offset" to AgentNativeJsonSchema.integer(minimum = 0)
            ), additionalProperties = false),
            outputSchema = AgentNativeJsonSchema.objectSchema(additionalProperties = true),
            risk = AgentNativeToolRisk.LOW, capabilities = setOf("collaboration.recall"),
            timeoutMillis = 20_000, idempotency = AgentNativeToolIdempotency.IDEMPOTENT),
        executor = AgentNativeToolExecutor { call ->
            if (call.input.containsKey("work_id") && call.input["mode"] != CollaborationCoordinatorUpdates.MODE)
                return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("invalid_arguments", "Work ID is only supported for coordinator updates.")
            if (call.input.containsKey("section") && call.input["mode"] != "goal_contract")
                return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("invalid_arguments", "Section is only supported for goal/context recall.")
            if (call.input.containsKey("topic") && call.input["mode"] != "evolution_rules")
                return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("invalid_arguments", "Topic is only supported for evolution rules.")
            if (call.input.containsKey("case_filter") && call.input["mode"] != CollaborationNumericFeedback.MODE)
                return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("invalid_arguments", "Case filter is only supported for numeric feedback.")
            val group = call.context.conversationId
            if (group.isBlank() || call.context.turnId.isBlank() || CollaborationGroupStore(context).load(group) == null)
                return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("group_unavailable", "No group is authorized for this call.")
            val archive = CollaborationResearchArchive(context, group)
            if (call.input["mode"] in setOf("evidence", "workspace", "goal_contract", "archive", "evolution", "capabilities", "method_history", "evolution_rules", "problems", CollaborationNumericFeedback.MODE, CollaborationCoordinatorUpdates.MODE, CollaborationPeerUpdates.MODE)) {
                val source = call.context.collaborationSourceMessageId
                if (source == null && call.input["mode"] in setOf("goal_contract", "archive", "capabilities", "method_history", CollaborationNumericFeedback.MODE, CollaborationCoordinatorUpdates.MODE, CollaborationPeerUpdates.MODE))
                    return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("dispatch_unavailable", "Goal contract recall requires an exact member binding.")
                val access = if (source != null) CollaborationEvidenceLedger(context).binding(source, group, call.context.turnId)
                    ?: return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("dispatch_unavailable", "No exact member binding.")
                else EncryptedAgentTeamExecutionStore(context).workspaceReadAccess(group, call.context.turnId)
                return@AgentNativeToolExecutor try { CollaborationScopedRecall.read(context, call.input, access) }
                catch (_: IllegalArgumentException) { AgentNativeToolExecutionResult.failure("invalid_cursor", "Invalid recall cursor.") }
            }
            val beforeRound = EncryptedAgentTeamExecutionStore(context).goalRound(group, call.context.turnId)
            val id = call.input["record_id"] as? String ?: ""
            if (id.isNotBlank()) {
                val record = archive.read(id) ?: return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(
                    "record_not_found", "Record is not in this group.")
                if (!CollaborationResearchArchive.visible(org.json.JSONObject(record.content), call.context.turnId, beforeRound))
                    return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("current_turn_isolated",
                        "Current-turn evidence is shared only through assigned dependencies and directed questions.")
                val offset = (call.input["offset"] as? Number)?.toInt()?.coerceIn(0, record.content.length) ?: 0
                val end = minOf(record.content.length, offset + 8_000)
                AgentNativeToolExecutionResult.success(mapOf("record_id" to id, "content" to record.content.substring(offset, end),
                    "total_characters" to record.content.length, "next_offset" to end.takeIf { it < record.content.length },
                    "trust" to "untrusted_group_evidence"))
            } else if (call.input["mode"] == "browse") {
                val page = try {
                    archive.browse(call.input["cursor"] as? String ?: "", call.context.turnId, beforeRound)
                } catch (_: KnowledgeSourcePageChanged) {
                    return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(
                        "history_changed", "New group records arrived; restart browsing without a cursor.")
                } catch (_: IllegalArgumentException) {
                    return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("invalid_cursor", "Invalid group history cursor.")
                }
                AgentNativeToolExecutionResult.success(mapOf("records" to page.records.map {
                    mapOf("record_id" to it.id, "title" to it.title, "summary" to it.summary,
                        "updated_at" to it.updatedAtMillis, "characters" to it.content.length)
                }, "next_cursor" to page.nextCursor, "total_records" to page.total,
                    "trust" to "untrusted_group_evidence"))
            } else {
                val rows = archive.search(call.input["query"] as? String ?: "", excludeTurn = call.context.turnId, beforeRound = beforeRound)
                AgentNativeToolExecutionResult.success(mapOf("records" to rows.map {
                    mapOf("record_id" to it.id, "title" to it.title, "summary" to it.summary,
                        "updated_at" to it.updatedAtMillis, "characters" to it.content.length)
                }, "coverage" to "ranked_subset_not_all_history",
                    "browse_hint" to "Use mode=browse and next_cursor to inspect the history directory, then read record_id with offset.",
                    "trust" to "untrusted_group_evidence"))
            }
        }
    ))
}
