package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View
import java.text.NumberFormat

internal class HealthActivityComparisonChart(context: Context, private val data: HealthActivityComparison,
    private val kind: HealthActivityKind) : View(context) {
    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    init {
        minimumHeight = (220 * density).toInt()
        contentDescription = context.getString(R.string.health_activity_comparison)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) =
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), resolveSize(minimumHeight, heightMeasureSpec))
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val left = 44 * density; val right = width - 10 * density
        val top = 14 * density; val bottom = height - 28 * density
        val divisor = if (kind == HealthActivityKind.CYCLING) 60_000.0 else 1.0
        val maximum = ((data.current + data.previous).filterNotNull().maxOrNull()?.toDouble() ?: 1.0).coerceAtLeast(divisor)
        paint.textSize = 11 * resources.displayMetrics.scaledDensity
        for (tick in 0..3) {
            val y = bottom - (bottom - top) * tick / 3
            paint.color = context.getColor(R.color.separator); paint.strokeWidth = density
            canvas.drawLine(left, y, right, y, paint)
            paint.color = context.getColor(R.color.text_secondary)
            canvas.drawText(NumberFormat.getIntegerInstance().format(maximum / divisor * tick / 3), 0f, y, paint)
        }
        fun plot(values: List<Long?>, color: Int) {
            var prior: Pair<Float, Float>? = null
            values.forEachIndexed { index, value ->
                if (value == null) { prior = null; return@forEachIndexed }
                val x = if (values.size == 1) (left + right) / 2 else left + (right - left) * index / (values.size - 1)
                val y = bottom - (bottom - top) * (value / maximum).toFloat()
                paint.color = color; paint.strokeWidth = 2 * density
                prior?.let { canvas.drawLine(it.first, it.second, x, y, paint) }
                canvas.drawCircle(x, y, 2.5f * density, paint); prior = x to y
            }
        }
        plot(data.previous, HealthTrendChart.BLUE); plot(data.current, context.getColor(R.color.health_overview_green))
        paint.color = context.getColor(R.color.text_secondary)
        canvas.drawText(data.first.toString(), left, height - 6 * density, paint)
        paint.textAlign = Paint.Align.RIGHT
        canvas.drawText(data.last.toString(), right, height - 6 * density, paint); paint.textAlign = Paint.Align.LEFT
    }
}
