package com.signalasi.chat

import java.util.Locale

enum class AgentGlobalContextMode {
    MINIMAL,
    FULL
}

object AgentGlobalContextDispatchPolicy {
    private val minimalQueries = setOf(
        "hello",
        "hi",
        "hey",
        "hithere",
        "goodmorning",
        "goodafternoon",
        "goodevening",
        "goodnight",
        "\u4f60\u597d",
        "\u60a8\u597d",
        "\u55e8",
        "\u54c8\u55bd",
        "\u65e9\u4e0a\u597d",
        "\u4e0b\u5348\u597d",
        "\u665a\u4e0a\u597d",
        "\u65e9\u5b89",
        "\u665a\u5b89"
    )

    fun mode(query: String, hasAttachments: Boolean): AgentGlobalContextMode {
        // The current conversation remains available separately. Cross-conversation
        // memory must not bias a fresh image or file with unrelated prior objects.
        if (hasAttachments) return AgentGlobalContextMode.MINIMAL
        val normalized = query
            .trim()
            .lowercase(Locale.ROOT)
            .replace(NON_SEMANTIC_CHARACTERS, "")
        return if (normalized in minimalQueries) {
            AgentGlobalContextMode.MINIMAL
        } else {
            AgentGlobalContextMode.FULL
        }
    }

    private val NON_SEMANTIC_CHARACTERS = Regex("[\\p{P}\\p{S}\\s]+")
}
