package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationLiveInventoryTest {
    private fun member(id: String, dependencies: Set<String> = emptySet(), policy: String = "success",
                       extra: Map<String, String> = emptyMap()) = AgentTeamMember("provider",
        deliveryMode = AgentDeliveryMode.OBSERVE, instanceId = "node:$id", objective = "Execute $id",
        dependsOnAgentIds = dependencies.mapTo(linkedSetOf()) { "node:$it" }, context = mapOf(
            CollaborationGoalLoop.WORK_ID to id, CollaborationResearchWorkflow.PERSON to "person:$id",
            CollaborationResearchWorkflow.STAGE to "EXECUTE", CollaborationWorkGraph.POLICY to policy
        ) + extra)

    private fun result(id: String, status: AgentSubagentStatus) = AgentSubagentChildResult(
        "run", "node:$id", "run", 1, status, output = "Not included in inventory")

    private fun inventory(members: List<AgentTeamMember>, completed: Map<String, AgentSubagentChildResult> = emptyMap(),
                          observed: Map<String, AgentSubagentStatus> = emptyMap()): JSONObject = JSONObject(
        CollaborationLiveGraph.inventory(AgentTeamDefinition("team", "provider", members, primaryInstanceId = members.first().memberId),
            completed, observed))

    private fun item(json: JSONObject, id: String): JSONObject = json.getJSONArray("items").let { array ->
        (0 until array.length()).map(array::getJSONObject).single { it.getString("id") == id }
    }

    @Test fun waitingReviewIsNotReportedAsRunningAndNamesItsExactDependencies() {
        val producer = member("producer")
        val review = member("review", setOf("producer"), extra = mapOf(
            CollaborationWorkGraph.INDEPENDENT to "true", CollaborationResearchWorkflow.STAGE to "VERIFY"))
        val json = inventory(listOf(producer, review), observed = mapOf(
            producer.memberId to AgentSubagentStatus.RUNNING, review.memberId to AgentSubagentStatus.QUEUED))
        val waiting = item(json, "review")
        assertEquals("QUEUED", waiting.getString("status"))
        assertEquals("waiting", waiting.getString("dependency_state"))
        assertEquals("producer", waiting.getJSONArray("waiting_for").getJSONObject(0).getString("id"))
        assertEquals("RUNNING", waiting.getJSONArray("waiting_for").getJSONObject(0).getString("status"))
        assertEquals("producer", waiting.getJSONArray("review_targets").getString(0))
        assertEquals("VERIFY", waiting.getString("stage"))
    }

    @Test fun satisfiedDependenciesDoNotPretendThatQueuedWorkHasStarted() {
        val review = member("review", setOf("producer"))
        val json = inventory(listOf(member("producer"), review),
            mapOf("node:producer" to result("producer", AgentSubagentStatus.SUCCEEDED)),
            mapOf(review.memberId to AgentSubagentStatus.QUEUED))
        assertEquals("QUEUED", item(json, "review").getString("status"))
        assertEquals("satisfied", item(json, "review").getString("dependency_state"))
        assertEquals(0, item(json, "review").getJSONArray("waiting_for").length())
    }

    @Test fun terminalObservationWithoutCommittedResultDoesNotReleaseDependencies() {
        val json = inventory(listOf(member("producer"), member("review", setOf("producer"))),
            observed = mapOf("node:producer" to AgentSubagentStatus.SUCCEEDED))
        assertEquals("RESULT_PENDING", item(json, "producer").getString("status"))
        assertEquals("waiting", item(json, "review").getString("dependency_state"))
        assertEquals("RESULT_PENDING", item(json, "review").getJSONArray("waiting_for").getJSONObject(0).getString("status"))
    }

    @Test fun failureIsBlockingOnlyForSuccessPolicyAndDoesNotBecomeSuccessfulEvidence() {
        val json = inventory(listOf(member("producer"), member("review", setOf("producer")),
            member("diagnosis", setOf("producer"), policy = "terminal")),
            mapOf("node:producer" to result("producer", AgentSubagentStatus.FAILED)))
        assertEquals("failed", item(json, "review").getString("dependency_state"))
        assertEquals("producer", item(json, "review").getJSONArray("unsuccessful_dependencies").getString(0))
        assertEquals("satisfied", item(json, "diagnosis").getString("dependency_state"))
        assertEquals("FAILED", item(json, "producer").getString("status"))
    }

    @Test fun completedSchedulerResultWinsOverStaleRunningObservation() {
        val json = inventory(listOf(member("producer")),
            mapOf("node:producer" to result("producer", AgentSubagentStatus.SUCCEEDED)),
            mapOf("node:producer" to AgentSubagentStatus.RUNNING))
        assertEquals("SUCCEEDED", item(json, "producer").getString("status"))
        assertFalse(json.toString().contains("Not included in inventory"))
    }

    @Test fun reviewSubjectsStaySeparateFromOwnTestDataAndExactMilestones() {
        val review = member("review", setOf("producer", "tests"), extra = mapOf(
            CollaborationWorkGraph.INDEPENDENT to "true",
            CollaborationReviewTargets.CONTEXT to "[\"producer\"]",
            CollaborationMilestoneDispatch.INPUTS to JSONArray().put(JSONObject().put("token", "a".repeat(64))
                .put("producer_node", "node:producer")).toString()))
        val value = item(inventory(listOf(member("producer"), member("tests"), review)), "review")
        assertEquals(2, value.getJSONArray("depends_on").length())
        assertEquals("[\"producer\"]", value.getJSONArray("review_targets").toString())
        assertEquals("a".repeat(64), value.getJSONArray(CollaborationMilestoneDispatch.USES).getString(0))
    }

    @Test fun absentObservationAndOmittedWorkAreExplicitNotAssumedRunningOrAbsent() {
        val nodes = (0 until 100).map { member("work-$it").copy(objective = "long assignment ".repeat(30)) }
        val json = inventory(nodes)
        val first = json.getJSONArray("items").getJSONObject(0)
        assertEquals("unobserved", first.getString("status"))
        assertTrue(first.getBoolean("assignment_truncated"))
        assertTrue(json.getInt("omitted") > 0)
        assertEquals(100, json.getInt("total"))
        assertTrue(json.getString("note").contains("omitted work is unknown, not absent"))
        assertTrue(json.toString().length < 6500)
    }

    @Test fun guidanceMakesInterimChecksOptionalWithoutWeakeningExistingWork() {
        val instructions = CollaborationLiveGraph.instructions()
        assertTrue(instructions.contains("planned review waiting on its author is NOT"))
        assertTrue(instructions.contains("uses_milestones"))
        assertTrue(instructions.contains("silently drop its required inputs"))
        assertTrue(instructions.contains("does not choose the research strategy"))
    }
}
