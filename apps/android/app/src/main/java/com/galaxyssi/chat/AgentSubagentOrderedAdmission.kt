package com.galaxyssi.chat

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock

/** Orders ready work before acquiring the shared permit, independently of dispatcher scheduling. */
internal class AgentSubagentOrderedAdmission(private val permits: Semaphore) {
    data class Candidate(val id: String, val ready: () -> Boolean)

    private val mutex = Mutex()
    private val admitted = hashSetOf<String>()
    private var pending = linkedMapOf<String, Candidate>()
    private val waiters = hashMapOf<String, CompletableDeferred<Unit>>()

    suspend fun update(candidates: List<Candidate>) = mutex.withLock {
        pending = candidates.filterNot { it.id in admitted }.associateByTo(linkedMapOf()) { it.id }
        signal()
    }

    suspend fun acquire(id: String) {
        while (true) {
            val wake = mutex.withLock {
                check(id in pending) { "Ordered child $id is not pending admission" }
                if (pending.values.firstOrNull { it.ready() }?.id == id) {
                    // Serialize permit requests, not execution. Waiting dependencies consume no permit.
                    permits.acquire()
                    admitted += id
                    pending.remove(id)
                    waiters.remove(id)
                    signal()
                    null
                } else waiters[id]?.takeUnless { it.isCompleted }
                    ?: CompletableDeferred<Unit>().also { waiters[id] = it }
            }
            if (wake == null) return
            wake.await()
        }
    }

    suspend fun settled(id: String) = mutex.withLock {
        admitted += id
        pending.remove(id)
        waiters.remove(id)
        signal()
    }

    private fun signal() {
        val next = pending.values.firstOrNull { it.ready() } ?: return
        waiters[next.id]?.complete(Unit)
    }
}
