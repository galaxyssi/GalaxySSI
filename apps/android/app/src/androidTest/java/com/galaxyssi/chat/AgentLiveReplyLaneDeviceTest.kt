package com.galaxyssi.chat

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentLiveReplyLaneDeviceTest {
    @Test fun blockedHistoryRecoveryDoesNotBlockLiveReplies() {
        val recoveryStarted = CountDownLatch(1)
        val releaseRecovery = CountDownLatch(1)
        val replyRan = CountDownLatch(1)
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            try {
                scenario.onActivity { activity ->
                    activity.agentRuntimeRecoveryExecutor.execute {
                        recoveryStarted.countDown()
                        releaseRecovery.await(30, TimeUnit.SECONDS)
                    }
                }
                assertTrue("Recovery worker should start", recoveryStarted.await(20, TimeUnit.SECONDS))
                scenario.onActivity { activity -> activity.agentLiveReplyExecutor.execute { replyRan.countDown() } }
                assertTrue("Live reply must not wait for recovery", replyRan.await(2, TimeUnit.SECONDS))
                assertTrue(releaseRecovery.count == 1L)
            } finally {
                releaseRecovery.countDown()
            }
        }
    }
}
