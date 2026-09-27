package com.galaxyssi.chat

import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.CopyOnWriteArraySet

/** Retained by asynchronous submission callbacks, even after the floating panel is closed. */
internal class ScreenAssistantAnalysisRequest {
    private val cancelled = AtomicBoolean(false)
    private val submittedTurns = CopyOnWriteArraySet<String>()
    private val pauseMonitor = Object()
    @Volatile var automation = false
    var preparingSubmission = false
    @Volatile var approvalDescription: String = ""
        private set
    @Volatile var isPaused = false
        private set
    @Volatile var turnId: String = ""
        set(value) {
            field = value
            if (value.isNotBlank()) submittedTurns.add(value)
        }
    val turnIds: Set<String> get() = submittedTurns.toSet()
    val isCancelled: Boolean get() = cancelled.get()
    fun setPaused(value: Boolean) = synchronized(pauseMonitor) {
        isPaused = value
        pauseMonitor.notifyAll()
    }
    fun awaitRunnable(checkCancelled: () -> Unit = {}) = synchronized(pauseMonitor) {
        while (isPaused && !isCancelled) {
            checkCancelled()
            pauseMonitor.wait(200L)
        }
        checkCancelled()
        if (isCancelled) throw AgentNativeToolCancelledException()
    }
    fun requireApproval(description: String, checkCancelled: () -> Unit) = synchronized(pauseMonitor) {
        approvalDescription = description
        try {
            while (approvalDescription.isNotBlank() && !isCancelled) {
                checkCancelled()
                pauseMonitor.wait(200L)
            }
            checkCancelled()
            if (isCancelled) throw AgentNativeToolCancelledException()
        } finally { approvalDescription = "" }
    }
    fun approve() = synchronized(pauseMonitor) { approvalDescription = ""; pauseMonitor.notifyAll() }
    fun cancel(): Boolean {
        val changed = cancelled.compareAndSet(false, true)
        synchronized(pauseMonitor) { pauseMonitor.notifyAll() }
        return changed
    }
}
