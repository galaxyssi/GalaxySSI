package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import kotlin.math.abs

internal class HealthAtlasSmoothMuscleStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.SMOOTH_MUSCLE_WAVE) {
    private val wall = Path()
    private val contour = FloatArray((RIGHT - LEFT) / 2 + 1)
    private val bolus = Path().apply {
        moveTo(-31f, 1f)
        cubicTo(-34f, -8f, -19f, -19f, -9f, -17f)
        cubicTo(1f, -23f, 12f, -17f, 17f, -14f)
        cubicTo(28f, -15f, 34f, -7f, 32f, 2f)
        cubicTo(33f, 10f, 22f, 19f, 12f, 17f)
        cubicTo(2f, 22f, -7f, 16f, -14f, 17f)
        cubicTo(-23f, 17f, -32f, 11f, -31f, 1f)
        close()
    }

    init { tag = "atlas-function-smooth-muscle-wave-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val frame = Motion(step, t)
        for (i in contour.indices) contour[i] = frame.radius((LEFT + 2 * i).toFloat())

        // A lengthwise cutaway: the two muscle layers follow the same lumen contour.
        layer(c, OUTER, 0xffdccfe7, violet)
        layer(c, CIRCULAR, 0xfff4c5bd, coral)
        layer(c, LINING, 0xfff8dcb7, 0xffbf8c79)
        layer(c, 0f, 0xfffff5e7, 0xffaf816e)
        fibers(c, frame)
        drawBolus(c, frame)
        callouts(c, frame, step, t)
        legend(c)
    }

    private fun layer(c: Canvas, offset: Float, fill: Long, edge: Long) {
        wall.rewind()
        wall.moveTo(LEFT.toFloat(), AXIS - contour.first() - offset)
        for (i in 1..contour.lastIndex) {
            wall.lineTo((LEFT + 2 * i).toFloat(), AXIS - contour[i] - offset)
        }
        for (i in contour.indices.reversed()) {
            wall.lineTo((LEFT + 2 * i).toFloat(), AXIS + contour[i] + offset)
        }
        wall.close()
        ink(fill)
        c.drawPath(wall, paint)

        // Outline only the sides so neither end looks sealed.
        wall.rewind()
        for (side in -1..1 step 2) {
            wall.moveTo(LEFT.toFloat(), AXIS + side * (contour.first() + offset))
            for (i in 1..contour.lastIndex) {
                wall.lineTo((LEFT + 2 * i).toFloat(), AXIS + side * (contour[i] + offset))
            }
        }
        stroke(c, wall, edge, if (offset == OUTER) 1.6f else 1.1f)
    }

    private fun fibers(c: Canvas, frame: Motion) {
        for (side in -1..1 step 2) {
            for (x in 24..336 step 9) {
                val start = x.toFloat()
                val end = start + 3f
                val squeeze = frame.squeezeAt(start)
                val open = frame.openingAt(start)
                val color = when {
                    squeeze > 5f -> SQUEEZE_INK
                    open > 5f -> OPEN_INK
                    else -> coral
                }
                line(c, start, AXIS + side * (frame.radius(start) + 8f),
                    end, AXIS + side * (frame.radius(end) + 17f), color, 1.4f)
            }
            for (x in 24..312 step 32) {
                val start = x.toFloat()
                val end = start + 23f
                wall.rewind()
                wall.moveTo(start, AXIS + side * (frame.radius(start) + 25f))
                for (sample in x + 4..x + 20 step 4) {
                    val at = sample.toFloat()
                    wall.lineTo(at, AXIS + side * (frame.radius(at) + 25f))
                }
                wall.lineTo(end, AXIS + side * (frame.radius(end) + 25f))
                stroke(c, wall, violet, 1.5f)
            }
        }
    }

    private fun drawBolus(c: Canvas, frame: Motion) {
        c.save()
        c.translate(frame.center, AXIS)
        c.scale(frame.stretch, frame.heightScale)
        ink(0xffecc174)
        c.drawPath(bolus, paint)
        stroke(c, bolus, sienna, 1.7f)
        oval(c, -21f, -9f, -5f, -3f, 0xffffe3a3, 0xffffe3a3)
        disc(c, 5f, 8f, 3.1f, 0xffc98d4c)
        disc(c, 15f, -5f, 2.5f, 0xffd09650)
        disc(c, -13f, 8f, 2.2f, 0xffd09650)
        c.restore()
    }

    private fun callouts(c: Canvas, frame: Motion, step: Int, t: Float) {
        val tip = AXIS - 18f * frame.heightScale
        line(c, frame.center, 47f, frame.center, tip, cream, 3.2f)
        line(c, frame.center, 47f, frame.center, tip, sienna, 1.2f)
        disc(c, frame.center, tip, 2.2f, sienna, cream)
        label(c, R.string.health_atlas_smooth_muscle_story_bolus, frame.center, 38f, 68f)

        if (step == 0) {
            wallArrows(c, frame, frame.center + 12f, true, sienna, 8f + 9f * t)
        }
        if (step in 1..3) {
            wallArrows(c, frame, frame.ahead, true, OPEN_INK, 8f + .6f * frame.opening)
            activityLabel(c, R.string.health_atlas_smooth_muscle_story_ahead, 267f, OPEN_INK)
        }
        if (step in 2..3) {
            wallArrows(c, frame, frame.behind, false, SQUEEZE_INK, 8f + .45f * frame.squeeze)
            activityLabel(c, R.string.health_atlas_smooth_muscle_story_behind, 93f, SQUEEZE_INK)
        }
        if (step == 4) {
            val wake = positions[4] - BEHIND_OFFSET
            wallArrows(c, frame, wake, true, OPEN_INK, 8f + 10f * t)
            activityLabel(c, R.string.health_atlas_smooth_muscle_story_reopening, wake, OPEN_INK)
        }
    }

    private fun activityLabel(c: Canvas, res: Int, x: Float, color: Long) {
        line(c, x - 58f, 261f, x - 50f, 261f, color, 2.6f)
        label(c, res, x + 10f, 265f, 110f)
    }

    private fun wallArrows(c: Canvas, frame: Motion, x: Float, outward: Boolean, color: Long, length: Float) {
        val radius = frame.radius(x) + OUTER
        for (side in -1..1 step 2) {
            val near = AXIS + side * (radius + 4f)
            val far = near + side * length
            arrow(c, x, if (outward) near else far, x, if (outward) far else near, color)
        }
    }

    private fun legend(c: Canvas) {
        rounded(c, 61f, 277f, 125f, 294f, 4f, 0xfff4c5bd)
        for (x in 70..116 step 9) line(c, x.toFloat(), 290f, x + 3f, 281f, coral, 1.5f)
        label(c, R.string.health_atlas_smooth_muscle_story_circular, 93f, 311f, 154f)
        rounded(c, 235f, 277f, 299f, 294f, 4f, 0xffdccfe7)
        for (y in 282..290 step 4) line(c, 243f, y.toFloat(), 291f, y.toFloat(), violet, 1.5f)
        label(c, R.string.health_atlas_smooth_muscle_story_longitudinal, 267f, 311f, 154f)

        arrow(c, 94f, 325f, 266f, 325f, sienna)
        label(c, R.string.health_atlas_smooth_muscle_story_downstream, 180f, 345f, 200f)
    }

    private class Motion(step: Int, t: Float) {
        // Shared endpoints make the anatomy continuous when the player crosses a chapter boundary.
        val center = positions[step] + (positions[step + 1] - positions[step]) * t
        val behind = center - BEHIND_OFFSET
        val ahead = center + 44f
        val opening = when (step) {
            0 -> 0f
            1 -> 16f * t
            4 -> 16f * (1f - t)
            else -> 16f
        }
        val squeeze = when (step) {
            2 -> 23f * t
            3 -> 23f
            4 -> 23f * (1f - t)
            else -> 0f
        }
        private val fullness = if (step == 0) 3f + 10f * t else 13f
        val stretch = 1f + squeeze / 180f
        val heightScale = (1.18f + .025f * fullness) / stretch

        fun squeezeAt(x: Float) = squeeze * bump(x - behind, 34f)
        fun openingAt(x: Float) = opening * bump(x - ahead, 39f)

        fun radius(x: Float): Float {
            val edge = (minOf(x - LEFT, RIGHT - x) / 19f).coerceIn(0f, 1f)
            return 28f + edge * (fullness * bump(x - center, 43f) + openingAt(x) - squeezeAt(x))
        }
    }

    private companion object {
        const val LEFT = 16
        const val RIGHT = 344
        const val AXIS = 151f
        const val OUTER = 29f
        const val CIRCULAR = 20f
        const val LINING = 6f
        const val BEHIND_OFFSET = 48f
        const val SQUEEZE_INK = 0xffa1475c
        const val OPEN_INK = 0xff397a70
        val positions = floatArrayOf(58f, 99f, 102f, 137f, 239f, 309f)

        fun bump(distance: Float, width: Float): Float {
            val q = (1f - abs(distance) / width).coerceAtLeast(0f)
            return q * q * (3f - 2f * q)
        }
    }
}
