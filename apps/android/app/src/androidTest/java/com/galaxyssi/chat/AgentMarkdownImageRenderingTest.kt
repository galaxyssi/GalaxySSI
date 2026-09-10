package com.galaxyssi.chat

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.os.SystemClock
import android.provider.MediaStore
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentMarkdownImageRenderingTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test fun streamingFinalAndHistoryDisplayImages() = withActivity { activity, source, name ->
        AgentMarkdownImageStore.cache(activity, source, fixture())
        val text = "Before\n\n![$name]($source)\n\nAfter"
        val raw = AgentRichContentCodec.encode(listOf(AgentRichBlock("text", AgentRichBlockType.TEXT, text = text)))
        listOf("", raw, AgentRichContentCodec.normalize(raw)).forEach { rich ->
            val root = render(activity, text, rich)
            await { image(root, name)?.drawable != null }
            instrumentation.runOnMainSync {
                assertTrue(image(root, name)!!.width > 0)
                assertFalse(children(root).filterIsInstance<TextView>().any { it.text.contains("![") })
            }
        }
    }

    @Test fun failedImageHasSourceAndRetryAndCanRecover() = withActivity { activity, source, name ->
        val root = render(activity, "![$name]($source)")
        await { children(root).filterIsInstance<TextView>().any {
            it.text.toString() == activity.getString(R.string.rich_output_load_failed) && it.isShown
        } }
        instrumentation.runOnMainSync {
            assertTrue(children(root).any {
                it.contentDescription == activity.getString(R.string.rich_output_image_source) && it.isShown
            })
        }
        AgentMarkdownImageStore.cache(activity, source, fixture())
        instrumentation.runOnMainSync {
            children(root).single { it.contentDescription == activity.getString(R.string.common_retry) }.performClick()
        }
        await { image(root, name)?.drawable != null }
        instrumentation.runOnMainSync {
            assertFalse(children(root).filterIsInstance<TextView>().any {
                it.text.toString() == activity.getString(R.string.rich_output_load_failed) && it.isShown
            })
        }
    }

    @Test fun fullscreenSaveKeepsOriginalImageBytes() = withActivity { activity, source, name ->
        val bytes = fixture()
        AgentMarkdownImageStore.cache(activity, source, bytes)
        val root = render(activity, "![$name]($source)")
        await { image(root, name)?.drawable != null }
        instrumentation.runOnMainSync { image(root, name)!!.performClick() }
        val saveLabel = activity.getString(R.string.peer_attachment_save)
        var save: AccessibilityNodeInfo? = null
        val until = SystemClock.elapsedRealtime() + 10_000
        while (save == null && SystemClock.elapsedRealtime() < until) {
            save = findNode(instrumentation.uiAutomation.rootInActiveWindow, saveLabel)
            SystemClock.sleep(50)
        }
        assertNotNull("Fullscreen must expose Save", save)
        assertTrue(save!!.performAction(AccessibilityNodeInfo.ACTION_CLICK))
        val resolver = activity.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        var saved: android.net.Uri? = null
        val deadline = SystemClock.elapsedRealtime() + 10_000
        try {
            while (saved == null && SystemClock.elapsedRealtime() < deadline) {
                resolver.query(collection, arrayOf(MediaStore.Downloads._ID),
                    "${MediaStore.Downloads.DISPLAY_NAME} = ? AND ${MediaStore.Downloads.IS_PENDING} = 0",
                    arrayOf("$name.png"), null)?.use { cursor ->
                    if (cursor.moveToFirst()) saved = android.content.ContentUris.withAppendedId(collection, cursor.getLong(0))
                }
                SystemClock.sleep(50)
            }
            assertNotNull("Save must create a Downloads image", saved)
            assertArrayEquals(bytes, resolver.openInputStream(saved!!)!!.use { it.readBytes() })
        } finally {
            saved?.let { resolver.delete(it, null, null) }
            instrumentation.uiAutomation.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK)
        }
    }

    @Test fun chineseTitleHidesEnglishFilenameAndTechnicalFooter() = withActivity { activity, source, name ->
        org.junit.Assume.assumeTrue(activity.resources.configuration.locales[0].language == "zh")
        AgentMarkdownImageStore.cache(activity, source, fixture())
        val title = "\u9cad\u9c7c\u56fe\u7247"
        val text = "[\u6253\u5f00/\u4e0b\u8f7d$title]($source)"
        val raw = AgentRichContentCodec.encode(listOf(AgentRichBlock("image", AgentRichBlockType.IMAGE,
            title = "$name.png", text = "outputs \u00b7 97.6 KB", uri = source,
            metadata = mapOf(AgentMarkdownImages.SOURCE to source, "category" to "outputs"))))
        val root = render(activity, text, raw)
        await { children(root).filterIsInstance<ImageView>().any { it.contentDescription == title && it.drawable != null } }
        instrumentation.runOnMainSync {
            val visible = children(root).filterIsInstance<TextView>().map { it.text.toString() }
            assertTrue(visible.contains(title))
            assertFalse(visible.any { it.contains("outputs") || it.contains("97.6 KB") || it.contains("$name.png") })
        }
    }

    private fun withActivity(test: (MainActivity, String, String) -> Unit) {
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)) as MainActivity
        val name = "markdown-image-test-${UUID.randomUUID()}"
        val source = "https://127.0.0.1/$name.png"
        try { test(activity, source, name) }
        finally {
            AgentMarkdownImageStore.cacheFile(activity, source).delete()
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    private fun render(activity: MainActivity, text: String, rich: String = ""): View {
        lateinit var root: View
        instrumentation.runOnMainSync {
            root = AgentRichContentView(activity, {}, {}, { _, _ -> }).create(AgentTranscriptEntry(
                id = "image-test", role = AgentTranscriptRole.ASSISTANT, text = text,
                timestampMillis = 1, richOutputJson = rich))
            val content = activity.findViewById<ViewGroup>(android.R.id.content)
            content.findViewWithTag<View>("markdown-image-test-content")?.let { content.removeView(it) }
            root.tag = "markdown-image-test-content"
            root.setBackgroundColor(Color.WHITE)
            content.addView(root, ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        instrumentation.waitForIdleSync()
        return root
    }

    private fun await(check: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        while (SystemClock.elapsedRealtime() < deadline) {
            var done = false
            instrumentation.runOnMainSync { done = check() }
            if (done) return
            SystemClock.sleep(50)
        }
        fail("Timed out waiting for image state")
    }

    private fun image(root: View, name: String): ImageView? {
        val title = if (root.resources.configuration.locales[0].language == "zh")
            root.context.getString(R.string.rich_output_type_image) else name
        return children(root).filterIsInstance<ImageView>()
            .firstOrNull { it !is ImageButton && it.contentDescription == title }
    }

    private fun children(view: View): List<View> = buildList {
        add(view)
        if (view is ViewGroup) for (i in 0 until view.childCount) addAll(children(view.getChildAt(i)))
    }

    private fun findNode(node: AccessibilityNodeInfo?, label: String): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.contentDescription == label) return node
        for (i in 0 until node.childCount) findNode(node.getChild(i), label)?.let { return it }
        return null
    }

    private fun fixture(): ByteArray {
        val bitmap = Bitmap.createBitmap(160, 90, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.CYAN) }
        return ByteArrayOutputStream().use { output ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
            bitmap.recycle()
            output.toByteArray()
        }
    }
}
