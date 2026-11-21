package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import com.galaxyssi.chat.R.string

internal class HealthAtlasPancreaticDeltaStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasEndocrineCellStoryView(context, story, HealthAtlasEndocrineCellAssignments.DELTA) {
    private val signal = 0xff8365a0
    private val alphaInk = 0xffa45550
    private val betaInk = 0xff357c79
    private val signalFill = shade(88f, 157f, 0xffeadcf1, 0xffc3a7d9)
    private val trace = Path()
    private val islet = curve {
        moveTo(29f, 168f)
        cubicTo(38f, 116f, 82f, 82f, 140f, 67f)
        cubicTo(208f, 49f, 287f, 77f, 321f, 129f)
        cubicTo(359f, 186f, 334f, 247f, 291f, 271f)
        cubicTo(236f, 297f, 160f, 292f, 102f, 280f)
        cubicTo(55f, 269f, 19f, 225f, 29f, 168f)
        close()
    }
    private val backgroundCells = floatArrayOf(
        61f, 173f, 91f, 132f, 121f, 90f, 128f, 160f, 163f, 210f, 180f, 254f,
        224f, 176f, 252f, 103f, 282f, 128f, 313f, 175f, 225f, 248f, 139f, 253f,
    )

    override fun scene(c: Canvas, step: Int, t: Float) {
        if (step == 3) {
            compareOutput(c, t)
            return
        }
        ink(0xfff5eadf); c.drawPath(islet, paint)
        stroke(c, islet, 0xffc29b92, 1.5f)
        for (i in backgroundCells.indices step 2) {
            val x = backgroundCells[i]
            val y = backgroundCells[i + 1]
            oval(c, x - 15f, y - 12f, x + 15f, y + 12f, 0xffecdbd2, 0xffd7beb6)
            disc(c, x + 1f, y, 4f, 0xffc8a7af)
        }
        label(c, string.health_atlas_delta_local_art_islet, 180f, 32f, 210f)
        when (step) {
            0 -> {
                val r = 42f + 8f * wave(t)
                ink(signal, 2f)
                c.drawArc(180f - r, 121f - r, 180f + r, 121f + r, -124f, 70f + 264f * t, false, paint)
            }
            1 -> localSpread(c, t)
            else -> {
                localSpread(c, .65f + .20f * t)
                shortOutput(c, 86f, -1f, t, alphaInk)
                shortOutput(c, 274f, 1f, t, betaInk)
            }
        }
        oval(c, 146f, 91f, 214f, 151f, signalFill, signal)
        disc(c, 178f, 121f, 10f, signal, cream)
        oval(c, 57f, 185f, 118f, 233f, 0xffedbeb0, alphaInk)
        disc(c, 86f, 211f, 8f, alphaInk, cream)
        oval(c, 242f, 185f, 303f, 233f, 0xffacd4c9, betaInk)
        disc(c, 274f, 211f, 8f, betaInk, cream)
        label(c, string.health_atlas_delta_local_art_delta, 180f, 55f, 142f)
        label(c, string.health_atlas_delta_local_art_alpha, 86f, 254f, 104f)
        label(c, string.health_atlas_delta_local_art_beta, 274f, 254f, 104f)
        if (step > 0) label(c, string.health_atlas_delta_local_art_somatostatin, 180f, 315f, 236f)
    }

    private fun localSpread(c: Canvas, t: Float) {
        for (i in 0..2) {
            val f = (t * 1.22f - i * .14f).coerceIn(0f, 1f)
            val r = 36f + 63f * f
            ink(if (i == 0) signal else 0xffb59bc4, 2.1f - i * .35f)
            c.drawArc(180f - r, 113f - r, 180f + r, 113f + r, 33f + 9f * i, 114f - 18f * i, false, paint)
        }
    }

    private fun shortOutput(c: Canvas, x: Float, direction: Float, t: Float, color: Long) {
        for (i in 0..2) {
            val f = (t * .8f + i * .31f) % 1f
            disc(c, x + direction * (30f + (24f - 12f * t) * f), 207f + (i - 1) * 9f, 2.7f - f, color)
        }
    }

    private fun compareOutput(c: Canvas, t: Float) {
        label(c, string.health_atlas_delta_local_art_output, 180f, 52f, 270f)
        label(c, string.health_atlas_delta_local_art_glucagon, 180f, 106f, 160f)
        drawTrace(c, 149f, t, alphaInk)
        label(c, string.health_atlas_delta_local_art_insulin, 180f, 201f, 160f)
        drawTrace(c, 244f, t, betaInk)
        val sweep = 39f + 282f * t
        line(c, sweep, 121f, sweep, 177f, signal, 1.2f)
        line(c, sweep, 216f, sweep, 270f, signal, 1.2f)
        diamond(c, sweep, 272f, 4.5f, signal)
        label(c, string.health_atlas_delta_local_art_lower, 180f, 315f, 250f)
    }

    private fun drawTrace(c: Canvas, y: Float, t: Float, color: Long) {
        line(c, 39f, y, 321f, y, divider, 1f)
        trace.rewind()
        for (i in 0..56) {
            val x = i / 56f
            val amplitude = 15f - 10f * x
            val point = y - amplitude * wave(x * 4f - .6f * t)
            if (i == 0) trace.moveTo(39f, point) else trace.lineTo(39f + 282f * x, point)
        }
        stroke(c, trace, color, 2.5f)
    }
}
