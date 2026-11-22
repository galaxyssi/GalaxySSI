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
    private val kind = initial.kind
    val diagramDescription = when (kind) {
        HealthAtlasPhysiologyKind.ALVEOLAR_DIFFUSION -> R.string.health_atlas_diffusion_diagram
        HealthAtlasPhysiologyKind.CARTILAGE_COMPRESSION -> R.string.health_atlas_compression_diagram
        HealthAtlasPhysiologyKind.BONE_BENDING -> R.string.health_atlas_bone_bending_diagram
        HealthAtlasPhysiologyKind.CALF_PUMP -> R.string.health_atlas_calf_pump_diagram
        HealthAtlasPhysiologyKind.PELVIC_SUPPORT -> R.string.health_atlas_pelvis_model_diagram
        HealthAtlasPhysiologyKind.CUSHION_CONTACT_PRESSURE -> R.string.health_atlas_cushion_model_diagram
        else -> error("Unexpected material response: $kind")
    }
    private val ink = context.getColor(R.color.text_primary)
    private val blue = 0xff3a778f.toInt()
    private val teal = 0xff3f7770.toInt()
    private val rose = 0xffb6757f.toInt()

    var model = initial
        set(value) {
            require(value.kind == field.kind)
            field = value
            contentDescription = context.getString(diagramDescription) + " " + HealthAtlasPhysiologyText.result(context, value) +
                "; " + HealthAtlasPhysiologyText.companion(context, value)
            invalidate()
        }

    init {
        tag = when (kind) {
            HealthAtlasPhysiologyKind.ALVEOLAR_DIFFUSION -> "atlas-diffusion-layer"
            HealthAtlasPhysiologyKind.CARTILAGE_COMPRESSION -> "atlas-cartilage-compression"
            HealthAtlasPhysiologyKind.BONE_BENDING -> "atlas-bone-bending"
            HealthAtlasPhysiologyKind.CALF_PUMP -> "atlas-calf-pump"
            HealthAtlasPhysiologyKind.PELVIC_SUPPORT -> "atlas-pelvic-support"
            HealthAtlasPhysiologyKind.CUSHION_CONTACT_PRESSURE -> "atlas-cushion-contact"
            else -> error("Unexpected material response: $kind")
        }
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
        when (kind) {
            HealthAtlasPhysiologyKind.ALVEOLAR_DIFFUSION -> drawExchange(canvas)
            HealthAtlasPhysiologyKind.CARTILAGE_COMPRESSION -> drawCartilage(canvas)
            HealthAtlasPhysiologyKind.BONE_BENDING -> drawBone(canvas)
            HealthAtlasPhysiologyKind.CALF_PUMP -> drawCalfPump(canvas)
            HealthAtlasPhysiologyKind.PELVIC_SUPPORT -> drawPelvicSupport(canvas)
            HealthAtlasPhysiologyKind.CUSHION_CONTACT_PRESSURE -> drawCushionContact(canvas)
            else -> Unit
        }
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
        label(c, R.string.health_atlas_diffusion_air, 74f, 145f, 116f)
        label(c, R.string.health_atlas_diffusion_barrier, 170f, 145f, 64f)
        label(c, R.string.health_atlas_diffusion_blood, 264f, 145f, 116f)
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
        label(c, R.string.health_atlas_compression_unloaded, 87f, 146f, 126f)
        label(c, R.string.health_atlas_compression_loaded, 253f, 146f, 126f)
    }

    private fun drawBone(c: Canvas) {
        val centerY = 77f
        val centerX = 91f
        val radius = (model.input(1) * 1.3).toFloat()
        val cavity = radius * model.input(2).toFloat()
        val strength = (model.result / model.kind.maximum).toFloat()
        val ring = Path().apply {
            fillType = Path.FillType.EVEN_ODD
            addCircle(centerX, centerY, radius, Path.Direction.CW)
            addCircle(centerX, centerY, cavity, Path.Direction.CW)
        }
        paint.color = 0xffeed6ab.toInt()
        c.drawPath(ring, paint)
        c.save()
        c.clipPath(ring)
        rectangle(c, centerX - radius, centerY - radius, centerX + radius, centerY,
            (0x00ad6554 or ((125 * strength).roundToInt() shl 24)), 0f)
        rectangle(c, centerX - radius, centerY, centerX + radius, centerY + radius,
            (0x0051869f or ((125 * strength).roundToInt() shl 24)), 0f)
        c.restore()
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2f
        paint.color = 0xffa3896c.toInt()
        c.drawCircle(centerX, centerY, radius, paint)
        c.drawCircle(centerX, centerY, cavity, paint)
        paint.style = Paint.Style.FILL
        for (dx in -5..5) {
            val x = centerX + dx * (radius + 9f) / 5
            line(c, x - 2, centerY, x + 2, centerY, 0xff726e73.toInt(), 1.35f)
        }

        val axis = 244f
        val span = 65f * strength
        val top = centerY - radius
        val bottom = centerY + radius
        fun stressLine(y: Float, offset: Float, fill: Int, border: Int) {
            paint.color = fill
            c.drawPath(Path().apply { moveTo(axis, centerY); lineTo(axis + offset, y); lineTo(axis, y); close() }, paint)
            line(c, axis, centerY, axis + offset, y, border, 2.1f)
        }
        stressLine(top, -span, 0xffefd2c2.toInt(), 0xffa9614c.toInt())
        stressLine(bottom, span, 0xffd7e8ef.toInt(), blue)
        line(c, axis, top - 4, axis, bottom + 4, 0xff7c7476.toInt(), 1.3f)
        label(c, R.string.health_atlas_bone_bending_neutral, centerX, 148f, 136f)
        label(c, R.string.health_atlas_bone_bending_compression, axis - 43, 16f, 125f)
        label(c, R.string.health_atlas_bone_bending_tension, axis + 44, 148f, 94f)
    }

    private fun drawCalfPump(c: Canvas) {
        val stroke = model.input(0).toFloat()
        val total = stroke * model.input(1).toFloat()
        val returning = (total * model.input(2) / 100).toFloat()
        val returnInk = 0xffa66c44.toInt()
        rectangle(c, 43f, 32f, 140f, 122f, 0xffe2eded.toInt(), 18f)
        rectangle(c, 50f, 39f, 133f, 115f, 0xfff3f7f5.toInt(), 14f)
        if (stroke > 0) {
            val top = 115f - 71f * stroke / 25f
            rectangle(c, 53f, top, 130f, 113f, 0xff8ac9ba.toInt(), minOf((113f - top) * .45f, 12f))
        }
        line(c, 39f, 44f, 39f, 111f, rose, 4f)
        line(c, 144f, 44f, 144f, 111f, rose, 4f)
        line(c, 75f, 33f, 91f, 40f, teal, 2.5f)
        line(c, 92f, 40f, 108f, 33f, teal, 2.5f)
        line(c, 75f, 115f, 91f, 122f, teal, 2.5f)
        line(c, 92f, 122f, 108f, 115f, teal, 2.5f)
        line(c, 196f, 54f, 314f, 54f, 0xffc5ded9.toInt(), 7f)
        line(c, 196f, 111f, 314f, 111f, 0xffeedccc.toInt(), 7f)
        if (total > 0) arrow(c, 196f, 54f, 196f + (118f * total / 750).coerceAtLeast(6f), 54f, teal, 3f)
        if (returning > 0) arrow(c, 314f, 111f, 314f - (118f * returning / 750).coerceAtLeast(6f), 111f, returnInk, 3f)
        label(c, R.string.health_atlas_calf_pump_chamber_label, 91f, 145f, 132f)
        label(c, R.string.health_atlas_calf_pump_forward_label, 255f, 72f, 145f)
        label(c, R.string.health_atlas_calf_pump_return_label, 255f, 130f, 145f)
    }

    private fun drawPelvicSupport(c: Canvas) {
        val left = 83f
        val right = 257f
        val span = (right - left) / 2
        val loadX = 170f + span * model.input(1).toFloat() / 100f
        val load = model.input(0).toFloat()
        rectangle(c, 61f, 70f, 279f, 84f, 0xffddc2a7.toInt(), 6f)
        line(c, left, 77f, right, 77f, 0xff9e826c.toInt(), 1.4f)
        oval(c, loadX - 4f, 73f, loadX + 4f, 81f, 0xff926b55.toInt())
        if (load > 0f) arrow(c, loadX, 63f - 42f * load / 800f, loadX, 67f, 0xff996449.toInt(), 3.3f)

        fun support(x: Float, force: Float, caption: Int, color: Int) {
            val base = 121f
            rectangle(c, x - 26f, base, x + 26f, base + 5f, 0xffcbdfdb.toInt(), 2f)
            if (force > 0f) arrow(c, x, base - 3f, x, base - (8f + 23f * force / 800f), color, 3f)
            label(c, caption, x, 147f, 130f)
        }
        support(left, model.companionValue.toFloat(), R.string.health_atlas_pelvis_model_left_support, blue)
        support(right, model.result.toFloat(), R.string.health_atlas_pelvis_model_right_support, teal)
    }

    private fun drawCushionContact(c: Canvas) {
        val force = model.input(0).toFloat()
        fun pad(x: Float, area: Float, pressure: Float, caption: Int) {
            val halfWidth = 10f + 49f * area / 90f
            rectangle(c, x - 63f, 82f, x + 63f, 117f, 0xfff5deb1.toInt(), 7f)
            rectangle(c, x - 63f, 113f, x + 63f, 124f, 0xffb3cec5.toInt(), 4f)
            repeat(7) { i ->
                val centerX = x - 51f + 17f * i
                val centerY = if (i % 2 == 0) 97f else 103f
                oval(c, centerX - 7f, centerY - 7f, centerX + 7f, centerY + 7f, 0xffe5b97d.toInt())
            }
            rectangle(c, x - halfWidth, 67f, x + halfWidth, 80f, 0xffb8d6d5.toInt(), 4f)
            if (force > 0f) {
                arrow(c, x, 56f - 30f * force / 80f, x, 63f, blue, 2.7f)
                val alpha = (60 + 190 * pressure / 80f).roundToInt()
                rectangle(c, x - halfWidth, 80f, x + halfWidth, 85f,
                    0x00a96459 or (alpha shl 24), 2f)
            }
            label(c, caption, x, 147f, 145f)
        }
        pad(85f, 40f, model.companionValue.toFloat(), R.string.health_atlas_cushion_model_standard_pad)
        pad(255f, model.input(1).toFloat(), model.result.toFloat(), R.string.health_atlas_cushion_model_changed_pad)
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
                val direction = if (x2 >= x1) 1f else -1f
                moveTo(x2 + 2 * direction, y2)
                lineTo(x2 - 6 * direction, y2 - 4)
                lineTo(x2 - 6 * direction, y2 + 4)
            } else {
                val direction = if (y2 >= y1) 1f else -1f
                moveTo(x2, y2 + 2 * direction)
                lineTo(x2 - 4, y2 - 6 * direction)
                lineTo(x2 + 4, y2 - 6 * direction)
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
