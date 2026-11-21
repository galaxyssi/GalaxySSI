package com.galaxyssi.chat

import android.animation.ValueAnimator
import android.app.Activity
import android.view.animation.LinearInterpolator
import kotlin.math.roundToLong

internal class HealthAtlasTeachingPlayback(
    activity: Activity,
    private val playLabel: Int,
    private val pauseLabel: Int,
    private val render: (Float) -> Unit,
) {
    private var length = 0L
    private var phase = 1f
    private var animator: ValueAnimator? = null
    val button = HealthCenterViews(activity).icon(R.drawable.ic_rich_play, playLabel) {
        if (animator == null) start() else pause()
    }

    fun showTarget(durationMs: Long) {
        pause()
        length = durationMs
        button.isEnabled = length > 0 && ValueAnimator.areAnimatorsEnabled()
        button.alpha = if (button.isEnabled) 1f else .4f
        show(1f)
    }

    fun pause() {
        animator?.removeAllUpdateListeners()
        animator?.cancel()
        animator = null
        setPlaying(false)
    }

    fun seek(position: Float) {
        pause()
        show(position.coerceIn(0f, 1f))
    }

    private fun start() {
        if (!button.isEnabled || !ValueAnimator.areAnimatorsEnabled()) return
        if (phase >= 1f) show(0f)
        setPlaying(true)
        val player = ValueAnimator.ofFloat(phase, 1f).apply {
            duration = (length * (1.0 - phase)).roundToLong().coerceAtLeast(1L)
            interpolator = LinearInterpolator()
            addUpdateListener {
                show(it.animatedValue as Float)
                if (phase >= 1f) pause()
            }
        }
        animator = player
        player.start()
    }

    private fun show(position: Float) {
        phase = position
        render(position)
    }

    private fun setPlaying(playing: Boolean) {
        button.setImageResource(if (playing) R.drawable.ic_rich_pause else R.drawable.ic_rich_play)
        button.contentDescription = button.context.getString(if (playing) pauseLabel else playLabel)
        button.tooltipText = button.contentDescription
    }
}
