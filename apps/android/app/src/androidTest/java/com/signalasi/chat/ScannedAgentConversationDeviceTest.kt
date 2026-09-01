package com.signalasi.chat

import android.content.Intent
import android.os.SystemClock
import android.view.View
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScannedAgentConversationDeviceTest {
    @Test
    fun scannedAgentStartsNewManualConversationWithMatchingModelSelection() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val activity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ) as MainActivity
        val previousConversation = activity.agentTranscriptStore.activeConversation()
        var createdConversationId = ""
        try {
            instrumentation.runOnMainSync {
                val target = AgentCallableTarget(
                    id = "desktop_test:claude",
                    title = "Claude Code · DESKTOP-TEST",
                    kind = AgentConnectorKind.AGENT,
                    status = AgentConnectorStatus.AVAILABLE,
                    capabilities = listOf(AgentCapability.CHAT, AgentCapability.CODE),
                    invocationProfile = AgentInvocationProfile(
                        defaultModelId = "best",
                        models = listOf(AgentModelOption("best", "Best"))
                    )
                )
                activity.showMainTab(PAGE_AGENT)
                activity.createAgentConversation(target)

                val created = activity.agentTranscriptStore.activeConversation()
                createdConversationId = created.id
                val selection = AgentModelSelectionSettings.selection(activity, created.id)
                assertFalse(created.id == previousConversation.id)
                assertEquals(AgentModelSelectionMode.MANUAL, selection.mode)
                assertEquals(target.id, selection.targetId)
                assertEquals("best", selection.modelId)
                assertEquals(target.title, selection.displayName)
                assertEquals(target.title, created.selectedModelOrAgent)
                assertEquals(View.VISIBLE, activity.agentPage.visibility)
                assertEquals(View.GONE, activity.chatPage.visibility)
            }

            val deadline = SystemClock.uptimeMillis() + 5_000L
            var subtitle = ""
            while (SystemClock.uptimeMillis() < deadline) {
                instrumentation.waitForIdleSync()
                instrumentation.runOnMainSync { subtitle = activity.agentSubtitleText.text.toString() }
                if (subtitle.contains("Claude Code") && !subtitle.contains("Auto")) break
                SystemClock.sleep(100L)
            }
            assertTrue(subtitle.contains("Claude Code"))
            assertFalse(subtitle.contains("Auto"))
        } finally {
            instrumentation.runOnMainSync {
                if (createdConversationId.isNotBlank()) {
                    activity.agentTranscriptStore.deleteConversation(createdConversationId)
                }
                activity.agentTranscriptStore.switchConversation(previousConversation.id)
                activity.finish()
            }
        }
    }
}
