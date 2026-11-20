package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View
import android.widget.LinearLayout

internal class HealthAtlasSarcomerePanel(activity: Activity, private val mechanism: HealthAtlasMechanism) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val drawing = Diagram(activity)
    private val ratio = ui.text("", 15f, bold = true).apply { tag = "atlas-sarcomere-ratio" }
    var stage = 0
        set(value) { if (field != value) { field = value; update() } }

    init {
        orientation = VERTICAL
        addView(drawing, LayoutParams(-1, -2))
        ui.add(this, ratio, 4)
        ui.add(this, ui.text(activity.getString(R.string.health_atlas_sarcomere_filaments), 12f, muted = true), 4)
        ui.add(this, ui.text(activity.getString(R.string.health_atlas_sarcomere_scope), 12f, muted = true), 8)
        update()
    }
    private fun update() {
        val model = HealthAtlasSarcomere(stage)
        drawing.model = model
        ratio.text = context.getString(R.string.health_atlas_sarcomere_ratio, model.relativeLengthPercent)
        drawing.contentDescription = context.getString(R.string.health_atlas_sarcomere_visual_stage,
            mechanism.stages[stage], ratio.text)
    }

    internal class Diagram(context: Context) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeCap = Paint.Cap.ROUND }
        private val thin = context.getColor(R.color.health_atlas_sarcomere_thin)
        private val thick = context.getColor(R.color.health_atlas_sarcomere_thick)
        private val disc = context.getColor(R.color.text_primary)
        private val marker = context.getColor(R.color.health_overview_green)
        private val discLabel = context.getString(R.string.health_atlas_sarcomere_z)
        var model = HealthAtlasSarcomere(0)
            set(value) { if (field != value) { field = value; invalidate() } }

        init {
            tag = "atlas-sarcomere-diagram"
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val w = MeasureSpec.getSize(widthMeasureSpec)
            setMeasuredDimension(w, resolveSize((w * .45f).toInt().coerceAtMost(
                (220 * resources.displayMetrics.density).toInt()), heightMeasureSpec))
        }
        private fun line(canvas: Canvas, a: Float, y: Float, b: Float, y2: Float, color: Int, width: Float) {
            paint.color = color; paint.strokeWidth = width; paint.style = Paint.Style.STROKE
            canvas.drawLine(a, y, b, y2, paint)
        }
        private fun arrow(canvas: Canvas, start: Float, end: Float, y: Float) {
            line(canvas, start, y, end, y, marker, 2.4f)
            val behind = end + if (start < end) -6f else 6f
            line(canvas, behind, y - 4, end, y, marker, 2.4f)
            line(canvas, behind, y + 4, end, y, marker, 2.4f)
        }
        override fun onDraw(canvas: Canvas) {
            val scale = minOf(width / 360f, height / 156f)
            val left = model.leftZ.toFloat()
            val right = model.rightZ.toFloat()
            val lThick = model.leftThick.toFloat()
            val rThick = model.rightThick.toFloat()
            canvas.save()
            canvas.translate((width - 360 * scale) / 2, (height - 156 * scale) / 2)
            canvas.scale(scale, scale)
            for (y in listOf(61f, 95f)) {
                line(canvas, left, y, left + model.thinLength, y, thin, 4f)
                line(canvas, right - model.thinLength, y, right, y, thin, 4f)
            }
            line(canvas, lThick, 78f, rThick, 78f, thick, 8f)
            for (x in 122..238 step 13) {
                line(canvas, x.toFloat(), 78f, x + 6f, 70f, thick, 2.5f)
                line(canvas, x.toFloat(), 78f, x - 6f, 86f, thick, 2.5f)
            }
            line(canvas, left, 46f, left, 109f, disc, 4f)
            line(canvas, right, 46f, right, 109f, disc, 4f)
            paint.style = Paint.Style.FILL; paint.color = disc; paint.textAlign = Paint.Align.CENTER; paint.textSize = 13f
            canvas.drawText(discLabel, left, 132f, paint)
            canvas.drawText(discLabel, right, 132f, paint)
            when (model.stage) {
                0 -> arrow(canvas, left - 20, left - 1, 34f)
                1 -> {
                    paint.color = marker
                    for (x in listOf(157f, 179f, 202f)) canvas.drawCircle(x, 39f, 3.5f, paint)
                }
                2 -> { arrow(canvas, left - 25, left - 2, 34f); arrow(canvas, right + 25, right + 2, 34f) }
            }
            canvas.restore()
        }
    }
}
