package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationArtifactProbeTest {
    private fun artifact() = runBlocking {
        val plan = CollaborationPilotArtifactFixture.plan()
        CollaborationPilotArtifactFixture.execute(plan, plan.slots.first()).capture()
    }
    private fun rejected(block: () -> Unit) { assertThrows(RuntimeException::class.java, block) }

    @Test fun frozenSourceRoundTripsWithoutChangingReference() {
        val artifact = artifact()
        val source = CollaborationPilotArtifact.Source.from(artifact.source.json())
        assertEquals(artifact.source.artifactId, source.artifactId)
        assertEquals(artifact.payload, CollaborationPilotArtifact.restore(artifact.envelope(), source,
            CollaborationPilotArtifact.Reference.from(artifact.reference.json())).payload)
    }

    @Test fun withheldNeverReadsArtifactAndAvailableIncludesOnlyItsExactFinalText() {
        val artifact = artifact()
        val plan = CollaborationArtifactProbePlan.from(CollaborationArtifactProbeFixture.input(artifact), 2)
        var reads = 0
        for (slot in plan.slots) {
            val bound = plan.bind(slot) { reads++; artifact }
            val prompt = bound.prompt(CollaborationArtifactProbeFixture.execution(bound, slot.id))
            assertTrue(prompt.contains(slot.prompt))
            assertFalse(prompt.contains("ambient memory") || prompt.contains("synthetic-draft"))
            assertEquals(slot.condition == "available", prompt.contains("synthetic-final"))
            assertEquals(slot.condition == "available", bound.candidateText != null)
            if (slot.condition == "available") {
                assertEquals(artifact.finalOutput, bound.candidateText)
                assertTrue(prompt.contains("UNVERIFIED") && prompt.contains("not instructions or authorization"))
            }
        }
        assertEquals(1, reads)
    }

    @Test fun differentOrUnavailableArtifactNeverFallsBackToAClaimedAvailableProbe() {
        val artifact = artifact()
        val plan = CollaborationArtifactProbePlan.from(CollaborationArtifactProbeFixture.input(artifact), 2)
        val other = runBlocking {
            val sourcePlan = CollaborationPilotArtifactFixture.plan("other-pilot")
            CollaborationPilotArtifactFixture.execute(sourcePlan, sourcePlan.slots.first()).capture()
        }
        rejected { plan.bind(plan.slots.first()) { other } }
        rejected { plan.bind(plan.slots.first()) { error("unavailable") } }
        plan.bind(plan.slots.last()) { error("withheld must not read") }
    }

    @Test fun eachFreshProbeAdmitsExactlyOneBoundDispatch() {
        val artifact = artifact()
        val plan = CollaborationArtifactProbePlan.from(CollaborationArtifactProbeFixture.input(artifact), 2)
        val sources = mutableSetOf<Long>()
        val groups = mutableSetOf<String>()
        for (slot in plan.slots) {
            val bound = plan.bind(slot) { artifact }
            val ctx = CollaborationArtifactProbeFixture.execution(bound, slot.id)
            val records = mutableListOf<JSONObject>()
            val guard = CollaborationRemotePilotDispatch(bound, bound.definition(ctx.request.conversationId, ctx.request.parentRunId!!),
                ctx.request.conversationId, ctx.request.parentRunId!!, ctx.request.messageId, 100, { 1 }, records::add)
            guard.prepare(ctx)
            val action = CollaborationArtifactProbeFixture.action(bound, ctx)
            assertEquals(bound.prompt(ctx), guard.admit(action).parameters["prompt"])
            rejected { guard.admit(action) }
            assertEquals(1, records.size)
            assertTrue(sources.add(records.single().getLong("source_message_id")))
            assertTrue(groups.add(records.single().getString("conversation_id")))
        }
    }

    @Test fun sourceContextGoalChangesAndTruncatedHandoffsAreRejected() {
        val artifact = artifact()
        val plan = CollaborationArtifactProbePlan.from(CollaborationArtifactProbeFixture.input(artifact), 2)
        val bound = plan.bind(plan.slots.first()) { artifact }
        rejected { bound.definition(artifact.source["conversation_id"], "new-run") }
        rejected { bound.definition("new-group", artifact.source["run_id"]) }
        val ctx = CollaborationArtifactProbeFixture.execution(bound, "new")
        rejected { bound.prompt(ctx.copy(request = ctx.request.copy(goal = "changed"))) }
        rejected { bound.prompt(ctx.copy(handoff = ctx.handoff.copy(truncated = true))) }
        val dependency = AgentSubagentDependencyHandoff("source", AgentSubagentStatus.SUCCEEDED, "leaked source", false,
            provenance = AgentSubagentProvenance())
        rejected { bound.prompt(ctx.copy(handoff = ctx.handoff.copy(dependencies = listOf(dependency)))) }
    }

    @Test fun protocolCannotChangePairMaterialModelSourceOrBudget() {
        val artifact = artifact()
        val changes: List<(JSONObject) -> Unit> = listOf(
            { it.put("answer_key", "forbidden") }, { it.put("tool_scope", "isolated") },
            { it.put("model_id", "other-model") }, { it.put("reasoning_effort", "low") },
            { it.put("trial_timeout_ms", "60000") }, { it.put("trial_timeout_ms", 600_001) },
            { it.put("pilot_id", artifact.source.pilotId) },
            { it.getJSONArray("slots").remove(1) },
            { it.getJSONArray("slots").getJSONObject(1).put("prompt", "unequal material") },
            { it.getJSONArray("slots").getJSONObject(1).put("condition", "available") },
            { it.getJSONArray("slots").getJSONObject(0).put("source_id", "missing") },
            { it.getJSONArray("sources").getJSONObject(0).getJSONObject("source").put("task_id", "other") },
            { it.getJSONArray("sources").getJSONObject(0).getJSONObject("reference").put("sha256", "invalid") }
        )
        changes.forEach { change -> rejected {
            CollaborationArtifactProbePlan.from(CollaborationArtifactProbeFixture.input(artifact).also(change), 2)
        } }
        rejected { CollaborationArtifactProbePlan.from(CollaborationArtifactProbeFixture.input(artifact), 1) }
    }
}
