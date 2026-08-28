package com.signalasi.chat

internal object ChatHistoryLoadPolicy {
    fun shouldReload(inMemoryMessagesEmpty: Boolean, markedLoaded: Boolean): Boolean =
        inMemoryMessagesEmpty || !markedLoaded
}
