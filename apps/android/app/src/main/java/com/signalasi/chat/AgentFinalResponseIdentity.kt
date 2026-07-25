package com.signalasi.chat

internal object AgentFinalResponseIdentity {
    fun dedupeKey(
        turnId: String,
        sourceMessageId: Long = 0L,
        taskId: String = ""
    ): String {
        val identity = when {
            turnId.isNotBlank() -> "turn:${turnId.trim()}"
            sourceMessageId > 0L -> "source:$sourceMessageId"
            taskId.isNotBlank() -> "task:${taskId.trim()}"
            else -> return ""
        }
        return "assistant-final:$identity"
    }
}
