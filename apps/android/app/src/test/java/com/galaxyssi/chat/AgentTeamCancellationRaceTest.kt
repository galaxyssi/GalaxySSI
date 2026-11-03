package com.galaxyssi.chat

import java.io.Closeable
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test

class AgentTeamCancellationRaceTest {
    @Test fun cancellationAfterCallbackKeepsUnconsumedEvidenceAndCompletedResult() = runBlocking {
        for (location in listOf("desktop", "cloud")) {
            RemoteFixture(location).use { fixture ->
                val adapter = fixture.preparedAdapter()
                adapter.startRun(fixture.memberRequest)
                assertTrue(fixture.provider.consumeResponse(fixture.response))
                adapter.cancelRun(fixture.memberRequest.runId)

                val record = fixture.ledger.completedUnapplied().single()
                assertEquals(fixture.response, record.response)
                assertEquals("remote evidence", fixture.provider.result("remote", record.ownerRunId)?.message)
                assertFalse(fixture.lease.isCancelled)
                assertEquals(1, fixture.dispatches.get())
            }
        }
    }

    @Test fun cancellationInsideAcknowledgementCannotRetireTheCallback() = runBlocking {
        val durable = InMemoryAgentManagedResponseLedger()
        lateinit var adapter: AgentAdapter
        lateinit var owner: String
        val ledger = object : AgentManagedResponseLedger by durable {
            override fun acknowledge(response: AgentConnectorResponse): AgentManagedResponseRecord? {
                val result = durable.acknowledge(response)
                // The live owner still exists, but the terminal evidence is already durable.
                runBlocking { adapter.cancelRun(owner) }
                return result
            }
        }
        RemoteFixture("cloud", ledger).use { fixture ->
            owner = fixture.memberRequest.runId
            adapter = fixture.preparedAdapter()
            adapter.startRun(fixture.memberRequest)
            assertTrue(fixture.provider.consumeResponse(fixture.response))
            assertEquals(fixture.response, durable.completedUnapplied().single().response)
            assertTrue("An explicit in-flight stop must still reach the cloud owner", fixture.lease.isCancelled)
        }
    }

    @Test fun graphInterruptionPreservesPendingAndJustCompletedRemoteWorkForRecovery() = runBlocking {
        withTimeout(10_000) {
            for (completeBeforeInterruption in listOf(false, true)) {
                RemoteFixture("cloud").use { fixture ->
                    val durable = InMemoryAgentTeamExecutionStore()
                    durable.create(fixture.definition, fixture.request)
                    val terminalObserved = CompletableDeferred<Unit>()
                    val adapter = requireNotNull(fixture.provider.adapter("remote"))
                    val heldAdapter = object : AgentAdapter by adapter {
                        override fun observeEvents(runId: String) = adapter.observeEvents(runId).onEach { event ->
                            if (event.type == AgentRunControlEventType.RUN_COMPLETED) {
                                terminalObserved.complete(Unit)
                                awaitCancellation()
                            }
                        }
                    }
                    val worker = fixture.worker(AgentAdapterDirectory().apply { register(heldAdapter) })
                    val crash = IOException("graph commit failed after dispatch")
                    val plan = fixture.plan()
                    AgentSubagentRuntime(
                        eventHook = durable,
                        graphExpansion = AgentSubagentExpansionHook { current, completed ->
                            if ("fast" in completed) {
                                if (completeBeforeInterruption) {
                                    assertTrue(fixture.provider.consumeResponse(fixture.response))
                                    terminalObserved.await()
                                }
                                throw crash
                            }
                            current
                        }
                    ).use { runtime ->
                        val handle = runtime.start(plan) { child ->
                            when (child.childId) {
                                "fast" -> {
                                    fixture.registered.await()
                                    AgentSubagentOutput("fast evidence")
                                }
                                "remote" -> worker.execute(fixture.execution(child))
                                else -> error("Final must not dispatch during interruption")
                            }
                        }
                        assertGraphInterruption(crash, runCatching { handle.await() }.exceptionOrNull())
                    }
                    assertFalse("Internal storage failure is not a remote stop", fixture.lease.isCancelled)
                    assertTrue(durable.records().single().events.none {
                        it.childStatus == AgentSubagentStatus.CANCELLED || it.runStatus != null
                    })
                    durable.markInterrupted(fixture.request.runId)
                    assertNull(durable.resumeCheckpoint(fixture.request.runId))
                    if (!completeBeforeInterruption) {
                        assertEquals(1, fixture.ledger.pendingForSupervisor(fixture.request.runId).size)
                        assertNotNull(fixture.ledger.complete(fixture.response))
                    }
                    val record = fixture.ledger.completedUnapplied().single()
                    assertTrue(durable.applyLateResponse(record))
                    fixture.ledger.markApplied(record.ownerRunId)
                    val checkpoint = requireNotNull(durable.resumeCheckpoint(fixture.request.runId))
                    assertEquals(setOf("fast", "remote"), checkpoint.completed.keys)
                    AgentTeamExecutionRuntime(durable).use { resumed ->
                        val result = resumed.resume(checkpoint) { execution ->
                            assertEquals("final", execution.member.memberId)
                            assertTrue(execution.handoff.dependencies.any { it.output == "remote evidence" })
                            AgentSubagentOutput("reviewed final")
                        }.await()
                        assertEquals(AgentTeamExecutionState.SUCCEEDED, result.snapshot.state)
                    }
                    assertEquals("Completed remote side effects must not replay", 1, fixture.dispatches.get())
                    val events = durable.records().single().events
                    assertEquals(events.size, events.map { it.sequence }.distinct().size)
                }
            }
        }
    }

    @Test fun stoppedTeamCancelsDetachedCloudAfterGraphInterruptionWithoutMqtt() = runBlocking {
        withTimeout(10_000) {
            RemoteFixture("cloud").use { fixture ->
                val durable = InMemoryAgentTeamExecutionStore()
                durable.create(fixture.definition, fixture.request)
                val worker = fixture.worker()
                val crash = IOException("graph commit failed with cloud work in flight")
                val released = CompletableDeferred<Unit>()
                val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
                try {
                    AgentSubagentRuntime(eventHook = durable,
                        graphExpansion = AgentSubagentExpansionHook { plan, completed ->
                            if ("fast" in completed) throw crash
                            plan
                        }).use { runtime ->
                        val subagent = runtime.start(fixture.plan()) { child ->
                            when (child.childId) {
                                "fast" -> {
                                    fixture.registered.await()
                                    AgentSubagentOutput("fast evidence")
                                }
                                "remote" -> worker.execute(fixture.execution(child))
                                else -> error("Interrupted final must not dispatch")
                            }
                        }
                        val handle = AgentTeamExecutionHandle(fixture.request.runId, subagent, durable,
                            fixture.definition.members.associateBy(AgentTeamMember::memberId)) { _, _, _ ->
                            error("No follow-up dispatch is expected")
                        }
                        val watcher = scope.watchAgentTeamExecution(handle, onSettled = {},
                            onReleased = { released.complete(Unit) })
                        assertGraphInterruption(crash, runCatching { handle.await() }.exceptionOrNull())
                        watcher.join()
                        released.await()
                        assertFalse(handle.isActive)
                        assertFalse("Interruption must leave the remote cloud request running", fixture.lease.isCancelled)
                        assertFalse("The settled production worker must have detached its live response callback",
                            fixture.provider.consumeResponse(fixture.response))
                        val snapshot = requireNotNull(durable.snapshot(fixture.request.runId))
                        assertEquals(AgentTeamExecutionState.INTERRUPTED, snapshot.state)
                        val pending = fixture.ledger.pendingForSupervisor(fixture.request.runId)
                        assertEquals(1, pending.size)
                        val stopped = AtomicBoolean(false)
                        val recovery = AgentTeamRemoteStopRecovery(isRequestReplyReady = {
                            if (stopped.get()) assertTrue("Cloud STOP must precede MQTT readiness", fixture.lease.isCancelled)
                            false
                        }, cancelDesktop = { error("Offline recovery must not access Desktop transport") })
                        recovery.reconcile(listOf(snapshot), fixture.ledger) { stopped.get() }
                        assertFalse("Interruption alone is not user STOP", fixture.lease.isCancelled)
                        stopped.set(true)
                        repeat(2) { recovery.reconcile(listOf(snapshot), fixture.ledger) { stopped.get() } }
                        assertTrue(fixture.lease.isCancelled)
                        assertFalse(fixture.lease.claimCompletion())
                        assertEquals("Cancellation must not acknowledge or retire pending evidence", pending,
                            fixture.ledger.pendingForSupervisor(fixture.request.runId))
                        assertTrue(fixture.ledger.completedUnapplied().isEmpty())
                        val terminal = requireNotNull(fixture.ledger.complete(fixture.response))
                        assertEquals(AgentManagedResponseState.COMPLETED, terminal.state)
                        assertEquals(fixture.response, fixture.ledger.completedUnapplied().single().response)
                        assertEquals(1, fixture.dispatches.get())
                    }
                } finally { scope.cancel() }
            }
        }
    }

    @Test fun stoppedTeamCloudRecoveryIsolatesAllSixLeaseIdentityFields() = runBlocking {
        RemoteFixture("cloud").use { fixture ->
            val durable = InMemoryAgentTeamExecutionStore()
            durable.create(fixture.definition, fixture.request)
            fixture.preparedAdapter().startRun(fixture.memberRequest)
            val pending = fixture.ledger.pendingForSupervisor(fixture.request.runId).single()
            val exact = AgentCloudDispatchIdentity(pending.sourceMessageId, pending.contactId, pending.conversationId,
                pending.turnId, pending.taskId, "team-${pending.ownerRunId}")
            val otherIdentities = listOf(exact.copy(sourceMessageId = nextSource.incrementAndGet()),
                exact.copy(contactId = "other-contact"), exact.copy(conversationId = "other-group"),
                exact.copy(turnId = "other-turn"), exact.copy(taskId = "other-task"),
                exact.copy(actionId = "team-other-owner"))
            val others = otherIdentities.associateWith(AgentCloudDispatchRegistry::register)
            try {
                offlineStopRecovery().reconcile(listOf(requireNotNull(durable.snapshot(fixture.request.runId))), fixture.ledger) { true }
                assertTrue(fixture.lease.isCancelled)
                others.forEach { (identity, lease) ->
                    assertFalse("STOP crossed a cloud identity boundary: $identity", lease.isCancelled)
                    assertTrue("Unrelated dispatch must remain active: $identity", lease.claimCompletion())
                }
                assertEquals(listOf(pending), fixture.ledger.pendingForSupervisor(fixture.request.runId))
                assertTrue(fixture.ledger.completedUnapplied().isEmpty())
            } finally {
                others.forEach { (identity, lease) -> AgentCloudDispatchRegistry.release(identity, lease) }
            }
        }
    }

    @Test fun cloudStopRecoveryRequiresStoppedOwningTeamAndPendingEvidence() = runBlocking {
        RemoteFixture("cloud").use { fixture ->
            val durable = InMemoryAgentTeamExecutionStore()
            durable.create(fixture.definition, fixture.request)
            fixture.preparedAdapter().startRun(fixture.memberRequest)
            val snapshot = requireNotNull(durable.snapshot(fixture.request.runId))
            val recovery = offlineStopRecovery()
            recovery.reconcile(listOf(snapshot), fixture.ledger) { false }
            assertFalse("A running or paused team is not stopped", fixture.lease.isCancelled)
            val mismatches = listOf(snapshot.copy(supervisorRunId = "other-supervisor"),
                snapshot.copy(conversationId = "other-group"),
                snapshot.copy(members = snapshot.members.filterNot { it.memberId == "remote" }))
            mismatches.forEach { other ->
                recovery.reconcile(listOf(other), fixture.ledger) { true }
                assertFalse("Only the exact owning team may stop a pending lease", fixture.lease.isCancelled)
            }
            val terminal = requireNotNull(fixture.ledger.acknowledge(fixture.response))
            assertEquals(AgentManagedResponseState.COMPLETED, terminal.state)
            recovery.reconcile(listOf(snapshot), fixture.ledger) { true }
            assertFalse("Completed evidence must not be treated as a pending stop outbox", fixture.lease.isCancelled)
            assertEquals(listOf(terminal), fixture.ledger.completedUnapplied())
        }
    }

    @Test fun cloudStopRecoveryCannotCancelCompletedLeaseOrConsumeItsEvidence() = runBlocking {
        RemoteFixture("cloud").use { fixture ->
            val durable = InMemoryAgentTeamExecutionStore()
            durable.create(fixture.definition, fixture.request)
            fixture.preparedAdapter().startRun(fixture.memberRequest)
            val snapshot = requireNotNull(durable.snapshot(fixture.request.runId))
            val pending = fixture.ledger.pendingForSupervisor(fixture.request.runId)
            assertTrue(fixture.lease.claimCompletion())
            val recovery = offlineStopRecovery()
            recovery.reconcile(listOf(snapshot), fixture.ledger) { true }
            assertFalse("Completion must remain the lease's terminal winner", fixture.lease.isCancelled)
            assertFalse(fixture.lease.cancel())
            assertEquals(pending, fixture.ledger.pendingForSupervisor(fixture.request.runId))
            assertTrue(fixture.provider.consumeResponse(fixture.response))
            val terminal = fixture.ledger.completedUnapplied().single()
            recovery.reconcile(listOf(snapshot), fixture.ledger) { true }
            assertEquals(listOf(terminal), fixture.ledger.completedUnapplied())
            assertEquals(fixture.response, terminal.response)
            assertFalse(fixture.lease.isCancelled)
        }
    }

    @Test fun managedCloudCancellationReceiptWaitsForExecutionUnwindAndRejectsLateSuccess() = runBlocking {
        withTimeout(10_000) {
            for (detached in listOf(false, true)) {
                RemoteFixture("cloud").use { fixture ->
                    val durable = InMemoryAgentTeamExecutionStore()
                    durable.create(fixture.definition, fixture.request)
                    fixture.preparedAdapter().startRun(fixture.memberRequest)
                    if (detached) fixture.provider.detachRun("remote", fixture.memberRequest.runId)
                    val identity = fixture.identity
                    val attempts = AgentProviderAttemptTracker(AgentProviderAttemptReport(identity.sourceMessageId,
                        identity.conversationId, identity.turnId, identity.taskId, identity.actionId))
                    attempts.start("cancelled-request", "remote", "provider", "model", System.currentTimeMillis())
                    val entered = CompletableDeferred<Unit>()
                    val unwinding = CompletableDeferred<Unit>()
                    val releaseUnwind = CompletableDeferred<Unit>()
                    val published = CompletableDeferred<AgentConnectorResponse>()
                    val pending = fixture.ledger.pendingForSupervisor(fixture.request.runId)
                    val execution = async(Dispatchers.Default) {
                        try {
                            fixture.lease.runRequest<Boolean> {
                                try {
                                    entered.complete(Unit)
                                    awaitCancellation()
                                } finally {
                                    withContext(NonCancellable) {
                                        unwinding.complete(Unit)
                                        releaseUnwind.await()
                                    }
                                }
                            }
                        } catch (_: CancellationException) {
                            attempts.cancel(System.currentTimeMillis())
                            fixture.lease.acknowledgeCancellation(identity, true, "Cloud execution cancelled", attempts.report) { receipt ->
                                // The production response bus uses these same live-owner and durable-ledger interceptors.
                                val consumed = AgentManagedConnectorResponseRegistry.consume(receipt) ||
                                    fixture.ledger.complete(receipt) != null
                                check(consumed) { "Managed cancellation must not become an ordinary incoming answer" }
                                published.complete(receipt)
                                consumed
                            }
                        }
                    }
                    try {
                        entered.await()
                        offlineStopRecovery().reconcile(listOf(requireNotNull(durable.snapshot(fixture.request.runId))), fixture.ledger) { true }
                        unwinding.await()
                        assertTrue(fixture.lease.isCancelled)
                        assertFalse("Requesting STOP must not fabricate an execution acknowledgment", published.isCompleted)
                        assertEquals(pending, fixture.ledger.pendingForSupervisor(fixture.request.runId))
                        assertTrue(fixture.ledger.completedUnapplied().isEmpty())
                        releaseUnwind.complete(Unit)
                        assertTrue(execution.await())
                        val receipt = published.await()
                        assertEquals(identity.sourceMessageId, receipt.sourceMessageId)
                        assertEquals(identity.contactId, receipt.contactId)
                        assertEquals(identity.conversationId, receipt.conversationId)
                        assertEquals(identity.turnId, receipt.turnId)
                        assertEquals(identity.taskId, receipt.taskId)
                        assertEquals("Cloud execution cancelled", receipt.content)
                        assertFalse(receipt.success)
                        assertEquals("cancelled", receipt.providerAttempts?.attempts?.single()?.state)
                        assertTrue(fixture.ledger.pendingForSupervisor(fixture.request.runId).isEmpty())
                        val terminal = fixture.ledger.completedUnapplied().single()
                        assertEquals(AgentManagedResponseState.COMPLETED, terminal.state)
                        assertEquals(receipt, terminal.response)
                        assertFalse(fixture.provider.consumeResponse(fixture.response))
                        assertEquals("Late success must not replace the cancellation acknowledgment", terminal,
                            fixture.ledger.complete(fixture.response))
                        assertEquals(listOf(terminal), fixture.ledger.completedUnapplied())
                        assertEquals(1, fixture.dispatches.get())
                    } finally {
                        releaseUnwind.complete(Unit)
                        fixture.lease.cancel()
                    }
                }
            }
        }
    }

    @Test fun nestedCloudCancellationTransitionsActiveLeaseBeforeAcknowledgingExecution() = runBlocking {
        RemoteFixture("cloud").use { fixture ->
            fixture.preparedAdapter().startRun(fixture.memberRequest)
            val identity = fixture.identity
            val pending = fixture.ledger.pendingForSupervisor(fixture.request.runId)
            val attempts = AgentProviderAttemptTracker(AgentProviderAttemptReport(identity.sourceMessageId,
                identity.conversationId, identity.turnId, identity.taskId, identity.actionId))
            attempts.start("nested-request", "remote", "provider", "model", System.currentTimeMillis())
            var acknowledged = false
            try {
                fixture.lease.runRequest<Unit> { throw CancellationException("Nested request cancelled") }
            } catch (_: CancellationException) {
                assertFalse("Nested cancellation has not yet transitioned the dispatch lease", fixture.lease.isCancelled)
                assertEquals(pending, fixture.ledger.pendingForSupervisor(fixture.request.runId))
                attempts.cancel(System.currentTimeMillis())
                acknowledged = fixture.lease.acknowledgeCancellation(identity, true, "Cloud execution cancelled", attempts.report) { receipt ->
                    assertTrue("Transition the lease before publishing its acknowledgment", fixture.lease.isCancelled)
                    AgentManagedConnectorResponseRegistry.consume(receipt) || fixture.ledger.complete(receipt) != null
                }
            }
            assertTrue(acknowledged)
            assertTrue(fixture.lease.isCancelled)
            assertFalse(fixture.lease.claimCompletion())
            assertTrue(fixture.ledger.pendingForSupervisor(fixture.request.runId).isEmpty())
            val terminal = fixture.ledger.completedUnapplied().single()
            assertEquals(AgentManagedResponseState.COMPLETED, terminal.state)
            assertEquals(false, terminal.response?.success)
            assertEquals("Cloud execution cancelled", terminal.response?.content)
            assertEquals("cancelled", terminal.response?.providerAttempts?.attempts?.single()?.state)
            assertEquals(terminal, fixture.ledger.complete(fixture.response))
        }
    }

    @Test fun cancellationAcknowledgmentCannotPublishForOrdinaryOrCompletedCloudDispatch() {
        val identity = AgentCloudDispatchIdentity(nextSource.incrementAndGet(), "cloud", "group", "turn", "task", "action")
        val report = AgentProviderAttemptReport(identity.sourceMessageId, identity.conversationId,
            identity.turnId, identity.taskId, identity.actionId)
        val ordinary = AgentCloudDispatchLease()
        assertFalse(ordinary.acknowledgeCancellation(identity, false, "Cancelled", report) {
            error("An ordinary cloud cancellation must not publish a managed answer")
        })
        assertTrue(ordinary.isCancelled)
        val completed = AgentCloudDispatchLease()
        assertTrue(completed.claimCompletion())
        assertFalse(completed.cancel())
        assertFalse(completed.acknowledgeCancellation(identity, true, "Cancelled", report) {
            error("A completed cloud dispatch cannot acquire a cancellation receipt")
        })
        assertFalse(completed.isCancelled)
    }

    @Test fun explicitCancellationStillStopsTheCloudRun() = runBlocking {
        withTimeout(10_000) {
            RemoteFixture("cloud").use { fixture ->
                val worker = fixture.worker()
                val durable = InMemoryAgentTeamExecutionStore()
                durable.create(fixture.definition, fixture.request)
                AgentSubagentRuntime(eventHook = durable,
                    graphExpansion = AgentSubagentExpansionHook { plan, _ -> plan }).use { runtime ->
                    val handle = runtime.start(fixture.plan()) { child ->
                        when (child.childId) {
                            "remote" -> worker.execute(fixture.execution(child))
                            "fast" -> awaitCancellation()
                            else -> error("Cancelled barrier dispatched")
                        }
                    }
                    fixture.registered.await()
                    assertTrue(handle.cancel("User stop"))
                    assertEquals(AgentSubagentRunStatus.CANCELLED, handle.await().status)
                    assertTrue(fixture.lease.isCancelled)
                    assertEquals(1, fixture.ledger.pendingForSupervisor(fixture.request.runId).size)
                    assertNotNull(fixture.ledger.complete(fixture.response))
                    val record = fixture.ledger.completedUnapplied().single()
                    assertEquals(fixture.response, record.response)
                    val before = durable.records().single().events
                    assertTrue(durable.applyLateResponse(record))
                    fixture.ledger.markApplied(record.ownerRunId)
                    assertTrue(fixture.ledger.completedUnapplied().isEmpty())
                    assertEquals(before, durable.records().single().events)
                    val snapshot = requireNotNull(durable.snapshot(fixture.request.runId))
                    assertEquals(AgentTeamExecutionState.CANCELLED, snapshot.state)
                    assertEquals(AgentSubagentStatus.CANCELLED, snapshot.members.single { it.memberId == "remote" }.status)
                }
            }
        }
    }

    @Test fun failFastStillStopsTheCloudRun() = runBlocking {
        withTimeout(10_000) {
            RemoteFixture("cloud").use { fixture ->
                val worker = fixture.worker()
                AgentSubagentRuntime(graphExpansion = AgentSubagentExpansionHook { plan, _ -> plan }).use { runtime ->
                    val handle = runtime.start(fixture.plan().copy(failurePolicy = AgentSubagentFailurePolicy.FAIL_FAST)) { child ->
                        when (child.childId) {
                            "remote" -> worker.execute(fixture.execution(child))
                            "fast" -> {
                                fixture.registered.await()
                                error("member failed")
                            }
                            else -> error("Failed barrier dispatched")
                        }
                    }
                    assertEquals(AgentSubagentRunStatus.FAILED, handle.await().status)
                    assertTrue(fixture.lease.isCancelled)
                }
            }
        }
    }

    @Test fun shutdownWatcherOwnsSequenceUntilTerminalPersistenceFinishes() = runBlocking {
        withTimeout(10_000) {
            for (cancelScopeBeforeWatch in listOf(false, true)) {
                val durable = InMemoryAgentTeamExecutionStore()
                val terminalWrite = CompletableDeferred<Unit>()
                val releaseWrite = CompletableDeferred<Unit>()
                val workerStarted = CompletableDeferred<Unit>()
                val released = CompletableDeferred<Unit>()
                val ownsSequence = AtomicBoolean(true)
                val settled = AtomicInteger()
                val store = object : AgentTeamExecutionStore by durable {
                    override suspend fun append(event: AgentSubagentEvent) {
                        if (event.runStatus != null) {
                            terminalWrite.complete(Unit)
                            releaseWrite.await()
                        }
                        durable.append(event)
                    }
                }
                val runtime = AgentTeamExecutionRuntime(store)
                val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
                val request = request("watch-shutdown-$cancelScopeBeforeWatch")
                val handle = runtime.start(singleMemberTeam(), request) {
                    workerStarted.complete(Unit)
                    awaitCancellation()
                }
                try {
                    workerStarted.await()
                    if (cancelScopeBeforeWatch) scope.cancel()
                    val watcher = scope.watchAgentTeamExecution(handle, onSettled = {
                        assertFalse(handle.isActive)
                        assertEquals(AgentTeamExecutionState.CANCELLED, durable.snapshot(request.runId)?.state)
                        settled.incrementAndGet()
                    }, onReleased = {
                        assertFalse(handle.isActive)
                        ownsSequence.set(false)
                        released.complete(Unit)
                    })
                    runtime.close()
                    scope.cancel()
                    terminalWrite.await()
                    assertTrue(handle.isActive)
                    assertTrue("Late callback must not claim the still-live sequence", ownsSequence.get())
                    assertFalse(released.isCompleted)
                    assertEquals(0, settled.get())
                    releaseWrite.complete(Unit)
                    watcher.join()
                    released.await()
                    assertFalse(ownsSequence.get())
                    assertEquals(1, settled.get())
                    val events = durable.records().single().events
                    assertEquals(1, events.count { it.runStatus != null })
                    assertEquals(events.size, events.map { it.sequence }.distinct().size)
                } finally {
                    releaseWrite.complete(Unit)
                    runtime.close()
                    scope.cancel()
                }
            }
        }
    }

    @Test fun cancellingOnlyWatcherCannotReleaseOrCancelAnExecutingHandle() = runBlocking {
        withTimeout(10_000) {
            val durable = InMemoryAgentTeamExecutionStore()
            val workerStarted = CompletableDeferred<Unit>()
            val finishWorker = CompletableDeferred<Unit>()
            val released = CompletableDeferred<Unit>()
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            AgentTeamExecutionRuntime(durable).use { runtime ->
                val handle = runtime.start(singleMemberTeam(), request("watch-only")) {
                    workerStarted.complete(Unit)
                    finishWorker.await()
                    AgentSubagentOutput("done")
                }
                val watcher = scope.watchAgentTeamExecution(handle, onSettled = {
                    assertEquals(AgentTeamExecutionState.SUCCEEDED, durable.snapshot(handle.supervisorRunId)?.state)
                }, onReleased = { released.complete(Unit) })
                try {
                    workerStarted.await()
                    watcher.cancel()
                    assertTrue(handle.isActive)
                    assertFalse(released.isCompleted)
                    assertFalse(watcher.isCompleted)
                    finishWorker.complete(Unit)
                    watcher.join()
                    released.await()
                    assertEquals(AgentTeamExecutionState.SUCCEEDED, handle.await().snapshot.state)
                } finally {
                    finishWorker.complete(Unit)
                    handle.cancel()
                    scope.cancel()
                }
            }
        }
    }

    private class RemoteFixture(
        location: String,
        durable: AgentManagedResponseLedger = InMemoryAgentManagedResponseLedger()
    ) : Closeable {
        private val source = nextSource.incrementAndGet()
        val request = request("remote-race-$source")
        val member = AgentTeamMember("remote", AgentDeliveryMode.OBSERVE)
        val memberRequest = request.copy(runId = stableAgentTeamMemberRunId(request.runId, "remote"),
            parentRunId = request.runId, deliveryMode = AgentDeliveryMode.OBSERVE, context = mapOf("managed_team" to true))
        val identity = AgentCloudDispatchIdentity(source, "remote", request.conversationId,
            request.messageId, request.taskId, "team-${memberRequest.runId}")
        val lease = AgentCloudDispatchRegistry.register(identity)
        val registered = CompletableDeferred<Unit>()
        val ledger = object : AgentManagedResponseLedger by durable {
            override fun register(record: AgentManagedResponseRecord) {
                durable.register(record)
                registered.complete(Unit)
            }
        }
        val dispatches = AtomicInteger()
        val provider = ActionExecutorAgentProvider({ listOf(registration()) }, object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                dispatches.incrementAndGet()
                return AgentActionResult(action.id, true, "Waiting", mapOf(
                    "awaiting_response" to "true", "resource_location" to location,
                    "source_message_id" to source.toString(), "contact_id" to identity.contactId,
                    "conversation_id" to identity.conversationId, "turn_id" to identity.turnId,
                    "task_id" to identity.taskId))
            }
        }, managedResponses = ledger)
        val response = AgentConnectorResponse(source, "remote", "remote evidence",
            conversationId = request.conversationId, turnId = request.messageId, taskId = request.taskId)
        val definition = AgentTeamDefinition("race-team-$source", "final", listOf(
            AgentTeamMember("fast", AgentDeliveryMode.OBSERVE), member,
            AgentTeamMember("final", AgentDeliveryMode.RESPOND, dependsOnAgentIds = setOf("fast", "remote"))))

        suspend fun preparedAdapter(): AgentAdapter {
            provider.prepare("remote", memberRequest, AgentAction(identity.actionId, AgentActionKind.CALL_CONNECTOR,
                "Remote", AgentRisk.LOW, AgentActionStatus.RUNNING, "Test managed dispatch",
                mapOf("connector_id" to "remote", "prompt" to "Review evidence"), false), screen())
            return requireNotNull(provider.adapter("remote"))
        }

        fun worker(directory: AgentAdapterDirectory = AgentAdapterDirectory().apply { register(provider) }) =
            ActionExecutorAgentTeamMemberWorker(provider, directory, ::screen)

        fun plan() = AgentSubagentPlan(request.runId, listOf(AgentSubagentChild("fast"),
            AgentSubagentChild("remote"), AgentSubagentChild("final", dependencies = setOf("fast", "remote"))),
            completionBarrierChildId = "final")

        fun execution(child: AgentSubagentExecutionContext) = AgentTeamMemberExecutionContext(member, memberRequest,
            child.handoff, child.depth, child.provenance, child.suspendExecutionPermit)

        override fun close() {
            provider.detachRun("remote", memberRequest.runId)
            AgentCloudDispatchRegistry.release(identity, lease)
        }
    }

    private companion object {
        val nextSource = AtomicLong(7_300_000)
        fun assertGraphInterruption(expected: IOException, actual: Throwable?) {
            assertTrue("Expected IOException, got $actual", actual is IOException)
            assertEquals(expected.message, actual?.message)
            assertTrue("Coroutine-recovered exception must retain the original failure in its cause chain",
                generateSequence(actual) { it.cause }.any { it === expected })
        }
        fun offlineStopRecovery() = AgentTeamRemoteStopRecovery(isRequestReplyReady = { false },
            cancelDesktop = { error("Offline recovery must not access Desktop transport") })
        fun request(runId: String) = AgentRunRequest(conversationId = "race-conversation", messageId = "turn-$runId",
            taskId = "task-$runId", runId = runId, goal = "Review evidence", idempotencyKey = runId)
        fun singleMemberTeam() = AgentTeamDefinition("watch-team", "final",
            listOf(AgentTeamMember("final", AgentDeliveryMode.RESPOND)))
        fun screen() = ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent")
        fun registration() = AgentRegistration(agentId = "remote", installationId = "race-installation",
            deviceId = "race-device", providerId = "race-provider", displayName = "Remote",
            kind = AgentConnectorKind.AGENT, location = AgentResourceLocation.TRUSTED_DESKTOP,
            status = AgentEndpointStatus.ONLINE, capabilities = setOf(AgentCapability.CODE),
            protocol = AgentProtocolRange("1.0", "1.0", "1.0",
                features = setOf("run.cancel", "run.recover", "run.events", "message.respond", "message.observe")),
            connectionKind = AgentConnectionKind.GALAXYSSI_LINK, trust = AgentResourceTrust.VERIFIED_PAIRED,
            adapterType = "codex-app-server-or-cli")
    }
}
