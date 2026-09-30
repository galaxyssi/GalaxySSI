package com.galaxyssi.chat

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.SystemClock
import org.json.JSONObject
import java.io.File

internal object ScreenPageVisualPolicy {
    fun same(first: IntArray, next: IntArray): Boolean {
        if (first.isEmpty() || first.size != next.size) return false
        val changed = first.indices.count { index ->
            val a = first[index]; val b = next[index]
            kotlin.math.abs((a shr 16 and 255) - (b shr 16 and 255)) +
                kotlin.math.abs((a shr 8 and 255) - (b shr 8 and 255)) +
                kotlin.math.abs((a and 255) - (b and 255)) > 60
        }
        return changed.toDouble() / first.size < .015
    }

    fun signature(file: File): IntArray {
        val bitmap = requireNotNull(BitmapFactory.decodeFile(file.path,
            BitmapFactory.Options().apply { inSampleSize = 8 }))
        try {
            // Ignore status/navigation bars and sticky top/bottom controls when detecting motion.
            val crop = Bitmap.createBitmap(bitmap, bitmap.width / 10, bitmap.height / 6,
                bitmap.width * 8 / 10, bitmap.height * 2 / 3)
            try {
                val small = Bitmap.createScaledBitmap(crop, 48, 80, true)
                try { return IntArray(48 * 80).also { small.getPixels(it, 0, 48, 0, 0, 48, 80) } }
                finally { if (small !== crop) small.recycle() }
            } finally { if (crop !== bitmap) crop.recycle() }
        } finally { bitmap.recycle() }
    }
}

/** Fallback for canvas/WebView pages that expose no scrollable accessibility node. */
internal class ScreenAssistantVisualPageCollector(
    private val context: Context,
    private val read: () -> PhoneUiSnapshot?,
    private val screenshot: (Int) -> File,
    private val gesture: (PhoneUiSnapshot, Boolean, () -> Unit) -> Boolean = ScreenAssistantPageScroll::move,
    private val settleMillis: Long = 550,
    private val suspendChat: () -> Int? = ScreenAssistantPageScroll::suspendChat,
    private val restoreChat: (Int?, PhoneUiSnapshot) -> Unit = ScreenAssistantPageScroll::restoreChat,
    private val extractText: (File) -> List<String> = { file ->
        AgentAndroidMlKitContentOcr(context).recognizeBytes(file.readBytes(), AgentOcrRequest(
            contentUri = "", sourceKind = AgentOcrSourceKind.CAPTURED,
            maxSourceBytes = 8L * 1024 * 1024, timeoutMillis = 5_000,
            scriptHint = AgentOcrScript.CHINESE)).text.lines().map(String::trim).filter(String::isNotBlank)
    }
) {
    fun collect(first: PhoneUiSnapshot, session: ScreenAssistantPageCollection, store: ScreenAssistantPageStore,
        id: String, meta: JSONObject, budget: Long, progress: (Int, Boolean) -> Unit): JSONObject {
        val lockId = "page-capture:$id"
        var image: File? = null
        var bytes = 0L
        var top = false
        var bottom = false
        var movedForward = 0
        var reason = "resource_limit"
        var previousLines = emptyList<String>()
        meta.put("capture_method", "visual_scroll").put("complete", false)
        fun verify(): PhoneUiSnapshot {
            session.checkpoint()
            val current = requireNotNull(read())
            if (!ScreenAssistantPagePolicy.sameTarget(first, current)) throw PageCaptureInterruptedException()
            check(current.nodes.none { it.password || it.editable }) { "Protected or editable surface" }
            return current
        }
        fun capture(): File = PhoneAssistantTaskControl.screenOperation(lockId, { session.request.isCancelled }) {
            verify()
            val file = screenshot(first.windowId)
            try { verify(); file } catch (error: Exception) { file.delete(); throw error }
        }
        fun move(forward: Boolean): Boolean = PhoneAssistantTaskControl.screenOperation(lockId,
            { session.request.isCancelled }) {
            val current = verify()
            session.ownScrollUntil = SystemClock.elapsedRealtime() + 5_000
            try { gesture(current, forward) { verify() } }
            finally { session.ownScrollUntil = SystemClock.elapsedRealtime() + settleMillis + 600 }
        }
        val suspendedTask = suspendChat()
        try {
            image = capture()
            val original = ScreenPageVisualPolicy.signature(image)
            var signature = original
            var unchanged = 0
            for (step in 0 until 200) {
                if (session.finishRequested.get()) { reason = "user_finish"; break }
                progress(0, true)
                if (!move(false)) { reason = "stalled"; break }
                SystemClock.sleep(settleMillis)
                val next = capture()
                val nextSignature = ScreenPageVisualPolicy.signature(next)
                unchanged = if (ScreenPageVisualPolicy.same(signature, nextSignature)) unchanged + 1 else 0
                image?.delete(); image = next; signature = nextSignature
                if (unchanged >= 3) { top = true; break }
            }
            unchanged = 0
            var previous: IntArray? = null
            for (step in 0 until 1000) {
                verify()
                val currentImage = requireNotNull(image)
                val currentSignature = ScreenPageVisualPolicy.signature(currentImage)
                if (previous == null || !ScreenPageVisualPolicy.same(requireNotNull(previous), currentSignature)) {
                    if (bytes + currentImage.length() > budget || context.filesDir.usableSpace < 32L * 1024 * 1024) {
                        reason = "resource_limit"; break
                    }
                    val index = session.pages
                    val target = File(store.directory(id), "$index.jpg")
                    currentImage.copyTo(target, overwrite = true)
                    bytes += target.length()
                    val snapshot = verify()
                    val structured = ScreenAssistantPagePolicy.text(snapshot, null)
                    val ocr = runCatching { extractText(target) }.getOrElse {
                        meta.put("ocr_incomplete", true)
                        emptyList()
                    }
                    verify()
                    val lines = ocr.ifEmpty { structured }
                    val text = ScreenAssistantPagePolicy.append(previousLines, lines).joinToString("\n")
                    previousLines = lines
                    File(store.directory(id), "$index.json").writeText(JSONObject()
                        .put("text", text).put("text_source", if (ocr.isEmpty()) "accessibility" else "ocr")
                        .put("observed_at", snapshot.observedAt).put("visual_only", snapshot.nodes.isEmpty()).toString())
                    bytes += text.toByteArray().size
                    session.pages++
                    previous = currentSignature
                    unchanged = 0
                    store.checkpoint(id, meta.put("pages", session.pages).put("bytes", bytes))
                    progress(session.pages, false)
                } else unchanged++
                if (session.finishRequested.get()) { reason = "user_finish"; break }
                if (unchanged >= 3) { bottom = true; reason = "visual_boundary"; break }
                if (!move(true)) { reason = "stalled"; break }
                movedForward++
                SystemClock.sleep(settleMillis)
                image?.delete(); image = capture()
            }
            // Restore only on a verified visual match, never claim restoration from empty UI text.
            var restored = ScreenPageVisualPolicy.same(original, ScreenPageVisualPolicy.signature(requireNotNull(image)))
            if (!restored && top && bottom && !session.finishRequested.get()) {
                for (step in 0 until movedForward + 3) {
                    if (restored || !move(false)) break
                    SystemClock.sleep(settleMillis)
                    image?.delete(); image = capture()
                    restored = ScreenPageVisualPolicy.same(original, ScreenPageVisualPolicy.signature(requireNotNull(image)))
                }
            }
            // Visual boundaries cannot prove hidden/collapsed content was included.
            return meta.put("reason", reason).put("top_verified", top).put("bottom_reached", bottom)
                .put("visual_traversal_finished", top && bottom && session.pages > 1)
                .put("position_restored", restored).put("bytes", bytes)
        } finally {
            image?.delete()
            restoreChat(suspendedTask, first)
        }
    }
}
