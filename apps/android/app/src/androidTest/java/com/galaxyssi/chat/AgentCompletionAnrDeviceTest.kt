package com.galaxyssi.chat

import android.os.Handler
import android.os.Looper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentCompletionAnrDeviceTest {
    @Test
    fun blockedLearningKeepsMainLooperResponsive() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val executor = Executors.newSingleThreadExecutor()
        val queue = AgentCompletionWorkQueue(executor)
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val completed = CountDownLatch(1)
        val uiPing = CountDownLatch(1)
        try {
            instrumentation.runOnMainSync {
                assertTrue(queue.enqueue("synthetic-completion") {
                    assertTrue(Looper.myLooper() != Looper.getMainLooper())
                    started.countDown()
                    check(release.await(5, TimeUnit.SECONDS))
                    completed.countDown()
                })
                Handler(Looper.getMainLooper()).post { uiPing.countDown() }
            }
            assertTrue(started.await(5, TimeUnit.SECONDS))
            assertTrue(uiPing.await(1, TimeUnit.SECONDS))
            assertEquals(1L, completed.count)
            release.countDown()
            assertTrue(completed.await(5, TimeUnit.SECONDS))
        } finally {
            release.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun memoryMutationDoesNotHoldMemoryLockWhileWaitingForWorldRepository() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val store = EncryptedAgentMemoryStore(instrumentation.targetContext)
        val field = GlobalAgentRepository::class.java.getDeclaredField("STORE_LOCK").apply { isAccessible = true }
        val repositoryLock = requireNotNull(field.get(null))
        val locked = CountDownLatch(1)
        val release = CountDownLatch(1)
        val uiPing = CountDownLatch(1)
        val blocker = Thread {
            synchronized(repositoryLock) {
                locked.countDown()
                check(release.await(5, TimeUnit.SECONDS))
            }
        }
        blocker.start()
        try {
            assertTrue(locked.await(5, TimeUnit.SECONDS))
            val item = AgentMemoryItem(kind = AgentMemoryKind.PREFERENCE,
                value = "Synthetic private test", privateMemory = true)
            instrumentation.runOnMainSync {
                synchronized(AgentMemoryStorage.lock) { store.publishMutation(emptyList(), listOf(item)) }
                Handler(Looper.getMainLooper()).post { uiPing.countDown() }
            }
            assertTrue(uiPing.await(1, TimeUnit.SECONDS))
        } finally {
            release.countDown()
            blocker.join(5_000)
        }
    }
}
