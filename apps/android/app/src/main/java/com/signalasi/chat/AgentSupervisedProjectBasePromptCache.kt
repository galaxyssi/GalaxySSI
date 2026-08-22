package com.signalasi.chat

import java.lang.ref.WeakReference

/** Reuses immutable base prompts across schema and evidence repair attempts for one request. */
internal object AgentSupervisedProjectBasePromptCache {
    private data class CachedPrompt(
        val request: WeakReference<AgentRequest>,
        val evidenceExpected: Boolean,
        val maximumCharacters: Int,
        val value: String
    )

    private val cacheLock = Any()
    private val prompts = mutableListOf<CachedPrompt>()

    fun render(
        request: AgentRequest,
        evidenceExpected: Boolean,
        maximumCharacters: Int,
        compile: () -> String
    ): String {
        synchronized(cacheLock) {
            takeCached(request, evidenceExpected, maximumCharacters)
        }?.let { cached -> return cached.value }

        val value = compile()
        return synchronized(cacheLock) {
            val cached = takeCached(request, evidenceExpected, maximumCharacters)
            if (cached != null) return@synchronized cached.value
            prompts += CachedPrompt(
                request = WeakReference(request),
                evidenceExpected = evidenceExpected,
                maximumCharacters = maximumCharacters,
                value = value
            )
            while (prompts.size > MAX_CACHED_PROMPTS) {
                prompts.removeAt(0)
            }
            value
        }
    }

    private fun takeCached(
        request: AgentRequest,
        evidenceExpected: Boolean,
        maximumCharacters: Int
    ): CachedPrompt? {
        prompts.removeAll { cached -> cached.request.get() == null }
        val index = prompts.indexOfFirst { cached ->
            cached.request.get() === request &&
                cached.evidenceExpected == evidenceExpected &&
                cached.maximumCharacters == maximumCharacters
        }
        if (index < 0) return null
        return prompts.removeAt(index).also { cached -> prompts += cached }
    }

    private const val MAX_CACHED_PROMPTS = 8
}
