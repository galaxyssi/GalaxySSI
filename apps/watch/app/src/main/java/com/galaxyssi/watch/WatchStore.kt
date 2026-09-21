package com.galaxyssi.watch

import android.content.Context
import com.galaxyssi.chat.AgentEncryptedDatabase
import com.galaxyssi.chat.AgentEncryptedPreferences
import org.json.JSONArray
import org.json.JSONObject

class WatchStore(context: Context) {
    private val prefs = AgentEncryptedPreferences(context, "watch_settings")
    private val tasks = AgentEncryptedDatabase(context, "watch_tasks")
    init {
        if (prefs.readString("paragraph_speech_defaults_v1", "") != "true") {
            prefs.writeString("auto_speech", "true")
            prefs.writeString("paragraph_speech_defaults_v1", "true")
        }
    }
    var apiProfile: ApiProfile?
        get() = prefs.readString("api_profile", "").takeIf { it.isNotBlank() }
            ?.let { runCatching { ApiProfile.fromJson(JSONObject(it)) }.getOrNull() }
        set(value) { if (value == null) prefs.remove("api_profile") else prefs.writeString("api_profile", value.json().toString()) }
    var samsungAutoConfirm: Boolean
        get() = prefs.readString("samsung_auto_confirm", "true").toBoolean()
        set(value) = prefs.writeString("samsung_auto_confirm", value.toString())
    var voiceOnOpen: Boolean
        get() = prefs.readString("voice_on_open", "false").toBoolean()
        set(value) = prefs.writeString("voice_on_open", value.toString())
    val historyLoaded: Boolean get() = taskSnapshot != null
    var foregroundWake: Boolean
        get() = prefs.readString("foreground_wake", "false").toBoolean()
        set(value) = prefs.writeString("foreground_wake", value.toString())
    var apiPreferred: Boolean
        get() = prefs.readString("api_preferred", "false").toBoolean()
        set(value) = prefs.writeString("api_preferred", value.toString())
    val outbox = AgentEncryptedDatabase(context, "watch_outbox")
    val inbox = AgentEncryptedDatabase(context, "watch_inbox")
    var activeTask: String
        get() = prefs.readString("active_task", "")
        set(value) { if (activeTask != value) prefs.writeString("active_task", value) }
    private val cachedReadVersions = java.util.concurrent.ConcurrentHashMap<String, String>()
    private val readRevision = java.util.concurrent.atomic.AtomicLong()
    val cachedReadRevision: Long get() = readRevision.get()
    fun cachedUnread(task: WatchTask) = task.reply.isNotBlank() && cachedReadVersions[task.id] != readVersion(task)
    private fun warmReadVersions(turns: List<WatchTask>) {
        turns.forEach { task ->
            if (!cachedReadVersions.containsKey(task.id)) {
                val version = prefs.readString("read:${task.id}", "")
                if (cachedReadVersions.putIfAbsent(task.id, version) == null) readRevision.incrementAndGet()
            }
        }
    }
    private fun readVersion(task: WatchTask) = "${task.state}:${task.reply.hashCode()}:${task.reply.length}"
    fun unread(task: WatchTask) = task.reply.isNotBlank() && prefs.readString("read:${task.id}", "") != readVersion(task)
    fun markRead(turns: List<WatchTask>) {
        turns.filter(::unread).forEach {
            val version = readVersion(it)
            prefs.writeString("read:${it.id}", version)
            if (cachedReadVersions.put(it.id, version) != version) readRevision.incrementAndGet()
        }
    }
    @Volatile private var taskSnapshot: List<WatchTask>? = null
    /** Non-blocking UI snapshot; populated by repository startup before transport work. */
    fun cachedTasks(): List<WatchTask> = taskSnapshot.orEmpty()
    fun cachedTask(id: String): WatchTask? = taskSnapshot?.firstOrNull { it.id == id }
    fun tasks(): List<WatchTask> = taskSnapshot ?: synchronized(this) {
        taskSnapshot ?: tasks.entries().mapNotNull { (_, value) ->
            runCatching { WatchTask.fromJson(JSONObject(value)) }.getOrNull()
        }.sortedByDescending { it.sourceId }.also { warmReadVersions(it); taskSnapshot = it }
    }
    @Synchronized fun save(task: WatchTask) {
        val current = tasks()
        tasks.writeString(task.id, task.json().toString())
        val updated = (current.filterNot { it.id == task.id } + task).sortedByDescending { it.sourceId }
        val old = updated.filter { it.state.terminal }.drop(100).map { it.id }.toSet()
        tasks.removeAll(old)
        old.forEach { prefs.remove("read:$it"); cachedReadVersions.remove(it) }
        taskSnapshot = updated.filterNot { it.id in old }
    }
    fun task(id: String): WatchTask? {
        if (id.isBlank()) return null
        taskSnapshot?.let { return it.firstOrNull { task -> task.id == id } }
        return tasks.readString(id, "").takeIf { it.isNotBlank() }?.let { WatchTask.fromJson(JSONObject(it)) }
    }
    var draft: String
        get() = prefs.readString("draft", "")
        set(value) { if (draft != value) prefs.writeString("draft", value) }
    var selectedDesktop: String
        get() = prefs.readString("desktop", "")
        set(value) = prefs.writeString("desktop", value)
    var selectedAgent: String
        get() = prefs.readString("agent", "")
        set(value) = prefs.writeString("agent", value)
    var backgroundEnabled: Boolean
        get() = prefs.readString("background_enabled", "true").toBoolean()
        set(value) = prefs.writeString("background_enabled", value.toString())
    var webSearch: Boolean
        get() = prefs.readString("web_search", "true").toBoolean()
        set(value) = prefs.writeString("web_search", value.toString())
    var vibration: Boolean
        get() = prefs.readString("vibration", "true").toBoolean()
        set(value) = prefs.writeString("vibration", value.toString())
    var autoSpeech: Boolean
        get() = prefs.readString("auto_speech", "true").toBoolean()
        set(value) = prefs.writeString("auto_speech", value.toString())
    fun saveAgents(desktop: String, value: JSONArray) = prefs.writeString("agents:$desktop", WatchAgentStatus.received(value, System.currentTimeMillis()).toString())
    fun agents(desktop: String): List<WatchAgent> {
        val array = runCatching { JSONArray(prefs.readString("agents:$desktop", "[]")) }.getOrDefault(JSONArray())
        val now = System.currentTimeMillis()
        return (0 until array.length()).mapNotNull { i ->
            val j = array.optJSONObject(i) ?: return@mapNotNull null
            val id = j.optString("agent_id").ifBlank {
                j.optString("mobile_contact_id").ifBlank { j.optString("id").substringAfterLast(':') }
            }
            if (id.isBlank() || id == "cloud-model") null else WatchAgent(desktop, id,
                j.optString("name").ifBlank { id }, WatchAgentStatus.available(j, now), WatchAgentStatus.label(j, now))
        }
    }
    fun forgetAgents(desktop: String) = prefs.remove("agents:$desktop")
}
