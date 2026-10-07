package com.galaxyssi.chat

/** One projection for both restored plans and durably appended collaboration work. */
internal object AgentTeamGraphPlan {
    const val ADMISSION_INSTRUCTIONS = "List work in intended admission order among dependency-ready items. Running work is not preempted; explicit learning priorities may reorder learning items within their positions."

    fun build(definition: AgentTeamDefinition, request: AgentRunRequest): AgentSubagentPlan {
        val research = CollaborationResearchWorkflow.isResearch(definition.members)
        val observers = definition.members.filter { it.deliveryMode == AgentDeliveryMode.OBSERVE }
            .mapTo(linkedSetOf(), AgentTeamMember::memberId)
        val learning = research && definition.members.any { CollaborationLearningWork.TASK in it.context }
        val ordered = if (learning) CollaborationLearningWork.ordered(definition.members) else definition.members
        val children = ordered.filter { it.deliveryMode != AgentDeliveryMode.IGNORE }.map { member ->
            val primary = member.memberId == definition.primaryMemberId
            AgentSubagentChild(childId = member.memberId,
                dependencies = if (!research && primary) (member.dependsOnAgentIds + observers) - member.memberId else member.dependsOnAgentIds,
                dependencyPolicy = if (research && member.context[CollaborationWorkGraph.POLICY] == "success" && !primary)
                    AgentSubagentDependencyPolicy.REQUIRE_SUCCESS
                else if (research || primary) AgentSubagentDependencyPolicy.ALLOW_TERMINAL else AgentSubagentDependencyPolicy.REQUIRE_SUCCESS,
                context = member.objective.ifBlank { request.goal }.take(8000),
                provenance = AgentSubagentProvenance(source = "agent-team", sourceId = definition.teamId, traceId = request.runId,
                    metadata = mapOf("delivery_mode" to member.deliveryMode.name, "role" to member.role.take(80),
                        "agent_id" to member.agentId, "instance_id" to member.memberId, "task_id" to request.taskId.take(160))))
        }
        return AgentSubagentPlan(supervisorId = request.runId, children = children,
            provenance = AgentSubagentProvenance(source = "agent-team-supervisor", sourceId = definition.teamId, traceId = request.runId,
                metadata = mapOf("primary_agent_id" to definition.primaryAgentId, "primary_instance_id" to definition.primaryMemberId,
                    "visibility" to definition.visibilityMode.name)),
            completionBarrierChildId = if (research && CollaborationLiveGraph.enabled(definition)) definition.primaryMemberId else "",
            preserveChildOrder = research)
    }
}
