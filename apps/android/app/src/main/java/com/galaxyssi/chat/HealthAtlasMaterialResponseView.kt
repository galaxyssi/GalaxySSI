package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import kotlin.math.roundToInt

internal class HealthAtlasMaterialResponseView(context: Context, initial: HealthAtlasPhysiology) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        strokeCap = Paint.Cap.ROUND
        textAlign = Paint.Align.CENTER
    }
    private val diffusion = initial.kind == HealthAtlasPhysiologyKind.ALVEOLAR_DIFFUSION
    private val labels = if (diffusion) listOf(R.string.health_atlas_diffusion_air,
        R.string.health_atlas_diffusion_barrier, R.string.health_atlas_diffusion_blood)
    else listOf(R.string.health_atlas_compression_unloaded, R.string.health_atlas_compression_loaded)
    private val guide = if (diffusion) R.string.health_atlas_diffusion_diagram else R.string.health_atlas_compression_diagram
    private val ink = context.getColor(R.color.text_primary)
    private val blue = 0xff3a778f.toInt()
    private val teal = 0xff3f7770.toInt()
    private val rose = 0xffb6757f.toInt()

    var model = initial
        set(value) {
            require(value.kind == field.kind)
            field = value
            contentDescription = context.getString(guide) + ". " + HealthAtlasPhysiologyText.result(context, value) +
                "; " + HealthAtlasPhysiologyText.companion(context, value)
            invalidate()
        }

    init {
        require(diffusion || initial.kind == HealthAtlasPhysiologyKind.CARTILAGE_COMPRESSION)
        tag = if (diffusion) "atlas-diffusion-layer" else "atlas-cartilage-compression"
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        model = initial
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val available = MeasureSpec.getSize(widthMeasureSpec)
        val targetHeight = minOf((available * .51f).roundToInt(), (170 * resources.displayMetrics.density).roundToInt())
        setMeasuredDimension(available, resolveSize(targetHeight, heightMeasureSpec))
    }

    override fun onDraw(canvas: Canvas) {
        val scale = minOf(width / 340f, height / 156f)
        if (scale <= 0f) return
        canvas.save()
        canvas.translate((width - 340 * scale) / 2, (height - 156 * scale) / 2)
        canvas.scale(scale, scale)
        if (diffusion) drawExchange(canvas) else drawCartilage(canvas)
        canvas.restore()
    }

    private fun drawExchange(c: Canvas) {
        val halfThickness = (13f * model.input(2)).toFloat()
        val extent = (40f * model.input(1)).toFloat()
        val top = 79f - extent / 2
        val bottom = 79f + extent / 2
        val left = 170f - halfThickness
        val right = 170f + halfThickness
        rectangle(c, 20f, 36f, left, 122f, 0xffdaeef4.toInt())
        rectangle(c, right, 36f, 320f, 122f, 0xfff5dcdf.toInt())
        rectangle(c, left - 2, top, right + 2, bottom, 0xffd4e8db.toInt())
        line(c, left, top, left, bottom, teal, 3f)
        line(c, right, top, right, bottom, rose, 3f)
        for (i in 0..5) {
            val y = top + (bottom - top) * (i + .5f) / 6
            oval(c, left + 1, y - 3, left + 6, y + 3, teal)
        }
        repeat(4) { i ->
            val x = 227f + i * 19
            val y = if (i % 2 == 0) 55f else 106f
            oval(c, x - 7, y - 4, x + 7, y + 4, 0xffc47f87.toInt())
            oval(c, x - 4, y - 1.5f, x + 4, y + 1.5f, 0xffefb0ae.toInt())
        }
        val transfers = if (model.result == 0.0) 0 else (1.0 + model.result).roundToInt().coerceIn(1, 6)
        repeat(transfers) { i ->
            val y = top + (i + 1) * extent / (transfers + 1)
            val from = left - 32f
            val to = right + 27f
            arrow(c, from, y, to, y, blue, 1.25f + .14f * model.result.toFloat())
            oval(c, from - 8, y - 2.7f, from - 2, y + 2.7f, blue)
        }
        label(c, labels[0], 74f, 145f, 116f)
        label(c, labels[1], 170f, 145f, 64f)
        label(c, labels[2], 264f, 145f, 116f)
    }

    private fun drawCartilage(c: Canvas) {
        fun section(x: Float, strain: Float) {
            val top = 62 + strain * 1.85f
            rectangle(c, x, 106f, x + 126, 126f, 0xffe5c9ae.toInt(), 4f)
            for (i in 0..8) {
                val y = if (i % 2 == 0) 116f else 119f
                line(c, x + 9 + i * 13, y + 1, x + 17 + i * 13, y - 3, 0xffb7987a.toInt(), 1.6f)
            }
            rectangle(c, x, top, x + 126, 109f, 0xffadd6c9.toInt(), 8f)
            line(c, x + 9, top + 2, x + 117, top + 2, teal, 2.4f)
            for (i in 0..8) {
                val px = x + 13 + (i % 5) * 24 + if (i > 4) 8 else 0
                val py = top + if (i < 5) (109 - top) * .34f else (109 - top) * .73f
                oval(c, px - 3.2f, py - 2.3f, px + 3.2f, py + 2.3f, 0xff4c8b82.toInt())
            }
        }
        section(24f, 0f)
        section(190f, model.result.toFloat())
        val stress = model.input(0).toFloat() / 64
        if (stress > 0f) for (x in listOf(211f, 253f, 295f)) {
            val y = 57f + model.result.toFloat() * 1.85f
            arrow(c, x, y - (10 + 25 * stress), x, y, 0xffa8613f.toInt(), 1.1f + stress * 1.7f)
        }
        label(c, labels[0], 87f, 146f, 126f)
        label(c, labels[1], 253f, 146f, 126f)
    }

    private fun rectangle(c: Canvas, left: Float, top: Float, right: Float, bottom: Float, color: Int, radius: Float = 10f) {
        paint.color = color
        c.drawRoundRect(left, top, right, bottom, radius, radius, paint)
    }

    private fun oval(c: Canvas, left: Float, top: Float, right: Float, bottom: Float, color: Int) {
        paint.color = color
        c.drawOval(left, top, right, bottom, paint)
    }

    private fun line(c: Canvas, x1: Float, y1: Float, x2: Float, y2: Float, color: Int, thickness: Float) {
        paint.color = color
        paint.strokeWidth = thickness
        c.drawLine(x1, y1, x2, y2, paint)
    }

    private fun arrow(c: Canvas, x1: Float, y1: Float, x2: Float, y2: Float, color: Int, thickness: Float) {
        line(c, x1, y1, x2, y2, color, thickness)
        val horizontal = y1 == y2
        c.drawPath(Path().apply {
            if (horizontal) {
                moveTo(x2 + 2, y2)
                lineTo(x2 - 6, y2 - 4)
                lineTo(x2 - 6, y2 + 4)
            } else {
                moveTo(x2, y2 + 2)
                lineTo(x2 - 4, y2 - 6)
                lineTo(x2 + 4, y2 - 6)
            }
            close()
        }, paint)
    }

    private fun label(c: Canvas, resource: Int, x: Float, y: Float, available: Float) {
        val text = context.getString(resource)
        paint.color = ink
        paint.textSize = 13f
        val natural = paint.measureText(text)
        if (natural > available) paint.textSize *= available / natural
        c.drawText(text, x, y, paint)
    }
}
