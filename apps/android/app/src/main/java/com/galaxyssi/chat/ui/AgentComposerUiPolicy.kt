package com.galaxyssi.chat.ui

data class AgentComposerUiState(
    val showPrimaryActionSlot: Boolean,
    val showMoreButton: Boolean,
    val showSendButton: Boolean,
    val showActionTray: Boolean,
    val showVoiceButton: Boolean = false
)

object AgentComposerUiPolicy {
    fun resolve(
        hasInput: Boolean,
        textModeActive: Boolean,
        actionTrayRequested: Boolean,
        voiceEntryAvailable: Boolean = false
    ): AgentComposerUiState {
        val showSend = hasInput
        val showTray = actionTrayRequested && !showSend
        val showMore = !showSend && (textModeActive || showTray)
        val showVoice = voiceEntryAvailable && !showSend && !showMore
        return AgentComposerUiState(
            showPrimaryActionSlot = showSend || showMore || showVoice,
            showMoreButton = showMore,
            showSendButton = showSend,
            showActionTray = showTray,
            showVoiceButton = showVoice
        )
    }
}
