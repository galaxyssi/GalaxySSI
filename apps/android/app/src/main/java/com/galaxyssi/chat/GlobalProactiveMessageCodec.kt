package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal object GlobalProactiveMessageCodec {
    fun encode(message: GlobalProactiveMessage): JSONObject = JSONObject()
        .put("id", message.id)
        .put("source_event_id", message.sourceEventId)
        .put("causal_event_ids", JSONArray(message.causalEventIds.toList()))
        .put("source_conversation_id", message.sourceConversationId)
        .put("target", message.target.name)
        .put("title", message.title)
        .put("content", message.content)
        .put("topic", message.topic)
        .put("urgent", message.urgent)
        .put("status", message.status.name)
        .put("created_at_millis", message.createdAtMillis)
        .put("notified_at_millis", message.notifiedAtMillis)
        .put("delivery_conversation_id", message.deliveryConversationId)
        .put("delivery_lease_expires_at_millis", message.deliveryLeaseExpiresAtMillis)
        .put("delivery_attempt_count", message.deliveryAttemptCount)
        .put("delivery_budget_counted", message.deliveryBudgetCounted)
        .put("last_delivery_error", message.lastDeliveryError)
        .put("delivered_at_millis", message.deliveredAtMillis)
        .put("delivered_conversation_id", message.deliveredConversationId)
        .put("delivery_group_id", message.deliveryGroupId)
        .put("viewed_at_millis", message.viewedAtMillis)
        .put("news_article_key", message.newsArticleKey)
        .put("news_translation_provider", message.newsTranslationProvider)
        .put("news_article_revision", message.newsArticleRevision)

    fun decode(json: JSONObject?): GlobalProactiveMessage? {
        if (json == null) return null
        val id = json.optString("id")
        if (id.isBlank()) return null
        val status = enumValue(json.optString("status"), GlobalProactiveMessageStatus.PENDING)
        val createdAtMillis = json.optLong("created_at_millis")
        val notifiedAtMillis = if (json.has("notified_at_millis")) json.optLong("notified_at_millis")
            else if (status in setOf(GlobalProactiveMessageStatus.NOTIFIED, GlobalProactiveMessageStatus.DELIVERED))
                json.optLong("delivered_at_millis").takeIf { it > 0L } ?: createdAtMillis else 0L
        val events = json.optJSONArray("causal_event_ids")
        return GlobalProactiveMessage(
            id = id,
            sourceEventId = json.optString("source_event_id"),
            causalEventIds = (0 until (events?.length() ?: 0)).mapNotNull { events?.optString(it)?.takeIf(String::isNotBlank) }
                .toSet().ifEmpty { setOf(json.optString("source_event_id")) },
            sourceConversationId = json.optString("source_conversation_id"),
            target = enumValue(json.optString("target"), GlobalProactiveTarget.CURRENT_CONVERSATION),
            title = GlobalAgentText.productTitle(json.optString("title")),
            content = json.optString("content"),
            topic = json.optString("topic"), urgent = json.optBoolean("urgent"), status = status,
            createdAtMillis = createdAtMillis, notifiedAtMillis = notifiedAtMillis,
            deliveryConversationId = json.optString("delivery_conversation_id"),
            deliveryLeaseExpiresAtMillis = json.optLong("delivery_lease_expires_at_millis"),
            deliveryAttemptCount = json.optInt("delivery_attempt_count").coerceAtLeast(0),
            deliveryBudgetCounted = if (json.has("delivery_budget_counted")) json.optBoolean("delivery_budget_counted")
                else status == GlobalProactiveMessageStatus.NOTIFIED,
            lastDeliveryError = json.optString("last_delivery_error").take(600),
            deliveredAtMillis = json.optLong("delivered_at_millis"),
            deliveredConversationId = json.optString("delivered_conversation_id"),
            deliveryGroupId = json.optString("delivery_group_id"), viewedAtMillis = json.optLong("viewed_at_millis"),
            newsArticleKey = json.optString("news_article_key"), newsTranslationProvider = json.optString("news_translation_provider"),
            newsArticleRevision = json.optInt("news_article_revision", 0)
        )
    }

    private inline fun <reified T : Enum<T>> enumValue(value: String, fallback: T): T =
        enumValues<T>().firstOrNull { it.name == value } ?: fallback
}
