package com.galaxyssi.chat

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

internal object AgentNativeToolBatchExecutor {
    suspend fun <T, R> executeOrdered(
        inputs: List<T>,
        maxParallel: Int = AgentAdaptiveConcurrencyPolicy.MAX_CONCURRENCY,
        limitProvider: () -> Int = {
            AgentAdaptiveConcurrencyRuntime.currentLimit(AgentConcurrencyWorkload.NATIVE_READ_IO)
        },
        execute: (T) -> R
    ): List<R> = coroutineScope {
        if (inputs.isEmpty()) return@coroutineScope emptyList()
        val maximum = maxParallel.coerceIn(
            1,
            minOf(inputs.size, AgentAdaptiveConcurrencyPolicy.MAX_CONCURRENCY)
        )
        val permits = AgentAdaptiveCoroutinePermitGate(
            limitProvider = { minOf(limitProvider(), maximum) },
            maximum = maximum
        )
        inputs.map { input ->
            async(Dispatchers.IO) {
                permits.acquire()
                try {
                    execute(input)
                } finally {
                    permits.release()
                }
            }
        }.awaitAll()
    }
}
