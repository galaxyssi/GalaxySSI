package com.galaxyssi.chat

internal object ChatMessageViewportPolicy {
    fun stackFromEnd(systemNotifications: Boolean): Boolean = !systemNotifications

    fun anchorToStartOnOpen(systemNotifications: Boolean): Boolean = systemNotifications

    fun followLatest(systemNotifications: Boolean, nearBottom: Boolean): Boolean =
        !systemNotifications && nearBottom
}
