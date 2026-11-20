package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.View

/** A parameter-response curve, not a time series or a personal measurement trend. */
internal class HealthAtlasPhysiologyChart(context: Context, initial: HealthAtlasPhysiology) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val density = resources.displayMetrics.density
    private val font = 12f * resources.displayMetrics.scaledDensity
    var model = initial
        set(value) {
            require(value.kind == field.kind)
            field = value
            contentDescription = HealthAtlasPhysiologyText.result(context, value) + "; " +
                HealthAtlasPhysiologyText.input(context, value, value.kind.axis)
            invalidate()
        }
    init { tag = "atlas-physiology-chart"; isSaveEnabled = false; importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES; model = initial }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), resolveSize((160 * density + font * 4).toInt(), heightMeasureSpec))
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        paint.textSize = font
        val low = model.kind.minimum; val high = model.plotMaximum
        val ticks = listOf(low, (low + high) / 2, high)
        val left = ticks.maxOf { paint.measureText(HealthAtlasPhysiologyText.number(it)) } + 12 * density
        val range = model.axisRange
        val right = width - paint.measureText(HealthAtlasPhysiologyText.number(range.endInclusive)) / 2 - 6 * density
        val top = font * 2; val bottom = height - font * 2
        if (right <= left || bottom <= top) return
        fun x(value: Double) = left + ((right - left) * (value - range.start) / (range.endInclusive - range.start)).toFloat()
        fun y(value: Double) = bottom - ((bottom - top) * (value - low) / (high - low)).toFloat()
        paint.color = context.getColor(R.color.text_secondary); paint.textAlign = Paint.Align.LEFT
        canvas.drawText(model.kind.unit, left, font, paint)
        paint.strokeWidth = density
        ticks.forEach { tick ->
            paint.color = context.getColor(R.color.separator); canvas.drawLine(left, y(tick), right, y(tick), paint)
            paint.color = context.getColor(R.color.text_secondary); paint.textAlign = Paint.Align.RIGHT
            canvas.drawText(HealthAtlasPhysiologyText.number(tick), left - 6 * density, y(tick) + font * .3f, paint)
        }
        paint.textAlign = Paint.Align.CENTER
        listOf(range.start, (range.start + range.endInclusive) / 2, range.endInclusive).forEach {
            canvas.drawText(HealthAtlasPhysiologyText.number(it), x(it), bottom + font * 1.4f, paint)
        }
        val path = Path().apply {
            for (step in 0..120) {
                val value = range.start + (range.endInclusive - range.start) * step / 120
                if (step == 0) moveTo(x(value), y(model.resultAt(value))) else lineTo(x(value), y(model.resultAt(value)))
            }
        }
        paint.color = context.getColor(R.color.health_overview_green); paint.strokeWidth = 2.5f * density; paint.style = Paint.Style.STROKE
        canvas.drawPath(path, paint)
        val px = x(model.input(model.kind.axis)); val py = y(model.result)
        paint.strokeWidth = density; canvas.drawLine(px, py, px, bottom, paint)
        paint.style = Paint.Style.FILL; canvas.drawCircle(px, py, 5 * density, paint)
    }
}
