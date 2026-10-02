package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationResearchPromptTest {
    @Test fun longGoalsNeverDisplaceCurrentAssignmentOrResponseProtocol() {
        for (size in listOf(10_000, 21_000, 100_000)) {
            val execution = execution("g".repeat(size))
            val result = CollaborationResearchPrompt.build(execution, descriptor(), emptyMap())
            assertTrue(result.text.length <= CollaborationResearchPrompt.MAX_CHARACTERS)
            assertTrue(result.text.contains("objective=Review the original evidence and propose a discriminating test."))
            assertTrue(result.text.contains(CollaborationResearchArtifact.FORMAT))
            assertTrue(result.text.contains("mode=goal_contract"))
            assertTrue(result.text.contains("Never repeat a completed side effect"))
            if ("Original user goal" in result.included) assertTrue(result.text.contains(execution.request.goal))
            else assertTrue("Original user goal" in result.omitted)
        }
    }

    @Test fun coordinatorKeepsFullCompletionContractUnderLargeContext() {
        val execution = execution("g".repeat(100_000), CollaborationResearchStage.DELIVER)
        val materials = mapOf("Prior assessment" to "a".repeat(120_000), "Historical evidence" to "h".repeat(50_000))
        val result = CollaborationResearchPrompt.build(execution, descriptor(), materials)
        assertTrue(result.text.contains(CollaborationGoalLoop.instructions()))
        assertFalse(result.text.contains("a".repeat(120_000)))
        assertTrue(result.omitted.containsAll(materials.keys))
        assertTrue(result.text.contains("omitted_sections"))
    }

    @Test fun livePlannerContractIsNotReplacedByCompletionContract() {
        val base = execution("goal")
        val execution = base.copy(member = base.member.copy(context = base.member.context +
            (CollaborationLiveGraph.PLANNER to "1")))
        assertTrue(CollaborationLiveGraph.planner(execution.member))
        val result = CollaborationResearchPrompt.build(execution, descriptor(), emptyMap())
        assertTrue(result.text.contains(CollaborationLiveGraph.instructions()))
        assertFalse(result.text.contains(CollaborationGoalLoop.instructions()))
    }

    @Test fun materialsKeepFullAssessmentsRostersAndStructuredMessages() {
        val roster = JSONArray((1..1024).map { JSONObject().put("id", "person-$it").put("role", "independent reviewer") }).toString()
        val assessment = JSONObject().put("original", "x".repeat(100_000)).toString()
        val messages = listOf(mapOf("from_instance_id" to "person-1", "text" to "quoted \"text\"\n\u4E2D\u6587 \uD83D\uDE00"))
        val base = execution("goal")
        val execution = base.copy(request = base.request.copy(context = base.request.context + mapOf(
            "collaboration_research_roster" to roster, CollaborationGoalLoop.PREVIOUS to assessment, "team_messages" to messages)))
        val materials = CollaborationResearchPrompt.materials(execution, "original history")
        assertEquals(roster, materials["Member roster"])
        assertEquals(assessment, materials["Prior assessment"])
        assertEquals(messages.first()["text"], JSONArray(materials.getValue("New team messages")).getJSONObject(0).getString("text"))
        val result = CollaborationResearchPrompt.build(execution, descriptor(), materials)
        assertTrue("Member roster" in result.omitted)
        assertTrue("Prior assessment" in result.omitted)
        assertTrue(result.text.contains("context section=Member roster"))
    }

    @Test fun partialDependencyOutputIsExplicitAndKeepsItsExactNode() {
        val base = execution("goal")
        val execution = base.copy(handoff = base.handoff.copy(dependencies = listOf(AgentSubagentDependencyHandoff(
            childId = "exact-node", status = AgentSubagentStatus.SUCCEEDED, output = "original excerpt",
            outputTruncated = true, provenance = AgentSubagentProvenance()))))
        val material = JSONArray(CollaborationResearchPrompt.materials(execution, "").getValue("Dependency evidence")).getJSONObject(0)
        assertEquals("exact-node", material.getString("node_id"))
        assertTrue(material.getBoolean("output_truncated"))
        assertEquals("original excerpt", material.getString("output"))
    }

    @Test fun missingDurableSnapshotFailsBeforeAResearchPromptCanBeDispatched() {
        assertTrue(runCatching {
            CollaborationResearchPrompt.build(execution("goal"), JSONObject().put("status", "rejected"), emptyMap())
        }.exceptionOrNull() is IllegalArgumentException)
    }

    @Test fun prepareRejectsCorruptCriteriaBeforeReadingHistoryOrPublishingAnyContract() {
        for (raw in listOf("not-json", "[] trailing", "[7]", "[{\"id\":\"c\"}]")) {
            val rows = MemoryRows()
            val store = CollaborationGoalContractStore(rows, { true })
            val base = execution("Original goal")
            val execution = base.copy(request = base.request.copy(context = base.request.context +
                (CollaborationGoalLoop.CRITERIA to raw)))
            val error = runCatching {
                CollaborationResearchPrompt.prepare(execution, store) { error("History must not be read under corrupt criteria") }
            }.exceptionOrNull()
            assertEquals(CollaborationGoalLoop.CONTRACT_RECOVERY_REQUIRED, error?.message)
            assertTrue(rows.values.isEmpty())
            assertEquals(raw, execution.request.context[CollaborationGoalLoop.CRITERIA])
        }
    }

    @Test fun preparePreservesPinnedSnapshotOnRetryAndRejectsMutableStatusOrEvidence() {
        val rows = MemoryRows()
        val store = CollaborationGoalContractStore(rows, { true })
        val base = execution("Original goal")
        val criteria = JSONArray().put(JSONObject().put("id", "c").put("requirement", "Original goal")
            .put("status", "open").put("evidence", JSONArray()))
        val execution = base.copy(request = base.request.copy(context = base.request.context +
            (CollaborationGoalLoop.CRITERIA to criteria.toString())))
        val first = CollaborationResearchPrompt.prepare(execution, store) { "Exact historical context" }
        val access = CollaborationWorkspaceAccess.from(execution)
        val pin = store.lookup(access).getString("snapshot_id")
        val retry = CollaborationResearchPrompt.prepare(execution, store) { error("A recovered dispatch must keep its original context") }
        assertTrue(first.contains(pin))
        assertTrue(retry.contains(pin))
        val originalRows = rows.values.toMap()
        criteria.getJSONObject(0).put("status", "met").put("evidence", JSONArray().put("different evidence"))
        val changed = execution.copy(request = execution.request.copy(context = execution.request.context +
            (CollaborationGoalLoop.CRITERIA to criteria.toString())))
        assertTrue(runCatching { CollaborationResearchPrompt.prepare(changed, store) { "new history" } }
            .exceptionOrNull() is IllegalArgumentException)
        assertEquals(originalRows, rows.values)
        assertEquals(pin, store.lookup(access).getString("snapshot_id"))
    }

    private class MemoryRows : CollaborationGoalContractRows {
        val values = linkedMapOf<String, String>()
        override fun read(key: String) = values[key]
        override fun commit(values: Map<String, String>) { this.values.putAll(values) }
        override fun removePrefix(prefix: String) { values.keys.removeAll { it.startsWith(prefix) } }
    }

    private fun execution(goal: String, stage: CollaborationResearchStage = CollaborationResearchStage.VERIFY) =
        AgentTeamMemberExecutionContext(
            member = AgentTeamMember("provider", AgentDeliveryMode.RESPOND, role = "reviewer",
                objective = "Review the original evidence and propose a discriminating test.", instanceId = "node",
                context = mapOf("collaboration_group_id" to "group", "collaboration_name" to "Curie",
                    CollaborationResearchWorkflow.PERSON to "person-curie",
                    CollaborationGoalLoop.ENABLED to "1", CollaborationResearchWorkflow.STAGE to stage.name)),
            request = AgentRunRequest(conversationId = "group", messageId = "turn", taskId = "task",
                runId = "child", parentRunId = "root", goal = goal, idempotencyKey = "dispatch",
                context = mapOf(CollaborationGoalLoop.CRITERIA to "[]")),
            handoff = AgentSubagentContextHandoff("", emptyList(), 0, 0, false), depth = 0,
            provenance = AgentSubagentProvenance())

    private fun descriptor() = JSONObject().put("status", "ok").put("snapshot_id", "a".repeat(64))
        .put("goal_sha256", "b".repeat(64)).put("criteria_sha256", "c".repeat(64)).put("page_count", 25)
}
