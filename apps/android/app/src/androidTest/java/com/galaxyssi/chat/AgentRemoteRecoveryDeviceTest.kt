package com.galaxyssi.chat

import android.content.Context
import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.delay
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentRemoteRecoveryDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun encryptedLedgerRejectsLateRecoveryAfterCancellation() {
        withLedger { store ->
            val created = store.appendNext(event(AgentRunControlEventType.RUN_STARTED))!!
            store.appendNext(event(AgentRunControlEventType.RUN_CANCELLED))
            assertNull(store.appendRecoveryIfCurrent(event(AgentRunControlEventType.RUN_RECOVERED), created.sequence))
            assertEquals(AgentRunControlState.CANCELLED, store.snapshot("recovery-device-run")!!.state)
            assertEquals(2, store.eventsPage("recovery-device-run").size)
        }
    }

    @Test fun encryptedLedgerAcceptsExactlyOneCurrentRecoveryAndPersistsIt() {
        val name = "recovery-test-${UUID.randomUUID()}.db"
        var store = AgentRunEventStore(context, name)
        try {
            val started = store.appendNext(event(AgentRunControlEventType.RUN_STARTED))!!
            val recovery = event(AgentRunControlEventType.RUN_RECOVERED)
            assertNotNull(store.appendRecoveryIfCurrent(recovery, started.sequence))
            assertNull(store.appendRecoveryIfCurrent(recovery, started.sequence))
            store.close()
            store = AgentRunEventStore(context, name)
            assertEquals(2, store.eventsPage("recovery-device-run").size)
            assertEquals(AgentRunControlEventType.RUN_RECOVERED, store.latestEvent("recovery-device-run")!!.type)
        } finally {
            store.close()
            context.deleteDatabase(name)
        }
    }

    @Test fun staleRecoveryCannotOverwriteNewToolProgress() {
        withLedger { store ->
            val started = store.appendNext(event(AgentRunControlEventType.RUN_STARTED))!!
            store.appendNext(event(AgentRunControlEventType.TOOL_PROGRESS))
            assertNull(store.appendRecoveryIfCurrent(event(AgentRunControlEventType.RUN_RECOVERED), started.sequence))
            assertEquals(AgentRunControlEventType.TOOL_PROGRESS, store.latestEvent("recovery-device-run")!!.type)
        }
    }

    @Test fun pairedDesktopReturnsLiveReadOnlyRecoveryObservation(): Unit = runBlocking {
        assumeTrue("Explicit paired Desktop probe", InstrumentationRegistry.getArguments()
            .getString("live_recovery_probe") == "true")
        withContext(Dispatchers.IO) { GalaxySSIMqttClient.connect(context) }
        withTimeout(15_000L) {
            while (!GalaxySSIMqttClient.isConnected()) delay(100L)
        }
        val handoff = withContext(Dispatchers.IO) {
            context.getSharedPreferences("galaxyssi_agent_task_identities", Context.MODE_PRIVATE).all.keys
                .mapNotNull { key ->
                    val parts = key.split('\u001f')
                    val source = parts.getOrNull(1)?.toLongOrNull() ?: return@mapNotNull null
                    parts[0] to source
                }.sortedByDescending { it.second }.firstNotNullOfOrNull { (contactId, source) ->
                    val contact = AppStore.contactById(context, contactId) ?: return@firstNotNullOfOrNull null
                    val desktop = contact.optString("desktop_id")
                    if (desktop.isBlank()) return@firstNotNullOfOrNull null
                    val identity = AgentTaskIdentityStore.find(context, contactId, source) ?: return@firstNotNullOfOrNull null
                    val link = GalaxySSILinkProtocol.serverLink(context, desktop) ?: return@firstNotNullOfOrNull null
                    if (!link.paired || link.routes.clientRouteId != identity.clientRouteId) return@firstNotNullOfOrNull null
                    AgentHandoffRecord(AgentHandoffRequest(conversationId = identity.conversationId,
                        taskId = identity.turnId, runId = "read-only-probe", fromAgentId = "galaxyssi-mobile",
                        toAgentId = contactId, reason = "\u53ea\u8bfb\u9a8c\u8bc1\u8fdc\u7aef\u4efb\u52a1\u72b6\u6001",
                        context = mapOf("turn_id" to identity.turnId)), AgentHandoffState.ACTIVE, source)
                }
        }
        assertNotNull("No existing paired task identity", handoff)
        val start = SystemClock.elapsedRealtime()
        val result = AndroidAgentRemoteRecovery.recover(context, listOf(handoff!!)).singleOrNull()
        assertNotNull("No verified Desktop observation", result)
        assertEquals(handoff.request.conversationId, result!!.observation!!.conversationId)
        Log.i("GalaxySSIRecoveryTest", "verified_query_ms=${SystemClock.elapsedRealtime() - start} status=${result.observation!!.status}")
    }

    private fun event(type: AgentRunControlEventType) = AgentRunControlEvent(
        conversationId = "recovery-device-conversation", messageId = "recovery-device-turn",
        taskId = "recovery-device-task", runId = "recovery-device-run", agentId = "codex", deviceId = "test-device",
        type = type, sequence = 0L)

    private fun withLedger(block: (AgentRunEventStore) -> Unit) {
        val name = "recovery-test-${UUID.randomUUID()}.db"
        val store = AgentRunEventStore(context, name)
        try { block(store) } finally { store.close(); context.deleteDatabase(name) }
    }
}
