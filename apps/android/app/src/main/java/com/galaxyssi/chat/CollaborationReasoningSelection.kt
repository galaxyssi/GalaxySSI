package com.galaxyssi.chat

/** Optional host-owned assignment control; absence keeps ordinary routing unchanged. */
internal object CollaborationReasoningSelection {
    const val KEY = "collaboration_reasoning_effort"

    fun explicit(value: String?): AgentModelReasoningEffort = requireNotNull(
        AgentModelReasoningEffort.entries.firstOrNull { it != AgentModelReasoningEffort.AUTO && it.wireValue == value }
    ) { "Explicit supported reasoning effort required; automatic or unknown values cannot pin an experiment" }

    fun parameters(context: Map<String, String>, adapterType: String): Map<String, String> {
        if (KEY !in context) return emptyMap()
        val effort = explicit(context[KEY])
        require(adapterType == "codex-app-server-or-cli") { "Pinned collaboration reasoning requires the Codex adapter" }
        require(context["collaboration_group_id"].orEmpty().isNotBlank() &&
            context["collaboration_model_id"].orEmpty().isNotBlank()) {
            "Pinned reasoning requires a scoped collaboration assignment and explicit model"
        }
        return mapOf("agent_reasoning_effort" to effort.wireValue)
    }
}
