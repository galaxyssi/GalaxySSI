package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import java.text.NumberFormat

internal class HealthAtlasEliminationChart(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val density = resources.displayMetrics.density
    private val textSize = 12f * resources.displayMetrics.scaledDensity
    var model = HealthAtlasElimination()
        set(value) {
            field = value
            contentDescription = context.getString(R.string.health_atlas_elimination_summary,
                value.halfLifeHours, value.elapsedHours, percent(value.percent))
            invalidate()
        }
    init { tag = "atlas-elimination-chart"; isSaveEnabled = false; model = model }
    private fun percent(value: Double) = NumberFormat.getNumberInstance().apply { maximumFractionDigits = 2 }.format(value)
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), resolveSize((180 * density + textSize * 3).toInt(), heightMeasureSpec))
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        paint.textSize = textSize
        val left = paint.measureText("100%") + 12 * density
        val right = width - paint.measureText("48") / 2 - 4 * density
        val top = textSize
        val bottom = height - textSize * 2
        if (right <= left || bottom <= top) return
        fun x(hours: Double) = left + ((right - left) * hours / 48).toFloat()
        fun y(value: Double) = bottom - ((bottom - top) * value / 100).toFloat()
        paint.strokeWidth = density
        for (value in listOf(0, 50, 100)) {
            paint.color = context.getColor(R.color.separator)
            canvas.drawLine(left, y(value.toDouble()), right, y(value.toDouble()), paint)
            paint.color = context.getColor(R.color.text_secondary); paint.textAlign = Paint.Align.RIGHT
            canvas.drawText("$value%", left - 6 * density, y(value.toDouble()) + textSize * .3f, paint)
        }
        paint.textAlign = Paint.Align.CENTER
        for (hour in listOf(0, 24, 48)) canvas.drawText(hour.toString(), x(hour.toDouble()), bottom + textSize * 1.4f, paint)
        val path = Path().apply {
            for (step in 0..192) {
                val hour = step / 4.0
                if (step == 0) moveTo(x(hour), y(model.percentAt(hour))) else lineTo(x(hour), y(model.percentAt(hour)))
            }
        }
        paint.style = Paint.Style.STROKE; paint.strokeWidth = density * 2.5f
        paint.color = context.getColor(R.color.health_overview_green); canvas.drawPath(path, paint)
        val mx = x(model.elapsedHours.toDouble()); val my = y(model.percent)
        paint.strokeWidth = density; canvas.drawLine(mx, my, mx, bottom, paint)
        paint.style = Paint.Style.FILL; canvas.drawCircle(mx, my, density * 5, paint)
    }
}
