package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal data class AgentShadowRoutingOrderEntry(val key: String, val createdAtMillis: Long)

internal object AgentShadowRoutingOrderIndex {
    const val KEY = "order-index:v1"
    const val PREFIX = "recommendation:"
    const val LIMIT = 500

    fun retain(entries: List<AgentShadowRoutingOrderEntry>): List<AgentShadowRoutingOrderEntry> =
        entries.sortedWith(compareByDescending<AgentShadowRoutingOrderEntry> { it.createdAtMillis }.thenBy { it.key })
            .distinctBy { it.key }.take(LIMIT)

    fun encode(entries: List<AgentShadowRoutingOrderEntry>): String = JSONObject()
        .put("version", 1)
        .put("entries", JSONArray().apply {
            entries.forEach { put(JSONArray().put(it.key).put(it.createdAtMillis)) }
        }).toString()

    fun decode(raw: String): List<AgentShadowRoutingOrderEntry>? = runCatching {
        val root = JSONObject(raw)
        require(root.getInt("version") == 1)
        val values = root.getJSONArray("entries")
        require(values.length() <= LIMIT)
        val entries = (0 until values.length()).map { index ->
            val entry = values.getJSONArray(index)
            require(entry.length() == 2)
            val key = entry.getString(0)
            require(key.startsWith(PREFIX) && key.length > PREFIX.length)
            val timestamp = entry.get(1)
            require(timestamp is Long || timestamp is Int)
            AgentShadowRoutingOrderEntry(key, (timestamp as Number).toLong())
        }
        require(entries.map { it.key }.distinct().size == entries.size)
        require(entries == retain(entries))
        entries
    }.getOrNull()
}
