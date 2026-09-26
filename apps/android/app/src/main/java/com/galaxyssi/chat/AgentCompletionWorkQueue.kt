package com.galaxyssi.chat

import android.util.Log
import java.util.concurrent.Executor
import java.util.concurrent.Executors

internal class AgentCompletionWorkQueue(
    private val executor: Executor,
    private val onFailure: (Throwable) -> Unit = {}
) {
    private val pending = mutableSetOf<String>()

    fun enqueue(runId: String, action: () -> Unit): Boolean {
        if (!synchronized(pending) { pending.add(runId) }) return false
        try {
            executor.execute {
                try {
                    action()
                } catch (error: Exception) {
                    onFailure(error)
                } finally {
                    synchronized(pending) { pending.remove(runId) }
                }
            }
        } catch (error: Exception) {
            synchronized(pending) { pending.remove(runId) }
            onFailure(error)
            return false
        }
        return true
    }
}

internal object AgentCompletedRunLearning {
    private val queue = AgentCompletionWorkQueue(
        Executors.newSingleThreadExecutor { task ->
            Thread(task, "galaxyssi-completed-run-learning").apply { isDaemon = true }
        }
    ) { error ->
        Log.w("GalaxySSI", "Completed run learning failed: ${error.javaClass.simpleName}")
    }

    fun enqueue(runId: String, action: () -> Unit): Boolean = queue.enqueue(runId, action)
}
