package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GlobalResponseDispatchIsolationDeviceTest {
    @Test fun ordinaryReplyDoesNotWaitForGlobalStore() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val runtime = GlobalSuperAgentRuntime.get(context)
        val lock = checkNotNull(GlobalAgentRepository::class.java.getDeclaredField("STORE_LOCK").apply {
            isAccessible = true
        }.get(null))
        val acquired = CountDownLatch(1)
        val release = CountDownLatch(1)
        val holder = thread(name = "test-global-response-storage-stall") {
            synchronized(lock) { acquired.countDown(); release.await(60, TimeUnit.SECONDS) }
        }
        val result = FutureTask {
            runtime.consumeResearchResponse(AgentConnectorResponse(
                sourceMessageId = System.currentTimeMillis(), contactId = "test-no-contact",
                content = "", conversationId = "test-dispatch-${UUID.randomUUID()}", turnId = "test-turn"
            ))
        }
        var worker: Thread? = null
        try {
            assertTrue(acquired.await(5, TimeUnit.SECONDS))
            worker = thread(name = "test-ordinary-reply-dispatch") { result.run() }
            assertFalse("Ordinary replies are not global task results", result.get(10, TimeUnit.SECONDS))
            assertEquals("The global store is still blocked", 1L, release.count)
        } finally {
            release.countDown()
            holder.join(5_000)
            worker?.join(10_000)
        }
    }
}
