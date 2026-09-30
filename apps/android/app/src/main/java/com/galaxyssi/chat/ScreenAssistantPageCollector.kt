package com.galaxyssi.chat

import android.content.Context
import android.os.SystemClock
import org.json.JSONObject
import java.io.File

internal class ScreenAssistantPageCollector(
    private val context: Context,
    private val read: () -> PhoneUiSnapshot? = { GalaxySSIAccessibilityService.readTargetUi() },
    private val scroll: (PhoneUiSnapshot, PhoneUiNode, Boolean) -> Boolean = { snapshot, node, forward ->
        GalaxySSIAccessibilityService.actOnTargetUi(snapshot.windowId, snapshot.revision, node.path,
            if (forward) "scroll_forward" else "scroll_backward", "")["accepted"] == true
    },
    private val screenshot: (Int) -> File = { PhoneUiScreenshot.capture(context, it) }
) {
    fun collect(session: ScreenAssistantPageCollection, renderHtml: Boolean = true,
        maxBytes: Long = 128L * 1024 * 1024, progress: (Int, Boolean) -> Unit): String {
        val store = ScreenAssistantPageStore(context)
        val id = store.create()
        val request = session.request
        val lockId = "page-capture:$id"
        PhoneAssistantTaskControl.bind(lockId, request)
        var metadata = JSONObject().put("id", id).put("pages", 0).put("complete", false)
            .put("reason", "capturing").put("created_at", System.currentTimeMillis())
        store.checkpoint(id, metadata)
        try {
            val first = requireNotNull(read()) { "No target application" }
            metadata.put("package_name", first.packageName)
            if (ScreenAssistantPagePolicy.scrollNode(first) == null) {
                metadata = ScreenAssistantVisualPageCollector(context, read, screenshot).collect(first, session,
                    store, id, metadata, minOf(maxBytes, context.filesDir.usableSpace / 10), progress)
            } else {
            val original = ScreenAssistantPagePolicy.fingerprint(ScreenAssistantPagePolicy.text(first, ScreenAssistantPagePolicy.scrollNode(first)))
            val budget = minOf(maxBytes.coerceAtLeast(1), (context.filesDir.usableSpace / 10).coerceAtLeast(0))
            var bytes = 0L
            var reason = "bottom"
            var topReached = false
            var snapshot = first
            var repositionSteps = 0
            var unchanged = 0
            while (!session.finishRequested.get()) {
                session.checkpoint()
                progress(0, true)
                val node = ScreenAssistantPagePolicy.scrollNode(snapshot) ?: break
                val before = contentKey(snapshot)
                val accepted = move(first, node, false, lockId, session)
                repositionSteps++
                snapshot = stable(first, session)
                if (!accepted) { topReached = true; break }
                unchanged = if (contentKey(snapshot) == before) unchanged + 1 else 0
                if (unchanged >= 3) { break }
                if (repositionSteps >= 1000) { reason = "resource_limit"; break }
            }
            if (ScreenAssistantPagePolicy.scrollNode(first) == null) reason = "no_scroll"
            var previous = emptyList<String>()
            var duplicate = 0
            var lastKey = ""
            var steps = 0
            while (true) {
                session.checkpoint()
                snapshot = stable(first, session)
                val lines = ScreenAssistantPagePolicy.text(snapshot, ScreenAssistantPagePolicy.scrollNode(snapshot))
                val image = if (snapshot.nodes.none { it.password }) runCatching {
                    PhoneAssistantTaskControl.screenOperation(lockId, { request.isCancelled }) {
                        if (session.interrupted) throw PageCaptureInterruptedException()
                        verify(first, requireNotNull(read()))
                        val file = screenshot(first.windowId)
                        try { verify(first, requireNotNull(read())); file } catch (failure: Exception) {
                            file.delete(); throw failure
                        }
                    }
                }.getOrNull() else null
                // Canvas/image-only pages still need visual change detection.
                val imageDigest = image?.inputStream()?.use { input ->
                    val digest = java.security.MessageDigest.getInstance("SHA-256")
                    val buffer = ByteArray(32 * 1024)
                    while (true) { val size = input.read(buffer); if (size < 0) break; digest.update(buffer, 0, size) }
                    digest.digest().joinToString("") { "%02x".format(it) }
                }.orEmpty()
                val key = ScreenAssistantPagePolicy.fingerprint(lines) + imageDigest
                val changed = key != lastKey
                if (changed) {
                    val index = session.pages
                    val text = ScreenAssistantPagePolicy.append(previous, lines).joinToString("\n")
                    val data = JSONObject().put("text", text).put("structure_truncated", snapshot.truncated)
                        .put("observed_at", snapshot.observedAt).put("revision", snapshot.revision)
                    image?.let { source ->
                        val target = File(store.directory(id), "$index.jpg")
                        check(source.renameTo(target) || run { source.copyTo(target); source.delete(); true })
                        bytes += target.length()
                    }
                    if (image == null) metadata.put("screenshots_incomplete", true)
                    File(store.directory(id), "$index.json").writeText(data.toString())
                    bytes += data.toString().toByteArray().size
                    if (snapshot.truncated) metadata.put("structure_truncated", true)
                    session.pages++
                    store.checkpoint(id, metadata.put("pages", session.pages).put("bytes", bytes))
                    previous = lines
                    lastKey = key
                    duplicate = 0
                    progress(session.pages, false)
                } else { duplicate++; image?.delete() }
                if (session.finishRequested.get()) { reason = "user_finish"; break }
                if (session.interrupted) { reason = "target_changed"; break }
                if (reason == "resource_limit" || bytes >= budget || context.filesDir.usableSpace < 32L * 1024 * 1024 || steps >= 1000) {
                    reason = "resource_limit"; break
                }
                val node = ScreenAssistantPagePolicy.scrollNode(snapshot) ?: break
                if (duplicate >= 3) { reason = "stalled"; break }
                if (!move(first, node, true, lockId, session)) { reason = "bottom"; break }
                steps++
            }
            var restored = false
            if (!session.interrupted && !request.isCancelled && reason in setOf("bottom", "no_scroll", "user_finish")) {
                repeat(steps + repositionSteps + 1) {
                    if (!restored) {
                        session.checkpoint()
                        snapshot = stable(first, session)
                        if (contentKey(snapshot) == original) restored = true
                        else ScreenAssistantPagePolicy.scrollNode(snapshot)?.let { move(first, it, false, lockId, session) }
                    }
                }
            }
            val complete = reason == "bottom" && topReached &&
                steps > 0 &&
                !metadata.optBoolean("structure_truncated") && !metadata.optBoolean("screenshots_incomplete")
            metadata.put("bottom_reached", reason == "bottom").put("top_verified", topReached)
            if (reason == "bottom" && !complete) reason = if (steps == 0) "no_scroll" else "coverage_incomplete"
            metadata.put("reason", reason).put("complete", complete).put("position_restored", restored)
            }
        } catch (failure: Exception) {
            android.util.Log.w("ScreenPageCapture", "Page capture stopped (${failure.javaClass.simpleName})", failure)
            metadata.put("reason", when {
                request.isCancelled -> "cancelled"
                failure is PageCaptureInterruptedException -> "target_changed"
                else -> "stalled"
            }).put("complete", false)
        } finally {
            // Removing the temporary binding must not cancel the request before model submission.
            PhoneAssistantTaskControl.release(lockId, request)
            store.checkpoint(id, metadata.put("pages", session.pages).put("finished_at", System.currentTimeMillis()))
        }
        if (!request.isCancelled) {
            if (renderHtml) store.buildHtml(id) else store.buildText(id)
        }
        return id
    }
    private fun contentKey(snapshot: PhoneUiSnapshot) = ScreenAssistantPagePolicy.fingerprint(
        ScreenAssistantPagePolicy.text(snapshot, ScreenAssistantPagePolicy.scrollNode(snapshot)))
    private fun verify(first: PhoneUiSnapshot, next: PhoneUiSnapshot) {
        if (!ScreenAssistantPagePolicy.sameTarget(first, next)) throw PageCaptureInterruptedException()
    }
    private fun stable(first: PhoneUiSnapshot, session: ScreenAssistantPageCollection): PhoneUiSnapshot {
        session.checkpoint()
        var last = requireNotNull(read())
        verify(first, last)
        repeat(8) {
            SystemClock.sleep(120)
            session.checkpoint()
            val next = requireNotNull(read())
            verify(first, next)
            if (contentKey(next) == contentKey(last)) return next
            last = next
        }
        return last
    }
    private fun move(first: PhoneUiSnapshot, node: PhoneUiNode, forward: Boolean,
        lockId: String, session: ScreenAssistantPageCollection): Boolean = PhoneAssistantTaskControl.screenOperation(lockId,
            { session.request.isCancelled }) {
        if (session.interrupted) throw PageCaptureInterruptedException()
        val current = requireNotNull(read())
        verify(first, current)
        // Re-read stale dynamic pages; never use a coordinate fallback.
        val actual = current.nodes.firstOrNull { it.path == node.path && it.className == node.className && it.scrollable }
            ?: throw PageCaptureInterruptedException()
        session.ownScrollUntil = SystemClock.elapsedRealtime() + 2_000L
        try { scroll(current, actual, forward) }
        finally { session.ownScrollUntil = SystemClock.elapsedRealtime() + 600L }
    }
}
