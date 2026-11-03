package com.galaxyssi.chat

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CollaborationArtifactProbeSyntheticDeviceTest {
    @Test fun recoveredCandidatesSurviveReopenWithoutLeakingToSharedControl() = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("artifactProbeSynthetic") == "true")
        require(Build.MODEL == "SM-S9480")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val sourcePlan = CollaborationPilotArtifactFixture.plan("rf-${UUID.randomUUID()}")
        val raw = CollaborationPilotReportFixture.report(sourcePlan).toString()
        val digest = CollaborationRemotePilotDispatch.sha256(raw.toByteArray(Charsets.UTF_8))
        val artifacts = sourcePlan.slots.map {
            CollaborationPilotArtifact.recoverReport(sourcePlan, it, "a".repeat(64), raw, digest)
        }
        val store = CollaborationPilotArtifactStore(context, sourcePlan.id)
        try {
            artifacts.forEach { store.freeze(it) }
            val reopened = CollaborationPilotArtifactStore(context, sourcePlan.id)
            val plan = CollaborationArtifactProbePlan.from(CollaborationArtifactProbeFixture.sharedInput(artifacts), 3)
            var reads = 0
            for (slot in plan.slots) {
                val bound = plan.bind(slot) { reads++; reopened.read(it.source, it.reference) }
                val prompt = bound.prompt(CollaborationArtifactProbeFixture.execution(bound, slot.id))
                assertEquals(slot.condition == "available", prompt.contains("synthetic-final"))
                if (slot.condition == "withheld") assertNull(bound.candidate)
                else assertEquals(artifacts.single { it.source["arm"] == slot.sourceId }.finalOutput, bound.candidateText)
            }
            assertEquals(2, reads)
        } finally { store.database.clear() }
    }

    @Test fun onlyAssignedAvailableProbeReadsEncryptedSource() = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("artifactProbeSynthetic") == "true")
        require(Build.MODEL == "SM-S9480")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val sourcePlan = CollaborationPilotArtifactFixture.plan("pf-${UUID.randomUUID()}")
        val artifact = CollaborationPilotArtifactFixture.execute(sourcePlan, sourcePlan.slots.first()).capture()
        val store = CollaborationPilotArtifactStore(context, sourcePlan.id)
        try {
            store.freeze(artifact)
            val plan = CollaborationArtifactProbePlan.from(CollaborationArtifactProbeFixture.input(artifact), 2)
            var reads = 0
            for (slot in plan.slots) {
                val bound = plan.bind(slot) { reads++; store.read(it.source, it.reference) }
                val execution = CollaborationArtifactProbeFixture.execution(bound, slot.id)
                val prompt = bound.prompt(execution)
                assertEquals(slot.condition == "available", prompt.contains("synthetic-final"))
                assertFalse(prompt.contains("synthetic-draft"))
                assertNotEquals(artifact.source["conversation_id"], execution.request.conversationId)
            }
            assertEquals(1, reads)
            assertEquals(artifact.reference, store.read(artifact.source, artifact.reference).reference)
        } finally { store.database.clear() }
    }
}
