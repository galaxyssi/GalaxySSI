package com.galaxyssi.chat

/** A health surface belongs to one private discussion, never to the global Agent landing page. */
internal object HealthCareAgentScope {
    fun concernId(conversation: AgentConversation): String? {
        if (conversation.status != AgentConversationStatus.ACTIVE || !conversation.privateMode || !conversation.trackingPaused)
            return null
        val topic = conversation.globalTopicKey
        if (!topic.startsWith(HealthCareDiscussionPolicy.TOPIC_PREFIX)) return null
        return topic.removePrefix(HealthCareDiscussionPolicy.TOPIC_PREFIX).takeIf(HealthProfilePolicy::uuid)
    }
}
