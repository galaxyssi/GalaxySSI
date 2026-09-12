package com.galaxyssi.chat

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.SystemClock
import android.provider.MediaStore
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.ImageView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CloudImageAnnotationUiTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test fun thumbnailOpensFullscreenAndSaveExportsRenderedImage() {
        val context = instrumentation.targetContext
        val bitmap = Bitmap.createBitmap(640, 480, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.WHITE) }
        val bytes = ByteArrayOutputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            bitmap.recycle()
            it.toByteArray()
        }
        val session = CloudImageAnnotationSession(context, listOf(CloudImagePayload("paper.png", "image/png", bytes)))
        val result = session.execute(CloudImageAnnotationPlan.TOOL, JSONObject().put("image_index", 0)
            .put("marks", JSONArray().put(JSONObject().put("left", 0.1).put("top", 0.1)
                .put("right", 0.8).put("bottom", 0.4).put("verdict", "note").put("note", "UI test annotation"))))
        assertTrue(result, JSONObject(result).getBoolean("image_saved"))
        val block = AgentRichContentCodec.decode(session.artifactSuffix().substringAfter("```galaxyssi-rich\n")
            .substringBeforeLast("```")).single()
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)) as MainActivity
        var saved: Uri? = null
        try {
            lateinit var root: View
            instrumentation.runOnMainSync {
                root = AgentRichContentView(activity, {}, {}, { _, _ -> }).create(AgentTranscriptEntry(
                    id = "annotation-ui-test", role = AgentTranscriptRole.ASSISTANT, text = session.artifactSuffix(),
                    timestampMillis = 1, richOutputJson = AgentRichContentCodec.encode(listOf(block))))
                activity.findViewById<ViewGroup>(android.R.id.content).addView(root,
                    ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            }
            var preview: ImageView? = null
            await {
                instrumentation.runOnMainSync {
                    preview = children(root).filterIsInstance<ImageView>()
                        .firstOrNull { it.contentDescription == block.title && it.drawable != null }
                }
                preview != null
            }
            instrumentation.runOnMainSync { assertTrue(preview!!.performClick()) }
            var save: AccessibilityNodeInfo? = null
            await {
                save = findNode(instrumentation.uiAutomation.rootInActiveWindow, activity.getString(R.string.peer_attachment_save))
                save != null
            }
            assertTrue(save!!.performAction(AccessibilityNodeInfo.ACTION_CLICK))
            val name = "\u6279\u6ce8\u56fe\u7247-${block.metadata["annotation_id"]!!.take(8)}.png"
            await {
                context.contentResolver.query(MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    arrayOf(MediaStore.Downloads._ID),
                    "${MediaStore.Downloads.DISPLAY_NAME} = ? AND ${MediaStore.Downloads.IS_PENDING} = 0",
                    arrayOf(name), null)?.use {
                    if (it.moveToFirst()) saved = android.content.ContentUris.withAppendedId(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI, it.getLong(0))
                }
                saved != null
            }
            val expected = context.contentResolver.openInputStream(Uri.parse(block.uri))!!.use { it.readBytes() }
            assertArrayEquals(expected, context.contentResolver.openInputStream(saved!!)!!.use { it.readBytes() })
        } finally {
            saved?.let { context.contentResolver.delete(it, null, null) }
            instrumentation.runOnMainSync { activity.finish() }
            File(context.filesDir, "agent-rich-output/image-annotations/${block.metadata["annotation_id"]}.png").delete()
        }
    }

    private fun await(check: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 15_000
        while (SystemClock.elapsedRealtime() < until) {
            if (check()) return
            SystemClock.sleep(50)
        }
        fail("Timed out waiting for annotation UI")
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
}
