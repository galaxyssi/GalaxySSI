package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** A local curriculum with synthetic workers; never invokes a model or resumes user research. */
@RunWith(AndroidJUnit4::class)
class CollaborationLearningDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun hostAdmissionOrderSurvivesRuntimeNormalization() = runBlocking {
        for (preserve in listOf(false, true)) {
            val executed = mutableListOf<String>()
            AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 1), kotlinx.coroutines.Dispatchers.Unconfined).use { runtime ->
                runtime.start(AgentSubagentPlan("ordering-fixture-${UUID.randomUUID()}",
                    listOf("z-first", "a-second").map { AgentSubagentChild(it) }, preserveChildOrder = preserve)) {
                    executed += it.childId
                    AgentSubagentOutput("Synthetic local response")
                }.await()
            }
            assertEquals(if (preserve) listOf("z-first", "a-second") else listOf("a-second", "z-first"), executed)
        }
    }

    @Test fun encryptedSelectionRunsLocallyAndRestoresExecutionFeedback() = runBlocking {
        val token = UUID.randomUUID().toString()
        val group = "learning-device-$token"
        val run = "learning-run-$token"
        val groups = CollaborationGroupStore(context)
        val database = AgentEncryptedDatabase(context, "learning-fixture-$token")
        groups.update(group) { it.copy(members = listOf("lead", "peer").map { name ->
            CollaborationMember(name, name, "fixture", "Local fixture") }, coordinatorId = "lead") }
        val workspace = CollaborationResearchWorkspace(context)
        fun access(round: Long) = CollaborationWorkspaceAccess(group, run, "turn", round, "lead-$round", "lead")
        fun publish(kind: String, spec: JSONObject, round: Long): JSONObject {
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Synthetic learning")
                .put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace", JSONArray().put(JSONObject()
                    .put("id", kind).put("kind", kind).put("title", kind).put("body", JSONObject().put("content", "Local fixture").put(kind, spec))))
            val receipt = workspace.publish(access(round), raw.toString(), round * 10)
            assertEquals(receipt.toString(), "recorded", receipt.optString("status"))
            return receipt.getJSONArray("revisions").getJSONObject(0)
        }
        try {
            val gap = publish("capability_gap", JSONObject("""{"category":"method","symptom":"Fixture uncertainty",
                "needed_capability":"Compare fixture methods","chosen_option":"probe","rationale":"Get evidence first",
                "learning_options":[{"id":"probe","action":"Probe","expected_gain":"Learn fixture outcome","cost":"Unknown",
                "goal_relevance":"Fixture","verification":"Local synthetic result"}]}"""), 1)
            val agenda = publish("learning_agenda", JSONObject().put("goal_alignment", "Fixture only")
                .put("resource_reasoning", "One local worker").put("selection_reason", "Probe before broad sweep")
                .put("reconsider_when", "After probe").put("options", JSONArray().put(JSONObject().put("id", "probe")
                    .put("gap", gap).put("gap_option", "probe").put("priority", 1).put("decision", "select")
                    .put("member", "peer").put("stage", "VERIFY").put("assignment", "Compare local synthetic fixture")
                    .put("current_goal_value", "Resolve fixture uncertainty").put("future_transfer_value", "Unverified")
                    .put("information_gain", "Observe known test").put("uncertainty", "No real capability conclusion")
                    .put("tradeoff", "Local test only").put("verification", "Original fixture receipt")
                    .put("reconsider_when", "After result").put("resource_estimates", JSONArray().put(JSONObject()
                        .put("unit", "elapsed_ms").put("status", "estimated").put("value", 100).put("basis", "Fixture"))))), 2)
            val item = JSONObject().put("id", "probe-work").put("member", "peer").put("stage", "VERIFY")
                .put("assignment", "Compare local synthetic fixture").put("learning", JSONObject().put("agenda", agenda).put("option_id", "probe"))
            fun report(work: JSONArray) = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Fixture only, not real learning")
                .put("decision", "continue").put("criteria", JSONArray().put(JSONObject().put("id", "fixture")
                    .put("requirement", "Compare local fixture").put("status", "open").put("evidence", JSONArray())))
                .put("work", work).put("blockers", JSONArray()).toString()
            val members = CollaborationGoalLoop.initial(listOf(AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead"),
                AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "peer")), "Compare local fixture").map {
                it.copy(context = it.context + mapOf("collaboration_group_id" to group, CollaborationTeamOrganization.ENABLED to "0")) }
            val request = AgentRunRequest(group, "turn", "task", runId = run, goal = "Compare local fixture",
                context = mapOf(CollaborationGoalLoop.ROUND to "2"))
            val definition = AgentTeamDefinition("fixture-team", "fixture", members, primaryInstanceId = "lead")
            fun store() = EncryptedAgentTeamExecutionStore(database, candidateWorkspace = { CollaborationResearchWorkspace(context) })
            val first = store()
            first.create(definition, request)
            first.append(AgentSubagentEvent(1, run, "lead", AgentSubagentEventKinds.CHILD_SUCCEEDED,
                childStatus = AgentSubagentStatus.SUCCEEDED, result = AgentSubagentChildResult(run, "lead", run, 1,
                    AgentSubagentStatus.SUCCEEDED, report(JSONArray().put(item)))))
            first.append(AgentSubagentEvent(2, run, kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED, runStatus = AgentSubagentRunStatus.SUCCEEDED))
            assertTrue(first.advanceGoal(run, "lead", 1000, true))
            val checkpoint = store().resumeCheckpoint(run)!!
            val selected = checkpoint.definition.members.single { CollaborationLearningWork.TASK in it.context }
            assertEquals("probe-work", selected.context[CollaborationGoalLoop.WORK_ID])
            assertTrue(checkpoint.request.context.containsKey(CollaborationLearningWork.CLAIMS))
            val seen = mutableListOf<String>()
            AgentTeamExecutionRuntime(store(), AgentSubagentLimits(maxConcurrency = 1)).use { runtime ->
                runtime.resume(checkpoint) { execution ->
                    seen += execution.member.memberId
                    if (execution.member.memberId == selected.memberId) AgentSubagentOutput("Synthetic result: 2 + 3 = 5; not a learning claim")
                    else AgentSubagentOutput(report(JSONArray()))
                }.await()
            }
            assertEquals(1, seen.count { it == selected.memberId })
            val reopened = store()
            assertTrue(reopened.advanceGoal(run, checkpoint.definition.primaryMemberId, 5000, true))
            val next = store().resumeCheckpoint(run)!!
            val outcomes = JSONObject(next.request.context.getValue(CollaborationLearningFeedback.OUTCOMES).toString())
            val outcome = outcomes.getJSONObject(selected.memberId)
            assertEquals("succeeded", outcome.getString("status"))
            assertFalse(outcome.getBoolean("capability_verified")); assertTrue(outcome.isNull("cost_micros"))
            assertTrue(outcome.getLong("elapsed_ms") >= 0)
            assertTrue(next.definition.members.none { CollaborationLearningWork.TASK in it.context })
            val replay = runCatching { CollaborationLearningWork.plan(AgentTeamExecutionRecord(next.definition, next.request),
                listOf(JSONObject(item.toString()).put("id", "renamed-probe")), { workspace }, access(5)) }
            assertTrue(replay.isFailure)
            val cloud = JSONObject(CollaborationCloudRecall.execute(context, access(5), JSONObject().put("mode", "evolution")))
            assertTrue(cloud.toString().contains("learning_agenda"))
        } finally {
            database.clear()
            groups.remove(group)
        }
    }
}
