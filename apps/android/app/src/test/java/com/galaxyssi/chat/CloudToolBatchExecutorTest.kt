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
    @Test fun modelPlannedWebAndImageSearchOverlapWithoutReorderingObservations() = runBlocking {
        val started = CountDownLatch(2)
        val calls = listOf("web_search", "web_image_search").mapIndexed { index, name ->
            PreparedCloudToolCall(AssembledToolCall("call-$index", index, name, "{}"), JSONObject())
        }
        val results = CloudToolBatchExecutor.executeOrdered(calls, 2) {
            started.countDown()
            assertTrue("Independent model-planned searches were serialized", started.await(2, TimeUnit.SECONDS))
            it.call.name
        }
        assertEquals(listOf("web_search", "web_image_search"), results.map { it.output })
    }

    @Test fun fastToolPublishesProgressBeforeSlowSiblingCompletes() = runBlocking {
        val fastReported = CountDownLatch(1)
        val calls = (0..1).map { PreparedCloudToolCall(AssembledToolCall("call-$it", it, "web_fetch", "{}"), JSONObject()) }
        val results = CloudToolBatchExecutor.executeOrdered(calls, 2, onCompleted = {
            if (it.call.callId == "call-1") fastReported.countDown()
        }) {
            if (it.call.callId == "call-0") assertTrue(fastReported.await(2, TimeUnit.SECONDS))
            it.call.callId
        }
        assertEquals(listOf("call-0", "call-1"), results.map { it.call.callId })
    }

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
