package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** Authenticated tool activity is bound to a member before dispatch, not inferred from its provider name. */
internal object CollaborationProgressStore {
    private val seenEvents = linkedMapOf<String, Pair<Long, String>>()
    private fun db(context: Context) = AgentEncryptedDatabase(context.applicationContext, "collaboration_progress_bindings")

    fun evidenceWaiting(context: Context, execution: AgentTeamMemberExecutionContext) {
        val request = execution.request
        val source = AgentTeamDispatchIds.sourceMessageId("member:${request.idempotencyKey}")
        val binding = binding(context, source, request.conversationId, request.messageId) ?: return
        write(context, binding, "evidence-transfer", context.getString(R.string.collaboration_evidence_transfer), System.currentTimeMillis())
    }

    fun waiting(context: Context, execution: AgentTeamMemberExecutionContext, prolonged: Boolean) {
        val request = execution.request
        val source = AgentTeamDispatchIds.sourceMessageId("member:${request.idempotencyKey}")
        val binding = binding(context, source, request.conversationId, request.messageId) ?: return
        write(context, binding, "connection-wait", context.getString(if (prolonged)
            R.string.collaboration_waiting_connection_long else R.string.collaboration_waiting_connection),
            System.currentTimeMillis())
    }

    @Synchronized
    fun register(context: Context, execution: AgentTeamMemberExecutionContext) {
        val member = execution.member
        if (member.context["collaboration_group_id"].isNullOrBlank()) return
        val request = execution.request
        val source = AgentTeamDispatchIds.sourceMessageId("member:${request.idempotencyKey}")
        val metadata = CollaborationTranscriptMetadata(member.context[CollaborationResearchWorkflow.PERSON].orEmpty().ifBlank { member.memberId },
            member.context["collaboration_name"].orEmpty(),
            CollaborationLabelPolicy.provider(member.context["collaboration_provider"].orEmpty(),
                member.context["collaboration_model_id"].orEmpty()), member.role,
            AgentSubagentStatus.RUNNING, request.parentRunId, activity = true,
            primary = member.deliveryMode == AgentDeliveryMode.RESPOND,
            researchStage = member.context[CollaborationResearchWorkflow.STAGE].orEmpty(), executionMemberId = member.memberId)
        val binding = JSONObject().put("conversation", request.conversationId).put("turn", request.messageId)
            .put("task", request.taskId).put("metadata", metadata.encode())
        val database = db(context)
        database.writeString(source.toString(), binding.toString())
        val keys = database.keys("")
        if (keys.size > 2048) database.mutateStrings(emptyMap(), database.oldestKeys("", keys.size - 2048))
    }

    private fun binding(context: Context, source: Long, conversation: String, turn: String): JSONObject? {
        if (source <= 0 || conversation.isBlank() || turn.isBlank()) return null
        val value = db(context).readString(source.toString(), "")
        if (value.isBlank()) return null
        return JSONObject(value).takeIf { it.optString("conversation") == conversation && it.optString("turn") == turn &&
            CollaborationGroupStore(context).load(conversation) != null }
    }

    /** Called only behind transport identity and execution-version checks. */
    fun remote(context: Context, source: Long, conversation: String, turn: String, payload: JSONObject): Boolean {
        val binding = binding(context, source, conversation, turn) ?: return false
        val metadata = requireNotNull(CollaborationTranscriptMetadata.decode(binding.getString("metadata")))
        AgentResearchTraceStore.remote(context, conversation, metadata.traceTurnId, payload)
        val events = buildList {
            payload.optJSONArray("events")?.let { array ->
                repeat(minOf(array.length(), 100)) { array.optJSONObject(it)?.let(::add) }
            }
            payload.optJSONObject("progress_event")?.let(::add)
        }
        events.forEach { event ->
            AgentResearchTraceStore.remote(context, conversation, metadata.traceTurnId, event)
            val text = context.connectorProgressText(event)
            if (text.isNotBlank()) write(context, binding, event.optString("event_id").ifBlank {
                AgentNativeJsonCodec.sha256(text)
            }, text, event.optLong("updated_at", event.optLong("created_at", System.currentTimeMillis())))
        }
        return true
    }

    fun cloud(context: Context, source: Long, conversation: String, turn: String, event: CloudToolEvent): Boolean {
        val binding = binding(context, source, conversation, turn) ?: return false
        val metadata = requireNotNull(CollaborationTranscriptMetadata.decode(binding.getString("metadata")))
        if (event.researchTraceJson.isNotBlank()) AgentResearchTraceStore.merge(context, conversation,
            metadata.traceTurnId, AgentResearchTrace.decode(JSONObject(event.researchTraceJson)))
        val text = listOf(event.tool, event.stage, event.detail).filter(String::isNotBlank).joinToString(" · ").take(1800)
        write(context, binding, AgentNativeJsonCodec.sha256(text), text, System.currentTimeMillis())
        return true
    }

    @Synchronized
    private fun write(context: Context, binding: JSONObject, eventId: String, text: String, at: Long) {
        val metadata = requireNotNull(CollaborationTranscriptMetadata.decode(binding.getString("metadata")))
        val key = "${metadata.traceTurnId}:activity:${AgentNativeJsonCodec.sha256(eventId)}"
        val hash = AgentNativeJsonCodec.sha256(text)
        val previous = seenEvents[key]
        if (previous != null && (previous.first > at || previous.second == hash)) return
        AgentTranscriptStore(context).upsert(AgentTranscriptRole.PROCESS, text,
            dedupeKey = key,
            conversationId = binding.getString("conversation"), turnId = binding.getString("turn"),
            taskId = binding.getString("task"), timestampMillis = at, collaborationJson = metadata.encode())
        seenEvents[key] = at to hash
        while (seenEvents.size > 4096) seenEvents.remove(seenEvents.keys.first())
    }
}
