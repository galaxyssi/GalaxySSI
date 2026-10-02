package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationCandidateGoalSnapshotTest {
    @Test fun snapshotExposesPendingHostWorkWithoutDiscardingSettledBlockers() = runBlocking {
        listOf("[]" to "blocked", checkpoint("validate") to "continue", checkpoint("done") to "blocked",
            "[{\"phase\":\"done\"}]" to "continue").forEach { (state, expected) ->
            val snapshot = snapshot(state)
            assertEquals(expected, snapshot.goalDisposition)
            assertEquals(AgentTeamExecutionState.INTERRUPTED, snapshot.state)
        }
    }

    @Test fun cancelledPendingCycleIsNotExposedAsRunnable() = runBlocking {
        val snapshot = snapshot(checkpoint("repair"), AgentSubagentRunStatus.CANCELLED)
        assertEquals("", snapshot.goalDisposition)
        assertEquals(AgentTeamExecutionState.CANCELLED, snapshot.state)
    }

    private fun checkpoint(phase: String): String {
        val target = JSONObject().put("object_id", "a".repeat(64)).put("revision", 1).put("sha256", "b".repeat(64))
        val cycle = JSONObject().put("id", "c".repeat(64)).put("object_id", target.getString("object_id"))
            .put("target", target).put("editor", "editor").put("reviewer", "reviewer").put("phase", phase)
            .put("node_id", "dispatch").put("criterion", JSONObject().put("id", "document").put("requirement", "Documented accuracy")
                .put("verification", "documentary").put("required_observations", JSONArray().put(JSONObject()
                    .put("origin", "android_cloud_tool").put("tool", "original_check"))))
        if (phase == "repair") cycle.put("review", JSONObject().put("object_id", "d".repeat(64)).put("revision", 1).put("sha256", "e".repeat(64)))
        if (phase == "done") cycle.put("result", "Stopped without certification")
        return JSONArray().put(cycle).toString()
    }

    private suspend fun snapshot(candidateState: String,
                                 terminal: AgentSubagentRunStatus = AgentSubagentRunStatus.SUCCEEDED): AgentTeamExecutionSnapshot {
        val criterion = JSONObject().put("id", "document").put("requirement", "Documented accuracy")
            .put("verification", "documentary").put("status", "open").put("evidence", JSONArray())
        val blocker = JSONObject().put("id", "lab").put("kind", "resource").put("reason", "An unrelated lab is unavailable")
            .put("resume_when", "Authorized lab is available").put("alternatives", JSONArray().put(JSONObject()
                .put("option", "Documentary sources").put("status", "not_applicable")
                .put("result", "Not a physical experiment").put("evidence", JSONArray().put("saved-check"))))
        val report = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Documentary work remains")
            .put("decision", "blocked").put("criteria", JSONArray().put(criterion))
            .put("work", JSONArray()).put("blockers", JSONArray().put(blocker))
        val people = CollaborationGoalLoop.initial(listOf(AgentTeamMember("fixture", AgentDeliveryMode.RESPOND,
            instanceId = "lead", context = mapOf("collaboration_group_id" to "group"))), "Goal")
        val request = AgentRunRequest("group", "turn", "task", runId = "run", goal = "Goal", context = mapOf(
            CollaborationGoalLoop.CRITERIA to JSONArray().put(criterion).toString(), CollaborationGoalLoop.HOST_ACCEPTANCE to "1",
            CollaborationCandidateEvolution.STATE to candidateState,
            CollaborationGoalLoop.FINISHED_WORK to JSONArray().put(CollaborationResourceRecovery.workId(blocker)).toString()))
        val store = InMemoryAgentTeamExecutionStore()
        store.create(AgentTeamDefinition("team", "fixture", people, primaryInstanceId = "lead"), request)
        store.append(AgentSubagentEvent(1, "run", "lead", AgentSubagentEventKinds.CHILD_SUCCEEDED,
            childStatus = AgentSubagentStatus.SUCCEEDED,
            result = AgentSubagentChildResult("run", "lead", "run", 1, AgentSubagentStatus.SUCCEEDED, report.toString())))
        store.append(AgentSubagentEvent(2, "run", kind = if (terminal == AgentSubagentRunStatus.CANCELLED)
            AgentSubagentEventKinds.SUPERVISOR_CANCELLED else AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED, runStatus = terminal))
        return requireNotNull(store.snapshot("run"))
    }
}
