package com.galaxyssi.chat

import android.content.Context
import android.text.Spanned
import android.text.style.ImageSpan
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReplyUnreadDeviceTest {
    @Test fun contactUnreadIsAdjacentToTitleAndOpeningListDoesNotClearIt() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val id = "unread-device-test"
                try {
                    activity.summaries[id] = ContactSummary(unreadCount = 1)
                    activity.refreshReplyUnreadDot()
                    val text = activity.agentSessionTitle.text as Spanned
                    assertEquals(1, text.getSpans(0, text.length, ImageSpan::class.java).size)
                    assertEquals(0, text.getSpanStart(text.getSpans(0, text.length, ImageSpan::class.java).single()))
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
        try {
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
        }
    }
}
