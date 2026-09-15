package com.galaxyssi.watch

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Window
import android.view.WindowManager

internal class WatchScreenAwakePolicy {
    private var wasWorking = false
    private var releaseAt = 0L
    fun remaining(now: Long, foreground: Boolean, working: Boolean): Long {
        if (!foreground) { wasWorking = false; releaseAt = 0; return 0 }
        if (working) { wasWorking = true; releaseAt = 0; return Long.MAX_VALUE }
        if (wasWorking) { wasWorking = false; releaseAt = now + 30_000 }
        return (releaseAt - now).coerceAtLeast(0)
    }
}

/** Hold only this foreground window; never change the watch's global screen timeout. */
internal class WatchScreenAwake(private val window: Window) {
    private val handler = Handler(Looper.getMainLooper())
    private val policy = WatchScreenAwakePolicy()
    private var foreground = false
    private var working = false
    private val expire = Runnable { applyState() }
    fun update(foreground: Boolean, working: Boolean) {
        this.foreground = foreground; this.working = working; applyState()
    }
    private fun applyState() {
        handler.removeCallbacks(expire)
        val remaining = policy.remaining(SystemClock.elapsedRealtime(), foreground, working)
        if (remaining > 0) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (remaining in 1 until Long.MAX_VALUE) handler.postDelayed(expire, remaining)
    }
}
