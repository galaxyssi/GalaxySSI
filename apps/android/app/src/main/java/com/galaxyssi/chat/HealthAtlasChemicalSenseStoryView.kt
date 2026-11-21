package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure

internal object HealthAtlasChemicalSenseMotion {
    fun transfer(t: Float, index: Int, startsAt: Float = 0f): Float =
        ((HealthAtlasFunctionStory.safePhase(t) - startsAt - .078f * index) * 1.55f).coerceIn(0f, 1f)

    fun odorChannels(variant: Boolean) = if (variant) listOf(1, 2) else listOf(0, 2)
}

internal class HealthAtlasChemicalSenseStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val senseSmell = story == HealthAtlasFunctionStory.OLFACTION
    private val flesh = shade(42f, 304f, 0xffffe6d3, 0xffe0a4a5)
    private val tissue = shade(98f, 300f, 0xfff6dcd7, 0xffd897a1)
    private val cell = shade(110f, 275f, 0xffdbefe9, 0xff8eb7aa)
    private val floor = shade(100f, 276f, 0xffebf4ef, 0xffb8d1ce)
    private val shape = Path()
    private val airway = Path().apply {
        moveTo(31f, 242f); cubicTo(47f, 240f, 65f, 225f, 96f, 214f)
        cubicTo(136f, 195f, 146f, 143f, 182f, 121f); quadTo(203f, 109f, 235f, 119f)
    }
    private val inhaled by lazy { track(airway) }
    private val smellRoutes = List(3) { i -> Path().apply {
        val x = 79f + i * 94f
        moveTo(x, 218f); cubicTo(x - 10f, 195f, x + 13f, 171f, x, 130f)
        quadTo(x - 3f, 100f, x, 88f)
    } }
    private val smellMeasures by lazy { smellRoutes.map(::track) }
    private val tasteNerve = Path().apply {
        moveTo(182f, 272f)
        cubicTo(192f, 287f, 214f, 289f, 229f, 297f)
        quadTo(254f, 320f, 315f, 306f)
    }
    private val tasteTrack by lazy { track(tasteNerve) }

    init { tag = if (senseSmell) "atlas-function-olfaction-art" else "atlas-function-taste-signal-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        if (senseSmell) when (step) {
            0 -> nasal(c, t)
            1, 2 -> receptors(c, step == 2, t)
            3 -> bulb(c, t)
            else -> corticalPattern(c, t)
        } else if (step == 0) tongue(c, t) else tasteBud(c, step, t)
    }

    private fun nasal(c: Canvas, t: Float) {
        shape.rewind()
        shape.moveTo(291f, 319f); shape.cubicTo(264f, 280f, 296f, 269f, 325f, 210f)
        shape.cubicTo(351f, 157f, 325f, 62f, 258f, 44f)
        shape.cubicTo(183f, 19f, 107f, 51f, 100f, 125f)
        shape.cubicTo(95f, 177f, 67f, 192f, 58f, 219f)
        shape.quadTo(57f, 232f, 95f, 233f)
        shape.quadTo(103f, 235f, 102f, 247f); shape.quadTo(108f, 257f, 136f, 254f)
        shape.quadTo(105f, 264f, 113f, 276f); shape.cubicTo(112f, 307f, 165f, 303f, 208f, 309f)
        shape.lineTo(221f, 332f); shape.close()
        paintFigure(c, flesh, coral)
        shape.rewind()
        shape.moveTo(84f, 216f); shape.cubicTo(116f, 199f, 121f, 153f, 152f, 128f)
        shape.cubicTo(170f, 105f, 219f, 100f, 244f, 116f)
        shape.cubicTo(264f, 155f, 265f, 214f, 251f, 232f)
        shape.quadTo(222f, 244f, 207f, 236f)
        shape.cubicTo(177f, 213f, 119f, 234f, 84f, 216f); shape.close()
        paintFigure(c, floor, blue)
        for (i in 0..2) {
            shape.rewind(); shape.moveTo(218f + i * 6f, 143f + 28f * i)
            shape.cubicTo(206f, 136f + 30f * i, 163f, 147f + 29f * i, 153f + i * 5f, 167f + 24f * i)
            stroke(c, shape, 0xff8fb4b5, 5.5f)
        }
        line(c, 181f, 114f, 231f, 112f, teal, 5.5f)
        stroke(c, airway, 0xff8ab4be, 1.8f)
        particles(c, inhaled, t, sienna, 5)
        leader(c, R.string.health_atlas_sense_smell_patch, 185f, 70f, 205f, 111f, teal)
        leader(c, R.string.health_atlas_sense_smell_cavity, 273f, 268f, 235f, 227f, blue)
    }

    private fun receptors(c: Canvas, active: Boolean, t: Float) {
        c.save()
        c.translate(0f, 360f); c.scale(1f, -1f)
        rounded(c, 27f, 162f, 333f, 249f, 17f, 0xfff6d8cd)
        rounded(c, 27f, 120f, 333f, 160f, 17f, 0xffc5ddda)
        for (i in 0..7) {
            val x = 48f + i * 38f
            oval(c, x - 15f, 189f, x + 15f, 238f, peach, coral)
            disc(c, x, 218f, 5f, violet)
        }
        for (i in 0..2) {
            val x = 80f + i * 99f
            line(c, x, 221f, x, 278f, teal, 4.3f)
            oval(c, x - 12f, 176f, x + 12f, 222f, cell, teal)
            line(c, x, 175f, x, 147f, teal, 3.5f)
            for (side in listOf(-1, 1)) for (j in 0..2) {
                shape.rewind(); shape.moveTo(x, 145f)
                shape.quadTo(x + side * 10f, 133f + j * 6f, x + side * (24f + 7f * j), 138f - j * 5f)
                stroke(c, shape, teal, 1.4f)
            }
            for (j in 0..2) {
                val f = HealthAtlasChemicalSenseMotion.transfer(t, j)
                disc(c, x + 12f * (j - 1) + 3f * wave(t + i), 79f + 53f * f - j * 11f, 3.2f, sienna, cream)
            }
            if (active && i != 1) {
                val f = HealthAtlasChemicalSenseMotion.transfer(t, 0, .2f)
                disc(c, x, 149f + 118f * f, 5.1f, violet, cream)
            }
        }
        c.restore()
        leader(c, R.string.health_atlas_sense_smell_cilia, 83f, 314f, 55f, 216f, teal)
        leader(c, R.string.health_atlas_sense_smell_layer, 269f, 314f, 311f, 236f, blue)
    }

    private fun bulb(c: Canvas, t: Float) {
        val variants = HealthAtlasChemicalSenseMotion.odorChannels(false)
        oval(c, 34f, 58f, 326f, 110f, flesh, coral)
        rounded(c, 24f, 126f, 336f, 148f, 7f, 0xffdcc49e)
        label(c, R.string.health_atlas_sense_smell_bulb_label, 180f, 43f, 164f)
        label(c, R.string.health_atlas_sense_smell_plate, 180f, 166f, 145f)
        for (i in 0..2) {
            val x = 79f + i * 94f
            val color = if (i in variants) listOf(blue, violet, teal)[i] else 0xffa1b4ae
            disc(c, x, 137f, 6f, cream)
            stroke(c, smellRoutes[i], color, 3.5f)
            disc(c, x, 88f, 13f, color, cream)
            oval(c, x - 13f, 216f, x + 13f, 245f, cell, teal)
            if (i in variants) particles(c, smellMeasures[i], t, color, 3)
        }
        label(c, R.string.health_atlas_sense_smell_patch, 180f, 295f, 240f)
    }

    private fun corticalPattern(c: Canvas, t: Float) {
        val variants = HealthAtlasChemicalSenseMotion.odorChannels(t > .52f)
        oval(c, 23f, 74f, 115f, 277f, flesh, coral)
        shape.rewind(); shape.moveTo(290f, 80f)
        shape.cubicTo(273f, 101f, 304f, 123f, 283f, 145f)
        shape.cubicTo(261f, 169f, 311f, 194f, 289f, 219f)
        shape.cubicTo(275f, 234f, 306f, 252f, 295f, 280f)
        stroke(c, shape, 0xffae83a5, 25f)
        stroke(c, shape, 0xffe0bad7, 16f)
        for (i in 0..2) {
            val y = 116f + i * 59f
            val color = if (i in variants) listOf(blue, violet, teal)[i] else 0xff9daba8
            disc(c, 69f, y, 13f, color, cream)
            line(c, 82f, y, 285f, y, color, 2.1f)
            if (i in variants) disc(c, 92f + 177f * (t * 2.1f % 1f), y, 5.1f, color, cream)
        }
        label(c, R.string.health_atlas_sense_smell_bulb_label, 71f, 314f, 128f)
        label(c, R.string.health_atlas_sense_smell_cortex, 278f, 314f, 142f)
    }

    private fun tongue(c: Canvas, t: Float) {
        shape.rewind(); shape.moveTo(41f, 202f)
        shape.cubicTo(31f, 133f, 112f, 145f, 149f, 135f)
        shape.cubicTo(213f, 122f, 307f, 110f, 323f, 160f)
        shape.cubicTo(348f, 227f, 203f, 254f, 109f, 254f)
        shape.quadTo(48f, 253f, 41f, 202f); shape.close()
        paintFigure(c, flesh, coral)
        for (i in 0..3) for (j in 0..2) {
            val x = 89f + 54f * i + j * 6f
            val y = 184f + 17f * j - 5f * i
            oval(c, x - 9f, y - 5f, x + 9f, y + 5f, peach, coral)
            disc(c, x, y, 2f, cream)
        }
        shape.rewind(); shape.moveTo(56f, 154f)
        shape.cubicTo(131f, 115f, 231f, 119f, 300f, 126f)
        stroke(c, shape, 0xff82acae, 6f)
        for (i in 0..7) {
            val x = 69f + 31f * i
            disc(c, x, 98f + 27f * t + 8f * wave(t + i * .31f), 3.8f, sienna, cream)
        }
        leader(c, R.string.health_atlas_sense_taste_saliva, 91f, 72f, 89f, 138f, blue)
        leader(c, R.string.health_atlas_sense_taste_papilla, 267f, 284f, 265f, 192f, coral)
    }

    private fun tasteBud(c: Canvas, step: Int, t: Float) {
        oval(c, 74f, 80f, 284f, 267f, tissue, coral)
        rounded(c, 28f, 72f, 156f, 108f, 11f, peach)
        rounded(c, 204f, 72f, 332f, 108f, 11f, peach)
        for (i in 0..4) {
            val a = i - 2
            shape.rewind(); shape.moveTo(179f + a * 7f, 104f)
            shape.cubicTo(183f + a * 35f, 129f, 184f + a * 39f, 195f, 183f + a * 12f, 255f)
            shape.cubicTo(162f + a * 11f, 217f, 157f + a * 37f, 140f, 179f + a * 7f, 104f)
            shape.close()
            paintFigure(c, if (a == 0 && step >= 2) cell else flesh, if (a == 0) teal else coral)
            disc(c, 170f + a * 26f, 189f, 5.5f, if (a == 0) violet else coral)
            line(c, 179f + a * 7f, 104f, 179f + a * 8f, 90f, teal, 1.45f)
        }
        stroke(c, tasteNerve, 0xff99bab6, 13f)
        stroke(c, tasteNerve, blue, 2.7f)
        if (step <= 2) for (i in 0..4) {
            val f = HealthAtlasChemicalSenseMotion.transfer(t, i)
            disc(c, 181f + (i - 2) * (9f - f * 6f), 48f + 38f * f - i * 3f, 3.5f, sienna, cream)
        }
        if (step == 2) disc(c, 179f, 111f + 115f * t, 5.5f, violet, cream)
        if (step >= 3) for (i in 0..2) {
            val f = HealthAtlasChemicalSenseMotion.transfer(t, i, .12f)
            disc(c, 176f + i * 4f + 2f * wave(t + i), 248f + 24f * f, 3.5f, violet, cream)
        }
        if (step == 4) particles(c, tasteTrack, t, blue, 4)
        if (step <= 2) leader(c, R.string.health_atlas_sense_taste_pore_label, 280f, 45f, 198f, 85f, sienna)
        if (step == 2) leader(c, R.string.health_atlas_sense_taste_cell, 271f, 126f, 189f, 160f, teal)
        if (step >= 3) {
            label(c, R.string.health_atlas_sense_taste_nerve, 275f, 343f, 153f)
            leader(c, R.string.health_atlas_sense_taste_atp_label, 98f, 294f, 171f, 260f, violet)
        }
    }

    private fun leader(c: Canvas, id: Int, x: Float, y: Float, tx: Float, ty: Float, color: Long) {
        val start = y + if (ty > y) 8f else -15f
        line(c, x, start, tx, ty, color, 1.25f)
        disc(c, tx, ty, 2.3f, color, cream)
        label(c, id, x, y, minOf(2f * x - 8f, 712f - 2f * x, 145f))
    }

    private fun paintFigure(c: Canvas, fill: android.graphics.Shader, edge: Long) {
        ink(cream); paint.shader = fill; c.drawPath(shape, paint); paint.shader = null
        stroke(c, shape, edge, 1.3f)
    }

    private fun particles(c: Canvas, path: PathMeasure, t: Float, color: Long, count: Int) {
        for (i in 0 until count) {
            val f = HealthAtlasChemicalSenseMotion.transfer(t, i)
            at(path, f) { x, y -> disc(c, x, y, if (i == 0) 4.8f else 3.6f, color, cream) }
        }
    }
}
