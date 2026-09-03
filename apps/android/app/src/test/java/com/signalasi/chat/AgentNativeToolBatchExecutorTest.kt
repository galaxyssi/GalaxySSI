package com.signalasi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentNativeToolBatchExecutorTest {
    @Test
    fun executesBeyondLegacyFourWhileKeepingInputOrder() = runBlocking {
        val active = AtomicInteger(0)
        val peak = AtomicInteger(0)
        val entered = CountDownLatch(6)
        val release = CountDownLatch(1)
        val execution = async(Dispatchers.Default) {
            AgentNativeToolBatchExecutor.executeOrdered(
                inputs = (1..6).toList(),
                maxParallel = 6,
                limitProvider = { 6 }
            ) { value ->
                val current = active.incrementAndGet()
                peak.accumulateAndGet(current) { previous, candidate -> maxOf(previous, candidate) }
                entered.countDown()
                try {
                    release.await(2, TimeUnit.SECONDS)
                    value * 10
                } finally {
                    active.decrementAndGet()
                }
            }
        }

        try {
            assertTrue(entered.await(2, TimeUnit.SECONDS))
        } finally {
            release.countDown()
        }
        assertEquals(listOf(10, 20, 30, 40, 50, 60), execution.await())
        assertEquals(6, peak.get())
    }
}
