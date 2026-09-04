package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.AssembledToolCall
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONObject

internal data class PreparedCloudToolCall(
    val call: AssembledToolCall,
    val arguments: JSONObject
)

internal data class CompletedCloudToolCall(
    val call: AssembledToolCall,
    val output: String
)

internal object CloudToolBatchExecutor {
    suspend fun executeOrdered(
        calls: List<PreparedCloudToolCall>,
        maxParallel: Int,
        execute: (PreparedCloudToolCall) -> String
    ): List<CompletedCloudToolCall> = coroutineScope {
        if (calls.isEmpty()) return@coroutineScope emptyList()
        val permits = Semaphore(maxParallel.coerceIn(1, calls.size))
        calls.map { prepared ->
            async(Dispatchers.IO) {
                permits.withPermit {
                    CompletedCloudToolCall(prepared.call, execute(prepared))
                }
            }
        }.awaitAll()
    }
}
