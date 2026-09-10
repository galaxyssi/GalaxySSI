package com.galaxyssi.chat

import android.os.Handler
import android.os.Looper
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentMemoryUiWorkDeviceTest {
    @Test fun blockedMemoryIoDoesNotBlockTheMainLooper() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val pulse = CountDownLatch(1)
        var ranOnMain = true
        AgentMemoryUiWork.execute {
            try {
                synchronized(AgentMemoryStorage.lock) {
                    ranOnMain = Looper.myLooper() == Looper.getMainLooper()
                    entered.countDown()
                    release.await(10, TimeUnit.SECONDS)
                }
            } finally { finished.countDown() }
        }
        try {
            assertTrue(entered.await(10, TimeUnit.SECONDS))
            assertFalse(ranOnMain)
            Handler(Looper.getMainLooper()).post { pulse.countDown() }
            assertTrue("Main looper must stay responsive while memory I/O is blocked", pulse.await(500, TimeUnit.MILLISECONDS))
        } finally {
            release.countDown()
            assertTrue(finished.await(10, TimeUnit.SECONDS))
        }
    }

    @Test fun memoryUiMutationsRunInSubmissionOrder() {
        val done = CountDownLatch(2)
        val order = mutableListOf<Int>()
        AgentMemoryUiWork.execute { order.add(1); done.countDown() }
        AgentMemoryUiWork.execute { order.add(2); done.countDown() }
        assertTrue(done.await(10, TimeUnit.SECONDS))
        assertEquals(listOf(1, 2), order)
    }
}
