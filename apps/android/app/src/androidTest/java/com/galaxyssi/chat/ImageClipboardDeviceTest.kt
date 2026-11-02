package com.galaxyssi.chat

import android.content.ClipboardManager
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.FrameLayout
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.UUID

class ImageClipboardDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private fun main(block: () -> Unit) = instrumentation.runOnMainSync(block)
    private fun picture(color: Int): File {
        val file = File(context.filesDir, "composer-attachments-v1/copy-test-${UUID.randomUUID()}.png").apply { parentFile!!.mkdirs() }
        val image = Bitmap.createBitmap(96, 64, Bitmap.Config.ARGB_8888).apply { eraseColor(color) }
        try { file.outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) } } finally { image.recycle() }
        return file
    }
    private fun digest(uri: Uri): String = context.contentResolver.openInputStream(uri)!!.use {
        MessageDigest.getInstance("SHA-256").digest(it.readBytes()).joinToString("") { byte -> "%02x".format(byte) }
    }
    private fun uri(file: File) = LocalAttachmentUris.forFile(context, file, file.name, "image/png")

    @Test fun agentInlineAndLocalImagesKeepTheirOriginalEncodedBytes() {
        val file = picture(Color.CYAN)
        val source = uri(file)
        val expected = digest(source)
        val encoded = android.util.Base64.encodeToString(file.readBytes(), android.util.Base64.NO_WRAP)
        val copies = mutableListOf<Uri>()
        try {
            for (block in listOf(
                AgentRichBlock("inline-copy", AgentRichBlockType.IMAGE, title = "inline.png", mimeType = "image/png", dataB64 = encoded),
                AgentRichBlock("local-copy", AgentRichBlockType.IMAGE, title = file.name, mimeType = "image/png", uri = source.toString()))) {
                val result = ImageClipboard.snapshot(context, ClipboardImageSource.fromBlock(context, block))
                copies += result
                assertEquals(expected, digest(result))
                assertEquals("image/png", context.contentResolver.getType(result))
            }
            assertTrue(runCatching { ImageClipboard.snapshot(context,
                ClipboardImageSource("not-an-image.txt", "text/plain") { "text".byteInputStream() }) }.isFailure)
        } finally { copies.forEach { context.contentResolver.delete(it, null, null) }; file.delete() }
    }

    @Test fun clipboardSnapshotIsTheOriginalImageAndSurvivesDeletingItsSource() {
        val file = picture(Color.GREEN)
        val source = uri(file)
        var copied: Uri? = null
        try {
            val expected = digest(source)
            copied = ImageClipboard.snapshot(context, ClipboardImageSource.fromUri(context, source, file.name, "image/png"))
            assertEquals("image/png", context.contentResolver.getType(copied))
            assertNotEquals(source, copied)
            assertTrue(file.delete())
            assertEquals(expected, digest(copied))
            val clip = android.content.ClipData.newUri(context.contentResolver, "图片", copied)
            assertTrue(clip.description.hasMimeType("image/*")); assertNull(clip.getItemAt(0).text)
        } finally { copied?.let { context.contentResolver.delete(it, null, null) }; file.delete() }
    }

    @Test fun longPressSelectsTheTouchedImageAfterTheMessageListReorders() {
        val host = instrumentation.startActivitySync(Intent(context, ComposerEditingTestActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as ComposerEditingTestActivity
        val file = picture(Color.BLUE)
        try { main {
            val first = PeerChatAttachment("first.png", "image/png", file.length(), uri(file).toString())
            val second = first.copy(name = "second.png")
            val original = ChatMessage(41, "", false, Contact("copy-fixture", "图片测试", ""), attachments = listOf(first, second))
            var position = -1
            var selected: PeerChatAttachment? = null
            val adapter = MessageAdapter(listOf(original), onImageMessageActions = { row, image -> position = row; selected = image })
            val holder = adapter.onCreateViewHolder(FrameLayout(host), 0)
            adapter.onBindViewHolder(holder, 0)
            adapter.syncMessages(listOf(original.copy(id = 99, attachments = emptyList()), original))
            assertTrue(holder.attachments.getChildAt(1).performLongClick())
            assertEquals(1, position); assertEquals(second, selected)
        } } finally { main { host.finish() }; file.delete() }
    }

    @Test fun messageCopyPublishesImageContentAndNativePasteOpensTheEditor() {
        val monitor = instrumentation.addMonitor(MainActivity::class.java.name, null, false)
        context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        val activity = instrumentation.waitForMonitorWithTimeout(monitor, 30_000) as MainActivity
        instrumentation.removeMonitor(monitor)
        await { !activity.initialAgentHydrationPending && activity.conversationWindow.conversationId.isNotBlank() }
        val firstFile = picture(Color.RED); val secondFile = picture(Color.BLUE)
        val a = Contact("image-copy-source-${UUID.randomUUID()}", "图片复制测试", "")
        val b = Contact("image-copy-target-${UUID.randomUUID()}", "图片粘贴测试", "")
        val clipboard = context.getSystemService(ClipboardManager::class.java)
        var previous: android.content.ClipData? = null
        var copied: Uri? = null
        var draft: AgentWindowDraft? = null
        var contact: Contact? = null
        val imports = mutableListOf<Uri>()
        try {
            val expected = digest(uri(secondFile))
            val images = listOf(firstFile, secondFile).map { PeerChatAttachment(it.name, "image/png", it.length(), uri(it).toString()) }
            main {
                previous = clipboard.primaryClip
                draft = activity.conversationWindow.snapshot(); contact = activity.selectedContact
                activity.selectedContact = a
                activity.messages[a.id] = mutableListOf(ChatMessage(987654321, "图片说明", false, a, attachments = images))
                activity.showMessageActions(0, images[1])
            }
            await {
                val nodes = instrumentation.uiAutomation.rootInActiveWindow?.findAccessibilityNodeInfosByText(context.getString(R.string.common_copy)).orEmpty()
                nodes.any { node ->
                    if (node.text?.toString() != context.getString(R.string.common_copy)) false else {
                        var target = node
                        while (!target.isClickable && target.parent != null) target = target.parent
                        target.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    }
                }
            }
            await { main {
                val clip = clipboard.primaryClip
                copied = clip?.getItemAt(0)?.uri?.takeIf { it.authority == context.packageName + ".files" && it.pathSegments.firstOrNull() == "clipboard_images" }
                if (copied != null) { assertTrue(clip!!.description.hasMimeType("image/*")); assertNull(clip.getItemAt(0).text) }
            }; copied != null }
            assertEquals(expected, digest(copied!!)); assertTrue(secondFile.delete())
            for (agent in listOf(true, false)) {
                val editorMonitor = instrumentation.addMonitor(ComposerAttachmentEditorActivity::class.java.name, null, false)
                try {
                    main {
                        if (!agent) activity.selectedContact = b
                        assertTrue((if (agent) activity.agentGoalInput else activity.messageInput).onTextContextMenuItem(android.R.id.paste))
                    }
                    val editor = instrumentation.waitForMonitorWithTimeout(editorMonitor, 15_000) as ComposerAttachmentEditorActivity
                    try {
                        val items = ComposerAttachmentItem.decode(editor.intent.getStringExtra(ComposerAttachmentEditorActivity.ITEMS)!!)
                        val item = items[editor.intent.getIntExtra(ComposerAttachmentEditorActivity.INDEX, 0)]
                        imports += Uri.parse(item.uri)
                        assertEquals(expected, digest(Uri.parse(item.uri))); assertFalse(item.sendOriginal)
                        assertEquals(if (agent) "agent" else "peer", editor.intent.getStringExtra(ComposerAttachmentEditorActivity.ROUTE))
                        main { assertTrue(activity.messages[b.id].isNullOrEmpty()) }
                    } finally { main { editor.finish() }; instrumentation.waitForIdleSync() }
                } finally { instrumentation.removeMonitor(editorMonitor) }
            }
        } finally {
            main {
                runCatching { previous?.let(clipboard::setPrimaryClip) ?: clipboard.clearPrimaryClip() }
                activity.messages.remove(a.id); activity.messages.remove(b.id)
                draft?.let { activity.agentGoalInput.setText(it.text); activity.agentInputAttachments.clear(); activity.agentInputAttachments.addAll(it.attachments); activity.conversationWindow.save() }
                activity.selectedContact = contact
                activity.finish()
            }
            imports.forEach { LocalAttachmentUris.resolve(context, it)?.delete() }
            copied?.let { context.contentResolver.delete(it, null, null) }
            firstFile.delete(); secondFile.delete()
        }
    }

    private fun await(condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 30_000
        while (!condition()) { check(SystemClock.elapsedRealtime() < until) { "Image clipboard flow did not complete" }; Thread.sleep(100) }
    }
}
