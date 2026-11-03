package com.galaxyssi.chat

import org.json.JSONObject

/** A preregistered, closed-book calibration pilot, not a general collaboration benchmark. */
internal data class CollaborationPilotPlan(
    val id: String,
    val targetId: String,
    val modelId: String,
    val profile: CollaborationTrialProfile,
    val timeoutMillis: Long,
    val slots: List<Slot>
) {
    data class Slot(val id: String, val caseId: String, val arm: String, val prompt: String)
    val maximumAdmissions: Int get() = slots.size * 3

    fun members(slot: Slot) = listOf(
        CollaborationMember(id = "analyst", name = "Analyst", agentId = targetId,
            providerLabel = "Cloud model", role = "Analyst", modelId = modelId)
    ) + if (slot.arm == "team") listOf(CollaborationMember(id = "reviewer", name = "Reviewer", agentId = targetId,
        providerLabel = "Cloud model", role = "Critical reviewer", modelId = modelId)) else emptyList()

    fun definition(slot: Slot, group: String, run: String): AgentTeamDefinition {
        val roster = members(slot)
        fun node(id: String, person: CollaborationMember, objective: String, dependencies: Set<String>) =
            AgentTeamMember(targetId, if (id == "final") AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
                instanceId = id, role = person.role, objective = objective, dependsOnAgentIds = dependencies,
                context = mapOf("collaboration_group_id" to group, "collaboration_name" to person.name,
                    "collaboration_provider" to person.providerLabel, "collaboration_model_id" to modelId,
                    CollaborationResearchWorkflow.PERSON to person.id))
        return AgentTeamDefinition(run, targetId, listOf(
            node("draft", roster.first(), "Produce an initial answer to the task. State supporting source IDs and uncertainties.", emptySet()),
            node("review", roster.last(), "Check the supplied draft against every task constraint and source. " +
                "Identify concrete errors, counterevidence and corrections. Do not assume a draft is correct.", setOf("draft")),
            node("final", roster.first(), "Revise the draft using the review and original sources. " +
                "Return only the final answer in the task's requested format; preserve uncertainty where evidence is insufficient.", setOf("draft", "review"))
        ), primaryInstanceId = "final", visibilityMode = AgentTeamVisibilityMode.VISIBLE)
    }

    companion object {
        fun from(value: JSONObject, authorizedAdmissions: Int): CollaborationPilotPlan {
            value.exactKeys("format", "pilot_id", "target_id", "model_id", "text_profile", "trial_timeout_ms", "slots")
            require(value.getString("format") == "galaxyssi.collaboration-pilot.v1")
            val slots = value.getJSONArray("slots").let { array -> (0 until array.length()).map { index ->
                array.getJSONObject(index).let { slot ->
                    slot.exactKeys("id", "case_id", "arm", "prompt")
                    Slot(slot.safeId("id"), slot.safeId("case_id"), slot.getString("arm"), slot.getString("prompt"))
                }
            } }
            require(slots.isNotEmpty() && slots.size <= 32 && authorizedAdmissions > 0)
            require(slots.size.toLong() * 3 <= authorizedAdmissions.toLong()) { "Plan exceeds explicitly authorized admissions" }
            require(slots.map { it.id }.distinct().size == slots.size)
            require(slots.all { it.arm in setOf("single", "team") && it.prompt.isNotBlank() &&
                it.prompt.toByteArray(Charsets.UTF_8).size <= 12_000 })
            slots.groupBy { it.caseId }.values.forEach { pair ->
                require(pair.size == 2 && pair.map { it.arm }.toSet() == setOf("single", "team"))
                require(pair.map { it.prompt }.distinct().size == 1) { "Paired arms must receive identical task inputs" }
            }
            val timeout = CollaborationTrialPolicy.strictLong(value.get("trial_timeout_ms"))
            require(timeout in 60_000..600_000)
            val profile = CollaborationTrialProfile.from(value.getJSONObject("text_profile"))
            require(profile.maxOutputTokens <= 4096)
            return CollaborationPilotPlan(value.safeId("pilot_id"), value.getString("target_id").also { require(it.isNotBlank()) },
                value.getString("model_id").also { require(it.isNotBlank() && it.length <= 256) }, profile, timeout, slots)
        }

        private fun JSONObject.safeId(key: String) = getString(key).also {
            require(Regex("[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}").matches(it))
        }
        private fun JSONObject.exactKeys(vararg names: String) {
            require(keys().asSequence().toSet() == names.toSet()) { "Unexpected or missing protocol fields" }
        }
    }
}
