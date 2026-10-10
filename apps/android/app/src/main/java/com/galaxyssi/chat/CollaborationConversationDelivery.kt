package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** A durable intent bridges two local stores. Replays preserve the first write and never certify reading. */
internal class CollaborationConversationDelivery(private val rows: CollaborationWorkspaceRows,
    private val clock: () -> Long = System::currentTimeMillis) {
    fun record(access: CollaborationWorkspaceAccess, target: JSONObject, text: String, now: Long,
               persist: (String, String, Long) -> Unit,
               observe: (CollaborationWorkspaceAccess, String, JSONObject, Long) -> JSONObject): JSONObject {
        val normalized = text.trim()
        require(normalized.isNotEmpty()) { "Interim content is empty" }
        CollaborationReviewContract.validateReference(target)
        val identity = JSONArray(listOf(access.groupId, access.runId, access.turnId, target.getString("object_id"),
            target.getInt("revision"), target.getString("sha256"))).toString()
        val id = hash(identity)
        val key = "group:${hash(access.groupId)}:conversation-delivery:$id"
        val digest = hash(normalized)
        val before = rows.read(key)?.let { encoded ->
            val envelope = JSONObject(encoded)
            val payload = envelope.getString("payload")
            require(hash(payload) == envelope.getString("sha256")) { "Interim delivery journal is corrupt" }
            JSONObject(payload).also {
                require(it.getString("status") in setOf("prepared", "conversation_persisted", "recorded")) {
                    "Unknown interim delivery journal state"
                }
                require(it.getString("identity") == identity && it.getString("content_sha256") == digest) {
                    "An interim delivery cannot change its content or target"
                }
            }
        }
        if (before?.optString("status") == "recorded") return before.getJSONObject("receipt")
        val intent = before ?: JSONObject().put("identity", identity).put("content_sha256", digest)
            .put("status", "prepared").put("at", now).put("round", access.round)
            .put("node", access.nodeId).put("person", access.personId).also { save(key, it) }
        val at = intent.getLong("at")
        val dedupe = "collaboration-delivery:$id"
        if (intent.getString("status") == "prepared") {
            persist(dedupe, normalized, at)
            save(key, intent.put("status", "conversation_persisted").put("confirmed_at", clock().coerceAtLeast(at)))
        }
        val confirmed = intent.getLong("confirmed_at")
        val observation = JSONObject().put("success", true).put("status", "conversation_persisted")
            .put("conversation_id", access.groupId).put("run_id", access.runId).put("turn_id", access.turnId)
            .put("target", JSONObject(target.toString())).put("content_sha256", digest)
            .put("presentation_normalization", "trim_outer_whitespace_only").put("dedupe_key", dedupe)
            .put("requested_at", at).put("persistence_confirmed_at", confirmed)
            .put("user_read", "not_observed").put("remote_acknowledgement", "not_implied")
            .put("goal_acceptance", "not_implied")
        val owner = access.copy(round = intent.getLong("round"), nodeId = intent.getString("node"), personId = intent.getString("person"))
        val evidence = observe(owner, dedupe, observation, confirmed)
        val receipt = JSONObject(observation.toString()).put("observation", evidence)
        save(key, intent.put("status", "recorded").put("receipt", receipt))
        return receipt
    }

    private fun save(key: String, value: JSONObject) {
        val raw = value.toString()
        rows.commit(mapOf(key to JSONObject().put("payload", raw).put("sha256", hash(raw)).toString()))
    }
    private fun hash(value: String) = AgentNativeJsonCodec.sha256(value)

    companion object {
        fun deliver(context: Context, execution: AgentTeamMemberExecutionContext, raw: String): JSONObject {
            val access = CollaborationWorkspaceAccess.from(execution)
            val workspace = CollaborationResearchWorkspace(context)
            val ledger = CollaborationEvidenceLedger(context)
            fun active() {
                require(AgentTeamDurableControl(context).get(access.runId) == AgentTeamUserControl.RUN &&
                    CollaborationGroupStore(context).load(access.groupId)?.members?.any { it.id == access.personId } == true) {
                    "Interim delivery is paused, stopped or no longer authorized"
                }
            }
            active()
            val metadata = CollaborationTranscriptMetadata(access.personId,
                execution.member.context["collaboration_name"].orEmpty(),
                CollaborationLabelPolicy.provider(execution.member.context["collaboration_provider"].orEmpty(),
                    execution.member.context["collaboration_model_id"].orEmpty()), execution.member.role,
                AgentSubagentStatus.SUCCEEDED, access.runId, result = true,
                researchStage = CollaborationResearchStage.DELIVER.name, executionMemberId = access.nodeId)
            return CollaborationGoalAcceptance(workspace, ledger).deliverInterim(access, raw,
                execution.request.context[CollaborationGoalLoop.CRITERIA]?.toString() ?: "[]") { target, saved ->
                active()
                workspace.recordConversationDelivery(access, target, saved.getJSONObject("body").getString("content"),
                    System.currentTimeMillis(), persist = { key, text, at ->
                        active()
                        AgentTranscriptStore(context).persistCollaborationDelivery(access.groupId, execution.request.taskId,
                            access.turnId, key, text, at, metadata.copy(completedAtMillis = at).encode())
                    }, observe = { owner, invocation, observation, at ->
                        ledger.record(owner, invocation, CollaborationInterimDelivery.TOOL, target.toString(),
                            observation.toString(), observation.getLong("requested_at"), at, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
                    })
            }
        }
    }
}
