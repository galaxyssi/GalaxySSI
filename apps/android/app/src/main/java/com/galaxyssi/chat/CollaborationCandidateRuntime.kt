package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Invoked under the team store lock; graph additions and candidate checkpoint share its commit. */
internal object CollaborationCandidateRuntime {
    fun update(record: AgentTeamExecutionRecord, workspaceProvider: (() -> CollaborationResearchWorkspace)?, completed: Set<String>,
               control: AgentTeamUserControl, admission: Int, requests: JSONArray = JSONArray(),
               intakeDependencies: Set<String>? = null): AgentTeamExecutionRecord {
        val previous = record.request.context[CollaborationCandidateEvolution.STATE]?.toString() ?: "[]"
        if (requests.length() == 0 && !CollaborationCandidateEvolution.pending(previous)) return record
        val workspace = runCatching { workspaceProvider?.invoke() }.getOrNull()
        val criteria = record.request.context[CollaborationGoalLoop.CRITERIA]?.toString() ?: "[]"
        require(CollaborationGoalLoop.preservedCriteriaError(criteria).isEmpty()) { "Candidate work needs the intact original contract" }
        val final = record.definition.members.single { it.memberId == record.definition.primaryMemberId }
        val roster = record.definition.members.filter { it.context[CollaborationGoalLoop.ROSTER] == "true" }
            .associateBy { it.context.getValue(CollaborationResearchWorkflow.PERSON) }
        val people = roster.keys
        val results = record.events.mapNotNull { it.result }.associateBy { it.childId }.filterKeys { it in completed }
        val statuses = record.events.filter { it.childStatus != null }.associate { it.childId to it.childStatus }
        val work = record.definition.members.filter { !it.context[CollaborationGoalLoop.WORK_ID].isNullOrBlank() }
        val granted = (intakeDependencies ?: final.dependsOnAgentIds).filterTo(linkedSetOf()) {
            results[it]?.status == AgentSubagentStatus.SUCCEEDED
        }
        val access = CollaborationWorkspaceAccess(final.context["collaboration_group_id"].orEmpty(), record.request.runId,
            record.request.messageId, record.request.context[CollaborationGoalLoop.ROUND]?.toString()?.toLongOrNull() ?: 0L,
            personId = final.context.getValue(CollaborationResearchWorkflow.PERSON), dependencyNodes = granted)
        val snapshot = CollaborationCandidateLiveGraph.Snapshot(access.groupId, access.runId, access.turnId,
            record.events.maxOfOrNull { it.sequence } ?: 0L,
            work.map { member ->
                val result = results[member.memberId]
                val status = when (result?.status ?: statuses[member.memberId]) {
                    AgentSubagentStatus.SUCCEEDED -> if (result == null) CollaborationCandidateLiveGraph.Status.RUNNING
                        else CollaborationCandidateLiveGraph.Status.SUCCEEDED
                    AgentSubagentStatus.FAILED -> if (result == null) CollaborationCandidateLiveGraph.Status.UNKNOWN
                        else CollaborationCandidateLiveGraph.Status.FAILED
                    AgentSubagentStatus.CANCELLED -> if (result == null) CollaborationCandidateLiveGraph.Status.UNKNOWN
                        else CollaborationCandidateLiveGraph.Status.CANCELLED
                    AgentSubagentStatus.SKIPPED -> if (result == null) CollaborationCandidateLiveGraph.Status.UNKNOWN
                        else CollaborationCandidateLiveGraph.Status.SKIPPED
                    AgentSubagentStatus.RUNNING -> CollaborationCandidateLiveGraph.Status.RUNNING
                    AgentSubagentStatus.QUEUED -> CollaborationCandidateLiveGraph.Status.QUEUED
                    else -> CollaborationCandidateLiveGraph.Status.UNKNOWN
                }
                CollaborationCandidateLiveGraph.Node(member.context.getValue(CollaborationGoalLoop.WORK_ID), member.memberId,
                    member.context.getValue(CollaborationResearchWorkflow.PERSON), status, member)
            }, work.filter { it.memberId in granted }.mapTo(linkedSetOf()) { it.context.getValue(CollaborationGoalLoop.WORK_ID) },
            results.mapValues { it.value.output }, CollaborationCandidateLiveGraph.Control.valueOf(control.name), admission)
        if (workspace == null) {
            val checkpoint = CollaborationCandidateVerificationState.checkpoint(previous)
            return record.copy(request = record.request.copy(context = record.request.context + mapOf(
                CollaborationCandidateEvolution.STATE to CollaborationCandidateVerificationState.encode(checkpoint.cycles,
                    CollaborationCandidateVerificationState.requests(checkpoint.pendingRequests, requests)),
                CollaborationCandidateEvolution.FEEDBACK to "Candidate workspace unavailable; requests retained without dispatch")))
        }
        val plan = CollaborationCandidateLiveGraph.plan(workspace, access, people, JSONArray(criteria), requests, previous,
            snapshot) { CollaborationLiveGraph.nodeId(record, "candidate:$it") }
        require(!plan.error) { plan.feedback }
        val nodes = plan.additions.map { addition ->
            val item = addition.work
            val person = roster.getValue(item.getString("member"))
            person.copy(instanceId = addition.dispatchId, deliveryMode = AgentDeliveryMode.OBSERVE,
                objective = item.getString("assignment"), dependsOnAgentIds = addition.dependencyDispatchIds,
                context = person.context + mapOf(CollaborationGoalLoop.ROSTER to "false",
                    CollaborationGoalLoop.WORK_ID to item.getString("id"),
                    CollaborationResearchWorkflow.STAGE to item.getString("stage"),
                    CollaborationWorkGraph.POLICY to "success", CollaborationWorkGraph.INDEPENDENT to "false") +
                    CollaborationCandidateEvolution.taskContext(item))
        }
        return CollaborationLiveGraph.append(record, nodes).let { updated ->
            updated.copy(request = updated.request.copy(context = updated.request.context + mapOf(
                CollaborationCandidateEvolution.STATE to plan.state, CollaborationCandidateEvolution.FEEDBACK to plan.feedback)))
        }
    }
}
