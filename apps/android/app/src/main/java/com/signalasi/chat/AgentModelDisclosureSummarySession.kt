package com.signalasi.chat

/**
 * Maintains the disclosure summary for one append-only model tool loop.
 * A changed message prefix invalidates the session and triggers a full rebuild.
 */
internal class AgentModelDisclosureSummarySession(
    private val textClassifier: (String) -> Set<AgentDisclosedDataKind> = { text ->
        AgentDataDisclosureClassifier.classifyText(text)
    }
) {
    private val observedMessages = mutableListOf<AgentModelMessage>()
    private val disclosedKinds = linkedSetOf<AgentDisclosedDataKind>()
    private var textCharacters = 0L
    private var conversationalMessages = 0
    private var hasSystemInstructions = false
    private var hasToolOutput = false

    @Synchronized
    fun summarize(messages: List<AgentModelMessage>): AgentDataDisclosureTextSummary {
        if (!extendsObservedPrefix(messages)) reset()
        for (index in observedMessages.size until messages.size) {
            append(messages[index])
        }
        val kinds = disclosedKinds.toMutableSet()
        if (conversationalMessages > 1) kinds += AgentDisclosedDataKind.CONVERSATION_HISTORY
        if (hasSystemInstructions) kinds += AgentDisclosedDataKind.SYSTEM_INSTRUCTIONS
        if (hasToolOutput) kinds += AgentDisclosedDataKind.TOOL_OUTPUT
        return AgentDataDisclosureTextSummary(
            textCharacters = textCharacters.toInt(),
            dataKinds = kinds
        )
    }

    internal val observedMessageCount: Int
        @Synchronized get() = observedMessages.size

    private fun extendsObservedPrefix(messages: List<AgentModelMessage>): Boolean =
        observedMessages.size <= messages.size && observedMessages.indices.all { index ->
            observedMessages[index] === messages[index]
        }

    private fun append(message: AgentModelMessage) {
        val text = message.text.ifBlank { message.toolResult?.message.orEmpty() }
        if (observedMessages.isNotEmpty()) textCharacters += 1
        textCharacters = (textCharacters + text.length).coerceAtMost(Int.MAX_VALUE.toLong())
        disclosedKinds += textClassifier(text)
        if (message.role == AgentModelMessageRole.USER || message.role == AgentModelMessageRole.ASSISTANT) {
            conversationalMessages += 1
        }
        hasSystemInstructions = hasSystemInstructions || message.role == AgentModelMessageRole.SYSTEM
        hasToolOutput = hasToolOutput || message.role == AgentModelMessageRole.TOOL
        observedMessages += message
    }

    private fun reset() {
        observedMessages.clear()
        disclosedKinds.clear()
        textCharacters = 0L
        conversationalMessages = 0
        hasSystemInstructions = false
        hasToolOutput = false
    }
}
