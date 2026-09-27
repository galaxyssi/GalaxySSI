package com.galaxyssi.chat

import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.CopyOnWriteArraySet

/** Retained by asynchronous submission callbacks, even after the floating panel is closed. */
internal class ScreenAssistantAnalysisRequest {
    private val cancelled = AtomicBoolean(false)
    private val submittedTurns = CopyOnWriteArraySet<String>()
    @Volatile var turnId: String = ""
        set(value) {
            field = value
            if (value.isNotBlank()) submittedTurns.add(value)
        }
    val turnIds: Set<String> get() = submittedTurns.toSet()
    val isCancelled: Boolean get() = cancelled.get()
    fun cancel(): Boolean = cancelled.compareAndSet(false, true)
}
