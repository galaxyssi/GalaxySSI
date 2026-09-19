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
    fun read(context: Context, conversation: String, turn: String, sourceLimit: Int = 50): AgentResearchTrace {
        if (conversation.isBlank() || turn.isBlank()) return AgentResearchTrace()
        val database = db(context)
        val recordKey = key(conversation, turn)
        val trace = AgentResearchTrace.decode(runCatching { JSONObject(database.readString(recordKey, "{}")) }.getOrNull())
        val sourcePrefix = "$recordKey:source:"
        val count = database.countKeys(sourcePrefix)
        if (count == 0) return trace
        val sources = mutableListOf<AgentResearchTrace.Source>()
        var after = ""
        val limit = sourceLimit.coerceIn(1, 20_000)
        while (sources.size < limit) {
            val keys = database.keysAfter(sourcePrefix, after, minOf(256, limit - sources.size))
            if (keys.isEmpty()) break
            keys.forEach { sourceKey ->
                val row = JSONObject(database.readString(sourceKey, "{}"))
                sources += AgentResearchTrace.Source(row.getString("url"), row.optString("title"), row.optString("status", "discovered"))
            }
            after = keys.last()
        }
        return trace.copy(sources = sources, totalSourceCount = count)
    }

    @Synchronized
    fun merge(context: Context, conversation: String, turn: String, delta: AgentResearchTrace) {
        if (!delta.visible || conversation.isBlank() || turn.isBlank()) return
        val database = db(context)
        if (database.contains(prefix(conversation) + "deleted")) return
        val recordKey = key(conversation, turn)
        val before = AgentResearchTrace.decode(JSONObject(database.readString(recordKey, "{}")))
        val after = before.merge(delta.copy(sources = emptyList())).copy(sources = emptyList())
        val writes = linkedMapOf<String, String>()
        // One encrypted row per URL: retain large investigations without rewriting a giant JSON blob.
        var count = database.countKeys("$recordKey:source:")
        var truncated = after.truncated
        (before.sources + delta.sources).forEach { source ->
            val url = AgentResearchTrace.safeUrl(source.url) ?: return@forEach
            val sourceKey = "$recordKey:source:${AgentNativeJsonCodec.sha256(url)}"
            val existing = writes[sourceKey] ?: database.readString(sourceKey, "")
            if (existing.isEmpty() && count >= 20_000) { truncated = true; return@forEach }
            val prior = existing.takeIf(String::isNotEmpty)?.let { row -> JSONObject(row).let {
                AgentResearchTrace.Source(it.getString("url"), it.optString("title"), it.optString("status", "discovered"))
            } }
            val merged = AgentResearchTrace(sources = listOfNotNull(prior)).merge(AgentResearchTrace(sources = listOf(source))).sources.single()
            val encoded = JSONObject().put("url", merged.url).put("title", merged.title).put("status", merged.status).toString()
            if (encoded != existing) writes[sourceKey] = encoded
            if (existing.isEmpty()) count++
        }
        val encoded = after.copy(truncated = truncated).toJson().toString()
        if (encoded != before.toJson().toString()) writes[recordKey] = encoded
        if (writes.isEmpty()) return
        database.mutateStrings(writes, emptyList())
        revision.value++
    }

    fun remote(context: Context, conversation: String, turn: String, event: JSONObject) {
        val trace = event.optJSONObject("research_trace")
            ?: event.optJSONObject("metadata")?.optJSONObject("research_trace") ?: return
        merge(context, conversation, turn, AgentResearchTrace.decode(trace).copy(remote = true))
    }

    /** Called after transport authentication, before UI/background routing or result acknowledgement. */
    fun receiveAuthenticated(context: Context, payload: JSONObject) {
        if (payload.optBoolean("peer_chat") || GalaxySSITransportPrivacyPolicy.isLocalOnly(payload) ||
            !AgentTaskIdentityStore.matchesRegistered(context, payload)) return
        val identity = AgentRemoteOutcomeCodec.observation(payload) ?: return
        if (!AgentConnectorResponseStore.isCurrentExecution(context, identity) ||
            AgentPendingDeliveryStore.isSuperseded(context, identity.sourceMessageId,
                identity.conversationId, identity.turnId)) return
        var trace = AgentResearchTrace.decode(payload.optJSONObject("research_trace"))
        payload.optJSONObject("progress_event")?.let {
            trace = trace.merge(AgentResearchTrace.decode(it.optJSONObject("metadata")?.optJSONObject("research_trace")))
        }
        val events = payload.optJSONArray("events")
        for (index in 0 until minOf(events?.length() ?: 0, 100)) {
            trace = trace.merge(AgentResearchTrace.decode(events?.optJSONObject(index)
                ?.optJSONObject("metadata")?.optJSONObject("research_trace")))
        }
        merge(context, identity.conversationId, identity.turnId, trace.copy(remote = true))
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
