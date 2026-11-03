package com.galaxyssi.chat

data class GlobalAgentProcessingBatch(
    val processedEventCount: Int,
    val changedWorldItemCount: Int,
    val queuedResearchTasks: List<GlobalResearchTask>,
    val proactiveMessages: List<GlobalProactiveMessage>,
    val queuedCognitionTasks: List<GlobalCognitionTask> = emptyList()
)

data class GlobalAgentNotificationCandidate(
    val title: String,
    val content: String,
    val conversationId: String,
    val messageIds: Set<String>,
    val attention: Boolean = false,
    val important: Boolean = false
)
