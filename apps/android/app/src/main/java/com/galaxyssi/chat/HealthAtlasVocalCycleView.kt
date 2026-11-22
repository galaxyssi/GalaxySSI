package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import android.widget.LinearLayout
import android.widget.SeekBar
import kotlin.math.roundToInt
import kotlin.math.sqrt

internal class HealthAtlasVocalCycleView(activity: Activity, initial: HealthAtlasPhysiology) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val art = GlottalDiagram(activity, initial)
    private val position = SeekBar(activity).apply {
        max = 1000
        tag = "atlas-vocal-cycle-position"
        isSaveEnabled = false
        contentDescription = context.getString(R.string.health_atlas_vocal_cycles_position)
    }
    private val playback = HealthAtlasTeachingPlayback(activity,
        R.string.health_atlas_vocal_cycles_play, R.string.health_atlas_vocal_cycles_pause) { phase ->
        art.phase = phase
        position.progress = (phase * position.max).roundToInt()
    }

    var model = initial
        set(value) {
            field = value
            art.model = value
            playback.showTarget(2400L)
        }

    init {
        orientation = VERTICAL
        ui.add(this, ui.line().apply {
            addView(ui.text(context.getString(R.string.health_atlas_vocal_cycles_caption), 14f, bold = true),
                LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
            addView(playback.button.apply { tag = "atlas-vocal-cycle-play" })
        })
        ui.add(this, art)
        ui.add(this, position)
        position.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onStartTrackingTouch(seek: SeekBar?) = playback.pause()
            override fun onStopTrackingTouch(seek: SeekBar?) = Unit
            override fun onProgressChanged(seek: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) playback.seek(progress.toFloat() / position.max)
            }
        })
        model = initial
    }

    override fun onDetachedFromWindow() {
        playback.pause()
        super.onDetachedFromWindow()
    }

    private class GlottalDiagram(context: Context, initial: HealthAtlasPhysiology) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            strokeCap = Paint.Cap.ROUND
        }
        private val path = Path()
        private val ink = context.getColor(R.color.text_primary)
        private val teal = 0xff297c79.toInt()
        private val gold = 0xffa86f32.toInt()

        var model = initial
            set(value) {
                field = value
                contentDescription = context.getString(R.string.health_atlas_vocal_cycles_diagram,
                    HealthAtlasPhysiologyText.resultNumber(value, value.result))
                invalidate()
            }
        var phase = 1f
            set(value) { field = value; invalidate() }

        init {
            tag = "atlas-vocal-cycle-diagram"
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val available = MeasureSpec.getSize(widthMeasureSpec)
            val height = minOf((available * .49f).roundToInt(), (175 * resources.displayMetrics.density).roundToInt())
            setMeasuredDimension(available, resolveSize(height, heightMeasureSpec))
        }

        override fun onDraw(canvas: Canvas) {
            val scale = minOf(width / 340f, height / 152f)
            if (scale <= 0f) return
            canvas.save()
            canvas.translate((width - 340 * scale) / 2, (height - 152 * scale) / 2)
            canvas.scale(scale, scale)
            val cycles = model.result
            val opening = HealthAtlasVocalCycleTeachingModel.relativeOpening(cycles, phase)
            drawGlottis(canvas, opening)
            drawCurve(canvas, cycles, opening)
            canvas.restore()
        }

        private fun drawGlottis(c: Canvas, opening: Float) {
            val x = 76f
            val gap = 21f * sqrt(opening)
            paint.color = 0xffb4767c.toInt()
            c.drawOval(20f, 20f, 132f, 132f, paint)
            paint.color = 0xff46505d.toInt()
            c.drawOval(28f, 30f, 124f, 124f, paint)
            for (side in floatArrayOf(-1f, 1f)) {
                path.rewind()
                path.moveTo(x, 33f)
                path.cubicTo(x + side * gap, 55f, x + side * gap, 87f, x + side * gap * .62f, 114f)
                path.cubicTo(x + side * 44f, 115f, x + side * 45f, 53f, x, 33f)
                path.close()
                paint.color = 0xffebb9aa.toInt()
                c.drawPath(path, paint)
                paint.color = 0xffffe5d2.toInt()
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = 2.5f
                c.drawPath(path, paint)
                paint.style = Paint.Style.FILL
            }
            label(c, context.getString(R.string.health_atlas_vocal_cycles_top_view), x, 148f, 135f)
        }

        private fun drawCurve(c: Canvas, cycles: Double, relativeOpening: Float) {
            val left = 160f
            val right = 319f
            val top = 46f
            val bottom = 112f
            fun graphY(value: Float) = bottom - (bottom - top) * value

            paint.color = 0xffdbe9eb.toInt()
            c.drawRoundRect(left - 6, top - 4, right + 6, bottom + 6, 6f, 6f, paint)
            paint.color = 0xff87a3a8.toInt()
            paint.strokeWidth = 1f
            for (value in floatArrayOf(0f, .5f, 1f)) c.drawLine(left, graphY(value), right, graphY(value), paint)
            path.rewind()
            for (i in 0..144) {
                val fraction = i / 144f
                val x = left + fraction * (right - left)
                val y = graphY(HealthAtlasVocalCycleTeachingModel.relativeOpening(cycles, fraction))
                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 2.1f
            paint.color = teal
            c.drawPath(path, paint)
            paint.style = Paint.Style.FILL
            val cursor = left + phase * (right - left)
            paint.color = gold
            paint.strokeWidth = 1.3f
            c.drawLine(cursor, top - 4, cursor, bottom + 6, paint)
            c.drawCircle(cursor, graphY(relativeOpening), 3.3f, paint)
            label(c, context.getString(R.string.health_atlas_vocal_cycles_opening), 239f, 30f, 171f)
            label(c, "0", left, 137f, 30f)
            label(c, HealthAtlasPhysiologyText.number(model.input(1), 0) + " ms", 304f, 137f, 65f)
        }

        private fun label(c: Canvas, text: String, x: Float, y: Float, room: Float) {
            paint.color = ink
            paint.textSize = 12f
            val width = paint.measureText(text)
            if (width > room) paint.textSize *= room / width
            c.drawText(text, x, y, paint)
        }
    }
}
