package com.galaxyssi.chat

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.view.View
import android.view.animation.LinearInterpolator
import android.widget.ImageView

internal class ConversationHubStatusIcon(context: Context, val status: ConversationHubAgentStatus) :
    androidx.appcompat.widget.AppCompatImageView(context) {
    private var spinner: ObjectAnimator? = null

    init {
        tag = status
        contentDescription = context.getString(status.labelRes())
        scaleType = ImageView.ScaleType.CENTER_INSIDE
        setImageResource(when {
            status.animated -> R.drawable.ic_agent_plan_progress
            status == ConversationHubAgentStatus.COMPLETE_UNREAD -> R.drawable.ic_conversation_complete
            status == ConversationHubAgentStatus.READ -> R.drawable.ic_conversation_read
            status in setOf(ConversationHubAgentStatus.WAITING_CONFIRMATION, ConversationHubAgentStatus.PAUSED) -> R.drawable.ic_conversation_paused
            status in setOf(ConversationHubAgentStatus.FAILED, ConversationHubAgentStatus.BLOCKED) -> R.drawable.ic_conversation_error
            else -> R.drawable.ic_tab_chat
        })
        imageTintList = ColorStateList.valueOf(Color.parseColor(status.foregroundColor()))
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

internal fun ConversationHubAgentStatus.foregroundColor(): String = when {
    animated -> "#1677FF"
    this == ConversationHubAgentStatus.COMPLETE_UNREAD -> "#12BD76"
    this in setOf(ConversationHubAgentStatus.WAITING_CONFIRMATION, ConversationHubAgentStatus.PAUSED) -> "#E59100"
    this in setOf(ConversationHubAgentStatus.FAILED, ConversationHubAgentStatus.BLOCKED) -> "#E53E46"
    else -> "#74777D"
}

internal fun ConversationHubAgentStatus.backgroundColor(): String = when {
    animated -> "#EAF3FF"
    this == ConversationHubAgentStatus.COMPLETE_UNREAD -> "#ECF9F2"
    this in setOf(ConversationHubAgentStatus.WAITING_CONFIRMATION, ConversationHubAgentStatus.PAUSED) -> "#FFF5E2"
    this in setOf(ConversationHubAgentStatus.FAILED, ConversationHubAgentStatus.BLOCKED) -> "#FDECEE"
    else -> "#EFF0F3"
}
