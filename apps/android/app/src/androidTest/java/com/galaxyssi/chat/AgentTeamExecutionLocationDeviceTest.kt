package com.galaxyssi.chat

import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic execution records only; never dispatch a model or touch an existing team. */
@RunWith(AndroidJUnit4::class)
class AgentTeamExecutionLocationDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun definition(id: String) = AgentTeamDefinition(id, "Local fixture", listOf(
        AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead")), primaryInstanceId = "lead")
    private fun request(id: String) = AgentRunRequest("group-$id", "turn-$id", "task-$id", runId = id, goal = "Local fixture")
    private fun access(id: String) = CollaborationWorkspaceAccess("group-$id", id, "turn-$id", 0)
    private fun isolated(id: String) = EncryptedAgentTeamExecutionStore(context, AgentEncryptedDatabase(context, "store-$id"))

    @Test fun reopeningResolvesPrivateStateWithoutExposingItToDefaultRecovery() {
        val id = "location-${UUID.randomUUID()}"
        val other = "$id-default"
        val store = isolated(id)
        val primary = EncryptedAgentTeamExecutionStore(context)
        try {
            primary.create(definition(other), request(other))
            val before = primary.deliveryCheckpoint(other)!!
            store.create(definition(id), request(id))
            store.create(definition(id), request(id))
            assertNull(primary.snapshot(id))
            val restored = AgentTeamExecutionLocations(context).state(access(id))
            assertEquals(id, restored.first.request.runId)
            assertEquals(id, restored.second.supervisorRunId)
            assertEquals(request(id).taskId, isolated(id).deliveryCheckpoint(id)!!.request.taskId)
            assertThrows(IllegalStateException::class.java) { primary.create(definition(id), request(id)) }
            assertThrows(IllegalStateException::class.java) { primary.remove(id) }
            assertNotNull(store.snapshot(id))
            store.clear()
            assertEquals(before, primary.deliveryCheckpoint(other))
            assertThrows(IllegalArgumentException::class.java) { AgentTeamExecutionLocations(context).state(access(id)) }
        } finally { store.clear(); primary.remove(other) }
    }

    @Test fun namespaceOwnerConflictAndForeignAccessAreRejectedBeforeMutation() {
        val id = "location-${UUID.randomUUID()}"
        val store = isolated(id)
        val other = isolated("other-$id")
        try {
            store.create(definition(id), request(id))
            val before = store.deliveryCheckpoint(id)
            assertThrows(IllegalStateException::class.java) { other.create(definition(id), request(id)) }
            assertThrows(IllegalArgumentException::class.java) {
                store.create(definition(id), request(id).copy(conversationId = "foreign"))
            }
            assertThrows(IllegalArgumentException::class.java) {
                AgentTeamExecutionLocations(context).state(access(id).copy(turnId = "foreign"))
            }
            assertThrows(IllegalArgumentException::class.java) {
                AgentTeamExecutionLocations(context).state(access(id).copy(groupId = "foreign"))
            }
            assertNull(other.snapshot(id))
            assertEquals(before, store.deliveryCheckpoint(id))
        } finally { store.clear(); other.clear() }
    }

    @Test fun mappedMissingRecordCannotFallBackToSameNamedDefaultRecord() {
        val id = "location-${UUID.randomUUID()}"
        val database = AgentEncryptedDatabase(context, "store-$id")
        val store = EncryptedAgentTeamExecutionStore(context, database)
        // The bare constructor models an old unindexed default record, not a model-writable API.
        val legacy = EncryptedAgentTeamExecutionStore(AgentEncryptedDatabase(context, AgentTeamExecutionLocation.DEFAULT_NAMESPACE))
        try {
            store.create(definition(id), request(id))
            database.clear()
            legacy.create(definition(id), request(id))
            assertThrows(IllegalArgumentException::class.java) { AgentTeamExecutionLocations(context).state(access(id)) }
        } finally {
            legacy.remove(id)
            store.remove(id)
        }
    }

    @Test fun existingLegacyDefaultOwnerCannotBeShadowed() {
        val id = "location-${UUID.randomUUID()}"
        val legacy = EncryptedAgentTeamExecutionStore(AgentEncryptedDatabase(context, AgentTeamExecutionLocation.DEFAULT_NAMESPACE))
        val store = isolated(id)
        try {
            legacy.create(definition(id), request(id))
            val before = legacy.deliveryCheckpoint(id)
            assertThrows(IllegalStateException::class.java) { store.create(definition(id), request(id)) }
            assertEquals(id, AgentTeamExecutionLocations(context).state(access(id)).first.request.runId)
            assertEquals(before, legacy.deliveryCheckpoint(id))
        } finally { legacy.remove(id); store.clear() }
    }

    @Test fun corruptLocationDoesNotFallBackAndCheckpointOwnerCannotBeSubstituted() {
        val id = "location-${UUID.randomUUID()}"
        val store = isolated(id)
        val directory = AgentEncryptedDatabase(context, "galaxyssi_team_execution_locations_v1")
        var original = ""
        try {
            store.create(definition(id), request(id))
            original = directory.readString(id, "")
            assertTrue(original.isNotEmpty())
            directory.writeString(id, "not-json")
            assertThrows(Exception::class.java) { AgentTeamExecutionLocations(context).state(access(id)) }
            directory.writeString(id, "")
            assertThrows(IllegalStateException::class.java) { AgentTeamExecutionLocations(context).state(access(id)) }
            val substituted = AgentTeamExecutionLocation.decode(original, id).copy(taskId = "foreign-task")
            directory.writeString(id, substituted.encode())
            assertThrows(IllegalStateException::class.java) { AgentTeamExecutionLocations(context).state(access(id)) }
        } finally {
            if (original.isNotEmpty()) directory.writeString(id, original)
            store.remove(id)
        }
    }

    @Test fun simultaneousStoreCreationAndScopedReadsDoNotDeadlockOrCrossRuns() {
        val id = "location-${UUID.randomUUID()}"
        val pool = Executors.newFixedThreadPool(2)
        val stores = (0..1).map { isolated("$id-$it") }
        try {
            val jobs = stores.mapIndexed { worker, store -> pool.submit {
                repeat(10) { iteration ->
                    val run = "$id-$worker-$iteration"
                    store.create(definition(run), request(run))
                    val state = AgentTeamExecutionLocations(context).state(access(run))
                    assertEquals(run, state.first.request.runId)
                    assertEquals(run, state.second.supervisorRunId)
                    assertNull(stores[1 - worker].snapshot(run))
                }
            } }
            jobs.forEach { it.get(30, TimeUnit.SECONDS) }
        } finally {
            pool.shutdownNow()
            check(pool.awaitTermination(5, TimeUnit.SECONDS))
            stores.forEach { it.clear() }
        }
    }

    @Test fun locationSurvivesActualProcessRestart() {
        val phase = InstrumentationRegistry.getArguments().getString("phase", "all")
        val id = "location-restart-fixture"
        val store = isolated(id)
        if (phase in setOf("all", "seed")) store.create(definition(id), request(id))
        if (phase in setOf("all", "recover")) {
            assertEquals(id, AgentTeamExecutionLocations(context).state(access(id)).first.request.runId)
            assertNull(EncryptedAgentTeamExecutionStore(context).snapshot(id))
        }
        if (phase in setOf("all", "cleanup")) store.remove(id)
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
            putString("fixture_pid", android.os.Process.myPid().toString())
        })
    }
}
