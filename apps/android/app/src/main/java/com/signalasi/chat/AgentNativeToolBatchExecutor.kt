package com.signalasi.chat

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

internal object AgentNativeToolBatchExecutor {
    suspend fun <T, R> executeOrdered(
        inputs: List<T>,
        maxParallel: Int = MAX_PARALLEL_READS,
        execute: (T) -> R
    ): List<R> = coroutineScope {
        if (inputs.isEmpty()) return@coroutineScope emptyList()
        val permits = Semaphore(maxParallel.coerceIn(1, inputs.size))
        inputs.map { input ->
            async(Dispatchers.IO) {
                permits.withPermit { execute(input) }
            }
        }.awaitAll()
    }

    private const val MAX_PARALLEL_READS = 4
}
