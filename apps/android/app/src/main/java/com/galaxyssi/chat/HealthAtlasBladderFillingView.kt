package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import android.view.View
import android.widget.LinearLayout
import kotlin.math.roundToInt

internal class HealthAtlasBladderFillingView(activity: Activity, initial: HealthAtlasPhysiology) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val art = FillingDiagram(activity)
    private val playback = HealthAtlasTeachingPlayback(activity,
        R.string.health_atlas_bladder_expansion_play, R.string.health_atlas_bladder_expansion_pause) {
        art.phase = it
    }

    var model = initial
        set(value) {
            require(value.kind == HealthAtlasPhysiologyKind.BLADDER_EXPANSION)
            field = value
            val start = value.input(0)
            val finish = start + value.input(1)
            art.setVolumes(start, finish)
            playback.showTarget(if (start < finish) 1800L else 0L)
        }

    init {
        orientation = VERTICAL
        ui.add(this, ui.line().apply {
            addView(ui.text(context.getString(R.string.health_atlas_bladder_expansion_caption), 14f, bold = true),
                LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
            addView(playback.button.apply { tag = "atlas-bladder-filling-play" })
        })
        ui.add(this, art)
        model = initial
    }

    override fun onDetachedFromWindow() {
        playback.pause()
        super.onDetachedFromWindow()
    }

    private class FillingDiagram(context: Context) : View(context) {
        private val brush = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            strokeCap = Paint.Cap.ROUND
            textAlign = Paint.Align.CENTER
        }
        private val shape = Path()
        private val ink = context.getColor(R.color.text_primary)
        private val wall = 0xffac727c.toInt()
        private val lining = 0xfff0b6b4.toInt()
        private val gold = 0xffbe8a47.toInt()
        private var startMl = 100.0
        private var endMl = 200.0

        var phase = 1f
            set(value) { field = value; invalidate() }

        init {
            tag = "atlas-bladder-filling-diagram"
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }

        fun setVolumes(start: Double, finish: Double) {
            startMl = start
            endMl = finish
            contentDescription = context.getString(R.string.health_atlas_bladder_expansion_description,
                HealthAtlasPhysiologyText.number(start, 0), HealthAtlasPhysiologyText.number(finish, 0))
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val available = MeasureSpec.getSize(widthMeasureSpec)
            val target = minOf((available * .50f).roundToInt(), (180 * resources.displayMetrics.density).roundToInt())
            setMeasuredDimension(available, resolveSize(target, heightMeasureSpec))
        }

        override fun onDraw(canvas: Canvas) {
            val scale = minOf(width / 340f, height / 156f)
            if (scale <= 0f) return
            canvas.save()
            canvas.translate((width - 340 * scale) / 2, (height - 156 * scale) / 2)
            canvas.scale(scale, scale)
            val currentMl = startMl + (endMl - startMl) * phase
            chamber(canvas, 83f, startMl)
            chamber(canvas, 257f, currentMl)
            brush.color = gold
            brush.strokeWidth = 2f
            canvas.drawLine(155f, 67f, 183f, 67f, brush)
            canvas.drawLine(183f, 67f, 176f, 62f, brush)
            canvas.drawLine(183f, 67f, 176f, 72f, brush)
            label(canvas, R.string.health_atlas_bladder_expansion_before, 83f, startMl)
            label(canvas, R.string.health_atlas_bladder_expansion_current, 257f, currentMl)
            canvas.restore()
        }

        private fun chamber(canvas: Canvas, x: Float, volumeMl: Double) {
            val relativeRadius = (HealthAtlasBladderExpansionTeachingModel.radiusCm(volumeMl) /
                HealthAtlasBladderExpansionTeachingModel.radiusCm(HealthAtlasBladderExpansionTeachingModel.MAX_FINAL_VOLUME)).toFloat()
            val halfWidth = 61f * relativeRadius
            val top = 102f - 92f * relativeRadius
            shape.rewind()
            shape.moveTo(x - 5, 118f)
            shape.lineTo(x - 6, 105f)
            shape.cubicTo(x - halfWidth * .47f, 99f, x - halfWidth, 86f, x - halfWidth, 58f)
            shape.cubicTo(x - halfWidth, top - 2, x + halfWidth, top - 2, x + halfWidth, 58f)
            shape.cubicTo(x + halfWidth, 86f, x + halfWidth * .47f, 99f, x + 6, 105f)
            shape.lineTo(x + 5, 118f)
            shape.close()
            brush.shader = LinearGradient(x, top, x, 118f, 0xffffe8b3.toInt(), 0xffd5a26c.toInt(), Shader.TileMode.CLAMP)
            canvas.drawPath(shape, brush)
            brush.shader = null
            brush.style = Paint.Style.STROKE
            brush.strokeWidth = 8f
            brush.color = wall
            canvas.drawPath(shape, brush)
            brush.color = lining
            brush.strokeWidth = 3.8f
            canvas.drawPath(shape, brush)
            brush.style = Paint.Style.FILL
        }

        private fun label(canvas: Canvas, title: Int, x: Float, volumeMl: Double) {
            brush.textSize = 12f
            brush.color = ink
            canvas.drawText(context.getString(title), x, 134f, brush)
            canvas.drawText(HealthAtlasPhysiologyText.number(volumeMl, 0) + " mL", x, 149f, brush)
        }
    }
}
