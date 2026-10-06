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

@RunWith(AndroidJUnit4::class)
class CollaborationReviewTargetsDeviceTest {
    private fun work(id: String, member: String) = JSONObject().put("id", id).put("member", member)
        .put("stage", "EXECUTE").put("assignment", "Synthetic review target test: $id")

    @Test fun androidPreservesReviewSubjectAndAllEvidenceDependencies() {
        val model = work("model", "builder")
        val probes = work("probes", "reviewer")
        val check = work("check", "reviewer").put("independent_review", true)
            .put("depends_on", JSONArray().put("model").put("probes"))
            .put("review_targets", JSONArray().put("model"))
        val plan = CollaborationWorkGraph.compile(listOf(model, probes, check), emptySet())
        assertEquals("", plan.error)
        val savedContext = JSONObject(CollaborationReviewTargets.context(check)).toString()
        val saved = JSONObject(savedContext)
        val restored = CollaborationReviewTargets.restore(JSONObject(check.toString()).apply { remove("review_targets") },
            saved.keys().asSequence().associateWith { saved.getString(it) })
        assertEquals(setOf("model"), CollaborationReviewTargets.read(restored))
        assertEquals(setOf("model", "probes"), CollaborationWorkGraph.dependencies(restored))
        val remaining = CollaborationWorkGraph.compile(listOf(restored), setOf("model", "probes"),
            mapOf("model" to "builder", "probes" to "reviewer"))
        assertEquals("", remaining.error)
        assertEquals(1, remaining.work.size)
    }

    @Test fun androidRejectsSelfReviewAndMalformedOrEmptyTargets() {
        val check = work("check", "reviewer").put("independent_review", true)
            .put("depends_on", JSONArray().put("model")).put("review_targets", JSONArray().put("model"))
        val error = CollaborationWorkGraph.compile(listOf(check), setOf("model"), mapOf("model" to "reviewer")).error
        assertTrue(error.contains("target model")); assertTrue(error.contains("author=reviewer"))
        for (targets in listOf<Any>(JSONArray(), JSONArray().put(42), "model", JSONObject.NULL)) {
            val changed = JSONObject(check.toString()).put("review_targets", targets)
            assertTrue(CollaborationWorkGraph.compile(listOf(changed), setOf("model"), mapOf("model" to "builder")).error.isNotBlank())
        }
    }

    @Test fun encryptedCheckpointReopensWithReviewTargetAndBothInputs() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val database = AgentEncryptedDatabase(context, "review-target-fixture-${UUID.randomUUID()}")
        val store = EncryptedAgentTeamExecutionStore(database)
        val people = listOf("lead", "builder", "reviewer").map { id ->
            AgentTeamMember("fixture", if (id == "lead") AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
                instanceId = id, context = mapOf("collaboration_group_id" to "review-target-fixture", "collaboration_name" to id))
        }
        val definition = AgentTeamDefinition("fixture", "fixture", CollaborationGoalLoop.initial(people, "Check a fixture"),
            primaryInstanceId = "lead")
        val request = AgentRunRequest("review-target-fixture", "turn", "task", runId = "root", goal = "Check a fixture")
        val assessment = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Check a saved model")
            .put("decision", "continue").put("criteria", JSONArray().put(JSONObject().put("id", "model")
                .put("requirement", "Verified fixture").put("status", "open").put("evidence", JSONArray())))
            .put("work", JSONArray().put(work("model", "builder")).put(work("probes", "reviewer"))
                .put(work("check", "reviewer").put("independent_review", true)
                    .put("depends_on", JSONArray().put("model").put("probes"))
                    .put("review_targets", JSONArray().put("model"))))
            .put("blockers", JSONArray())
        try {
            AgentTeamExecutionRuntime(store).use { runtime ->
                runtime.start(definition, request) { AgentSubagentOutput(assessment.toString()) }.await()
            }
            assertTrue(store.advanceGoal("root", "lead", System.currentTimeMillis()))
            val recovered = EncryptedAgentTeamExecutionStore(database)
            val checkpoint = requireNotNull(recovered.resumeCheckpoint("root"))
            val check = checkpoint.definition.members.singleOrNull { it.context[CollaborationGoalLoop.WORK_ID] == "check" }
            assertNotNull(checkpoint.request.context.toString(), check)
            requireNotNull(check)
            assertEquals("[\"model\"]", check.context[CollaborationReviewTargets.CONTEXT])
            val inputs = checkpoint.definition.members.filter { it.memberId in check.dependsOnAgentIds }
                .map { it.context[CollaborationGoalLoop.WORK_ID] }.toSet()
            assertEquals(setOf("model", "probes"), inputs)
            assertEquals("true", check.context[CollaborationWorkGraph.INDEPENDENT])
            assertTrue(checkpoint.request.context[CollaborationGoalLoop.CRITERIA].toString().contains("Verified fixture"))
        } finally { database.clear() }
    }
}
