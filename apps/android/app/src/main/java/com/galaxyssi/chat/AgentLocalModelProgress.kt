package com.galaxyssi.chat

import android.content.Context

/** Runs on the local inference worker, persists before notifying UI, and retains no Activity. */
internal object AgentLocalModelProgress {
    fun sink(context: Context, identity: AgentLocalDispatchIdentity, managedTeam: Boolean,
             cancellation: AgentNativeToolCancellationToken,
             catalog: List<AgentNativeToolDescriptor>): AgentModelToolLoopEventSink {
        val app = context.applicationContext
        val titles = catalog.associate { it.id to it.title }
        val transcripts by lazy { AgentTranscriptStore(app) }
        val workspaces by lazy { EncryptedAgentWorkspaceStore(app) }
        return AgentLocalModelProgressFence(identity, cancellation) { event ->
            val projection = AgentModelToolLoopTimelinePolicy.project(event)
            val safeProjection = projection.copy(detail = AgentObservationRedaction.redact(projection.detail))
            val title = titles[projection.toolId].orEmpty().ifBlank {
                projection.toolId.substringAfterLast('.').replace('_', ' ')
                    .ifBlank { app.getString(R.string.agent_model_loop_tool_fallback) }
            }
            val text = app.modelToolTimelineText(safeProjection, event.round, title)
            if (managedTeam) {
                if (text != null) CollaborationProgressStore.local(app, identity, projection.dedupeSuffix,
                    text, event.occurredAtEpochMillis)
            } else if (transcripts.conversation(identity.conversationId) != null) {
                if (text != null) transcripts.upsert(AgentTranscriptRole.PROCESS, text,
                    dedupeKey = "agent-local-loop:${identity.sourceMessageId}:${projection.dedupeSuffix}",
                    conversationId = identity.conversationId, turnId = identity.turnId, taskId = identity.turnId,
                    timestampMillis = event.occurredAtEpochMillis)
                // The UI workspace is keyed by the turn, not the native Agent's transport task id.
                val workspace = workspaces.find(identity.turnId)
                if (workspace?.conversationId == identity.conversationId && workspace.taskId == identity.turnId &&
                    workspace.sessionId == identity.turnId && !workspace.status.isTerminal && !workspace.cancellationRequested) {
                    val supervisor = AgentTaskRuntime.supervisor(app)
                    val stage = "local_model.${event.type.name.lowercase(java.util.Locale.ROOT)}"
                    if (event.type == AgentModelToolLoopEventType.MODEL_REQUESTED) {
                        supervisor.heartbeat(workspace.workspaceId, stage)
                    } else supervisor.progress(workspace.workspaceId, stage)
                }
            }
        }
    }
}
