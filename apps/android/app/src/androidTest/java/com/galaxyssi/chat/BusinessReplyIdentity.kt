package com.galaxyssi.chat

import org.json.JSONObject

/** Follow a hydrated final row only when its business result is unchanged. */
internal fun resolveBusinessReply(
    entries: List<AgentTranscriptEntry>, reference: AgentTranscriptEntry,
    workspace: AgentWorkspace? = null
): AgentTranscriptEntry? {
    if (reference.conversationId.isBlank() || reference.turnId.isBlank()) return null
    val expected = AgentRichContentCodec.decode(reference.richOutputJson)
    return entries.lastOrNull { candidate ->
        candidate.role == AgentTranscriptRole.ASSISTANT &&
            !AgentTranscriptRenderPolicy.isLiveStream(candidate) &&
            !candidate.dedupeKey.startsWith("remote-approval:") &&
            candidate.conversationId == reference.conversationId &&
            candidate.turnId == reference.turnId &&
            (candidate.taskId == reference.taskId || (workspace != null &&
                workspace.status == AgentWorkspaceStatus.COMPLETED &&
                workspace.workspaceId == reference.turnId && workspace.taskId == reference.turnId &&
                workspace.conversationId == reference.conversationId && candidate.taskId.isNotBlank() &&
                candidate.dedupeKey == AgentFinalResponseIdentity.dedupeKey(reference.turnId) &&
                (ConversationHubAgentStatusPolicy.hasDeliveredReply(workspace, candidate) ||
                    completedConnectorSnapshotMatches(workspace, reference, candidate)))) &&
            candidate.text == reference.text &&
            (candidate.richOutputJson == reference.richOutputJson || run {
                val actual = AgentRichContentCodec.decode(candidate.richOutputJson)
                expected.isNotEmpty() && actual.size == expected.size && expected.zip(actual).all { (a, b) ->
                    if (a.type !in setOf(AgentRichBlockType.IMAGE, AgentRichBlockType.FILE)) a == b
                    else {
                        val hash = a.metadata["sha256"].orEmpty().lowercase()
                        hash.matches(Regex("[0-9a-f]{64}")) && hash == b.metadata["sha256"].orEmpty().lowercase() &&
                            a.id == b.id && a.type == b.type && a.mimeType == b.mimeType &&
                            a.title == b.title && a.text == b.text &&
                            listOf("artifact_id", "task_id", "desktop_id", "client_route_id").all {
                                a.metadata[it].orEmpty() == b.metadata[it].orEmpty()
                            }
                    }
                }
            })
    }
}

/** Connector receipt resumes the parent loop after the remote reply's original timestamp. */
private fun completedConnectorSnapshotMatches(
    workspace: AgentWorkspace, reference: AgentTranscriptEntry, candidate: AgentTranscriptEntry
): Boolean = runCatching {
    if (workspace.cancellationRequested || candidate.timestampMillis < workspace.createdAtMillis ||
        reference.taskId.isBlank() || workspace.remoteRunId != reference.taskId) return false
    val result = JSONObject(workspace.resultJson)
    val metadata = result.getJSONObject("metadata")
    val loop = result.getJSONObject("execution_loop")
    val completedAt = loop.getLong("updated_at")
    result.getString("phase") == AgentPhase.COMPLETED.name &&
        result.getString("message") == candidate.text &&
        metadata.getString("remote_task_id") == reference.taskId &&
        metadata.getString("task_id") == candidate.taskId &&
        metadata.getString("conversation_id") == reference.conversationId &&
        metadata.getString("turn_id") == reference.turnId &&
        loop.getString("task_id") == reference.turnId &&
        loop.getString("phase") == AgentExecutionLoopPhase.COMPLETED.name &&
        completedAt >= candidate.timestampMillis &&
        workspace.eventJournal.none {
            it.kind == AgentTaskEventKinds.RESUMED && it.timestampMillis > completedAt
        }
}.getOrDefault(false)
