package com.galaxyssi.chat

import android.content.Context

internal object CollaborationRecallNativeTool {
    const val ID = "galaxyssi.phone.collaboration.recall"

    fun definitions(context: Context): List<AgentNativeToolDefinition> = listOf(AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(
            id = ID, version = "1.0.0", title = context.getString(R.string.collaboration_recall_title),
            description = context.getString(R.string.collaboration_recall_description),
            location = AgentNativeToolLocation.PHONE,
            inputSchema = AgentNativeJsonSchema.objectSchema(properties = mapOf(
                "query" to AgentNativeJsonSchema.string(maxLength = 1000),
                "mode" to AgentNativeJsonSchema.string(maxLength = 16),
                "cursor" to AgentNativeJsonSchema.string(maxLength = 512),
                "record_id" to AgentNativeJsonSchema.string(maxLength = 64),
                "object_id" to AgentNativeJsonSchema.string(maxLength = 64),
                "revision" to AgentNativeJsonSchema.integer(minimum = 1),
                "offset" to AgentNativeJsonSchema.integer(minimum = 0)
            ), additionalProperties = false),
            outputSchema = AgentNativeJsonSchema.objectSchema(additionalProperties = true),
            risk = AgentNativeToolRisk.LOW, capabilities = setOf("collaboration.recall"),
            timeoutMillis = 20_000, idempotency = AgentNativeToolIdempotency.IDEMPOTENT),
        executor = AgentNativeToolExecutor { call ->
            val group = call.context.conversationId
            if (group.isBlank() || call.context.turnId.isBlank() || CollaborationGroupStore(context).load(group) == null)
                return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("group_unavailable", "No group is authorized for this call.")
            val archive = CollaborationResearchArchive(context, group)
            if (call.input["mode"] == "workspace") {
                val workspace = CollaborationResearchWorkspace(context)
                val access = EncryptedAgentTeamExecutionStore(context).workspaceReadAccess(group, call.context.turnId)
                val objectId = call.input["object_id"] as? String ?: ""
                if (objectId.isNotBlank()) {
                    val revision = workspace.read(access, objectId, (call.input["revision"] as? Number)?.toInt() ?: 0)
                        ?: return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(
                            "object_unavailable", "Object revision is missing or isolated from this assignment.")
                    val content = revision.toString()
                    val offset = (call.input["offset"] as? Number)?.toInt()?.coerceIn(0, content.length) ?: 0
                    val end = minOf(content.length, offset + 8_000)
                    return@AgentNativeToolExecutor AgentNativeToolExecutionResult.success(mapOf(
                        "content" to content.substring(offset, end), "total_characters" to content.length,
                        "next_offset" to end.takeIf { it < content.length }, "trust" to "member_reported_not_verified"))
                }
                val page = try { workspace.browse(access, call.input["cursor"] as? String ?: "") }
                catch (_: IllegalArgumentException) { return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(
                    "invalid_cursor", "Invalid workspace cursor.") }
                return@AgentNativeToolExecutor AgentNativeToolExecutionResult.success(mapOf(
                    "revisions" to page.revisions.map { it.toString() }, "next_cursor" to page.next,
                    "trust" to "member_reported_not_verified"))
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
