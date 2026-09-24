package com.galaxyssi.watch

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.view.View
import android.view.animation.LinearInterpolator
import android.widget.ImageView

internal class WatchConversationStatusIcon(context: Context, val status: WatchConversationStatus) : ImageView(context) {
    private var spinner: ObjectAnimator? = null

    init {
        contentDescription = context.getString(status.label())
        tag = status
        scaleType = ScaleType.CENTER_INSIDE
        setImageResource(when {
            status.animated -> R.drawable.ic_agent_plan_progress
            status == WatchConversationStatus.COMPLETE_UNREAD -> R.drawable.ic_conversation_complete
            status == WatchConversationStatus.READ -> R.drawable.ic_conversation_read
            status == WatchConversationStatus.WAITING_APPROVAL -> R.drawable.ic_conversation_paused
            status == WatchConversationStatus.FAILED -> R.drawable.ic_conversation_error
            else -> R.drawable.ic_tab_chat
        })
        imageTintList = ColorStateList.valueOf(Color.parseColor(when {
            status.animated -> "#1677FF"
            status == WatchConversationStatus.COMPLETE_UNREAD -> "#12BD76"
            status == WatchConversationStatus.WAITING_APPROVAL -> "#E59100"
            status == WatchConversationStatus.FAILED -> "#E53E46"
            else -> "#A5ABB6"
        }))
    }

    override fun onAttachedToWindow() { super.onAttachedToWindow(); updateAnimation() }
    override fun onDetachedFromWindow() { stopAnimation(); super.onDetachedFromWindow() }
    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        if (isVisible) updateAnimation() else stopAnimation()
    }
    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        if (visibility == View.VISIBLE) updateAnimation() else stopAnimation()
    }
    private fun updateAnimation() {
        if (status.animated && isAttachedToWindow && isShown && windowVisibility == View.VISIBLE &&
            ValueAnimator.areAnimatorsEnabled() && spinner == null) {
            spinner = ObjectAnimator.ofFloat(this, View.ROTATION, 0f, 360f).apply {
                duration = 1200L
                repeatCount = ValueAnimator.INFINITE
                interpolator = LinearInterpolator()
                start()
            }
        }
    }
    private fun stopAnimation() { spinner?.cancel(); spinner = null; rotation = 0f }
}
