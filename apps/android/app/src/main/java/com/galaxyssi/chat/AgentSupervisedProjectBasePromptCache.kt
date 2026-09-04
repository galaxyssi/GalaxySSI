package com.galaxyssi.chat

internal data class AgentSupervisedProjectBasePromptKey(
    val stablePrefix: String,
    val goal: String,
    val durableContext: String,
    val conversationTransport: String,
    val progressLedger: String,
    val directResponseAllowed: Boolean = false,
    val maximumCharacters: Int,
    val minimumBaseCharacters: Int
)

/** Reuses exact base prompts across equivalent repair requests and provider rotations. */
internal object AgentSupervisedProjectBasePromptCache {
    private val prompts = AgentSingleFlightLruCache<AgentSupervisedProjectBasePromptKey, String>(
        maximumEntries = MAX_CACHED_PROMPTS
    )

    fun render(
        key: AgentSupervisedProjectBasePromptKey,
        compile: () -> String
    ): String = prompts.getOrCompute(key, compile)

    private const val MAX_CACHED_PROMPTS = 8
}
