package com.galaxyssi.chat

import android.graphics.Bitmap
import android.os.SystemClock
import android.text.Spanned
import android.text.style.ImageSpan
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class ConversationStatusDeviceTest {
    @Test fun listUpdatesRunningToUnreadToReadWithoutUnreadDot() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val key = "status-test-${UUID.randomUUID()}"
        val transcript = AgentTranscriptStore(context, key)
        val workspaces = EncryptedAgentWorkspaceStore(context)
        var conversationId = ""
        var original = ""
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            try {
                await(scenario) { !it.initialAgentHydrationPending }
                scenario.onActivity { original = it.agentTranscriptStore.activeConversation().id }
                val conversation = transcript.createConversation("状态图标验证", privateMode = true)
                conversationId = conversation.id
                transcript.append(AgentTranscriptRole.USER, "状态图标测试", conversationId = conversation.id,
                    turnId = key, taskId = key)
                var workspace = workspaces.upsert(AgentWorkspace(key, key, conversation.id, key,
                    goal = "UI status verification", status = AgentWorkspaceStatus.RUNNING), 0)
                scenario.onActivity { it.showAgentSessionsPage() }
                awaitIcon(scenario, ConversationHubAgentStatus.RUNNING)
                screenshot(context, "conversation-status-running.png")
                transcript.append(AgentTranscriptRole.ASSISTANT, "状态图标验证完成", "assistant-final:$key",
                    conversationId = conversation.id, turnId = key, taskId = key)
                workspace = workspaces.upsert(workspace.copy(status = AgentWorkspaceStatus.COMPLETED), workspace.revision)
                awaitIcon(scenario, ConversationHubAgentStatus.COMPLETE_UNREAD)
                scenario.onActivity { activity ->
                    val root = activity.agentSessionsDialog!!.window!!.decorView
                    val title = descendants(root).filterIsInstance<TextView>().first { it.text.toString() == "状态图标验证" }
                    val text = title.text
                    assertTrue(text !is Spanned || text.getSpans(0, text.length, ImageSpan::class.java).isEmpty())
                }
                screenshot(context, "conversation-status-completed.png")
                scenario.onActivity { activity ->
                    val root = activity.agentSessionsDialog!!.window!!.decorView
                    var row: View = descendants(root).filterIsInstance<TextView>().first { it.text.toString() == "状态图标验证" }
                    while (!row.isClickable) row = row.parent as View
                    row.performClick()
                }
                await(scenario) { !AgentReplyUnreadStore.hasUnread(it, conversation.id) }
                scenario.onActivity { it.showAgentSessionsPage() }
                awaitIcon(scenario, ConversationHubAgentStatus.READ, title = "状态图标验证")
                screenshot(context, "conversation-status-read.png")
                assertEquals(AgentWorkspaceStatus.COMPLETED, workspaces.find(key)?.status)
            } finally {
                scenario.onActivity { activity ->
                    activity.agentSessionsDialog?.dismiss()
                    if (original.isNotBlank()) activity.agentTranscriptStore.switchConversation(original)
                    activity.resetAgentTranscriptRendering(original)
                    activity.refreshAgentConversationHeader()
                    activity.refreshAgentTranscriptWindow()
                }
                workspaces.delete(key)
                if (conversationId.isNotBlank()) transcript.deleteConversation(conversationId)
            }
        }
    }

    @Test fun allStatusIconsHaveAccessibleDistinctLabelsAndStableSize() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            val labels = ConversationHubAgentStatus.entries.map { state ->
                val icon = ConversationHubStatusIcon(context, state)
                assertEquals(state, icon.tag)
                assertNotNull(icon.drawable)
                icon.contentDescription.toString()
            }
            assertEquals(labels.size, labels.toSet().size)
        }
    }

    private fun awaitIcon(scenario: ActivityScenario<MainActivity>, status: ConversationHubAgentStatus, title: String = "状态图标验证") =
        await(scenario) { activity ->
            val root = activity.agentSessionsDialog?.window?.decorView ?: return@await false
            val label = descendants(root).filterIsInstance<TextView>().firstOrNull { it.text.toString() == title }
                ?: return@await false
            var row: View = label
            while (!row.isClickable && row.parent is View) row = row.parent as View
            descendants(row).filterIsInstance<ConversationHubStatusIcon>().any { it.status == status }
        }

    private fun await(scenario: ActivityScenario<MainActivity>, condition: (MainActivity) -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 20000
        do {
            var ready = false
            scenario.onActivity { ready = condition(it) }
            if (ready) return
            SystemClock.sleep(100)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Conversation status did not update")
    }

    private fun descendants(view: View): Sequence<View> = sequence {
        yield(view)
        if (view is ViewGroup) for (index in 0 until view.childCount) yieldAll(descendants(view.getChildAt(index)))
    }
    private fun screenshot(context: android.content.Context, name: String) {
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        java.io.File(context.getExternalFilesDir(null), name).outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        bitmap.recycle()
    }
}
