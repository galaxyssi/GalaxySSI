package com.galaxyssi.chat

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import org.json.JSONException
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic workers only; never starts a connector or modifies the user's active conversation. */
@RunWith(AndroidJUnit4::class)
class CollaborationPilotArtifactDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private fun requireDevice() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("candidateArtifactSynthetic") == "true")
        require(Build.MODEL == "SM-S9480")
    }

    @Test fun encryptedCandidateSurvivesExecutionCleanupAndStoreReopen() = runBlocking {
        requireDevice()
        val plan = CollaborationPilotArtifactFixture.plan("af-${UUID.randomUUID()}")
        val artifacts = CollaborationPilotArtifactStore(context, plan.id)
        val execution = AgentEncryptedDatabase(context, "artifact-execution-${plan.id}")
        try {
            for (slot in plan.slots) {
                val result = CollaborationPilotArtifactFixture.execute(plan, slot, EncryptedAgentTeamExecutionStore(execution))
                val artifact = result.capture()
                val ref = artifacts.freeze(artifact)
                execution.clear()
                val reopened = CollaborationPilotArtifactStore(context, plan.id)
                val recovered = reopened.read(result.source, ref)
                assertEquals(artifact.payload, recovered.payload)
                assertEquals(result.snapshot.finalOutput, recovered.finalOutput)
                assertEquals(ref, reopened.freeze(artifact))
            }
            assertEquals(2, artifacts.database.keys().size)
        } finally { execution.clear(); artifacts.database.clear() }
    }

    @Test fun concurrentDifferentResultsCannotOverwriteSameSource() = runBlocking {
        requireDevice()
        val plan = CollaborationPilotArtifactFixture.plan("af-${UUID.randomUUID()}")
        val result = CollaborationPilotArtifactFixture.execute(plan, plan.slots.first())
        val first = result.capture()
        val second = result.copy(snapshot = result.snapshot.copy(finalOutput = "replacement",
            members = result.snapshot.members.map { if (it.memberId == "final") it.copy(output = "replacement") else it })).capture()
        val store = CollaborationPilotArtifactStore(context, plan.id)
        val pool = Executors.newFixedThreadPool(2)
        try {
            val futures = listOf(first, second).map { artifact -> pool.submit(Callable {
                runCatching { CollaborationPilotArtifactStore(context, plan.id).freeze(artifact) }
            }) }
            val outcomes = futures.map { it.get(30, TimeUnit.SECONDS) }
            assertEquals(1, outcomes.count { it.isSuccess })
            assertEquals(1, outcomes.count { it.isFailure })
            val ref = outcomes.single { it.isSuccess }.getOrThrow()
            val winner = listOf(first, second).single { it.reference == ref }
            assertEquals(winner.payload, store.read(winner.source, ref).payload)
            assertEquals(1, store.database.keys().size)
        } finally { pool.shutdownNow(); store.database.clear() }
    }

    @Test fun corruptOrForeignCandidatesFailClosedWithoutReplacement() = runBlocking {
        requireDevice()
        val plan = CollaborationPilotArtifactFixture.plan("af-${UUID.randomUUID()}")
        val result = CollaborationPilotArtifactFixture.execute(plan, plan.slots.first())
        val artifact = result.capture()
        val store = CollaborationPilotArtifactStore(context, plan.id)
        val foreign = CollaborationPilotArtifactStore(context, "af-${UUID.randomUUID()}")
        try {
            assertThrows(IllegalArgumentException::class.java) { foreign.freeze(artifact) }
            assertThrows(IllegalArgumentException::class.java) { foreign.read(artifact.source, artifact.reference) }
            store.freeze(artifact)
            store.database.writeString(artifact.reference.artifactId, "corrupted fixture")
            assertThrows(JSONException::class.java) { store.read(artifact.source, artifact.reference) }
            assertThrows(JSONException::class.java) { store.freeze(artifact) }
            assertEquals("corrupted fixture", store.database.readString(artifact.reference.artifactId, ""))
            assertTrue(foreign.database.keys().isEmpty())
        } finally { store.database.clear(); foreign.database.clear() }
    }
}
