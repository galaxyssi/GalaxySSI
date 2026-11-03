package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Durable execution facts, deliberately distinct from measured learning gains. */
internal object CollaborationLearningFeedback {
    const val OUTCOMES = "collaboration_research_learning_outcomes"
    const val RESOURCES = "collaboration_research_learning_resources"

    fun capture(record: AgentTeamExecutionRecord, results: Collection<AgentSubagentChildResult>): String {
        val prior = record.request.context[OUTCOMES]?.toString() ?: "{}"
        val tasks = record.definition.members.filter { CollaborationLearningWork.TASK in it.context }.associateBy { it.memberId }
        if (tasks.isEmpty()) return prior
        val outcomes = JSONObject(prior)
        results.filter { it.childId in tasks && it.supervisorId == record.request.runId && it.status.isTerminal }.forEach { result ->
            if (outcomes.has(result.childId)) return@forEach
            val member = tasks.getValue(result.childId)
            val binding = JSONObject(member.context.getValue(CollaborationLearningWork.TASK))
            val measured = result.startedAtMillis > 0 && result.completedAtMillis >= result.startedAtMillis
            val elapsed = if (measured) result.completedAtMillis - result.startedAtMillis else null
            val estimates = binding.getJSONArray("resource_estimates")
            val estimate = (0 until estimates.length()).map(estimates::getJSONObject).firstOrNull {
                it.getString("unit") == "elapsed_ms" && it.getString("status") == "estimated"
            }?.getDouble("value")
            outcomes.put(result.childId, JSONObject().put("node_id", result.childId)
                .put("work_id", member.context[CollaborationGoalLoop.WORK_ID]).put("binding", binding)
                .put("status", result.status.name.lowercase()).put("started_at", result.startedAtMillis)
                .put("completed_at", result.completedAtMillis).put("elapsed_ms", elapsed ?: JSONObject.NULL)
                .put("elapsed_estimate_error_ms", if (elapsed != null && estimate != null) elapsed.toDouble() - estimate else JSONObject.NULL)
                .put("cost_micros", JSONObject.NULL).put("tokens", JSONObject.NULL)
                .put("output_sha256", AgentNativeJsonCodec.sha256(result.output)).put("output_truncated", result.outputTruncated)
                .put("capability_verified", false).put("learning_gain", JSONObject.NULL))
        }
        return outcomes.toString()
    }

    fun resources(definition: AgentTeamDefinition, completed: Set<String>, concurrency: Int, coordinationConcurrency: Int = 0): String = JSONObject()
        .put("scope", "this_team_snapshot").put("configured_max_concurrency", concurrency + coordinationConcurrency)
        .put("configured_work_concurrency", concurrency).put("configured_coordination_concurrency", coordinationConcurrency)
        .put("capacity_scope", "shared_research_runtime_not_per_team")
        .put("unfinished_work", definition.members.count { it.deliveryMode != AgentDeliveryMode.IGNORE && it.memberId !in completed })
        .put("global_available_slots", JSONObject.NULL).put("remaining_money", JSONObject.NULL)
        .put("note", "Unknown is not free or unlimited. Existing scheduler and authorization govern execution; this snapshot grants no resources.")
        .toString()

    fun outcomes(raw: String): String = if (raw == "{}") "" else JSONObject(raw).let { values ->
        val items = values.keys().asSequence().map { values.getJSONObject(it) }.sortedBy { it.getLong("completed_at") }.toList()
        JSONObject().put("items", JSONArray(items)).put("total", items.size)
            .put("meaning", "Execution receipts, not proof of learning. Inspect originals and probes/experiments before changing priorities.").toString()
    }
}
