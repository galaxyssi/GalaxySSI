package com.galaxyssi.chat

import android.content.Context
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject

data class AgentInitialPlanningReference(val sessionId: String, val conversationId: String,
    val turnId: String, val inputSha256: String) {
    internal fun scope() = AgentModelLoopScope(sessionId, conversationId, turnId, turnId,
        AgentWorkspaceScope.id(conversationId, sessionId), "phone-planner", "initial-planning-intent")
    internal fun toJson() = JSONObject().put("session", sessionId).put("conversation", conversationId)
        .put("turn", turnId).put("sha256", inputSha256)
    companion object {
        internal fun fromJson(json: JSONObject) = AgentInitialPlanningReference(json.getString("session"),
            json.getString("conversation"), json.getString("turn"), json.getString("sha256"))
    }
}

internal data class AgentInitialPlanningInput(val goal: String, val conversation: AgentConversationContext,
    val turnId: String, val members: List<AgentRequestedMember>, val mode: AgentTaskExecutionMode,
    val planner: AgentPlannerRecoverySpec)

/** The session root holds only a reference; full planning input lives in encrypted bounded records. */
internal class AgentInitialPlanningJournal(context: Context,
    private val journal: AgentModelLoopJournal = EncryptedAgentModelLoopJournal(context)) {
    private val codec = SharedPreferencesAgentSessionStore(context, "initial-planning-codec")

    fun <T> begin(sessionId: String, input: AgentInitialPlanningInput,
        block: (AgentInitialPlanningReference) -> T): T {
        val encoded = encode(input)
        val reference = AgentInitialPlanningReference(sessionId, input.conversation.conversationId,
            input.turnId, AgentNativeJsonCodec.sha256(encoded))
        require(sessionId.isNotBlank() && reference.conversationId.isNotBlank() && reference.turnId.isNotBlank())
        return runBlocking { journal.withLease(reference.scope()) {
            it.write("initial", encoded)
            block(reference)
        } }
    }

    fun <T> restore(reference: AgentInitialPlanningReference, block: (AgentInitialPlanningInput) -> T): T = runBlocking {
        journal.withLease(reference.scope()) { records ->
            val encoded = records.read("initial") ?: throw AgentModelLoopRecoveryException("initial_planning_input_missing")
            if (AgentNativeJsonCodec.sha256(encoded) != reference.inputSha256) {
                throw AgentModelLoopRecoveryException("initial_planning_input_changed")
            }
            val input = decode(encoded)
            if (input.turnId != reference.turnId || input.conversation.conversationId != reference.conversationId) {
                throw AgentModelLoopRecoveryException("initial_planning_scope_changed")
            }
            block(input)
        }
    }

    private fun encode(input: AgentInitialPlanningInput): String = JSONObject()
        .put("schema", 1).put("goal", input.goal).put("turn", input.turnId).put("mode", input.mode.name)
        .put("planner", JSONObject().put("kind", input.planner.kind.name)
            .put("configuration", input.planner.configurationSha256)
            .put("action", input.planner.action?.let(codec::encodeExecutableAction)))
        .put("members", JSONArray().apply { input.members.forEach { put(JSONObject().put("id", it.agentId)
            .put("name", it.displayName).put("occurrence", it.occurrence).put("role", it.roleHint)) } })
        .put("conversation", JSONObject().put("id", input.conversation.conversationId)
            .put("summary", input.conversation.summary).put("private", input.conversation.privateMode)
            .put("global", input.conversation.globalContext).put("tracking_paused", input.conversation.trackingPaused)
            .put("turns", JSONArray().apply { input.conversation.turns.forEach { put(encodeEntry(it)) } })).toString()

    private fun decode(encoded: String): AgentInitialPlanningInput = try {
        val json = JSONObject(encoded)
        require(json.getInt("schema") == 1)
        val conversation = json.getJSONObject("conversation")
        val planner = json.getJSONObject("planner")
        AgentInitialPlanningInput(json.getString("goal"), AgentConversationContext(conversation.getString("id"),
            conversation.getString("summary"), conversation.getJSONArray("turns").objects().map(::decodeEntry),
            conversation.getBoolean("private"), conversation.getString("global"), conversation.getBoolean("tracking_paused")),
            json.getString("turn"), json.getJSONArray("members").objects().map {
                AgentRequestedMember(it.getString("id"), it.getString("name"), it.getInt("occurrence"), it.getString("role"))
            }, AgentTaskExecutionMode.valueOf(json.getString("mode")),
            AgentPlannerRecoverySpec(AgentPlannerRecoveryKind.valueOf(planner.getString("kind")),
                planner.optJSONObject("action")?.let(codec::decodeAction), planner.getString("configuration")))
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
}
