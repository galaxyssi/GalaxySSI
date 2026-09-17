package com.galaxyssi.watch

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.*
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import android.view.accessibility.AccessibilityManager
import java.io.FileDescriptor
import java.io.PrintWriter

/** Only confirms a Samsung speech window opened by this app in this process. */
class WatchSamsungConfirmService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private val gate = WatchConfirmGate()
    private var enteredSamsung = false
    private var connected = false
    private var status = "idle"
    private var lastEvent = 0
    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { cancel("screen-off") }
    }
    private val poll = object : Runnable {
        override fun run() {
            if (!connected || !gate.active(SystemClock.elapsedRealtime())) { cancel("expired-or-disconnected"); return }
            if (!(application as WatchApplication).repository.store.samsungAutoConfirm || !enabled(this@WatchSamsungConfirmService)) {
                cancel("disabled"); return
            }
            runCatching { inspect() }.onFailure { cancel("inspection-error:${it.javaClass.simpleName}") }
            if (gate.active(SystemClock.elapsedRealtime())) handler.postDelayed(this, 200)
        }
    }
    override fun onServiceConnected() {
        current = this
        connected = true
        registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF), RECEIVER_NOT_EXPORTED)
    }
    private fun arm() {
        cancel("new-session"); gate.arm(SystemClock.elapsedRealtime()); status = "armed"; handler.post(poll)
    }
    private fun cancel(reason: String = "cancelled") { gate.cancel(); enteredSamsung = false; handler.removeCallbacks(poll); status = reason }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (!gate.active(SystemClock.elapsedRealtime())) return
        lastEvent = event?.eventType ?: 0
        when (event?.eventType) {
            AccessibilityEvent.TYPE_VIEW_CLICKED, AccessibilityEvent.TYPE_VIEW_LONG_CLICKED,
            AccessibilityEvent.TYPE_TOUCH_INTERACTION_START -> if (gate.hasCandidate) cancel("interaction:$lastEvent")
            // Samsung scrolls the result view itself as recognition updates; restart stability
            // instead of treating these programmatic events as a user cancellation.
            AccessibilityEvent.TYPE_VIEW_SCROLLED, AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> gate.reset()
        }
    }
    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN) cancel("key")
        return false
    }
    override fun onInterrupt() { cancel() }
    override fun onUnbind(intent: Intent?): Boolean {
        connected = false; cancel("unbound"); if (current === this) current = null
        return super.onUnbind(intent)
    }
    override fun dump(fd: FileDescriptor, writer: PrintWriter, args: Array<out String>?) {
        writer.println("SamsungConfirm connected=$connected active=${gate.active(SystemClock.elapsedRealtime())} state=$status lastEvent=$lastEvent")
    }
    override fun onDestroy() {
        connected = false; cancel(); if (current === this) current = null
        runCatching { unregisterReceiver(screenOff) }; super.onDestroy()
    }
    private fun inspect() {
        val now = SystemClock.elapsedRealtime()
        val allWindows = windows
        val activeRoot = allWindows.firstOrNull { it.type == AccessibilityWindowInfo.TYPE_APPLICATION && it.isFocused }?.root
        if (activeRoot == null) { gate.reset(); status = "waiting-app-window"; return }
        try {
            if (activeRoot.packageName?.toString() != WatchSpeechInput.SAMSUNG_PACKAGE) {
                if (enteredSamsung) cancel("left-samsung") else { gate.reset(); status = "waiting-samsung" }
                return
            }
            // Samsung's IME is also used by other apps. Require its speech activity shell.
            if (!hasNode(activeRoot, "remote_input_recycler_view")) { gate.reset(); status = "waiting-remote-shell"; return }
            enteredSamsung = true
            val candidates = allWindows.filter { it.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD }
            for (window in candidates) {
                val root = window.root ?: continue
                try {
                    if (root.packageName?.toString() != WatchSpeechInput.SAMSUNG_PACKAGE) continue
                    val text = readNode(root, "result_edit_text") { if (it.isVisibleToUser) it.text?.toString()?.trim() else null }
                    val micOff = readNode(root, "static_view") {
                        it.isVisibleToUser && it.contentDescription?.toString()?.lowercase() in setOf("麦克风关闭", "microphone off")
                    } == true
                    val button = root.findAccessibilityNodeInfosByViewId(id("action_button"))
                    try {
                        val confirm = button.singleOrNull()?.takeIf {
                            it.isVisibleToUser && it.isEnabled && it.isClickable &&
                                it.contentDescription?.toString()?.lowercase() in setOf("完成", "done")
                        }
                        val key = if (!text.isNullOrBlank() && micOff && confirm != null)
                            "${activeRoot.windowId}:${window.id}:$text" else null
                        status = "result=${!text.isNullOrBlank()} micOff=$micOff button=${confirm != null}"
                        if (gate.ready(key, now) && confirm != null) {
                            // Disarm before ACTION_CLICK so callbacks cannot trigger a second action.
                            cancel("consumed")
                            status = "clicked=${confirm.performAction(AccessibilityNodeInfo.ACTION_CLICK)}"
                        }
                        return
                    } finally { button.forEach { it.recycle() } }
                } finally { root.recycle() }
            }
            gate.reset(); status = "waiting-ime"
        } finally { activeRoot.recycle() }
    }
    private fun id(name: String) = "${WatchSpeechInput.SAMSUNG_PACKAGE}:id/$name"
    private fun hasNode(root: AccessibilityNodeInfo, name: String) = readNode(root, name) { it.isVisibleToUser } == true
    private fun <T> readNode(root: AccessibilityNodeInfo, name: String, read: (AccessibilityNodeInfo) -> T): T? {
        val nodes = root.findAccessibilityNodeInfosByViewId(id(name))
        return try { nodes.singleOrNull()?.let(read) } finally { nodes.forEach { it.recycle() } }
    }
    companion object {
        private var current: WatchSamsungConfirmService? = null
        fun startSession(context: Context) {
            val enabled = (context.applicationContext as WatchApplication).repository.store.samsungAutoConfirm
            if (enabled && enabled(context)) current?.takeIf { it.connected }?.arm()
        }
        fun cancelSession() { current?.cancel() }
        fun enabled(context: Context): Boolean = context.getSystemService(AccessibilityManager::class.java)
            .getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { it.resolveInfo.serviceInfo.packageName == context.packageName &&
                it.resolveInfo.serviceInfo.name == WatchSamsungConfirmService::class.java.name }
    }
}
