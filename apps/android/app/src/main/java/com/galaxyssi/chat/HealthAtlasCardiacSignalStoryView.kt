package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure

internal object HealthAtlasCardiacSignalMotion {
    fun shortening(step: Int, fraction: Float): Float {
        val f = HealthAtlasFunctionStory.safePhase(fraction)
        val ease = f * f * (3f - 2f * f)
        return when (step) {
            3 -> ease
            4 -> 1f - ease
            else -> 0f
        }
    }
}

internal class HealthAtlasCardiacSignalStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.CARDIAC_EXCITATION) {
    private val myocardium = shade(28f, 176f, 0xfff7c6b2, 0xffd08083)
    private val cellWash = shade(242f, 310f, 0xffffe2d0, 0xffe5a8a4)
    private val outline = 0xff975367
    private val circuit = 0xff4f5578
    private val excited = 0xffe79b45
    private val myofibril = 0xff975e80
    private val trace = Path()
    private val routes = listOf(
        path {
            moveTo(112f, 48f)
            cubicTo(126f, 58f, 153f, 42f, 184f, 65f)
        },
        path {
            moveTo(112f, 48f)
            cubicTo(112f, 74f, 121f, 81f, 140f, 95f)
        },
        path {
            moveTo(140f, 95f)
            quadTo(151f, 111f, 151f, 124f)
            lineTo(153f, 159f)
        },
        path {
            moveTo(153f, 159f)
            cubicTo(140f, 169f, 128f, 151f, 120f, 131f)
        },
        path {
            moveTo(153f, 159f)
            cubicTo(169f, 177f, 188f, 158f, 197f, 118f)
        },
    ).map { it to track(it) }
    private val wall = path {
        moveTo(147f, 46f)
        cubicTo(116f, 17f, 91f, 36f, 93f, 76f)
        cubicTo(96f, 123f, 119f, 154f, 146f, 173f)
        cubicTo(159f, 185f, 174f, 181f, 188f, 168f)
        cubicTo(214f, 146f, 220f, 112f, 218f, 79f)
        cubicTo(220f, 46f, 190f, 37f, 174f, 55f)
        quadTo(163f, 70f, 147f, 46f)
        close()
    }
    private val rightVentricle = path {
        moveTo(106f, 99f)
        cubicTo(117f, 95f, 124f, 105f, 133f, 111f)
        quadTo(141f, 119f, 142f, 142f)
        cubicTo(133f, 144f, 115f, 122f, 106f, 99f)
        close()
    }
    private val leftVentricle = path {
        moveTo(171f, 105f)
        cubicTo(179f, 94f, 196f, 87f, 200f, 103f)
        cubicTo(203f, 126f, 181f, 157f, 168f, 160f)
        quadTo(161f, 146f, 171f, 105f)
        close()
    }

    init { tag = "atlas-function-cardiac-excitation-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        drawHeart(c, step, t)
        drawCell(c, step, t)
    }

    private fun drawHeart(c: Canvas, step: Int, t: Float) {
        ink(cream)
        paint.shader = myocardium
        c.drawPath(wall, paint)
        paint.shader = null
        stroke(c, wall, outline, 2f)
        ink(0xfff5d8c7)
        c.drawPath(leftVentricle, paint)
        c.drawPath(rightVentricle, paint)
        stroke(c, leftVentricle, outline, 1.4f)
        stroke(c, rightVentricle, outline, 1.35f)
        for ((index, route) in routes.withIndex()) {
            stroke(c, route.first, circuit, 1.25f)
            val progress = when {
                step == 0 && index in 0..1 -> t
                step == 2 && index == 2 -> (t / .56f).coerceAtMost(1f)
                step == 2 && index in 3..4 && t >= .56f -> (t - .56f) / .44f
                else -> -1f
            }
            if (progress >= 0f) {
                colorRoute(c, route.second, progress)
                at(route.second, progress) { x, y -> disc(c, x, y, 3.4f, excited, cream) }
            }
        }
        disc(c, 112f, 48f, if (step == 0) 7f + 2.4f * wave(t) else 5f, excited, circuit)
        disc(c, 140f, 95f, if (step == 1) 7f + 2.5f * wave(t) else 4.5f, excited, circuit)
        line(c, 118f, 48f, 248f, 39f, circuit, 1.1f)
        label(c, R.string.health_atlas_cardiac_sa_label, 294f, 43f, 100f)
        line(c, 146f, 94f, 251f, 84f, circuit, 1.1f)
        label(c, R.string.health_atlas_cardiac_av_label, 294f, 88f, 103f)
        line(c, 191f, 153f, 246f, 147f, circuit, 1.1f)
        label(c, R.string.health_atlas_cardiac_network_label, 291f, 151f, 108f)
        line(c, 164f, 175f, 75f, 213f, outline, 1.05f)
        line(c, 178f, 177f, 289f, 213f, outline, 1.05f)
    }

    private fun drawCell(c: Canvas, step: Int, t: Float) {
        val shortening = HealthAtlasCardiacSignalMotion.shortening(step, t)
        val left = 33f + 33f * shortening
        val right = 326f - 33f * shortening
        val cy = 273f
        label(c, R.string.health_atlas_cardiac_cell_label, 180f, 231f, 201f)
        oval(c, left, 242f, right, 305f, cellWash, outline)
        val width = right - left
        for (i in 0..3) {
            val x = left + 28f + (width - 56f) * i / 3f
            line(c, x, cy - 13f, x, cy + 12f, outline, 1.8f)
            if (i > 0) {
                val previous = left + 28f + (width - 56f) * (i - 1) / 3f
                line(c, previous, cy - 5f, previous + 29f, cy - 5f, myofibril, 2.4f)
                line(c, x - 29f, cy + 4f, x, cy + 4f, myofibril, 2.4f)
                val center = (x + previous) * .5f
                line(c, center - 14f, cy, center + 14f, cy, 0xffbf8063, 2.8f)
            }
        }
        if (step == 2 && t > .72f) {
            val pulseX = left + 13f + (width - 26f) * ((t - .72f) / .28f)
            disc(c, pulseX, cy + 24f, 3.2f, excited, cream)
        }
        trace.rewind()
        trace.moveTo(left + 15f, 253f)
        trace.cubicTo(left + width * .36f, 246f, right - width * .35f, 257f, right - 15f, 253f)
        stroke(c, trace, 0xffb0cec4, 6f)
        for (i in 0..5) {
            val x = left + 25f + (width - 50f) * i / 5f
            val f = (shortening - i * .06f).coerceAtLeast(0f)
            disc(c, x, 252f + 15f * f, 2.7f, teal, cream)
        }
        line(c, 229f, 321f, 249f, 283f, outline, 1.1f)
        label(c, R.string.health_atlas_cardiac_filaments_label, 251f, 338f, 109f)
        disc(c, 94f, 334f, 3.5f, teal, cream)
        label(c, R.string.health_atlas_cardiac_calcium_label, 128f, 338f, 60f)
    }

    private fun colorRoute(c: Canvas, route: PathMeasure, progress: Float) {
        trace.rewind()
        if (route.getSegment(0f, route.length * progress, trace, true)) stroke(c, trace, excited, 2.8f)
    }

    private fun path(block: Path.() -> Unit) = Path().apply(block)
}
