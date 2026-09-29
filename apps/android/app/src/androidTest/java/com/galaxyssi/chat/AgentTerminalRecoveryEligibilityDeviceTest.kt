package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentTerminalRecoveryEligibilityDeviceTest {
    @Test fun discoveryAfterRestartIsNotMistakenForGenerationOne() = fixture { context, fields, response ->
        assertTrue(AgentConnectorResponseStore.observeExecution(context, response.copy(executionGeneration = 3)))
        assertTrue(AndroidAgentResultRecovery.eligible(context, "isolated-desktop", fields))
        assertFalse(AndroidAgentResultRecovery.eligible(context, "isolated-desktop", fields.put("execution_generation", 1)))
        assertTrue(AndroidAgentResultRecovery.eligible(context, "isolated-desktop", fields.put("execution_generation", 3)))
        assertFalse(AndroidAgentResultRecovery.eligible(context, "isolated-desktop", fields.put("conversation_id", "other")))
    }

    @Test fun cancelledSourceAndPersistedBodyAreNotDownloadedAgain() = fixture { context, fields, response ->
        assertTrue(AgentConnectorResponseStore.append(context, response))
        assertFalse(AndroidAgentResultRecovery.eligible(context, "isolated-desktop", fields))
        AgentConnectorResponseStore.remove(context, response)
        val pending = requireNotNull(AgentPendingDeliveryStore.find(context, response.sourceMessageId))
        AgentTerminalDeliveryStore.mark(context, pending, "\u7528\u6237\u5df2\u53d6\u6d88")
        assertFalse(AndroidAgentResultRecovery.eligible(context, "isolated-desktop", fields))
    }

    @Test fun managedChildRecoversWithoutAnOrdinaryPendingRow() = fixture(managed = true) { context, fields, response ->
        assertNull(AgentPendingDeliveryStore.find(context, response.sourceMessageId))
        assertTrue(AndroidAgentResultRecovery.eligible(context, "isolated-desktop", fields))
        assertTrue(AgentConnectorResponseStore.observeExecution(context, response.copy(executionGeneration = 3)))
        assertFalse(AndroidAgentResultRecovery.eligible(context, "isolated-desktop", fields.put("execution_generation", 2)))
        assertTrue(AndroidAgentResultRecovery.eligible(context, "isolated-desktop", fields.put("execution_generation", 3)))
        AgentPendingDeliveryStore.remove(context, response.sourceMessageId)
        assertFalse("A retired source must not be revived by its managed ledger", AndroidAgentResultRecovery.eligible(
            context, "isolated-desktop", fields))
    }

    @Test fun managedRecoveryRequiresExactIdentityAndPairing() = fixture(managed = true) { context, fields, _ ->
        for (key in listOf("contact_id", "conversation_id", "turn_id", "task_id", "client_route_id", "source_message_id")) {
            for (value in listOf("", "other")) {
                assertFalse("Must reject mismatched $key", AndroidAgentResultRecovery.eligible(context,
                    "isolated-desktop", JSONObject(fields.toString()).put(key, value)))
            }
        }
        assertFalse(AndroidAgentResultRecovery.eligible(context, "unpaired-desktop", fields))
    }

    @Test fun anotherChildsReplyDoesNotCompleteThisChild() = fixture(managed = true) { context, fields, response ->
        assertTrue(AgentConnectorResponseStore.append(context,
            response.copy(sourceMessageId = 43, taskId = "sibling-task")))
        assertTrue(AgentConnectorResponseStore.containsTurn(context, response.conversationId, response.turnId))
        assertTrue(AndroidAgentResultRecovery.eligible(context, "isolated-desktop", fields))
        assertTrue(AgentConnectorResponseStore.append(context, response))
        assertFalse(AndroidAgentResultRecovery.eligible(context, "isolated-desktop", fields))
    }

    @Test fun completedAndCancelledManagedChildrenAreNotFetchedAgain() = fixture(managed = true) { context, fields, response ->
        val ledger = EncryptedAgentManagedResponseLedger(context)
        assertNotNull(ledger.complete(response))
        assertFalse(AndroidAgentResultRecovery.eligible(context, "isolated-desktop", fields))
        ledger.markApplied("managed-owner")
        assertFalse(AndroidAgentResultRecovery.eligible(context, "isolated-desktop", fields))
        assertTrue(ledger.pendingRecoveryDeliveries().isEmpty())
    }

    @Test fun reconnectDiscoveryIncludesManagedChildrenWithoutChangingTheParentHead() = fixture(managed = true) { context, _, response ->
        val parent = AgentPendingDelivery(41, response.conversationId, response.turnId, "parent-task", response.contactId)
        AgentPendingDeliveryStore.put(context, parent)
        val seen = mutableListOf<AgentPendingDelivery>()
        runBlocking {
            AndroidAgentRecoveryWake.recoverPending(context, isReady = { true }, recover = { deliveries, _ -> seen += deliveries })
        }
        assertEquals(setOf(41L, 42L), seen.map { it.sourceMessageId }.toSet())
        assertEquals(2, seen.size)
        assertNull(AgentPendingDeliveryStore.find(context, 42))
        assertFalse(AgentPendingDeliveryStore.isSuperseded(context, 41, parent.conversationId, parent.turnId))
        EncryptedAgentManagedResponseLedger(context).markApplied("managed-owner")
        seen.clear()
        runBlocking {
            AndroidAgentRecoveryWake.recoverPending(context, isReady = { true }, recover = { deliveries, _ -> seen += deliveries })
        }
        assertEquals(listOf(41L), seen.map { it.sourceMessageId })
    }

    private fun fixture(managed: Boolean = false, block: (Context, JSONObject, AgentConnectorResponse) -> Unit) {
        val context = IsolatedContext(InstrumentationRegistry.getInstrumentation().targetContext)
        try {
            val route = "r".repeat(22)
            val link = JSONObject().put("desktop_id", "isolated-desktop").put("desktop_fingerprint", "b".repeat(64))
                .put("client_route_id", route).put("link_secret", GalaxySSILinkProtocol.newLinkSecret())
                .put("local_identity_fingerprint", "a".repeat(64)).put("paired", true)
            AgentEncryptedPreferences(context, "opaque_link_v2").writeString("servers", JSONArray().put(link).toString())
            val response = AgentConnectorResponse(42, "isolated-contact", "\u539f\u59cb\u5931\u8d25\u539f\u56e0",
                "isolated-conversation", "isolated-turn", "isolated-task", success = false, taskStatus = "failed")
            AgentTaskIdentityStore.register(context, response.contactId, response.sourceMessageId,
                AgentTaskIdentity(route, response.conversationId, response.taskId, response.turnId))
            if (managed) {
                EncryptedAgentManagedResponseLedger(context).register(AgentManagedResponseRecord(
                    "managed-owner", "managed-supervisor", "codex", AgentDeliveryMode.RESPOND,
                    response.sourceMessageId, response.contactId, response.conversationId, response.turnId, response.taskId))
            } else {
                AgentPendingDeliveryStore.put(context, AgentPendingDelivery(response.sourceMessageId,
                    response.conversationId, response.turnId, response.taskId, response.contactId))
            }
            val fields = AgentConnectorResponseCodec.encode(response).put("client_route_id", route)
                .put("agent_id", "codex").apply { remove("execution_generation") }
            block(context, fields, response)
        } finally { context.close() }
    }

    private class IsolatedContext(base: Context) : ContextWrapper(base) {
        private val prefix = "terminal-eligibility-${UUID.randomUUID()}-"
        private val preferences = mutableSetOf<String>()
        override fun getApplicationContext(): Context = this
        override fun getDatabasePath(name: String): File =
            if (File(name).isAbsolute) File(name) else baseContext.getDatabasePath(prefix + name)
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory)
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?,
            errorHandler: DatabaseErrorHandler?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory, errorHandler)
        override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
            preferences.add(prefix + name)
            return baseContext.getSharedPreferences(prefix + name, mode)
        }
        fun close() {
            EncryptedAgentManagedResponseLedger(this).clear()
            AgentConnectorResponseStore.clear(this)
            AgentPendingDeliveryStore.close(this)
            baseContext.deleteDatabase(prefix + AgentConnectorResponseInbox.DATABASE_NAME)
            baseContext.deleteDatabase(prefix + AgentPendingDeliveryJournal.DATABASE_NAME)
            preferences.forEach(baseContext::deleteSharedPreferences)
        }
    }
}
