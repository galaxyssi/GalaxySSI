package com.galaxyssi.chat

import android.content.Context

internal class AndroidAppControlPlatform(context: Context) : AgentAppControlPlatform {
    private val app = context.applicationContext
    override fun execute(operation: String, input: AgentNativeJsonObject, invocation: AgentNativeToolInvocation): AgentNativeJsonObject {
        fun arg(name: String) = input[name]?.toString().orEmpty().trim()
        fun limit() = (input["limit"] as? Number)?.toInt()?.coerceIn(1, 20) ?: 8
        return when (operation) {
            "reminders" -> VoiceReminderRepository(app).load().toJson()
            "context" -> AppVoiceControlBridge.context(invocation.context.conversationId, invocation.context.turnId) +
                mapOf("sim_audio_capture" to false, "sim_audio_injection" to false)
            "contacts" -> {
                val query = arg("query")
                val contacts = AppStore.contacts(app)
                val matched = (0 until contacts.length()).asSequence().mapNotNull(contacts::optJSONObject)
                    .filter { query.isBlank() || it.optString("name").contains(query, ignoreCase = true) ||
                        it.optString("display_name").contains(query, ignoreCase = true) }
                    .filter { AppStore.isDirectPeerContact(app, it.optString("id")) }
                    .take(limit() + 1).toList()
                mapOf("contacts" to matched.take(limit()).map {
                    mapOf("contact_id" to it.optString("id"), "name" to it.optString("display_name").ifBlank { it.optString("name") })
                }, "has_more" to (matched.size > limit()))
            }
            "send_message" -> send(arg("contact_id"), input["text"]?.toString().orEmpty(), invocation)
            "news" -> mapOf("articles" to AttentionArticleStore(app).voiceArticles(arg("query"),
                (input["since_epoch_ms"] as? Number)?.toLong() ?: 0, limit()))
            "read_article" -> {
                val id = arg("article_id")
                val store = AttentionArticleStore(app)
                val body = store.body(id)?.takeIf(String::isNotBlank)
                    ?: throw AppControlFailure("article_not_ready", "No readable body for this article ID.")
                val metadata = store.metadata(id)
                mapOf("article_id" to id, "title" to metadata?.chineseTitle.orEmpty(),
                    "body" to body, "url" to metadata?.url.orEmpty())
            }
            "navigate", "playback" -> AppVoiceControlBridge.execute(operation, input, invocation)
            else -> throw AppControlFailure("unknown_app_action", operation)
        }
    }

    private fun send(contactId: String, text: String, invocation: AgentNativeToolInvocation): AgentNativeJsonObject {
        if (text.isBlank() || !AppStore.isDirectPeerContact(app, contactId))
            throw AppControlFailure("invalid_peer_message", "Choose a paired person/device and non-empty text.")
        val topic = AppStore.outgoingTopicForContact(app, contactId)
            ?: throw AppControlFailure("peer_route_unavailable", "The selected peer has no verified send route.")
        invocation.checkpoint()
        // The registry's durable effect claim prevents automatic resend after an ambiguous crash.
        val id = ChatHistoryStore.appendOutgoing(app, contactId, text, app.getString(R.string.delivery_status_sending))
        check(id > 0)
        val result = try {
            GalaxySSIMqttClient.publishPeerMessageResult(content = text, contactId = contactId,
                topicOverride = topic, clientMessageId = id)
        } catch (error: Exception) {
            ChatHistoryStore.markOutgoingDelivery(app, contactId, id, "publish_failed", error.javaClass.simpleName,
                app.getString(R.string.delivery_status_failed))
            throw AppControlFailure("peer_send_failed", "Message $id was saved but publication failed. Inspect before retrying.")
        }
        val state = when (result) {
            MqttPublishResult.PUBLISHED -> "published"
            MqttPublishResult.QUEUED -> "queued"
            MqttPublishResult.FAILED -> "failed"
        }
        val label = when (result) {
            MqttPublishResult.PUBLISHED -> R.string.delivery_status_sent
            MqttPublishResult.QUEUED -> R.string.delivery_status_queued
            MqttPublishResult.FAILED -> R.string.delivery_status_failed
        }
        ChatHistoryStore.markOutgoingDelivery(app, contactId, id, state, "app_control", app.getString(label))
        AppVoiceControlBridge.refreshContact(contactId)
        return mapOf("contact_id" to contactId, "message_id" to id, "state" to state,
            "dispatch_accepted" to (result != MqttPublishResult.FAILED), "delivery_verified" to false)
    }
}
