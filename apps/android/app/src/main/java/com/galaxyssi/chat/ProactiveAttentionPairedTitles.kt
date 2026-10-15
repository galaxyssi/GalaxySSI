package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject
import java.util.UUID

internal data class AttentionTitleRequest(
    val id: String,
    val source: Long,
    val contact: String,
    val owner: String,
    val expires: Long,
    val titles: Map<String, String>,
    val completed: Boolean = false
) {
    val conversation: String get() = PREFIX + id
    fun matches(response: AgentConnectorResponse): Boolean = response.sourceMessageId == source &&
        response.contactId == contact && response.conversationId == conversation && response.turnId == id

    fun json(): String = JSONObject().put("id", id).put("source", source).put("contact", contact)
        .put("owner", owner).put("expires", expires).put("titles", JSONObject(titles))
        .put("completed", completed).toString()

    companion object {
        const val PREFIX = "public-attention:titles:"
        const val LEASE = 15 * 60_000L
        fun parse(raw: String): AttentionTitleRequest? = runCatching {
            val value = JSONObject(raw)
            val titles = value.getJSONObject("titles")
            AttentionTitleRequest(value.getString("id"), value.getLong("source"), value.getString("contact"),
                value.getString("owner"), value.getLong("expires"),
                titles.keys().asSequence().associateWith(titles::getString), value.optBoolean("completed"))
        }.getOrNull()
    }
}

/** One durable public-title batch; final replies use the existing background response consumer. */
internal class ProactiveAttentionPairedTitles(context: Context,
    private val scheduleNext: (Context) -> Unit = { ProactiveAttentionTitleScheduler.request(it, 30_000L) }) {
    private val context = context.applicationContext
    private val database = AgentEncryptedDatabase(this.context, "attention_paired_titles_v1")
    private fun read() = AttentionTitleRequest.parse(database.readString("request", "{}"))

    fun pendingDelay(now: Long): Long = synchronized(LOCK) {
        val request = read() ?: return 0L
        if (request.completed) return 0L
        if (request.expires > now) return request.expires - now
        GlobalModelCallBudgetStore(context).release(GlobalModelCallKind.COGNITION, request.owner)
        database.writeString("request", request.copy(completed = true).json())
        0L
    }

    fun dispatch(contact: String, owner: String, titles: Map<String, String>, now: Long): Boolean = synchronized(LOCK) {
        if (pendingDelay(now) > 0L) return false
        val topic = AppStore.outgoingTopicForContact(context, contact) ?: return false
        val id = UUID.randomUUID()
        val request = AttentionTitleRequest(id.toString(), (id.mostSignificantBits and 0x1FFFFFFFFFFFFFL).coerceAtLeast(1L),
            contact, owner, now + AttentionTitleRequest.LEASE, titles)
        database.writeString("request", request.json())
        GalaxySSIMqttClient.connect(context)
        val published = GalaxySSIMqttClient.publishUserMessage(
            content = ProactiveAttentionTitlePolicy.SYSTEM + "\n" +
                ProactiveAttentionTitlePolicy.prompt(titles, ProactiveAttentionTitleStore(context).feedback(titles)),
            contactId = contact, topicOverride = topic, clientMessageId = request.source,
            conversationId = request.conversation, turnId = request.id, trustedBackgroundCognition = true)
        if (!published) database.writeString("request", request.copy(completed = true).json())
        published
    }

    fun consume(response: AgentConnectorResponse): Boolean {
        if (!response.conversationId.startsWith(AttentionTitleRequest.PREFIX)) return false
        synchronized(LOCK) {
            val request = read() ?: return true
            // Never let an expired or unrelated reply populate the next batch's cache.
            if (!request.matches(response) || request.completed) return true
            GlobalModelCallBudgetStore(context).complete(GlobalModelCallKind.COGNITION, request.owner,
                response.inputTokens, response.outputTokens, response.costMicros, response.content)
            val store = ProactiveAttentionTitleStore(context)
            val saved = if (response.success && !response.remoteFailure) store.accept(response.content, request.titles) else 0
            database.writeString("request", request.copy(completed = true).json())
            if (saved > 0) GlobalProactiveDeliveryBus.signalReady()
            android.util.Log.i("GalaxySSIAttention", "paired_title_translation requested=${request.titles.size} saved=$saved")
        }
        scheduleNext(context)
        return true
    }

    companion object { private val LOCK = Any() }
}
