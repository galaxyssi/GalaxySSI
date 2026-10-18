package com.galaxyssi.chat

// Only identifiers and geometry survive background plaintext eviction.
internal data class ChatMessageScrollAnchor(val messageId: Long, val sequence: Long, val topOffset: Int)

internal class ChatMessageViewportState {
    var contactId = ""
        private set
    var generation = 0L
        private set
    var followLatest = false
        private set
    var suspended = false
        private set
    var pendingAnchor: ChatMessageScrollAnchor? = null
        private set

    fun select(id: String, systemNotifications: Boolean) {
        contactId = id
        generation++
        followLatest = !systemNotifications
        pendingAnchor = null
        suspended = false
    }

    fun suspend(anchor: ChatMessageScrollAnchor?) {
        if (suspended) return
        generation++
        if (!followLatest) pendingAnchor = anchor
        suspended = true
    }

    fun resume() { suspended = false }

    fun sent(id: String): Boolean {
        if (id != contactId) return false
        generation++
        pendingAnchor = null
        followLatest = true
        return true
    }

    fun userScroll(nearBottom: Boolean, systemNotifications: Boolean) {
        pendingAnchor = null
        followLatest = !systemNotifications && nearBottom
    }

    fun beginUserScroll() {
        generation++
        pendingAnchor = null
        followLatest = false
    }

    fun restored() { pendingAnchor = null }

    fun accepts(id: String, requestGeneration: Long): Boolean =
        !suspended && id == contactId && generation == requestGeneration
}
