package com.galaxyssi.chat.ui

data class AgentComposerUiState(
    val showPrimaryActionSlot: Boolean,
    val showMoreButton: Boolean,
    val showSendButton: Boolean,
    val showActionTray: Boolean
)

object AgentComposerUiPolicy {
    fun resolve(
        hasInput: Boolean,
        textModeActive: Boolean,
        actionTrayRequested: Boolean
    ): AgentComposerUiState {
        val showSend = hasInput
        val showTray = actionTrayRequested && !showSend
        val showMore = !showSend && (textModeActive || showTray)
        return AgentComposerUiState(
            showPrimaryActionSlot = showSend || showMore,
            showMoreButton = showMore,
            showSendButton = showSend,
            showActionTray = showTray
        )
    }
}
