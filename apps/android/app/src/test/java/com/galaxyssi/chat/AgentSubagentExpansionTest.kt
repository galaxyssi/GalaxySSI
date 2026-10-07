package com.galaxyssi.chat

import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.ContinuationInterceptor
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class AgentSubagentExpansionTest {
    @Test fun externalWakeDuringPersistenceIsReconciledWithoutAnotherChildCompletion() = runBlocking {
        withTimeout(10_000) {
            val entered = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            val reconciled = CompletableDeferred<Unit>()
            val stopWorker = CompletableDeferred<Unit>()
            val phase = AtomicInteger()
            val runtime = AgentSubagentRuntime(graphExpansion = AgentSubagentExpansionHook { plan, _ ->
                when (phase.get()) {
                    1 -> { entered.complete(Unit); release.await(); phase.compareAndSet(1, 2) }
                    2 -> reconciled.complete(Unit)
                }
                plan
            })
            try {
                val started = CompletableDeferred<Unit>()
                val plan = AgentSubagentPlan("external", listOf(AgentSubagentChild("worker"),
                    AgentSubagentChild("final", dependencies = setOf("worker"))), completionBarrierChildId = "final")
                val handle = runtime.start(plan) { context ->
                    if (context.childId == "worker") { started.complete(Unit); stopWorker.await() }
                    AgentSubagentOutput("done")
                }
                started.await()
                phase.set(1)
                assertTrue(runtime.requestExpansion("external"))
                entered.await()
                repeat(20) { assertTrue(runtime.requestExpansion("external")) }
                release.complete(Unit)
                reconciled.await()
                assertTrue(handle.isActive)
                stopWorker.complete(Unit)
                assertEquals(AgentSubagentRunStatus.SUCCEEDED, handle.await().status)
                assertFalse(runtime.requestExpansion("external"))
            } finally { release.complete(Unit); stopWorker.complete(Unit); runtime.shutdown() }
        }
    }

    @Test
    fun dynamicReviewFinishesWhileUnrelatedSlowChildIsHeldAndBarrierIncludesEverything() = runBlocking {
        val slowStarted = CompletableDeferred<Unit>()
        val releaseSlow = CompletableDeferred<Unit>()
        val reviewProcessed = CompletableDeferred<Unit>()
        val barrierHandoff = CompletableDeferred<AgentSubagentContextHandoff>()
        val durableIds = Collections.synchronizedSet(mutableSetOf<String>())
        val runtime = AgentSubagentRuntime(
            limits = AgentSubagentLimits(maxConcurrency = 2),
            eventHook = AgentSubagentEventHook { event ->
                event.result?.let { durableIds += it.childId }
            },
            graphExpansion = AgentSubagentExpansionHook { plan, completed ->
                assertTrue(durableIds.containsAll(completed.keys))
                if ("review" in completed) reviewProcessed.complete(Unit)
                if ("fast" in completed) appendReview(plan) else plan
            }
        )
        try {
            val handle = runtime.start(plan()) { context ->
                when (context.childId) {
                    "fast" -> {
                        slowStarted.await()
                        AgentSubagentOutput("fast evidence")
                    }
                    "slow" -> {
                        slowStarted.complete(Unit)
                        releaseSlow.await()
                        AgentSubagentOutput("slow evidence")
                    }
                    "review" -> {
                        assertEquals("fast evidence", context.dependency("fast")?.output)
                        AgentSubagentOutput("dynamic review")
                    }
                    else -> {
                        barrierHandoff.complete(context.handoff)
                        AgentSubagentOutput("final")
                    }
                }
            }
            withTimeout(TIMEOUT) { reviewProcessed.await() }
            assertFalse(releaseSlow.isCompleted)
            assertFalse(barrierHandoff.isCompleted)
            assertTrue(handle.isActive)
            releaseSlow.complete(Unit)
            val result = withTimeout(TIMEOUT) { handle.await() }
            assertEquals(AgentSubagentRunStatus.SUCCEEDED, result.status)
            assertEquals(setOf("fast", "slow", "review", "final"), result.results.map { it.childId }.toSet())
            val evidence = barrierHandoff.await().dependencies.associate { it.childId to it.output }
            assertEquals(mapOf("fast" to "fast evidence", "slow" to "slow evidence", "review" to "dynamic review"), evidence)
        } finally {
            runtime.shutdown()
        }
    }

    @Test
    fun serialHookCoalescesCompletionsDuringExpansionWithoutHoldingOnlyPermitOrEventLock() = runBlocking {
        val hookEntered = CompletableDeferred<Unit>()
        val releaseHook = CompletableDeferred<Unit>()
        val releaseRemaining = CompletableDeferred<Unit>()
        val remainingDurable = CompletableDeferred<Unit>()
        val durableCount = AtomicInteger(0)
        val activeHooks = AtomicInteger(0)
        val snapshots = mutableListOf<Set<String>>()
        val runtime = AgentSubagentRuntime(
            limits = AgentSubagentLimits(maxConcurrency = 1),
            dispatcher = coroutineContext[ContinuationInterceptor] as CoroutineDispatcher,
            eventHook = AgentSubagentEventHook { event ->
                if (event.result != null && event.childId in setOf("b", "c") && durableCount.incrementAndGet() == 2) {
                    remainingDurable.complete(Unit)
                }
            },
            graphExpansion = AgentSubagentExpansionHook { plan, completed ->
                assertEquals(1, activeHooks.incrementAndGet())
                try {
                    snapshots += completed.keys.toSet()
                    if (completed.keys == setOf("a")) {
                        hookEntered.complete(Unit)
                        releaseHook.await()
                    }
                    plan
                } finally {
                    activeHooks.decrementAndGet()
                }
            }
        )
        try {
            val handle = runtime.start(plan().copy(children = listOf(
                AgentSubagentChild("a"), AgentSubagentChild("b"), AgentSubagentChild("c"),
                AgentSubagentChild("final")
            ))) { context ->
                if (context.childId in setOf("b", "c")) releaseRemaining.await()
                if (context.childId == "final") {
                    assertEquals(setOf("a", "b", "c"), snapshots.last())
                    assertEquals(setOf("a", "b", "c"), context.handoff.dependencies.map { it.childId }.toSet())
                }
                AgentSubagentOutput(context.childId)
            }
            withTimeout(TIMEOUT) { hookEntered.await() }
            releaseRemaining.complete(Unit)
            withTimeout(TIMEOUT) { remainingDurable.await() }
            yield()
            assertEquals(1, activeHooks.get())
            releaseHook.complete(Unit)
            assertEquals(AgentSubagentRunStatus.SUCCEEDED, withTimeout(TIMEOUT) { handle.await() }.status)
            assertEquals(listOf(emptySet<String>(), setOf("a"), setOf("a", "b", "c"), setOf("a", "b", "c", "final")), snapshots)
        } finally {
            runtime.shutdown()
        }
    }

    @Test
    fun appendedChildWaitsForBothTerminalAndGraphPersistenceBeforeQueueing() = runBlocking {
        val terminalEntered = CompletableDeferred<Unit>()
        val releaseTerminal = CompletableDeferred<Unit>()
        val expansionEntered = CompletableDeferred<Unit>()
        val releaseExpansion = CompletableDeferred<Unit>()
        val reviewQueued = CompletableDeferred<Unit>()
        val reviewRan = CompletableDeferred<Unit>()
        val releaseSlow = CompletableDeferred<Unit>()
        val order = Collections.synchronizedList(mutableListOf<String>())
        val runtime = AgentSubagentRuntime(
            eventHook = AgentSubagentEventHook { event ->
                if (event.childId == "fast" && event.kind == AgentSubagentEventKinds.CHILD_SUCCEEDED) {
                    terminalEntered.complete(Unit)
                    releaseTerminal.await()
                    order += "terminal-durable"
                }
                if (event.childId == "review" && event.kind == AgentSubagentEventKinds.CHILD_QUEUED) {
                    assertTrue("graph-durable" in order)
                    order += "review-queued"
                    reviewQueued.complete(Unit)
                }
            },
            graphExpansion = AgentSubagentExpansionHook { current, completed ->
                if ("fast" in completed && current.children.none { it.childId == "review" }) {
                    assertTrue("terminal-durable" in order)
                    expansionEntered.complete(Unit)
                    releaseExpansion.await()
                    order += "graph-durable"
                    appendReview(current)
                } else current
            }
        )
        try {
            val handle = runtime.start(plan()) {
                when (it.childId) {
                    "slow" -> releaseSlow.await()
                    "review" -> {
                        assertTrue(reviewQueued.isCompleted)
                        order += "review-ran"
                        reviewRan.complete(Unit)
                    }
                }
                AgentSubagentOutput(it.childId)
            }
            withTimeout(TIMEOUT) { terminalEntered.await() }
            assertFalse(expansionEntered.isCompleted)
            assertFalse(reviewQueued.isCompleted)
            releaseTerminal.complete(Unit)
            withTimeout(TIMEOUT) { expansionEntered.await() }
            assertFalse(reviewQueued.isCompleted)
            releaseExpansion.complete(Unit)
            withTimeout(TIMEOUT) { reviewRan.await() }
            releaseSlow.complete(Unit)
            assertEquals(AgentSubagentRunStatus.SUCCEEDED, withTimeout(TIMEOUT) { handle.await() }.status)
            assertEquals(listOf("terminal-durable", "graph-durable", "review-queued", "review-ran"), order)
        } finally {
            releaseTerminal.complete(Unit)
            releaseExpansion.complete(Unit)
            releaseSlow.complete(Unit)
            runtime.shutdown()
        }
    }

    @Test
    fun stopWhileAppendedQueueWaitsOnEventMutexPreventsQueueAndExecution() = runBlocking {
        for (stop in listOf("cancel", "fail-fast", "storage-failure")) {
            val expansionEntered = CompletableDeferred<Unit>()
            val releaseExpansion = CompletableDeferred<Unit>()
            val graphReturned = CompletableDeferred<Unit>()
            val releaseSlow = CompletableDeferred<Unit>()
            val terminalEntered = CompletableDeferred<Unit>()
            val releaseTerminal = CompletableDeferred<Unit>()
            val events = mutableListOf<AgentSubagentEvent>()
            val invoked = mutableListOf<String>()
            val runtime = AgentSubagentRuntime(
                dispatcher = coroutineContext[ContinuationInterceptor] as CoroutineDispatcher,
                eventHook = AgentSubagentEventHook { event ->
                    if (event.childId == "slow" && event.result != null) {
                        terminalEntered.complete(Unit)
                        withContext(NonCancellable) { releaseTerminal.await() }
                        if (stop == "storage-failure") error("terminal persistence failed")
                    }
                    events += event
                },
                graphExpansion = AgentSubagentExpansionHook { current, completed ->
                    if ("fast" in completed && current.children.none { it.childId == "review" }) {
                        expansionEntered.complete(Unit)
                        releaseExpansion.await()
                        graphReturned.complete(Unit)
                        appendReview(current)
                    } else current
                }
            )
            try {
                val initial = plan().copy(failurePolicy = if (stop == "fail-fast")
                    AgentSubagentFailurePolicy.FAIL_FAST else AgentSubagentFailurePolicy.CONTINUE)
                val handle = runtime.start(initial) {
                    invoked += it.childId
                    if (it.childId == "slow") {
                        releaseSlow.await()
                        if (stop == "fail-fast") error("fatal slow child")
                    }
                    AgentSubagentOutput(it.childId)
                }
                withTimeout(TIMEOUT) { expansionEntered.await() }
                releaseSlow.complete(Unit)
                withTimeout(TIMEOUT) { terminalEntered.await() }
                releaseExpansion.complete(Unit)
                withTimeout(TIMEOUT) { graphReturned.await() }
                yield()
                if (stop == "cancel") assertTrue(handle.cancel("stop queued expansion"))
                releaseTerminal.complete(Unit)
                if (stop == "storage-failure") {
                    assertEquals("terminal persistence failed", expectFailure<IllegalStateException> { handle.await() }.message)
                } else {
                    val expected = if (stop == "fail-fast") AgentSubagentRunStatus.FAILED else AgentSubagentRunStatus.CANCELLED
                    assertEquals(expected, withTimeout(TIMEOUT) { handle.await() }.status)
                }
                assertTrue(stop, events.none { it.childId == "review" && it.kind == AgentSubagentEventKinds.CHILD_QUEUED })
                assertFalse(stop, "review" in invoked)
                assertFalse(stop, "final" in invoked)
                assertTrue(stop, events.none { it.kind == AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED })
            } finally {
                releaseExpansion.complete(Unit)
                releaseTerminal.complete(Unit)
                releaseSlow.complete(Unit)
                runtime.shutdown()
            }
        }
    }

    @Test
    fun cancellationDuringQueuePersistenceDoesNotStartTheAppendedWorker() = runBlocking {
        val queueEntered = CompletableDeferred<Unit>()
        val releaseQueue = CompletableDeferred<Unit>()
        val invoked = Collections.synchronizedList(mutableListOf<String>())
        val runtime = AgentSubagentRuntime(
            eventHook = AgentSubagentEventHook { event ->
                if (event.childId == "review" && event.kind == AgentSubagentEventKinds.CHILD_QUEUED) {
                    queueEntered.complete(Unit)
                    withContext(NonCancellable) { releaseQueue.await() }
                }
            },
            graphExpansion = AgentSubagentExpansionHook { current, completed ->
                if ("fast" in completed) appendReview(current) else current
            }
        )
        try {
            val handle = runtime.start(plan()) {
                invoked += it.childId
                AgentSubagentOutput(it.childId)
            }
            withTimeout(TIMEOUT) { queueEntered.await() }
            assertTrue(handle.cancel("stop in-flight queue persistence"))
            releaseQueue.complete(Unit)
            assertEquals(AgentSubagentRunStatus.CANCELLED, withTimeout(TIMEOUT) { handle.await() }.status)
            assertFalse("review" in invoked)
            assertFalse("final" in invoked)
        } finally {
            releaseQueue.complete(Unit)
            runtime.shutdown()
        }
    }

    @Test
    fun recoveryExpandsFromDurableResultsAndNeverReexecutesRestoredChildren() = runBlocking {
        for (reviewAlreadyDurable in listOf(false, true)) {
            val initial = if (reviewAlreadyDurable) appendReview(plan()) else plan()
            val restoredIds = if (reviewAlreadyDurable) setOf("fast", "review") else setOf("fast")
            val restored = restoredIds.associateWith { result(it, "persisted $it") }
            val invoked = Collections.synchronizedList(mutableListOf<String>())
            val snapshots = Collections.synchronizedList(mutableListOf<Set<String>>())
            val events = Collections.synchronizedList(mutableListOf<AgentSubagentEvent>())
            val runtime = AgentSubagentRuntime(
                eventHook = AgentSubagentEventHook { events += it },
                graphExpansion = AgentSubagentExpansionHook { current, completed ->
                    snapshots += completed.keys.toSet()
                    appendReview(current)
                }
            )
            try {
                val handle = runtime.resume(initial, restored, 20L) { context ->
                    invoked += context.childId
                    if (context.childId == "final") {
                        assertEquals("persisted fast", context.dependency("fast")?.output)
                        assertEquals(setOf("fast", "slow", "review"), context.handoff.dependencies.map { it.childId }.toSet())
                    }
                    AgentSubagentOutput("new ${context.childId}")
                }
                val outcome = withTimeout(TIMEOUT) { handle.await() }
                assertEquals(AgentSubagentRunStatus.SUCCEEDED, outcome.status)
                assertEquals(restoredIds, snapshots.first())
                assertTrue(invoked.none { it in restoredIds })
                assertEquals(invoked.size, invoked.distinct().size)
                assertEquals(21L, events.first().sequence)
                assertTrue(events.none { it.childId in restoredIds })
            } finally {
                runtime.shutdown()
            }
        }
    }

    @Test
    fun configuredHookDoesNotChangeStaticStartOrResumeWithoutAnExplicitBarrier() = runBlocking {
        for (resume in listOf(false, true)) {
            val slowStarted = CompletableDeferred<Unit>()
            val finalStarted = CompletableDeferred<Unit>()
            val releaseSlow = CompletableDeferred<Unit>()
            val hookCalls = AtomicInteger(0)
            val invoked = Collections.synchronizedList(mutableListOf<String>())
            val runtime = AgentSubagentRuntime(graphExpansion = AgentSubagentExpansionHook { _, _ ->
                hookCalls.incrementAndGet()
                error("Unflagged plans must not invoke the hook")
            })
            try {
                val initial = plan().copy(completionBarrierChildId = " ")
                    .changeChild("final") { it.copy(dependencies = setOf("fast")) }
                val worker = AgentSubagentWorker {
                    invoked += it.childId
                    when (it.childId) {
                        "slow" -> {
                            slowStarted.complete(Unit)
                            releaseSlow.await()
                        }
                        "final" -> {
                            slowStarted.await()
                            finalStarted.complete(Unit)
                        }
                    }
                    AgentSubagentOutput(it.childId)
                }
                val handle = if (resume) runtime.resume(initial, mapOf("fast" to result("fast", "saved")), 20L, worker)
                    else runtime.start(initial, worker)
                withTimeout(TIMEOUT) { finalStarted.await() }
                assertFalse(releaseSlow.isCompleted)
                releaseSlow.complete(Unit)
                assertEquals(AgentSubagentRunStatus.SUCCEEDED, withTimeout(TIMEOUT) { handle.await() }.status)
                assertEquals(0, hookCalls.get())
                assertEquals(if (resume) 0 else 1, invoked.count { it == "fast" })
            } finally {
                runtime.shutdown()
            }
        }
    }

    @Test
    fun configuredHookDoesNotEscalateLegacyChildCancellation() = runBlocking {
        val runtime = AgentSubagentRuntime(graphExpansion = AgentSubagentExpansionHook { _, _ ->
            error("Unflagged plans must not invoke the hook")
        })
        try {
            val initial = plan().copy(completionBarrierChildId = "", children = listOf(
                AgentSubagentChild("fast"),
                AgentSubagentChild("final", dependencies = setOf("fast"),
                    dependencyPolicy = AgentSubagentDependencyPolicy.ALLOW_TERMINAL)
            ))
            val handle = runtime.start(initial) {
                if (it.childId == "fast") throw CancellationException("one child stopped")
                AgentSubagentOutput("static dependent still ran")
            }
            val outcome = withTimeout(TIMEOUT) { handle.await() }
            assertEquals(AgentSubagentRunStatus.CANCELLED, outcome.status)
            assertEquals(AgentSubagentStatus.SUCCEEDED, outcome["final"]?.status)
        } finally {
            runtime.shutdown()
        }
    }

    @Test
    fun continuePolicyExpandsFailedEvidenceAndBarrierReceivesSkippedAndDynamicResults() = runBlocking {
        val handoff = CompletableDeferred<AgentSubagentContextHandoff>()
        val runtime = AgentSubagentRuntime(graphExpansion = AgentSubagentExpansionHook { current, completed ->
            if ("fast" in completed && current.children.none { it.childId == "review" }) {
                current.copy(children = current.children + AgentSubagentChild("review", dependencies = setOf("fast"),
                    dependencyPolicy = AgentSubagentDependencyPolicy.ALLOW_TERMINAL))
            } else current
        })
        try {
            val initial = plan().copy(children = plan().children + AgentSubagentChild("skipped", dependencies = setOf("fast")))
            val handle = runtime.start(initial) {
                when (it.childId) {
                    "fast" -> error("recoverable failure")
                    "skipped" -> error("skipped worker must not run")
                    "review" -> assertEquals(AgentSubagentStatus.FAILED, it.dependency("fast")?.status)
                    "final" -> handoff.complete(it.handoff)
                }
                AgentSubagentOutput(it.childId)
            }
            val outcome = withTimeout(TIMEOUT) { handle.await() }
            assertEquals(AgentSubagentRunStatus.COMPLETED_WITH_FAILURES, outcome.status)
            assertEquals(AgentSubagentStatus.SUCCEEDED, outcome["review"]?.status)
            val evidence = handoff.await().dependencies.associate { it.childId to it.status }
            assertEquals(setOf("fast", "slow", "skipped", "review"), evidence.keys)
            assertEquals(AgentSubagentStatus.FAILED, evidence["fast"])
            assertEquals(AgentSubagentStatus.SKIPPED, evidence["skipped"])
        } finally {
            runtime.shutdown()
        }
    }

    @Test
    fun fullyCompletedRecoveryStillCallsHookWithoutReexecutingBarrier() = runBlocking {
        val snapshots = Collections.synchronizedList(mutableListOf<Set<String>>())
        val invoked = AtomicInteger(0)
        val restored = plan().children.associate { it.childId to result(it.childId, "persisted") }
        val runtime = AgentSubagentRuntime(graphExpansion = AgentSubagentExpansionHook { current, completed ->
            snapshots += completed.keys.toSet()
            current
        })
        try {
            val handle = runtime.resume(plan(), restored, 20L) { invoked.incrementAndGet(); AgentSubagentOutput() }
            assertEquals(AgentSubagentRunStatus.SUCCEEDED, withTimeout(TIMEOUT) { handle.await() }.status)
            assertEquals(listOf(restored.keys), snapshots)
            assertEquals(0, invoked.get())
        } finally {
            runtime.shutdown()
        }
    }

    @Test
    fun rejectsIdentityRewritesRemovalsBarrierDependencyDropsAndInvalidGraphsBeforeExecution() = runBlocking {
        val changes: List<Pair<String, (AgentSubagentPlan) -> AgentSubagentPlan>> = listOf(
            "supervisor" to { it.copy(supervisorId = "different") },
            "provenance" to { it.copy(provenance = AgentSubagentProvenance(source = "changed")) },
            "failure policy" to { it.copy(failurePolicy = AgentSubagentFailurePolicy.FAIL_FAST) },
            "barrier identity" to { it.copy(completionBarrierChildId = "") },
            "remove child" to { it.copy(children = it.children.filterNot { child -> child.childId == "fast" }
                .map { child -> child.copy(dependencies = child.dependencies - "fast") }) },
            "rewrite context" to { current -> current.changeChild("fast") { it.copy(context = "changed") } },
            "rewrite provenance" to { current -> current.changeChild("fast") {
                it.copy(provenance = AgentSubagentProvenance(sourceId = "changed"))
            } },
            "rewrite parent" to { current -> current.changeChild("fast") { it.copy(parentId = "slow") } },
            "rewrite dependency" to { current -> current.changeChild("fast") { it.copy(dependencies = setOf("slow")) } },
            "drop barrier dependency" to { current -> current.changeChild("final") { it.copy(dependencies = setOf("fast")) } },
            "rewrite barrier context" to { current -> current.changeChild("final") { it.copy(context = "changed") } },
            "depend on barrier" to { it.copy(children = it.children + AgentSubagentChild("new", dependencies = setOf("final"))) },
            "unknown dependency" to { it.copy(children = it.children + AgentSubagentChild("new", dependencies = setOf("missing"))) },
            "cycle" to { it.copy(children = it.children + listOf(
                AgentSubagentChild("x", dependencies = setOf("y")),
                AgentSubagentChild("y", dependencies = setOf("x"))
            )) },
            "parent cycle" to { it.copy(children = it.children + listOf(
                AgentSubagentChild("x", parentId = "y"), AgentSubagentChild("y", parentId = "x")
            )) },
            "duplicate" to { it.copy(children = it.children + AgentSubagentChild("fast")) }
        )
        for ((label, change) in changes) {
            assertRejected(label, AgentSubagentLimits(), change)
        }
        assertRejected("maxChildren", AgentSubagentLimits(maxChildren = 3)) {
            it.copy(children = it.children + AgentSubagentChild("new"))
        }
        assertRejected("maxDepth", AgentSubagentLimits(maxDepth = 1)) {
            it.copy(children = it.children + AgentSubagentChild("new", parentId = "fast"))
        }
    }

    @Test
    fun completionBarrierCannotBeExpandedAfterItRuns() = runBlocking {
        val invoked = Collections.synchronizedList(mutableListOf<String>())
        val events = Collections.synchronizedList(mutableListOf<AgentSubagentEvent>())
        val runtime = AgentSubagentRuntime(
            eventHook = AgentSubagentEventHook { events += it },
            graphExpansion = AgentSubagentExpansionHook { current, completed ->
                if ("final" in completed) current.copy(children = current.children + AgentSubagentChild("too-late"))
                else current
            }
        )
        try {
            val handle = runtime.start(plan()) {
                invoked += it.childId
                AgentSubagentOutput()
            }
            expectFailure<IllegalArgumentException> { handle.await() }
            assertEquals(1, invoked.count { it == "final" })
            assertFalse("too-late" in invoked)
            assertTrue(events.none { it.kind == AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED })
        } finally {
            runtime.shutdown()
        }
    }

    @Test
    fun noHookPreservesStaticExecutionEvenWhenBarrierFieldIsPresent() = runBlocking {
        val finalStarted = CompletableDeferred<Unit>()
        val releaseSlow = CompletableDeferred<Unit>()
        val runtime = AgentSubagentRuntime(limits = AgentSubagentLimits(maxConcurrency = 2))
        try {
            val handle = runtime.start(plan().copy(children = listOf(
                AgentSubagentChild("slow"), AgentSubagentChild("final")
            ))) {
                if (it.childId == "slow") releaseSlow.await() else finalStarted.complete(Unit)
                AgentSubagentOutput()
            }
            withTimeout(TIMEOUT) { finalStarted.await() }
            assertFalse(releaseSlow.isCompleted)
            releaseSlow.complete(Unit)
            assertEquals(AgentSubagentRunStatus.SUCCEEDED, withTimeout(TIMEOUT) { handle.await() }.status)
        } finally {
            runtime.shutdown()
        }
    }

    @Test
    fun cancellationInterruptsInitialRecoveryHookWithoutStartingChildren() = runBlocking {
        val entered = CompletableDeferred<Unit>()
        val calls = AtomicInteger(0)
        val runtime = AgentSubagentRuntime(graphExpansion = AgentSubagentExpansionHook { _, _ ->
            entered.complete(Unit)
            awaitCancellation()
        })
        try {
            val handle = runtime.start(plan()) { calls.incrementAndGet(); AgentSubagentOutput() }
            withTimeout(TIMEOUT) { entered.await() }
            assertTrue(handle.cancel("cancel recovery"))
            assertEquals(AgentSubagentRunStatus.CANCELLED, withTimeout(TIMEOUT) { handle.await() }.status)
            assertEquals(0, calls.get())
        } finally {
            runtime.shutdown()
        }
    }

    @Test
    fun cancellationDiscardsExpansionReturnedByNonCancellableStorageHook() = runBlocking {
        val slowStarted = CompletableDeferred<Unit>()
        val entered = CompletableDeferred<Unit>()
        val releaseHook = CompletableDeferred<Unit>()
        val invoked = Collections.synchronizedList(mutableListOf<String>())
        val events = Collections.synchronizedList(mutableListOf<AgentSubagentEvent>())
        val runtime = AgentSubagentRuntime(
            eventHook = AgentSubagentEventHook { events += it },
            graphExpansion = AgentSubagentExpansionHook { current, completed ->
                if ("fast" in completed) {
                    entered.complete(Unit)
                    withContext(NonCancellable) { releaseHook.await() }
                    appendReview(current)
                } else current
            }
        )
        try {
            val handle = runtime.start(plan()) {
                invoked += it.childId
                if (it.childId == "slow") {
                    slowStarted.complete(Unit)
                    awaitCancellation()
                }
                slowStarted.await()
                AgentSubagentOutput("fast")
            }
            withTimeout(TIMEOUT) { entered.await() }
            handle.cancel("stop expansion")
            releaseHook.complete(Unit)
            val outcome = withTimeout(TIMEOUT) { handle.await() }
            assertEquals(AgentSubagentRunStatus.CANCELLED, outcome.status)
            assertFalse("review" in invoked)
            assertFalse("final" in invoked)
            assertTrue(events.none { it.kind == AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED })
        } finally {
            releaseHook.complete(Unit)
            runtime.shutdown()
        }
    }

    @Test
    fun workerCancellationInterruptsExpansionBeforeDependentOrAppendedWorkStarts() = runBlocking {
        val entered = CompletableDeferred<Unit>()
        val cancelSlow = CompletableDeferred<Unit>()
        val invoked = Collections.synchronizedList(mutableListOf<String>())
        val runtime = AgentSubagentRuntime(graphExpansion = AgentSubagentExpansionHook { current, completed ->
            if ("fast" in completed) {
                entered.complete(Unit)
                awaitCancellation()
            }
            current
        })
        try {
            val initial = plan().copy(children = plan().children + AgentSubagentChild("dependent",
                dependencies = setOf("slow"), dependencyPolicy = AgentSubagentDependencyPolicy.ALLOW_TERMINAL))
            val handle = runtime.start(initial) {
                invoked += it.childId
                if (it.childId == "slow") {
                    cancelSlow.await()
                    throw CancellationException("worker stopped")
                }
                AgentSubagentOutput("fast")
            }
            withTimeout(TIMEOUT) { entered.await() }
            cancelSlow.complete(Unit)
            val outcome = withTimeout(TIMEOUT) { handle.await() }
            assertEquals(AgentSubagentRunStatus.CANCELLED, outcome.status)
            assertFalse("dependent" in invoked)
            assertFalse("final" in invoked)
        } finally {
            runtime.shutdown()
        }
    }

    @Test
    fun failFastInterruptsExpansionAndDoesNotStartBarrierOrAppendedWork() = runBlocking {
        val entered = CompletableDeferred<Unit>()
        val releaseFailure = CompletableDeferred<Unit>()
        val invoked = Collections.synchronizedList(mutableListOf<String>())
        val runtime = AgentSubagentRuntime(graphExpansion = AgentSubagentExpansionHook { current, completed ->
            if ("fast" in completed) {
                entered.complete(Unit)
                awaitCancellation()
            }
            current
        })
        try {
            val handle = runtime.start(plan().copy(failurePolicy = AgentSubagentFailurePolicy.FAIL_FAST)) {
                invoked += it.childId
                if (it.childId == "slow") {
                    releaseFailure.await()
                    error("fatal child")
                }
                AgentSubagentOutput("fast")
            }
            withTimeout(TIMEOUT) { entered.await() }
            releaseFailure.complete(Unit)
            val outcome = withTimeout(TIMEOUT) { handle.await() }
            assertEquals(AgentSubagentRunStatus.FAILED, outcome.status)
            assertEquals(AgentSubagentStatus.FAILED, outcome["slow"]?.status)
            assertFalse("final" in invoked)
        } finally {
            runtime.shutdown()
        }
    }

    @Test
    fun eventStorageFailureNeverReachesExpansionAsDurableEvidenceOrReportsSuccess() = runBlocking {
        val slowStarted = CompletableDeferred<Unit>()
        val snapshots = Collections.synchronizedList(mutableListOf<Set<String>>())
        val invoked = Collections.synchronizedList(mutableListOf<String>())
        val runtime = AgentSubagentRuntime(
            eventHook = AgentSubagentEventHook { event ->
                if (event.kind == AgentSubagentEventKinds.CHILD_SUCCEEDED && event.childId == "fast") {
                    error("event storage unavailable")
                }
            },
            graphExpansion = AgentSubagentExpansionHook { current, completed ->
                snapshots += completed.keys.toSet()
                if ("fast" in completed) appendReview(current) else current
            }
        )
        try {
            val handle = runtime.start(plan()) {
                invoked += it.childId
                if (it.childId == "slow") {
                    slowStarted.complete(Unit)
                    awaitCancellation()
                }
                slowStarted.await()
                AgentSubagentOutput("fast")
            }
            val failure = expectFailure<IllegalStateException> { handle.await() }
            assertTrue(failure.message.orEmpty().contains("event storage unavailable"))
            assertEquals(listOf(emptySet<String>()), snapshots)
            assertFalse("review" in invoked)
            assertFalse("final" in invoked)
        } finally {
            runtime.shutdown()
        }
    }

    @Test
    fun expansionStorageFailureCancelsUnrelatedWorkAndNeverStartsNewNodes() = runBlocking {
        val slowStarted = CompletableDeferred<Unit>()
        val slowStopped = CompletableDeferred<Unit>()
        val invoked = Collections.synchronizedList(mutableListOf<String>())
        val events = Collections.synchronizedList(mutableListOf<AgentSubagentEvent>())
        val runtime = AgentSubagentRuntime(
            eventHook = AgentSubagentEventHook { events += it },
            graphExpansion = AgentSubagentExpansionHook { current, completed ->
                if ("fast" in completed) error("graph storage unavailable")
                current
            }
        )
        try {
            val handle = runtime.start(plan()) {
                invoked += it.childId
                if (it.childId == "slow") {
                    slowStarted.complete(Unit)
                    try { awaitCancellation() } finally { slowStopped.complete(Unit) }
                }
                slowStarted.await()
                AgentSubagentOutput("fast")
            }
            val failure = expectFailure<IllegalStateException> { handle.await() }
            assertEquals("graph storage unavailable", failure.message)
            assertTrue(slowStopped.isCompleted)
            assertFalse("review" in invoked)
            assertFalse("final" in invoked)
            assertTrue(events.none { it.kind == AgentSubagentEventKinds.CHILD_CANCELLED })
            assertTrue(events.none { it.runStatus != null })
        } finally {
            runtime.shutdown()
        }
    }

    @Test
    fun committedExpansionThenThrowRemainsResumableWithoutReplayingCompletedSideEffects() = runBlocking {
        for (slowReturnsObservationOnInterrupt in listOf(false, true)) {
            val storedPlan = AtomicReference(plan())
            val durableCompleted = ConcurrentHashMap<String, AgentSubagentChildResult>()
            val events = Collections.synchronizedList(mutableListOf<AgentSubagentEvent>())
            val slowStarted = CompletableDeferred<Unit>()
            val fastEffects = AtomicInteger(0)
            val slowStarts = AtomicInteger(0)
            val slowEffects = AtomicInteger(0)
            val reviewEffects = AtomicInteger(0)
            val finalEffects = AtomicInteger(0)
            val runtime = AgentSubagentRuntime(
                eventHook = AgentSubagentEventHook { event ->
                    events += event
                    event.result?.let { durableCompleted[it.childId] = it }
                },
                graphExpansion = AgentSubagentExpansionHook { current, completed ->
                    if ("fast" in completed && current.children.none { it.childId == "review" }) {
                        storedPlan.set(appendReview(current))
                        error("graph committed before hook failure")
                    }
                    current
                }
            )
            val worker = AgentSubagentWorker { context ->
                when (context.childId) {
                    "fast" -> {
                        slowStarted.await()
                        fastEffects.incrementAndGet()
                        AgentSubagentOutput("durable fast")
                    }
                    "slow" -> {
                        if (slowStarts.incrementAndGet() == 1) {
                            slowStarted.complete(Unit)
                            try {
                                awaitCancellation()
                            } catch (cancelled: CancellationException) {
                                if (!slowReturnsObservationOnInterrupt) throw cancelled
                            }
                        }
                        slowEffects.incrementAndGet()
                        AgentSubagentOutput("durable slow")
                    }
                    "review" -> {
                        assertEquals("durable fast", context.dependency("fast")?.output)
                        reviewEffects.incrementAndGet()
                        AgentSubagentOutput("durable review")
                    }
                    else -> {
                        assertEquals("durable fast", context.dependency("fast")?.output)
                        assertEquals("durable slow", context.dependency("slow")?.output)
                        assertEquals("durable review", context.dependency("review")?.output)
                        finalEffects.incrementAndGet()
                        AgentSubagentOutput("final")
                    }
                }
            }
            try {
                val first = runtime.start(storedPlan.get(), worker)
                assertEquals("graph committed before hook failure", expectFailure<IllegalStateException> { first.await() }.message)
                assertTrue(storedPlan.get().children.any { it.childId == "review" })
                assertTrue("review" in storedPlan.get().children.single { it.childId == "final" }.dependencies)
                assertEquals(if (slowReturnsObservationOnInterrupt) setOf("fast", "slow") else setOf("fast"), durableCompleted.keys)
                assertTrue(events.none { it.kind == AgentSubagentEventKinds.CHILD_CANCELLED || it.runStatus != null })
                assertEquals(0, reviewEffects.get())
                assertEquals(0, finalEffects.get())

                val resumed = runtime.resume(storedPlan.get(), durableCompleted.toMap(), events.last().sequence, worker)
                val outcome = withTimeout(TIMEOUT) { resumed.await() }
                assertEquals(AgentSubagentRunStatus.SUCCEEDED, outcome.status)
                assertEquals(1, fastEffects.get())
                assertEquals(1, slowEffects.get())
                assertEquals(if (slowReturnsObservationOnInterrupt) 1 else 2, slowStarts.get())
                assertEquals(1, reviewEffects.get())
                assertEquals(1, finalEffects.get())
                assertEquals(1, events.count { it.childId == "fast" && it.kind == AgentSubagentEventKinds.CHILD_SUCCEEDED })
                assertEquals(1, events.count { it.childId == "slow" && it.kind == AgentSubagentEventKinds.CHILD_SUCCEEDED })
            } finally {
                runtime.shutdown()
            }
        }
    }

    private suspend fun assertRejected(
        label: String,
        limits: AgentSubagentLimits,
        change: (AgentSubagentPlan) -> AgentSubagentPlan
    ) {
        val invoked = AtomicInteger(0)
        val runtime = AgentSubagentRuntime(limits = limits,
            graphExpansion = AgentSubagentExpansionHook { current, _ -> change(current) })
        try {
            val handle = runtime.start(plan()) { invoked.incrementAndGet(); AgentSubagentOutput() }
            expectFailure<IllegalArgumentException> { handle.await() }
            assertEquals(label, 0, invoked.get())
        } finally {
            runtime.shutdown()
        }
    }

    private suspend inline fun <reified T : Throwable> expectFailure(crossinline block: suspend () -> Unit): T {
        try {
            withTimeout(TIMEOUT) { block() }
        } catch (failure: Throwable) {
            if (failure is T) return failure
            throw failure
        }
        fail("Expected ${T::class.java.simpleName}")
        error("unreachable")
    }

    private fun plan() = AgentSubagentPlan(
        supervisorId = "expansion-run",
        children = listOf(
            AgentSubagentChild("fast"), AgentSubagentChild("slow"),
            AgentSubagentChild("final", dependencies = setOf("fast", "slow"),
                dependencyPolicy = AgentSubagentDependencyPolicy.ALLOW_TERMINAL)
        ),
        completionBarrierChildId = "final"
    )

    private fun appendReview(plan: AgentSubagentPlan): AgentSubagentPlan {
        if (plan.children.any { it.childId == "review" }) return plan
        return plan.copy(children = plan.children + AgentSubagentChild("review", dependencies = setOf("fast")))
            .changeChild("final") { it.copy(dependencies = it.dependencies + "review") }
    }

    private fun AgentSubagentPlan.changeChild(id: String, change: (AgentSubagentChild) -> AgentSubagentChild) =
        copy(children = children.map { if (it.childId == id) change(it) else it })

    private fun result(id: String, output: String) = AgentSubagentChildResult(
        supervisorId = "expansion-run", childId = id, parentId = "expansion-run", depth = 1,
        status = AgentSubagentStatus.SUCCEEDED, output = output
    )

    private companion object {
        const val TIMEOUT = 5_000L
    }
}
