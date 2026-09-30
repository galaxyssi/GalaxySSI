package com.galaxyssi.chat

import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import java.util.concurrent.atomic.AtomicReference

/** A document capture owns one physical screen, regardless of how many chat windows are open. */
internal object ScreenAssistantContentCapture {
    private data class Active(val packageName: String, val session: ScreenAssistantPageCollection)
    private val active = AtomicReference<Active?>()

    fun acquire(packageName: String, session: ScreenAssistantPageCollection): Boolean =
        active.compareAndSet(null, Active(packageName, session))

    fun release(session: ScreenAssistantPageCollection) {
        active.get()?.takeIf { it.session === session }?.let { active.compareAndSet(it, null) }
    }

    fun onInteraction(packageName: String, eventType: Int) {
        val current = active.get()?.takeIf { it.packageName == packageName } ?: return
        val session = current.session
        if (eventType == AccessibilityEvent.TYPE_VIEW_CLICKED ||
            eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED ||
            eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED && SystemClock.elapsedRealtime() > session.ownScrollUntil) {
            session.interrupted = true
        }
    }
}
