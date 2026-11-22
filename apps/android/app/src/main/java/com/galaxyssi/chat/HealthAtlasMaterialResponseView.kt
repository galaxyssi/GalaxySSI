package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

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
        HealthAtlasPhysiologyKind.DIAPHRAGM_DISPLACEMENT -> R.string.health_atlas_diaphragm_demo_diagram
        HealthAtlasPhysiologyKind.ARTERIAL_CONTINUITY -> R.string.health_atlas_arterial_continuity_diagram
        HealthAtlasPhysiologyKind.AIRWAY_CILIARY_CLEARANCE -> R.string.health_atlas_airway_ciliary_clearance_diagram
        HealthAtlasPhysiologyKind.CORNEAL_REFRACTION -> R.string.health_atlas_model_corneal_refraction_diagram
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
            HealthAtlasPhysiologyKind.DIAPHRAGM_DISPLACEMENT -> "atlas-diaphragm-displacement"
            HealthAtlasPhysiologyKind.ARTERIAL_CONTINUITY -> "atlas-arterial-continuity"
            HealthAtlasPhysiologyKind.AIRWAY_CILIARY_CLEARANCE -> "atlas-airway-cilia-track"
            HealthAtlasPhysiologyKind.CORNEAL_REFRACTION -> "atlas-corneal-rays"
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
            HealthAtlasPhysiologyKind.DIAPHRAGM_DISPLACEMENT -> drawDiaphragm(canvas)
            HealthAtlasPhysiologyKind.ARTERIAL_CONTINUITY -> drawArterialContinuity(canvas)
            HealthAtlasPhysiologyKind.AIRWAY_CILIARY_CLEARANCE -> drawCiliaTrack(canvas)
            HealthAtlasPhysiologyKind.CORNEAL_REFRACTION -> drawRefraction(canvas)
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

    private fun drawDiaphragm(c: Canvas) {
        val halfWidth = 108f * sqrt(model.input(1).toFloat() / 250f)
        val left = 170f - halfWidth
        val right = 170f + halfWidth
        val rest = 88f
        val shift = model.input(0).toFloat() * 1.1f
        val current = rest + shift
        fun dome(y: Float) = Path().apply {
            moveTo(left, y)
            cubicTo(left + halfWidth * .58f, y - 29f, right - halfWidth * .58f, y - 29f, right, y)
        }
        val chest = Path().apply {
            moveTo(left, current)
            cubicTo(left, 77f, left - 8f, 37f, left + 14f, 29f)
            cubicTo(139f, 1f, 201f, 1f, right - 14f, 29f)
            cubicTo(right + 8f, 37f, right, 77f, right, current)
        }
        val gain = Path().apply {
            addPath(dome(rest))
            lineTo(right, current)
            cubicTo(right - halfWidth * .58f, current - 29f, left + halfWidth * .58f, current - 29f, left, current)
            close()
        }
        paint.color = 0xffdeeeef.toInt()
        val chamber = Path(chest).apply {
            cubicTo(right - halfWidth * .58f, current - 29f, left + halfWidth * .58f, current - 29f, left, current)
            close()
        }
        c.drawPath(chamber, paint)
        if (shift > 0f) {
            paint.color = 0xffa7d7c9.toInt()
            c.drawPath(gain, paint)
        }
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2.5f
        paint.color = blue
        c.drawPath(chest, paint)
        val dashes = DashPathEffect(floatArrayOf(6f, 4f), 0f)
        paint.pathEffect = dashes
        c.drawPath(dome(rest), paint)
        paint.pathEffect = null
        paint.color = teal
        paint.strokeWidth = 3.5f
        c.drawPath(dome(current), paint)
        paint.style = Paint.Style.FILL
        if (shift >= 8f) arrow(c, 170f, rest - 21f, 170f, current - 23f, teal, 2f)
        paint.pathEffect = dashes
        line(c, 35f, 143f, 57f, 143f, blue, 2f)
        paint.pathEffect = null
        line(c, 184f, 143f, 206f, 143f, teal, 3f)
        label(c, R.string.health_atlas_diaphragm_demo_resting, 111f, 147f, 98f)
        label(c, R.string.health_atlas_diaphragm_demo_current, 261f, 147f, 98f)
    }

    private fun drawArterialContinuity(c: Canvas) {
        val x = 77f
        val y = 67f
        val radius = model.input(0).toFloat() * 1.15f
        val speed = (model.result / model.kind.maximum).toFloat()
        val outer = radius + 8f
        oval(c, x - outer, y - outer, x + outer, y + outer, 0xffba8290.toInt())
        oval(c, x - radius, y - radius, x + radius, y + radius, 0xffefc8cb.toInt())
        line(c, x - radius, y, x + radius, y, 0xff775565.toInt(), 1.7f)
        repeat(2) {
            val edge = if (it == 0) x - radius else x + radius
            line(c, edge, y - 4f, edge, y + 4f, 0xff775565.toInt(), 1.7f)
        }
        val start = 156f
        val end = 315f
        line(c, start, y, end, y, 0xffbfd6d7.toInt(), 3f)
        for (mark in 0..4) {
            val tick = start + (end - start) * mark / 4f
            line(c, tick, y - 5f, tick, y + 5f, 0xff759397.toInt(), 1.5f)
        }
        if (speed > 0f) arrow(c, start, y, start + ((end - start) * speed).coerceAtLeast(8f), y, teal, 3.3f)
        else oval(c, start - 3f, y - 3f, start + 3f, y + 3f, teal)
        label(c, R.string.health_atlas_arterial_continuity_section, x, 145f, 134f)
        label(c, R.string.health_atlas_arterial_continuity_speed, (start + end) / 2, 145f, 172f)
    }

    private fun drawCiliaTrack(c: Canvas) {
        val left = 26f
        val right = 314f
        val step = (right - left) / 9
        val marker = left + (right - left) * (model.companionValue.toFloat() / 100f)
        rectangle(c, left - 12, 34f, right + 12, 64f, 0xffd3e8e3.toInt(), 14f)
        repeat(9) { i ->
            val x = left + step * i
            rectangle(c, x + 1, 77f, x + step - 1, 121f, 0xffa4d4cb.toInt(), 8f)
            oval(c, x + 10, 95f, x + 23, 112f, 0xff598788.toInt())
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 1.65f
            paint.color = teal
            repeat(4) { branch ->
                val base = x + 4 + branch * 6
                c.drawPath(Path().apply {
                    moveTo(base, 80f)
                    quadTo(base - 3, 69f, base + 4, if ((i + branch) % 3 == 0) 57f else 60f)
                }, paint)
            }
            paint.style = Paint.Style.FILL
        }
        line(c, left, 49f, right, 49f, 0xff7faaa3.toInt(), 1.6f)
        if (marker - left >= 8f) arrow(c, left, 49f, marker - 2f, 49f, teal, 2.1f)
        oval(c, marker - 6, 43f, marker + 6, 55f, 0xffbc803f.toInt())
        oval(c, marker - 2, 45f, marker + 1, 48f, 0xffffe0a5.toInt())
        label(c, R.string.health_atlas_airway_ciliary_clearance_track, 170f, 145f, 300f)
    }

    private fun drawRefraction(c: Canvas) {
        val x = 170f
        val y = 76f
        val incidentDegrees = model.input(0).toFloat()
        val refractedDegrees = model.result.toFloat()
        val incident = Math.toRadians(incidentDegrees.toDouble())
        val refracted = Math.toRadians(refractedDegrees.toDouble())
        rectangle(c, 16f, y, 324f, 151f, 0xffd5e9ed.toInt(), 5f)
        line(c, 16f, y, 324f, y, blue, 2f)
        paint.pathEffect = DashPathEffect(floatArrayOf(4f, 4f), 0f)
        line(c, x, 11f, x, 144f, 0xff668895.toInt(), 1.4f)
        paint.pathEffect = null

        fun ray(fromX: Float, fromY: Float, dx: Float, dy: Float, length: Float, color: Int) {
            val toX = fromX + dx * length
            val toY = fromY + dy * length
            line(c, fromX, fromY, toX, toY, color, 3f)
            val baseX = toX - 8 * dx
            val baseY = toY - 8 * dy
            c.drawPath(Path().apply {
                moveTo(toX, toY)
                lineTo(baseX - 3.5f * dy, baseY + 3.5f * dx)
                lineTo(baseX + 3.5f * dy, baseY - 3.5f * dx)
                close()
            }, paint)
        }
        val incidentX = sin(incident).toFloat()
        val incidentY = cos(incident).toFloat()
        ray(x - incidentX * 62, y - incidentY * 62, incidentX, incidentY, 62f, 0xffa16629.toInt())
        ray(x, y, sin(refracted).toFloat(), cos(refracted).toFloat(), 62f, teal)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 1.3f
        paint.color = 0xffa16629.toInt()
        c.drawArc(x - 25, y - 25, x + 25, y + 25, -90f - incidentDegrees, incidentDegrees, false, paint)
        paint.color = teal
        c.drawArc(x - 25, y - 25, x + 25, y + 25, 90f - refractedDegrees, refractedDegrees, false, paint)
        paint.style = Paint.Style.FILL
        label(c, R.string.health_atlas_model_corneal_refraction_incident_ray, 65f, 25f, 110f)
        label(c, R.string.health_atlas_model_corneal_refraction_refracted_ray, 258f, 139f, 106f)
        label(c, R.string.health_atlas_model_corneal_refraction_surface, 253f, 65f, 128f)
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
