package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import com.galaxyssi.chat.HealthAtlasLeydigEndocrineAssignment.ENDOCRINE_OUTPUT
import com.galaxyssi.chat.HealthAtlasLeydigEndocrineAssignment.INTERSTITIUM
import com.galaxyssi.chat.HealthAtlasLeydigEndocrineAssignment.PITUITARY_SIGNAL
import com.galaxyssi.chat.HealthAtlasLeydigEndocrineAssignment.TESTOSTERONE
import com.galaxyssi.chat.R.string
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasLeydigEndocrineStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val tubuleInk = 0xff527572
    private val cellInk = 0xff864753
    private val vesselInk = 0xff924e60
    private val signalInk = 0xff24577e
    private val outputInk = 0xff8c510f

    // Unitless teaching geometry. Tokens show direction, not concentration or timing.
    private val germRing = FloatArray(32) { i ->
        val angle = (i / 2) * PI / 8.0
        if (i % 2 == 0) 42f * cos(angle).toFloat() else 59f * sin(angle).toFloat()
    }
    private val leydigOutline = Path().apply {
        moveTo(-13f, -1f)
        cubicTo(-13f, -8f, -6f, -13f, 1f, -12f)
        cubicTo(11f, -13f, 15f, -6f, 13f, 2f)
        cubicTo(12f, 10f, 4f, 14f, -4f, 11f)
        cubicTo(-11f, 10f, -14f, 5f, -13f, -1f)
        close()
    }
    private val capillary = Path().apply {
        moveTo(35f, 251f)
        cubicTo(91f, 265f, 133f, 248f, 168f, 238f)
        cubicTo(219f, 223f, 244f, 267f, 325f, 251f)
    }
    private val lhRoute = track(Path().apply {
        moveTo(209f, 238f)
        cubicTo(205f, 221f, 216f, 186f, 201f, 159f)
    })
    private val bloodRoute = track(Path().apply {
        moveTo(193f, 189f)
        cubicTo(196f, 211f, 172f, 220f, 179f, 236f)
        cubicTo(225f, 230f, 254f, 266f, 317f, 252f)
    })
    private val localRoute = track(Path().apply {
        moveTo(168f, 172f)
        quadTo(155f, 180f, 132f, 172f)
    })
    private val trace = Path()
    private val diamond = Path().apply {
        moveTo(0f, -5f)
        lineTo(5f, 0f)
        lineTo(0f, 5f)
        lineTo(-5f, 0f)
        close()
    }

    init { tag = "atlas-function-leydig-endocrine-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        rounded(c, 19f, 53f, 341f, 268f, 12f, 0xfff9ede4)
        tubule(c, 79f, 151f, 10f, 1f)
        tubule(c, 282f, 150f, -15f, .96f)
        line(c, 98f, 38f, 90f, 77f, tubuleInk, 1.1f)
        line(c, 263f, 38f, 266f, 73f, tubuleInk, 1.1f)
        label(c, string.health_atlas_leydig_endocrine_art_tubules, 180f, 32f, 206f)
        stroke(c, capillary, vesselInk, 16f)
        stroke(c, capillary, 0xffeab2b7, 12f)
        leydigCell(c, 166f, 144f, -16f)
        leydigCell(c, 190f, 151f, 12f)
        leydigCell(c, 166f, 173f, 35f)
        leydigCell(c, 191f, 188f, -19f)
        label(c, string.health_atlas_leydig_endocrine_art_cells, 180f, 112f, 110f)
        line(c, 180f, 118f, 174f, 130f, cellInk, 1.1f)
        label(c, string.health_atlas_leydig_endocrine_art_capillary, 180f, 283f, 154f)
        line(c, 180f, 270f, 180f, 245f, vesselInk, 1.1f)

        val key = when (step) {
            INTERSTITIUM -> {
                val focus = sin(t * PI).toFloat()
                ink(cellInk, 1.2f + 1.2f * focus)
                c.drawRoundRect(146f - 3f * focus, 127f, 215f + 3f * focus, 205f, 13f, 13f, paint)
                string.health_atlas_leydig_endocrine_art_interstitium
            }
            PITUITARY_SIGNAL -> {
                route(c, lhRoute, t, signalInk, input = true)
                string.health_atlas_leydig_endocrine_art_lh
            }
            TESTOSTERONE -> {
                production(c, 173f, 141f, t)
                production(c, 191f, 186f, (t + .33f) % 1f)
                string.health_atlas_leydig_endocrine_art_testosterone
            }
            ENDOCRINE_OUTPUT -> {
                route(c, bloodRoute, t, outputInk, input = false)
                route(c, localRoute, t, outputInk, input = false)
                string.health_atlas_leydig_endocrine_art_destinations
            }
            else -> return
        }
        rounded(c, 32f, 298f, 328f, 325f, 7f, 0xfffbf8ee)
        label(c, key, 180f, 316f, 280f)
        label(c, string.health_atlas_gonadal_story_art_educational, 180f, 345f, 255f)
    }

    private fun tubule(c: Canvas, x: Float, y: Float, rotation: Float, scale: Float) {
        c.save()
        c.translate(x, y)
        c.rotate(rotation)
        c.scale(scale, scale)
        oval(c, -55f, -79f, 55f, 79f, 0xffa9c5bd, tubuleInk)
        oval(c, -50f, -74f, 50f, 74f, 0xffd2dfce, tubuleInk)
        oval(c, -29f, -45f, 29f, 45f, 0xffbcd4ca, 0xff8cad9f)
        oval(c, -19f, -31f, 19f, 31f, 0xfff2faf5, tubuleInk)
        for (i in 0 until germRing.size step 2) {
            val gx = germRing[i]
            val gy = germRing[i + 1]
            disc(c, gx, gy, 4.3f, 0xff6b8f85)
            disc(c, gx * .73f, gy * .75f, 2.8f, 0xff719b8f)
        }
        c.restore()
    }

    private fun leydigCell(c: Canvas, x: Float, y: Float, rotation: Float) {
        c.save()
        c.translate(x, y)
        c.rotate(rotation)
        ink(0xffefb9a5)
        c.drawPath(leydigOutline, paint)
        stroke(c, leydigOutline, cellInk, 1.4f)
        disc(c, 0f, 0f, 4.1f, cellInk)
        disc(c, 6f, -5f, 1.7f, cream)
        disc(c, -6f, 4f, 1.3f, cream)
        c.restore()
    }

    private fun route(c: Canvas, path: PathMeasure, t: Float, color: Long, input: Boolean) {
        trace.rewind()
        if (path.getSegment(0f, path.length * t, trace, true)) stroke(c, trace, color, 1.3f)
        at(path, t) { x, y ->
            if (input) {
                c.save()
                c.translate(x, y)
                ink(signalInk)
                c.drawPath(diamond, paint)
                stroke(c, diamond, cream, 1.1f)
                c.restore()
            } else {
                disc(c, x, y, 4.5f, cream, outputInk)
            }
        }
    }

    private fun production(c: Canvas, x: Float, y: Float, t: Float) {
        ink(outputInk, 1.6f)
        paint.alpha = (205f * (1f - t)).toInt()
        c.drawCircle(x, y, 12f + 10f * t, paint)
        disc(c, x + 10f + 8f * t, y - 7f - 9f * t, 3f + t, cream, outputInk)
    }
}
