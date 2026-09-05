package com.galaxyssi.chat

/** UI identity only: loading a transcript row must not decrypt the run ledger. */
data class AgentVoiceRunReference(
    val runId: String,
    val conversationId: String,
    val turnId: String,
    val taskId: String
) {
    fun matches(conversationId: String, turnId: String, taskId: String): Boolean =
        runId.isNotBlank() && this.conversationId.isNotBlank() &&
            this.turnId.isNotBlank() && this.taskId.isNotBlank() &&
            this.conversationId == conversationId && this.turnId == turnId && this.taskId == taskId
}
