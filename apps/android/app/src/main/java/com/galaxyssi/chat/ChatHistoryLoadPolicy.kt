package com.galaxyssi.chat

internal object ChatHistoryLoadPolicy {
    fun shouldReload(inMemoryMessagesEmpty: Boolean, markedLoaded: Boolean): Boolean =
        inMemoryMessagesEmpty || !markedLoaded
}
