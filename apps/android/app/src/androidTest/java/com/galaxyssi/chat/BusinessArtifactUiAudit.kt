package com.galaxyssi.chat

import android.app.Instrumentation
import android.content.ContentUris
import android.graphics.Bitmap
import android.graphics.Rect
import android.net.Uri
import android.os.SystemClock
import android.provider.MediaStore
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.ImageView
import java.io.File
import java.security.MessageDigest
import org.json.JSONObject

/** Click a real delivered preview and its save control, without resending a model task. */
internal fun auditBusinessImageUi(
    instrumentation: Instrumentation, window: MainActivity, entry: AgentTranscriptEntry, directory: File
): JSONObject {
    val context = instrumentation.targetContext
    val rawBlocks = AgentRichContentCodec.decode(entry.richOutputJson)
    val block = AgentImagePresentation.annotate(rawBlocks,
        entry.text + "\n" + rawBlocks.filter { it.type == AgentRichBlockType.TEXT }.joinToString("\n") { it.text },
        window.resources.configuration.locales[0].language == "zh",
        window.getString(R.string.rich_output_type_image)).first {
        it.type == AgentRichBlockType.IMAGE && AgentDesktopArtifactStore.localFile(context, it) != null
    }
    val resolved = AgentDesktopArtifactStore.resolveBlock(context, block)
    val expected = context.contentResolver.openInputStream(Uri.parse(resolved.uri))!!.use { input ->
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(65536)
        while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
        digest.digest().joinToString("") { "%02x".format(it) }
    }
    val title = AgentImagePresentation.title(resolved, window.getString(R.string.rich_output_type_image))
    val capture = captureBusinessOutput(instrumentation, window, File(directory, "before-open.png"), entry.id)
    check(capture.targetVisible && capture.stable && capture.focused)
    var clicked = false
    instrumentation.runOnMainSync {
        val position = window.agentTranscriptAdapter.indexOfEntry(entry.id)
        val row = window.agentOutputList.findViewHolderForAdapterPosition(position)?.itemView
        val image = row?.let(::auditViews)?.filterIsInstance<ImageView>()?.firstOrNull {
            it.contentDescription == title && it.isClickable && it.drawable != null && it.getGlobalVisibleRect(Rect())
        }
        clicked = image?.performClick() == true
    }
    check(clicked) { "Delivered image thumbnail was not clickable" }
    val result = JSONObject().put("entry_id", entry.id).put("artifact_id", block.id)
        .put("scope", "first_delivered_preview_ui_open_and_save").put("thumbnail_clicked", true)
    try {
        var save: AccessibilityNodeInfo? = null
        check(auditAwait {
            save = auditNode(instrumentation.uiAutomation.rootInActiveWindow) {
                it.contentDescription == window.getString(R.string.peer_attachment_save)
            }
            save != null
        }) { "Fullscreen save control unavailable" }
        val image = auditNode(instrumentation.uiAutomation.rootInActiveWindow) {
            it.className == ImageView::class.java.name && it.contentDescription == title && !it.isClickable
        }
        val imageBounds = Rect().also { image?.getBoundsInScreen(it) }
        check(image != null && imageBounds.width() > window.resources.displayMetrics.widthPixels * .8)
        SystemClock.sleep(600)
        val screenshot = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { File(directory, "fullscreen.png").outputStream().use { screenshot.compress(Bitmap.CompressFormat.PNG, 100, it) } }
        finally { screenshot.recycle() }
        result.put("fullscreen_open", true)
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        fun rows(after: Long): List<Long> {
            val ids = mutableListOf<Long>()
            context.contentResolver.query(collection, arrayOf(MediaStore.Downloads._ID),
                "${MediaStore.Downloads.RELATIVE_PATH}=? AND ${MediaStore.Downloads.IS_PENDING}=0 AND ${MediaStore.Downloads._ID}>?",
                arrayOf("Download/GalaxySSI/", after.toString()), "${MediaStore.Downloads._ID} DESC")?.use { cursor ->
                while (cursor.moveToNext()) ids += cursor.getLong(0)
            }
            return ids
        }
        val before = rows(0).maxOrNull() ?: 0L
        check(requireNotNull(save).performAction(AccessibilityNodeInfo.ACTION_CLICK))
        var matchedId: Long? = null
        check(auditAwait {
            matchedId = rows(before).firstOrNull { id ->
                context.contentResolver.openInputStream(ContentUris.withAppendedId(collection, id))?.use { input ->
                    val digest = MessageDigest.getInstance("SHA-256")
                    val buffer = ByteArray(65536)
                    while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
                    digest.digest().joinToString("") { "%02x".format(it) } == expected
                } == true
            }
            matchedId != null
        }) { "Save click did not create a matching download" }
        result.put("save_clicked", true).put("new_download_hash_matches", true).put("sha256", expected)
            .put("download_id", matchedId)
        File(directory, "ui-audit.json").writeText(result.toString(2))
        return result
    } finally {
        instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
    }
}

private fun auditAwait(condition: () -> Boolean): Boolean {
    val until = SystemClock.elapsedRealtime() + 15000
    do { if (condition()) return true; SystemClock.sleep(150) } while (SystemClock.elapsedRealtime() < until)
    return false
}

private fun auditViews(view: View): List<View> = listOf(view) + if (view is ViewGroup)
    (0 until view.childCount).flatMap { auditViews(view.getChildAt(it)) } else emptyList()

private fun auditNode(node: AccessibilityNodeInfo?, match: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
    if (node == null) return null
    if (match(node)) return node
    for (i in 0 until node.childCount) auditNode(node.getChild(i), match)?.let { return it }
    return null
}
