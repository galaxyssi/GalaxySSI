package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.modelstream.ModelStreamProvider
import com.galaxyssi.chat.voice.modelstream.ModelStreamRequest
import com.galaxyssi.chat.voice.modelstream.OkHttpCloudModelStreamClient
import java.util.UUID
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real socket cancellation and production receipt routing; only unique fixture ownership is removed. */
@RunWith(AndroidJUnit4::class)
class AgentTeamCloudStopDeviceTest {
    @Test fun offlineStopClosesDetachedCloudAndPersistsInternalCancellation(): Unit = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val run = "cloud-stop-${UUID.randomUUID()}"
        val member = "fixture-member"
        val owner = stableAgentTeamMemberRunId(run, member)
        val source = (UUID.randomUUID().mostSignificantBits ushr 2).coerceAtLeast(2)
        val id = AgentCloudDispatchIdentity(source, "$run-contact", "$run-conversation", "$run-turn", "$run-task", "team-$owner")
        val ledger = EncryptedAgentManagedResponseLedger(context)
        val team = AgentTeamExecutionSnapshot(run, run, id.conversationId, id.taskId, member,
            "Synthetic detached cloud cancellation", AgentTeamVisibilityMode.BACKGROUND,
            AgentTeamExecutionState.INTERRUPTED, listOf(AgentTeamMemberSnapshot(member, "Fixture",
                AgentDeliveryMode.OBSERVE, AgentSubagentStatus.RUNNING)))
        val record = AgentManagedResponseRecord(owner, run, member, AgentDeliveryMode.OBSERVE,
            source, id.contactId, id.conversationId, id.turnId, id.taskId)
        val lease = AgentCloudDispatchRegistry.register(id)
        val failure = AtomicReference<Throwable?>()
        val receipt = AtomicReference<AgentConnectorResponse?>()
        val client = OkHttpCloudModelStreamClient()
        ledger.register(record)
        try {
            MockWebServer().use { server ->
                server.start()
                server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
                val request = ModelStreamRequest(run, ModelStreamProvider.OPENAI_COMPATIBLE,
                    server.url("/").toString(), emptyMap(), "{\"messages\":[{\"role\":\"user\",\"content\":\"Fixture\"}]}")
                val worker = thread(name = "cloud-stop-device-fixture") {
                    try {
                        lease.runRequest { client.stream(request).collect() }
                        error("The held request must not complete normally")
                    } catch (_: CancellationException) {
                        runCatching {
                            val report = AgentProviderAttemptReport(source, id.conversationId, id.turnId, id.taskId, id.actionId)
                            check(lease.acknowledgeCancellation(id, true, "Fixture cloud execution cancelled", report) {
                                receipt.set(it)
                                AgentConnectorResponseBus.publish(context, it)
                            })
                        }.exceptionOrNull()?.let(failure::set)
                    } catch (error: Throwable) {
                        failure.set(error)
                    } finally {
                        AgentCloudDispatchRegistry.release(id, lease)
                    }
                }
                try {
                    assertNotNull(withContext(Dispatchers.IO) { server.takeRequest(3, TimeUnit.SECONDS) })
                    assertEquals(1, ledger.pendingForSupervisor(run).size)
                    AgentTeamRemoteStopRecovery({ false }, { error("MQTT must not be used") })
                        .reconcile(listOf(team), ledger) { it == run }
                    withContext(Dispatchers.IO) { worker.join(3_000) }
                    assertFalse("Stopped cloud socket must settle", worker.isAlive)
                    failure.get()?.let { throw AssertionError("Fixture worker failed", it) }
                    assertTrue(lease.isCancelled)
                    assertTrue(client.activeRequestIds().isEmpty())
                    assertEquals(1, server.requestCount)
                    val cancelled = requireNotNull(receipt.get())
                    val reopened = EncryptedAgentManagedResponseLedger(context)
                    val saved = reopened.completedUnapplied().single { it.ownerRunId == owner }
                    assertFalse(requireNotNull(saved.response).success)
                    assertEquals(cancelled.content, saved.response?.content)
                    assertTrue(reopened.pendingForSupervisor(run).isEmpty())
                    assertFalse("Internal cancellation must not become an ordinary reply", AgentConnectorResponseStore.contains(context, cancelled))
                    assertTrue(AgentConnectorResponseBus.publish(context, cancelled.copy(success = true, content = "Late success")))
                    assertEquals(cancelled.content, reopened.completedUnapplied().single { it.ownerRunId == owner }.response?.content)
                    assertFalse(AgentConnectorResponseStore.contains(context, cancelled))
                } finally {
                    lease.cancel()
                    withContext(Dispatchers.IO) { worker.join(3_000) }
                }
            }
        } finally {
            lease.cancel()
            AgentCloudDispatchRegistry.release(id, lease)
            ledger.removeOwner(owner)
        }
    }
}
