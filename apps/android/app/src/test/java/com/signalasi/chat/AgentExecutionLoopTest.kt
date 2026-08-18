package com.signalasi.chat

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentExecutionLoopTest {
    @Test
    fun happyPathPersistsTheCanonicalExecutionSequence() {
        var now = 1_000L
        val loop = AgentExecutionLoop.create { now }

        loop.start("task-1", AgentExecutionLoopBudget())
        now += 20
        loop.transition(AgentExecutionLoopPhase.ACT, "Run tool", "action-1", toolCall = true)
        now += 30
        loop.transition(AgentExecutionLoopPhase.OBSERVE, "Read result", "action-1")
        loop.transition(AgentExecutionLoopPhase.VERIFY, "Verify goal")
        loop.transition(AgentExecutionLoopPhase.FINALIZE, "Prepare result")
        loop.transition(AgentExecutionLoopPhase.LEARN, "Record evidence")
        val completed = loop.transition(AgentExecutionLoopPhase.COMPLETED, "Done")

        assertEquals(AgentExecutionLoopPhase.COMPLETED, completed.phase)
        assertEquals(1, completed.snapshot.usage.iterations)
        assertEquals(1, completed.snapshot.usage.actions)
        assertEquals(1, completed.snapshot.usage.toolCalls)
        assertEquals(50L, completed.snapshot.usage.activeDurationMillis)
        assertTrue(completed.snapshot.phase.isTerminal)
    }

    @Test
    fun replanConsumesAnIterationAndReturnsToAction() {
        val loop = AgentExecutionLoop.create { 1_000L }
        loop.start("task-2", AgentExecutionLoopBudget(maxIterations = 3, maxReplans = 2))
        loop.transition(AgentExecutionLoopPhase.ACT, actionId = "first")
        loop.transition(AgentExecutionLoopPhase.OBSERVE, actionId = "first")
        loop.transition(AgentExecutionLoopPhase.REPLAN, "First approach failed")
        loop.transition(AgentExecutionLoopPhase.ACT, actionId = "second")

        val snapshot = requireNotNull(loop.snapshot)
        assertEquals(AgentExecutionLoopPhase.ACT, snapshot.phase)
        assertEquals(2, snapshot.usage.iterations)
        assertEquals(1, snapshot.usage.replans)
        assertEquals(2, snapshot.usage.actions)
    }

    @Test
    fun iterationBudgetFailsInsteadOfStartingAnUnboundedReplan() {
        val loop = AgentExecutionLoop.create { 1_000L }
        loop.start("task-3", AgentExecutionLoopBudget(maxIterations = 1, maxReplans = 3))
        loop.transition(AgentExecutionLoopPhase.ACT)
        loop.transition(AgentExecutionLoopPhase.OBSERVE)
        val failed = loop.transition(AgentExecutionLoopPhase.REPLAN)

        assertEquals(AgentExecutionLoopPhase.FAILED, failed.phase)
        assertTrue(failed.snapshot.budgetFailure.contains("iteration", ignoreCase = true))
    }

    @Test
    fun toolAndActionBudgetsAreEnforcedBeforeAnotherSideEffect() {
        val loop = AgentExecutionLoop.create { 1_000L }
        loop.start(
            "task-4",
            AgentExecutionLoopBudget(maxActions = 1, maxToolCalls = 1)
        )
        loop.transition(AgentExecutionLoopPhase.ACT, actionId = "one", toolCall = true)
        loop.transition(AgentExecutionLoopPhase.OBSERVE, actionId = "one")
        val failed = loop.transition(AgentExecutionLoopPhase.ACT, actionId = "two", toolCall = true)

        assertEquals(AgentExecutionLoopPhase.FAILED, failed.phase)
        assertTrue(failed.snapshot.budgetFailure.contains("Action budget"))
    }

    @Test
    fun waitingForADeviceDoesNotConsumeActiveExecutionTime() {
        var now = 1_000L
        val loop = AgentExecutionLoop.create { now }
        loop.start("task-5", AgentExecutionLoopBudget())
        now = 1_500L
        loop.transition(AgentExecutionLoopPhase.WAITING_RESPONSE)
        now = 91_500L
        loop.transition(AgentExecutionLoopPhase.OBSERVE)
        now = 92_000L
        val verified = loop.transition(AgentExecutionLoopPhase.VERIFY)

        assertEquals(AgentExecutionLoopPhase.VERIFY, verified.phase)
        assertEquals(1_000L, verified.snapshot.usage.activeDurationMillis)
        assertTrue(verified.snapshot.budgetFailure.isBlank())
    }

    @Test
    fun pauseAndResumeReturnToTheExactDurablePhase() {
        val loop = AgentExecutionLoop.create { 1_000L }
        loop.start("task-6", AgentExecutionLoopBudget())
        loop.transition(AgentExecutionLoopPhase.ACT, actionId = "action")
        val paused = loop.pause()
        val resumed = loop.resume()

        assertEquals(AgentExecutionLoopPhase.PAUSED, paused.phase)
        assertEquals(AgentExecutionLoopPhase.ACT, paused.snapshot.resumePhase)
        assertEquals(AgentExecutionLoopPhase.ACT, resumed.phase)
    }

    @Test
    fun retryBudgetAppliesToFailedActions() {
        val loop = AgentExecutionLoop.create { 1_000L }
        loop.start("task-7", AgentExecutionLoopBudget(maxRetries = 1))
        loop.transition(AgentExecutionLoopPhase.FAILED, "First failure")
        loop.transition(AgentExecutionLoopPhase.ACT, retry = true)
        loop.transition(AgentExecutionLoopPhase.FAILED, "Second failure")
        val exhausted = loop.transition(AgentExecutionLoopPhase.ACT, retry = true)

        assertEquals(AgentExecutionLoopPhase.FAILED, exhausted.phase)
        assertTrue(exhausted.snapshot.budgetFailure.contains("Retry budget"))
    }

    @Test
    fun invalidTransitionsAreRejected() {
        val loop = AgentExecutionLoop.create { 1_000L }
        loop.start("task-8", AgentExecutionLoopBudget())

        assertThrows(IllegalArgumentException::class.java) {
            loop.transition(AgentExecutionLoopPhase.LEARN)
        }
    }

    @Test
    fun snapshotRoundTripRetiresLegacyCountLimits() {
        val loop = AgentExecutionLoop.create { 1_000L }
        loop.start("task-9", AgentExecutionLoopBudget(maxIterations = 5, maxRetries = 4))
        loop.transition(AgentExecutionLoopPhase.ACT, actionId = "action-9", toolCall = true)
        val original = requireNotNull(loop.snapshot)

        val restored = AgentExecutionLoopJsonCodec.decode(
            AgentExecutionLoopJsonCodec.encode(original)
        )

        assertNotNull(restored)
        assertEquals(original.copy(budget = original.budget.copy(enforceCountLimits = false)), restored)
    }

    @Test
    fun interruptedActivePhaseRecoversToSafePause() {
        val loop = AgentExecutionLoop.create { 1_000L }
        loop.start("task-10", AgentExecutionLoopBudget())
        loop.transition(AgentExecutionLoopPhase.ACT, actionId = "action-10")
        val recovered = loop.recoverInterrupted()

        assertNotNull(recovered)
        assertEquals(AgentExecutionLoopPhase.PAUSED, recovered?.phase)
        assertEquals(AgentExecutionLoopPhase.ACT, recovered?.snapshot?.resumePhase)
        assertFalse(recovered?.snapshot?.phase?.isActive ?: true)
    }

    @Test
    fun buildTasksUseMediumReasoningWithoutAnAbsoluteDeadline() {
        val profile = AgentExecutionProfile.forGoal(
            "Build an Android phone game and return the APK"
        )
        val loop = AgentExecutionLoop.create { 1_000L }
        val started = loop.start(
            "task-build",
            AgentModelPlannerSettings().executionLoopBudget(profile),
            profile
        )

        assertEquals(AgentExecutionTaskKind.BUILD, started.snapshot.taskKind)
        assertEquals(AgentExecutionReasoningEffort.MEDIUM, started.snapshot.reasoningEffort)
        assertTrue(started.snapshot.budget.noProgressTimeoutMillis >= 420_000L)
        assertFalse(started.snapshot.budget.enforceCountLimits)
    }

    @Test
    fun supervisedProjectContinuesPastFixedActionAndReplanCounts() {
        val profile = AgentExecutionProfile.forGoal(
            "Update the Android project, verify it, and create a pull request"
        )
        val budget = AgentModelPlannerSettings().executionLoopBudget(profile)
        val loop = AgentExecutionLoop.create { 1_000L }
        loop.start("continuous-project", budget, profile)

        repeat(30) { index ->
            loop.transition(
                AgentExecutionLoopPhase.ACT,
                actionId = "project-action-$index",
                toolCall = true
            )
            loop.transition(
                AgentExecutionLoopPhase.OBSERVE,
                actionId = "project-action-$index"
            )
            loop.transition(AgentExecutionLoopPhase.REPLAN, "Continue from verified evidence")
        }

        val snapshot = requireNotNull(loop.snapshot)
        assertEquals(AgentExecutionLoopPhase.REPLAN, snapshot.phase)
        assertTrue(snapshot.usage.actions > budget.maxActions)
        assertTrue(snapshot.usage.replans > budget.maxReplans)
        assertTrue(snapshot.usage.toolCalls > budget.maxToolCalls)
        assertTrue(snapshot.budgetFailure.isBlank())
    }

    @Test
    fun continuousProjectBudgetSurvivesCheckpointRoundTrip() {
        val profile = AgentExecutionProfile.forGoal(
            "Build the project on the phone and publish a pull request"
        )
        val loop = AgentExecutionLoop.create { 2_000L }
        val started = loop.start(
            "continuous-project-json",
            AgentModelPlannerSettings().executionLoopBudget(profile),
            profile
        )

        val restored = requireNotNull(
            AgentExecutionLoopJsonCodec.decode(
                AgentExecutionLoopJsonCodec.encode(started.snapshot)
            )
        )

        assertFalse(restored.budget.enforceCountLimits)
        assertEquals(AgentExecutionTaskKind.BUILD, restored.taskKind)
    }

    @Test
    fun foregroundAgentSettingsDoNotEnforceFixedActionCounts() {
        val budget = AgentModelPlannerSettings(
            maxActions = 8,
            maxReplans = 3,
            maxToolCalls = 8,
            maxLoopIterations = 8
        ).executionLoopBudget(AgentExecutionProfile.forGoal("hello"))
        val loop = AgentExecutionLoop.create { 3_000L }
        loop.start("unbounded-foreground-task", budget)

        repeat(20) { index ->
            loop.transition(AgentExecutionLoopPhase.ACT, actionId = "action-$index", toolCall = true)
            loop.transition(AgentExecutionLoopPhase.OBSERVE, actionId = "action-$index")
            loop.transition(AgentExecutionLoopPhase.REPLAN, "Continue from new evidence")
        }

        val snapshot = requireNotNull(loop.snapshot)
        assertEquals(AgentExecutionLoopPhase.REPLAN, snapshot.phase)
        assertTrue(snapshot.usage.actions > 8)
        assertTrue(snapshot.budgetFailure.isBlank())
        assertFalse(snapshot.budget.enforceCountLimits)
    }

    @Test
    fun inputAttachmentUsesMediumReasoningWithoutRequiringANewArtifact() {
        val profile = AgentExecutionProfile.forGoal(
            goal = "Summarize this spreadsheet",
            hasAttachments = true
        )

        assertEquals(AgentExecutionTaskKind.ARTIFACT, profile.taskKind)
        assertEquals(AgentExecutionReasoningEffort.MEDIUM, profile.reasoningEffort)
        assertFalse(profile.requiresArtifact)
    }

    @Test
    fun repeatedFailureRemainsAvailableForModelDrivenReplanning() {
        val loop = AgentExecutionLoop.create { 1_000L }
        loop.start(
            "task-failure",
            AgentExecutionLoopBudget(
                maxSameFailureAttempts = 2,
                enforceCountLimits = false
            )
        )
        loop.transition(AgentExecutionLoopPhase.ACT, actionId = "verify")
        loop.transition(AgentExecutionLoopPhase.OBSERVE, actionId = "verify")

        val failures = (1..10).map {
            loop.recordFailure("command", "python verify.py exited $it", "verify")
        }

        assertTrue(failures.all { it.phase == AgentExecutionLoopPhase.REPLAN })
        assertTrue(failures.all { it.retry })
        assertTrue(failures.last().snapshot.budgetFailure.isBlank())
        assertEquals(10, failures.last().snapshot.failureCounts.values.single())
    }

    @Test
    fun noProgressUsesTheSameRecoveryBudgetInsteadOfElapsedTaskTime() {
        var now = 1_000L
        val loop = AgentExecutionLoop.create { now }
        loop.start(
            "task-stalled",
            AgentExecutionLoopBudget(
                maxSameFailureAttempts = 2,
                noProgressTimeoutMillis = 5_000L
            )
        )
        now += 4_999L
        assertEquals(null, loop.checkNoProgress())
        now += 1L

        val recovery = requireNotNull(loop.checkNoProgress())
        assertEquals(AgentExecutionLoopPhase.REPLAN, recovery.phase)
        assertTrue(recovery.snapshot.budgetFailure.isBlank())
    }

    @Test
    fun everyPhaseIsJournaledAndCheckpointedInTheDurableWorkspace() = runBlocking {
        val store = InMemoryAgentWorkspaceStore(clock = { 2_000L })
        val supervisor = AgentTaskSupervisor(store, clock = { 2_000L })
        val workspace = AgentWorkspace(
            workspaceId = "workspace-loop",
            sessionId = "session-loop",
            conversationId = "conversation-loop",
            taskId = "task-loop",
            goal = "Run a bounded task"
        )
        val handle = supervisor.submit(workspace) {
            val loop = AgentExecutionLoop.create { 2_000L }
            persistExecutionLoop(loop.start("task-loop", AgentExecutionLoopBudget()))
            persistExecutionLoop(loop.transition(AgentExecutionLoopPhase.ACT, actionId = "action"))
            persistExecutionLoop(loop.transition(AgentExecutionLoopPhase.OBSERVE, actionId = "action"))
            persistExecutionLoop(loop.transition(AgentExecutionLoopPhase.VERIFY))
            persistExecutionLoop(loop.transition(AgentExecutionLoopPhase.FINALIZE))
            persistExecutionLoop(loop.transition(AgentExecutionLoopPhase.LEARN))
            persistExecutionLoop(loop.transition(AgentExecutionLoopPhase.COMPLETED))
        }

        handle.join()

        val persisted = requireNotNull(store.find("workspace-loop"))
        assertEquals(AgentWorkspaceStatus.COMPLETED, persisted.status)
        assertEquals(
            listOf("plan", "act", "observe", "verify", "finalize", "learn", "completed"),
            persisted.eventJournal
                .filter { it.kind.startsWith("agent.loop.") }
                .map { it.kind.substringAfterLast('.') }
        )
        val restored = AgentExecutionLoopJsonCodec.decode(
            persisted.checkpoints.last().stateJson
        )
        assertEquals(AgentExecutionLoopPhase.COMPLETED, restored?.phase)
        assertEquals(7L, restored?.revision)
        supervisor.shutdown()
    }
}
