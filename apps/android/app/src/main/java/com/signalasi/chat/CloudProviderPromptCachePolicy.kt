package com.signalasi.chat

internal object CloudProviderPromptCachePolicy {
    fun shouldRequestExplicitCache(apiStyle: String, defaultSystemPrompt: Boolean): Boolean =
        apiStyle == "anthropic" && !defaultSystemPrompt
}
