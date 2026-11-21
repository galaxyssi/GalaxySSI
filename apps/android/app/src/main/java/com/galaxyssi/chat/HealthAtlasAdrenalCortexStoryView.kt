package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import com.galaxyssi.chat.R.string

internal class HealthAtlasAdrenalCortexStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasEndocrineCellStoryView(context, story, HealthAtlasEndocrineCellAssignments.CORTEX) {
    private val capsule = 0xff986b42
    private val zoneFill = longArrayOf(0xffebca8b, 0xffe9aa8c, 0xffd6a0ae)
    private val zoneInk = longArrayOf(0xff856121, 0xffa5553f, 0xff834a6f)
    private val zoneMuted = longArrayOf(0xffefdfbe, 0xffead1c1, 0xffe5cdd6)
    private val top = floatArrayOf(102f, 145f, 216f)
    private val bottom = floatArrayOf(145f, 216f, 261f)
    private val zoneTitle = intArrayOf(
        string.health_atlas_cortex_output_art_glomerulosa,
        string.health_atlas_cortex_output_art_fasciculata,
        string.health_atlas_cortex_output_art_reticularis,
    )
    private val hormone = intArrayOf(
        string.health_atlas_cortex_output_art_aldosterone,
        string.health_atlas_cortex_output_art_cortisol,
        string.health_atlas_cortex_output_art_androgen,
    )
    private val section = curve {
        moveTo(52f, 232f)
        cubicTo(59f, 201f, 103f, 159f, 141f, 115f)
        cubicTo(161f, 91f, 180f, 84f, 195f, 98f)
        cubicTo(229f, 126f, 266f, 214f, 306f, 239f)
        cubicTo(333f, 262f, 307f, 286f, 268f, 270f)
        cubicTo(238f, 258f, 210f, 255f, 175f, 269f)
        cubicTo(121f, 289f, 38f, 277f, 52f, 232f)
        close()
    }
    private val rim = track(section)
    private val sinusoid = curve {
        moveTo(251f, 82f)
        cubicTo(284f, 111f, 219f, 137f, 250f, 172f)
        cubicTo(284f, 202f, 228f, 229f, 252f, 260f)
        quadTo(267f, 278f, 305f, 287f)
    }
    private val sinusoidTrack = track(sinusoid)

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> locate(c, t)
            4 -> drain(c, t)
            else -> zone(c, step - 1, t)
        }
    }

    private fun locate(c: Canvas, t: Float) {
        sectionLayer(c, 1f, 0xfff3dfb9, capsule)
        sectionLayer(c, .94f, zoneFill[0], zoneInk[0])
        sectionLayer(c, .83f, zoneFill[1], zoneInk[1])
        sectionLayer(c, .60f, zoneFill[2], zoneInk[2])
        sectionLayer(c, .45f, 0xffd4b6bb, 0xff926b77)
        at(rim, .03f + .36f * t) { x, y ->
            ink(cream, 4.5f); c.drawCircle(x, y, 5f, paint)
            ink(capsule, 1.8f); c.drawCircle(x, y, 5f, paint)
        }
        label(c, string.health_atlas_cortex_output_art_capsule, 78f, 102f, 123f)
        line(c, 82f, 112f, 104f, 155f, capsule, 1.3f)
        label(c, string.health_atlas_cortex_output_art_cortex, 272f, 111f, 140f)
        line(c, 266f, 123f, 232f, 173f, zoneInk[1], 1.4f)
        label(c, string.health_atlas_cortex_output_art_medulla, 180f, 222f, 105f)
        label(c, string.health_atlas_cortex_output_art_section, 180f, 315f, 285f)
    }

    private fun sectionLayer(c: Canvas, scale: Float, color: Long, outline: Long) {
        c.save()
        c.scale(scale, scale, 180f, 226f)
        ink(color); c.drawPath(section, paint)
        stroke(c, section, outline, 1.5f)
        c.restore()
    }

    private fun zone(c: Canvas, index: Int, t: Float) {
        label(c, zoneTitle[index], 180f, 64f, 275f)
        rounded(c, 29f, 91f, 191f, 282f, 6f, 0xfff1ddba)
        for (i in 0..2) {
            val y1 = top[i]
            val y2 = bottom[i]
            rounded(c, 29f, y1, 191f, y2, 0f, if (i == index) zoneFill[i] else zoneMuted[i])
            line(c, 29f, y1, 191f, y1, zoneInk[i], 1f)
        }
        rounded(c, 29f, 261f, 191f, 282f, 0f, 0xffdac9c8)
        line(c, 29f, 261f, 191f, 261f, divider, 1f)
        drawTexture(c, index)
        val scanX = 40f + 140f * t
        rounded(c, scanX - 7f, top[index] + 3f, scanX + 7f, bottom[index] - 3f, 4f, 0x55fff8eb)
        line(c, scanX, top[index] + 3f, scanX, bottom[index] - 3f, cream, 1.6f)
        val center = (top[index] + bottom[index]) * .5f
        line(c, 196f, center, 317f, center, divider, 1.4f)
        outputGlyph(c, index, 203f + 110f * t, center)
        label(c, hormone[index], 267f, center + 27f, 126f)
        label(c, string.health_atlas_cortex_output_art_depth, 109f, 309f, 189f)
    }

    private fun drawTexture(c: Canvas, index: Int) {
        val color = zoneInk[index]
        when (index) {
            0 -> for (i in 0..4) {
                val x = 48f + 28f * i
                disc(c, x - 6f, 124f, 4.2f, color)
                disc(c, x, 117f, 4.2f, color)
                disc(c, x + 6f, 124f, 4.2f, color)
                disc(c, x + 1f, 132f, 4.2f, color)
            }
            1 -> for (i in 0..6) {
                val x = 43f + 22f * i
                for (j in 0..3) {
                    val y = 156f + 15f * j
                    oval(c, x - 6f, y - 7f, x + 6f, y + 7f, 0xfff6d2af, color)
                    disc(c, x, y, 2f, color)
                }
            }
            else -> for (i in 0..6) {
                val x = 43f + 21f * i
                line(c, x, 227f, x + 9f, 238f, color, 2.1f)
                line(c, x + 9f, 238f, x, 250f, color, 2.1f)
                if (i < 6) line(c, x + 9f, 238f, x + 21f, 227f, color, 2.1f)
                disc(c, x + 9f, 238f, 3.4f, color)
            }
        }
    }

    private fun drain(c: Canvas, t: Float) {
        label(c, string.health_atlas_cortex_output_art_sinusoid, 180f, 62f, 265f)
        vessel(c, sinusoid, 22f)
        for (i in 0..2) {
            val y = 118f + 60f * i
            rounded(c, 29f, y - 19f, 162f, y + 19f, 6f, zoneFill[i])
            label(c, hormone[i], 95f, y + 4f, 119f)
            line(c, 172f, y, 218f, y, divider, 1.45f)
            outputGlyph(c, i, 175f + 40f * ((t + .15f * i) % 1f), y)
            at(sinusoidTrack, (.51f + .08f * i + .63f * t) % 1f) { x, markY ->
                outputGlyph(c, i, x, markY)
            }
        }
        label(c, string.health_atlas_cortex_output_art_circulation, 235f, 317f, 200f)
    }

    private fun outputGlyph(c: Canvas, index: Int, x: Float, y: Float) {
        val color = zoneInk[index]
        when (index) {
            0 -> disc(c, x, y, 5f, color, cream)
            1 -> rounded(c, x - 4.5f, y - 4.5f, x + 4.5f, y + 4.5f, 1f, color)
            else -> diamond(c, x, y, 6f, color)
        }
    }
}
