package com.signalasi.chat

internal data class AgentSupervisedProjectBasePromptKey(
    val stablePrefix: String,
    val goal: String,
    val durableContext: String,
    val conversationTransport: String,
    val progressLedger: String,
    val maximumCharacters: Int,
    val minimumBaseCharacters: Int
)

/** Reuses exact base prompts across equivalent repair requests and provider rotations. */
internal object AgentSupervisedProjectBasePromptCache {
    private data class CachedPrompt(
        val key: AgentSupervisedProjectBasePromptKey,
        val value: String
    )

    private val cacheLock = Any()
    private val prompts = mutableListOf<CachedPrompt>()

    fun render(
        key: AgentSupervisedProjectBasePromptKey,
        compile: () -> String
    ): String {
        synchronized(cacheLock) {
            takeCached(key)
        }?.let { cached -> return cached.value }

        val value = compile()
        return synchronized(cacheLock) {
            val cached = takeCached(key)
            if (cached != null) return@synchronized cached.value
            prompts += CachedPrompt(key, value)
            while (prompts.size > MAX_CACHED_PROMPTS) {
                prompts.removeAt(0)
            }
            value
        }
    }

    private fun takeCached(key: AgentSupervisedProjectBasePromptKey): CachedPrompt? {
        val index = prompts.indexOfFirst { cached -> cached.key == key }
        if (index < 0) return null
        return prompts.removeAt(index).also { cached -> prompts += cached }
    }

    private const val MAX_CACHED_PROMPTS = 8
}
