package com.galaxyssi.chat

import android.content.Context
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject

data class AgentPlanningReference(val sessionId: String, val conversationId: String,
    val turnId: String, val inputSha256: String, val basePlanId: String = "", val baseRevision: Int = 0) {
    val isReplanning: Boolean get() = basePlanId.isNotBlank() && baseRevision > 0
    internal fun scope() = AgentModelLoopScope(sessionId, conversationId, turnId, turnId,
        AgentWorkspaceScope.id(conversationId, sessionId), "phone-planner",
        if (isReplanning) "replanning-intent-${baseRevision + 1}-$inputSha256" else "initial-planning-intent")
    internal fun toJson() = JSONObject().put("session", sessionId).put("conversation", conversationId)
        .put("turn", turnId).put("sha256", inputSha256).put("base_plan", basePlanId).put("base_revision", baseRevision)
    companion object {
        internal fun fromJson(json: JSONObject) = AgentPlanningReference(json.getString("session"),
            json.getString("conversation"), json.getString("turn"), json.getString("sha256"),
            json.optString("base_plan"), json.optInt("base_revision"))
    }
}

internal data class AgentPlanningInput(val goal: String, val conversation: AgentConversationContext,
    val turnId: String, val members: List<AgentRequestedMember>, val mode: AgentTaskExecutionMode,
    val planner: AgentPlannerRecoverySpec, val replan: AgentReplanningIntent? = null)

internal data class AgentReplanningIntent(val planId: String, val revision: Int, val planSha256: String,
    val reason: String) {
    fun toJson() = JSONObject().put("plan", planId).put("revision", revision).put("sha256", planSha256).put("reason", reason)
    companion object {
        fun fromJson(json: JSONObject) = AgentReplanningIntent(json.getString("plan"), json.getInt("revision"),
            json.getString("sha256"), json.getString("reason"))
    }
}

/** The session root holds only a reference; full planning input lives in encrypted bounded records. */
internal class AgentPlanningJournal(context: Context,
    private val journal: AgentModelLoopJournal = EncryptedAgentModelLoopJournal(context)) {
    private val codec = SharedPreferencesAgentSessionStore(context, "initial-planning-codec")

    fun <T> begin(sessionId: String, input: AgentPlanningInput,
        block: (AgentPlanningReference) -> T): T {
        val encoded = encode(input)
        val reference = AgentPlanningReference(sessionId, input.conversation.conversationId,
            input.turnId, AgentNativeJsonCodec.sha256(encoded), input.replan?.planId.orEmpty(), input.replan?.revision ?: 0)
        require(sessionId.isNotBlank() && reference.conversationId.isNotBlank() && reference.turnId.isNotBlank())
        return runBlocking { journal.withLease(reference.scope()) {
            it.write("initial", encoded)
            block(reference)
        } }
    }

    fun <T> restore(reference: AgentPlanningReference, block: (AgentPlanningInput) -> T): T = runBlocking {
        journal.withLease(reference.scope()) { records ->
            val encoded = records.read("initial") ?: throw AgentModelLoopRecoveryException("initial_planning_input_missing")
            if (AgentNativeJsonCodec.sha256(encoded) != reference.inputSha256) {
                throw AgentModelLoopRecoveryException("initial_planning_input_changed")
            }
            val input = decode(encoded)
            if (input.turnId != reference.turnId || input.conversation.conversationId != reference.conversationId ||
                input.replan?.planId.orEmpty() != reference.basePlanId || (input.replan?.revision ?: 0) != reference.baseRevision) {
                throw AgentModelLoopRecoveryException("initial_planning_scope_changed")
            }
            block(input)
        }
    }

    private fun encode(input: AgentPlanningInput): String = JSONObject()
        .put("schema", 1).put("goal", input.goal).put("turn", input.turnId).put("mode", input.mode.name)
        .put("replan", input.replan?.toJson())
        .put("planner", input.planner.toJson(codec))
        .put("members", JSONArray().apply { input.members.forEach { put(JSONObject().put("id", it.agentId)
            .put("name", it.displayName).put("occurrence", it.occurrence).put("role", it.roleHint)) } })
        .put("conversation", JSONObject().put("id", input.conversation.conversationId)
            .put("summary", input.conversation.summary).put("private", input.conversation.privateMode)
            .put("global", input.conversation.globalContext).put("tracking_paused", input.conversation.trackingPaused)
            .put("turns", JSONArray().apply { input.conversation.turns.forEach { put(encodeEntry(it)) } })).toString()

    private fun decode(encoded: String): AgentPlanningInput = try {
        val json = JSONObject(encoded)
        require(json.getInt("schema") == 1)
        val conversation = json.getJSONObject("conversation")
        val planner = json.getJSONObject("planner")
        AgentPlanningInput(json.getString("goal"), AgentConversationContext(conversation.getString("id"),
            conversation.getString("summary"), conversation.getJSONArray("turns").objects().map(::decodeEntry),
            conversation.getBoolean("private"), conversation.getString("global"), conversation.getBoolean("tracking_paused")),
            json.getString("turn"), json.getJSONArray("members").objects().map {
                AgentRequestedMember(it.getString("id"), it.getString("name"), it.getInt("occurrence"), it.getString("role"))
            }, AgentTaskExecutionMode.valueOf(json.getString("mode")),
            decodePlannerRecoverySpec(planner, codec),
            json.optJSONObject("replan")?.let(AgentReplanningIntent::fromJson))
    } catch (error: Exception) { throw AgentModelLoopRecoveryException("initial_planning_input_invalid", error) }

    private fun encodeEntry(e: AgentTranscriptEntry) = JSONObject().put("id", e.id).put("role", e.role.name)
        .put("text", e.text).put("timestamp", e.timestampMillis).put("dedupe", e.dedupeKey)
        .put("conversation", e.conversationId).put("turn", e.turnId).put("task", e.taskId).put("rich", e.richOutputJson)
        .put("source_conversation", e.sourceConversationId).put("source_title", e.sourceConversationTitle)
        .put("source_entry", e.sourceEntryId).put("text_chunks", e.textChunkCount).put("text_length", e.textLength)
        .put("text_sha", e.textSha256).put("rich_chunks", e.richOutputChunkCount).put("rich_length", e.richOutputLength)
        .put("rich_sha", e.richOutputSha256)

    private fun decodeEntry(e: JSONObject) = AgentTranscriptEntry(e.getString("id"),
        AgentTranscriptRole.valueOf(e.getString("role")), e.getString("text"), e.getLong("timestamp"),
        e.getString("dedupe"), e.getString("conversation"), e.getString("turn"), e.getString("task"), e.getString("rich"),
        e.getString("source_conversation"), e.getString("source_title"), e.getString("source_entry"),
        e.getInt("text_chunks"), e.getInt("text_length"), e.getString("text_sha"), e.getInt("rich_chunks"),
        e.getInt("rich_length"), e.getString("rich_sha"))
    private fun JSONArray.objects() = (0 until length()).map(::getJSONObject)

    fun planFingerprint(plan: AgentPlan, goal: String): String {
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        codec.encodeDurableActivePlan(plan, goal).forEach { record ->
            val bytes = (record + "\n").toByteArray(Charsets.UTF_8)
            try { digest.update(bytes) } finally { bytes.fill(0) }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }
}
