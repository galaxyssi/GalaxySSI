package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

internal object HealthAtlasInsulinDiagram {
    const val FUSION_START = .54f
    fun potassiumOpen(t: Float) = 1f - ease(interval(t, .04f, .68f))
    fun relativeDepolarization(t: Float) = ease(interval(t, .19f, .85f))
    fun calciumOpen(t: Float) = ease(interval(t, .04f, .34f))
    fun approach(t: Float) = ease(interval(t, 0f, FUSION_START))
    fun aperture(t: Float) = ease(interval(t, FUSION_START, .72f))
    fun release(t: Float, index: Int) = interval(t, .60f + .075f * index, .90f + .04f * index)

    private fun interval(t: Float, start: Float, end: Float) = ((t - start) / (end - start)).coerceIn(0f, 1f)
    private fun ease(t: Float) = t * t * (3f - 2f * t)
}

internal class HealthAtlasInsulinStoryView(context: Context) :
    HealthAtlasFunctionArt(context, HealthAtlasFunctionStory.INSULIN_SECRETION) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    }
    private val stageBox = RectF(0f, 0f, 360f, 360f)
    private val line = Path()
    private val membraneTrace = Path()
    private val point = FloatArray(2)
    private val paper = gradient(0f, 360f, 0xffe6f3f6, 0xfffbf0de)
    private val cytosol = gradient(123f, 354f, 0xfff5e6dd, 0xffeed7c7)
    private val mitochondrion = gradient(162f, 243f, 0xfff2bcb1, 0xffb97583)
    private val granuleShell = gradient(-35f, 35f, 0xffdeebec, 0xff83aeba)
    private val membrane = 0xff9e7662
    private val cream = 0xfff9efdc
    private val glucose = 0xffb07a25
    private val energy = 0xff91653a
    private val potassium = 0xff875387
    private val calcium = 0xff287c72
    private val insulin = 0xff397eaa
    private val ink = 0xff25474f
    private val islet by lazy { requireNotNull(context.getDrawable(R.drawable.health_atlas_digestive_islet)).mutate() }
    private val bloodRoute = PathMeasure(Path().apply {
        moveTo(190f, 111f); quadTo(188f, 133f, 189f, 149f)
        quadTo(222f, 157f, 242f, 126f); quadTo(270f, 91f, 320f, 101f)
    }, false)

    init { tag = "atlas-function-insulin-secretion-art" }

    override fun onDraw(c: Canvas) {
        val scale = minOf(width, height) / 360f
        if (scale <= 0f) return
        val chapter = story.chapter(phase)
        val t = story.fraction(phase)
        c.save()
        c.translate((width - 360f * scale) / 2f, (height - 360f * scale) / 2f)
        c.scale(scale, scale)
        brush(cream); paint.shader = paper; c.drawRoundRect(stageBox, 8f, 8f, paint); paint.shader = null
        when (chapter) {
            0 -> glucoseEntry(c, t)
            1 -> potassiumGate(c, t)
            2 -> calciumGate(c, t)
            3 -> granuleRelease(c, t)
            else -> bloodTransport(c, t)
        }
        c.restore()
    }

    private fun glucoseEntry(c: Canvas, t: Float) {
        cellCutaway(c, 129f, gate = 116f)
        channel(c, 116f, 129f, glucose, 1f)
        label(c, 86f, 57f, R.string.health_atlas_insulin_art_glucose)
        leader(c, 260f, 88f, 139f, 124f, R.string.health_atlas_insulin_art_transporter, glucose)
        for (i in 0..4) {
            val f = wrap(t * 1.06f + i / 5f)
            val x = 116f + 14f * sin(6.2f * f) * if (f > .50f) 1.4f else 1f
            sugar(c, x, 75f + 110f * f)
        }
        drawMitochondrion(c)
        for (i in 0..3) {
            val f = wrap(t * 1.51f + i / 4f)
            particle(c, 218f + 45f * f, 216f + (i - 1.5f) * (3f + 7f * f), energy, 3f)
        }
        label(c, 227f, 283f, R.string.health_atlas_insulin_art_energy)
    }

    private fun potassiumGate(c: Canvas, t: Float) {
        cellCutaway(c, 146f, gate = 182f)
        val open = HealthAtlasInsulinDiagram.potassiumOpen(t)
        channel(c, 182f, 146f, potassium, open)
        label(c, 84f, 79f, R.string.health_atlas_insulin_art_potassium)
        label(c, 250f, 61f, if (open >= .4f) R.string.health_atlas_insulin_art_k_open else R.string.health_atlas_insulin_art_k_closed)
        for (i in 0..4) {
            val f = wrap(t * (1.15f + open * .25f) + i / 5f)
            val y = if (i < (open - .4f) / .6f * 5f) 222f - 132f * f else 185f + f * 52f
            val x = 182f + if (y in 126f..165f) 0f else (i - 2) * 10f
            particle(c, x, y, potassium, 4f)
        }
        for (i in 0..3) particle(c, 238f + 51f * wrap(t * 1.2f + i / 4f), 202f + i * 10f, energy, 3f)
        label(c, 243f, 264f, R.string.health_atlas_insulin_art_energy)
        potassiumTrace(c, t)
    }

    private fun potassiumTrace(c: Canvas, t: Float) {
        brush(0xfffaf5ed)
        c.drawRoundRect(20f, 277f, 340f, 350f, 8f, 8f, paint)
        brush(0xffd9c6b7, 1f)
        c.drawRoundRect(20f, 277f, 340f, 350f, 8f, 8f, paint)
        label(c, 80f, 296f, R.string.health_atlas_insulin_art_k_opening)
        label(c, 275f, 296f, R.string.health_atlas_insulin_art_voltage)
        for ((colour, trace) in listOf(
            potassium to HealthAtlasInsulinDiagram::potassiumOpen,
            calcium to HealthAtlasInsulinDiagram::relativeDepolarization,
        )) {
            val x = if (colour == potassium) 80f else 275f
            brush(colour, 2f)
            c.drawLine(x - 12f, 302f, x + 12f, 302f, paint)
            val yAt: (Float) -> Float = { 338f - 26f * trace(it) }
            shape {
                moveTo(39f, yAt(0f))
                for (i in 1..24) {
                    val f = t * i / 24f
                    lineTo(39f + 282f * f, yAt(f))
                }
            }
            c.drawPath(line, paint)
            particle(c, 39f + 282f * t, yAt(t), colour, 3.2f)
        }
    }

    private fun calciumGate(c: Canvas, t: Float) {
        cellCutaway(c, 146f, gate = 182f)
        val open = HealthAtlasInsulinDiagram.calciumOpen(t)
        channel(c, 182f, 146f, calcium, open)
        label(c, 83f, 72f, R.string.health_atlas_insulin_art_calcium)
        leader(c, 259f, 58f, 205f, 142f, R.string.health_atlas_insulin_art_ca_gate, calcium)
        for (i in 0..6) {
            val f = wrap(t * 1.34f + i / 7f)
            val passage = .38f + .59f * open
            val y = 87f + 153f * minOf(f, passage)
            val spread = if (y <= 163f) 0f else (y - 163f) * .29f
            val x = 182f + (i - 3) * spread / 4f
            if (open > .67f || y < 127f) particle(c, x, y, calcium, 4.2f)
        }
        for (i in 0..2) {
            val radius = 13f + 10f * wrap(t * 1.65f + i / 3f)
            if (open > .64f) {
                brush(0x84287c72, 1.2f)
                c.drawOval(182f - radius, 193f - radius / 2f, 182f + radius, 193f + radius / 2f, paint)
            }
        }
    }

    private fun granuleRelease(c: Canvas, t: Float) {
        val aperture = HealthAtlasInsulinDiagram.aperture(t)
        cellCutaway(c, 141f, aperture)
        val centerY = 239f - 64f * HealthAtlasInsulinDiagram.approach(t)
        if (aperture < .09f) {
            c.save()
            c.translate(180f, centerY)
            brush(cream); paint.shader = granuleShell; c.drawCircle(0f, 0f, 31f, paint); paint.shader = null
            brush(insulin, 1.5f); c.drawCircle(0f, 0f, 31f, paint)
            insulinMolecule(c, 0f, 0f, 1f)
            c.restore()
        } else {
            for (i in 0..2) {
                val f = HealthAtlasInsulinDiagram.release(t, i)
                val x = 180f + (i - 1) * 37f * f
                insulinMolecule(c, x, 177f - 94f * f, .54f)
            }
        }
        for (i in 0..4) {
            val f = wrap(t * 1.5f + i * .2f)
            particle(c, 114f + 14f * f + i * 4f, 187f + i * 9f + f * 5f, calcium, 3.1f)
        }
        label(c, 265f, 55f, R.string.health_atlas_insulin_art_hormone)
        leader(c, 192f, 286f, 190f, centerY + (if (t < .54f) 22f else 10f),
            R.string.health_atlas_insulin_art_granule, insulin)
    }

    private fun bloodTransport(c: Canvas, t: Float) {
        c.save()
        c.translate(0f, 47f)
        islet.setBounds(0, 0, 360, 280)
        islet.draw(c)
        for (i in 0..5) {
            val f = wrap(t * 1.1f + i / 6f)
            if (bloodRoute.getPosTan(f * bloodRoute.length, point, null)) insulinMolecule(c, point[0], point[1], .32f)
        }
        c.restore()
        leader(c, 154f, 65f, 184f, 126f, R.string.health_atlas_insulin_art_beta, calcium)
        leader(c, 273f, 259f, 251f, 162f, R.string.health_atlas_insulin_art_capillary, membrane)
        insulinMolecule(c, 126f, 316f, .55f)
        label(c, 179f, 321f, R.string.health_atlas_insulin_art_hormone)
    }

    private fun cellCutaway(c: Canvas, y: Float, pore: Float = 0f, gate: Float? = null) {
        shape {
            moveTo(23f, y); lineTo(145f, y)
            if (pore > 0f) {
                val width = 5f + 20f * pore
                lineTo(180f - width, y)
                cubicTo(178f - width, y + 12f, 147f, y + 44f, 180f, y + 55f)
                cubicTo(213f, y + 44f, 182f + width, y + 12f, 180f + width, y)
            }
            lineTo(337f, y)
        }
        brush(cream)
        membraneTrace.set(line)
        line.lineTo(337f, 323f); line.quadTo(336f, 343f, 315f, 343f)
        line.lineTo(45f, 343f); line.quadTo(24f, 343f, 23f, 323f); line.close()
        paint.shader = cytosol; c.drawPath(line, paint); paint.shader = null
        c.save()
        gate?.let { c.clipOutRect(it - 18f, y - 8f, it + 18f, y + 8f) }
        brush(membrane, 8f); c.drawPath(membraneTrace, paint)
        brush(0xffecc6a0, 5.5f); c.drawPath(membraneTrace, paint)
        for (x in 28..330 step 11) if (pore == 0f || x !in 147..216) {
            circle(c, x.toFloat(), y - 3f, 1.2f, cream)
            circle(c, x.toFloat(), y + 3f, 1.2f, 0xffc39776)
        }
        c.restore()
        label(c, 75f, 28f, R.string.health_atlas_insulin_art_outside)
        label(c, 79f, 321f, R.string.health_atlas_insulin_art_inside)
    }

    private fun channel(c: Canvas, x: Float, y: Float, colour: Long, open: Float) {
        val spread = 4f + 8f * open
        for (direction in listOf(-1, 1)) {
            val cx = x + direction * (8f + spread)
            brush(colour)
            c.drawRoundRect(cx - 8f, y - 20f, cx + 8f, y + 19f, 7f, 7f, paint)
            brush(cream, 1.4f)
            c.drawLine(cx - 2f, y - 11f, cx - 2f, y + 10f, paint)
        }
        if (open < .40f) {
            brush(colour, 4f); c.drawLine(x - spread, y, x + spread, y, paint)
        }
    }

    private fun drawMitochondrion(c: Canvas) {
        shape {
            moveTo(142f, 211f); cubicTo(136f, 187f, 171f, 175f, 193f, 179f)
            cubicTo(225f, 184f, 221f, 206f, 206f, 224f)
            cubicTo(192f, 243f, 151f, 239f, 142f, 211f); close()
        }
        brush(cream); paint.shader = mitochondrion; c.drawPath(line, paint); paint.shader = null
        brush(0xff96576c, 1.8f); c.drawPath(line, paint)
        shape {
            moveTo(148f, 210f); cubicTo(173f, 207f, 154f, 189f, 169f, 192f)
            cubicTo(185f, 195f, 168f, 223f, 181f, 225f)
            cubicTo(193f, 225f, 186f, 188f, 199f, 193f); quadTo(205f, 196f, 204f, 209f)
        }
        brush(0xfff3d0cc, 2.8f); c.drawPath(line, paint)
    }

    private fun sugar(c: Canvas, x: Float, y: Float) {
        shape {
            for (i in 0..5) {
                val angle = i * PI.toFloat() / 3f
                val px = x + 5.7f * cos(angle)
                val py = y + 5.7f * sin(angle)
                if (i == 0) moveTo(px, py) else lineTo(px, py)
            }
            close()
        }
        brush(0xfff0ca7f); c.drawPath(line, paint)
        brush(glucose, 1.1f); c.drawPath(line, paint)
    }

    private fun insulinMolecule(c: Canvas, x: Float, y: Float, scale: Float) {
        for (i in 0..4) {
            val a = i * 2f * PI.toFloat() / 5f
            val cx = x + 7f * scale * cos(a)
            val cy = y + 6f * scale * sin(a)
            circle(c, cx, cy, 4.4f * scale, insulin)
            circle(c, cx - scale, cy - scale, 2.0f * scale, 0xffb3dceb)
        }
    }

    private fun leader(c: Canvas, x: Float, y: Float, tx: Float, ty: Float, res: Int, colour: Long) {
        brush(colour, 1.2f)
        c.drawLine(x, if (ty < y) y - 16f else y + 6f, tx, ty, paint)
        particle(c, tx, ty, colour, 2.4f)
        label(c, x, y, res)
    }

    private fun label(c: Canvas, x: Float, y: Float, res: Int) {
        brush(ink)
        val value = context.getString(res)
        paint.textSize = 13f
        val available = 2f * minOf(x - 8f, 352f - x)
        val width = paint.measureText(value)
        if (width > available) paint.textSize *= available / width
        c.drawText(value, x, y, paint)
    }

    private fun particle(c: Canvas, x: Float, y: Float, colour: Long, radius: Float) {
        circle(c, x, y, radius + .7f, cream)
        circle(c, x, y, radius, colour)
    }
    private fun circle(c: Canvas, x: Float, y: Float, radius: Float, colour: Long) {
        brush(colour); c.drawCircle(x, y, radius, paint)
    }
    private fun brush(colour: Long, width: Float = 0f) {
        paint.color = colour.toInt()
        paint.style = if (width == 0f) Paint.Style.FILL else Paint.Style.STROKE
        paint.strokeWidth = width
    }
    private inline fun shape(build: Path.() -> Unit) { line.rewind(); line.build() }
    private fun wrap(t: Float) = t % 1f
    private fun gradient(y0: Float, y1: Float, a: Long, b: Long) =
        LinearGradient(0f, y0, 0f, y1, a.toInt(), b.toInt(), Shader.TileMode.CLAMP)
}
