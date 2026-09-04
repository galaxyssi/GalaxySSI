package com.galaxyssi.chat.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.util.AttributeSet
import android.widget.FrameLayout
import com.galaxyssi.chat.R

class AgentRecordingSurfaceView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {
    private val surfacePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        isDither = true
    }

    init {
        setWillNotDraw(false)
        clipToPadding = false
    }

    override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
        super.onSizeChanged(width, height, oldWidth, oldHeight)
        if (width <= 0 || height <= 0) return
        val light = context.getColor(R.color.agent_recording_gradient_light)
        val mid = context.getColor(R.color.agent_recording_gradient_mid)
        surfacePaint.shader = LinearGradient(
            0f,
            0f,
            0f,
            height.toFloat(),
            intArrayOf(
                Color.TRANSPARENT,
                light.withAlpha(30),
                light.withAlpha(132),
                mid.withAlpha(224),
                context.getColor(R.color.agent_recording_gradient_deep)
            ),
            floatArrayOf(0f, 0.16f, 0.36f, 0.64f, 1f),
            Shader.TileMode.CLAMP
        )
    }

    override fun onDraw(canvas: Canvas) {
        val width = width.toFloat()
        val height = height.toFloat()
        if (width <= 0f || height <= 0f) return
        canvas.drawRect(0f, 0f, width, height, surfacePaint)
    }

    private fun Int.withAlpha(alpha: Int): Int = Color.argb(
        alpha.coerceIn(0, 255),
        Color.red(this),
        Color.green(this),
        Color.blue(this)
    )
}
