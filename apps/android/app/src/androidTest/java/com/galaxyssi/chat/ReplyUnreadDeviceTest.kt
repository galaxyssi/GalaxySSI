package com.galaxyssi.chat

import android.content.Context
import android.view.View
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReplyUnreadDeviceTest {
    @Test fun contactUnreadAppearsOnShortcutAndOpeningListDoesNotClearIt() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val id = "unread-device-test"
                try {
                    activity.summaries[id] = ContactSummary(lastAt = 1L, unreadCount = 1)
                    activity.refreshReplyUnreadDot()
                    assertEquals(View.VISIBLE, activity.findViewById<View>(R.id.agentSessionsUnreadDot).visibility)
                    assertFalse(activity.agentSessionTitle.text.contains('\uFFFC'))
                    activity.showAgentSessionsPage()
                    assertEquals(1, activity.summaries[id]?.unreadCount)
                } finally {
                    activity.summaries.remove(id)
                    activity.agentSessionsDialog?.dismiss()
                    activity.refreshReplyUnreadDot()
                }
            }
        }
    }

    @Test fun agentUnreadSurvivesRefreshAndOnlyMatchingConversationCanReadIt() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val id = "unread-device-test-agent"
        val entry = AgentTranscriptEntry("test-reply", AgentTranscriptRole.ASSISTANT,
            "Test", 1L, "test-final", id)
        val database = AgentTranscriptEntryDatabase.shared(context)
        try {
            assertTrue(database.insert(entry))
            AgentReplyUnreadStore.record(context, entry)
            AgentReplyUnreadStore.read(context, "different", listOf(entry))
            val prefs = context.getSharedPreferences("agent_reply_unread", Context.MODE_PRIVATE)
            assertEquals(setOf("test-final"), prefs.getStringSet(id, emptySet()))
            AgentReplyUnreadStore.read(context, id, listOf(entry))
            assertFalse(prefs.contains(id))
            AgentReplyUnreadStore.record(context, entry.copy(text = "Updated"), entry)
            assertFalse(prefs.contains(id))
        } finally {
            AgentReplyUnreadStore.remove(context, id)
            database.deleteById(entry.id)
        }
    }
}
