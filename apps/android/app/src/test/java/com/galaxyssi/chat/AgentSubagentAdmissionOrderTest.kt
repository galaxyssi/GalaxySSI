package com.galaxyssi.chat

import java.util.concurrent.ConcurrentLinkedDeque
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentSubagentAdmissionOrderTest {
    @Test fun bothCoordinatorsKnowTheAdmissionSemantics() {
        assertTrue(CollaborationGoalLoop.instructions().contains(AgentTeamGraphPlan.ADMISSION_INSTRUCTIONS))
        assertTrue(CollaborationLiveGraph.instructions().contains(AgentTeamGraphPlan.ADMISSION_INSTRUCTIONS))
    }

    @Test fun researchProjectionPreservesPlannerOrderAndLearningPositions() {
        val ordinary = member("m-middle")
        fun learn(id: String, priority: Int) = member(id).copy(context = member(id).context +
            (CollaborationLearningWork.TASK to JSONObject().put("agenda", JSONObject().put("sha256", "agenda"))
                .put("priority", priority).toString()))
        val members = listOf(learn("z-low", 2), ordinary, learn("a-high", 1))
        val definition = AgentTeamDefinition("team", "fixture", members, primaryInstanceId = ordinary.memberId)
        val graph = AgentTeamGraphPlan.build(definition, request())
        assertTrue(graph.preserveChildOrder)
        assertEquals(listOf("a-high", "m-middle", "z-low"), graph.children.map { it.childId })
        val ordinaryResearch = definition.copy(members = listOf(member("z-model"), member("m-challenge"), member("a-audit")), primaryInstanceId = "a-audit")
        assertEquals(listOf("z-model", "m-challenge", "a-audit"), AgentTeamGraphPlan.build(ordinaryResearch, request()).children.map { it.childId })
        assertFalse(AgentTeamGraphPlan.build(definition.copy(members = members.map { it.copy(context = emptyMap()) }), request()).preserveChildOrder)
    }

    @Test fun reversedDispatcherCannotGiveBookkeepingTheFirstTwoPermits() = runBlocking {
        val dispatcher = ReverseDispatcher()
        val released = CompletableDeferred<Unit>()
        val started = CopyOnWriteArrayList<String>()
        AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 2), dispatcher).use { runtime ->
            val handle = runtime.start(plan("z-model", "m-challenge", "a-audit")) {
                started += it.childId
                if (it.childId != "a-audit") released.await()
                AgentSubagentOutput("fixture")
            }
            dispatcher.drain()
            assertEquals(setOf("z-model", "m-challenge"), started.toSet())
            released.complete(Unit)
            dispatcher.drain()
            assertEquals(AgentSubagentRunStatus.SUCCEEDED, withTimeout(2000) { handle.await() }.status)
            assertEquals("a-audit", started.last())
        }
    }

    @Test fun blockedEarlierWorkDoesNotOccupyAPermitOrBlockItsProducer() = runBlocking {
        val dispatcher = ReverseDispatcher()
        val started = mutableListOf<String>()
        val graph = plan("z-review", "m-producer", "a-independent").let { it.copy(children = it.children.map { child ->
            if (child.childId == "z-review") child.copy(dependencies = setOf("m-producer")) else child }) }
        AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 1), dispatcher).use { runtime ->
            val handle = runtime.start(graph) { started += it.childId; AgentSubagentOutput("fixture") }
            dispatcher.drain()
            assertEquals(AgentSubagentRunStatus.SUCCEEDED, withTimeout(2000) { handle.await() }.status)
        }
        assertEquals(listOf("m-producer", "z-review", "a-independent"), started)
    }

    @Test fun failedDependencyIsSkippedWithoutStrandingIndependentWork() = runBlocking {
        val dispatcher = ReverseDispatcher()
        val graph = plan("z-review", "m-producer", "a-independent").let { it.copy(children = it.children.map { child ->
            if (child.childId == "z-review") child.copy(dependencies = setOf("m-producer")) else child }) }
        val invoked = mutableListOf<String>()
        AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 1), dispatcher).use { runtime ->
            val handle = runtime.start(graph) {
                invoked += it.childId
                if (it.childId == "m-producer") error("Known fixture failure")
                AgentSubagentOutput("fixture")
            }
            dispatcher.drain()
            val result = withTimeout(2000) { handle.await() }
            assertEquals(AgentSubagentStatus.SKIPPED, result["z-review"]?.status)
            assertEquals(AgentSubagentStatus.SUCCEEDED, result["a-independent"]?.status)
            assertEquals(listOf("m-producer", "a-independent"), invoked)
        }
    }

    @Test fun defaultDispatcherRepeatedlyKeepsIntentionalOrder() = runBlocking {
        repeat(20) { iteration ->
            val seen = CopyOnWriteArrayList<String>()
            val ids = (0 until 24).map { "work-${100-it}" }
            AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 1, maxChildren = ids.size)).use { runtime ->
                withTimeout(5000) { runtime.start(plan(*ids.toTypedArray()).copy(supervisorId = "repeat-$iteration")) {
                    seen += it.childId; AgentSubagentOutput("fixture")
                }.await() }
            }
            assertEquals(ids, seen)
        }
    }

    @Test fun restoredTerminalWorkIsNotReplayedAndPendingOrderSurvives() = runBlocking {
        val seen = CopyOnWriteArrayList<String>()
        val graph = plan("z-completed", "m-next", "a-last")
        val completed = AgentSubagentChildResult(graph.supervisorId, "z-completed", graph.supervisorId, 1,
            AgentSubagentStatus.SUCCEEDED, "durable output")
        AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 1)).use { runtime ->
            val result = withTimeout(5000) { runtime.resume(graph, mapOf("z-completed" to completed), 5) {
                seen += it.childId; AgentSubagentOutput("fixture")
            }.await() }
            assertEquals("durable output", result["z-completed"]?.output)
        }
        assertEquals(listOf("m-next", "a-last"), seen)
    }

    @Test fun appendedWorkDoesNotJumpAheadOfExistingReadyWork() = runBlocking {
        val seen = CopyOnWriteArrayList<String>()
        val graph = plan("z-producer", "m-old", "final").copy(completionBarrierChildId = "final")
        AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 1), graphExpansion = AgentSubagentExpansionHook { current, completed ->
            if ("z-producer" in completed && current.children.none { it.childId == "a-added" })
                current.copy(children = current.children + AgentSubagentChild("a-added"))
            else current
        }).use { runtime ->
            val result = withTimeout(5000) { runtime.start(graph) { seen += it.childId; AgentSubagentOutput("fixture") }.await() }
            assertEquals(AgentSubagentRunStatus.SUCCEEDED, result.status)
        }
        assertEquals(listOf("z-producer", "m-old", "a-added", "final"), seen)
    }

    @Test fun expansionCannotChangeAdmissionMode() = runBlocking {
        AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 1), graphExpansion = AgentSubagentExpansionHook { current, _ ->
            current.copy(preserveChildOrder = false)
        }).use { runtime ->
            val failure = runCatching { withTimeout(5000) {
                runtime.start(plan("z-work", "final").copy(completionBarrierChildId = "final")) { error("Must reject before execution") }.await()
            } }.exceptionOrNull()
            assertTrue(failure.toString(), failure?.message.orEmpty().contains("admission mode"))
        }
    }

    @Test fun cancellationReleasesOrderedAndSharedPermitWaiters() = runBlocking {
        val entered = CompletableDeferred<Unit>()
        AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 1)).use { runtime ->
            val first = runtime.start(plan("z-first", "a-queued")) { entered.complete(Unit); awaitCancellation() }
            withTimeout(5000) { entered.await() }
            first.cancel("fixture pause")
            withTimeout(5000) { first.await() }
            val second = withTimeout(5000) { runtime.start(plan("z-next", "a-last").copy(supervisorId = "after-cancel")) {
                AgentSubagentOutput("fixture")
            }.await() }
            assertEquals(AgentSubagentRunStatus.SUCCEEDED, second.status)
        }
    }

    @Test fun waitingWorkerCanReleaseItsPermitForQueuedWorkAndResume() = runBlocking {
        val secondDone = CompletableDeferred<Unit>()
        val seen = CopyOnWriteArrayList<String>()
        AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 1)).use { runtime ->
            withTimeout(5000) { runtime.start(plan("z-first", "a-second")) {
                seen += it.childId
                if (it.childId == "z-first") it.suspendExecutionPermit { secondDone.await() }
                else secondDone.complete(Unit)
                AgentSubagentOutput("fixture")
            }.await() }
        }
        assertEquals(listOf("z-first", "a-second"), seen)
    }

    @Test fun thousandReadyNodesRetainOrderWithoutChangingConcurrencyLimit() = runBlocking {
        val ids = (0 until 1024).map { "node-${2048-it}" }
        val seen = CopyOnWriteArrayList<String>()
        val active = AtomicInteger()
        AgentSubagentRuntime(AgentSubagentLimits(maxChildren = ids.size, maxConcurrency = 1)).use { runtime ->
            withTimeout(15_000) { runtime.start(plan(*ids.toTypedArray())) {
                assertEquals(1, active.incrementAndGet())
                seen += it.childId
                active.decrementAndGet()
                AgentSubagentOutput("fixture")
            }.await() }
        }
        assertEquals(ids, seen)
    }

    @Test fun readyQueueWakesOnlyTheNextEligibleWaiter() = runBlocking {
        val count = 1024
        val readinessChecks = AtomicInteger()
        val dispatcher = ReverseDispatcher()
        val permits = kotlinx.coroutines.sync.Semaphore(1)
        val admission = AgentSubagentOrderedAdmission(permits)
        admission.update((0 until count).map { index ->
            AgentSubagentOrderedAdmission.Candidate("child-$index") { readinessChecks.incrementAndGet(); true }
        })
        val scope = kotlinx.coroutines.CoroutineScope(dispatcher)
        val seen = mutableListOf<Int>()
        val jobs = (0 until count).map { index ->
            scope.launch {
                admission.acquire("child-$index")
                seen += index
                permits.release()
                admission.settled("child-$index")
            }
        }
        dispatcher.drain()
        assertTrue(jobs.all { it.isCompleted })
        assertEquals((0 until count).toList(), seen)
        assertTrue("Wakeups should not scan every ready waiter after each grant: ${readinessChecks.get()}", readinessChecks.get() <= count * 5)
    }

    private fun member(id: String) = AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = id,
        context = mapOf("collaboration_group_id" to "fixture-group", CollaborationResearchWorkflow.STAGE to "EXECUTE"))
    private fun request() = AgentRunRequest("group", "turn", "task", runId = "ordered-run", goal = "General research fixture")
    private fun plan(vararg ids: String) = AgentSubagentPlan("ordered-run", ids.map { AgentSubagentChild(it) }, preserveChildOrder = true)

    private class ReverseDispatcher : CoroutineDispatcher() {
        private val queue = ConcurrentLinkedDeque<Runnable>()
        override fun dispatch(context: CoroutineContext, block: Runnable) { queue.addLast(block) }
        fun drain() {
            var remaining = 10_000
            while (true) {
                val next = queue.pollLast() ?: return
                check(remaining-- > 0) { "Fixture scheduler did not quiesce" }
                next.run()
            }
        }
    }
}
