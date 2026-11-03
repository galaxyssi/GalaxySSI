package com.galaxyssi.chat

/** Builds a notification from messages already admitted by the delivery and permission policies. */
object GlobalProactiveNotificationPolicy {
    fun enabledFor(message: GlobalProactiveMessage, settings: GlobalAgentSettings): Boolean =
        AttentionArticlePolicy.visible(message) && settings.notificationsEnabled && (message.id.startsWith("attention-feed:") ||
            (settings.enabled && settings.proactiveInsightsEnabled))

    fun candidate(candidates: List<GlobalProactiveMessage>): GlobalAgentNotificationCandidate? {
        val messages = candidates.filter(AttentionArticlePolicy::visible)
        if (messages.isEmpty()) return null
        val primary = messages.lastOrNull(GlobalProactiveMessage::urgent) ?: messages.last()
        if (messages.size == 1) {
            return GlobalAgentNotificationCandidate(
                title = GlobalAgentText.productTitle(primary.title).ifBlank { "GalaxySSI" },
                content = primary.content.take(240),
                conversationId = primary.deliveredConversationId,
                messageIds = setOf(primary.id),
                attention = ProactiveAttentionPolicy.isAttention(primary),
                important = primary.urgent
            )
        }
        val title = if (messages.any { GlobalAgentText.containsCjk(it.content) }) {
            "GalaxySSI \u6709 ${messages.size} \u6761\u65b0\u53d1\u73b0"
        } else {
            "GalaxySSI has ${messages.size} new insights"
        }
        val content = messages.asReversed()
            .distinctBy { GlobalAgentText.normalize(it.topic) }
            .take(3)
            .joinToString(" \u00b7 ") { it.topic.ifBlank { it.content.take(48) } }
        return GlobalAgentNotificationCandidate(
            title = title,
            content = content,
            conversationId = primary.deliveredConversationId,
            messageIds = messages.map(GlobalProactiveMessage::id).toSet(),
            attention = messages.any(ProactiveAttentionPolicy::isAttention),
            important = messages.any(GlobalProactiveMessage::urgent)
        )
    }
}
