package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.view.View

/** A labeled process sequence, deliberately separate from anatomical geometry. */
internal class HealthAtlasProcessView(context: Context, private val mechanism: HealthAtlasMechanism) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val density = resources.displayMetrics.density
    private val labelPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 12f * resources.displayMetrics.scaledDensity }
    private var labels = emptyList<StaticLayout>()
    private var rowHeight = 0f
    var phase = 0f
        set(value) { field = if (value.isFinite()) value.coerceIn(0f, 1f) else 0f; invalidate()
            contentDescription = context.getString(R.string.health_atlas_stage, minOf(3, (field * 4).toInt()) + 1, 4, mechanism.stages[minOf(3, (field * 4).toInt())]) }
    init { isSaveEnabled = false; tag = "atlas-process"; importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES; phase = 0f }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val column = ((width - 40 * density) / 2).toInt().coerceAtLeast(1)
        labels = mechanism.stages.map { text ->
            StaticLayout.Builder.obtain(text, 0, text.length, labelPaint, column)
                .setAlignment(Layout.Alignment.ALIGN_CENTER).setIncludePad(false).build()
        }
        rowHeight = 38 * density + labels.maxOf { it.height }
        setMeasuredDimension(width, resolveSize((rowHeight * 2 + 48 * density).toInt(), heightMeasureSpec))
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val accent = context.getColor(R.color.health_overview_green)
        if (labels.size != 4) return
        val left = 14 * density + labels[0].width / 2f
        val right = width - left
        val top = 24 * density
        val bottom = top + rowHeight + 24 * density
        val points = listOf(left to top, right to top, right to bottom, left to bottom)
        paint.strokeWidth = density * 2; paint.style = Paint.Style.STROKE; paint.color = context.getColor(R.color.separator)
        val path = Path().apply {
            moveTo(left, top); lineTo(right, top)
            lineTo(width - 4 * density, top); lineTo(width - 4 * density, bottom)
            lineTo(right, bottom); lineTo(left, bottom)
        }
        canvas.drawPath(path, paint)
        val measure = android.graphics.PathMeasure(path, false)
        val position = FloatArray(2)
        measure.getPosTan(measure.length * phase, position, null)
        paint.style = Paint.Style.FILL; paint.color = accent
        canvas.drawCircle(position[0], position[1], density * 5, paint)
        val current = minOf(3, (phase * 4).toInt())
        points.forEachIndexed { index, (x,y) ->
            paint.style = Paint.Style.FILL; paint.color = if (index <= current) accent else context.getColor(R.color.button_soft)
            canvas.drawCircle(x,y,density * 14,paint)
            paint.color = if (index <= current) android.graphics.Color.WHITE else context.getColor(R.color.text_primary)
            paint.textAlign = Paint.Align.CENTER; paint.textSize = density * 13
            canvas.drawText((index + 1).toString(),x,y + density * 4,paint)
            labelPaint.color = context.getColor(R.color.text_primary)
            canvas.save(); canvas.translate(x - labels[index].width / 2f, y + 24 * density)
            labels[index].draw(canvas); canvas.restore()
        }
    }
}
