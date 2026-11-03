package com.galaxyssi.chat

import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test

class AgentSubagentCoordinationAdmissionTest {
    private fun child(id: String, coordination: Boolean = false) = AgentSubagentChild(id,
        executionLane = if (coordination) AgentSubagentExecutionLane.COORDINATION else AgentSubagentExecutionLane.WORK)

    @Test fun budgetsAreSharedAcrossRunsAndCoordinatorsRetainAdmissionOrder() = runBlocking {
        withTimeout(10_000) {
            val workers = AtomicInteger(); val coordinators = AtomicInteger()
            val maxWorkers = AtomicInteger(); val maxCoordinators = AtomicInteger()
            val starts = CopyOnWriteArrayList<String>()
            AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 2, maxCoordinationConcurrency = 1)).use { runtime ->
                (1..4).map { run -> async {
                    val children = (1..4).flatMap { listOf(child("w$it"), child("c$it", true)) }
                    runtime.execute(AgentSubagentPlan("run$run", children, preserveChildOrder = true)) { context ->
                        val coordination = context.childId.startsWith("c")
                        val counter = if (coordination) coordinators else workers
                        val maximum = if (coordination) maxCoordinators else maxWorkers
                        maximum.accumulateAndGet(counter.incrementAndGet(), ::maxOf)
                        starts += "${context.supervisorId}:${context.childId}"
                        try { delay(2); AgentSubagentOutput("done") } finally { counter.decrementAndGet() }
                    }
                } }.awaitAll().forEach { assertEquals(AgentSubagentRunStatus.SUCCEEDED, it.status) }
            }
            assertEquals(2, maxWorkers.get()); assertEquals(1, maxCoordinators.get())
            for (run in 1..4) {
                assertEquals((1..4).map { "run$run:c$it" }, starts.filter { it.startsWith("run$run:c") })
            }
        }
    }

    @Test fun disabledCoordinationCapacityPreservesOriginalSharedLimit() = runBlocking {
        withTimeout(10_000) {
            val active = AtomicInteger(); val maximum = AtomicInteger()
            AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 1)).use { runtime ->
                runtime.execute(AgentSubagentPlan("shared", listOf(child("w"), child("c", true)))) {
                    maximum.accumulateAndGet(active.incrementAndGet(), ::maxOf)
                    try { delay(2); AgentSubagentOutput() } finally { active.decrementAndGet() }
                }
            }
            assertEquals(1, maximum.get())
        }
    }

    @Test fun cancellationWhileCoordinationPermitIsSuspendedDoesNotReleaseWorkerCapacity() = runBlocking {
        withTimeout(10_000) {
            val held = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
            val suspended = CompletableDeferred<Unit>(); val never = CompletableDeferred<Unit>()
            val activeWorkers = AtomicInteger(); val maximum = AtomicInteger()
            AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 1, maxCoordinationConcurrency = 1)).use { runtime ->
                val first = runtime.start(AgentSubagentPlan("first", listOf(child("work"), child("control", true)))) { context ->
                    if (context.childId == "work") {
                        maximum.accumulateAndGet(activeWorkers.incrementAndGet(), ::maxOf)
                        held.complete(Unit)
                        try { release.await() } finally { activeWorkers.decrementAndGet() }
                    } else context.suspendExecutionPermit { suspended.complete(Unit); never.await() }
                    AgentSubagentOutput()
                }
                held.await(); suspended.await()
                val secondStarted = CompletableDeferred<Unit>()
                val second = runtime.start(AgentSubagentPlan("second", listOf(child("control", true)))) {
                    secondStarted.complete(Unit); AgentSubagentOutput()
                }
                secondStarted.await(); assertEquals(AgentSubagentRunStatus.SUCCEEDED, second.await().status)
                first.cancel("test cancellation")
                assertEquals(AgentSubagentRunStatus.CANCELLED, first.await().status)
                runtime.execute(AgentSubagentPlan("after", listOf(child("a"), child("b"), child("c", true)))) { context ->
                    if (context.childId != "c") {
                        maximum.accumulateAndGet(activeWorkers.incrementAndGet(), ::maxOf)
                        try { delay(2) } finally { activeWorkers.decrementAndGet() }
                    }
                    AgentSubagentOutput()
                }
            }
            assertEquals(1, maximum.get())
        }
    }

    @Test fun updatingAdmissionDoesNotWaitForAFullPermitPool() = runBlocking {
        withTimeout(5_000) {
            val permits = Semaphore(1, 1)
            val queue = AgentSubagentOrderedAdmission(permits)
            queue.update(listOf(AgentSubagentOrderedAdmission.Candidate("first") { true }))
            val waiting = launch(start = CoroutineStart.UNDISPATCHED) { queue.acquire("first") }
            queue.update(listOf(AgentSubagentOrderedAdmission.Candidate("first") { true },
                AgentSubagentOrderedAdmission.Candidate("second") { true }))
            waiting.cancel(); waiting.join()
            permits.release()
            queue.acquire("second")
            assertEquals(0, permits.availablePermits)
            permits.release()
        }
    }

    @Test fun suspendedCoordinatorReacquiresItsOwnLaneWhileWorkerStillRuns() = runBlocking {
        withTimeout(10_000) {
            val workerStarted = CompletableDeferred<Unit>(); val releaseWorker = CompletableDeferred<Unit>()
            val suspended = CompletableDeferred<Unit>(); val resume = CompletableDeferred<Unit>()
            val resumed = CompletableDeferred<Unit>(); val secondStarted = CompletableDeferred<Unit>()
            val releaseSecond = CompletableDeferred<Unit>()
            AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 1, maxCoordinationConcurrency = 1)).use { runtime ->
                val first = runtime.start(AgentSubagentPlan("first", listOf(child("worker"), child("control", true)))) { context ->
                    if (context.childId == "worker") {
                        workerStarted.complete(Unit); releaseWorker.await()
                    } else {
                        context.suspendExecutionPermit { suspended.complete(Unit); resume.await() }
                        resumed.complete(Unit)
                    }
                    AgentSubagentOutput()
                }
                try {
                    workerStarted.await(); suspended.await()
                    val second = runtime.start(AgentSubagentPlan("second", listOf(child("control", true)))) {
                        secondStarted.complete(Unit); releaseSecond.await(); AgentSubagentOutput()
                    }
                    secondStarted.await(); resume.complete(Unit)
                    assertFalse(resumed.isCompleted)
                    releaseSecond.complete(Unit); second.await(); resumed.await()
                    assertFalse(releaseWorker.isCompleted)
                    releaseWorker.complete(Unit)
                    assertEquals(AgentSubagentRunStatus.SUCCEEDED, first.await().status)
                } finally { releaseSecond.complete(Unit); releaseWorker.complete(Unit); first.cancel() }
            }
        }
    }

    @Test fun invalidCoordinationBudgetIsRejected() {
        assertThrows(IllegalArgumentException::class.java) { AgentSubagentLimits(maxCoordinationConcurrency = -1) }
        assertThrows(IllegalArgumentException::class.java) {
            AgentSubagentLimits(maxConcurrency = Int.MAX_VALUE, maxCoordinationConcurrency = 1)
        }
    }
}
