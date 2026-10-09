package com.galaxyssi.chat

import org.json.JSONObject

internal object CollaborationTrialDeviceBinding {
    fun validate(model: String): String = model.also {
        require(it.isNotBlank() && it.length <= 128 && it == it.trim() &&
            it.none { ch -> ch.isISOControl() || ch in "*,;|" }) {
            "Use one exact device model, not a list or wildcard"
        }
    }

    fun requireOperatorTarget(actualModel: String, operatorModel: String?) {
        val expected = validate(requireNotNull(operatorModel) { "Explicit trial device required" })
        require(actualModel == expected) { "Connected model differs from the explicit trial device" }
    }
}

/** An experiment envelope, not a plan: production coordination chooses all executable work. */
internal class CollaborationAdaptivePilotPlan private constructor(
    val id: String, val deviceModel: String, override val targetId: String, override val selection: CollaborationLiveModelSelection,
    val goal: String, val timeoutMillis: Long, val maximumDispatches: Int, val members: List<CollaborationMember>,
    val singleAgent: Boolean = false,
    val continuity: CollaborationPilotContinuitySpec? = null
) : CollaborationTrialSelectionPolicy {
    val executionMode get() = if (singleAgent) "single_agent" else "adaptive_team"
    // Production normalizes assignment boundaries; keep the frozen request unchanged.
    val executionObjective get() = goal.trim()
    fun requireDevice(actualModel: String, operatorModel: String?) {
        require(operatorModel == deviceModel && actualModel == deviceModel) {
            "Trial device mismatch: the frozen protocol, explicit operator target and connected model must agree"
        }
    }

    fun definition(group: String, run: String): AgentTeamDefinition {
        val people = members.mapIndexed { index, person ->
            AgentTeamMember(targetId, if (index == 0) AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
                instanceId = person.id, role = person.role, context = mapOf(
                    "collaboration_group_id" to group, "collaboration_name" to person.name,
                    "collaboration_provider" to person.providerLabel, "collaboration_model_id" to selection.modelId,
                    CollaborationReasoningSelection.KEY to selection.reasoningEffort.wireValue))
        }
        val nodes = if (singleAgent) listOf(people.single().copy(objective = executionObjective,
            context = people.single().context + (CollaborationResearchWorkflow.PERSON to members.single().id)))
            else CollaborationResearchWorkflow.expand(people, goal)
        return AgentTeamDefinition(run, targetId, nodes,
            primaryInstanceId = people.first().memberId, visibilityMode = AgentTeamVisibilityMode.VISIBLE)
    }

    fun matchesExecution(member: AgentTeamMember, definition: AgentTeamDefinition): Boolean = if (singleAgent) {
        definition.members.size == 1 && member == definition.members.single() && member.objective == executionObjective &&
            member.context[CollaborationResearchWorkflow.PERSON] == members.single().id &&
            member.context[CollaborationGoalLoop.ENABLED] == null && CollaborationResearchWorkflow.stage(member) == null &&
            member.context[CollaborationLiveGraph.ENABLED] == null && member.dependsOnAgentIds.isEmpty()
    } else member.context[CollaborationGoalLoop.ENABLED] == "1" && CollaborationResearchWorkflow.stage(member) != null

    companion object {
        const val FORMAT = "galaxyssi.adaptive-collaboration-pilot.v2"
        const val SINGLE_FORMAT = "galaxyssi.single-agent-calibration.v1"
        fun from(value: JSONObject, authorizedDispatches: Int, authorizedMillis: Long): CollaborationAdaptivePilotPlan {
            val required = setOf("format", "pilot_id", "target_id", "model_id", "reasoning_effort",
                "tool_scope", "goal", "trial_timeout_ms", "maximum_dispatches", "members", "device_model")
            val keys = value.keys().asSequence().toSet()
            require(keys == required || keys == required + "continuity") { "Unexpected adaptive trial fields" }
            val continuity = if (value.has("continuity")) CollaborationPilotContinuitySpec.from(value.getJSONObject("continuity")) else null
            fun text(key: String) = (value.get(key) as? String)?.takeIf(String::isNotBlank) ?: error("Nonblank string required: $key")
            require(text("format") in setOf(FORMAT, SINGLE_FORMAT) && text("tool_scope") == CollaborationRemotePilotPlan.TOOL_SCOPE)
            val singleAgent = text("format") == SINGLE_FORMAT
            val id = text("pilot_id").also { require(it.matches(Regex("[a-zA-Z0-9][a-zA-Z0-9_-]{0,47}"))) }
            val device = CollaborationTrialDeviceBinding.validate(text("device_model"))
            val target = text("target_id").also { require(it.length <= 256 && ':' in it && it.endsWith(":codex")) }
            val selection = CollaborationLiveModelSelection.from(text("model_id"), text("reasoning_effort"))
            val timeout = CollaborationTrialPolicy.strictLong(value.get("trial_timeout_ms"))
            val limit = CollaborationTrialPolicy.strictLong(value.get("maximum_dispatches"))
            require(authorizedMillis > 0 && timeout in 1..authorizedMillis) { "Trial exceeds the operator's time envelope" }
            require(authorizedDispatches > 0 && limit in 1..authorizedDispatches.toLong()) { "Trial exceeds authorized phone dispatches" }
            val goal = text("goal").also { require(it.toByteArray(Charsets.UTF_8).size <= 60_000) { "Trial goal is too large; no silent truncation" } }
            val raw = value.getJSONArray("members")
            require(if (singleAgent) raw.length() == 1 && limit == 1L else raw.length() >= 2) {
                "Single-agent calibration requires one member and one free-running dispatch; adaptive teams require a coordinator and a peer"
            }
            val members = (0 until raw.length()).map { index ->
                val person = raw.getJSONObject(index)
                require(person.keys().asSequence().toSet() == setOf("id", "name", "role")) { "Trial members do not provide task steps or permissions" }
                fun field(key: String) = (person.get(key) as? String)?.takeIf(String::isNotBlank) ?: error("Member $index.$key is missing")
                CollaborationMember(field("id").also { require(it.matches(Regex("[a-zA-Z0-9_-]{1,64}"))) }, field("name"),
                    target, "Codex", role = field("role"), modelId = selection.modelId)
            }
            require(members.map { it.id }.distinct().size == members.size) { "Trial person IDs must be distinct" }
            return CollaborationAdaptivePilotPlan(id, device, target, selection, goal, timeout, limit.toInt(), members, singleAgent, continuity)
        }
    }
}
