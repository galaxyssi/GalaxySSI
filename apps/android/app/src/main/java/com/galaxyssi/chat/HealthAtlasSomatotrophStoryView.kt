package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import com.galaxyssi.chat.R.string

internal class HealthAtlasSomatotrophStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasAnteriorPituitaryArt(context, story) {
    private val gh = 0xff307a71
    private val igf = 0xff765291
    private val cell = Path().apply {
        moveTo(74f, 169f)
        cubicTo(64f, 132f, 97f, 102f, 151f, 99f)
        cubicTo(211f, 92f, 277f, 107f, 280f, 161f)
        cubicTo(286f, 199f, 228f, 222f, 173f, 219f)
        cubicTo(132f, 221f, 86f, 206f, 74f, 169f)
        close()
    }
    private val cellShade = shade(95f, 222f, 0xffffeddb, 0xffe6b0a6)
    private val capillary = cubic(34f, 247f, 115f, 223f, 250f, 268f, 326f, 242f)
    private val capillaryTrack = track(capillary)
    private val trunk = cubic(89f, 182f, 103f, 180f, 121f, 178f, 143f, 182f)
    private val upperBranch = cubic(143f, 182f, 179f, 182f, 173f, 111f, 246f, 111f)
    private val lowerBranch = cubic(143f, 182f, 175f, 183f, 178f, 248f, 240f, 248f)
    private val upperTrack = track(upperBranch)
    private val lowerTrack = track(lowerBranch)
    private val trunkTrack = track(trunk)
    private val liverShape = Path().apply {
        moveTo(8f, 42f)
        cubicTo(11f, 18f, 40f, 7f, 74f, 14f)
        cubicTo(100f, 16f, 117f, 26f, 141f, 25f)
        cubicTo(138f, 46f, 114f, 62f, 94f, 67f)
        cubicTo(76f, 71f, 65f, 95f, 34f, 99f)
        cubicTo(13f, 99f, 5f, 71f, 8f, 42f)
        close()
    }
    private val liverDivision = cubic(76f, 16f, 66f, 40f, 81f, 56f, 93f, 67f)
    private val liverShade = shade(10f, 94f, 0xffe5a18a, 0xffbc7266)
    private val fiber = Path().apply {
        moveTo(2f, 10f)
        cubicTo(14f, 1f, 90f, 0f, 122f, 6f)
        quadTo(132f, 10f, 124f, 18f)
        cubicTo(101f, 26f, 25f, 25f, 7f, 21f)
        quadTo(1f, 19f, 2f, 10f)
        close()
    }
    private val input = cubic(39f, 84f, 95f, 83f, 130f, 103f, 140f, 148f)
    private val hepaticOut = cubic(153f, 187f, 200f, 195f, 216f, 263f, 316f, 259f)
    private val inputTrack = track(input)
    private val hepaticTrack = track(hepaticOut)
    private val muscleGh = cubic(47f, 98f, 82f, 99f, 96f, 146f, 129f, 168f)
    private val muscleIgf = cubic(312f, 98f, 283f, 99f, 270f, 146f, 237f, 168f)
    private val muscleGhTrack = track(muscleGh)
    private val muscleIgfTrack = track(muscleIgf)

    init { tag = "atlas-function-somatotroph-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> release(c, t)
            1 -> branch(c, t)
            2 -> relay(c, t)
            else -> tissueResponse(c, t)
        }
    }

    private fun release(c: Canvas, t: Float) {
        vessel(c, capillary, 21f)
        ink(pale); paint.shader = cellShade; c.drawPath(cell, paint); paint.shader = null
        stroke(c, cell, 0xffa36570, 2f)
        oval(c, 96f, 130f, 158f, 176f, 0xffc58fa9, 0xff916983)
        disc(c, 123f, 154f, 5f, 0xff9a6687)
        for (i in 0..6) {
            val f = (t - .065f * i) / .56f
            val x = 149f + 15f * i
            val y = 180f + 10f * wave(i * .15f)
            if (f < .69f) {
                val approach = smooth(f / .69f)
                disc(c, mix(x, 172f + 4f * i, approach), mix(y, 216f, approach), 5f, pale, gh)
            } else if (f < 1f) {
                disc(c, 172f + 4f * i, mix(216f, 243f, (f - .69f) / .31f), 3.4f, gh)
            }
            val released = t - .56f - .065f * i
            if (released >= 0f) marker(c, capillaryTrack, .47f + .014f * i + released * 1.35f, gh)
        }
        label(c, string.health_atlas_antsoma_art_cell, 180f, 68f, 260f)
        label(c, string.health_atlas_antsoma_art_gh_blood, 180f, 293f, 270f)
    }

    private fun branch(c: Canvas, t: Float) {
        vessel(c, trunk, 13f)
        vessel(c, upperBranch, 10f)
        vessel(c, lowerBranch, 10f)
        pituitary(c, 20f, 145f, 1.06f, gh)
        liver(c, 238f, 69f, .68f)
        fibers(c, 234f, 222f, .77f)
        for (i in 0..3) {
            val f = (t - i * .11f) * 2.1f
            marker(c, trunkTrack, f * 3f, gh)
            marker(c, upperTrack, (f - .33f) * 1.32f, gh)
            marker(c, lowerTrack, (f - .33f) * 1.18f, gh)
        }
        label(c, string.health_atlas_antpit_art_anterior, 61f, 234f, 104f)
        label(c, string.health_atlas_antsoma_art_gh_blood, 135f, 146f, 145f)
        label(c, string.health_atlas_antsoma_art_liver, 288f, 60f, 120f)
        label(c, string.health_atlas_antsoma_art_muscle, 284f, 305f, 135f)
    }

    private fun relay(c: Canvas, t: Float) {
        vessel(c, hepaticOut, 16f)
        liver(c, 50f, 106f, 1.26f)
        stroke(c, input, vesselEdge, 9f)
        stroke(c, input, vesselFill, 6f)
        for (i in 0..2) {
            val delay = .09f * i
            marker(c, inputTrack, (t - delay) / .41f, gh)
            val response = (t - .26f - delay) / .29f
            if (response in 0f..1f) {
                ring(c, 141f + i * 12f, 158f + i * 9f, 6f + response * 12f, fade(igf, 1f - response), 2.4f)
            }
            marker(c, hepaticTrack, (t - .46f - delay) / .39f, igf, 4.6f, angular = true)
        }
        label(c, string.health_atlas_antsoma_art_gh, 64f, 59f, 85f)
        label(c, string.health_atlas_antsoma_art_liver, 204f, 116f, 100f)
        label(c, string.health_atlas_antsoma_art_igf_blood, 244f, 297f, 196f)
    }

    private fun tissueResponse(c: Canvas, t: Float) {
        vessel(c, muscleGh, 12f)
        vessel(c, muscleIgf, 12f)
        fibers(c, 87f, 159f, 1.43f)
        for (i in 0..2) {
            marker(c, muscleGhTrack, (t - .13f * i) / .53f, gh)
            marker(c, muscleIgfTrack, (t - .07f - .13f * i) / .53f, igf, 4.5f, angular = true)
        }
        for (i in 0..5) {
            val f = smooth((t - .34f - .06f * i) / .31f)
            val x = 125f + 22f * i
            val y = 186f + 31f * (i % 3)
            if (f > 0f) line(c, x, y, x + 27f * f, y, 0xff8a464e, 3.6f)
        }
        label(c, string.health_atlas_antsoma_art_gh, 70f, 71f, 91f)
        label(c, string.health_atlas_antsoma_art_igf, 288f, 71f, 108f)
        label(c, string.health_atlas_antsoma_art_muscle, 180f, 291f, 220f)
    }

    private fun liver(c: Canvas, x: Float, y: Float, scale: Float) {
        c.save(); c.translate(x, y); c.scale(scale, scale)
        ink(pale); paint.shader = liverShade; c.drawPath(liverShape, paint); paint.shader = null
        stroke(c, liverShape, 0xff854d4d, 1.9f)
        stroke(c, liverDivision, 0xffa75f59, 1.7f)
        c.restore()
    }

    private fun fibers(c: Canvas, x: Float, y: Float, scale: Float) {
        c.save(); c.translate(x, y); c.scale(scale, scale)
        for (row in 0..2) {
            c.save(); c.translate(0f, 22f * row)
            shape(c, fiber, if (row == 1) 0xffd79b9a else 0xffe5aaa0, 0xffa35d65)
            for (i in 0..7) {
                val xx = 21f + 12f * i
                line(c, xx, 7f, xx - 2f, 19f, 0xffbc7880, 1.3f)
            }
            c.restore()
        }
        c.restore()
    }
}
