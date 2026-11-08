package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class AgentDelayedActivityDeviceTest {
    @Test fun destroyedPageCannotSubmitOrRefreshFromDelayedCallbacks() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val transcripts = AgentTranscriptStore(context)
        val previous = transcripts.activeConversation().id
        val temporary = transcripts.createAgentConversation("Lifecycle test", privateMode = true, trackingPaused = true)
        val token = "destroyed-${UUID.randomUUID()}"
        val preferences = context.getSharedPreferences(DEBUG_AGENT_PREFS, Context.MODE_PRIVATE)
        try {
            transcripts.switchConversation(temporary.id)
            lateinit var closed: MainActivity
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra("galaxyssi_open_agent", true)
                .putExtra("galaxyssi_agent_conversation_id", temporary.id)).use { scenario ->
                scenario.onActivity { activity ->
                    closed = activity
                    // Queue while alive, then finish on the same UI turn before the delayed work runs.
                    activity.scheduleDebugAgentGoal(token, "Lifecycle test must not be submitted", false)
                    activity.finish()
                }
            }
            instrumentation.runOnMainSync {
                assertTrue(closed.isDestroyed)
                closed.globalInsightCountRefreshInProgress.set(false)
                closed.refreshGlobalInsightIndicator()
                closed.scheduleDebugAgentGoal(token, "Destroyed page must not submit", false)
                assertFalse(closed.globalInsightCountRefreshInProgress.get())
            }
            SystemClock.sleep(600)
            instrumentation.waitForIdleSync()
            assertFalse(preferences.contains(token))
            assertTrue(transcripts.page(conversationId = temporary.id, pageSize = 10).entries.isEmpty())
        } finally {
            preferences.edit().remove(token).commit()
            transcripts.switchConversation(previous)
            transcripts.deleteConversation(temporary.id)
        }
    }
}
