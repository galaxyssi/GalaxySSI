package com.galaxyssi.chat

internal object AgentConnectorPromptContextPolicy {
    fun select(
        connectorTaskMode: String,
        compiledPrompt: String,
        appendGeneralContext: () -> String
    ): String = if (connectorTaskMode == PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE) {
        compiledPrompt
    } else {
        appendGeneralContext()
    }
}
