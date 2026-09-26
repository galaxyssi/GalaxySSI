package com.galaxyssi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentCompletionWorkQueueTest {
    @Test
    fun `blocked learning does not block the caller or accept duplicate pending runs`() {
        val executor = Executors.newSingleThreadExecutor()
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val caller = Thread.currentThread()
        val queue = AgentCompletionWorkQueue(executor)
        try {
            assertTrue(queue.enqueue("run-a") {
                assertFalse(Thread.currentThread() === caller)
                started.countDown()
                check(release.await(5, TimeUnit.SECONDS))
            })
            assertTrue(started.await(5, TimeUnit.SECONDS))
            assertFalse(queue.enqueue("run-a") { error("Duplicate learning") })
            assertTrue(queue.enqueue("run-b") { finished.countDown() })
            assertEquals(1L, finished.count)
            release.countDown()
            assertTrue(finished.await(5, TimeUnit.SECONDS))
        } finally {
            release.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun `failure does not strand a run or stop subsequent work`() {
        val tasks = ArrayDeque<Runnable>()
        val failures = mutableListOf<Throwable>()
        val queue = AgentCompletionWorkQueue(Executor { tasks.addLast(it) }, failures::add)
        assertTrue(queue.enqueue("failed") { error("Synthetic learning failure") })
        assertTrue(queue.enqueue("next") {})
        tasks.removeFirst().run()
        tasks.removeFirst().run()
        assertEquals(1, failures.size)
        assertTrue(queue.enqueue("failed") {})
        tasks.removeFirst().run()
    }

    @Test
    fun `rejected scheduling releases the deduplication key without running inline`() {
        var rejected = true
        var ran = false
        val tasks = ArrayDeque<Runnable>()
        val queue = AgentCompletionWorkQueue(Executor {
            if (rejected) throw java.util.concurrent.RejectedExecutionException()
            tasks.addLast(it)
        })
        assertFalse(queue.enqueue("run") { ran = true })
        assertFalse(ran)
        rejected = false
        assertTrue(queue.enqueue("run") { ran = true })
        assertFalse(ran)
        tasks.removeFirst().run()
        assertTrue(ran)
    }
}
