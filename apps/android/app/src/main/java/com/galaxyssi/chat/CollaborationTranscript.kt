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
    val primary: Boolean = false,
    val activity: Boolean = false,
    val summary: String = "",
    val eventCount: Int = 0,
    val details: String = "",
    val researchStage: String = "",
    val executionMemberId: String = memberId,
    val paused: Boolean = false,
    val goalDisposition: String = "",
    val startedAtMillis: Long = 0L,
    val completedAtMillis: Long = 0L,
    val clockStoppedAtMillis: Long = 0L,
    val connectionState: String = ""
) {
    fun encode(): String = JSONObject().put("member_id", memberId).put("name", name)
        .put("provider", provider).put("role", role).put("status", status.name)
        .put("run_id", runId).put("result", result).put("waiting", waiting)
        .put("primary", primary).put("activity", activity).put("summary", summary)
        .put("event_count", eventCount).put("details", details)
        .put("research_stage", researchStage).put("execution_member_id", executionMemberId).put("paused", paused)
        .put("goal_disposition", goalDisposition)
        .put("started_at_millis", startedAtMillis).put("completed_at_millis", completedAtMillis)
        .put("clock_stopped_at_millis", clockStoppedAtMillis).put("connection_state", connectionState).toString()

    val traceTurnId: String get() = "collaboration:$runId:$executionMemberId"

    companion object {
        fun decode(raw: String): CollaborationTranscriptMetadata? {
            if (raw.isBlank()) return null
            return runCatching {
                val json = JSONObject(raw)
                CollaborationTranscriptMetadata(json.getString("member_id"), json.getString("name"),
                    json.getString("provider"), json.getString("role"),
                    AgentSubagentStatus.valueOf(json.getString("status")), json.getString("run_id"),
                    json.optBoolean("result"), json.optBoolean("waiting"), json.optBoolean("primary"),
                    json.optBoolean("activity"), json.optString("summary"), json.optInt("event_count"),
                    json.optString("details"), json.optString("research_stage"),
                    json.optString("execution_member_id").ifBlank { json.getString("member_id") }, json.optBoolean("paused"), json.optString("goal_disposition"),
                    json.optLong("started_at_millis"), json.optLong("completed_at_millis"), json.optLong("clock_stopped_at_millis"),
                    json.optString("connection_state"))
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
    private val appContext = context.applicationContext
    private val transcript by lazy { AgentTranscriptStore(context.applicationContext) }
    private val groups = CollaborationGroupStore(context.applicationContext)
    private val published = linkedMapOf<String, Pair<String, String>>()

    @Synchronized
    fun publish(snapshot: AgentTeamExecutionSnapshot) {
        if (snapshot.conversationId.isBlank()) return
        if (snapshot.members.none { it.collaborationGroupId == snapshot.conversationId } ||
            groups.load(snapshot.conversationId) == null) return
        snapshot.members.filter { it.collaborationGroupId == snapshot.conversationId }.forEach { member ->
            if (member.deliveryMode == AgentDeliveryMode.IGNORE) return@forEach
            if (member.researchStage.isNotBlank() && member.status == AgentSubagentStatus.QUEUED) return@forEach
            val status = member.status
            val recovering = snapshot.state == AgentTeamExecutionState.INTERRUPTED && !member.status.isTerminal
            val metadata = CollaborationTranscriptMetadata(member.personId, member.displayName,
                member.providerLabel, member.role, status, snapshot.supervisorRunId,
                waiting = member.waitingForDependencies, primary = member.memberId == snapshot.primaryMemberId,
                researchStage = member.researchStage, executionMemberId = member.memberId,
                summary = if (recovering) appContext.getString(R.string.collaboration_waiting_connection_long) else "",
                paused = snapshot.paused, goalDisposition = if (member.memberId == snapshot.primaryMemberId) snapshot.goalDisposition else "",
                startedAtMillis = member.executionStartedAtMillis,
                completedAtMillis = member.completedAtMillis,
                clockStoppedAtMillis = if (snapshot.paused || snapshot.state.isTerminal) {
                    snapshot.interruptedAtMillis.takeIf { it > 0L } ?: snapshot.updatedAtMillis
                } else 0L)
            val key = "collaboration:${snapshot.supervisorRunId}:${member.memberId}"
            val assignment = member.role.ifBlank { member.displayName }
            val detail = when {
                member.memberId == snapshot.primaryMemberId && snapshot.goalDisposition == "blocked" &&
                    snapshot.finalOutput == CollaborationGoalLoop.CONTRACT_RECOVERY_REQUIRED -> snapshot.finalOutput
                status == AgentSubagentStatus.FAILED -> member.errorMessage
                else -> ""
            }
            write(snapshot, "$key:status", listOf(assignment, detail).filter(String::isNotBlank).joinToString("\n"),
                snapshot.createdAtMillis, metadata)
            if (member.status == AgentSubagentStatus.SUCCEEDED && member.output.isNotBlank()) {
                // A content-addressed result is append-only; a correction never replaces previous evidence.
                val revision = UUID.nameUUIDFromBytes(member.output.toByteArray()).toString()
                val content = if (member.researchStage.isNotBlank()) {
                    val requests = CollaborationResearchArtifact.decode(member.output)?.optJSONArray("requests")
                    val questions = buildList {
                        repeat(minOf(3, requests?.length() ?: 0)) { index ->
                            val request = requests?.optJSONObject(index) ?: return@repeat
                            val targets = request.optJSONArray("to") ?: return@repeat
                            val names = (0 until minOf(3, targets.length())).mapNotNull { i ->
                                snapshot.members.firstOrNull { it.personId == targets.optString(i) &&
                                    it.personId != member.personId }?.displayName
                            }.distinct().joinToString(" ") { "@$it" }
                            if (names.isNotBlank() && request.optString("question").isNotBlank())
                                add(appContext.getString(R.string.collaboration_directed_question, names,
                                    request.getString("question").take(1200)))
                        }
                    }
                    (listOf(CollaborationResearchArtifact.publicText(member.output)) + questions).joinToString("\n\n")
                } else member.output
                write(snapshot, "$key:result:$revision", content,
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
