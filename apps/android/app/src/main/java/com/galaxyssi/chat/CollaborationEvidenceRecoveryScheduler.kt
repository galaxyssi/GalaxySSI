package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.yield

internal enum class CollaborationEvidenceSlice { COMPLETE, YIELDED, DEFERRED }

/** Bounded I/O lanes, not a limit on members, observations or research attempts. */
internal class CollaborationEvidenceRecoveryScheduler(private val parallelism: Int = 2) {
    init { require(parallelism > 0) }

    suspend fun run(batch: List<Pair<String, String>>, onClaim: (String) -> Unit,
        onFailure: (String, Exception) -> Unit,
        recover: suspend (String) -> CollaborationEvidenceSlice) = coroutineScope {
        val queue = ArrayDeque(batch)
        val lock = Mutex()
        repeat(minOf(parallelism, batch.size)) {
            launch {
                while (true) {
                    ensureActive()
                    val job = lock.withLock {
                        if (queue.isEmpty()) null else queue.removeFirst().also { onClaim(it.first) }
                    } ?: break
                    val outcome = try { recover(job.second) }
                    catch (cancelled: CancellationException) { throw cancelled }
                    catch (error: Exception) {
                        onFailure(job.second, error)
                        CollaborationEvidenceSlice.DEFERRED
                    }
                    // Only a successful transfer slice is immediately requeued. Offline jobs retain backoff.
                    if (outcome == CollaborationEvidenceSlice.YIELDED) lock.withLock { queue.addLast(job) }
                    yield()
                }
            }
        }
    }
}
