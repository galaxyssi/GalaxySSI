package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Exercise real store planning with local results, never model calls or user work. */
internal object CandidateReviewReassignmentFixture {
    suspend fun seed(store: AgentTeamExecutionStore, f: CandidateRuntimeFixture): AgentTeamExecutionCheckpoint {
        val initial = f.record()
        val completed = linkedSetOf<String>()
        var sequence = 0L
        suspend fun complete(id: String, output: String) {
            store.append(AgentSubagentEvent(++sequence, f.access.runId, id, AgentSubagentEventKinds.CHILD_SUCCEEDED,
                childStatus = AgentSubagentStatus.SUCCEEDED, result = AgentSubagentChildResult(f.access.runId, id,
                    f.access.runId, 1, AgentSubagentStatus.SUCCEEDED, output)))
            completed += id
        }
        suspend fun advance() = requireNotNull(store.expandResearchGraph(f.access.runId, "final", completed, ++sequence))
        store.create(initial.definition, initial.request)
        complete("producer", f.produce())
        val firstPlan = advance().definition.members.single(CollaborationLiveGraph::planner)
        complete(firstPlan.memberId, f.expansion(true))
        val enrolled = advance()
        val old = enrolled.definition.members.single { it.context.containsKey(CollaborationCandidateEvolution.TASK) &&
            JSONObject(it.context.getValue(CollaborationCandidateEvolution.TASK)).getString("member") == "reviewer-a" }
        f.workspace.enrollPublication(f.access.copy(nodeId = old.memberId, personId = "reviewer-a",
            dependencyNodes = old.dependsOnAgentIds), CollaborationResearchStage.VERIFY,
            JSONObject(old.context.getValue(CollaborationCandidateEvolution.TASK)))
        complete(old.memberId, "Completed response, but no accepted workspace publication")
        val settled = advance()
        val retryPlan = settled.definition.members.single { CollaborationLiveGraph.planner(it) && it.memberId !in completed }
        val cycle = CollaborationCandidateVerificationState.read(settled.request.context.getValue(
            CollaborationCandidateEvolution.STATE).toString()).let { values ->
            (0 until values.length()).map { values.getJSONObject(it) }.single { it.getString("node_id") == old.memberId }
        }
        check(cycle.getBoolean("retryable_review"))
        val retry = JSONObject().put("target", cycle.getJSONObject("target")).put("criterion_id", "accuracy")
            .put("editor", "editor").put("reviewer", "reviewer-b")
            .put(CollaborationCandidateLiveGraph.PRODUCERS, JSONArray().put("producer"))
            .put("retry_review", JSONObject().put("node_id", old.memberId).put("reason", "Publish a review grounded in the saved original"))
        val request = JSONObject(f.expansion()).put(CollaborationCandidateEvolution.REQUESTS, JSONArray().put(retry))
        complete(retryPlan.memberId, request.toString())
        val admitted = advance()
        val replacement = replacement(admitted)
        check(replacement.memberId != old.memberId && replacement.dependsOnAgentIds == setOf("producer"))
        check(admitted.definition.members.single { it.memberId == old.memberId } == old)
        check(admitted.definition.members.single { it.memberId == "slow" } == initial.definition.members.single { it.memberId == "slow" })
        check(admitted.completed.getValue(old.memberId).output.contains("no accepted workspace publication"))
        check(advance().definition == admitted.definition)
        return admitted
    }

    fun replacement(record: AgentTeamExecutionCheckpoint) = record.definition.members.single { member ->
        member.context[CollaborationCandidateEvolution.TASK]?.let { JSONObject(it).has("review_reassignment") } == true
    }
}
