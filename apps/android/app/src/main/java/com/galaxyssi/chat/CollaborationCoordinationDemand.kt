package com.galaxyssi.chat

/** A declared successor owns routine handoff; this does not judge the result's scientific sufficiency. */
internal object CollaborationCoordinationDemand {
    fun pendingInputs(work: List<AgentTeamMember>, results: Map<String, AgentSubagentChildResult>): Set<String> = buildSet {
        work.forEach { consumer ->
            if (consumer.memberId !in results && consumer.deliveryMode != AgentDeliveryMode.IGNORE &&
                !CollaborationLiveGraph.planner(consumer) && consumer.dependsOnAgentIds.none { dependency ->
                    results[dependency]?.let { it.status != AgentSubagentStatus.SUCCEEDED || it.outputTruncated } == true
                }) addAll(consumer.dependsOnAgentIds - consumer.memberId)
        }
        // A completed intermediary forwards ownership of its ancestors to its pending successor.
        val members = work.associateBy { it.memberId }
        val queue = java.util.ArrayDeque(this)
        while (queue.isNotEmpty()) {
            val id = queue.removeFirst()
            val result = results[id] ?: continue
            if (result.status != AgentSubagentStatus.SUCCEEDED || result.outputTruncated) continue
            members[id]?.dependsOnAgentIds.orEmpty().forEach { dependency ->
                if (add(dependency)) queue.addLast(dependency)
            }
        }
    }

    fun requiresCheckpoint(source: AgentTeamMember, result: AgentSubagentChildResult, pendingInputs: Set<String>): Boolean {
        if (source.memberId !in pendingInputs || result.status != AgentSubagentStatus.SUCCEEDED || result.outputTruncated ||
            source.context.containsKey(CollaborationCandidateEvolution.TASK)) return true
        val artifact = CollaborationResearchArtifact.decode(result.output) ?: return true
        if (artifact.optBoolean("unstructured") || artifact.has("validation_warning") ||
            CollaborationMilestoneCoordination.explicitRequest(artifact)) return true
        // A model's success status alone must never suppress publication/transport failures.
        if (artifact.optJSONObject("workspace_receipt")?.optString("status") != "recorded" ||
            artifact.optJSONObject("delivery_receipt")?.optString("status") != "recorded") return true
        return false
    }
}
