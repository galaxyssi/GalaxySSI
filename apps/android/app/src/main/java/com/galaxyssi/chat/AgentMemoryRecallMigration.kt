package com.galaxyssi.chat

import android.os.Process
import android.util.Log
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

internal object AgentMemoryRecallMigration {
    private val pending = ConcurrentHashMap.newKeySet<String>()
    private val worker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "memory-recall-index").apply { isDaemon = true }
    }

    fun resume(index: AgentMemoryRecallIndex, generation: String) {
        val identity = "${index.database.storageIdentity}:$generation"
        if (!pending.add(identity)) return
        try {
            worker.execute {
                try {
                    Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
                    while (!Thread.currentThread().isInterrupted && !index.backfillPage(generation)) Thread.sleep(10)
                } catch (error: Exception) {
                    if (error is InterruptedException) Thread.currentThread().interrupt()
                    Log.w("GalaxySSIMemoryRecall", "Index backfill paused (${error.javaClass.simpleName}); source records remain intact")
                } finally { pending.remove(identity) }
            }
        } catch (error: RuntimeException) { pending.remove(identity); throw error }
    }
}
