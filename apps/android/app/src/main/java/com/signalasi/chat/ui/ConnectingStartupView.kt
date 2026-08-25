package com.signalasi.chat.ui

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.AttributeSet
import android.util.TypedValue
import android.view.View
import com.signalasi.chat.R
import kotlin.math.max

internal data class ConnectingFrame(
    val characters: String,
    val cursorVisible: Boolean
)

internal object ConnectingFrameSequence {
    private const val LABEL = "CONNECTING"
    private val glitchFrames = listOf(
        "CONNEC<:_\\",
        "CONNECT:|<",
        "CONNECTI-~",
        "CONNEC|_>\\",
        "CONNECT/|"
    )

    fun frameAt(tick: Int, reduceMotion: Boolean = false): ConnectingFrame {
        if (reduceMotion) return ConnectingFrame(LABEL, false)
        val safeTick = max(0, tick)
        val phase = safeTick % 24
        val cycle = safeTick / 24
        val glitchIndex = when (phase) {
            in 7..11 -> phase - 7
            in 17..20 -> phase - 16
            else -> -1
        }
        val characters = if (glitchIndex >= 0) {
            glitchFrames[(glitchIndex + cycle) % glitchFrames.size].padEnd(LABEL.length).take(LABEL.length)
        } else {
            LABEL
        }
        val cursorVisible = phase in 2..6 || phase in 12..16 || phase >= 21
        return ConnectingFrame(characters, cursorVisible)
    }
}

class ConnectingStartupView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {
    private val handler = Handler(Looper.getMainLooper())
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = context.getColor(R.color.text_secondary)
        textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 11f, resources.displayMetrics)
        typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }
    private val cursorPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = context.getColor(R.color.text_secondary)
    }
    private val cellAdvance = 13f * resources.displayMetrics.density
    private val cursorSize = 10f * resources.displayMetrics.density
    private val cursorGap = 3f * resources.displayMetrics.density
    private val reduceMotion = runCatching {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }.getOrDefault(false)
    private var tick = 0
    private var firstDrawAt = 0L
    private var readyToFinish = false
    private var finishScheduled = false

    private val advanceFrame = object : Runnable {
        override fun run() {
            if (!isAttachedToWindow || visibility != VISIBLE || reduceMotion) return
            tick += 1
            invalidate()
            handler.postDelayed(this, FRAME_MILLIS)
        }
    }

    init {
        isClickable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        tick = 0
        if (!reduceMotion) handler.postDelayed(advanceFrame, FRAME_MILLIS)
    }

    override fun onDetachedFromWindow() {
        handler.removeCallbacksAndMessages(null)
        animate().cancel()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (firstDrawAt == 0L) {
            firstDrawAt = android.os.SystemClock.uptimeMillis()
            scheduleFinishIfReady()
        }

        val frame = ConnectingFrameSequence.frameAt(tick, reduceMotion)
        val labelWidth = frame.characters.length * cellAdvance
        val fullWidth = labelWidth + cursorGap + cursorSize
        val startX = (width - fullWidth) / 2f + cellAdvance / 2f
        val baseline = height / 2f - (textPaint.ascent() + textPaint.descent()) / 2f

        frame.characters.forEachIndexed { index, character ->
            canvas.drawText(character.toString(), startX + index * cellAdvance, baseline, textPaint)
        }
        if (frame.cursorVisible) {
            drawCheckerCursor(canvas, startX - cellAdvance / 2f + labelWidth + cursorGap, height / 2f - cursorSize / 2f)
        }
    }

    fun finishWhenReady() {
        readyToFinish = true
        scheduleFinishIfReady()
    }

    private fun scheduleFinishIfReady() {
        if (!readyToFinish || firstDrawAt == 0L || finishScheduled) return
        finishScheduled = true
        val minimumVisibleMillis = if (reduceMotion) REDUCED_MOTION_MILLIS else MINIMUM_VISIBLE_MILLIS
        val elapsed = android.os.SystemClock.uptimeMillis() - firstDrawAt
        handler.postDelayed(::fadeOut, (minimumVisibleMillis - elapsed).coerceAtLeast(0L))
    }

    private fun fadeOut() {
        handler.removeCallbacks(advanceFrame)
        animate()
            .alpha(0f)
            .setDuration(if (reduceMotion) 0L else FADE_MILLIS)
            .setListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    visibility = GONE
                }
            })
            .start()
    }

    private fun drawCheckerCursor(canvas: Canvas, left: Float, top: Float) {
        val square = cursorSize / 4f
        for (row in 0 until 4) {
            for (column in 0 until 4) {
                if ((row + column) % 2 == 0) {
                    canvas.drawRect(
                        left + column * square,
                        top + row * square,
                        left + (column + 1) * square,
                        top + (row + 1) * square,
                        cursorPaint
                    )
                }
            }
        }
    }

    private companion object {
        const val FRAME_MILLIS = 75L
        const val MINIMUM_VISIBLE_MILLIS = 1_250L
        const val REDUCED_MOTION_MILLIS = 250L
        const val FADE_MILLIS = 170L
    }
}
