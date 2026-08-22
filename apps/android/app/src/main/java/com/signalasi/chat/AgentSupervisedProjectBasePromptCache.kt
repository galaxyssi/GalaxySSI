package com.signalasi.chat

import java.util.concurrent.CountDownLatch

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

    private class InFlightPrompt(val key: AgentSupervisedProjectBasePromptKey) {
        private val completion = CountDownLatch(1)

        @Volatile
        private var value: String? = null

        @Volatile
        private var failure: Throwable? = null

        fun complete(value: String) {
            this.value = value
            completion.countDown()
        }

        fun fail(failure: Throwable) {
            this.failure = failure
            completion.countDown()
        }

        fun await(): String {
            try {
                completion.await()
            } catch (interrupted: InterruptedException) {
                Thread.currentThread().interrupt()
                throw interrupted
            }
            failure?.let { throw it }
            return requireNotNull(value)
        }
    }

    private val cacheLock = Any()
    private val prompts = mutableListOf<CachedPrompt>()
    private val inFlightPrompts = mutableListOf<InFlightPrompt>()

    fun render(
        key: AgentSupervisedProjectBasePromptKey,
        compile: () -> String
    ): String {
        var ownsCompilation = false
        val inFlight = synchronized(cacheLock) {
            takeCached(key)?.let { cached -> return cached.value }
            inFlightPrompts.firstOrNull { candidate -> candidate.key == key }
                ?: InFlightPrompt(key).also { created ->
                    inFlightPrompts += created
                    ownsCompilation = true
                }
        }
        if (!ownsCompilation) return inFlight.await()

        return try {
            val value = compile()
            synchronized(cacheLock) {
                prompts += CachedPrompt(key, value)
                while (prompts.size > MAX_CACHED_PROMPTS) {
                    prompts.removeAt(0)
                }
            }
            inFlight.complete(value)
            value
        } catch (failure: Throwable) {
            inFlight.fail(failure)
            throw failure
        } finally {
            synchronized(cacheLock) {
                inFlightPrompts.remove(inFlight)
            }
        }
    }

    private fun takeCached(key: AgentSupervisedProjectBasePromptKey): CachedPrompt? {
        val index = prompts.indexOfFirst { cached -> cached.key == key }
        if (index < 0) return null
        return prompts.removeAt(index).also { cached -> prompts += cached }
    }

    private const val MAX_CACHED_PROMPTS = 8
}
