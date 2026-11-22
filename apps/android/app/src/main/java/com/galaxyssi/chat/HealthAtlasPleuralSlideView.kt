package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View
import android.widget.LinearLayout
import kotlin.math.roundToInt

internal class HealthAtlasPleuralSlideView(activity: Activity, initial: HealthAtlasPhysiology) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val art = SlidingDiagram(activity, initial)
    private val playback = HealthAtlasTeachingPlayback(activity,
        R.string.health_atlas_pleural_slide_play, R.string.health_atlas_pleural_slide_pause) {
        art.phase = it
    }

    var model = initial
        set(value) {
            field = value
            art.model = value
            playback.showTarget(if (value.input(0) > 0.0) 2300L else 0L)
        }

    init {
        orientation = VERTICAL
        ui.add(this, ui.line().apply {
            addView(ui.text(context.getString(R.string.health_atlas_pleural_slide_caption), 14f, bold = true),
                LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
            addView(playback.button.apply { tag = "atlas-pleural-slide-play" })
        })
        ui.add(this, art)
        model = initial
    }

    override fun onDetachedFromWindow() {
        playback.pause()
        super.onDetachedFromWindow()
    }

    private class SlidingDiagram(context: Context, initial: HealthAtlasPhysiology) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            strokeCap = Paint.Cap.ROUND
        }
        private val ink = context.getColor(R.color.text_primary)
        private val filmMarker = 0xff477f89.toInt()

        var model = initial
            set(value) {
                field = value
                contentDescription = context.getString(R.string.health_atlas_pleural_slide_diagram,
                    HealthAtlasPhysiologyText.resultNumber(value, value.result))
                invalidate()
            }
        var phase = 1f
            set(value) { field = value; invalidate() }

        init {
            tag = "atlas-pleural-slide-diagram"
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val available = MeasureSpec.getSize(widthMeasureSpec)
            val height = minOf((available * .50f).roundToInt(), (178 * resources.displayMetrics.density).roundToInt())
            setMeasuredDimension(available, resolveSize(height, heightMeasureSpec))
        }

        override fun onDraw(canvas: Canvas) {
            val scale = minOf(width / 340f, height / 163f)
            if (scale <= 0f) return
            canvas.save()
            canvas.translate((width - 340 * scale) / 2, (height - 163 * scale) / 2)
            canvas.scale(scale, scale)

            val speed = model.input(0)
            val gap = 16f + 24f * model.input(1).toFloat()
            val center = 81f
            val upper = center - gap / 2
            val lower = center + gap / 2

            fill(canvas, upper - 21f, upper, 0xffe9c4b8.toInt(), 8f)
            fill(canvas, upper - 4f, upper + 1f, 0xffa76a65.toInt(), 2f)
            fill(canvas, upper + 1f, lower - 1f, 0xffcfe4ea.toInt(), 0f)
            fill(canvas, lower - 1f, lower + 4f, 0xff61948e.toInt(), 2f)
            fill(canvas, lower + 4f, lower + 24f, 0xffabd0c6.toInt(), 8f)

            canvas.save()
            canvas.clipRect(23f, upper - 20f, 309f, lower)
            val surfaceOffset = offset(speed, 1f)
            paint.strokeWidth = 2f
            paint.color = 0xffa66e63.toInt()
            for (i in -7..12) {
                val x = 24f + i * 28 + surfaceOffset
                canvas.drawLine(x, upper - 14f, x + 9f, upper - 14f, paint)
            }
            paint.color = filmMarker
            for (row in 1..4) {
                val fraction = row / 5f
                val y = lower - gap * fraction
                val dx = offset(speed, fraction)
                for (i in -3..7) {
                    val x = 28f + 44f * i + dx
                    canvas.drawCircle(x, y, 2.1f, paint)
                }
            }
            canvas.restore()

            paint.color = filmMarker
            paint.strokeWidth = 1.6f
            canvas.drawLine(322f, upper, 322f, lower, paint)
            canvas.drawLine(317f, upper, 327f, upper, paint)
            canvas.drawLine(317f, lower, 327f, lower, paint)
            label(canvas, R.string.health_atlas_pleural_slide_wall, 15f)
            label(canvas, R.string.health_atlas_pleural_slide_lung, 151f)
            canvas.restore()
        }

        private fun offset(speed: Double, fractionFromReference: Float): Float =
            (HealthAtlasPleuralSlideTeachingModel.relativeVelocity(speed, fractionFromReference) * phase * 5).toFloat()

        private fun fill(canvas: Canvas, top: Float, bottom: Float, color: Int, radius: Float) {
            paint.color = color
            canvas.drawRoundRect(23f, top, 309f, bottom, radius, radius, paint)
        }

        private fun label(canvas: Canvas, resource: Int, y: Float) {
            paint.color = ink
            paint.textSize = 12.5f
            canvas.drawText(context.getString(resource), 166f, y, paint)
        }
    }
}
