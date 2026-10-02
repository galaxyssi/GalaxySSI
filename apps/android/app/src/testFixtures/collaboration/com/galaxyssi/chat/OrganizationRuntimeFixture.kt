package com.galaxyssi.chat

import java.util.concurrent.CopyOnWriteArrayList
import org.json.JSONArray
import org.json.JSONObject

/** Dedicated local execution only; no providers, workspace tools or original user research. */
internal class OrganizationRuntimeFixture {
    val run = "organization-runtime-fixture"
    val calls = CopyOnWriteArrayList<String>()
    val request = AgentRunRequest("organization-fixture-group", "fixture-turn", "fixture-task",
        runId = run, goal = "Check a local fixture and independently review it")
    val definition = AgentTeamDefinition("organization-fixture-team", "fixture", CollaborationGoalLoop.initial(
        listOf("lead", "author", "reviewer", "backup").map { id ->
            AgentTeamMember("fixture", if (id == "lead") AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
                role = if (id == "lead") "Coordinator" else "Reviewer", instanceId = id,
                requiredCapabilities = setOf(AgentCapability.RESEARCH), context = mapOf(
                    "collaboration_group_id" to request.conversationId, "collaboration_name" to id,
                    "collaboration_model_id" to "local-fixture"))
        }, request.goal), primaryInstanceId = "lead")

    fun output(execution: AgentTeamMemberExecutionContext): AgentSubagentOutput {
        val member = execution.member
        val work = member.context[CollaborationGoalLoop.WORK_ID].orEmpty()
        calls += work.ifEmpty { "assessment:${execution.request.context[CollaborationGoalLoop.ROUND] ?: 0}" }
        if (work.isNotEmpty()) return AgentSubagentOutput("Fixture result $work")
        val round = execution.request.context[CollaborationGoalLoop.ROUND]?.toString()?.toIntOrNull() ?: 0
        val tasks = when (round) {
            0 -> listOf(job("build", "author", "Publish the local fixture description"),
                job("review", "reviewer", "Independently inspect the fixture description", "VERIFY")
                    .put("depends_on", JSONArray().put("build")).put("independent_review", true))
            1 -> listOf(job("cross-check", "backup", "Check the saved description against the second fixture"))
            else -> listOf(job("revision", "author", "Revise the saved fixture after the independent cross-check", "REVISE"))
        }
        return AgentSubagentOutput(assessment(tasks))
    }

    suspend fun seed(store: AgentTeamExecutionStore): AgentTeamExecutionCheckpoint {
        AgentTeamExecutionRuntime(store).use { runtime -> runtime.start(definition, request, ::output).await() }
        check(store.advanceGoal(run, "lead", System.currentTimeMillis(), true))
        val first = requireNotNull(store.resumeCheckpoint(run))
        AgentTeamExecutionRuntime(store).use { runtime -> runtime.resume(first, ::output).await() }
        check(store.advanceGoal(run, first.definition.primaryMemberId, System.currentTimeMillis(), true))
        return requireNotNull(store.resumeCheckpoint(run))
    }

    fun validate(checkpoint: AgentTeamExecutionCheckpoint) {
        val history = CollaborationTeamOrganizationHistory.decode(checkpoint.request.context[
            CollaborationTeamOrganizationHistory.HISTORY]?.toString(), run, request.conversationId)
        check(history.size == 2 && history.map { it.workId }.toSet() == setOf("build", "review"))
        check(history.all { it.outcome == CollaborationTeamOrganization.Outcome.SUCCEEDED && it.costUsdMicros == null })
        check(JSONArray(checkpoint.request.context[CollaborationGoalLoop.FINISHED_WORK].toString()).length() == 2)
        val roster = checkpoint.definition.members.filter { it.context[CollaborationGoalLoop.ROSTER] == "true" }
        check(roster.size == 4)
        check(roster.filter { it.context[CollaborationTeamOrganization.STATE] == "standby" }
            .map { it.context[CollaborationResearchWorkflow.PERSON] }.toSet() == setOf("author", "reviewer"))
        check(roster.all { it.agentId == "fixture" && it.context["collaboration_model_id"] == "local-fixture" })
        check(checkpoint.definition.members.single { it.deliveryMode == AgentDeliveryMode.OBSERVE }
            .context[CollaborationGoalLoop.WORK_ID] == "cross-check")
    }

    suspend fun recover(store: AgentTeamExecutionStore) {
        val checkpoint = requireNotNull(store.resumeCheckpoint(run))
        validate(checkpoint)
        calls.clear()
        AgentTeamExecutionRuntime(store).use { runtime -> runtime.resume(checkpoint, ::output).await() }
        check(calls.count { it == "cross-check" } == 1 && calls.none { it in setOf("build", "review") })
        check(store.advanceGoal(run, checkpoint.definition.primaryMemberId, System.currentTimeMillis(), true))
        val next = requireNotNull(store.resumeCheckpoint(run))
        check(next.definition.members.first { it.memberId == "author" }.context[CollaborationTeamOrganization.STATE] == "active")
        check(next.definition.members.first { it.memberId == "backup" }.context[CollaborationTeamOrganization.STATE] == "standby")
        check(JSONArray(next.request.context[CollaborationGoalLoop.FINISHED_WORK].toString()).length() == 3)
    }

    private fun job(id: String, member: String, assignment: String, stage: String = "EXECUTE") =
        JSONObject().put("id", id).put("member", member).put("assignment", assignment).put("stage", stage)

    private fun assessment(work: List<JSONObject>) = JSONObject().put("format", CollaborationGoalLoop.FORMAT)
        .put("decision", "continue").put("summary", "Local organization fixture checkpoint")
        .put("criteria", JSONArray().put(JSONObject().put("id", "fixture")
            .put("requirement", request.goal).put("verification", "documentary").put("status", "open").put("evidence", JSONArray())))
        .put("work", JSONArray(work)).put("blockers", JSONArray()).toString()
}
