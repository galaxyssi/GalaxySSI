package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentFinalizationRaceDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun foregroundReloadCannotInterruptFinalization() {
        val sessions = InMemoryAgentSessionStore()
        val runtime = runtime(sessions)
        prepare(runtime)
        val held = CountDownLatch(1)
        val release = CountDownLatch(1)
        val reloading = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(2)
        runtime.bindExecutionLoopEventSink(AgentExecutionLoopEventSink { event ->
            if (event.phase == AgentExecutionLoopPhase.FINALIZE) {
                held.countDown()
                check(release.await(10, TimeUnit.SECONDS))
            }
        })
        try {
            val finishing = pool.submit<AgentUiState> {
                finalizeAgentExecution(runtime, runtime.activeConversationTurnId, runtime.snapshot()) { _, _ -> }
            }
            assertTrue(held.await(10, TimeUnit.SECONDS))
            val reload = pool.submit<AgentUiState> { reloading.countDown(); runtime.reloadSession() }
            assertTrue(reloading.await(2, TimeUnit.SECONDS))
            assertThrows(TimeoutException::class.java) { reload.get(100, TimeUnit.MILLISECONDS) }
            release.countDown()
            assertEquals(AgentExecutionLoopPhase.COMPLETED, finishing.get(15, TimeUnit.SECONDS).executionLoop?.phase)
            assertEquals(AgentExecutionLoopPhase.COMPLETED, reload.get(15, TimeUnit.SECONDS).executionLoop?.phase)
            assertEquals("Saved answer", sessions.load()?.lastActionResult?.message)
        } finally { release.countDown(); pool.shutdownNow(); pool.awaitTermination(10, TimeUnit.SECONDS) }
    }

    @Test fun staleDurableSnapshotCannotReplaceNewerLoopAndRepeatedFinalizationIsIdempotent() {
        val sessions = InMemoryAgentSessionStore()
        val runtime = runtime(sessions)
        prepare(runtime)
        val old = sessions.load()!!
        val first = finalizeAgentExecution(runtime, runtime.activeConversationTurnId, runtime.snapshot()) { _, _ -> }
        sessions.save(old)
        assertEquals(AgentExecutionLoopPhase.COMPLETED, runtime.reloadSession().executionLoop?.phase)
        val repeated = finalizeAgentExecution(runtime, runtime.activeConversationTurnId, runtime.snapshot()) { _, _ -> }
        assertEquals(first.executionLoop?.revision, repeated.executionLoop?.revision)
        assertEquals("Saved answer", repeated.lastActionResult?.message)
    }

    @Test fun processRestartPreservesAcceptedAnswerForFinalizationOnly() {
        val sessions = InMemoryAgentSessionStore()
        val original = runtime(sessions)
        prepare(original)
        original.beginExecutionFinalization()
        sessions.save(sessions.load()!!.copy(processInstanceId = "old-process"))
        val restored = runtime(sessions)
        assertEquals(AgentPhase.COMPLETED, restored.phaseSnapshot())
        val result = finalizeAgentExecution(restored, "fixture", restored.snapshot()) { _, _ -> }
        assertEquals(AgentExecutionLoopPhase.COMPLETED, result.executionLoop?.phase)
        assertEquals("Saved answer", result.lastActionResult?.message)
    }

    @Test fun recoverRequestedAcceptedReplyWithoutProviderOrToolReplay() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        val source = args.getString("recover_completed_source")?.toLongOrNull()
        assumeTrue(source != null)
        val turn = args.getString("recover_completed_turn").orEmpty()
        require(turn.isNotBlank())
        val response = AgentConnectorResponseStore.pending(context).singleOrNull {
            it.sourceMessageId == source && it.turnId == turn
        }
        // A background worker may already have finished the same idempotent recovery after installation.
        if (response != null) {
            withTimeout(30_000) {
                while (AgentTaskRuntime.supervisor(context).findWorkspace(turn)?.status != AgentWorkspaceStatus.COMPLETED) {
                    assertTrue(AgentCompletedReplyRecovery.pending(context, response))
                    AgentConnectorBackgroundDelivery(context, ::runtime).consume(response)
                    delay(100)
                }
            }
        }
        val workspace = AgentTaskRuntime.supervisor(context).findWorkspace(turn)!!
        assertEquals(AgentWorkspaceStatus.COMPLETED, workspace.status)
        val session = SharedPreferencesAgentSessionStore(context, "task:$turn").load()!!
        assertEquals(AgentExecutionLoopPhase.COMPLETED, session.executionLoopSnapshot?.phase)
        val expected = CodexStyleResponsePolicy.sanitizeAssistantText(session.lastActionResult?.message.orEmpty())
        assertTrue(expected.isNotBlank())
        val replies = AgentTranscriptStore(context).entriesForTurn(turn).filter {
            it.role == AgentTranscriptRole.ASSISTANT && it.text == expected
        }
        assertEquals(1, replies.size)
        if (response != null) assertFalse(AgentConnectorResponseStore.contains(context, response))
    }

    private fun prepare(runtime: MobileNativeAgent) {
        val turn = "finalization-test-${UUID.randomUUID()}"
        runtime.currentGoal = ""
        runtime.activeConversationTurnId = turn
        runtime.executionLoop.start(turn, AgentExecutionLoopBudget())
        runtime.executionLoop.transition(AgentExecutionLoopPhase.VERIFY)
        runtime.phase = AgentPhase.COMPLETED
        runtime.lastActionResult = AgentActionResult("answer", true, "Saved answer")
        runtime.persistSession()
    }

    private fun runtime(sessions: AgentSessionStore) = MobileNativeAgent(context, sessionStore = sessions,
        memoryStore = InMemoryAgentMemoryStore(), screenObservationOverride = false,
        connectorRegistry = object : AgentConnectorRegistry {
            override fun availableTargets() = emptyList<AgentCallableTarget>()
        }, planner = object : AgentPlanner {
            override fun plan(request: AgentRequest): AgentPlan = error("Finalization must not call a model")
        }, actionExecutor = object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult =
                error("Finalization must not replay an action")
        })
}
