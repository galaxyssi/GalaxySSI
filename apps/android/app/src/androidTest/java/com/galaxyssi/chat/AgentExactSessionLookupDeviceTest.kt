package com.galaxyssi.chat

import android.content.Intent
import android.net.Uri
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
class AgentExactSessionLookupDeviceTest {
    @Test fun explicitReplyDoesNotLoadAnUnrelatedLockedTask() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val window = "exact-session-${UUID.randomUUID()}"
        val transcript = AgentTranscriptStore(context, window)
        val conversation = transcript.createConversation("Session lookup isolation", privateMode = true)
        val turn = "test-turn-${UUID.randomUUID()}"
        val prefs = AgentEncryptedPreferences(context, SharedPreferencesAgentSessionStore.PREFS)
        var unrelated = "task:000-isolation-${UUID.randomUUID()}"
        while (AgentActivePlanPersistence.lock(unrelated) === AgentActivePlanPersistence.lock("task:$turn")) {
            unrelated = "task:000-isolation-${UUID.randomUUID()}"
        }
        val lock = AgentActivePlanPersistence.lock(unrelated)
        val release = CountDownLatch(1)
        val acquired = CountDownLatch(1)
        val monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
        var activity: MainActivity? = null
        var holder: Thread? = null
        var worker: Thread? = null
        try {
            context.startActivity(Intent(context, ConversationWindowActivity::class.java)
                .setData(Uri.parse("galaxyssi://conversation-window/$window"))
                .putExtra(AgentConversationWindows.WINDOW_KEY, window)
                .putExtra(AgentConversationWindows.CONVERSATION, conversation.id)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_NEW_TASK))
            val opened = instrumentation.waitForMonitorWithTimeout(monitor, 20_000) as? MainActivity
                ?: error("Conversation window did not open")
            activity = opened
            assertTrue(opened.initialAgentHydrationReady.await(20, TimeUnit.SECONDS))
            // Only this test's encrypted root is created; real task state is untouched.
            prefs.writeString(unrelated, "{}")
            holder = thread(name = "test-unrelated-session-lock") {
                synchronized(lock) { acquired.countDown(); release.await(60, TimeUnit.SECONDS) }
            }
            assertTrue(acquired.await(5, TimeUnit.SECONDS))
            val result = FutureTask {
                opened.runtimeForConnectorResponse(
                    sourceMessageId = System.currentTimeMillis(), contactId = "test-no-contact",
                    conversationId = conversation.id, turnId = turn, taskId = turn, restorePersisted = true
                )
            }
            worker = thread(name = "test-exact-session-lookup") { result.run() }
            assertNull("Missing explicit task must not require unrelated snapshots", result.get(10, TimeUnit.SECONDS))
            assertEquals(1L, release.count)
        } finally {
            release.countDown()
            holder?.join(5_000)
            worker?.join(10_000)
            prefs.remove(unrelated)
            instrumentation.runOnMainSync { activity?.takeUnless { it.isDestroyed }?.finishAndRemoveTask() }
            instrumentation.removeMonitor(monitor)
            transcript.deleteConversation(conversation.id)
        }
    }
}
