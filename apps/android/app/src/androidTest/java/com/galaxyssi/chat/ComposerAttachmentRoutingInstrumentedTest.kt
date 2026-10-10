package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.view.View
import android.widget.LinearLayout
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class ComposerAttachmentRoutingInstrumentedTest {
    @Test fun editorResultsStageWithoutSendingAndStayBoundToTheirOwner() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val monitor = instrumentation.addMonitor(MainActivity::class.java.name, null, false)
        context.startActivity(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        val activity = instrumentation.waitForMonitorWithTimeout(monitor, 30_000L) as MainActivity
        val deadline = android.os.SystemClock.elapsedRealtime() + 30_000L
        while (activity.initialAgentHydrationPending || activity.conversationWindow.conversationId.isBlank()) {
            check(android.os.SystemClock.elapsedRealtime() < deadline) { "Main composer did not hydrate" }
            Thread.sleep(100)
        }
        val file = File(context.filesDir, "composer-attachments-v1/test-${UUID.randomUUID()}.png")
        file.parentFile!!.mkdirs()
        val bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.GREEN) }
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
        val item = ComposerAttachmentItem("routing-fixture", LocalAttachmentUris.forFile(context, file, "test.png", "image/png").toString(),
            "test.png", "image/png", file.length())
        var originalDraft: AgentWindowDraft? = null
        var originalContact: Contact? = null
        val firstPeer = "crop-test-first-${UUID.randomUUID()}"
        val secondPeer = "crop-test-second-${UUID.randomUUID()}"
        try {
            instrumentation.runOnMainSync {
                originalDraft = activity.conversationWindow.snapshot()
                originalContact = activity.selectedContact
                val target = activity.agentTranscriptStore.activeConversation().id
                val goal = activity.agentGoalInput.text.toString()
                val result = Intent().putExtra(ComposerAttachmentEditorActivity.ITEMS, ComposerAttachmentItem.encode(listOf(item)))
                    .putExtra(ComposerAttachmentEditorActivity.ROUTE, "agent")
                    .putExtra(ComposerAttachmentEditorActivity.TARGET, target)
                assertTrue(activity.handleComposerAttachmentResult(REQUEST_COMPOSER_ATTACHMENT_EDIT, Activity.RESULT_OK, result))
                assertEquals(listOf(item.uri), activity.agentInputAttachments.map { it.uri.toString() })
                assertEquals(goal, activity.agentGoalInput.text.toString())
                assertTrue(activity.handleComposerAttachmentResult(REQUEST_COMPOSER_ATTACHMENT_EDIT, Activity.RESULT_CANCELED, null))
                assertEquals(1, activity.agentInputAttachments.size)

                activity.selectedContact = Contact(secondPeer, "裁剪测试联系人 B", "")
                result.putExtra(ComposerAttachmentEditorActivity.ROUTE, "peer")
                    .putExtra(ComposerAttachmentEditorActivity.TARGET, firstPeer)
                activity.handleComposerAttachmentResult(REQUEST_COMPOSER_ATTACHMENT_EDIT, Activity.RESULT_OK, result)
                assertEquals(1, activity.peerComposerAttachments(firstPeer).size)
                assertTrue(activity.peerComposerAttachments(secondPeer).isEmpty())
                assertTrue(activity.messages[firstPeer].isNullOrEmpty())
                assertEquals(1, activity.agentInputAttachments.size)

                activity.selectedContact = Contact(firstPeer, "裁剪测试联系人 A", "")
                activity.renderPeerComposerAttachments()
                activity.updateInputActions()
                assertEquals(View.VISIBLE, activity.sendButton.visibility)
                val row = activity.findViewById<LinearLayout>(R.id.chatAttachmentPreviewList)
                assertEquals(1, row.childCount)
                val card = row.getChildAt(0) as android.widget.FrameLayout
                card.getChildAt(card.childCount - 1).performClick()
                assertTrue(activity.peerComposerAttachments(firstPeer).isEmpty())
                assertEquals(1, activity.agentInputAttachments.size)
            }
        } finally {
            instrumentation.runOnMainSync {
                activity.setPeerComposerAttachments(firstPeer, emptyList())
                activity.setPeerComposerAttachments(secondPeer, emptyList())
                originalDraft?.let { draft ->
                    activity.agentInputAttachments.clear(); activity.agentInputAttachments.addAll(draft.attachments)
                    activity.agentGoalInput.setText(draft.text)
                    activity.conversationWindow.save()
                }
                activity.selectedContact = originalContact
                activity.finish()
            }
            instrumentation.removeMonitor(monitor)
            file.delete()
        }
    }
}
