package com.signalasi.chat

import android.animation.ValueAnimator
import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.animation.LinearInterpolator
import android.widget.LinearLayout
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.DrawableCompat
import kotlin.math.PI
import kotlin.math.sin

internal class AgentVoiceTranscriptionPendingView(
    context: Context,
    bubbleBackground: Boolean = true,
    accessibilityText: CharSequence = context.getString(R.string.voice_status_recognizing),
    dotColorRes: Int = R.color.agent_voice_transcript_dot
) : LinearLayout(context) {
    private val dots = List(DOT_COUNT) { createDot(dotColorRes) }
    private var pulseAnimator: ValueAnimator? = null

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER
        minimumWidth = dp(if (bubbleBackground) 96 else 48)
        minimumHeight = dp(if (bubbleBackground) 44 else 32)
        if (bubbleBackground) {
            setPadding(dp(15), dp(10), dp(15), dp(10))
            setBackgroundResource(R.drawable.bubble_agent_user_background)
        } else {
            setPadding(dp(2), dp(7), dp(2), dp(7))
            background = null
        }
        contentDescription = accessibilityText
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        dots.forEachIndexed { index, dot ->
            addView(dot, LayoutParams(dp(7), dp(7)).apply {
                if (index > 0) marginStart = dp(6)
            })
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        startPulse()
    }

    override fun onDetachedFromWindow() {
        pulseAnimator?.cancel()
        pulseAnimator = null
        super.onDetachedFromWindow()
    }

    private fun createDot(dotColorRes: Int): View = View(context).apply {
        background = ContextCompat.getDrawable(context, R.drawable.agent_voice_transcription_dot)
            ?.mutate()
            ?.also { drawable ->
                DrawableCompat.setTint(drawable, ContextCompat.getColor(context, dotColorRes))
            }
        alpha = MIN_ALPHA
    }

    private fun startPulse() {
        if (pulseAnimator?.isRunning == true) return
        pulseAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = PULSE_DURATION_MS
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener { animator ->
                val progress = animator.animatedFraction
                dots.forEachIndexed { index, dot ->
                    val wave = ((sin(progress * TWO_PI - index * PHASE_OFFSET) + 1.0) / 2.0).toFloat()
                    dot.alpha = MIN_ALPHA + (MAX_ALPHA - MIN_ALPHA) * wave
                    val scale = MIN_SCALE + (MAX_SCALE - MIN_SCALE) * wave
                    dot.scaleX = scale
                    dot.scaleY = scale
                }
            }
            start()
        }
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density + 0.5f).toInt()

    private companion object {
        const val DOT_COUNT = 3
        const val PULSE_DURATION_MS = 900L
        const val MIN_ALPHA = 0.32f
        const val MAX_ALPHA = 1f
        const val MIN_SCALE = 0.82f
        const val MAX_SCALE = 1f
        const val TWO_PI = 2.0 * PI
        const val PHASE_OFFSET = TWO_PI / DOT_COUNT
    }
}
