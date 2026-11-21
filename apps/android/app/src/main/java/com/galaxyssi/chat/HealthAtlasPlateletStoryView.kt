package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasPlateletStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.PLATELET_HEMOSTASIS) {
    private data class Pose(val x: Float, val y: Float, val angle: Float)
    private data class Arrival(val from: Pose, val to: Pose, val delay: Float)

    private val liningInk = 0xffa7697b
    private val wallInk = 0xffbe8b93
    private val plateletInk = 0xff946024
    private val plateletFill = 0xffffd694
    private val fiberInk = 0xff307e79
    private val signalInk = 0xff87649d
    private val lumen = shade(94f, 234f, 0xfffbfffc, 0xffdceeea)
    private val wall = shade(80f, 270f, 0xfff3d7d7, 0xffe8b6b9)
    private val topWall = Path().apply {
        addRoundRect(24f, 80f, 336f, 113f, 14f, 14f, Path.Direction.CW)
    }
    private val lowerWall = Path().apply {
        moveTo(24f, 234f)
        quadTo(24f, 221f, 40f, 221f)
        lineTo(148f, 221f)
        quadTo(157f, 221f, 162f, 230f)
        lineTo(170f, 243f)
        quadTo(172f, 248f, 167f, 256f)
        quadTo(160f, 270f, 150f, 270f)
        lineTo(40f, 270f)
        quadTo(24f, 270f, 24f, 255f)
        close()
    }
    private val exposedEdge = Path().apply {
        moveTo(151f, 224f)
        quadTo(157f, 226f, 161f, 234f)
        lineTo(167f, 244f)
        quadTo(170f, 249f, 163f, 258f)
    }
    private val anchor = Arrival(Pose(104f, 165f, -22f), Pose(166f, 221f, 18f), 0f)
    private val recruits = listOf(
        Arrival(Pose(225f, 154f, 20f), Pose(185f, 214f, -18f), 0f),
        Arrival(Pose(252f, 188f, -25f), Pose(199f, 226f, 20f), .10f),
        Arrival(Pose(126f, 129f, 11f), Pose(176f, 201f, -28f), .20f),
        Arrival(Pose(229f, 205f, 12f), Pose(181f, 234f, 8f), .30f),
    )
    private val strands = listOf(
        fiber(157f, 226f, 167f, 199f, 193f, 207f, 205f, 228f),
        fiber(162f, 239f, 176f, 224f, 183f, 200f, 200f, 213f),
        fiber(160f, 219f, 180f, 216f, 187f, 236f, 201f, 238f),
        fiber(172f, 199f, 170f, 214f, 189f, 218f, 190f, 247f),
        fiber(172f, 246f, 183f, 233f, 198f, 222f, 199f, 214f),
    )
    private val scratch = Path()
    private val pointCount = 14
    private val unitX = FloatArray(pointCount) { cos(it * 2 * PI / pointCount - PI / 2).toFloat() }
    private val unitY = FloatArray(pointCount) { sin(it * 2 * PI / pointCount - PI / 2).toFloat() }
    private val outlineX = FloatArray(pointCount)
    private val outlineY = FloatArray(pointCount)

    init { tag = "atlas-function-platelet-hemostasis-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val phase = HealthAtlasFunctionStory.safePhase(t)
        vessel(c, if (step == 0) wave(phase * .5f) else 0f)
        redCell(c, 64f, 151f, -21f)
        redCell(c, 211f, 130f, 14f)
        redCell(c, 301f, 194f, -17f)
        platelet(c, 57f, 195f, 15f, 0f, .74f)
        platelet(c, 289f, 164f, 24f, 0f, .70f)

        val attached = when (step) {
            0 -> 0f
            1 -> ease(phase / .82f)
            else -> 1f
        }
        val active = when {
            step < 2 -> 0f
            step == 2 -> ease(phase / .58f)
            else -> 1f
        }
        arriving(c, anchor, attached, active)
        if (step == 2) signals(c, ease((phase - .16f) / .76f), 1f)
        if (step == 3) signals(c, 1f, 1f - ease(phase / .42f))
        for (recruit in recruits) {
            val joined = when {
                step < 3 -> 0f
                step == 3 -> ease((phase - recruit.delay) / .64f)
                else -> 1f
            }
            arriving(c, recruit, joined, ease(joined / .7f))
        }
        if (step == 4) fibrin(c, phase)
        annotations(c, step)
    }

    private fun vessel(c: Canvas, focus: Float) {
        ink(cream)
        paint.shader = lumen
        c.drawRoundRect(24f, 88f, 336f, 235f, 15f, 15f, paint)
        paint.shader = null
        drawWall(c, topWall)
        drawLowerWall(c, focus)
        c.save()
        c.translate(360f, 0f)
        c.scale(-1f, 1f)
        drawLowerWall(c, focus)
        c.restore()
        for (i in 0..7) liningCell(c, 46f + 38f * i, 105f)
        line(c, 87f, 62f, 87f, 98f, wallInk, 1.1f)
        label(c, R.string.health_atlas_platelet_vessel_lining, 87f, 55f, 124f)
        arrow(c, 245f, 66f, 299f, 66f, fiberInk)
        label(c, R.string.health_atlas_platelet_blood_flow, 272f, 55f, 106f)
    }

    private fun drawWall(c: Canvas, shape: Path) {
        ink(cream)
        paint.shader = wall
        c.drawPath(shape, paint)
        paint.shader = null
        stroke(c, shape, wallInk, 1.2f)
    }

    private fun drawLowerWall(c: Canvas, focus: Float) {
        drawWall(c, lowerWall)
        line(c, 37f, 251f, 149f, 251f, 0xffdca2a8, 1.3f)
        for (i in 0..2) liningCell(c, 50f + 39f * i, 225f)
        stroke(c, exposedEdge, 0xfff4d6aa, 4f + 3f * focus.coerceAtLeast(0f))
        stroke(c, exposedEdge, 0xffae7c51, 1.3f)
    }

    private fun liningCell(c: Canvas, x: Float, y: Float) {
        oval(c, x - 16f, y - 4f, x + 16f, y + 4f, 0xfff4c8cf, liningInk)
        oval(c, x - 3f, y - 1.7f, x + 3f, y + 1.7f, liningInk, liningInk)
    }

    private fun redCell(c: Canvas, x: Float, y: Float, angle: Float) {
        c.save()
        c.translate(x, y)
        c.rotate(angle)
        oval(c, -18f, -9f, 18f, 9f, 0xffe7aaad, 0xffbd7e8b)
        oval(c, -8f, -3.8f, 8f, 3.8f, 0xfff6c8c7, 0xffdc9da5)
        c.restore()
    }

    private fun arriving(c: Canvas, arrival: Arrival, f: Float, activation: Float) {
        val (from, to) = arrival
        platelet(c, mix(from.x, to.x, f), mix(from.y, to.y, f), mix(from.angle, to.angle, f), activation)
    }

    private fun platelet(c: Canvas, x: Float, y: Float, angle: Float, activation: Float, size: Float = 1f) {
        c.save()
        c.translate(x, y)
        c.rotate(angle)
        c.scale(size, size)
        // Morph the same disk into a rounded, projected silhouette without moving its center.
        for (i in 0 until pointCount) {
            val tip = if (i % 2 == 0) 1f else 0f
            outlineX[i] = unitX[i] * (13f + activation * (8f * tip - 3f))
            outlineY[i] = unitY[i] * (7f + activation * (8f * tip + 1f))
        }
        scratch.rewind()
        scratch.moveTo((outlineX.last() + outlineX[0]) * .5f, (outlineY.last() + outlineY[0]) * .5f)
        for (i in 0 until pointCount) {
            val next = (i + 1) % pointCount
            scratch.quadTo(outlineX[i], outlineY[i],
                (outlineX[i] + outlineX[next]) * .5f, (outlineY[i] + outlineY[next]) * .5f)
        }
        scratch.close()
        ink(plateletFill)
        c.drawPath(scratch, paint)
        stroke(c, scratch, plateletInk, 1.35f)
        disc(c, -4f, -1.5f, 1.65f, cream)
        disc(c, 3.5f, 1.5f, 1.3f, plateletInk)
        c.restore()
    }

    private fun signals(c: Canvas, spread: Float, visibility: Float) {
        if (spread <= 0f || visibility <= 0f) return
        for (i in 0..3) {
            val f = ease(spread * 1.28f - i * .09f)
            if (f > 0f) {
                val endX = 141f + i * 14f
                disc(c, mix(166f, endX, f), 221f - (36f + (i % 2) * 8f) * f,
                    (2.6f + .6f * f) * visibility, signalInk)
            }
        }
    }

    private fun fiber(x1: Float, y1: Float, cx1: Float, cy1: Float, cx2: Float, cy2: Float, x2: Float, y2: Float) =
        track(Path().apply {
            moveTo(x1, y1)
            cubicTo(cx1, cy1, cx2, cy2, x2, y2)
        })

    private fun fibrin(c: Canvas, t: Float) {
        strands.forEachIndexed { i, strand ->
            val length = strand.length * ease(.32f + t * 1.55f - i * .18f)
            scratch.rewind()
            if (strand.getSegment(0f, length, scratch, true)) {
                stroke(c, scratch, 0xffedf8ee, 4f)
                stroke(c, scratch, fiberInk, 1.75f)
            }
        }
    }

    private fun annotations(c: Canvas, step: Int) {
        when (step) {
            0 -> {
                line(c, 180f, 260f, 180f, 296f, wallInk, 1.1f)
                label(c, R.string.health_atlas_platelet_exposed_gap, 180f, 317f, 150f)
            }
            1, 2 -> {
                val x = if (step == 1) 180f else 108f
                platelet(c, x, 295f, 0f, if (step == 1) 0f else 1f, .78f)
                label(c, R.string.health_atlas_platelet_fragment, x, 319f, 118f)
                if (step == 2) {
                    disc(c, 244f, 296f, 2.6f, signalInk)
                    disc(c, 252f, 290f, 2.6f, signalInk)
                    disc(c, 260f, 296f, 2.6f, signalInk)
                    label(c, R.string.health_atlas_platelet_signals, 252f, 319f, 118f)
                }
            }
            3, 4 -> {
                platelet(c, 102f, 296f, -18f, 1f, .61f)
                platelet(c, 114f, 292f, 18f, 1f, .61f)
                label(c, R.string.health_atlas_platelet_plug, 108f, 319f, 118f)
                if (step == 4) {
                    line(c, 240f, 297f, 264f, 291f, fiberInk, 1.75f)
                    line(c, 244f, 289f, 260f, 299f, fiberInk, 1.75f)
                    label(c, R.string.health_atlas_platelet_fibrin_mesh, 252f, 319f, 118f)
                }
            }
        }
    }

    private fun mix(from: Float, to: Float, f: Float) = from + (to - from) * f

    private fun ease(value: Float): Float {
        val f = value.coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }
}
