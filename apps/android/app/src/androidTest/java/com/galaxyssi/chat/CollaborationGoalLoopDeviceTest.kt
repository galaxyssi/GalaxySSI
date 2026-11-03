package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Isolated encrypted database only; no model requests, contacts, or existing research runs. */
@RunWith(AndroidJUnit4::class)
class CollaborationGoalLoopDeviceTest {
    @Test fun recruitmentProjectionSurvivesCrashBetweenGroupWriteAndCheckpointAcknowledgement() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val groupId = "recruitment-fixture-${UUID.randomUUID()}"
        val database = AgentEncryptedDatabase(context, groupId)
        val groups = CollaborationGroupStore(context)
        val names = CollaborationGroupStore.names(context)
        val store = EncryptedAgentTeamExecutionStore(database, recruitmentNames = { names })
        groups.update(groupId) { it.copy(members = listOf(
            CollaborationMember("lead", names[0], "fixture", "Fixture"),
            CollaborationMember("worker", names[1], "fixture", "Fixture")), coordinatorId = "lead") }
        val members = groups.load(groupId)!!.members.map { member -> AgentTeamMember("fixture",
            if (member.id == "lead") AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE, instanceId = member.id,
            context = mapOf("collaboration_group_id" to groupId, "collaboration_name" to member.name)) }
        val definition = AgentTeamDefinition("fixture", "fixture", CollaborationGoalLoop.initial(members, "Test a fixture"), primaryInstanceId = "lead")
        val request = AgentRunRequest(groupId, "turn", "task", runId = "root", goal = "Test a fixture")
        val assessment = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "An independent tester is needed")
            .put("decision", "continue").put("criteria", JSONArray().put(JSONObject().put("id", "test")
                .put("requirement", "Verified fixture").put("status", "open").put("evidence", JSONArray())))
            .put("recruit", JSONArray().put(JSONObject().put("id", "tester").put("template_member", "worker")
                .put("role", "Tester").put("scope", "Independent fixture verification").put("reason", "Separate verification needed")))
            .put("work", JSONArray().put(JSONObject().put("id", "verify").put("member", "recruit:tester")
                .put("stage", "VERIFY").put("assignment", "Check the fixture"))).put("blockers", JSONArray())
        try {
            AgentTeamExecutionRuntime(store).use { runtime ->
                runtime.start(definition, request) { AgentSubagentOutput(assessment.toString()) }.await()
            }
            assertTrue(store.advanceGoal("root", "lead", System.currentTimeMillis()))
            val checkpoint = store.resumeCheckpoint("root")!!
            val pending = checkpoint.definition.members.filter { it.context[CollaborationGoalLoop.ROSTER] == "true" &&
                it.context[CollaborationGoalRecruitment.PUBLISHED] == "false" }
            assertEquals(1, pending.size)
            groups.projectRecruits(groupId, pending) // Simulate interruption before the execution-store acknowledgement.
            val reopened = EncryptedAgentTeamExecutionStore(database, recruitmentNames = { names })
            assertTrue(reopened.reconcileGoalRecruits("root", checkpoint.definition.primaryMemberId) { groups.projectRecruits(groupId, it) })
            assertEquals(3, groups.load(groupId)!!.members.size)
            val acknowledged = reopened.resumeCheckpoint("root")!!
            assertTrue(acknowledged.definition.members.filter { it.context[CollaborationGoalRecruitment.VACANCY] == "tester" }
                .all { it.context[CollaborationGoalRecruitment.PUBLISHED] == "true" })
            groups.update(groupId) { it.copy(members = it.members.filterNot { member -> member.id == pending.single().memberId }) }
            reopened.reconcileGoalRecruits("root", checkpoint.definition.primaryMemberId) { error("Must not recreate a removed member") }
            assertEquals(2, groups.load(groupId)!!.members.size)
        } finally { database.clear(); groups.remove(groupId) }
    }

    @Test fun nextBatchAndAcceptanceCriteriaSurviveStoreReopen() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val database = AgentEncryptedDatabase(context, "goal-loop-fixture-${UUID.randomUUID()}")
        val store = EncryptedAgentTeamExecutionStore(database)
        val members = listOf(AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead"),
            AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "worker")).map {
            it.copy(context = mapOf("collaboration_group_id" to "fixture", "collaboration_name" to it.memberId))
        }
        val definition = AgentTeamDefinition("fixture", "fixture", CollaborationResearchWorkflow.expand(members, "Verify a file"), primaryInstanceId = "lead")
        val request = AgentRunRequest("fixture", "turn", "task", runId = "root", goal = "Verify a file")
        val assessment = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "File still needs verification")
            .put("decision", "continue").put("criteria", JSONArray().put(JSONObject().put("id", "file")
                .put("requirement", "Verified file").put("status", "open").put("evidence", JSONArray())))
            .put("work", JSONArray().put(JSONObject().put("id", "verify-file-v1").put("member", "worker")
                .put("stage", "VERIFY").put("assignment", "Check the fixture file"))).put("blockers", JSONArray())
        try {
            AgentTeamExecutionRuntime(store).use { runtime ->
                runtime.start(definition, request) { AgentSubagentOutput(assessment.toString()) }.await()
            }
            val reopened = EncryptedAgentTeamExecutionStore(database)
            assertEquals("continue", reopened.snapshot("root")?.goalDisposition)
            assertTrue(reopened.advanceGoal("root", "lead", System.currentTimeMillis()))
            val recovered = EncryptedAgentTeamExecutionStore(database)
            val checkpoint = requireNotNull(recovered.resumeCheckpoint("root"))
            assertEquals("root", checkpoint.request.runId)
            assertEquals("Verify a file", checkpoint.request.goal)
            assertTrue(checkpoint.request.context[CollaborationGoalLoop.CRITERIA].toString().contains("Verified file"))
            assertFalse(recovered.advanceGoal("root", "lead", System.currentTimeMillis()))
            assertEquals(1, database.keys("goal-cycle:root:").size)
            assertEquals(1L, recovered.goalRound("fixture", "turn"))
            recovered.remove("root")
            assertTrue(database.keys("goal-cycle:root:").isEmpty())
        } finally { database.clear() }
    }

    @Test fun oldUnfinishedRunIsNotEvictedByTwoHundredNewCompletions() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val database = AgentEncryptedDatabase(context, "goal-retention-fixture-${UUID.randomUUID()}")
        val store = EncryptedAgentTeamExecutionStore(database)
        val definition = AgentTeamDefinition("fixture", "lead", listOf(AgentTeamMember("lead", AgentDeliveryMode.RESPOND)))
        fun request(id: String) = AgentRunRequest("fixture", id, id, runId = id, goal = "Fixture")
        try {
            store.create(definition, request("old-unfinished"))
            repeat(205) { index ->
                val id = "complete-$index"
                store.create(definition, request(id))
                store.append(AgentSubagentEvent(1L, id, kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED,
                    runStatus = AgentSubagentRunStatus.SUCCEEDED, timestampMillis = System.currentTimeMillis() + index))
            }
            assertNotNull(store.snapshot("old-unfinished"))
            assertTrue(store.snapshots().any { it.supervisorRunId == "old-unfinished" })
            store.markNonTerminalInterrupted()
            assertNotNull(store.resumeCheckpoint("old-unfinished"))
        } finally { database.clear() }
    }
}
