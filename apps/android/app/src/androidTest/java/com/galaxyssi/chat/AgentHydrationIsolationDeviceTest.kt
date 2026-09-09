package com.galaxyssi.chat

import android.content.Intent
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentHydrationIsolationDeviceTest {
    @Test fun transcriptReadinessDoesNotWaitForGlobalDashboardStorage() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val key = "hydration-isolation-${UUID.randomUUID()}"
        val store = AgentTranscriptStore(context, key)
        val conversation = store.createConversation("Hydration isolation", privateMode = true)
        store.append(AgentTranscriptRole.USER, "Hydration isolation", conversationId = conversation.id)
        val lock = checkNotNull(GlobalAgentRepository::class.java.getDeclaredField("STORE_LOCK").apply {
            isAccessible = true
        }.get(null))
        val acquired = CountDownLatch(1)
        val release = CountDownLatch(1)
        val holder = thread(name = "test-dashboard-storage-stall") {
            synchronized(lock) {
                acquired.countDown()
                release.await(60, TimeUnit.SECONDS)
            }
        }
        val monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
        var activity: MainActivity? = null
        try {
            assertTrue(acquired.await(5, TimeUnit.SECONDS))
            context.startActivity(Intent(context, ConversationWindowActivity::class.java)
                .setData(Uri.parse("galaxyssi://conversation-window/$key"))
                .putExtra(AgentConversationWindows.WINDOW_KEY, key)
                .putExtra(AgentConversationWindows.CONVERSATION, conversation.id)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_NEW_TASK))
            activity = instrumentation.waitForMonitorWithTimeout(monitor, 20_000) as? MainActivity
                ?: error("Conversation window did not open")
            assertTrue("Transcript readiness must not require the dashboard storage lock",
                activity.initialAgentHydrationReady.await(10, TimeUnit.SECONDS))
            assertEquals("The dashboard is still blocked during this assertion", 1L, release.count)
            instrumentation.runOnMainSync {
                assertFalse(activity.initialAgentHydrationPending)
                assertEquals(conversation.id, activity.agentTranscriptWindow.conversationId)
                assertTrue(activity.agentTranscriptWindow.entries.any { it.text == "Hydration isolation" })
            }
        } finally {
            release.countDown()
            holder.join(5_000)
            instrumentation.runOnMainSync { activity?.takeUnless { it.isDestroyed }?.finishAndRemoveTask() }
            instrumentation.removeMonitor(monitor)
            store.deleteConversation(conversation.id)
        }
    }
}
