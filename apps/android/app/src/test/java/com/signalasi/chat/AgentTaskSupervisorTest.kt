package com.signalasi.chat

import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTaskSupervisorTest {
    @Test
    fun explicitlyReopensInterruptedFailedWorkspaceWithAuditEvent() {
        val store = InMemoryAgentWorkspaceStore()
        val failed = store.upsert(
            workspace("interrupted", AgentWorkspaceStatus.FAILED),
            expectedRevision = 0L
        )
        val supervisor = AgentTaskSupervisor(store)

        val reopened = supervisor.reopenInterruptedWorkspace(failed.workspaceId)

        assertEquals(AgentWorkspaceStatus.PAUSED, reopened.status)
        assertEquals("", reopened.errorMessage)
        assertEquals(AgentTaskEventKinds.RECOVERED_INTERRUPTED, reopened.eventJournal.last().kind)
        supervisor.close()
    }

    @Test
    fun atomicallyRecordsRecoveredWaitingSnapshotFromFailedWorkspace() {
        val store = InMemoryAgentWorkspaceStore()
        store.upsert(
            workspace("atomic-recovery", AgentWorkspaceStatus.FAILED).copy(
                errorMessage = "Process was interrupted"
            ),
            expectedRevision = 0L
        )
        val supervisor = AgentTaskSupervisor(store)

        val recovered = supervisor.recordRecoveredExecutionSnapshot(
            workspaceId = "workspace-atomic-recovery",
            snapshot = AgentWorkspaceExecutionSnapshot(
                status = AgentWorkspaceStatus.WAITING_RESPONSE,
                remoteRunId = "731",
                handoffIds = listOf("codex:731")
            )
        )

        assertEquals(AgentWorkspaceStatus.WAITING_RESPONSE, recovered.status)
        assertEquals("", recovered.errorMessage)
        assertEquals("731", recovered.remoteRunId)
        assertTrue(recovered.eventJournal.any {
            it.kind == AgentTaskEventKinds.RECOVERED_INTERRUPTED
        })
        assertEquals(AgentTaskEventKinds.SNAPSHOT, recovered.eventJournal.last().kind)
        supervisor.close()
    }

    @Test(expected = IllegalArgumentException::class)
    fun recoveredSnapshotCannotReopenCancelledWorkspace() {
        val store = InMemoryAgentWorkspaceStore()
        store.upsert(
            workspace("cancelled-recovery", AgentWorkspaceStatus.CANCELLED).copy(
                cancellationRequested = true
            ),
            expectedRevision = 0L
        )
        val supervisor = AgentTaskSupervisor(store)
        try {
            supervisor.recordRecoveredExecutionSnapshot(
                workspaceId = "workspace-cancelled-recovery",
                snapshot = AgentWorkspaceExecutionSnapshot(
                    status = AgentWorkspaceStatus.WAITING_RESPONSE
                )
            )
        } finally {
            supervisor.close()
        }
    }

    @Test
    fun memoryObserverReceivesQueuedAndTerminalTaskIdentity() = runBlocking {
        val store = InMemoryAgentWorkspaceStore()
        val observed = Collections.synchronizedList(mutableListOf<AgentWorkspace>())
        val supervisor = AgentTaskSupervisor(
            workspaceStore = store,
            memoryObserver = { observed.add(it) }
        )

        supervisor.submit(workspace("memory")) {
            recordExecutionSnapshot(
                AgentWorkspaceExecutionSnapshot(agentId = "model:deepseek")
            )
        }.join()

        assertTrue(observed.any {
            it.taskId == "task-memory" && it.status == AgentWorkspaceStatus.QUEUED
        })
        assertTrue(observed.any {
            it.taskId == "task-memory" &&
                it.agentId == "model:deepseek" &&
                it.status == AgentWorkspaceStatus.COMPLETED
        })
        assertTrue(supervisor.activeWorkspaces().isEmpty())
        supervisor.shutdown()
    }

    @Test
    fun readReasoningLaneBoundsConcurrentWork() = runBlocking {
        val store = InMemoryAgentWorkspaceStore()
        val supervisor = AgentTaskSupervisor(store, maxConcurrentReadReasoningTasks = 2)
        val running = AtomicInteger(0)
        val maximumRunning = AtomicInteger(0)
        val started = AtomicInteger(0)
        val release = CompletableDeferred<Unit>()

        val handles = (1..4).map { index ->
            supervisor.submit(workspace(index.toString())) {
                val active = running.incrementAndGet()
                updateMaximum(maximumRunning, active)
                started.incrementAndGet()
                try {
                    release.await()
                } finally {
                    running.decrementAndGet()
                }
            }
        }

        awaitCondition { started.get() == 2 }
        assertEquals(2, maximumRunning.get())
        assertEquals(2, started.get())

        release.complete(Unit)
        handles.map { it.job }.joinAll()

        assertEquals(4, started.get())
        assertTrue(store.list().all { it.status == AgentWorkspaceStatus.COMPLETED })
        supervisor.shutdown()
    }

    @Test
    fun foregroundChatStartsWhileBackgroundWorkUsesItsReservedCapacity() = runBlocking {
        val store = InMemoryAgentWorkspaceStore()
        val supervisor = AgentTaskSupervisor(store, maxConcurrentReadReasoningTasks = 2)
        val backgroundStarted = CompletableDeferred<Unit>()
        val secondBackgroundStarted = CompletableDeferred<Unit>()
        val foregroundStarted = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()

        val firstBackground = supervisor.submit(
            workspace("background-one"),
            AgentTaskLane.READ_REASONING,
            AgentTaskPriority.BACKGROUND
        ) {
            backgroundStarted.complete(Unit)
            release.await()
        }
        withTimeout(TEST_TIMEOUT_MILLIS) { backgroundStarted.await() }
        val secondBackground = supervisor.submit(
            workspace("background-two"),
            AgentTaskLane.READ_REASONING,
            AgentTaskPriority.BACKGROUND
        ) {
            secondBackgroundStarted.complete(Unit)
            release.await()
        }
        val foreground = supervisor.submit(
            workspace("foreground"),
            AgentTaskLane.READ_REASONING,
            AgentTaskPriority.FOREGROUND
        ) {
            foregroundStarted.complete(Unit)
            release.await()
        }

        withTimeout(TEST_TIMEOUT_MILLIS) { foregroundStarted.await() }
        assertFalse(secondBackgroundStarted.isCompleted)
        assertEquals(1, AgentForegroundWorkCoordinator.activeCount)

        release.complete(Unit)
        listOf(firstBackground.job, secondBackground.job, foreground.job).joinAll()

        assertTrue(secondBackgroundStarted.isCompleted)
        assertEquals(0, AgentForegroundWorkCoordinator.activeCount)
        supervisor.shutdown()
    }

    @Test
    fun foregroundLeaseCoversQueuedAndRunningLifecycle() = runBlocking {
        val store = InMemoryAgentWorkspaceStore()
        val supervisor = AgentTaskSupervisor(store)
        val started = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()

        val handle = supervisor.submit(
            workspace("foreground-lease"),
            priority = AgentTaskPriority.FOREGROUND
        ) {
            started.complete(Unit)
            release.await()
        }

        assertTrue(AgentForegroundWorkCoordinator.hasForegroundWork)
        withTimeout(TEST_TIMEOUT_MILLIS) { started.await() }
        release.complete(Unit)
        handle.join()

        assertFalse(AgentForegroundWorkCoordinator.hasForegroundWork)
        supervisor.shutdown()
    }

    @Test
    fun sideEffectLaneRunsOneTaskAtATime() = runBlocking {
        val store = InMemoryAgentWorkspaceStore()
        val supervisor = AgentTaskSupervisor(store)
        val firstStarted = CompletableDeferred<Unit>()
        val releaseFirst = CompletableDeferred<Unit>()
        val secondStarted = CompletableDeferred<Unit>()

        val first = supervisor.submit(workspace("first"), AgentTaskLane.SIDE_EFFECT) {
            firstStarted.complete(Unit)
            releaseFirst.await()
        }
        withTimeout(TEST_TIMEOUT_MILLIS) { firstStarted.await() }
        val second = supervisor.submit(workspace("second"), AgentTaskLane.SIDE_EFFECT) {
            secondStarted.complete(Unit)
        }

        delay(100L)
        assertFalse(secondStarted.isCompleted)

        releaseFirst.complete(Unit)
        listOf(first.job, second.job).joinAll()

        assertTrue(secondStarted.isCompleted)
        assertEquals(AgentWorkspaceStatus.COMPLETED, store.find("workspace-first")?.status)
        assertEquals(AgentWorkspaceStatus.COMPLETED, store.find("workspace-second")?.status)
        supervisor.shutdown()
    }

    @Test
    fun failedTaskDoesNotCancelSibling() = runBlocking {
        val store = InMemoryAgentWorkspaceStore()
        val supervisor = AgentTaskSupervisor(store)
        val siblingCompleted = CompletableDeferred<Unit>()

        val failed = supervisor.submit(workspace("failed")) {
            throw IllegalStateException("reasoning failed")
        }
        val sibling = supervisor.submit(workspace("sibling")) {
            delay(50L)
            siblingCompleted.complete(Unit)
        }

        listOf(failed.job, sibling.job).joinAll()

        assertTrue(siblingCompleted.isCompleted)
        assertEquals(AgentWorkspaceStatus.FAILED, store.find("workspace-failed")?.status)
        assertEquals(AgentWorkspaceStatus.COMPLETED, store.find("workspace-sibling")?.status)
        assertTrue(supervisor.isActive)
        supervisor.shutdown()
    }

    @Test
    fun cancellationSourcePersistsCancellationEventAndCheckpoint() = runBlocking {
        var now = 1_000L
        val store = InMemoryAgentWorkspaceStore(clock = { now++ })
        val supervisor = AgentTaskSupervisor(store, clock = { now++ })
        val started = CompletableDeferred<Unit>()
        val handle = supervisor.submit(workspace("cancel")) {
            checkpoint(
                checkpointId = "before-side-effect",
                planSnapshot = "1. Read\n2. Confirm\n3. Execute",
                stateJson = "{\"step\":2}"
            )
            started.complete(Unit)
            awaitCancellation()
        }

        withTimeout(TEST_TIMEOUT_MILLIS) { started.await() }
        assertTrue(handle.cancel("user stopped task"))
        handle.join()

        val cancelled = requireNotNull(store.find("workspace-cancel"))
        assertEquals(AgentWorkspaceStatus.CANCELLED, cancelled.status)
        assertTrue(cancelled.cancellationRequested)
        assertEquals("before-side-effect", cancelled.checkpoints.single().id)
        assertEquals("{\"step\":2}", cancelled.checkpoints.single().stateJson)
        assertTrue(cancelled.eventJournal.any { it.kind == AgentTaskEventKinds.CHECKPOINT })
        assertTrue(cancelled.eventJournal.any {
            it.kind == AgentTaskEventKinds.CANCELLED && it.message == "user stopped task"
        })
        assertTrue(handle.cancellationSource.isCancellationRequested)
        assertTrue(supervisor.recoverableTasks().isEmpty())
        supervisor.shutdown()
    }

    @Test
    fun taskCancellationPropagatesToNativeToolTokenExactlyOnce() {
        val cancellation = AgentTaskCancellationSource(Job()) { false }
        val token = cancellation.asNativeToolCancellationToken()
        val callbacks = AtomicInteger(0)
        token.invokeOnCancellation { callbacks.incrementAndGet() }

        cancellation.cancelExecution("first cancellation")
        cancellation.cancelExecution("duplicate cancellation")

        assertTrue(token.isCancellationRequested)
        assertEquals(1, callbacks.get())
    }

    @Test
    fun disposedTaskCancellationListenerIsNotInvoked() {
        val cancellation = AgentTaskCancellationSource(Job()) { false }
        val callbacks = AtomicInteger(0)
        val registration = cancellation.asNativeToolCancellationToken()
            .invokeOnCancellation { callbacks.incrementAndGet() }

        registration.dispose()
        cancellation.cancelExecution("cancel after disposal")

        assertEquals(0, callbacks.get())
    }

    @Test
    fun listenerRegisteredAfterTaskCancellationRunsImmediately() {
        val cancellation = AgentTaskCancellationSource(Job()) { false }
        val callbacks = AtomicInteger(0)

        cancellation.cancelExecution("cancel before listener registration")
        cancellation.asNativeToolCancellationToken()
            .invokeOnCancellation { callbacks.incrementAndGet() }

        assertEquals(1, callbacks.get())
    }

    @Test
    fun recoverableTasksResumeThroughHookFromDurableState() = runBlocking {
        val store = InMemoryAgentWorkspaceStore()
        store.upsert(workspace("paused", status = AgentWorkspaceStatus.PAUSED))
        store.upsert(workspace("running", status = AgentWorkspaceStatus.RUNNING))
        store.upsert(workspace("complete", status = AgentWorkspaceStatus.COMPLETED))
        val supervisor = AgentTaskSupervisor(store)
        val resumedIds = Collections.synchronizedList(mutableListOf<String>())

        assertEquals(
            setOf("workspace-paused", "workspace-running"),
            supervisor.recoverableTasks().map { it.workspaceId }.toSet()
        )

        val handles = supervisor.resumeRecoverable(
            hook = AgentTaskResumeHook { context, recovered ->
                resumedIds += recovered.workspaceId
                context.checkpoint(
                    checkpointId = "resumed-${recovered.taskId}",
                    stateJson = "{\"resumed\":true}"
                )
            }
        )
        handles.map { it.job }.joinAll()

        assertEquals(setOf("workspace-paused", "workspace-running"), resumedIds.toSet())
        listOf("workspace-paused", "workspace-running").forEach { workspaceId ->
            val resumed = requireNotNull(store.find(workspaceId))
            assertEquals(AgentWorkspaceStatus.COMPLETED, resumed.status)
            assertTrue(resumed.eventJournal.any { it.kind == AgentTaskEventKinds.RESUMED })
            assertTrue(resumed.checkpoints.single().stateJson.contains("resumed"))
        }
        assertEquals(AgentWorkspaceStatus.COMPLETED, store.find("workspace-complete")?.status)
        supervisor.shutdown()
    }

    @Test
    fun watchdogWarnsThenRequestsOneModelAssessmentWithoutTerminatingTask() {
        var now = 1_000L
        val store = InMemoryAgentWorkspaceStore(clock = { now })
        store.upsert(workspace("stalled", status = AgentWorkspaceStatus.RUNNING))
        val signals = Collections.synchronizedList(mutableListOf<AgentTaskLivenessSignal>())
        val supervisor = AgentTaskSupervisor(
            workspaceStore = store,
            clock = { now },
            livenessPolicy = livenessPolicy(),
            livenessListener = AgentTaskLivenessListener { signals += it }
        )

        now = 1_011L
        assertEquals(
            listOf(AgentTaskLivenessSignalKind.STALLED),
            supervisor.sweepLiveness().map(AgentTaskLivenessSignal::kind)
        )
        assertEquals(AgentWorkspaceStatus.RUNNING, store.find("workspace-stalled")?.status)

        now = 1_021L
        assertEquals(
            listOf(AgentTaskLivenessSignalKind.ASSESSMENT_REQUIRED),
            supervisor.sweepLiveness().map(AgentTaskLivenessSignal::kind)
        )
        val awaitingAssessment = requireNotNull(store.find("workspace-stalled"))
        assertEquals(AgentWorkspaceStatus.RUNNING, awaitingAssessment.status)
        assertTrue(awaitingAssessment.eventJournal.any {
            it.kind == AgentTaskEventKinds.LIVENESS_ASSESSMENT_REQUESTED
        })
        assertTrue(supervisor.sweepLiveness().isEmpty())
        assertEquals(
            listOf(
                AgentTaskLivenessSignalKind.STALLED,
                AgentTaskLivenessSignalKind.ASSESSMENT_REQUIRED
            ),
            signals.map(AgentTaskLivenessSignal::kind)
        )
        now = 1_022L
        supervisor.progress("workspace-stalled", "model.assessing", "Model selected recovery")
        assertEquals(
            listOf(
                AgentTaskLivenessSignalKind.STALLED,
                AgentTaskLivenessSignalKind.ASSESSMENT_REQUIRED,
                AgentTaskLivenessSignalKind.RECOVERED
            ),
            signals.map(AgentTaskLivenessSignal::kind)
        )
        supervisor.close()
    }

    @Test
    fun progressAfterWarningPublishesRecoveredSignal() {
        var now = 1_000L
        val store = InMemoryAgentWorkspaceStore(clock = { now })
        store.upsert(workspace("recovered", status = AgentWorkspaceStatus.RUNNING))
        val signals = Collections.synchronizedList(mutableListOf<AgentTaskLivenessSignal>())
        val supervisor = AgentTaskSupervisor(
            workspaceStore = store,
            clock = { now },
            livenessPolicy = livenessPolicy(),
            livenessListener = AgentTaskLivenessListener { signals += it }
        )

        now = 1_011L
        supervisor.sweepLiveness()
        now = 1_012L
        supervisor.progress("workspace-recovered", "tool.running", "Running tool")

        assertEquals(
            listOf(AgentTaskLivenessSignalKind.STALLED, AgentTaskLivenessSignalKind.RECOVERED),
            signals.map(AgentTaskLivenessSignal::kind)
        )
        assertFalse(
            livenessPolicy().hasUnresolvedStall(requireNotNull(store.find("workspace-recovered")))
        )
        supervisor.close()
    }

    @Test
    fun changingProgressWithinOneStageKeepsLivenessWithoutPersistingEveryUpdate() = runBlocking {
        var now = 1_000L
        val store = InMemoryAgentWorkspaceStore(clock = { now })
        val release = CompletableDeferred<Unit>()
        val started = CompletableDeferred<Unit>()
        val supervisor = AgentTaskSupervisor(
            workspaceStore = store,
            clock = { now },
            livenessPolicy = AgentTaskLivenessPolicy(
                queuedWarningMillis = 15L,
                queuedTimeoutMillis = 60L,
                runningWarningMillis = 15L,
                runningTimeoutMillis = 60L,
                waitingResponseWarningMillis = 15L,
                waitingResponseTimeoutMillis = 60L,
                watchdogIntervalMillis = 60_000L,
                heartbeatWriteThrottleMillis = 10L
            )
        )
        val handle = supervisor.submit(workspace("coalesced-progress")) {
            started.complete(Unit)
            release.await()
        }
        withTimeout(TEST_TIMEOUT_MILLIS) { started.await() }

        now = 1_001L
        supervisor.progress("workspace-coalesced-progress", "download", "Downloaded 1%")
        now = 1_008L
        supervisor.progress("workspace-coalesced-progress", "download", "Downloaded 70%")

        val coalesced = requireNotNull(store.find("workspace-coalesced-progress"))
        assertEquals(
            listOf("Downloaded 1%"),
            coalesced.eventJournal
                .filter { it.kind == AgentTaskEventKinds.PROGRESS }
                .map(AgentWorkspaceEvent::message)
        )
        now = 1_017L
        assertTrue(supervisor.sweepLiveness().isEmpty())

        now = 1_018L
        supervisor.progress("workspace-coalesced-progress", "download", "Downloaded 100%")
        assertEquals(
            listOf("Downloaded 1%", "Downloaded 100%"),
            requireNotNull(store.find("workspace-coalesced-progress"))
                .eventJournal
                .filter { it.kind == AgentTaskEventKinds.PROGRESS }
                .map(AgentWorkspaceEvent::message)
        )

        release.complete(Unit)
        handle.join()
        supervisor.shutdown()
    }

    @Test
    fun resumingAStalledTaskPublishesRecoveredSignal() = runBlocking {
        var now = 1_000L
        val store = InMemoryAgentWorkspaceStore(clock = { now })
        store.upsert(workspace("resume-stalled", status = AgentWorkspaceStatus.RUNNING))
        val signals = Collections.synchronizedList(mutableListOf<AgentTaskLivenessSignal>())
        val supervisor = AgentTaskSupervisor(
            workspaceStore = store,
            clock = { now },
            livenessPolicy = livenessPolicy(),
            livenessListener = AgentTaskLivenessListener { signals += it }
        )

        now = 1_011L
        supervisor.sweepLiveness()
        supervisor.resume(
            workspaceId = "workspace-resume-stalled",
            hook = AgentTaskResumeHook { _, _ -> }
        ).join()

        assertEquals(
            listOf(AgentTaskLivenessSignalKind.STALLED, AgentTaskLivenessSignalKind.RECOVERED),
            signals.map(AgentTaskLivenessSignal::kind)
        )
        assertEquals(AgentWorkspaceStatus.COMPLETED, store.find("workspace-resume-stalled")?.status)
        supervisor.shutdown()
    }

    @Test
    fun authenticatedLateConnectorResponseReopensOnlyItsFailedHandoff() {
        val store = InMemoryAgentWorkspaceStore()
        store.upsert(
            workspace("late", status = AgentWorkspaceStatus.FAILED).copy(
                handoffIds = listOf("codex:731"),
                errorMessage = "Codex timed out"
            )
        )
        val supervisor = AgentTaskSupervisor(store)

        assertEquals(
            null,
            supervisor.reconcileLateConnectorResponse("workspace-late", 999L)
        )
        val recovered = requireNotNull(
            supervisor.reconcileLateConnectorResponse("workspace-late", 731L)
        )

        assertEquals(AgentWorkspaceStatus.WAITING_RESPONSE, recovered.status)
        assertEquals("", recovered.errorMessage)
        assertEquals(AgentTaskEventKinds.LATE_RESPONSE, recovered.eventJournal.last().kind)
        supervisor.close()
    }

    @Test
    fun durableTurnBindingRecoversReplacementHandoffThatWasNotCheckpointed() {
        val store = InMemoryAgentWorkspaceStore()
        store.upsert(
            workspace("durable-late", status = AgentWorkspaceStatus.FAILED).copy(
                handoffIds = listOf("codex:100"),
                errorMessage = "Connector response timed out"
            )
        )
        val supervisor = AgentTaskSupervisor(store)

        assertEquals(
            null,
            supervisor.reconcileLateConnectorResponse("workspace-durable-late", 200L)
        )
        val recovered = requireNotNull(
            supervisor.reconcileLateConnectorResponse(
                workspaceId = "workspace-durable-late",
                sourceMessageId = 200L,
                durableTurnId = "workspace-durable-late"
            )
        )

        assertEquals(AgentWorkspaceStatus.WAITING_RESPONSE, recovered.status)
        assertEquals("", recovered.errorMessage)
        assertEquals(AgentTaskEventKinds.LATE_RESPONSE, recovered.eventJournal.last().kind)
        supervisor.close()
    }

    private suspend fun awaitCondition(condition: () -> Boolean) {
        withTimeout(TEST_TIMEOUT_MILLIS) {
            while (!condition()) delay(10L)
        }
    }

    private fun updateMaximum(maximum: AtomicInteger, candidate: Int) {
        while (true) {
            val current = maximum.get()
            if (candidate <= current || maximum.compareAndSet(current, candidate)) return
        }
    }

    private fun workspace(
        suffix: String,
        status: AgentWorkspaceStatus = AgentWorkspaceStatus.CREATED
    ): AgentWorkspace = AgentWorkspace(
        workspaceId = "workspace-$suffix",
        sessionId = "session-$suffix",
        conversationId = "conversation-$suffix",
        taskId = "task-$suffix",
        status = status
    )

    private fun livenessPolicy() = AgentTaskLivenessPolicy(
        queuedWarningMillis = 10L,
        queuedTimeoutMillis = 20L,
        runningWarningMillis = 10L,
        runningTimeoutMillis = 20L,
        waitingResponseWarningMillis = 10L,
        waitingResponseTimeoutMillis = 20L,
        absoluteTimeoutMillis = 1_000L,
        watchdogIntervalMillis = 60_000L,
        heartbeatWriteThrottleMillis = 0L
    )

    private companion object {
        const val TEST_TIMEOUT_MILLIS = 5_000L
    }
}
