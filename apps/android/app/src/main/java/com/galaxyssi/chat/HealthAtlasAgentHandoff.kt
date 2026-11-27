package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import android.os.SystemClock
import java.util.UUID
import org.json.JSONObject

class HealthAtlasDiscussionActivity : MainActivity()

/** A one-use in-process capability: exported Activity extras cannot create an Agent request. */
internal object HealthAtlasAgentHandoff {
    private const val KEY = "health_atlas_handoff"
    private data class Request(val conversation: String, val prompt: String, val created: Long)
    private val pending = linkedMapOf<String, Request>()
    @Synchronized fun prepare(context: Context, title: String, prompt: String, itemId: String): Intent {
        require(prompt.length in 1..9000)
        require(itemId.length in 1..60)
        pending.entries.removeAll { SystemClock.elapsedRealtime() - it.value.created > 120_000 }
        while (pending.size >= 8) pending.remove(pending.keys.first())
        val store = AgentTranscriptStore(context)
        val key = "body-atlas:$itemId"
        val index = AgentEncryptedPreferences(context, "atlas_educational_conversations")
        val topics = JSONObject(index.readString("topics", "{}"))
        val conversation = topics.optString(key).takeIf(String::isNotBlank)?.let(store::conversation)?.takeIf {
            it.status == AgentConversationStatus.ACTIVE && it.globalTopicKey == key && it.createdByAgent &&
                !it.privateMode && !it.trackingPaused
        } ?: store.createAgentConversation(title, globalTopicKey = key).also {
            index.writeString("topics", topics.put(key, it.id).toString())
        }
        val token = UUID.randomUUID().toString()
        pending[token] = Request(conversation.id, prompt, SystemClock.elapsedRealtime())
        return Intent(context, HealthAtlasDiscussionActivity::class.java)
            .putExtra(AgentConversationWindows.WINDOW_KEY, "atlas:" + conversation.id)
            .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", conversation.id).putExtra(KEY, token)
    }
    fun consume(activity: MainActivity) {
        val token = activity.intent?.getStringExtra(KEY) ?: return
        activity.intent?.removeExtra(KEY)
        val request = synchronized(this) { pending.remove(token) } ?: return
        if (SystemClock.elapsedRealtime() - request.created > 120_000) return
        if (activity.agentTranscriptStore.activeConversation().id != request.conversation) return
        activity.submitAgentGoal(goalOverride = request.prompt, attachmentsOverride = emptyList(),
            pendingVoiceConversationId = request.conversation, pendingVoiceDedupeKey = "body-atlas:$token")
    }
}
