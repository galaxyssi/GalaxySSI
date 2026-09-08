package com.galaxyssi.chat

internal object ChatMessageViewportPolicy {
    fun stackFromEnd(): Boolean = false

    fun anchorToStartOnOpen(systemNotifications: Boolean): Boolean = systemNotifications

    fun followLatest(systemNotifications: Boolean, nearBottom: Boolean): Boolean =
        !systemNotifications && nearBottom
}
