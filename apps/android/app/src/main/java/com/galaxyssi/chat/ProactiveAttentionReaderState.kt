package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

internal data class AttentionReaderState(
    val filter: AttentionFeedFilter = AttentionFeedFilter.ALL,
    val keys: List<String> = emptyList(),
    val expanded: Set<String> = emptySet(),
    val anchor: String = "",
    val offset: Int = 0
)

internal class ProactiveAttentionReaderStateStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, GlobalAgentRepository.DATABASE_NAME)
    fun read(): AttentionReaderState = runCatching {
        val json = JSONObject(database.readString(KEY, "{}"))
        fun strings(name: String) = json.optJSONArray(name)?.let { array ->
            (0 until array.length()).map { array.optString(it) }.filter(String::isNotBlank)
        }.orEmpty()
        AttentionReaderState(runCatching { AttentionFeedFilter.valueOf(json.optString("filter")) }
            .getOrDefault(AttentionFeedFilter.ALL), strings("keys"), strings("expanded").toSet(),
            json.optString("anchor"), json.optInt("offset"))
    }.getOrDefault(AttentionReaderState())

    fun write(state: AttentionReaderState) = database.writeString(KEY, JSONObject()
        .put("filter", state.filter.name).put("keys", JSONArray(state.keys))
        .put("expanded", JSONArray(state.expanded.toList())).put("anchor", state.anchor)
        .put("offset", state.offset).toString())

    companion object { private const val KEY = "attention_reader_position_v1" }
}
