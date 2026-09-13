package com.galaxyssi.watch

import android.content.Context
import com.galaxyssi.chat.AgentEncryptedDatabase
import com.galaxyssi.chat.AgentEncryptedPreferences
import org.json.JSONArray
import org.json.JSONObject

class WatchStore(context: Context) {
    private val prefs = AgentEncryptedPreferences(context, "watch_settings")
    private val tasks = AgentEncryptedDatabase(context, "watch_tasks")
    var apiProfile: ApiProfile?
        get() = prefs.readString("api_profile", "").takeIf { it.isNotBlank() }
            ?.let { runCatching { ApiProfile.fromJson(JSONObject(it)) }.getOrNull() }
        set(value) { if (value == null) prefs.remove("api_profile") else prefs.writeString("api_profile", value.json().toString()) }
    var apiPreferred: Boolean
        get() = prefs.readString("api_preferred", "false").toBoolean()
        set(value) = prefs.writeString("api_preferred", value.toString())
    val outbox = AgentEncryptedDatabase(context, "watch_outbox")
    val inbox = AgentEncryptedDatabase(context, "watch_inbox")
    var activeTask: String
        get() = prefs.readString("active_task", "")
        set(value) = prefs.writeString("active_task", value)
    private fun readVersion(task: WatchTask) = "${task.state}:${task.reply.hashCode()}:${task.reply.length}"
    fun unread(task: WatchTask) = task.reply.isNotBlank() && prefs.readString("read:${task.id}", "") != readVersion(task)
    fun markRead(turns: List<WatchTask>) {
        turns.filter(::unread).forEach { prefs.writeString("read:${it.id}", readVersion(it)) }
    }
    @Synchronized fun tasks(): List<WatchTask> = tasks.entries().mapNotNull { (_, value) ->
        runCatching { WatchTask.fromJson(JSONObject(value)) }.getOrNull()
    }.sortedByDescending { it.sourceId }
    @Synchronized fun save(task: WatchTask) {
        tasks.writeString(task.id, task.json().toString())
        val old = tasks().filter { it.state.terminal }.drop(100)
        tasks.removeAll(old.map { it.id })
        old.forEach { prefs.remove("read:${it.id}") }
    }
    @Synchronized fun task(id: String): WatchTask? = tasks.readString(id, "")
        .takeIf { it.isNotBlank() }?.let { WatchTask.fromJson(JSONObject(it)) }
    var draft: String
        get() = prefs.readString("draft", "")
        set(value) = prefs.writeString("draft", value)
    var selectedDesktop: String
        get() = prefs.readString("desktop", "")
        set(value) = prefs.writeString("desktop", value)
    var selectedAgent: String
        get() = prefs.readString("agent", "")
        set(value) = prefs.writeString("agent", value)
    var vibration: Boolean
        get() = prefs.readString("vibration", "true").toBoolean()
        set(value) = prefs.writeString("vibration", value.toString())
    var autoSpeech: Boolean
        get() = prefs.readString("auto_speech", "false").toBoolean()
        set(value) = prefs.writeString("auto_speech", value.toString())
    fun saveAgents(desktop: String, value: JSONArray) = prefs.writeString("agents:$desktop", value.toString())
    fun agents(desktop: String): List<WatchAgent> {
        val array = runCatching { JSONArray(prefs.readString("agents:$desktop", "[]")) }.getOrDefault(JSONArray())
        return (0 until array.length()).mapNotNull { i ->
            val j = array.optJSONObject(i) ?: return@mapNotNull null
            val id = j.optString("agent_id").ifBlank {
                j.optString("mobile_contact_id").ifBlank { j.optString("id").substringAfterLast(':') }
            }
            if (id.isBlank() || id == "cloud-model") null else WatchAgent(desktop, id,
                j.optString("name").ifBlank { id }, j.optBoolean("available", false) ||
                    j.optString("status") in setOf("ready", "available", "running"))
        }
    }
    fun forgetAgents(desktop: String) = prefs.remove("agents:$desktop")
}
