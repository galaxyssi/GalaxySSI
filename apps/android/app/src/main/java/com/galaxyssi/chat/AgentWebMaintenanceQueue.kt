package com.galaxyssi.chat

import android.util.Log
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ConcurrentHashMap

internal class AgentWebLearningState {
    @Volatile var generation = 0L
}

/** Best-effort source learning only; durable document evidence never goes through this queue. */
internal object AgentWebMaintenanceQueue {
    private val states = ConcurrentHashMap<String, AgentWebLearningState>()
    fun state(databasePath: String): AgentWebLearningState = states.computeIfAbsent(databasePath) { AgentWebLearningState() }
    private val executor = ThreadPoolExecutor(1, 1, 30L, TimeUnit.SECONDS,
        ArrayBlockingQueue(16), { task ->
            Thread(task, "galaxyssi-web-learning").apply { isDaemon = true; priority = Thread.MIN_PRIORITY }
        }).apply { allowCoreThreadTimeOut(true) }

    fun submit(task: () -> Unit): Boolean = try {
        executor.execute {
            runCatching(task).onFailure { Log.w("GalaxySSIWebLearning", "Deferred source learning failed", it) }
        }
        true
    } catch (_: RejectedExecutionException) { false }
}
