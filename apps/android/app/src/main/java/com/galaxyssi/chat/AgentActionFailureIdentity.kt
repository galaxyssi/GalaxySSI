package com.galaxyssi.chat

internal object AgentActionFailureIdentity {
    fun failureClass(action: AgentAction): String {
        val target = action.parameters["tool_id"].orEmpty()
            .ifBlank { action.parameters["connector_id"].orEmpty() }
            .ifBlank { action.target }
            .trim()
            .lowercase()
            .ifBlank { "unknown" }
        val input = action.parameters["input_json"].orEmpty().trim()
        val inputIdentity = if (input.isBlank()) "no-input" else input.hashCode().toUInt().toString(16)
        return "action:${action.kind.name.lowercase()}:$target:$inputIdentity"
    }
}
