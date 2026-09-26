package com.galaxyssi.chat

internal object AgentConversationActivityPolicy {
    fun messageTime(conversation: AgentConversation): Long =
        conversation.latestMessageTimestampMillis.takeIf { it > 0L }
            ?: if (conversation.latestMessageIndexed) conversation.createdAt else conversation.updatedAt
}
