package com.galaxyssi.chat

/** Recovery may change the plan, but cannot turn a manual provider selection into Auto. */
internal object AgentSupervisedRecoveryBinding {
    fun resolve(connector: AgentAction, history: List<AgentAction> = emptyList(), reroute: () -> AgentAction): AgentAction {
        // Older recovery revisions could drop the manual lock. Recover the turn's original binding,
        // not today's global/conversation selection, which may belong to a later user request.
        val original = history.firstOrNull { it.isSupervisedProjectConnector() &&
            it.parameters["manual_target_locked"].equals("true", ignoreCase = true) }
        if (!connector.parameters["manual_target_locked"].equals("true", ignoreCase = true) && original != null) {
            val keys = setOf("connector_id", "connector_kind", "connector_adapter_type", "connector_failure_domain",
                "manual_target_locked", "manual_model_id", "agent_model_id", "agent_reasoning_effort", "model_id", AgentInvocationBinding.TARGET)
            return resolve(connector.copy(target = original.target,
                parameters = (connector.parameters - keys) + original.parameters.filterKeys { it in keys }), reroute = reroute)
        }
        if (connector.parameters["manual_target_locked"].equals("true", ignoreCase = true)) {
            return connector.copy(parameters = connector.parameters + mapOf(
                "manual_target_locked" to "true",
                "auto_reroute_on_failure" to "false",
                "routing_fallback_ids" to ""
            ))
        }
        return reroute()
    }
}
