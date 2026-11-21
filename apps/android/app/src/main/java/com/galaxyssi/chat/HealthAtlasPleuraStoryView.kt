package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import androidx.annotation.StringRes
import kotlin.math.PI
import kotlin.math.cos

internal class HealthAtlasPleuraStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.PLEURAL_COUPLING) {
    private val parietal = 0xff527f79
    private val visceral = 0xff95576b
    private val fluid = 0xffa6dbe3
    private val guide = 0xff516b72
    private val lungColor = shade(44f, 195f, 0xfffae0d9, 0xffdba0a9)
    private val edge = Path()
    private val lung = Path()
    private val dome = Path()
    private val accent = Path()
    private val airway = Path().apply {
        moveTo(180f, 40f); lineTo(180f, 97f)
        quadTo(179f, 108f, 151f, 123f)
        moveTo(180f, 97f); quadTo(185f, 106f, 210f, 120f)
    }

    init { tag = "atlas-function-pleural-coupling-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val pulse = (1f - cos(2.0 * PI * t).toFloat()) / 2f
        val breath = when (step) {
            0 -> .28f * pulse
            1 -> .55f * t
            2 -> .55f + .45f * t
            3 -> 1f - .72f * pulse
            else -> 1f - t
        }
        val widen = 1f + .11f * breath
        stroke(c, airway, 0xffab8072, 14f)
        stroke(c, airway, 0xffeed2ba, 11f)
        for (y in 47..91 step 7) line(c, 175f, y.toFloat(), 185f, y + 1f, 0xffc59883, 1f)
        for (side in -1..1 step 2) {
            c.save()
            c.translate(180f, 0f)
            c.scale(side * widen, 1f)
            hemiThorax(c, breath, heartSide = side > 0, highlightLung = step == 2)
            c.restore()
        }
        val sampleX = 180f - 102f * widen
        line(c, sampleX - 7f, 135f, 30f, 164f, guide, 1f)
        line(c, 30f, 164f, 30f, 226f, guide, 1f)
        ink(guide, 1.3f)
        c.drawCircle(sampleX, 130f, 8f, paint)
        callout(c, R.string.health_atlas_pleura_story_lung, 91f, 25f, 100f, 129f, 66f)
        callout(c, R.string.health_atlas_pleura_story_wall, 280f, 25f, 126f,
            180f + 91f * widen, 78f - 2f * breath)
        callout(c, R.string.health_atlas_pleura_story_diaphragm, 180f, 211f, 124f,
            180f, 171f + 17f * breath, below = true)
        if (step == 1 || step == 4) {
            val outer = 302f + 10f * breath
            val lower = 171f + 20f * breath
            val direction = if (step == 1) 1f else -1f
            arrow(c, outer, 129f, outer + direction * 21f, 129f - direction * 7f, teal)
            arrow(c, 239f, lower + 9f, 239f, lower + 9f + direction * 16f, teal)
        }
        if (step == 2) {
            arrow(c, 231f, 132f, 250f + 13f * breath, 145f + 12f * breath, visceral)
        }
        cutaway(c, breath, step == 3)
    }

    private fun hemiThorax(c: Canvas, breath: Float, heartSide: Boolean, highlightLung: Boolean) {
        edge.rewind()
        edge.moveTo(26f, 49f)
        edge.cubicTo(47f, 32f, 81f, 59f, 96f, 96f)
        edge.cubicTo(106f, 122f, 109f, 150f, 102f, 176f + 9f * breath)
        stroke(c, edge, 0xffe4baac, 22f)
        stroke(c, edge, 0xfff4dcd0, 18f)
        for (i in 0..4) {
            val x = 86f + 6f * i - 1.15f * i * i
            val y = 81f + 19f * i - 3f * breath
            accent.rewind()
            accent.moveTo(x + 14f, y - 4f)
            accent.quadTo(x + 8f, y + 4f, x - 13f, y + 9f)
            stroke(c, accent, 0xffb88c72, 9f)
            stroke(c, accent, 0xffffebcc, 6f)
        }
        dome.rewind()
        dome.moveTo(102f, 176f + 9f * breath)
        lungBase(dome, breath)
        dome.cubicTo(26f, 154f + 22f * breath, 14f, 165f + 17f * breath, 0f, 166f + 17f * breath)
        c.save()
        c.translate(0f, 5f)
        stroke(c, dome, 0xffa86567, 11f)
        stroke(c, dome, 0xffdfa495, 8f)
        c.restore()

        // Both layers share the moving costal and basal contour; stroke widths reveal the film.
        lung.set(edge)
        lungBase(lung, breath)
        stroke(c, lung, parietal, 7f)
        stroke(c, lung, fluid, 4.5f)
        val notch = if (heartSide) 12f else 0f
        lung.cubicTo(16f + notch, 164f + 16f * breath, 12f + notch, 147f, 19f + notch, 133f)
        lung.cubicTo(29f, 116f, 8f, 105f, 14f, 78f)
        lung.quadTo(15f, 57f, 26f, 49f)
        lung.close()
        ink(cream); paint.shader = lungColor; c.drawPath(lung, paint); paint.shader = null
        stroke(c, lung, visceral, if (highlightLung) 2.3f else 1.5f)
        c.save()
        c.clipPath(lung)
        accent.rewind()
        accent.moveTo(33f, 91f)
        accent.quadTo(64f, 126f, 106f, 151f + 5f * breath)
        if (!heartSide) {
            accent.moveTo(57f, 116f)
            accent.quadTo(77f, 108f, 105f, 109f)
        }
        stroke(c, accent, 0xffc48e98, 1.3f)
        c.restore()
    }

    private fun lungBase(path: Path, breath: Float) {
        path.cubicTo(81f, 174f + 9f * breath, 66f, 147f + 22f * breath, 42f, 154f + 22f * breath)
    }

    private fun cutaway(c: Canvas, breath: Float, sliding: Boolean) {
        rounded(c, 20f, 226f, 340f, 318f, 7f, 0xfff5ded2)
        rounded(c, 24f, 269f, 336f, 314f, 5f, 0xfff5c7c7)
        ink(fluid); c.drawRect(24f, 266f, 336f, 272f, paint)
        line(c, 24f, 266f, 336f, 266f, parietal, 1.8f)
        line(c, 24f, 272f, 336f, 272f, visceral, 1.8f)
        // The ticks are fixed to their respective sheets, not particles moving in the liquid.
        for (i in 0..4) {
            val wallX = 55f + i * 54f + 9f * breath
            val lungX = 55f + i * 54f + 35f * breath
            line(c, wallX, 266f, wallX - 5f, 253f, if (sliding) parietal else 0xffaeaca0, 2f)
            line(c, lungX, 272f, lungX + 5f, 286f, if (sliding) visceral else 0xffc79a9f, 2f)
        }
        label(c, R.string.health_atlas_pleura_story_detail, 180f, 245f, 220f)
        key(c, R.string.health_atlas_pleura_story_parietal, 64f, parietal)
        key(c, R.string.health_atlas_pleura_story_fluid, 180f, fluid)
        key(c, R.string.health_atlas_pleura_story_visceral, 296f, visceral)
    }

    private fun key(c: Canvas, @StringRes id: Int, x: Float, color: Long) {
        line(c, x - 9f, 324f, x + 9f, 324f, color, 4f)
        label(c, id, x, 342f, 112f)
    }

    private fun callout(c: Canvas, @StringRes id: Int, x: Float, y: Float, width: Float,
        targetX: Float, targetY: Float, below: Boolean = false) {
        line(c, x, y + if (below) -16f else 6f, targetX, targetY, guide, 1f)
        disc(c, targetX, targetY, 1.6f, guide)
        label(c, id, x, y, width)
    }
}
