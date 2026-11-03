package com.galaxyssi.chat

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test

class CollaborationEvidenceRecoverySchedulerTest {
    private fun batch(vararg keys: String) = keys.map { "index:$it" to it }

    @Test fun slowFirstResponseDoesNotBlockLaterMembers(): Unit = runBlocking {
        val slowStarted = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val fastFinished = CompletableDeferred<Unit>()
        val completed = mutableListOf<String>()
        val runner = async {
            CollaborationEvidenceRecoveryScheduler().run(batch("slow", "fast", "last"), {}, { _, e -> throw e }) {
                if (it == "slow") { slowStarted.complete(Unit); release.await() }
                completed += it
                if (it == "last") fastFinished.complete(Unit)
                CollaborationEvidenceSlice.COMPLETE
            }
        }
        try {
            withTimeout(2_000) { slowStarted.await(); fastFinished.await() }
            assertEquals(listOf("fast", "last"), completed)
            assertFalse(runner.isCompleted)
        } finally { release.complete(Unit) }
        runner.await()
        assertEquals(listOf("fast", "last", "slow"), completed)
    }

    @Test fun yieldedArchiveRotatesBehindSmallJobsWithoutRetryingOfflineJob(): Unit = runBlocking {
        val order = mutableListOf<String>()
        var slices = 0
        val claims = mutableListOf<String>()
        CollaborationEvidenceRecoveryScheduler(1).run(batch("large", "offline", "small"), claims::add, { _, e -> throw e }) {
            order += it
            when {
                it == "offline" -> CollaborationEvidenceSlice.DEFERRED
                it == "large" && ++slices < 4 -> CollaborationEvidenceSlice.YIELDED
                else -> CollaborationEvidenceSlice.COMPLETE
            }
        }
        assertEquals(listOf("large", "offline", "small", "large", "large", "large"), order)
        assertEquals(order.map { "index:$it" }, claims)
    }

    @Test fun concurrencyIsBoundedAndCancellationDoesNotClaimUnstartedJobs(): Unit = runBlocking {
        val claims = mutableListOf<String>()
        val bothStarted = CompletableDeferred<Unit>()
        var active = 0
        var maximum = 0
        val runner = async(start = CoroutineStart.UNDISPATCHED) {
            CollaborationEvidenceRecoveryScheduler().run(batch("a", "b", "c"), claims::add, { _, e -> throw e }) {
                active++
                maximum = maxOf(maximum, active)
                if (active == 2) bothStarted.complete(Unit)
                try { awaitCancellation() } finally { active-- }
            }
        }
        withTimeout(2_000) { bothStarted.await() }
        runner.cancelAndJoin()
        assertEquals(2, maximum)
        assertEquals(0, active)
        assertEquals(listOf("index:a", "index:b"), claims)
    }

    @Test fun failedJobDoesNotCancelUnrelatedImportsOrRetryInTheSamePass(): Unit = runBlocking {
        val failures = mutableListOf<String>()
        val completed = mutableListOf<String>()
        CollaborationEvidenceRecoveryScheduler(1).run(batch("broken", "good"), {}, { key, _ -> failures += key }) {
            if (it == "broken") error("Synthetic storage failure")
            completed += it
            CollaborationEvidenceSlice.COMPLETE
        }
        assertEquals(listOf("broken"), failures)
        assertEquals(listOf("good"), completed)
    }

    @Test fun emptyBatchDoesNotClaimOrStartWork(): Unit = runBlocking {
        CollaborationEvidenceRecoveryScheduler().run(emptyList(), { error("No claim") }, { _, e -> throw e }) {
            error("No work")
        }
    }
}
