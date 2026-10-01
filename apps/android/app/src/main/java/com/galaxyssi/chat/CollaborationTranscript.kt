package com.galaxyssi.chat

import android.content.Context
import java.util.UUID
import org.json.JSONObject

internal data class CollaborationTranscriptMetadata(
    val memberId: String,
    val name: String,
    val provider: String,
    val role: String,
    val status: AgentSubagentStatus,
    val runId: String,
    val result: Boolean = false,
    val waiting: Boolean = false,
    val primary: Boolean = false
) {
    fun encode(): String = JSONObject().put("member_id", memberId).put("name", name)
        .put("provider", provider).put("role", role).put("status", status.name)
        .put("run_id", runId).put("result", result).put("waiting", waiting)
        .put("primary", primary).toString()

    companion object {
        fun decode(raw: String): CollaborationTranscriptMetadata? {
            if (raw.isBlank()) return null
            return runCatching {
                val json = JSONObject(raw)
                CollaborationTranscriptMetadata(json.getString("member_id"), json.getString("name"),
                    json.getString("provider"), json.getString("role"),
                    AgentSubagentStatus.valueOf(json.getString("status")), json.getString("run_id"),
                    json.optBoolean("result"), json.optBoolean("waiting"), json.optBoolean("primary"))
            }.getOrNull()
        }
    }
}

internal object CollaborationPeerResultPolicy {
    fun messages(snapshot: AgentTeamExecutionSnapshot): List<AgentTeamMessageEnvelope> {
        if (snapshot.state.isTerminal) return emptyList()
        return snapshot.members.filter { it.collaborationGroupId == snapshot.conversationId &&
            it.status == AgentSubagentStatus.SUCCEEDED && it.output.isNotBlank() }.flatMap { sender ->
            snapshot.members.filter { recipient ->
                recipient.collaborationGroupId == snapshot.conversationId && recipient.receivePeerResults &&
                    recipient.memberId != sender.memberId && recipient.memberId != snapshot.primaryMemberId &&
                    recipient.canReceiveTeamMessage(snapshot.state)
            }.map { recipient ->
                AgentTeamMessageEnvelope(
                    messageId = UUID.nameUUIDFromBytes(
                        "${snapshot.supervisorRunId}:${sender.memberId}:${recipient.memberId}:result:${UUID.nameUUIDFromBytes(sender.output.toByteArray())}".toByteArray()
                    ).toString(),
                    teamId = snapshot.teamId, conversationId = snapshot.conversationId,
                    supervisorRunId = snapshot.supervisorRunId, fromInstanceId = sender.memberId,
                    toInstanceId = recipient.memberId, kind = AgentTeamMessageKind.RESULT,
                    text = sender.output, createdAtMillis = sender.completedAtMillis
                )
            }
        }
    }
}

/** Public member events remain PROCESS records so they cannot acknowledge the parent task. */
internal class CollaborationTranscriptPublisher(context: Context) {
    private val transcript by lazy { AgentTranscriptStore(context.applicationContext) }
    private val groups = CollaborationGroupStore(context.applicationContext)
    private val published = linkedMapOf<String, Pair<String, String>>()

    @Synchronized
    fun publish(snapshot: AgentTeamExecutionSnapshot) {
        if (snapshot.conversationId.isBlank()) return
        if (snapshot.members.none { it.collaborationGroupId == snapshot.conversationId } ||
            groups.load(snapshot.conversationId) == null) return
        snapshot.members.filter { it.collaborationGroupId == snapshot.conversationId }.forEach { member ->
            val status = if (snapshot.state == AgentTeamExecutionState.INTERRUPTED && !member.status.isTerminal)
                AgentSubagentStatus.FAILED else member.status
            val metadata = CollaborationTranscriptMetadata(member.memberId, member.displayName,
                member.providerLabel, member.role, status, snapshot.supervisorRunId,
                waiting = member.waitingForDependencies, primary = member.memberId == snapshot.primaryMemberId)
            val key = "collaboration:${snapshot.supervisorRunId}:${member.memberId}"
            write(snapshot, "$key:status", member.role.ifBlank { member.displayName },
                snapshot.createdAtMillis, metadata)
            if (member.status == AgentSubagentStatus.SUCCEEDED && member.output.isNotBlank()) {
                // A content-addressed result is append-only; a correction never replaces previous evidence.
                val revision = UUID.nameUUIDFromBytes(member.output.toByteArray()).toString()
                write(snapshot, "$key:result:$revision", member.output,
                    member.completedAtMillis.coerceAtLeast(snapshot.createdAtMillis), metadata.copy(result = true, waiting = false))
            }
        }
    }

    private fun write(snapshot: AgentTeamExecutionSnapshot, key: String, text: String, timestamp: Long,
        metadata: CollaborationTranscriptMetadata) {
        val json = metadata.encode()
        val fingerprint = UUID.nameUUIDFromBytes(text.toByteArray()).toString() to json
        if (published[key] == fingerprint) return
        transcript.upsert(AgentTranscriptRole.PROCESS, text, dedupeKey = key, timestampMillis = timestamp,
            conversationId = snapshot.conversationId, taskId = snapshot.taskId, collaborationJson = json)
        published[key] = fingerprint
        while (published.size > 4096) published.remove(published.keys.first())
    }
}
