package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import android.widget.LinearLayout
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

internal class HealthAtlasUreterTransportView(activity: Activity, initial: HealthAtlasPhysiology) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val art = TransportDiagram(activity, initial)
    private val playback = HealthAtlasTeachingPlayback(activity,
        R.string.health_atlas_ureter_delivery_play, R.string.health_atlas_ureter_delivery_pause) {
        art.phase = it
    }

    var model = initial
        set(value) {
            field = value
            art.model = value
            playback.showTarget(1100L * value.inputs[0])
        }

    init {
        orientation = VERTICAL
        ui.add(this, ui.line().apply {
            addView(ui.text(context.getString(R.string.health_atlas_ureter_delivery_caption), 14f, bold = true),
                LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
            addView(playback.button.apply { tag = "atlas-ureter-transport-play" })
        })
        ui.add(this, art)
        model = initial
    }

    override fun onDetachedFromWindow() {
        playback.pause()
        super.onDetachedFromWindow()
    }

    private class TransportDiagram(context: Context, initial: HealthAtlasPhysiology) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            strokeCap = Paint.Cap.ROUND
        }
        private val tube = Path()
        private val ink = context.getColor(R.color.text_primary)
        private val wall = 0xffac7783.toInt()
        private val lining = 0xfff5d0c7.toInt()
        private val marker = 0xffb57839.toInt()
        private val arrival = 0xff508679.toInt()

        var model = initial
            set(value) {
                field = value
                contentDescription = context.getString(R.string.health_atlas_ureter_delivery_diagram,
                    HealthAtlasPhysiologyText.resultNumber(value, value.result))
                invalidate()
            }
        var phase = 1f
            set(value) { field = value; invalidate() }

        init {
            tag = "atlas-ureter-transport-diagram"
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val available = MeasureSpec.getSize(widthMeasureSpec)
            val height = minOf((available * .51f).roundToInt(), (180 * resources.displayMetrics.density).roundToInt())
            setMeasuredDimension(available, resolveSize(height, heightMeasureSpec))
        }

        override fun onDraw(canvas: Canvas) {
            val scale = minOf(width / 340f, height / 162f)
            if (scale <= 0f) return
            canvas.save()
            canvas.translate((width - 340 * scale) / 2, (height - 162 * scale) / 2)
            canvas.scale(scale, scale)
            val frame = HealthAtlasUreterDeliveryTeachingModel.frame(model.inputs[0], phase)
            val inTransit = frame.inTransit
            val packetRadius = sqrt(model.input(1) / 3).toFloat()
            endpoint(canvas, 19f, 63f, 64f, 103f)
            endpoint(canvas, 273f, 63f, 321f, 103f)
            tube.rewind()
            val contraction = inTransit?.minus(.075f)
            for (direction in listOf(-1, 1)) {
                for (index in 0..52) {
                    val step = if (direction < 0) index else 52 - index
                    val at = step / 52f
                    val x = 59f + at * 222f
                    val y = center(at) + direction * tubeRadius(at, contraction)
                    if (direction < 0 && index == 0) tube.moveTo(x, y) else tube.lineTo(x, y)
                }
            }
            tube.close()
            paint.color = lining
            canvas.drawPath(tube, paint)
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 2.7f
            paint.color = wall
            canvas.drawPath(tube, paint)
            paint.style = Paint.Style.FILL
            if (inTransit != null) {
                val x = 59f + inTransit * 222f
                val y = center(inTransit)
                paint.color = marker
                val radius = 3.8f + packetRadius * 2.1f
                canvas.drawOval(x - radius * 1.5f, y - radius, x + radius * 1.5f, y + radius, paint)
            }
            label(canvas, context.getString(R.string.health_atlas_ureter_delivery_pelvis), 43f, 43f)
            label(canvas, context.getString(R.string.health_atlas_ureter_delivery_tube), 170f, 26f)
            label(canvas, context.getString(R.string.health_atlas_ureter_delivery_bladder), 297f, 43f)
            repeat(HealthAtlasUreterDeliveryTeachingModel.PACKETS) { i ->
                paint.color = if (i < frame.arrived) arrival else 0xff9a8785.toInt()
                paint.style = if (i < frame.arrived) Paint.Style.FILL else Paint.Style.STROKE
                paint.strokeWidth = 1.4f
                canvas.drawCircle(107f + i * 25f, 126f, 3.3f + 3f * packetRadius, paint)
            }
            paint.style = Paint.Style.FILL
            label(canvas, context.getString(R.string.health_atlas_ureter_delivery_counter, frame.arrived,
                HealthAtlasUreterDeliveryTeachingModel.PACKETS), 170f, 151f)
            canvas.restore()
        }

        private fun center(at: Float) = 82f - 27f * sin(PI * at).toFloat()

        private fun tubeRadius(at: Float, contraction: Float?): Float {
            if (contraction == null) return 10f
            val fromWave = (at - contraction) / .045f
            return 10f - 7f * exp(-fromWave * fromWave)
        }

        private fun endpoint(canvas: Canvas, left: Float, top: Float, right: Float, bottom: Float) {
            paint.color = wall
            canvas.drawOval(left, top, right, bottom, paint)
            paint.color = lining
            canvas.drawOval(left + 4f, top + 4f, right - 4f, bottom - 4f, paint)
        }

        private fun label(canvas: Canvas, caption: String, x: Float, y: Float) {
            paint.textSize = 12f
            paint.color = ink
            canvas.drawText(caption, x, y, paint)
        }
    }
}
