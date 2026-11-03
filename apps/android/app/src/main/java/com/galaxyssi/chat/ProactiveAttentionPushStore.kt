package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** Cursor and pending work commit together, before fetching any article. */
class ProactiveAttentionPushStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, "attention_push_v1")
    private fun read() = JSONObject(database.readString("hn", "{}"))
    private fun save(state: JSONObject) = database.writeString("hn", state.toString())

    fun accept(type: String, data: String, now: Long = System.currentTimeMillis()) = synchronized(LOCK) {
        save(ProactiveAttentionPushPolicy.apply(read(), type, data, now))
    }

    fun next(now: Long = System.currentTimeMillis()): Long? = synchronized(LOCK) {
        val pending = read().optJSONObject("pending") ?: return null
        pending.keys().asSequence().filter { pending.getJSONObject(it).optLong("next") <= now }
            .maxOfOrNull(String::toLong)
    }

    fun complete(id: Long) = synchronized(LOCK) {
        val state = read()
        state.optJSONObject("pending")?.remove(id.toString())
        save(state)
    }

    fun defer(id: Long, now: Long = System.currentTimeMillis()) = synchronized(LOCK) {
        val state = read()
        val item = state.optJSONObject("pending")?.optJSONObject(id.toString()) ?: return
        val delay = ProactiveAttentionPushPolicy.retryDelay(item.optLong("delay"))
        item.put("delay", delay).put("next", now + delay)
        save(state)
    }

    fun status(value: String, now: Long = System.currentTimeMillis()) = synchronized(LOCK) {
        val state = read().put("connection", value).put("connection_at", now)
        save(state)
    }

    fun snapshot(): JSONObject = synchronized(LOCK) { read() }
    companion object { private val LOCK = Any() }
}
