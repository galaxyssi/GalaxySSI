package com.galaxyssi.chat

import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

internal class BackupOperationRunner(private val executor: Executor) {
    private val active = AtomicBoolean(false)

    fun submit(work: () -> Unit, complete: (Result<Unit>) -> Unit): Boolean {
        if (!active.compareAndSet(false, true)) return false
        try {
            executor.execute {
                val result = runCatching(work)
                active.set(false)
                complete(result)
            }
        } catch (failure: RejectedExecutionException) { active.set(false); complete(Result.failure(failure)) }
        return true
    }

    companion object {
        val shared = BackupOperationRunner(Executors.newSingleThreadExecutor { action ->
            Thread(action, "backup-io").apply { isDaemon = true }
        })
    }
}
