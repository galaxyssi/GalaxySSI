package com.galaxyssi.chat

internal object AgentVoiceAttachmentSubmissionPolicy {
    fun <T> select(
        goalOverride: String?,
        composerAttachments: List<T>,
        attachmentSnapshot: List<T>?
    ): List<T> = attachmentSnapshot?.toList()
        ?: if (goalOverride == null) composerAttachments.toList() else emptyList()
}
