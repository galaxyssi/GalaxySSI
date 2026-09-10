package com.galaxyssi.chat

import android.content.Context
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject

internal object AgentTranscriptWindowMutationLock

/** Runtime persistence must outlive individual Activity windows. */
internal object AgentWindowTaskPersistence {
    val executor = java.util.concurrent.Executors.newSingleThreadExecutor { task ->
        Thread(task, "agent-window-task-persistence").apply { isDaemon = true }
    }
}

internal data class AgentWindowDraft(
    val text: String = "",
    val attachments: List<AgentInputAttachment> = emptyList(),
    val entryId: String = "",
    val topOffset: Int = 0,
    val autoFollow: Boolean = true
)

/** Each window owns its draft; transcript and model selection remain conversation data. */
internal class AgentWindowStateStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, "agent_window_state_v1")

    fun select(window: String, conversation: String) = synchronized(AgentTranscriptWindowMutationLock) {
        database.writeString("selected:$window", conversation)
    }
    fun selected(window: String): String = database.readString("selected:$window", "")
    fun protectConversation(id: String) = database.writeString("window-conversation:$id", "1")
    fun isWindowConversation(id: String): Boolean = database.readString("window-conversation:$id", "") == "1"

    fun save(window: String, conversation: String, state: AgentWindowDraft) {
        database.writeString("draft:$window:$conversation", JSONObject()
            .put("text", state.text)
            .put("attachments", JSONArray(state.attachments.map(AgentInputAttachment::descriptor)))
            .put("entry", state.entryId).put("offset", state.topOffset)
            .put("follow", state.autoFollow).toString())
    }

    fun load(window: String, conversation: String): AgentWindowDraft = runCatching {
        val json = JSONObject(database.readString("draft:$window:$conversation", "{}"))
        val files = json.optJSONArray("attachments") ?: JSONArray()
        AgentWindowDraft(json.optString("text"), buildList {
            for (index in 0 until files.length()) {
                val file = files.getJSONObject(index)
                add(AgentInputAttachment(file.getString("id"), Uri.parse(file.getString("uri")),
                    file.getString("name"), file.getString("mime_type"), file.optLong("size")))
            }
        }, json.optString("entry"), json.optInt("offset"), json.optBoolean("follow", true))
    }.getOrDefault(AgentWindowDraft())
}
