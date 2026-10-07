package com.galaxyssi.chat

import java.util.concurrent.ExecutorService
import java.util.concurrent.Future
import java.util.concurrent.RejectedExecutionException

/** Refresh/cancel and posted callbacks run on the UI thread; storage work never does. */
internal class AgentTeamHistoryLoad(
    private val executor: ExecutorService,
    private val post: (() -> Unit) -> Unit,
    private val read: () -> List<AgentTeamMessageEnvelope>,
    private val render: (Result<List<AgentTeamMessageEnvelope>>) -> Unit
) {
    private var generation = 0L
    private var pending: Future<*>? = null

    fun refresh() {
        cancel()
        val request = generation
        try {
            pending = executor.submit {
                val result = runCatching(read)
                post { if (request == generation) render(result) }
            }
        } catch (failure: RejectedExecutionException) {
            post { if (request == generation) render(Result.failure(failure)) }
        }
    }

    fun cancel() {
        generation++
        // Do not interrupt an in-progress atomic legacy migration; only ignore its stale UI result.
        pending?.cancel(false)
        pending = null
    }
}
