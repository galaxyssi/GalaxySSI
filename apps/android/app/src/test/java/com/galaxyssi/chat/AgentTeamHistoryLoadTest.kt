package com.galaxyssi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test

class AgentTeamHistoryLoadTest {
    private fun message(id: String) = AgentTeamMessageEnvelope(messageId = id, teamId = "team",
        conversationId = "conversation", supervisorRunId = "run", fromInstanceId = "author",
        kind = AgentTeamMessageKind.REVIEW, text = id)

    private class Fixture(read: () -> List<AgentTeamMessageEnvelope>) : AutoCloseable {
        val pool = Executors.newFixedThreadPool(2)
        val posted = LinkedBlockingQueue<() -> Unit>()
        val rendered = mutableListOf<Result<List<AgentTeamMessageEnvelope>>>()
        val load = AgentTeamHistoryLoad(pool, { posted.put(it) }, read, { rendered += it })
        fun next(): () -> Unit = requireNotNull(posted.poll(5, TimeUnit.SECONDS)) { "No UI completion posted" }
        override fun close() { load.cancel(); pool.shutdownNow(); assertTrue(pool.awaitTermination(5, TimeUnit.SECONDS)) }
    }

    @Test fun readsOffCallingThreadAndOnlyRendersWhenUiCallbackRuns() {
        val uiThread = Thread.currentThread()
        val expected = listOf(message("latest"))
        Fixture({ assertNotSame(uiThread, Thread.currentThread()); expected }).use { fixture ->
            fixture.load.refresh()
            val completion = fixture.next()
            assertTrue(fixture.rendered.isEmpty())
            completion()
            assertEquals(expected, fixture.rendered.single().getOrThrow())
        }
    }

    @Test fun detachedViewCannotRenderAnAlreadyPostedResult() {
        Fixture({ listOf(message("old-view")) }).use { fixture ->
            fixture.load.refresh()
            val completion = fixture.next()
            fixture.load.cancel()
            completion()
            assertTrue(fixture.rendered.isEmpty())
        }
    }

    @Test fun outOfOrderLoadsDoNotReplaceNewPageWithOlderHistory() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val calls = AtomicInteger()
        try {
            Fixture({
                if (calls.incrementAndGet() == 1) {
                    entered.countDown()
                    check(release.await(5, TimeUnit.SECONDS))
                    listOf(message("old"))
                } else listOf(message("new"))
            }).use { fixture ->
                fixture.load.refresh()
                assertTrue(entered.await(5, TimeUnit.SECONDS))
                fixture.load.refresh()
                fixture.next()()
                release.countDown()
                fixture.next()()
                assertEquals(listOf("new"), fixture.rendered.single().getOrThrow().map { it.messageId })
            }
        } finally { release.countDown() }
    }

    @Test fun failureIsNotAnEmptyHistoryAndExplicitRetryCanRecover() {
        val calls = AtomicInteger()
        Fixture({ if (calls.incrementAndGet() == 1) error("Unreadable ciphertext") else listOf(message("recovered")) }).use { fixture ->
            fixture.load.refresh()
            fixture.next()()
            assertEquals("Unreadable ciphertext", fixture.rendered.single().exceptionOrNull()?.message)
            fixture.load.refresh()
            fixture.next()()
            assertEquals("recovered", fixture.rendered.last().getOrThrow().single().messageId)
        }
    }

    @Test fun cancellingQueuedReadDoesNotStartStorageWork() {
        val ready = CountDownLatch(2)
        val release = CountDownLatch(1)
        val calls = AtomicInteger()
        Fixture({ calls.incrementAndGet(); emptyList() }).use { fixture ->
            try {
                val blockers = (1..2).map { fixture.pool.submit { ready.countDown(); release.await() } }
                assertTrue(ready.await(5, TimeUnit.SECONDS))
                fixture.load.refresh()
                fixture.load.cancel()
                release.countDown()
                blockers.forEach { it.get(5, TimeUnit.SECONDS) }
                fixture.pool.submit {}.get(5, TimeUnit.SECONDS)
                assertEquals(0, calls.get())
                assertTrue(fixture.posted.isEmpty())
            } finally { release.countDown() }
        }
    }

    @Test fun shutdownExecutorProducesVisibleFailureInsteadOfThrowingOnUiThread() {
        Fixture({ emptyList() }).use { fixture ->
            fixture.pool.shutdown()
            fixture.load.refresh()
            fixture.next()()
            assertTrue(fixture.rendered.single().isFailure)
        }
    }
}
