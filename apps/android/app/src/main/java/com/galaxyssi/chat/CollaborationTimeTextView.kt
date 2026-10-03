package com.galaxyssi.chat

import android.content.Context
import android.view.View
import androidx.appcompat.widget.AppCompatTextView

/** Only attached, visible labels tick; no transcript reload or storage access occurs here. */
internal class CollaborationTimeTextView(context: Context) : AppCompatTextView(context) {
    private var formatter: ((Long) -> String)? = null
    private var ticking = false
    private var accessibleLabel: ((String) -> String)? = null
    private val tick = object : Runnable {
        override fun run() {
            refresh()
            if (ticking && isAttachedToWindow && windowVisibility == View.VISIBLE && isShown) postDelayed(this, 1_000L)
        }
    }

    fun bindTime(ticking: Boolean = false, accessibility: ((String) -> String)? = null, formatter: (Long) -> String) {
        this.ticking = ticking
        this.formatter = formatter
        accessibleLabel = accessibility
        refresh()
        restart()
    }

    private fun refresh() {
        val value = formatter?.invoke(System.currentTimeMillis()) ?: return
        if (text.toString() != value) text = value
        accessibleLabel?.let { contentDescription = it(value) }
    }

    private fun restart() {
        if (formatter == null) return
        removeCallbacks(tick)
        if (!isAttachedToWindow || windowVisibility != View.VISIBLE || !isShown) return
        refresh()
        if (ticking) postDelayed(tick, 1_000L)
    }

    override fun onAttachedToWindow() { super.onAttachedToWindow(); restart() }
    override fun onDetachedFromWindow() { removeCallbacks(tick); super.onDetachedFromWindow() }
    override fun onWindowVisibilityChanged(visibility: Int) { super.onWindowVisibilityChanged(visibility); restart() }
    override fun onVisibilityAggregated(isVisible: Boolean) { super.onVisibilityAggregated(isVisible); restart() }
}
