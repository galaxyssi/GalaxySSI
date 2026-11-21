package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import com.galaxyssi.chat.HealthAtlasVestibularGlandAssignment as Lesson
import com.galaxyssi.chat.R.string

internal class HealthAtlasVestibularGlandStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val map = requireNotNull(context.getDrawable(R.drawable.health_atlas_greater_vestibular_gland_ducts))
    private val guide = 0xff758b8d
    private val rim = 0xff6c9a91
    private val lumen = 0xffebf2df
    private val mucus = 0xff387b72
    private val cellShade = shade(-29f, -8f, 0xffd3e9dc, 0xff91b8ad)
    private val lobuleShade = shade(-32f, 32f, 0xffe5eee0, 0xffaccbbf)
    private val panelShade = shade(77f, 280f, 0xfff5eadf, 0xffe3d6d1)
    private val trail = Path()

    private val upper = Path().apply {
        moveTo(91f, 113f); cubicTo(143f, 113f, 154f, 141f, 175f, 170f)
        quadTo(184f, 182f, 212f, 182f)
    }
    private val middle = Path().apply {
        moveTo(106f, 182f); cubicTo(144f, 182f, 174f, 181f, 212f, 182f)
    }
    private val lower = Path().apply {
        moveTo(91f, 251f); cubicTo(143f, 251f, 154f, 223f, 175f, 195f)
        quadTo(184f, 183f, 212f, 182f)
    }
    private val main = Path().apply {
        moveTo(212f, 182f); cubicTo(241f, 182f, 263f, 169f, 305f, 172f)
    }
    private val collectionTracks = listOf(track(upper), track(middle), track(lower))
    private val mainTrack = track(main)
    private val leftOutlet = track(Path().apply {
        moveTo(94f, 223f); cubicTo(113f, 222f, 126f, 208f, 146f, 201f)
        quadTo(147f, 205f, 145f, 211f)
    })
    private val rightOutlet = track(Path().apply {
        moveTo(266f, 223f); cubicTo(247f, 222f, 234f, 208f, 214f, 201f)
        quadTo(213f, 205f, 215f, 211f)
    })
    private val stroma = Path().apply {
        moveTo(59f, 90f)
        cubicTo(84f, 71f, 118f, 77f, 153f, 103f)
        cubicTo(198f, 141f, 227f, 142f, 268f, 146f)
        cubicTo(318f, 149f, 331f, 163f, 324f, 189f)
        cubicTo(319f, 213f, 261f, 208f, 225f, 213f)
        cubicTo(178f, 219f, 157f, 264f, 112f, 280f)
        cubicTo(74f, 294f, 42f, 276f, 50f, 247f)
        cubicTo(57f, 218f, 51f, 200f, 60f, 179f)
        cubicTo(67f, 157f, 37f, 111f, 59f, 90f)
        close()
    }
    private val branches = listOf(upper, middle, lower)

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            Lesson.MAP -> location(c, t, false)
            Lesson.ACINI -> micro(c, t, false)
            Lesson.COLLECTION -> micro(c, t, true)
            Lesson.OUTLET -> location(c, t, true)
        }
    }

    private fun location(c: Canvas, t: Float, flow: Boolean) {
        map.setBounds(0, 28, 360, 308)
        map.draw(c)
        if (flow) {
            outletBead(c, leftOutlet, t)
            outletBead(c, rightOutlet, (t + .22f) % 1f)
        } else {
            val radius = 19f + 2.5f * wave(t)
            ink(0x6560998d, 1.1f)
            c.drawCircle(94f, 223f, radius, paint)
            c.drawCircle(266f, 223f, radius, paint)
        }
        leader(c, 146f, 93f, 180f, 110f)
        leader(c, 250f, 155f, 218f, 198f)
        leader(c, 73f, 263f, 86f, 237f)
        leader(c, 271f, 258f, 244f, 216f)
        label(c, string.health_atlas_vestibular_gland_urethral, 81f, 92f, 129f)
        label(c, string.health_atlas_vestibular_gland_pores, 286f, 147f, 133f)
        label(c, string.health_atlas_vestibular_gland_pair, 76f, 283f, 135f)
        label(c, string.health_atlas_vestibular_gland_duct, 279f, 280f, 130f)
    }

    private fun micro(c: Canvas, t: Float, collecting: Boolean) {
        ink(cream); paint.shader = panelShade; c.drawPath(stroma, paint); paint.shader = null
        stroke(c, stroma, 0xffc9b2ac, 1.3f)
        for (branch in branches) stroke(c, branch, rim, 11f)
        stroke(c, main, rim, 18f)
        for (branch in branches) stroke(c, branch, lumen, 6.5f)
        stroke(c, main, lumen, 12f)
        acinus(c, 91f, 113f, -2f)
        acinus(c, 106f, 182f, 0f)
        acinus(c, 91f, 251f, 2f)
        if (collecting) {
            // Each pass shows one acinus feeding its branch, then the shared lumen.
            val slot = (t * collectionTracks.size).toInt().coerceAtMost(collectionTracks.lastIndex)
            val p = t * collectionTracks.size - slot
            val branch = collectionTracks[slot]
            val distance = p * (branch.length + mainTrack.length)
            if (distance < branch.length) {
                at(branch, distance / branch.length) { x, y -> disc(c, x, y, 2.5f, mucus) }
            } else {
                at(mainTrack, (distance - branch.length) / mainTrack.length) { x, y ->
                    disc(c, x, y, 3f, mucus, lumen)
                }
            }
            leader(c, 166f, 77f, 151f, 144f)
            leader(c, 274f, 246f, 273f, 173f)
            label(c, string.health_atlas_vestibular_gland_branches, 167f, 66f, 158f)
            label(c, string.health_atlas_vestibular_gland_main_duct, 271f, 267f, 143f)
        } else {
            secrete(c, 91f, 113f, t)
            secrete(c, 106f, 182f, (t + .25f) % 1f)
            secrete(c, 91f, 251f, (t + .5f) % 1f)
            leader(c, 107f, 69f, 92f, 93f)
            leader(c, 155f, 314f, 94f, 252f)
            label(c, string.health_atlas_vestibular_gland_cells, 107f, 58f, 165f)
            label(c, string.health_atlas_vestibular_gland_lumen, 166f, 334f, 155f)
        }
    }

    private fun acinus(c: Canvas, x: Float, y: Float, turn: Float) {
        c.save()
        c.translate(x, y)
        c.rotate(turn)
        oval(c, -31f, -31f, 31f, 31f, lobuleShade, rim)
        // Leave a neck where the radial epithelium meets the collecting branch.
        rounded(c, 2f, -3.25f, 33f, 3.25f, 2f, lumen)
        disc(c, 0f, 0f, 11f, lumen)
        for (sector in 0..7) {
            if (sector == 2) continue
            c.save()
            c.rotate(sector * 45f)
            oval(c, -6.3f, -28f, 6.3f, -9f, cellShade, 0xff88ada2)
            disc(c, 0f, -23f, 2.1f, 0xff748b8d)
            c.restore()
        }
        c.restore()
    }

    private fun secrete(c: Canvas, x: Float, y: Float, t: Float) {
        disc(c, x, y - 10f + 10f * t, 1.8f + .7f * t, mucus)
    }

    private fun outletBead(c: Canvas, path: PathMeasure, t: Float) {
        val distance = t * path.length
        trail.rewind()
        if (path.getSegment((distance - 8f).coerceAtLeast(0f), distance, trail, true)) {
            stroke(c, trail, mucus, 1.35f)
        }
        at(path, t) { x, y -> disc(c, x, y, 1.9f, lumen, mucus) }
    }

    private fun leader(c: Canvas, x: Float, y: Float, atX: Float, atY: Float) {
        line(c, x, y, atX, atY, guide, 1f)
        disc(c, atX, atY, 2f, cream, guide)
    }
}
