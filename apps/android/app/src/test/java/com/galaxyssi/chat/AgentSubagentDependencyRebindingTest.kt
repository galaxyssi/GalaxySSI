package com.galaxyssi.chat

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test

class AgentSubagentDependencyRebindingTest {
    private fun plan() = AgentSubagentPlan("rebind-run", listOf(
        AgentSubagentChild("producer"), AgentSubagentChild("probe"),
        AgentSubagentChild("review", dependencies = setOf("producer", "probe")),
        AgentSubagentChild("final", dependencies = setOf("producer", "probe", "review"))), completionBarrierChildId = "final")
    private fun rebind(plan: AgentSubagentPlan) = plan.copy(children = plan.children.map {
        if (it.childId == "review") it.copy(dependencies = setOf("probe"), dependencyRevision = it.dependencyRevision + 1) else it
    })
    private fun hook(block: suspend (AgentSubagentPlan, Map<String, AgentSubagentChildResult>, Set<String>) -> AgentSubagentPlan) =
        object : AgentSubagentExpansionHook {
            override suspend fun expand(plan: AgentSubagentPlan, completed: Map<String, AgentSubagentChildResult>): AgentSubagentPlan =
                error("Admission-aware hook required")
            override suspend fun expandWithAdmissions(plan: AgentSubagentPlan, completed: Map<String, AgentSubagentChildResult>,
                admitted: Set<String>) = block(plan, completed, admitted)
        }

    @Test fun waitingReviewUsesReboundInputBeforeProducerFinishesAndOnlyRunsOnce(): Unit = runBlocking {
        withTimeout(10_000) {
            val producerStarted = CompletableDeferred<Unit>()
            val releaseProducer = CompletableDeferred<Unit>()
            val reviewStarted = CompletableDeferred<Unit>()
            val calls = ConcurrentHashMap<String, Int>()
            val events = CopyOnWriteArrayList<AgentSubagentEvent>()
            val changed = AtomicBoolean(false)
            val runtime = AgentSubagentRuntime(eventHook = AgentSubagentEventHook { events += it },
                graphExpansion = hook { current, completed, admitted ->
                    if ("probe" in completed && changed.compareAndSet(false, true)) {
                        assertTrue("producer" in admitted)
                        assertFalse("review" in admitted)
                        assertTrue(events.any { it.childId == "review" && it.kind == AgentSubagentEventKinds.CHILD_QUEUED })
                        assertTrue(events.none { it.childId == "review" && it.kind == AgentSubagentEventKinds.CHILD_ADMITTED })
                        rebind(current)
                    } else current
                })
            try {
                val handle = runtime.start(plan()) { context ->
                    calls.merge(context.childId, 1, Int::plus)
                    assertTrue(events.any { it.childId == context.childId && it.kind == AgentSubagentEventKinds.CHILD_ADMITTED } || context.childId == "final")
                    when (context.childId) {
                        "producer" -> { producerStarted.complete(Unit); releaseProducer.await() }
                        "probe" -> producerStarted.await()
                        "review" -> {
                            assertFalse(releaseProducer.isCompleted)
                            assertNull(context.dependency("producer"))
                            assertEquals("probe result", context.dependency("probe")?.output)
                            reviewStarted.complete(Unit)
                        }
                        "final" -> assertTrue(releaseProducer.isCompleted)
                    }
                    AgentSubagentOutput("${context.childId} result")
                }
                reviewStarted.await()
                assertFalse(calls.containsKey("final"))
                releaseProducer.complete(Unit)
                assertEquals(AgentSubagentRunStatus.SUCCEEDED, handle.await().status)
                assertEquals(mapOf("producer" to 1, "probe" to 1, "review" to 1, "final" to 1), calls)
                assertEquals(1, events.count { it.childId == "review" && it.kind == AgentSubagentEventKinds.CHILD_ADMITTED })
            } finally { runtime.shutdown() }
        }
    }

    @Test fun admittedPermitWaiterCannotBeChangedEvenBeforeRunning(): Unit = runBlocking {
        withTimeout(10_000) {
            val started = CompletableDeferred<Unit>()
            val attempted = AtomicBoolean(false)
            val events = CopyOnWriteArrayList<AgentSubagentEvent>()
            val runtime = AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 1),
                eventHook = AgentSubagentEventHook { events += it },
                graphExpansion = hook { current, _, admitted ->
                    if (attempted.get()) {
                        assertTrue("probe" in admitted)
                        assertTrue(events.none { it.childId == "probe" && it.childStatus == AgentSubagentStatus.RUNNING })
                        current.copy(children = current.children.map { if (it.childId == "probe")
                            it.copy(dependencyRevision = 1) else it })
                    } else current
                })
            try {
                val handle = runtime.start(plan().copy(preserveChildOrder = true)) {
                    assertEquals("producer", it.childId)
                    started.complete(Unit)
                    awaitCancellation()
                }
                started.await()
                attempted.set(true)
                assertTrue(runtime.requestExpansion("rebind-run"))
                val failure = runCatching { handle.await() }.exceptionOrNull()
                assertTrue(failure.toString(), failure is IllegalArgumentException)
            } finally { runtime.shutdown() }
        }
    }

    @Test fun revisionDoesNotPermitChangingAssignmentAuthorityOrAddingDependencies(): Unit = runBlocking {
        val changes = listOf<(AgentSubagentChild) -> AgentSubagentChild>(
            { it.copy(dependencies = setOf("probe"), dependencyRevision = 2) },
            { it.copy(dependencies = setOf("probe"), dependencyRevision = 1, context = "different assignment") },
            { it.copy(dependencies = setOf("probe"), dependencyRevision = 1, dependencyPolicy = AgentSubagentDependencyPolicy.ALLOW_TERMINAL) },
            { it.copy(dependencies = setOf("final"), dependencyRevision = 1) })
        for (change in changes) {
            val runtime = AgentSubagentRuntime(graphExpansion = hook { current, _, _ ->
                current.copy(children = current.children.map { if (it.childId == "review") change(it) else it })
            })
            try {
                val handle = runtime.start(plan()) { error("Must reject before dispatch") }
                assertTrue(withTimeout(10_000) { runCatching { handle.await() }.exceptionOrNull() } is IllegalArgumentException)
            } finally { runtime.shutdown() }
        }
    }

    @Test fun failedAdmissionPersistenceNeverStartsReboundReview(): Unit = runBlocking {
        withTimeout(10_000) {
            val changed = AtomicBoolean(false)
            val reviewStarted = AtomicBoolean(false)
            val runtime = AgentSubagentRuntime(eventHook = AgentSubagentEventHook {
                if (it.childId == "review" && it.kind == AgentSubagentEventKinds.CHILD_ADMITTED) error("Admission persistence failed")
            }, graphExpansion = hook { current, completed, _ ->
                if ("probe" in completed && changed.compareAndSet(false, true)) rebind(current) else current
            })
            try {
                val handle = runtime.start(plan()) {
                    when (it.childId) {
                        "producer" -> awaitCancellation()
                        "review" -> reviewStarted.set(true)
                    }
                    AgentSubagentOutput("result")
                }
                assertNotNull(runCatching { handle.await() }.exceptionOrNull())
                assertTrue(changed.get())
                assertFalse(reviewStarted.get())
            } finally { runtime.shutdown() }
        }
    }
}
