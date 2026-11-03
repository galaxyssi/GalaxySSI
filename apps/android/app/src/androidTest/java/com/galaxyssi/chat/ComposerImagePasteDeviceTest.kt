package com.galaxyssi.chat

import android.content.ClipData
import android.content.ClipDescription
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.view.inputmethod.EditorInfo
import androidx.core.content.FileProvider
import androidx.core.view.ContentInfoCompat
import androidx.core.view.ViewCompat
import androidx.core.view.inputmethod.EditorInfoCompat
import androidx.core.view.inputmethod.InputConnectionCompat
import androidx.core.view.inputmethod.InputContentInfoCompat
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.ui.ComposerImageContentReceiver
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.UUID

class ComposerImagePasteDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private fun main(block: () -> Unit) = instrumentation.runOnMainSync(block)

    @Test fun imagesAndMixedTextReachBothRealInputLayoutsWithoutPastingUris() {
        both { host, uri ->
            val accepted = mutableListOf<Uri>()
            main {
                host.input.imageContentReceiver = ComposerImageContentReceiver(host.input) { images, release ->
                    accepted += images; release(); true
                }
                host.input.setText("左右"); host.input.setSelection(1)
                val clip = ClipData("fixture", arrayOf("image/png", "text/plain"), ClipData.Item(uri)).apply {
                    addItem(ClipData.Item("测试图片"))
                }
                assertNull(ViewCompat.performReceiveContent(host.input,
                    ContentInfoCompat.Builder(clip, ContentInfoCompat.SOURCE_CLIPBOARD).build()))
                assertEquals(listOf(uri), accepted)
                assertEquals("左测试图片右", host.input.text.toString())
                assertEquals(0, host.recordingStarts)
            }
        }
    }

    @Test fun keyboardImageCommitAdvertisesImagesAndIsConsumedExactlyOnce() {
        both { host, uri -> main {
            var calls = 0
            host.input.imageContentReceiver = ComposerImageContentReceiver(host.input) { images, release ->
                assertEquals(listOf(uri), images); calls++; release(); true
            }
            val info = EditorInfo()
            val connection = host.input.onCreateInputConnection(info)!!
            assertTrue(EditorInfoCompat.getContentMimeTypes(info).contains("image/*"))
            assertTrue(InputConnectionCompat.commitContent(connection, info,
                InputContentInfoCompat(uri, ClipDescription("图片", arrayOf("image/png")), null), 0, null))
            assertEquals(1, calls)
            assertEquals("123", host.input.text.toString())
            assertFalse(InputConnectionCompat.commitContent(connection, info,
                InputContentInfoCompat(uri, ClipDescription("PDF", arrayOf("application/pdf")), null), 0, null))
            assertEquals(1, calls)
        } }
    }

    @Test fun plainImageUrlsRemainTextAndRejectedImagesAreNotLost() {
        both { host, uri -> main {
            var calls = 0
            val receiver = ComposerImageContentReceiver(host.input) { _, _ -> calls++; false }
            host.input.imageContentReceiver = receiver
            val text = ContentInfoCompat.Builder(ClipData.newPlainText("URL", "https://example.org/photo.png"),
                ContentInfoCompat.SOURCE_CLIPBOARD).build()
            assertSame(text, receiver.receive(text))
            assertEquals(0, calls)
            val image = ContentInfoCompat.Builder(ClipData.newUri(context.contentResolver, "图片", uri),
                ContentInfoCompat.SOURCE_CLIPBOARD).build()
            assertSame(image, receiver.receive(image))
            assertEquals(1, calls)
        } }
    }

    @Test fun pastedImagesOpenTheNormalEditorForAgentAndPeerWithoutSending() {
        val monitor = instrumentation.addMonitor(MainActivity::class.java.name, null, false)
        context.startActivity(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        val activity = instrumentation.waitForMonitorWithTimeout(monitor, 30_000) as MainActivity
        instrumentation.removeMonitor(monitor)
        val deadline = android.os.SystemClock.elapsedRealtime() + 30_000
        while (activity.initialAgentHydrationPending || activity.conversationWindow.conversationId.isBlank()) {
            check(android.os.SystemClock.elapsedRealtime() < deadline) { "Main composer did not hydrate" }
            Thread.sleep(100)
        }
        var draft: AgentWindowDraft? = null
        var contact: Contact? = null
        val retained = mutableListOf<File>()
        main { draft = activity.conversationWindow.snapshot(); contact = activity.selectedContact; activity.agentInputAttachments.clear() }
        try {
            for (agent in listOf(true, false)) {
                val file = File(context.cacheDir, "composer-crops/paste-${UUID.randomUUID()}.png").apply { parentFile!!.mkdirs() }
                val bitmap = Bitmap.createBitmap(256, 192, Bitmap.Config.ARGB_8888)
                file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }; bitmap.recycle()
                val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
                val editorMonitor = instrumentation.addMonitor(ComposerAttachmentEditorActivity::class.java.name, null, false)
                try {
                    var target = ""
                    main {
                        if (!agent) activity.selectedContact = Contact("paste-peer-fixture", "图片粘贴测试", "")
                        target = if (agent) activity.agentTranscriptStore.activeConversation().id else "paste-peer-fixture"
                        val input = if (agent) activity.agentGoalInput else activity.messageInput
                        assertNull(ViewCompat.performReceiveContent(input, ContentInfoCompat.Builder(
                            ClipData.newUri(context.contentResolver, "图片", uri), ContentInfoCompat.SOURCE_CLIPBOARD).build()))
                    }
                    val editor = instrumentation.waitForMonitorWithTimeout(editorMonitor, 15_000) as? ComposerAttachmentEditorActivity
                        ?: error("Image paste did not open the attachment editor")
                    try {
                        val item = ComposerAttachmentItem.decode(editor.intent.getStringExtra(ComposerAttachmentEditorActivity.ITEMS)!!).single()
                        assertEquals(target, editor.intent.getStringExtra(ComposerAttachmentEditorActivity.TARGET))
                        assertEquals(if (agent) "agent" else "peer", editor.intent.getStringExtra(ComposerAttachmentEditorActivity.ROUTE))
                        assertTrue(item.isImage); assertFalse(item.sendOriginal)
                        val privateFile = LocalAttachmentUris.resolve(context, Uri.parse(item.uri))!!
                        retained += privateFile
                        assertTrue(file.delete()); assertTrue(privateFile.exists())
                        assertNotEquals(uri.toString(), item.uri)
                        main {
                            assertNotNull(editor.window.decorView.findViewWithTag<android.widget.CheckBox>("composer_original_quality"))
                            assertTrue(activity.messages["paste-peer-fixture"].isNullOrEmpty())
                        }
                    } finally { main { editor.finish() } }
                } finally { instrumentation.removeMonitor(editorMonitor); file.delete() }
            }
        } finally {
            main {
                draft?.let { activity.agentInputAttachments.clear(); activity.agentInputAttachments.addAll(it.attachments)
                    activity.agentGoalInput.setText(it.text); activity.conversationWindow.save() }
                activity.selectedContact = contact
                activity.finish()
            }
            retained.forEach { it.delete() }
        }
    }

    private fun both(test: (ComposerEditingTestActivity, Uri) -> Unit) {
        val file = File(context.cacheDir, "composer-crops/paste-${UUID.randomUUID()}.png").apply { parentFile!!.mkdirs() }
        val bitmap = Bitmap.createBitmap(32, 24, Bitmap.Config.ARGB_8888)
        try {
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
            for (id in listOf(R.id.agentGoalInput, R.id.messageInput)) {
                val host = instrumentation.startActivitySync(Intent(context, ComposerEditingTestActivity::class.java)
                    .putExtra("input_id", id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as ComposerEditingTestActivity
                try { test(host, uri) } finally { main { host.finish() } }
            }
        } finally { bitmap.recycle(); file.delete() }
    }
}
