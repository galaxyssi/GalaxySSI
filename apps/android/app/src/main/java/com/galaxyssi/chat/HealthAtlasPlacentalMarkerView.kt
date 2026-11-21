package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View
import android.widget.LinearLayout
import kotlin.math.roundToInt
import kotlin.math.sqrt

internal class HealthAtlasPlacentalMarkerView(activity: Activity, initial: HealthAtlasPhysiology) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val art = ExchangeDiagram(activity, initial)
    private val playback = HealthAtlasTeachingPlayback(activity,
        R.string.health_atlas_placental_marker_play, R.string.health_atlas_placental_marker_pause) {
        art.phase = it
    }

    var model = initial
        set(value) {
            field = value
            art.model = value
            playback.showTarget(if (value.result > 0) 2300L else 0L)
        }

    init {
        orientation = VERTICAL
        ui.add(this, ui.line().apply {
            addView(ui.text(context.getString(R.string.health_atlas_placental_marker_caption), 14f, bold = true),
                LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
            addView(playback.button.apply { tag = "atlas-placental-marker-play" })
        })
        ui.add(this, art)
        model = initial
    }

    override fun onDetachedFromWindow() {
        playback.pause()
        super.onDetachedFromWindow()
    }

    private class ExchangeDiagram(context: Context, initial: HealthAtlasPhysiology) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            strokeCap = Paint.Cap.ROUND
        }
        private val tissueInk = 0xff4c414a.toInt()
        private val gold = 0xffb47a33.toInt()
        private var presentedTransfer = initial.result

        var model = initial
            set(value) {
                field = value
                presentedTransfer = value.result
                contentDescription = context.getString(R.string.health_atlas_placental_marker_diagram,
                    HealthAtlasPhysiologyText.number(value.companionValue), HealthAtlasPhysiologyText.number(value.result))
                invalidate()
            }
        var phase = 1f
            set(value) { field = value; invalidate() }

        init {
            tag = "atlas-placental-marker-diagram"
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val available = MeasureSpec.getSize(widthMeasureSpec)
            val height = minOf((available * .58f).roundToInt(), (200 * resources.displayMetrics.density).roundToInt())
            setMeasuredDimension(available, resolveSize(height, heightMeasureSpec))
        }

        override fun onDraw(canvas: Canvas) {
            val scale = minOf(width / 340f, height / 183f)
            if (scale <= 0f) return
            canvas.save()
            canvas.translate((width - 340 * scale) / 2, (height - 183 * scale) / 2)
            canvas.scale(scale, scale)
            val amounts = HealthAtlasPlacentalMarkerTeachingModel.atPhase(model.input(0), presentedTransfer, phase)
            lane(canvas, 13f, amounts.maternal, R.string.health_atlas_placental_marker_maternal, 0xffefdadb.toInt())
            lane(canvas, 119f, amounts.fetal, R.string.health_atlas_placental_marker_fetal, 0xffd4e7e9.toInt())
            for (i in 0..12) {
                val x = 27f + i * 24f
                paint.color = if (i % 2 == 0) 0xffb0c8c3.toInt() else 0xffbfd4d2.toInt()
                canvas.drawOval(x - 13, 82f, x + 13, 102f, paint)
            }
            label(canvas, context.getString(R.string.health_atlas_placental_marker_barrier), 94f, 96f, 122f, tissueInk)
            if (presentedTransfer > 0 && phase < 1f) {
                val x = 225f + 19f * phase
                val y = 63f + 67f * phase
                paint.color = gold
                canvas.drawCircle(x, y, 4.4f, paint)
                paint.color = 0xffffdfac.toInt()
                canvas.drawCircle(x - 1.2f, y - 1.1f, 1.6f, paint)
            }
            canvas.restore()
        }

        private fun lane(c: Canvas, top: Float, units: Double, title: Int, fill: Int) {
            paint.color = fill
            c.drawRoundRect(13f, top, 327f, top + 51f, 13f, 13f, paint)
            label(c, context.getString(title), 72f, top + 22f, 110f, tissueInk)
            label(c, context.getString(R.string.health_atlas_placental_marker_amount_label,
                HealthAtlasPhysiologyText.number(units, 1)), 248f, top + 43f, 148f, tissueInk)
            val slots = 8 * units / HealthAtlasPlacentalMarkerTeachingModel.MAX_STARTING_UNITS
            repeat(8) { index ->
                val x = 151f + index * 21f
                val y = top + 18f
                paint.color = 0xffac9693.toInt()
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = 1.2f
                c.drawCircle(x, y, 6.3f, paint)
                paint.style = Paint.Style.FILL
                val share = (slots - index).coerceIn(0.0, 1.0).toFloat()
                if (share > 0f) { paint.color = gold; c.drawCircle(x, y, 5.3f * sqrt(share), paint) }
            }
        }

        private fun label(c: Canvas, text: String, x: Float, y: Float, room: Float, color: Int) {
            paint.color = color
            paint.textSize = 12.5f
            val width = paint.measureText(text)
            if (width > room) paint.textSize *= room / width
            c.drawText(text, x, y, paint)
        }
    }
}
