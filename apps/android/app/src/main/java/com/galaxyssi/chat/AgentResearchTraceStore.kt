package com.galaxyssi.chat

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONObject

/** Small encrypted rows, scoped to a conversation and turn; writes never touch model context. */
internal object AgentResearchTraceStore {
    val revision = MutableStateFlow(0L)
    private fun db(context: Context) = AgentEncryptedDatabase(context.applicationContext, "agent_research_traces")
    private fun prefix(conversation: String) = AgentNativeJsonCodec.sha256(conversation) + ":"
    private fun key(conversation: String, turn: String) = prefix(conversation) + AgentNativeJsonCodec.sha256(turn)

    @Synchronized
    fun read(context: Context, conversation: String, turn: String): AgentResearchTrace {
        if (conversation.isBlank() || turn.isBlank()) return AgentResearchTrace()
        return AgentResearchTrace.decode(runCatching { JSONObject(db(context).readString(key(conversation, turn), "{}")) }.getOrNull())
    }

    @Synchronized
    fun merge(context: Context, conversation: String, turn: String, delta: AgentResearchTrace) {
        if (!delta.visible || conversation.isBlank() || turn.isBlank()) return
        val database = db(context)
        if (database.contains(prefix(conversation) + "deleted")) return
        val before = read(context, conversation, turn)
        val after = before.merge(delta)
        if (before == after) return
        database.writeString(key(conversation, turn), after.toJson().toString())
        revision.value++
    }

    fun remote(context: Context, conversation: String, turn: String, event: JSONObject) {
        val trace = event.optJSONObject("research_trace")
            ?: event.optJSONObject("metadata")?.optJSONObject("research_trace") ?: return
        merge(context, conversation, turn, AgentResearchTrace.decode(trace).copy(remote = true))
    }

    @Synchronized
    fun delete(context: Context, conversation: String) {
        val database = db(context)
        database.mutateStrings(mapOf(prefix(conversation) + "deleted" to "true"), database.keys(prefix(conversation)))
        revision.value++
    }

    @Synchronized
    fun clear(context: Context) { db(context).clear(); revision.value++ }
}
