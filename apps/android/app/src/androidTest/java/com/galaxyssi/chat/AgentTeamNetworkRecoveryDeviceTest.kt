package com.galaxyssi.chat

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.PowerManager
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Uses real Android connectivity/idle state but never invokes a model or a contact. */
@RunWith(AndroidJUnit4::class)
class AgentTeamNetworkRecoveryDeviceTest {
    @Test fun waitsThroughRealOutageAndRespectsDurableControls() = runBlocking {
        val arguments = InstrumentationRegistry.getArguments()
        assumeTrue("Requires the explicit host fault-matrix runner", arguments.getString("network_fault_test") == "true")
        val minimumOutage = arguments.getString("minimum_outage_ms")?.toLong() ?: 600_000L
        require(minimumOutage in 60_000L..3_600_000L)
        val context = ApplicationProvider.getApplicationContext<Context>()
        val id = "network-fixture-${UUID.randomUUID()}"
        val control = AgentTeamDurableControl(context)
        val store = EncryptedAgentTeamExecutionStore(context)
        val runtime = AgentTeamExecutionRuntime(store)
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val power = context.getSystemService(PowerManager::class.java)
        fun online(): Boolean = connectivity.getNetworkCapabilities(connectivity.activeNetwork)?.let {
            it.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                it.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        } == true
        assertFalse("Host must disconnect networking before starting", online())
        val started = SystemClock.elapsedRealtime()
        val adapters = listOf("lead", "paused", "stopped").associateWith { NetworkFixtureAdapter("$id-$it", ::online) }
        val directory = AgentAdapterDirectory().apply { adapters.values.forEach(::register) }
        val waiting = CopyOnWriteArrayList<Long>()
        val longWaitObserved = AtomicBoolean(false)
        var idleObserved = false
        var offlineMillis = 0L
        var pausedHeldAfterReconnect = false
        val reportFile = File(context.getExternalFilesDir(null), "agent-team-network-recovery-report.json")
        fun report(phase: String, error: String? = null) {
            reportFile.writeText(JSONObject().apply {
                put("fixture_id", id)
                put("phase", phase)
                put("elapsed_ms", SystemClock.elapsedRealtime() - started)
                put("offline_ms", offlineMillis)
                put("online", online())
                put("idle_observed", idleObserved)
                put("long_wait_observed", longWaitObserved.get())
                put("waiting_count", waiting.size)
                put("lead_dispatches", adapters.getValue("lead").requests.size)
                put("paused_dispatches", adapters.getValue("paused").requests.size)
                put("stopped_dispatches", adapters.getValue("stopped").requests.size)
                put("paused_held_after_reconnect", pausedHeldAfterReconnect)
                put("model_requests", 0)
                if (error != null) put("error", error)
            }.toString(2))
        }
        val worker = AgentAdapterTeamMemberWorker(directory,
            onWaiting = { _, longWait -> waiting += SystemClock.elapsedRealtime(); if (longWait) longWaitObserved.set(true) },
            beforeDispatch = { control.awaitDispatch(it.request.runId) })
        fun execution(name: String) = AgentTeamMemberExecutionContext(
            AgentTeamMember(adapters.getValue(name).registration.agentId, AgentDeliveryMode.RESPOND),
            AgentRunRequest(conversationId = id, messageId = "$id-$name", taskId = "$id-$name", runId = "$id-$name",
                goal = "Isolated network fixture", idempotencyKey = "$id-$name"),
            AgentSubagentContextHandoff("", emptyList(), 0, 0, false), 0, AgentSubagentProvenance())
        control.set("$id-paused", AgentTeamUserControl.PAUSE)
        control.set("$id-stopped", AgentTeamUserControl.STOP)
        val leadId = adapters.getValue("lead").registration.agentId
        val request = AgentRunRequest(conversationId = id, messageId = id, taskId = id, runId = id,
            goal = "Isolated checkpoint recovery", idempotencyKey = id)
        val definition = AgentTeamDefinition(id, leadId, listOf(
            AgentTeamMember("saved-observer", AgentDeliveryMode.OBSERVE),
            AgentTeamMember(leadId, AgentDeliveryMode.RESPOND)))
        var monitor: kotlinx.coroutines.Job? = null
        var pausedJob: kotlinx.coroutines.Job? = null
        var stoppedJob: kotlinx.coroutines.Job? = null
        try {
            store.create(definition, request)
            store.append(AgentSubagentEvent(1L, id, "saved-observer", AgentSubagentEventKinds.CHILD_SUCCEEDED,
                childStatus = AgentSubagentStatus.SUCCEEDED, result = AgentSubagentChildResult(id, "saved-observer", id,
                    1, AgentSubagentStatus.SUCCEEDED, output = "saved evidence", startedAtMillis = 1, completedAtMillis = 2)))
            store.markInterrupted(id)
            val invoked = CopyOnWriteArrayList<String>()
            val task = runtime.resume(requireNotNull(store.resumeCheckpoint(id))) {
                invoked += it.member.memberId
                assertEquals("saved evidence", it.handoff.dependencies.single().output)
                worker.execute(it)
            }
            val paused = async { worker.execute(execution("paused")) }
            val stopped = async { runCatching { worker.execute(execution("stopped")) } }
            pausedJob = paused
            stoppedJob = stopped
            monitor = launch {
                while (true) {
                    idleObserved = idleObserved || power.isDeviceIdleMode
                    if (!online()) offlineMillis = SystemClock.elapsedRealtime() - started
                    report("waiting")
                    delay(5_000)
                }
            }
            withTimeout(minimumOutage + 300_000L) {
                while (!online()) delay(500)
                offlineMillis = SystemClock.elapsedRealtime() - started
                assertTrue("Real outage must meet the requested duration", offlineMillis >= minimumOutage)
                delay(1_500)
                pausedHeldAfterReconnect = adapters.getValue("paused").requests.isEmpty() && !paused.isCompleted
                assertTrue("Network recovery must not clear pause", pausedHeldAfterReconnect)
                assertTrue("Stop must remain cancelled", stopped.await().exceptionOrNull() is CancellationException)
                assertEquals(AgentTeamUserControl.STOP, AgentTeamDurableControl(context).get("$id-stopped"))
                control.set("$id-paused", AgentTeamUserControl.RUN)
                assertEquals("network fixture result", paused.await().content)
                val result = task.await()
                assertEquals(AgentTeamExecutionState.SUCCEEDED, result.snapshot.state)
                assertEquals(listOf(leadId), invoked.toList())
                assertEquals(2L, result.snapshot.members.single { it.memberId == "saved-observer" }.completedAtMillis)
            }
            assertEquals(1, adapters.getValue("lead").requests.size)
            assertEquals(1, adapters.getValue("paused").requests.size)
            assertEquals(0, adapters.getValue("stopped").requests.size)
            assertTrue("Offline retries must remain paced", waiting.size <= minimumOutage / 60_000 + 10)
            assertTrue("Must observe Android deep idle", idleObserved)
            if (minimumOutage >= 360_000L) assertTrue("Must enter long-offline waiting", longWaitObserved.get())
            monitor.cancel()
            report("passed")
        } catch (failure: Throwable) {
            monitor?.cancel()
            pausedJob?.cancel()
            stoppedJob?.cancel()
            report("failed", failure.toString())
            throw failure
        } finally {
            monitor?.cancel()
            runtime.close()
            store.remove(id)
            listOf("paused", "stopped").forEach { control.remove("$id-$it") }
        }
    }
}

private class NetworkFixtureAdapter(
    agentId: String,
    private val online: () -> Boolean
) : AgentAdapter {
    override val registration = AgentRegistration(agentId = agentId, installationId = "$agentId-installation",
        deviceId = "fixture-device", providerId = "test", displayName = agentId, kind = AgentConnectorKind.AGENT,
        location = AgentResourceLocation.PHONE, status = AgentEndpointStatus.ONLINE,
        capabilities = setOf(AgentCapability.REASONING), protocol = AgentProtocolRange("1.0", "1.0", "1.0", setOf("run.events")),
        connectionKind = AgentConnectionKind.IN_PROCESS, trust = AgentResourceTrust.PHONE_SYSTEM)
    val requests = CopyOnWriteArrayList<AgentRunRequest>()
    private val events = mutableMapOf<String, MutableSharedFlow<AgentRunControlEvent>>()
    override suspend fun connect(): AgentProtocolAgreement {
        if (!online()) throw IOException("Fixture observed Android network offline")
        return AgentProtocolAgreement("1.0", setOf("run.events"))
    }
    override suspend fun disconnect() = Unit
    override suspend fun status() = registration
    override suspend fun startRun(request: AgentRunRequest): AgentRunHandle {
        check(online()) { "Must not dispatch offline" }
        requests += request
        events.getOrPut(request.runId) { MutableSharedFlow(extraBufferCapacity = 4) }.emit(
            AgentRunControlEvent(conversationId = request.conversationId, messageId = request.messageId,
                taskId = request.taskId, runId = request.runId, agentId = registration.agentId,
                deviceId = registration.deviceId, type = AgentRunControlEventType.RUN_COMPLETED, sequence = 1L,
                payload = mapOf("result" to "network fixture result")))
        return AgentRunHandle(request.runId, request.taskId, registration.agentId)
    }
    override suspend fun sendMessage(runId: String, message: AgentControlMessage) = Unit
    override suspend fun cancelRun(runId: String) = Unit
    override fun observeEvents(runId: String): Flow<AgentRunControlEvent> =
        events.getOrPut(runId) { MutableSharedFlow(extraBufferCapacity = 4) }
    override suspend fun recoverRuns(): List<AgentRecoverableRun> = emptyList()
}
