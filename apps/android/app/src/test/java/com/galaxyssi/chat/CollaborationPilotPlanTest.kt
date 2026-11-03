package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationPilotPlanTest {
    private fun input() = JSONObject().put("format", "galaxyssi.collaboration-pilot.v1").put("pilot_id", "pilot-1")
        .put("target_id", "cloud-target").put("model_id", "fixed-model").put("trial_timeout_ms", 180_000)
        .put("text_profile", CollaborationTrialProfile(2048, 0.0, "disabled").json())
        .put("slots", JSONArray(listOf("single", "team").map { JSONObject().put("id", it).put("case_id", "case-1")
            .put("arm", it).put("prompt", "Answer using only the supplied sources.") }))

    @Test fun pairedArmsHaveEqualTaskAndThreeOpportunitiesButDifferentReviewers() {
        val plan = CollaborationPilotPlan.from(input(), 6)
        assertEquals(6, plan.maximumAdmissions)
        for (slot in plan.slots) {
            val definition = plan.definition(slot, "fresh-group", "fresh-run")
            assertEquals(3, definition.members.size)
            assertEquals(listOf("draft", "review", "final"), definition.members.map { it.memberId })
            assertEquals(setOf("draft", "review"), definition.members.last().dependsOnAgentIds)
            assertTrue(definition.members.all { it.agentId == plan.targetId &&
                it.context["collaboration_model_id"] == plan.modelId && CollaborationResearchWorkflow.stage(it) == null })
            val identities = definition.members.map { it.context[CollaborationResearchWorkflow.PERSON] }
            assertEquals(if (slot.arm == "single") 1 else 2, identities.distinct().size)
            assertEquals(identities.first(), identities.last())
        }
        assertEquals(plan.definition(plan.slots[0], "g", "r").members.map { it.objective },
            plan.definition(plan.slots[1], "g", "r").members.map { it.objective })
    }

    @Test fun noAnswerKeysUnknownFieldsOrUnbalancedPairsMayReachThePhone() {
        val changes: List<(JSONObject) -> Unit> = listOf(
            { it.put("answer_key", "private") },
            { it.getJSONArray("slots").getJSONObject(0).put("rubric", "private") },
            { it.getJSONArray("slots").remove(1) },
            { it.getJSONArray("slots").getJSONObject(1).put("arm", "single") },
            { it.getJSONArray("slots").getJSONObject(1).put("prompt", "different input") },
            { it.getJSONArray("slots").getJSONObject(1).put("id", "single") },
            { it.put("pilot_id", "../path") }
        )
        changes.forEach { change -> assertThrows(IllegalArgumentException::class.java) {
            CollaborationPilotPlan.from(input().also(change), 6)
        } }
    }

    @Test fun boundsAreExplicitAndDoNotSilentlyShortenAnInput() {
        assertThrows(IllegalArgumentException::class.java) { CollaborationPilotPlan.from(input(), 5) }
        assertThrows(IllegalArgumentException::class.java) { CollaborationPilotPlan.from(input(), 0) }
        assertThrows(IllegalArgumentException::class.java) { CollaborationPilotPlan.from(input().put("trial_timeout_ms", 0), 6) }
        val large = input().apply { repeat(2) { getJSONArray("slots").getJSONObject(it).put("prompt", "x".repeat(12_001)) } }
        assertThrows(IllegalArgumentException::class.java) { CollaborationPilotPlan.from(large, 6) }
        assertThrows(RuntimeException::class.java) { CollaborationPilotPlan.from(input().put("trial_timeout_ms", "180000"), 6) }
    }

    @Test fun trialPromptDoesNotInventOtherPeopleOrReadUnrelatedHistory() {
        val plan = CollaborationPilotPlan.from(input(), 6)
        val node = plan.definition(plan.slots.first(), "g", "r").members.last()
        val handoff = AgentSubagentContextHandoff("ignored context", listOf(
            AgentSubagentDependencyHandoff("draft", AgentSubagentStatus.SUCCEEDED, "draft evidence", false,
                provenance = AgentSubagentProvenance())
        ), 0, 60_000, false)
        val execution = AgentTeamMemberExecutionContext(node, AgentRunRequest("g", "t", "task", goal = "original task"),
            handoff, 0, AgentSubagentProvenance())
        val prompt = CollaborationTrialPrompt.build(execution)
        assertTrue(prompt.contains("Identity: analyst"))
        assertTrue(prompt.contains("original task") && prompt.contains("draft evidence"))
        assertFalse(prompt.contains("Other members") || prompt.contains("ignored context"))
        assertThrows(IllegalStateException::class.java) {
            CollaborationTrialPrompt.build(execution.copy(handoff = handoff.copy(dependencies =
                handoff.dependencies.map { it.copy(outputTruncated = true) })))
        }
    }
}
