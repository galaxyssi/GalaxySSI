package com.galaxyssi.chat

/** Recovery may change the plan, but cannot turn a manual provider selection into Auto. */
internal object AgentSupervisedRecoveryBinding {
    fun resolve(connector: AgentAction, reroute: () -> AgentAction): AgentAction {
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
