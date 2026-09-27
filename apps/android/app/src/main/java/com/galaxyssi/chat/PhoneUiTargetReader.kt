package com.galaxyssi.chat

import android.graphics.Rect
import android.os.Bundle
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import java.security.MessageDigest

internal data class PhoneUiNode(
    val path: String, val text: String, val description: String, val viewId: String,
    val className: String, val bounds: String, val clickable: Boolean, val longClickable: Boolean,
    val editable: Boolean, val scrollable: Boolean, val enabled: Boolean,
    val checked: Boolean?, val password: Boolean, val textTruncated: Boolean = false
) {
    fun json(): Map<String, Any?> = linkedMapOf(
        "node_path" to path, "text" to text, "description" to description, "view_id" to viewId,
        "class_name" to className, "bounds" to bounds, "clickable" to clickable,
        "long_clickable" to longClickable, "editable" to editable, "scrollable" to scrollable,
        "enabled" to enabled, "checked" to checked, "password" to password,
        "text_truncated" to textTruncated
    )
}

internal data class PhoneUiSnapshot(
    val windowId: Int, val packageName: String, val revision: String,
    val nodes: List<PhoneUiNode>, val truncated: Boolean,
    val observedAt: Long = System.currentTimeMillis()
) {
    fun frame(): Map<String, Any?> = linkedMapOf(
        "window_id" to windowId, "package_name" to packageName, "revision" to revision
    )

    fun page(offset: Int = 0, limit: Int = 80): Map<String, Any?> {
        val start = offset.coerceAtLeast(0).coerceAtMost(nodes.size)
        val end = (start + limit.coerceIn(1, 100)).coerceAtMost(nodes.size)
        return linkedMapOf(
            // The codec sorts keys; keep action preconditions ahead of a truncated node page.
            "_frame" to frame(),
            "window_id" to windowId, "package_name" to packageName, "revision" to revision,
            "observed_at_epoch_ms" to observedAt, "total_nodes" to nodes.size,
            "truncated" to truncated, "nodes" to nodes.subList(start, end).map(PhoneUiNode::json),
            "next_offset" to end.takeIf { it < nodes.size },
            "source" to "accessibility_target_window"
        )
    }
}

/** Never selects an accessibility overlay or the IME as the application being observed. */
internal class PhoneUiTargetReader(private val service: GalaxySSIAccessibilityService) {
    fun targetWindow(externalOnly: Boolean): AccessibilityWindowInfo? {
        val windows = service.windows
        val candidates = windows.map { window ->
            PhoneUiWindowCandidate(window.id, window.root?.packageName?.toString().orEmpty(),
                window.type == AccessibilityWindowInfo.TYPE_APPLICATION,
                window.isFocused, window.isActive, window.layer)
        }
        val id = PhoneUiObservationPolicy.select(candidates, service.packageName, externalOnly) ?: return null
        return windows.firstOrNull { it.id == id }
    }

    fun snapshot(externalOnly: Boolean = true): PhoneUiSnapshot? {
        val window = targetWindow(externalOnly) ?: return null
        val root = window.root ?: return null
        val nodes = mutableListOf<PhoneUiNode>()
        var visited = 0
        var truncated = false
        val stack = java.util.ArrayDeque<Pair<AccessibilityNodeInfo, String>>()
        stack.add(root to "0")
        while (stack.isNotEmpty() && visited < 5_000) {
            val (node, path) = stack.removeLast()
            visited++
            val bounds = Rect().also(node::getBoundsInScreen)
            if (node.isVisibleToUser && !bounds.isEmpty) nodes += describe(node, path)
            if (path.count { it == '/' } >= 100) { truncated = true; continue }
            val children = node.childCount.coerceAtMost(5_000 - visited - stack.size)
            if (children < node.childCount) truncated = true
            for (index in children - 1 downTo 0) node.getChild(index)?.let { stack.add(it to "$path/$index") }
        }
        if (stack.isNotEmpty() || nodes.any { it.textTruncated }) truncated = true
        val digest = MessageDigest.getInstance("SHA-256").digest(
            (window.id.toString() + root.packageName + nodes.joinToString("\n")).toByteArray(Charsets.UTF_8)
        ).joinToString("") { "%02x".format(it) }
        return PhoneUiSnapshot(window.id, root.packageName?.toString().orEmpty(), digest, nodes, truncated)
    }

    fun act(windowId: Int, revision: String, path: String, operation: String, text: String): Map<String, Any?> {
        val before = snapshot() ?: error("No external application window is available")
        require(PhoneUiObservationPolicy.canMutatePackage(before.packageName)) {
            "System security and permission dialogs must be operated by the user"
        }
        require(PhoneUiObservationPolicy.accepts(windowId, revision, before.windowId, before.revision)) {
            "The page changed. Read the target window again before acting."
        }
        val expected = before.nodes.singleOrNull { it.path == path } ?: error("The target node is unavailable")
        require(expected.enabled && !expected.password) { "The target is disabled or is a protected password field" }
        val root = targetWindow(true)?.takeIf { it.id == windowId }?.root ?: error("Target window changed")
        var node = root
        val parts = path.split('/')
        require(parts.firstOrNull() == "0") { "Invalid node path" }
        for (part in parts.drop(1)) node = node.getChild(part.toInt()) ?: error("Target node changed")
        val actual = describe(node, path)
        require(actual == expected && node.isVisibleToUser) {
            val changed = expected.json().keys.filter { expected.json()[it] != actual.json()[it] }
            "Target node changed after observation (${changed.joinToString(",")}); inspect again"
        }
        require(when (operation) {
            "click" -> node.isClickable
            "long_click" -> node.isLongClickable
            "set_text" -> node.isEditable
            "scroll_forward", "scroll_backward" -> node.isScrollable
            else -> false
        }) { "The target does not support this operation" }
        val action = when (operation) {
            "click" -> AccessibilityNodeInfo.ACTION_CLICK
            "long_click" -> AccessibilityNodeInfo.ACTION_LONG_CLICK
            "set_text" -> AccessibilityNodeInfo.ACTION_SET_TEXT
            "scroll_forward" -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            "scroll_backward" -> AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            else -> error("Unsupported UI operation")
        }
        val args = if (operation == "set_text") Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        } else null
        val accepted = node.performAction(action, args)
        val deadline = SystemClock.elapsedRealtime() + 1_500L
        var after: PhoneUiSnapshot? = before
        while (accepted && SystemClock.elapsedRealtime() < deadline) {
            SystemClock.sleep(80L)
            after = snapshot()
            if (after == null || after.revision != before.revision) break
        }
        return linkedMapOf("_frame" to after?.frame(),
            "accepted" to accepted, "ui_changed" to (after?.revision != before.revision),
            "business_success_verified" to false,
            "observation" to after?.page(), "instruction" to "Verify the requested outcome from a fresh observation; acceptance alone is not task completion.")
    }

    private fun describe(node: AccessibilityNodeInfo, path: String): PhoneUiNode {
        val bounds = Rect().also(node::getBoundsInScreen)
        val secret = node.isPassword
        return PhoneUiNode(path,
            if (secret) "[password]" else node.text?.toString().orEmpty().take(1_000),
            if (secret) "" else node.contentDescription?.toString().orEmpty().take(500),
            node.viewIdResourceName.orEmpty(), node.className?.toString().orEmpty(),
            "${bounds.left},${bounds.top},${bounds.right},${bounds.bottom}",
            node.isClickable, node.isLongClickable, node.isEditable, node.isScrollable,
            node.isEnabled, node.isChecked.takeIf { node.isCheckable }, secret,
            !secret && (node.text?.length ?: 0) > 1_000 || !secret && (node.contentDescription?.length ?: 0) > 500)
    }
}
