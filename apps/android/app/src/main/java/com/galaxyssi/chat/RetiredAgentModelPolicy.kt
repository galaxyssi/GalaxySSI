package com.galaxyssi.chat

object RetiredAgentModelPolicy {
    fun isRetired(modelId: String): Boolean =
        modelId.trim().equals("gpt-5.3-codex-spark", ignoreCase = true)

    // An empty selection delegates to the Agent's current advertised default.
    fun availableOrDefault(modelId: String): String =
        modelId.trim().takeUnless(::isRetired).orEmpty()
}
