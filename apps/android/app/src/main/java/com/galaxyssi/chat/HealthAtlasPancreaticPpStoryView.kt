package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import com.galaxyssi.chat.R.string

internal class HealthAtlasPancreaticPpStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasEndocrineCellStoryView(context, story, HealthAtlasEndocrineCellAssignments.PP) {
    private val ppInk = 0xff236b64
    private val ductInk = 0xffa16d46
    private val pancreasFill = shade(108f, 221f, 0xfff4d6a0, 0xffdf9b77)
    private val pancreas = curve {
        moveTo(57f, 152f)
        cubicTo(68f, 113f, 108f, 133f, 143f, 134f)
        cubicTo(208f, 135f, 249f, 122f, 289f, 112f)
        cubicTo(320f, 107f, 332f, 131f, 305f, 148f)
        cubicTo(275f, 160f, 252f, 156f, 225f, 166f)
        cubicTo(193f, 176f, 147f, 173f, 120f, 185f)
        cubicTo(114f, 208f, 96f, 226f, 73f, 218f)
        cubicTo(49f, 209f, 47f, 180f, 57f, 152f)
        close()
    }
    private val uncinate = curve {
        moveTo(73f, 202f)
        quadTo(97f, 205f, 121f, 184f)
        quadTo(139f, 189f, 130f, 202f)
        quadTo(110f, 222f, 73f, 217f)
        close()
    }
    private val stomach = curve {
        moveTo(89f, 108f)
        quadTo(88f, 141f, 112f, 137f)
        cubicTo(151f, 118f, 171f, 165f, 146f, 202f)
        cubicTo(129f, 231f, 95f, 233f, 75f, 211f)
        quadTo(61f, 198f, 44f, 211f)
        lineTo(36f, 194f)
        quadTo(59f, 173f, 85f, 188f)
        quadTo(107f, 203f, 116f, 182f)
        quadTo(123f, 166f, 102f, 167f)
        quadTo(68f, 167f, 67f, 108f)
        close()
    }
    private val bloodRoute = curve {
        moveTo(40f, 222f)
        cubicTo(105f, 235f, 115f, 130f, 183f, 155f)
        cubicTo(247f, 178f, 237f, 224f, 323f, 186f)
    }
    private val bloodTrack = track(bloodRoute)
    private val digestiveVessel = curve {
        moveTo(38f, 139f)
        cubicTo(110f, 104f, 250f, 158f, 322f, 123f)
    }
    private val digestiveTrack = track(digestiveVessel)

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> locate(c, t)
            1 -> meal(c, t)
            2 -> circulation(c, t)
            else -> digestiveContext(c, t)
        }
    }

    private fun locate(c: Canvas, t: Float) {
        ink(cream); paint.shader = pancreasFill; c.drawPath(pancreas, paint); paint.shader = null
        stroke(c, pancreas, ductInk, 1.8f)
        ink(0xffc9dfc7); c.drawPath(uncinate, paint)
        stroke(c, uncinate, ppInk, 1.6f)
        label(c, string.health_atlas_pp_signal_art_pancreas, 181f, 92f, 220f)
        line(c, 110f, 211f, 159f + 45f * t, 255f, ppInk, 1.4f)
        val r = 10f + 5f * wave(t)
        ink(ppInk, 1.9f); c.drawCircle(110f, 208f, r, paint)
        diamond(c, 159f + 45f * t, 255f, 4f, ppInk)
        label(c, string.health_atlas_pp_signal_art_uncinate, 180f, 283f, 240f)
    }

    private fun meal(c: Canvas, t: Float) {
        ink(0xffedbea9); c.drawPath(stomach, paint)
        stroke(c, stomach, ductInk, 1.8f)
        c.save()
        c.clipPath(stomach)
        for (i in 0..4) {
            val y = 103f + 85f * ((t + i * .17f) % 1f)
            disc(c, 80f + (i % 3) * 5f + (y - 103f) * .46f, y, 3.3f, ductInk)
        }
        c.restore()
        oval(c, 216f, 139f, 318f, 211f, 0xffb9d9c8, ppInk)
        disc(c, 267f, 173f, 12f, ppInk, cream)
        for (i in 0..2) {
            val f = (t * 1.2f - .18f * i).coerceIn(0f, 1f)
            val x = 172f + 37f * f
            ink(0xff947639, 2f)
            c.drawArc(x - 13f, 151f, x + 13f, 201f, -61f, 122f, false, paint)
        }
        label(c, string.health_atlas_pp_signal_art_meal, 92f, 265f, 140f)
        label(c, string.health_atlas_pp_signal_art_cell, 267f, 265f, 138f)
    }

    private fun circulation(c: Canvas, t: Float) {
        vessel(c, bloodRoute, 28f)
        oval(c, 28f, 124f, 101f, 181f, 0xffb9d9c8, ppInk)
        disc(c, 63f, 151f, 9f, ppInk, cream)
        for (i in 0..2) {
            val f = (t * 1.2f - i * .16f).coerceIn(0f, 1f)
            diamond(c, 54f + i * 9f + 9f * f, 182f + 32f * f, 3.6f, ppInk)
        }
        for (i in 0..5) {
            val f = (t * .83f + i * .16f) % 1f
            at(bloodTrack, f) { x, y -> diamond(c, x, y, 4.5f, ppInk) }
        }
        label(c, string.health_atlas_pp_signal_art_blood, 180f, 77f, 240f)
        diamond(c, 97f, 282f, 5f, ppInk)
        label(c, string.health_atlas_pp_signal_art_pp, 196f, 287f, 182f)
    }

    private fun digestiveContext(c: Canvas, t: Float) {
        label(c, string.health_atlas_pp_signal_art_pp, 180f, 91f, 270f)
        vessel(c, digestiveVessel, 19f)
        for (i in 0..5) {
            at(digestiveTrack, (t * .69f + .17f * i) % 1f) { x, y -> diamond(c, x, y, 4f, ppInk) }
        }
        label(c, string.health_atlas_pp_signal_art_regulators, 87f, 195f, 131f)
        for (i in 0..2) {
            val f = (t + i * .25f) % 1f
            val x = 47f + 83f * f
            line(c, x, 223f - 7f * i, x + 8f, 223f - 7f * i, violet, 2.2f)
        }
        for (i in 0..4) {
            val x = 176f + 17f * i
            val y = 213f - 13f * wave(i / 8f)
            oval(c, x - 13f, y - 16f, x + 13f, y + 16f, 0xfff0c6a4, ductInk)
            disc(c, x, y - 5f, 4f, ductInk)
        }
        rounded(c, 158f, 225f, 325f, 248f, 8f, 0xfffae2be)
        line(c, 170f, 226f, 325f, 226f, ductInk, 1.2f)
        line(c, 170f, 247f, 325f, 247f, ductInk, 1.2f)
        for (i in 0..3) {
            val f = (t * .64f + .23f * i) % 1f
            disc(c, 184f + 138f * f, 236f, 2.6f, ductInk)
        }
        label(c, string.health_atlas_pp_signal_art_exocrine, 240f, 276f, 194f)
    }
}
