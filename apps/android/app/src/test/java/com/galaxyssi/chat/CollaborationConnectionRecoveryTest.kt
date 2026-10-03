package com.galaxyssi.chat

import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test

class CollaborationConnectionRecoveryTest {
    private fun execution() = AgentTeamMemberExecutionContext(
        AgentTeamMember("agent", AgentDeliveryMode.RESPOND),
        AgentRunRequest(conversationId = "group", messageId = "turn", taskId = "task", runId = "run",
            goal = "Check evidence", idempotencyKey = "original"),
        AgentSubagentContextHandoff("", emptyList(), 0, 0, false), 0, AgentSubagentProvenance())

    @Test fun circuitOpenBeforeDispatchWaitsInsteadOfFailing() = runBlocking {
        val adapter = ConnectionAdapter().apply { circuitChecks = 1; finishOnStart = true }
        val waits = AtomicInteger()
        val worker = AgentAdapterTeamMemberWorker(AgentAdapterDirectory().apply { register(adapter) },
            onWaiting = { _, _ -> waits.incrementAndGet() })
        val result = withTimeout(5000) { worker.execute(execution()) }
        assertEquals("saved result", result.content)
        assertEquals(1, adapter.starts.get())
        assertEquals(1, waits.get())
        assertEquals(0, adapter.cancels.get())
    }

    @Test fun postDispatchOutageReconcilesOriginalWithoutRedispatchOrCancellation() = runBlocking {
        val adapter = ConnectionAdapter()
        val waiting = CompletableDeferred<Unit>()
        val restored = AtomicInteger()
        val reconciled = AtomicInteger()
        val worker = AgentAdapterTeamMemberWorker(AgentAdapterDirectory().apply { register(adapter) },
            livenessProbeMillis = 20,
            onWaiting = { _, _ -> waiting.complete(Unit) },
            onReconnected = { restored.incrementAndGet() },
            reconcileOriginal = {
                assertEquals("original", it.request.idempotencyKey)
                reconciled.incrementAndGet()
                adapter.finish()
            })
        val task = async { worker.execute(execution()) }
        withTimeout(5000) {
            adapter.dispatched.await()
            adapter.online = false
            waiting.await()
            delay(80)
            assertFalse(task.isCompleted)
            assertEquals(0, adapter.cancels.get())
            adapter.online = true
            assertEquals("saved result", task.await().content)
        }
        assertEquals(1, adapter.starts.get())
        assertEquals(1, restored.get())
        assertEquals(1, reconciled.get())
    }

    @Test fun confirmedRemoteFailureRemainsFailureEvenWhenEndpointIsOffline() = runBlocking {
        val adapter = ConnectionAdapter()
        val worker = AgentAdapterTeamMemberWorker(AgentAdapterDirectory().apply { register(adapter) }, livenessProbeMillis = 20)
        val task = async { runCatching { worker.execute(execution()) } }
        withTimeout(5000) {
            adapter.dispatched.await()
            adapter.online = false
            adapter.finish(failed = true)
            assertEquals("verified computation error", task.await().exceptionOrNull()?.message)
        }
        assertEquals(1, adapter.starts.get())
    }

    @Test fun stopDuringOutageDoesNotReconnectOrStartAgain() = runBlocking {
        val adapter = ConnectionAdapter()
        val waiting = CompletableDeferred<Unit>()
        val worker = AgentAdapterTeamMemberWorker(AgentAdapterDirectory().apply { register(adapter) },
            livenessProbeMillis = 20, onWaiting = { _, _ -> waiting.complete(Unit) })
        val task = async { worker.execute(execution()) }
        withTimeout(5000) {
            adapter.dispatched.await()
            adapter.online = false
            waiting.await()
            task.cancel()
            task.join()
        }
        assertEquals(1, adapter.starts.get())
        assertEquals(1, adapter.cancels.get())
    }

    @Test fun dispatchedOfflineMemberReleasesCapacityForIndependentWork() = runBlocking {
        val adapter = ConnectionAdapter().apply { offlineOnStart = true }
        val worker = AgentAdapterTeamMemberWorker(AgentAdapterDirectory().apply { register(adapter) }, livenessProbeMillis = 20)
        val runtime = AgentTeamExecutionRuntime(InMemoryAgentTeamExecutionStore(), AgentSubagentLimits(maxConcurrency = 1))
        val completed = mutableListOf<String>()
        try {
            val result = withTimeout(5000) {
                runtime.start(AgentTeamDefinition("team", "lead", listOf(
                    AgentTeamMember("agent", AgentDeliveryMode.OBSERVE),
                    AgentTeamMember("healthy", AgentDeliveryMode.OBSERVE),
                    AgentTeamMember("lead", AgentDeliveryMode.RESPOND))), execution().request) {
                    if (it.member.memberId == "agent") worker.execute(it)
                    else {
                        completed += it.member.memberId
                        if (it.member.memberId == "healthy") { adapter.online = true; adapter.finish() }
                        AgentSubagentOutput("independent work completed")
                    }
                }.await()
            }
            assertEquals(AgentTeamExecutionState.SUCCEEDED, result.snapshot.state)
            assertTrue(completed.contains("healthy"))
            assertEquals(1, adapter.starts.get())
        } finally { runtime.close() }
    }
}

private class ConnectionAdapter : AgentAdapter {
    override val registration = AgentRegistration(agentId = "agent", installationId = "install", deviceId = "desktop",
        providerId = "test", displayName = "Researcher", kind = AgentConnectorKind.AGENT,
        location = AgentResourceLocation.TRUSTED_DESKTOP, status = AgentEndpointStatus.ONLINE,
        capabilities = setOf(AgentCapability.REASONING), protocol = AgentProtocolRange("1.0", "1.0", "1.0", setOf("run.events")),
        connectionKind = AgentConnectionKind.GALAXYSSI_LINK, trust = AgentResourceTrust.VERIFIED_PAIRED)
    var online = true
    var circuitChecks = 0
    var finishOnStart = false
    var offlineOnStart = false
    val starts = AtomicInteger()
    val cancels = AtomicInteger()
    val dispatched = CompletableDeferred<Unit>()
    private val events = MutableSharedFlow<AgentRunControlEvent>(extraBufferCapacity = 8)
    override suspend fun connect(): AgentProtocolAgreement {
        if (circuitChecks-- > 0) throw AgentProviderCircuitOpenException("test", 1)
        return AgentProtocolAgreement("1.0", setOf("run.events"))
    }
    override suspend fun disconnect() = Unit
    override suspend fun status() = registration.copy(status = if (online) AgentEndpointStatus.ONLINE else AgentEndpointStatus.OFFLINE)
    override suspend fun startRun(request: AgentRunRequest): AgentRunHandle {
        starts.incrementAndGet()
        dispatched.complete(Unit)
        if (offlineOnStart) online = false
        if (finishOnStart) finish()
        return AgentRunHandle(request.runId, request.taskId, registration.agentId)
    }
    suspend fun finish(failed: Boolean = false) = events.emit(AgentRunControlEvent(
        conversationId = "group", messageId = "turn", taskId = "task", runId = "run", agentId = "agent", deviceId = "desktop",
        type = if (failed) AgentRunControlEventType.RUN_FAILED else AgentRunControlEventType.RUN_COMPLETED,
        sequence = 1, payload = mapOf("result" to "saved result", "error" to if (failed) "verified computation error" else "")))
    override suspend fun sendMessage(runId: String, message: AgentControlMessage) = Unit
    override suspend fun cancelRun(runId: String) { cancels.incrementAndGet() }
    override fun observeEvents(runId: String) = events
    override suspend fun recoverRuns(): List<AgentRecoverableRun> = emptyList()
}
