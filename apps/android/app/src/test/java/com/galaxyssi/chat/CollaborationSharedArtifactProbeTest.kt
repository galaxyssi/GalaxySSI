package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationSharedArtifactProbeTest {
    private fun sources() = runBlocking {
        val source = CollaborationPilotArtifactFixture.plan()
        source.slots.map { CollaborationPilotArtifactFixture.execute(source, it).capture() }
    }
    private fun input(artifacts: List<CollaborationPilotArtifact>) = CollaborationArtifactProbeFixture.sharedInput(artifacts)

    @Test fun oneSharedControlDoesNotReadAnyCandidateOrReuseSourceContexts() {
        val artifacts = sources()
        val plan = CollaborationArtifactProbePlan.from(input(artifacts), 3)
        var reads = 0
        for (slot in plan.slots) {
            val bound = plan.bind(slot) { candidate -> reads++; artifacts.single { it.reference == candidate.reference } }
            assertEquals(slot.condition == "available", bound.candidateText != null)
            if (slot.condition == "withheld") assertNull(bound.candidate)
            val ctx = CollaborationArtifactProbeFixture.execution(bound, slot.id)
            val prompt = bound.prompt(ctx)
            assertEquals(slot.condition == "available", prompt.contains("synthetic-final"))
            for (artifact in artifacts) assertThrows(RuntimeException::class.java) {
                bound.definition(artifact.source["conversation_id"], "fresh")
            }
        }
        assertEquals(2, reads)
    }

    @Test fun multipleControlsMissingSourcesUnequalMaterialAndBudgetAreRejected() {
        val artifacts = sources()
        val changes: List<(JSONObject) -> Unit> = listOf(
            { it.getJSONArray("slots").getJSONObject(0).put("source_id", "single") },
            { it.getJSONArray("slots").getJSONObject(1).put("source_id", "") },
            { it.getJSONArray("slots").getJSONObject(2).put("source_id", "single") },
            { it.getJSONArray("slots").getJSONObject(2).put("prompt", "different") },
            { it.getJSONArray("slots").remove(0) },
            { it.getJSONArray("slots").getJSONObject(2).put("condition", "withheld").put("source_id", "") },
            { it.getJSONArray("slots").getJSONObject(0).put("case_id", "different") }
        )
        changes.forEach { change -> assertThrows(RuntimeException::class.java) {
            CollaborationArtifactProbePlan.from(input(artifacts).also(change), 3)
        } }
        assertThrows(RuntimeException::class.java) { CollaborationArtifactProbePlan.from(input(artifacts), 2) }
    }
}
