package com.galaxyssi.chat

internal object AgentDirectExecutionPolicy {
    fun requiresUiThread(action: AgentAction): Boolean =
        action.kind != AgentActionKind.CALL_CONNECTOR
}
