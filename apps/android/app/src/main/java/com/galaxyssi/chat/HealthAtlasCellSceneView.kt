package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.Drawable
import android.view.View

internal abstract class HealthAtlasCellSceneView(context: Context, private val stageTitles: List<String>,
    private val stageLabel: Int, private val maxHeightDp: Int = 240) : View(context) {
    protected val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeCap = Paint.Cap.ROUND }
    val stage get() = (phase * 4f).toInt().coerceAtMost(3)
    var phase = 0f
        set(value) {
            require(value in 0f..1f)
            if (value == field) return
            val previous = stage
            field = value
            if (previous != stage) describe()
            invalidate()
        }

    init {
        require(stageTitles.size == 4)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        describe()
    }

    private fun describe() {
        contentDescription = context.getString(stageLabel, stageTitles[stage])
    }

    final override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = (width * .56f).toInt().coerceAtMost((maxHeightDp * resources.displayMetrics.density).toInt())
        setMeasuredDimension(width, resolveSize(height, heightMeasureSpec))
    }

    final override fun onDraw(canvas: Canvas) = drawFrame(canvas, width, height, phase)

    fun drawFrame(canvas: Canvas, frameWidth: Int, frameHeight: Int, position: Float) {
        phase = position
        val scale = minOf(frameWidth / 360f, frameHeight / 200f)
        val progress = phase * 4f - stage
        val ease = progress * progress * (3f - 2f * progress)
        canvas.save()
        canvas.translate((frameWidth - 360f * scale) / 2f, (frameHeight - 200f * scale) / 2f)
        canvas.scale(scale, scale)
        drawScene(canvas, ease)
        canvas.restore()
    }

    protected abstract fun drawScene(canvas: Canvas, t: Float)

    protected fun portrait(res: Int): Drawable = requireNotNull(context.getDrawable(res)).mutate().apply {
        val width = intrinsicWidth.coerceAtLeast(1)
        val height = intrinsicHeight.coerceAtLeast(1)
        val fit = 200f / maxOf(width, height)
        val dx = (width * fit / 2).toInt()
        val dy = (height * fit / 2).toInt()
        setBounds(-dx, -dy, dx, dy)
        setFilterBitmap(true)
    }

    protected fun fill(color: Int) { paint.style = Paint.Style.FILL; paint.color = color }
    protected fun stroke(color: Int, width: Float) {
        paint.style = Paint.Style.STROKE; paint.color = color; paint.strokeWidth = width
    }

    protected fun drawPortrait(canvas: Canvas, art: Drawable, x: Float, y: Float, size: Float, widthRatio: Float = 1f) {
        canvas.save()
        canvas.translate(x, y)
        canvas.scale(size * widthRatio / 200f, size / 200f)
        art.draw(canvas)
        canvas.restore()
    }
}
