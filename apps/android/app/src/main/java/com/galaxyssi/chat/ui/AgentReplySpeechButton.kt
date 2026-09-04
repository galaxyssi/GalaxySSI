package com.galaxyssi.chat.ui

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.util.AttributeSet
import android.view.Gravity
import android.view.View
import android.view.animation.LinearInterpolator
import android.widget.LinearLayout
import android.widget.TextView
import com.galaxyssi.chat.R
import kotlin.math.PI
import kotlin.math.sin

internal class AgentReplySpeechButton @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {
    private val glyph = AgentReplySpeechGlyphView(context)
    private val label = TextView(context)

    internal var isPlayingSpeech: Boolean = false
        private set

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumWidth = 0
        minimumHeight = dp(32)
        setPadding(dp(9), 0, dp(11), 0)
        isClickable = true
        isFocusable = true
        background = RippleDrawable(
            android.content.res.ColorStateList.valueOf(Color.parseColor("#14000000")),
            roundedSurface(),
            roundedSurface()
        )

        addView(glyph, LayoutParams(dp(18), dp(18)))
        addView(
            label.apply {
                gravity = Gravity.CENTER_VERTICAL
                includeFontPadding = false
                textSize = 12f
            },
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                marginStart = dp(6)
            }
        )
        setPlaying(false)
    }

    fun setPlaying(playing: Boolean) {
        isPlayingSpeech = playing
        val color = if (playing) ACTIVE_COLOR else IDLE_COLOR
        glyph.setPlaying(playing, color)
        label.setText(
            if (playing) R.string.agent_reply_speech_playing_label
            else R.string.agent_reply_speech_idle_label
        )
        label.setTextColor(color)
        contentDescription = context.getString(
            if (playing) R.string.agent_reply_speech_disable
            else R.string.agent_reply_speech_enable
        )
    }

    private fun roundedSurface() = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = dp(5).toFloat()
        setColor(Color.WHITE)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density + 0.5f).toInt()

    private companion object {
        val IDLE_COLOR: Int = Color.parseColor("#666A72")
        val ACTIVE_COLOR: Int = Color.parseColor("#079D85")
    }
}

private class AgentReplySpeechGlyphView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val speaker = Path()
    private var playing = false
    private var iconColor = Color.GRAY
    private var animationProgress = 0f
    private var animator: ValueAnimator? = null

    fun setPlaying(value: Boolean, color: Int) {
        playing = value
        iconColor = color
        if (value && isAttachedToWindow) startAnimation() else stopAnimation()
        invalidate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (playing) startAnimation()
    }

    override fun onDetachedFromWindow() {
        stopAnimation()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val scale = width.coerceAtMost(height) / 18f
        val offsetX = (width - 18f * scale) / 2f
        val offsetY = (height - 18f * scale) / 2f
        canvas.save()
        canvas.translate(offsetX, offsetY)
        canvas.scale(scale, scale)

        paint.color = iconColor
        paint.style = Paint.Style.FILL
        speaker.reset()
        speaker.moveTo(2f, 7f)
        speaker.lineTo(5f, 7f)
        speaker.lineTo(8.5f, 4f)
        speaker.lineTo(8.5f, 14f)
        speaker.lineTo(5f, 11f)
        speaker.lineTo(2f, 11f)
        speaker.close()
        canvas.drawPath(speaker, paint)

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 1.35f
        drawArc(canvas, RectF(7.5f, 5.5f, 14.5f, 12.5f), arcAlpha(0f))
        drawArc(canvas, RectF(7.5f, 3f, 17f, 15f), arcAlpha(0.45f))
        canvas.restore()
    }

    private fun drawArc(canvas: Canvas, bounds: RectF, alpha: Int) {
        paint.alpha = alpha
        canvas.drawArc(bounds, -48f, 96f, false, paint)
        paint.alpha = 255
    }

    private fun arcAlpha(phase: Float): Int {
        if (!playing) return 255
        val wave = (sin((animationProgress + phase) * 2f * PI).toFloat() + 1f) / 2f
        return (105f + 150f * wave).toInt()
    }

    private fun startAnimation() {
        if (animator?.isRunning == true) return
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1_550L
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener {
                animationProgress = it.animatedValue as Float
                invalidate()
            }
            start()
        }
    }

    private fun stopAnimation() {
        animator?.cancel()
        animator = null
        animationProgress = 0f
    }
}
