package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationAdaptivePilotMilestonesTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        override fun read(key: String) = data[key]
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
        override fun commit(values: Map<String, String>) { data.putAll(values) }
    }
    private val author = CollaborationWorkspaceAccess("group", "run", "turn", 1, "producer", "author")
    private fun artifact(id: String, observations: JSONArray = JSONArray()) = JSONObject()
        .put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Synthetic candidate")
        .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(JSONObject()
            .put("id", id).put("kind", "proposal").put("title", id).put("observations", observations)
            .put("body", JSONObject().put("content", "Executable candidate $id")))).toString()

    private fun checkpoint(scope: CollaborationWorkspaceAccess = author): AgentTeamExecutionCheckpoint {
        val member = AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = scope.nodeId,
            context = mapOf("collaboration_group_id" to scope.groupId, CollaborationResearchWorkflow.PERSON to scope.personId,
                CollaborationResearchWorkflow.STAGE to "EXECUTE", CollaborationGoalLoop.ROSTER to "false"))
        return AgentTeamExecutionCheckpoint(AgentTeamDefinition(scope.groupId, "fixture", listOf(member), primaryInstanceId = scope.nodeId),
            AgentRunRequest(scope.groupId, scope.turnId, "task", runId = scope.runId, goal = "Synthetic task",
                context = mapOf(CollaborationGoalLoop.ROUND to scope.round.toString())), emptyMap(), 0L)
    }

    @Test fun archivesEveryPageWithoutChangingWorkspaceOrClaimingPeerReads() {
        val rows = Rows(); val workspace = CollaborationResearchWorkspace(rows)
        workspace.enrollPublication(author, CollaborationResearchStage.EXECUTE)
        repeat(35) { workspace.publishMilestone(author, "m$it", artifact("candidate-$it")) }
        val before = rows.data.toMap()
        val archive = CollaborationAdaptivePilotMilestones("group", "run", "turn", workspace) { _, _ -> error("No observations") }
        val first = archive.capture(checkpoint())
        assertEquals(35, first.getJSONArray("milestones").length())
        assertFalse(first.getBoolean("peer_read_proven")); assertFalse(first.getBoolean("scientific_acceptance_proven"))
        assertEquals(before, rows.data)
        assertEquals(first.toString(), archive.capture(checkpoint()).toString())
        first.getJSONArray("milestones").getJSONObject(0).put("tampered", true)
        assertFalse(archive.snapshot().toString().contains("tampered"))
    }

    @Test fun archivesExactObservationsButNotUnpublishedData() {
        val rows = Rows(); val ledgerRows = Rows(); val ledger = CollaborationEvidenceLedger(ledgerRows)
        val workspace = CollaborationResearchWorkspace(rows, evidence = ledger::references)
        workspace.enrollPublication(author, CollaborationResearchStage.EXECUTE)
        val ref = ledger.record(author, "published", "measure", "{}", "{\"value\":1}", 1, 2)
        ledger.record(author, "private", "measure", "{}", "{\"value\":99}", 2, 3)
        workspace.publishMilestone(author, "m1", artifact("candidate", JSONArray().put(ref)))
        val before = ledgerRows.data.toMap()
        val archive = CollaborationAdaptivePilotMilestones("group", "run", "turn", workspace) { access, observation ->
            ledger.read(access, observation.getString("evidence_id"), observation.getString("sha256"))
        }.capture(checkpoint())
        val observations = archive.getJSONArray("milestones").getJSONObject(0).getJSONArray("observations")
        assertEquals(1, observations.length())
        assertEquals(ref.getString("sha256"), observations.getJSONObject(0).getString("sha256"))
        assertEquals(before, ledgerRows.data)
        assertFalse(archive.toString().contains("value\\\":99"))
    }

    @Test fun missingObservationDoesNotCommitPartialArchiveAndCanBeRetried() {
        val rows = Rows(); val ledger = CollaborationEvidenceLedger(Rows())
        val workspace = CollaborationResearchWorkspace(rows, evidence = ledger::references)
        workspace.enrollPublication(author, CollaborationResearchStage.EXECUTE)
        val ref = ledger.record(author, "published", "measure", "{}", "{\"value\":1}", 1, 2)
        workspace.publishMilestone(author, "m1", artifact("candidate", JSONArray().put(ref)))
        var available = false
        val archive = CollaborationAdaptivePilotMilestones("group", "run", "turn", workspace) { access, observation ->
            if (available) ledger.read(access, observation.getString("evidence_id"), observation.getString("sha256")) else null
        }
        assertThrows(IllegalArgumentException::class.java) { archive.capture(checkpoint()) }
        assertEquals(0, archive.snapshot().getJSONArray("milestones").length())
        available = true
        assertEquals(1, archive.capture(checkpoint()).getJSONArray("milestones").length())
    }

    @Test fun roundChangesPreserveOriginalsAndRejectOtherTrialIdentities() {
        val workspace = CollaborationResearchWorkspace(Rows())
        val archive = CollaborationAdaptivePilotMilestones("group", "run", "turn", workspace) { _, _ -> null }
        for (round in 1L..2L) {
            val scope = author.copy(round = round, nodeId = "producer-$round")
            workspace.enrollPublication(scope, CollaborationResearchStage.EXECUTE)
            workspace.publishMilestone(scope, "m1", artifact("candidate-$round"))
            assertEquals(round.toInt(), archive.capture(checkpoint(scope)).getJSONArray("milestones").length())
        }
        for (scope in listOf(author.copy(groupId = "other"), author.copy(runId = "other"), author.copy(turnId = "other"))) {
            assertThrows(IllegalArgumentException::class.java) { archive.capture(checkpoint(scope)) }
        }
        assertEquals(2, archive.snapshot().getJSONArray("milestones").length())
    }

    @Test fun emptyArchiveIsANullObservationNotAnInnovationResult() {
        val archive = CollaborationAdaptivePilotMilestones("group", "run", "turn", CollaborationResearchWorkspace(Rows())) { _, _ -> null }
        val captured = archive.capture(checkpoint())
        assertEquals(0, captured.getJSONArray("milestones").length())
        assertEquals("test_observer_not_agent", captured.getString("capture_role"))
        assertFalse(captured.getBoolean("scientific_acceptance_proven"))
    }

    @Test fun wrongProducerAttributionCannotBeArchived() {
        val workspace = CollaborationResearchWorkspace(Rows())
        workspace.enrollPublication(author, CollaborationResearchStage.EXECUTE)
        workspace.publishMilestone(author, "m1", artifact("candidate"))
        val archive = CollaborationAdaptivePilotMilestones("group", "run", "turn", workspace) { _, _ -> null }
        assertThrows(IllegalArgumentException::class.java) { archive.capture(checkpoint(author.copy(personId = "someone-else"))) }
    }
}
