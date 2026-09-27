package com.galaxyssi.chat

import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

internal class ScreenAssistantPageCollection(val request: ScreenAssistantAnalysisRequest) {
    val finishRequested = AtomicBoolean(false)
    @Volatile var pages = 0
    @Volatile var interrupted = false
    @Volatile var ownScrollUntil = 0L
    fun checkpoint() {
        request.awaitRunnable()
        if (interrupted) throw PageCaptureInterruptedException()
    }
    fun finish() { finishRequested.set(true); request.setPaused(false) }
}

internal class PageCaptureInterruptedException : IllegalStateException("Target page changed")

internal object ScreenAssistantPagePolicy {
    fun scrollNode(snapshot: PhoneUiSnapshot): PhoneUiNode? = snapshot.nodes
        .filter { it.scrollable && it.enabled && !it.password }
        .maxByOrNull { bounds(it.bounds)?.let { b -> (b[2] - b[0]).toLong() * (b[3] - b[1]) } ?: 0L }

    fun text(snapshot: PhoneUiSnapshot, scroll: PhoneUiNode?): List<String> = snapshot.nodes
        .filter { node -> !node.password && !node.editable && (scroll == null ||
            node.path.startsWith(scroll.path + "/") && intersects(node.bounds, scroll.bounds)) }
        .flatMap { node -> listOf(node.text, node.description.takeIf { it != node.text }.orEmpty()) }
        .map(String::trim).filter(String::isNotBlank)

    // Remove only a contiguous viewport overlap, not every repeated sentence in the article.
    fun append(previous: List<String>, current: List<String>): List<String> {
        val overlap = (minOf(previous.size, current.size) downTo 1).firstOrNull { count ->
            previous.takeLast(count) == current.take(count)
        } ?: 0
        return current.drop(overlap)
    }

    fun fingerprint(lines: List<String>): String = MessageDigest.getInstance("SHA-256")
        .digest(lines.joinToString("\n").toByteArray()).joinToString("") { "%02x".format(it) }

    fun sameTarget(first: PhoneUiSnapshot, next: PhoneUiSnapshot): Boolean =
        first.windowId == next.windowId && first.packageName == next.packageName &&
            address(first) == address(next)

    fun escape(value: String): String = value.replace("&", "&amp;").replace("<", "&lt;")
        .replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;")

    private fun address(snapshot: PhoneUiSnapshot) = snapshot.nodes.firstOrNull {
        it.viewId.endsWith("/url_bar") || it.viewId.endsWith("/location_bar_edit_text")
    }?.text.orEmpty()

    private fun bounds(value: String): List<Int>? = value.split(',').mapNotNull(String::toIntOrNull)
        .takeIf { it.size == 4 && it[2] > it[0] && it[3] > it[1] }

    private fun intersects(a: String, b: String): Boolean {
        val x = bounds(a) ?: return false
        val y = bounds(b) ?: return false
        return x[0] < y[2] && x[2] > y[0] && x[1] < y[3] && x[3] > y[1]
    }
}
