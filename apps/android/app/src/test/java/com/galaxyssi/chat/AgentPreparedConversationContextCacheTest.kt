package com.galaxyssi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentPreparedConversationContextCacheTest {
    @Test
    fun processUpdatesKeepPreparedDialogueContext() {
        val cache = AgentPreparedConversationContextCache()
        val context = context("conversation")
        cache.putIfCurrent(context, cache.version("conversation"))

        cache.invalidateTranscriptMutation("conversation", AgentTranscriptRole.PROCESS)

        assertSame(context, cache.get("conversation"))
    }

    @Test
    fun userAndAssistantUpdatesInvalidatePreparedDialogueContext() {
        listOf(AgentTranscriptRole.USER, AgentTranscriptRole.ASSISTANT).forEach { role ->
            val cache = AgentPreparedConversationContextCache()
            cache.putIfCurrent(context("conversation"), cache.version("conversation"))

            cache.invalidateTranscriptMutation("conversation", role)

            assertNull(cache.get("conversation"))
        }
    }

    @Test
    fun multiConversationInvalidationClearsEveryAffectedContext() {
        val cache = AgentPreparedConversationContextCache()
        cache.putIfCurrent(context("source"), cache.version("source"))
        cache.putIfCurrent(context("target"), cache.version("target"))

        cache.invalidate(listOf("source", "target"))

        assertNull(cache.get("source"))
        assertNull(cache.get("target"))
    }

    @Test
    fun staleBackgroundCompilationCannotRestoreInvalidatedContext() {
        val cache = AgentPreparedConversationContextCache()
        val startedAtVersion = cache.version("conversation")

        cache.invalidate("conversation")
        val accepted = cache.putIfCurrent(context("conversation"), startedAtVersion)

        assertNull(cache.get("conversation"))
        org.junit.Assert.assertFalse(accepted)
    }

    @Test
    fun currentPreparedContextCanBeReadWithoutRecompilation() {
        val cache = AgentPreparedConversationContextCache()
        val context = context("conversation")

        assertTrue(cache.putIfCurrent(context, cache.version("conversation")))

        assertSame(context, cache.get("conversation"))
    }

    @Test
    fun registrySharesPreparedContextAcrossStoreInstances() {
        val firstStoreCache = AgentPreparedConversationContextCacheRegistry.shared
        val secondStoreCache = AgentPreparedConversationContextCacheRegistry.shared
        val context = context("shared-conversation")
        firstStoreCache.clear()

        try {
            assertTrue(firstStoreCache.putIfCurrent(context, firstStoreCache.version(context.conversationId)))

            assertSame(context, secondStoreCache.get(context.conversationId))
        } finally {
            firstStoreCache.clear()
        }
    }

    @Test
    fun concurrentCallersCompileOneConversationOnce() {
        val cache = AgentPreparedConversationContextCache()
        val calls = AtomicInteger()
        val ready = CountDownLatch(8)
        val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(8)
        val futures = (1..8).map {
            executor.submit<AgentConversationContext> {
                ready.countDown()
                start.await(2, TimeUnit.SECONDS)
                cache.getOrCompute("conversation") {
                    calls.incrementAndGet()
                    Thread.sleep(20)
                    context("conversation")
                }
            }
        }

        check(ready.await(2, TimeUnit.SECONDS))
        start.countDown()
        val contexts = futures.map { it.get(2, TimeUnit.SECONDS) }
        executor.shutdownNow()

        contexts.drop(1).forEach { assertSame(contexts.first(), it) }
        assertEquals(1, calls.get())
    }

    @Test
    fun invalidationDuringCompilationRebuildsBeforeReturning() {
        val cache = AgentPreparedConversationContextCache()
        val calls = AtomicInteger()
        val firstStarted = CountDownLatch(1)
        val releaseFirst = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        val future = executor.submit<AgentConversationContext> {
            cache.getOrCompute("conversation") {
                val call = calls.incrementAndGet()
                if (call == 1) {
                    firstStarted.countDown()
                    releaseFirst.await(2, TimeUnit.SECONDS)
                }
                context("conversation").copy(summary = "version-$call")
            }
        }

        check(firstStarted.await(2, TimeUnit.SECONDS))
        cache.invalidate("conversation")
        releaseFirst.countDown()
        val prepared = future.get(2, TimeUnit.SECONDS)
        executor.shutdownNow()

        assertEquals("version-2", prepared.summary)
        assertEquals(2, calls.get())
        assertSame(prepared, cache.get("conversation"))
    }

    @Test
    fun differentConversationsCanCompileInParallel() {
        val cache = AgentPreparedConversationContextCache()
        val bothStarted = CountDownLatch(2)
        val release = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(2)
        val futures = listOf("conversation-a", "conversation-b").map { conversationId ->
            executor.submit<AgentConversationContext> {
                cache.getOrCompute(conversationId) {
                    bothStarted.countDown()
                    release.await(2, TimeUnit.SECONDS)
                    context(conversationId)
                }
            }
        }

        check(bothStarted.await(2, TimeUnit.SECONDS))
        release.countDown()
        val contexts = futures.map { it.get(2, TimeUnit.SECONDS) }
        executor.shutdownNow()

        assertEquals(listOf("conversation-a", "conversation-b"), contexts.map { it.conversationId })
    }

    private fun context(conversationId: String) = AgentConversationContext(
        conversationId = conversationId,
        summary = "summary",
        turns = emptyList(),
        privateMode = false
    )
}
