package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path

internal object HealthAtlasAirwayMotion {
    fun surfaceTravel(step: Int, fraction: Float) = when (step) {
        3 -> HealthAtlasFunctionStory.safePhase(fraction) * .84f
        4 -> .84f + .16f * HealthAtlasFunctionStory.safePhase(fraction)
        else -> 0f
    }

    fun fall(step: Int, fraction: Float, index: Int) =
        if (step == 0) (HealthAtlasFunctionStory.safePhase(fraction) * 1.42f - index * .13f).coerceIn(0f, 1f) else 1f
}

internal class HealthAtlasAirwayStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.AIRWAY_CLEARANCE) {
    private val lungFill = shade(34f, 138f, 0xffffe5de, 0xffdf9a9d)
    private val cellFill = shade(230f, 302f, 0xffc4e5e7, 0xff79aab8)
    private val shape = Path()
    private val leftLung = Path().apply {
        moveTo(85f, 66f)
        cubicTo(80f, 54f, 69f, 57f, 57f, 69f)
        cubicTo(43f, 84f, 39f, 106f, 40f, 125f)
        cubicTo(42f, 140f, 59f, 139f, 76f, 131f)
        cubicTo(85f, 127f, 88f, 120f, 87f, 103f)
        close()
    }
    private val rightLung = Path().apply {
        moveTo(106f, 66f)
        cubicTo(113f, 55f, 125f, 59f, 137f, 74f)
        cubicTo(150f, 92f, 154f, 113f, 151f, 127f)
        cubicTo(147f, 141f, 132f, 139f, 120f, 134f)
        cubicTo(111f, 131f, 105f, 124f, 106f, 112f)
        cubicTo(114f, 103f, 114f, 95f, 106f, 89f)
        close()
    }
    private val airway = Path().apply {
        moveTo(95f, 34f)
        cubicTo(92f, 42f, 96f, 50f, 96f, 65f)
        lineTo(96f, 87f)
        cubicTo(91f, 95f, 78f, 98f, 62f, 108f)
        moveTo(96f, 87f)
        cubicTo(102f, 93f, 117f, 99f, 131f, 110f)
    }
    private val clearance = track(Path().apply {
        moveTo(61f, 109f)
        cubicTo(70f, 102f, 87f, 98f, 95f, 89f)
        cubicTo(99f, 75f, 94f, 51f, 95f, 34f)
    })
    private val toEsophagus = track(Path().apply {
        moveTo(95f, 34f)
        cubicTo(104f, 24f, 111f, 32f, 108f, 48f)
        cubicTo(109f, 61f, 118f, 69f, 123f, 79f)
    })
    private val bendInk = 0xff446b7d
    private val filmInk = 0xffa4c9c8
    private val dustInk = 0xffae784d

    init { tag = "atlas-function-airway-clearance-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        overview(c, step, t)
        crossSection(c, step, t)
    }

    private fun overview(c: Canvas, step: Int, t: Float) {
        for (lung in listOf(leftLung, rightLung)) {
            ink(cream)
            paint.shader = lungFill
            c.drawPath(lung, paint)
            paint.shader = null
            stroke(c, lung, coral, 1.25f)
        }
        if (step == 4) {
            shape.rewind()
            shape.moveTo(96f, 34f)
            shape.cubicTo(107f, 22f, 111f, 33f, 108f, 48f)
            shape.cubicTo(109f, 61f, 118f, 69f, 123f, 79f)
            stroke(c, shape, 0xffcf9683, 7.5f)
            stroke(c, shape, 0xffffe3cf, 4f)
        }
        stroke(c, airway, bendInk, 12f)
        stroke(c, airway, 0xffa9d0da, 8f)
        stroke(c, airway, 0xffe9f4ed, 4f)
        for (i in 0..3) line(c, 91f, 49f + 9f * i, 101f, 49f + 9f * i, 0xff6f9daa, 1.1f)
        line(c, 113f, 43f, 205f, 43f, filmInk, 1.05f)
        label(c, R.string.health_atlas_airway_throat, 259f, 47f, 103f)
        disc(c, 82f, 97f, 12f, 0xffd8efea, teal)
        disc(c, 82f, 97f, 4f, teal, cream)
        line(c, 95f, 108f, 206f, 117f, teal, 1.1f)
        label(c, R.string.health_atlas_airway_airway_wall, 270f, 121f, 116f)
        if (step == 3) {
            val f = HealthAtlasAirwayMotion.surfaceTravel(step, t)
            at(clearance, .27f + .71f * f) { x, y -> disc(c, x, y, 4.3f, teal, cream) }
        } else if (step == 4) {
            val f = (t * 1.38f).coerceIn(0f, 1f)
            if (f < .3f) at(clearance, .866f + f * (.134f / .3f)) { x, y -> disc(c, x, y, 4.3f, teal, cream) }
            else at(toEsophagus, (f - .3f) / .7f) { x, y -> disc(c, x, y, 4.3f, teal, cream) }
            line(c, 133f, 73f, 181f, 74f, coral, 1.1f)
            label(c, R.string.health_atlas_airway_esophagus, 245f, 78f, 122f)
        }
    }

    private fun crossSection(c: Canvas, step: Int, t: Float) {
        rounded(c, 18f, 147f, 342f, 330f, 8f, 0xfff5f4e9)
        if (step >= 3) {
            arrow(c, 99f, 177f, 222f, 177f, teal)
            label(c, R.string.health_atlas_airway_toward_throat, 278f, 181f, 100f)
        } else {
            label(c, if (step == 0) R.string.health_atlas_airway_particles else R.string.health_atlas_airway_mucus,
                266f, 174f, 121f)
        }
        rounded(c, 25f, 199f, 335f, 223f, 8f, 0xffc6e2d6)
        rounded(c, 25f, 217f, 335f, 253f, 4f, 0xffdcecef)
        line(c, 34f, 218f, 327f, 218f, filmInk, 1.1f)
        for (index in 0..6) {
            val x = 48f + index * 44f
            if (index == 3) {
                goblet(c, x, step, t)
            } else {
                oval(c, x - 20f, 244f, x + 20f, 305f, cellFill, bendInk)
                oval(c, x - 8f, 277f, x + 8f, 290f, 0xffa9b5db, violet)
                for (fiber in -2..2) cilium(c, x + fiber * 6f, 246f, index, fiber, step, t)
            }
        }
        c.save()
        c.clipRect(25f, 181f, 335f, 221f)
        val drift = HealthAtlasAirwayMotion.surfaceTravel(step, t) * 288f
        for (i in 0..2) {
            val descent = HealthAtlasAirwayMotion.fall(step, t, i)
            val x = 50f + i * 32f + drift + 4f * wave(descent * .5f)
            val y = 184f + 25f * descent + i * 3f
            disc(c, x, y, 4f - i * .4f, dustInk, cream)
        }
        c.restore()
        if (step == 1) {
            label(c, R.string.health_atlas_airway_goblet, 181f, 319f, 140f)
        } else {
            label(c, R.string.health_atlas_airway_cilia, 45f, 319f, 50f)
            line(c, 34f, 304f, 29f, 239f, teal, 1f)
            label(c, R.string.health_atlas_airway_mucus, 268f, 319f, 114f)
            line(c, 324f, 310f, 331f, 215f, teal, 1f)
        }
    }

    private fun goblet(c: Canvas, x: Float, step: Int, t: Float) {
        shape.rewind()
        shape.moveTo(x - 17f, 246f)
        shape.cubicTo(x - 21f, 263f, x - 3f, 271f, x - 5f, 290f)
        shape.quadTo(x - 4f, 304f, x + 7f, 301f)
        shape.cubicTo(x + 11f, 285f, x + 4f, 274f, x + 17f, 248f)
        shape.quadTo(x + 2f, 241f, x - 17f, 246f)
        shape.close()
        ink(0xffb0d6bb)
        c.drawPath(shape, paint)
        stroke(c, shape, teal, 1.2f)
        disc(c, x + 2f, 288f, 5f, violet, cream)
        for (i in -1..1) {
            val upward = if (step == 1) ((t - (i + 1) * .14f) * 1.38f).coerceIn(0f, 1f) else 0f
            disc(c, x + 7f * i + 7f * upward, 257f - 51f * upward + 2f * i, 4f, 0xff69a68f, cream)
        }
    }

    private fun cilium(c: Canvas, x: Float, y: Float, column: Int, fiber: Int, step: Int, t: Float) {
        val beat = if (step in 2..4) 13f * wave(t * 2f - .13f * column - .035f * fiber) else 2f
        shape.rewind()
        shape.moveTo(x, y)
        shape.cubicTo(x + beat * .2f, y - 9f, x + beat, y - 14f, x + beat, y - 25f + kotlin.math.abs(beat) * .20f)
        stroke(c, shape, teal, 1.6f)
    }
}
