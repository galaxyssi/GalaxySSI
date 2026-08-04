package com.signalasi.chat

internal object AgentDirectExecutionPolicy {
    fun requiresUiThread(action: AgentAction): Boolean =
        action.kind != AgentActionKind.CALL_CONNECTOR
}
