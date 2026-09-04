package com.galaxyssi.chat

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.runBlocking

@RunWith(AndroidJUnit4::class)
class AgentEncryptedStorageInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val storageNames = mutableListOf<String>()

    @After
    fun cleanUp() {
        storageNames.forEach { name ->
            context.getSharedPreferences(name, Context.MODE_PRIVATE).edit().clear().commit()
            context.deleteDatabase("$name.db")
        }
    }

    @Test
    fun encryptedPreferencesRejectPlaintextValues() {
        val name = newStorageName()
        context.getSharedPreferences(name, Context.MODE_PRIVATE)
            .edit()
            .putString("value", "obsolete plaintext")
            .commit()

        assertEquals("default", AgentEncryptedPreferences(context, name).readString("value", "default"))
    }

    @Test
    fun encryptedDatabaseDoesNotImportSameNamedPreferences() {
        val name = newStorageName()
        AgentEncryptedPreferences(context, name).writeString("value", "obsolete preference value")
        val database = AgentEncryptedDatabase(context, name)

        assertEquals("default", database.readString("value", "default"))
        assertFalse(database.contains("value"))
        database.close()
    }

    @Test
    fun currentEncryptedStoresRoundTripValues() {
        val preferencesName = newStorageName()
        val preferences = AgentEncryptedPreferences(context, preferencesName)
        assertFalse(preferences.contains("value"))
        preferences.writeString("value", "current preference value")
        assertTrue(preferences.contains("value"))
        assertEquals("current preference value", preferences.readString("value", "default"))

        val databaseName = newStorageName()
        val database = AgentEncryptedDatabase(context, databaseName)
        database.writeString("value", "current database value")
        assertTrue(database.contains("value"))
        assertEquals("current database value", database.readString("value", "default"))
        database.close()
    }

    @Test
    fun encryptedDatabaseMutatesMultipleValuesInOneTransaction() {
        val databaseName = newStorageName()
        val database = AgentEncryptedDatabase(context, databaseName)
        database.writeString("obsolete", "remove me")

        database.mutateStrings(
            upserts = mapOf(
                "run" to "created",
                "context" to "ready"
            ),
            removeKeys = listOf("obsolete")
        )

        assertEquals("created", database.readString("run", "missing"))
        assertEquals("ready", database.readString("context", "missing"))
        assertFalse(database.contains("obsolete"))
        database.close()
    }

    @Test
    fun encryptedDatabaseListsKeysByWriteRecencyWithoutDecryptingValues() {
        val databaseName = newStorageName()
        val database = AgentEncryptedDatabase(context, databaseName)
        database.writeString("campaign:older", "first")
        database.writeString("campaign:newer", "second")
        database.writeString("campaign:older", "refreshed")

        assertEquals(
            listOf("campaign:older", "campaign:newer"),
            database.recentKeys("campaign:", 2)
        )
        database.close()
    }

    @Test
    fun encryptedDatabaseListsOldestKeysWithoutDecryptingValues() {
        val name = "agent-encrypted-oldest-${UUID.randomUUID()}"
        val database = AgentEncryptedDatabase(context, name)
        try {
            database.writeString("entry:first", "first")
            database.writeString("entry:second", "second")
            database.writeString("entry:third", "third")

            assertEquals(listOf("entry:first", "entry:second"), database.oldestKeys("entry:", 2))
            assertTrue(database.oldestKeys("entry:", 0).isEmpty())
        } finally {
            database.clear()
        }
    }

    @Test
    fun connectorResponseFindsTheExactEncryptedTaskCheckpoint() {
        val turnId = "index-test-${UUID.randomUUID()}"
        val storageKey = "task:$turnId"
        val sourceMessageId = System.currentTimeMillis() * 1_000L + 731L
        val contactId = "index-test-contact"
        val store = SharedPreferencesAgentSessionStore(context, storageKey)
        val waiting = AgentSessionSnapshot(
            sessionId = "index-test-session",
            phase = AgentPhase.WAITING_RESPONSE,
            currentGoal = "Verify exact connector checkpoint lookup",
            currentScreen = ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent"),
            currentPlan = null,
            auditTrail = emptyList(),
            lastActionResult = AgentActionResult(
                actionId = "dispatch",
                success = false,
                message = "Waiting for connector response",
                metadata = mapOf(
                    "source_message_id" to sourceMessageId.toString(),
                    "contact_id" to contactId,
                    "awaiting_response" to "true"
                )
            ),
            updatedAtMillis = System.currentTimeMillis()
        )

        try {
            store.save(waiting)

            assertEquals(
                storageKey,
                SharedPreferencesAgentSessionStore.taskStorageKeyForConnectorResponse(
                    context,
                    sourceMessageId,
                    contactId
                )
            )
        } finally {
            store.save(waiting.copy(phase = AgentPhase.COMPLETED))
            store.clear()
        }
    }

    @Test
    fun teamStoreKeepsConcurrentRunsCreatedByIndependentInstances() = runBlocking {
        val databaseName = newStorageName()
        val runIds = (1..12).map { "team-concurrency-$it-${UUID.randomUUID()}" }

        coroutineScope {
            runIds.mapIndexed { index, runId ->
                async(Dispatchers.Default) {
                    val store = EncryptedAgentTeamExecutionStore(
                        AgentEncryptedDatabase(context, databaseName)
                    )
                    store.create(
                        AgentTeamDefinition(
                            teamId = "team-$index",
                            primaryAgentId = "agent-$index",
                            members = listOf(AgentTeamMember(
                                agentId = "agent-$index",
                                deliveryMode = AgentDeliveryMode.RESPOND
                            ))
                        ),
                        AgentRunRequest(
                            conversationId = "conversation-$index",
                            messageId = "message-$index",
                            taskId = "task-$index",
                            runId = runId,
                            goal = "Verify durable concurrent team storage"
                        )
                    )
                    store.append(AgentSubagentEvent(
                        sequence = 1L,
                        supervisorId = runId,
                        kind = AgentSubagentEventKinds.SUPERVISOR_STARTED,
                        timestampMillis = System.currentTimeMillis()
                    ))
                }
            }.awaitAll()
        }

        val snapshots = EncryptedAgentTeamExecutionStore(
            AgentEncryptedDatabase(context, databaseName)
        ).snapshots()
        assertEquals(runIds.toSet(), snapshots.mapTo(linkedSetOf(), AgentTeamExecutionSnapshot::supervisorRunId))
        assertTrue(snapshots.all { it.state == AgentTeamExecutionState.RUNNING })
    }

    private fun newStorageName(): String =
        "galaxyssi_current_storage_test_${UUID.randomUUID()}".also(storageNames::add)
}
