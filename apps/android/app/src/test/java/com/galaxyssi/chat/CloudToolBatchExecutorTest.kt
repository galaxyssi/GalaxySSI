package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.AssembledToolCall
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class CloudToolBatchExecutorTest {
    @Test
    fun independentToolCallsRunConcurrentlyAndKeepModelOrder() = runBlocking {
        val active = AtomicInteger()
        val peak = AtomicInteger()
        val firstPairStarted = CountDownLatch(2)
        val calls = (0 until 3).map { index ->
            PreparedCloudToolCall(
                AssembledToolCall("call-$index", index, "web_fetch", "{}"),
                JSONObject().put("index", index)
            )
        }

        val results = CloudToolBatchExecutor.executeOrdered(calls, maxParallel = 2) { prepared ->
            val running = active.incrementAndGet()
            peak.updateAndGet { previous -> maxOf(previous, running) }
            firstPairStarted.countDown()
            firstPairStarted.await(1, TimeUnit.SECONDS)
            Thread.sleep(20L)
            active.decrementAndGet()
            "result-${prepared.arguments.getInt("index")}"
        }

        assertEquals(listOf("call-0", "call-1", "call-2"), results.map { it.call.callId })
        assertEquals(listOf("result-0", "result-1", "result-2"), results.map { it.output })
        assertTrue("Expected at least two web tools to overlap", peak.get() >= 2)
    }
}
