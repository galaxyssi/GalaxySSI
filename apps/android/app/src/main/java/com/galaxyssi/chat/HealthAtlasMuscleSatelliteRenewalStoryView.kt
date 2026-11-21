package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import androidx.annotation.StringRes
import com.galaxyssi.chat.HealthAtlasMuscleSatelliteRenewalAssignment as Lesson
import com.galaxyssi.chat.R.string

internal class HealthAtlasMuscleSatelliteRenewalStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val fiberTint = shade(202f, 296f, 0xfff5c8ad, 0xffd99b94)
    private val fiberEdge = 0xff8f4e59
    private val laminaEdge = 0xff5e766b
    private val laminaBand = 0xffd7e3c6
    private val reserveEdge = 0xff28675d
    private val reserveFill = 0xff9ccec1
    private val activeFill = 0xffc9e4d7
    private val nucleusInk = 0xff444265
    private val myoblastFill = 0xfff5d39a
    private val myoblastEdge = 0xff966237
    private val myoblastNucleus = 0xff754049
    private val leader = 0xff52686b
    private val fiber = Path()
    private val sarcolemma = Path()
    private val lamina = Path()
    private val profile = Path()
    private val highlight = Path()
    private val measure = PathMeasure()
    private val signalPath = Path().apply {
        moveTo(62f, 117f)
        cubicTo(85f, 110f, 113f, 116f, 139f, 145f)
    }
    private val signalRoute = track(signalPath)

    init { tag = Lesson.ART_TAG }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            Lesson.NICHE -> niche(c, t)
            Lesson.ACTIVATION -> activation(c, t)
            Lesson.DIVISION -> division(c, t)
            Lesson.RENEWAL -> renewal(c, t)
            Lesson.FUSION -> fusion(c, t)
        }
    }

    private fun niche(c: Canvas, t: Float) {
        drawFiber(c)
        drawLamina(c, CELL_X, 41f)
        satellite(c, CELL_X, 184f, 36f, 13f, reserveFill)
        trace(c, lamina, progress(t, 0f, .65f), 0xff336b5b)
        trace(c, sarcolemma, progress(t, .23f, 1f), 0xffa64c59)
        lead(c, string.health_atlas_muscle_satellite_renewal_art_lamina, 87f, 111f, CELL_X, 147f, laminaEdge)
        lead(c, string.health_atlas_muscle_satellite_renewal_art_cell, 265f, 111f, 202f, 177f, reserveEdge)
        lead(c, string.health_atlas_muscle_satellite_renewal_art_sarcolemma, 92f, 326f, 86f, 294f, fiberEdge)
        fiberLabel(c, 261f)
    }

    private fun activation(c: Canvas, t: Float) {
        val state = progress(t, .22f, .88f)
        val y = 184f - 9f * state
        drawFiber(c)
        drawLamina(c, CELL_X, 41f + 12f * state)
        satellite(c, CELL_X, y, 36f + 3f * state, 13f + 11f * state, mix(reserveFill, activeFill, state))
        stroke(c, signalPath, myoblastEdge, .85f)
        for (i in 0..2) {
            val signal = (t - i * .13f) / .58f
            if (signal in 0f..1f) {
                at(signalRoute, signal) { x, yy ->
                    val r = 3f + 2.8f * (1f - signal)
                    profile.rewind()
                    profile.moveTo(x, yy - r)
                    profile.lineTo(x + r, yy)
                    profile.lineTo(x, yy + r)
                    profile.lineTo(x - r, yy)
                    profile.close()
                    ink(myoblastFill)
                    c.drawPath(profile, paint)
                    stroke(c, profile, myoblastEdge, 1.15f)
                }
            }
        }
        label(c, string.health_atlas_muscle_satellite_renewal_art_signals, 101f, 95f, 150f)
        val cellLabel = if (state < .45f) string.health_atlas_muscle_satellite_renewal_art_cell
            else string.health_atlas_muscle_satellite_renewal_art_active
        lead(c, cellLabel, 263f, 95f, 200f, y - 8f, reserveEdge)
        fiberLabel(c, 180f)
    }

    private fun division(c: Canvas, t: Float) {
        val y = 175f - 11f * progress(t, 0f, .66f)
        val pinch = progress(t, .12f, .75f)
        val apart = progress(t, .75f, .97f)
        drawFiber(c)
        drawLamina(c, CELL_X, 53f + 14f * pinch, span = 65f + 42f * pinch)
        if (t < .75f) {
            val offset = 9f + 21f * pinch
            val rx = 30f
            val ry = 24f - 2f * pinch
            val neck = ry * (1f - pinch)
            // Two lobes share one membrane until the waist closes.
            profile.rewind()
            profile.moveTo(CELL_X - offset - rx, y)
            for (direction in 1 downTo -1 step 2) {
                val dy = -ry * direction
                val waistY = y - neck * direction
                val from = CELL_X - offset * direction
                val to = CELL_X + offset * direction
                profile.cubicTo(from - 28f * direction, y + dy * .72f, from - 16f * direction, y + dy, from, y + dy)
                profile.cubicTo(from + .62f * offset * direction, y + dy, CELL_X - 5f * direction, waistY, CELL_X, waistY)
                profile.cubicTo(CELL_X + 5f * direction, waistY, to - .62f * offset * direction, y + dy, to, y + dy)
                profile.cubicTo(to + 16f * direction, y + dy, to + 28f * direction, y + dy * .72f, to + rx * direction, y)
            }
            profile.close()
            paintCell(c, activeFill, reserveEdge)
            val separation = 30f * progress(t, .12f, .7f)
            ovalNucleus(c, CELL_X - separation, y, 10f, 8f, nucleusInk)
            if (separation > 0f) ovalNucleus(c, CELL_X + separation, y, 10f, 8f, nucleusInk)
        } else {
            val offset = 30f + 8f * apart
            satellite(c, CELL_X - offset, y, 30f - 3f * apart, 22f - 1f * apart, activeFill)
            satellite(c, CELL_X + offset, y, 30f - 3f * apart, 22f - 1f * apart, activeFill)
        }
        label(c, if (t < .75f) string.health_atlas_muscle_satellite_renewal_art_division
            else string.health_atlas_muscle_satellite_renewal_art_daughters, CELL_X, 100f, 170f)
        fiberLabel(c, 180f)
    }

    private fun renewal(c: Canvas, t: Float) {
        val settle = progress(t, .06f, .88f)
        val left = 142f - 35f * settle
        val right = 218f + 29f * settle
        val leftY = 164f + 20f * settle
        val rightY = 164f + 9f * settle
        drawFiber(c)
        drawBranchLamina(c, left, right, 127f + 18f * settle, 127f + 12f * settle)
        satellite(c, left, leftY, 27f + 7f * settle, 21f - 8f * settle, mix(activeFill, reserveFill, settle))
        myoblast(c, right, rightY, settle)
        lead(c, string.health_atlas_muscle_satellite_renewal_art_reserve, 91f, 96f, left, leftY - 10f, reserveEdge)
        lead(c, string.health_atlas_muscle_satellite_renewal_art_myoblast, 266f, 96f, right, rightY - 11f, myoblastEdge)
        fiberLabel(c, 180f)
    }

    private fun fusion(c: Canvas, t: Float) {
        val approach = progress(t, 0f, .43f)
        val merge = progress(t, .43f, .93f)
        val membraneRise = if (t < .43f) 0f else 30f * (1f - merge)
        drawFiber(c, membraneRise)
        drawLamina(c, RESERVE_X, 43f, FUSION_X, 54f * (1f - merge), span = 54f)
        satellite(c, RESERVE_X, 184f, 34f, 13f, reserveFill)
        if (t < .43f) {
            myoblast(c, FUSION_X, 173f + 15f * approach, 1f)
        } else {
            val y = 188f + 34f * merge
            ovalNucleus(c, FUSION_X, y, 12f, 5.5f, myoblastNucleus, myoblastFill)
            lead(c, string.health_atlas_muscle_satellite_renewal_art_nucleus, 265f, 326f, FUSION_X, y + 7f, myoblastEdge)
        }
        lead(c, string.health_atlas_muscle_satellite_renewal_art_reserve, 89f, 96f, RESERVE_X, 174f, reserveEdge)
        lead(c, string.health_atlas_muscle_satellite_renewal_art_fusion, 267f, 96f, FUSION_X + 25f,
            if (t < .43f) 169f + 22f * approach else TOP - .45f * membraneRise, myoblastEdge)
        fiberLabel(c, 90f)
    }

    private fun drawFiber(c: Canvas, rise: Float = 0f) {
        sarcolemma.rewind()
        sarcolemma.moveTo(50f, TOP)
        if (rise > 0f) {
            // The outer contour becomes continuous across the former point of contact.
            sarcolemma.lineTo(FUSION_X - 43f, TOP)
            sarcolemma.cubicTo(FUSION_X - 28f, TOP, FUSION_X - 27f, TOP - rise, FUSION_X, TOP - rise)
            sarcolemma.cubicTo(FUSION_X + 27f, TOP - rise, FUSION_X + 28f, TOP, FUSION_X + 43f, TOP)
        }
        sarcolemma.lineTo(310f, TOP)
        fiber.set(sarcolemma)
        fiber.cubicTo(326f, TOP, 334f, 213f, 334f, 229f)
        fiber.lineTo(334f, 267f)
        fiber.cubicTo(334f, 284f, 325f, 294f, 308f, 294f)
        fiber.lineTo(52f, 294f)
        fiber.cubicTo(35f, 294f, 26f, 284f, 26f, 267f)
        fiber.lineTo(26f, 229f)
        fiber.cubicTo(26f, 213f, 34f, TOP, 50f, TOP)
        fiber.close()
        ink(cream)
        paint.shader = fiberTint
        c.drawPath(fiber, paint)
        paint.shader = null
        c.save()
        c.clipPath(fiber)
        for (row in 0..3) {
            val y = 220f + 18f * row
            line(c, 33f, y, 327f, y, 0x72fff0d5, 7f)
            line(c, 37f, y + 7f, 323f, y + 7f, 0x62a5656b, 1f)
        }
        for (i in 0..21) {
            val x = 28f + 15f * i
            line(c, x, 210f, x, 286f, 0x46aa626b, 3.1f)
            line(c, x + 4f, 213f, x + 4f, 283f, 0x6dffe8c6, 1.3f)
        }
        ovalNucleus(c, 67f, 218f, 12f, 4.4f, 0xff8b5b75)
        ovalNucleus(c, 155f, 280f, 13f, 4.5f, 0xff8b5b75)
        ovalNucleus(c, 310f, 278f, 11f, 4.4f, 0xff8b5b75)
        c.restore()
        stroke(c, fiber, fiberEdge, 2f)
    }

    private fun drawLamina(c: Canvas, x: Float, lift: Float, x2: Float = 0f, lift2: Float = 0f, span: Float = 58f) {
        lamina.rewind()
        lamina.moveTo(32f, LAMINA_Y)
        addArch(x, lift, span)
        if (lift2 > 0f) addArch(x2, lift2, 68f)
        lamina.lineTo(328f, LAMINA_Y)
        paintLamina(c)
    }

    private fun drawBranchLamina(c: Canvas, left: Float, right: Float, leftTop: Float, rightTop: Float) {
        val mid = (left + right) / 2f
        val bridge = maxOf(leftTop, rightTop) + 9f
        lamina.rewind()
        lamina.moveTo(32f, LAMINA_Y)
        lamina.lineTo(left - 61f, LAMINA_Y)
        lamina.cubicTo(left - 40f, LAMINA_Y, left - 42f, leftTop, left, leftTop)
        lamina.cubicTo(left + 22f, leftTop, mid - 12f, bridge, mid, bridge)
        lamina.cubicTo(mid + 12f, bridge, right - 22f, rightTop, right, rightTop)
        lamina.cubicTo(right + 42f, rightTop, right + 42f, LAMINA_Y, right + 63f, LAMINA_Y)
        lamina.lineTo(328f, LAMINA_Y)
        paintLamina(c)
    }

    private fun paintLamina(c: Canvas) {
        stroke(c, lamina, laminaEdge, 5.4f)
        stroke(c, lamina, laminaBand, 2.9f)
    }

    private fun addArch(x: Float, lift: Float, span: Float) {
        val top = LAMINA_Y - lift
        lamina.lineTo(x - span, LAMINA_Y)
        lamina.cubicTo(x - .67f * span, LAMINA_Y, x - .68f * span, top, x, top)
        lamina.cubicTo(x + .68f * span, top, x + .67f * span, LAMINA_Y, x + span, LAMINA_Y)
    }

    private fun satellite(c: Canvas, x: Float, y: Float, rx: Float, ry: Float, fill: Long) {
        cellProfile(x, y, rx, ry)
        paintCell(c, fill, reserveEdge)
        ovalNucleus(c, x, y, minOf(13f, rx * .39f), ry * .46f, nucleusInk)
    }

    private fun myoblast(c: Canvas, x: Float, y: Float, differentiation: Float) {
        cellProfile(x, y, 27f + 11f * differentiation, 21f - 7f * differentiation)
        paintCell(c, mix(activeFill, myoblastFill, differentiation), mix(reserveEdge, myoblastEdge, differentiation))
        ovalNucleus(c, x, y, 10.5f + 1.5f * differentiation, 8f - 2.5f * differentiation,
            mix(nucleusInk, myoblastNucleus, differentiation))
    }

    private fun cellProfile(x: Float, y: Float, rx: Float, ry: Float) {
        profile.rewind()
        profile.moveTo(x - rx, y + .08f * ry)
        profile.cubicTo(x - .65f * rx, y - .8f * ry, x - .39f * rx, y - ry, x + .06f * rx, y - ry)
        profile.cubicTo(x + .49f * rx, y - ry, x + .74f * rx, y - .42f * ry, x + rx, y + .06f * ry)
        profile.cubicTo(x + .68f * rx, y + .59f * ry, x + .33f * rx, y + ry, x - .06f * rx, y + ry)
        profile.cubicTo(x - .49f * rx, y + ry, x - .8f * rx, y + .45f * ry, x - rx, y + .08f * ry)
        profile.close()
    }

    private fun paintCell(c: Canvas, fill: Long, edge: Long) {
        ink(fill)
        c.drawPath(profile, paint)
        stroke(c, profile, edge, 1.8f)
    }

    private fun ovalNucleus(c: Canvas, x: Float, y: Float, rx: Float, ry: Float, color: Long, rim: Long = color) {
        oval(c, x - rx, y - ry, x + rx, y + ry, color, rim)
        if (ry > 5f) disc(c, x - rx * .26f, y - ry * .22f, 1.35f, 0xffe0c7ba)
    }

    private fun trace(c: Canvas, contour: Path, fraction: Float, color: Long) {
        measure.setPath(contour, false)
        val head = fraction * 1.31f
        val tail = (head - .31f).coerceAtLeast(0f)
        highlight.rewind()
        if (measure.getSegment(tail * measure.length, head.coerceAtMost(1f) * measure.length, highlight, true)) {
            stroke(c, highlight, cream, 7.4f)
            stroke(c, highlight, color, 3.6f)
        }
    }

    private fun fiberLabel(c: Canvas, x: Float) =
        lead(c, string.health_atlas_muscle_satellite_renewal_art_fiber, x, 326f, x, 268f, fiberEdge)

    private fun lead(c: Canvas, @StringRes text: Int, x: Float, y: Float, tx: Float, ty: Float, color: Long) {
        val start = if (ty > y) y + 8f else y - 17f
        val elbow = if (ty > y) ty - 12f else ty + 12f
        line(c, x, start, tx, elbow, cream, 3.2f)
        line(c, tx, elbow, tx, ty, cream, 3.2f)
        line(c, x, start, tx, elbow, leader, 1.05f)
        line(c, tx, elbow, tx, ty, leader, 1.05f)
        disc(c, tx, ty, 2.15f, color, cream)
        label(c, text, x, y, 146f)
    }

    private fun progress(value: Float, start: Float, end: Float): Float {
        val t = ((value - start) / (end - start)).coerceIn(0f, 1f)
        return t * t * (3f - 2f * t)
    }

    private fun mix(from: Long, to: Long, t: Float): Long {
        var result = 0xff000000
        for (shift in 0..16 step 8) {
            val a = (from shr shift and 0xff).toInt()
            val b = (to shr shift and 0xff).toInt()
            result = result or ((a + (b - a) * t).toLong() shl shift)
        }
        return result
    }

    private companion object {
        const val CELL_X = 180f
        const val RESERVE_X = 107f
        const val FUSION_X = 247f
        const val LAMINA_Y = 188f
        const val TOP = 202f
    }
}
