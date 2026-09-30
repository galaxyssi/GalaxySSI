package com.galaxyssi.chat

import android.os.Handler
import android.os.Looper
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Only vertical reading gestures, against the same observed external window. */
internal object ScreenAssistantPageScroll {
    fun suspendChat(): Int? {
        check(Looper.myLooper() != Looper.getMainLooper())
        val task = java.util.concurrent.atomic.AtomicReference<Int?>()
        val done = CountDownLatch(1)
        Handler(Looper.getMainLooper()).post {
            try { task.set(ScreenAssistantChatActivity.suspendForPageReading()) }
            finally { done.countDown() }
        }
        check(done.await(3, TimeUnit.SECONDS)) { "Could not release the article window" }
        if (task.get() != null) {
            val deadline = android.os.SystemClock.elapsedRealtime() + 3_000
            while (ScreenAssistantChatActivity.isOpen() && android.os.SystemClock.elapsedRealtime() < deadline)
                android.os.SystemClock.sleep(50)
            check(!ScreenAssistantChatActivity.isOpen()) { "Article window is still covered" }
            android.os.SystemClock.sleep(250)
        }
        return task.get()
    }

    fun restoreChat(taskId: Int?, expected: PhoneUiSnapshot) {
        if (taskId == null) return
        val current = GalaxySSIAccessibilityService.readTargetUi() ?: return
        if (!ScreenAssistantPagePolicy.sameTarget(expected, current)) return
        Handler(Looper.getMainLooper()).post { ScreenAssistantChatActivity.restoreAfterPageReading(taskId) }
    }

    fun move(expected: PhoneUiSnapshot, forward: Boolean, checkpoint: () -> Unit): Boolean {
        check(Looper.myLooper() != Looper.getMainLooper())
        require(PhoneUiObservationPolicy.canMutatePackage(expected.packageName))
        val service = requireNotNull(GalaxySSIAccessibilityService.targetService())
        val main = Handler(Looper.getMainLooper())
        val ready = CountDownLatch(1)
        val active = AtomicBoolean(true)
        main.post {
            if (active.get()) {
                service.captureWithoutAssistant {}
                // The Activity is backgrounded: a render-frame callback may not be delivered.
                // Hiding is synchronous; allow the input-window update to reach the compositor.
                main.postDelayed({ if (active.get()) ready.countDown() }, 100)
            }
        }
        try {
            check(ready.await(3, TimeUnit.SECONDS)) { "Could not expose the reading surface" }
            check(!ScreenAssistantChatActivity.isOpen()) { "Reading interrupted by assistant interaction" }
            checkpoint()
            val current = requireNotNull(GalaxySSIAccessibilityService.readTargetUi())
            check(ScreenAssistantPagePolicy.sameTarget(expected, current)) { "Target window changed" }
            check(current.nodes.none { it.password || it.editable }) { "Not a read-only document surface" }
            val bounds = requireNotNull(GalaxySSIAccessibilityService.targetWindowBounds(expected.windowId))
            require(bounds.width() > 100 && bounds.height() > 200)
            val x = bounds.centerX()
            val top = bounds.top + (bounds.height() * .28f).toInt()
            val bottom = bounds.top + (bounds.height() * .76f).toInt()
            return GalaxySSIAccessibilityService.performReadingSwipe(x, if (forward) bottom else top,
                x, if (forward) top else bottom)
        } finally {
            active.set(false)
            val restored = CountDownLatch(1)
            main.post {
                service.restoreAssistantAfterCapture()
                restored.countDown()
            }
            restored.await(3, TimeUnit.SECONDS)
        }
    }
}
