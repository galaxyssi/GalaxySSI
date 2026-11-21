package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader
import androidx.annotation.StringRes
import kotlin.math.abs
import kotlin.math.sin

internal class HealthAtlasArterialStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.ARTERIAL_PULSE) {
    private val outer = shade(199f, 299f, 0xfff4d4bf, 0xffdea392)
    private val media = shade(205f, 292f, 0xffeca8a0, 0xffcc7680)
    private val intima = shade(216f, 285f, 0xfff4c0a9, 0xffe09487)
    private val lumen = shade(223f, 279f, 0xffffe1ce, 0xffefada5)
    private val outline = 0xff995b67
    private val guide = 0xff5d797c
    private val blood = 0xff984957
    private val pulse = 0xff9c621e
    private val segment = Path()
    private val lamella = Path()
    private val layerLines = intArrayOf(0, 6, 9, 16)
    private val arch = Path().apply {
        moveTo(49f, 132f)
        cubicTo(51f, 119f, 47f, 112f, 55f, 92f)
        cubicTo(64f, 70f, 81f, 65f, 100f, 72f)
        cubicTo(120f, 79f, 127f, 95f, 125f, 113f)
        cubicTo(124f, 122f, 123f, 132f, 125f, 145f)
    }
    private val branches = listOf(
        branch(61f, 82f, 53f, 52f),
        branch(78f, 73f, 77f, 44f),
        branch(97f, 73f, 103f, 50f),
    )
    private val archTrack = track(arch)

    init { tag = "atlas-function-arterial-pulse-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val center = HealthAtlasArterialMotion.front(step, t)
        val expansion = HealthAtlasArterialMotion.expansion(step, t, .24f)
        drawLocator(c, step, t)
        drawSection(c, step, t, expansion)
        line(c, 19f, 158f, 341f, 158f, 0xffccdcd5, 1f)
        label(c, R.string.health_atlas_arterial_longitudinal, 180f, 180f, 210f)
        drawTube(c, step, t)
        if (center != null) drawPulse(c, step, t, center)
        val distance = HealthAtlasArterialMotion.flowTravel(step, t)
        if (distance != null) drawFlow(c, distance)
        drawLegend(c)
    }

    private fun drawLocator(c: Canvas, step: Int, t: Float) {
        label(c, R.string.health_atlas_arterial_aortic_arch, 85f, 28f, 132f)
        branches.forEach { stroke(c, it, outline, 10f); stroke(c, it, 0xffdd8891, 7f) }
        stroke(c, arch, outline, 20f)
        stroke(c, arch, 0xffdd8891, 17f)
        stroke(c, arch, 0xffeda9a3, 8f)
        at(archTrack, .37f) { x, y ->
            line(c, x + 11f, y + 2f, 166f, 105f, guide, 1.1f)
            disc(c, x, y, 10f, 0x26fff4e8, guide)
        }
        label(c, R.string.health_atlas_arterial_from_heart, 48f, 153f, 90f)
        if (step != 0) {
            at(archTrack, (t * .62f + .1f).coerceIn(0f, 1f)) { x, y ->
                disc(c, x, y, 3.4f, cream, if (step == 2) pulse else blood)
            }
        }
    }

    private fun drawSection(c: Canvas, step: Int, t: Float, expansion: Float) {
        val x = 217f
        val y = 93f
        val r = 23f + 7f * expansion
        label(c, R.string.health_atlas_arterial_cross_section, x, 28f, 174f)
        disc(c, x, y, r + 16f, 0xffe9bca7, outline)
        disc(c, x, y, r + 10f, 0xffda8991, outline)
        disc(c, x, y, r + 2.5f, 0xfff5bea5)
        disc(c, x, y, r, 0xfffae0cc, outline)
        for (offset in 5..8 step 3) {
            ink(0xfff4baab, 1.25f)
            c.drawCircle(x, y, r + offset, paint)
        }
        sectionLabel(c, 322f, 62f, x + (r + 13f) * .66f, y - (r + 13f) * .75f,
            R.string.health_atlas_arterial_outer_wall)
        sectionLabel(c, 322f, 96f, x + r + 7f, y, R.string.health_atlas_arterial_elastic_media)
        sectionLabel(c, 316f, 131f, x + (r + 1f) * .71f, y + (r + 1f) * .71f,
            R.string.health_atlas_arterial_intima)
        if (step == 0) {
            val focus = r + 7f
            ink(pulse, 2.4f)
            c.drawArc(x - focus, y - focus, x + focus, y + focus, -138f, 48f + 288f * t, false, paint)
        } else {
            label(c, R.string.health_atlas_arterial_lumen, x, y + 4f, (r - 3f) * 2)
        }
    }

    private fun sectionLabel(c: Canvas, x: Float, baseline: Float, targetX: Float, targetY: Float, @StringRes res: Int) {
        line(c, targetX, targetY, x - 32f, baseline - 4f, guide, .95f)
        disc(c, targetX, targetY, 1.65f, guide, cream)
        label(c, res, x, baseline, 62f)
    }

    private fun drawTube(c: Canvas, step: Int, t: Float) {
        drawLayer(c, step, t, 16f, outer)
        drawLayer(c, step, t, 11f, media)
        drawLayer(c, step, t, 3f, intima)
        drawLayer(c, step, t, 0f, lumen)
        for (side in -1..1 step 2) {
            for (offset in layerLines) {
                lamella.rewind()
                for (i in 0..24) {
                    val f = i / 24f
                    val y = TUBE_Y + side * (radius(step, t, f) + offset)
                    if (i == 0) lamella.moveTo(X0, y) else lamella.lineTo(xAt(f), y)
                }
                stroke(c, lamella, if (offset == 0 || offset == 16) outline else 0xfff5c4b0, 1.1f)
            }
        }
        // Leave the segment open at both ends; it is a cutaway, not a capped vessel.
        for (f in listOf(0f, 1f)) {
            val r = radius(step, t, f)
            for (side in -1..1 step 2) {
                val x = xAt(f)
                line(c, x, TUBE_Y + side * r, x, TUBE_Y + side * (r + 16f), outline, 1.5f)
            }
        }
    }

    private fun drawLayer(c: Canvas, step: Int, t: Float, offset: Float, fill: Shader) {
        segment.rewind()
        for (i in 0..24) {
            val f = i / 24f
            val y = TUBE_Y - radius(step, t, f) - offset
            if (i == 0) segment.moveTo(X0, y) else segment.lineTo(xAt(f), y)
        }
        for (i in 24 downTo 0) {
            val f = i / 24f
            segment.lineTo(xAt(f), TUBE_Y + radius(step, t, f) + offset)
        }
        segment.close()
        ink(cream)
        paint.shader = fill
        c.drawPath(segment, paint)
        paint.shader = null
    }

    private fun drawPulse(c: Canvas, step: Int, t: Float, fraction: Float) {
        val x = xAt(fraction)
        val y = TUBE_Y - radius(step, t, fraction) - 16f
        ink(pulse, 2.1f)
        c.drawArc(x - 12f, y - 11f, x + 12f, y + 5f, 207f, 126f, false, paint)
        disc(c, x, y, 2.5f, pulse, cream)
    }

    private fun drawFlow(c: Canvas, distance: Float) {
        for (index in 0..3) {
            val f = (distance + index * .25f) % 1f
            val x = xAt(.05f + .9f * f)
            val y = TUBE_Y + if (index % 2 == 0) -5f else 6f
            arrow(c, x - 5f, y, x + 7f, y, blood)
        }
    }

    private fun drawLegend(c: Canvas) {
        arrow(c, 43f, 329f, 63f, 329f, blood)
        label(c, R.string.health_atlas_arterial_flow, 108f, 333f, 76f)
        disc(c, 200f, 329f, 3.5f, pulse)
        label(c, R.string.health_atlas_arterial_wave, 265f, 333f, 111f)
    }

    private fun xAt(f: Float) = X0 + (X1 - X0) * f
    private fun radius(step: Int, t: Float, f: Float) = 20f + 12f * HealthAtlasArterialMotion.expansion(step, t, f)
    private fun branch(x: Float, y: Float, endX: Float, endY: Float) =
        Path().apply { moveTo(x, y); quadTo(x, y - 11f, endX, endY) }

    private companion object {
        const val X0 = 28f
        const val X1 = 332f
        const val TUBE_Y = 253f
    }
}

internal object HealthAtlasArterialMotion {
    // Unitless teaching poses, not an estimator of a person's pressure, flow, or vessel size.
    fun expansion(chapter: Int, progress: Float, location: Float): Float {
        val t = HealthAtlasFunctionStory.safePhase(progress)
        return when (chapter) {
            1 -> .88f * smooth(t)
            2 -> {
                val distance = abs(HealthAtlasFunctionStory.safePhase(location) - requireNotNull(front(chapter, t)))
                .22f + .67f * smooth(1f - (distance / .36f).coerceAtMost(1f))
            }
            3 -> .8f * (1f - smooth(t))
            4 -> .82f * sin(t * Math.PI).toFloat()
            else -> 0f
        }
    }

    fun front(chapter: Int, progress: Float): Float? =
        if (chapter == 2) .06f + .88f * HealthAtlasFunctionStory.safePhase(progress) else null

    fun flowTravel(chapter: Int, progress: Float): Float? {
        val t = HealthAtlasFunctionStory.safePhase(progress)
        return when (chapter) {
            1, 2 -> .76f * t
            3 -> .48f * t - .17f * t * t
            4 -> .57f * t
            else -> null
        }
    }

    private fun smooth(t: Float) = t * t * (3f - 2f * t)
}
