package com.galaxyssi.chat

// Navigation metadata only: never retain list rows, message text, or views across backgrounding.
internal data class ConversationHubScrollAnchor(
    val stableRowId: String,
    val topOffset: Int,
    val position: Int = 0
) {
    fun restoredPosition(ids: List<String>): Int {
        val exact = ids.indexOf(stableRowId)
        return if (exact >= 0) exact else position.coerceIn(0, (ids.size - 1).coerceAtLeast(0))
    }
}

internal data class ConversationHubNavigationState(
    val tab: ConversationHubTab,
    val archived: Boolean,
    val visible: Boolean,
    val hiddenDestination: ConversationHubItemKind?,
    val anchor: ConversationHubScrollAnchor?,
    val loadedAgentCount: Int,
    val contactScrollY: Int
)

internal fun MainActivity.suspendConversationHubForBackground() {
    val snapshot = captureConversationHubNavigation?.invoke()?.takeIf { it.visible || it.hiddenDestination != null }
    agentSessionsDialog?.dismiss()
    if (snapshot != null) {
        suspendedConversationHub = snapshot
        restoreHiddenConversationHub = { restoreSuspendedConversationHub() }
    }
}

internal fun MainActivity.restoreSuspendedConversationHub(): Boolean {
    val snapshot = suspendedConversationHub ?: return false
    suspendedConversationHub = null
    restoreHiddenConversationHub = null
    showConversationHub(
        initialTab = snapshot.tab,
        showArchived = snapshot.archived,
        restoredNavigation = snapshot,
        afterFirstFramePresented = if (!snapshot.visible && snapshot.hiddenDestination == ConversationHubItemKind.CONTACT) {
            { showAgentHomeFromChat(preserveNavigationContent = true) }
        } else null
    )
    return true
}
