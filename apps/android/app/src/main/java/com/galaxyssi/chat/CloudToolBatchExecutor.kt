package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.AssembledToolCall
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
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
        onCompleted: (CompletedCloudToolCall) -> Unit = {},
        execute: suspend (PreparedCloudToolCall) -> String
    ): List<CompletedCloudToolCall> = coroutineScope {
        if (calls.isEmpty()) return@coroutineScope emptyList()
        val permits = Semaphore(maxParallel.coerceIn(1, calls.size))
        val progress = Mutex()
        calls.map { prepared ->
            async(Dispatchers.IO) {
                permits.withPermit {
                    val completed = CompletedCloudToolCall(prepared.call, execute(prepared))
                    progress.withLock { onCompleted(completed) }
                    completed
                }
            }
        }.awaitAll()
    }
}
