package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import com.galaxyssi.chat.R.string

internal class HealthAtlasGonadotrophStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasAnteriorPituitaryArt(context, story) {
    private val fsh = 0xff2d7d78
    private val lh = 0xff8b4876
    private val gnrh = 0xff536f92
    private val follicleEdge = 0xffa2677a
    private val tubuleEdge = 0xff788e90
    private val input = cubic(77f, 156f, 138f, 108f, 157f, 215f, 237f, 181f)
    private val inputTrack = track(input)
    private val trunk = cubic(87f, 178f, 124f, 184f, 159f, 180f, 178f, 175f)
    private val ovarianBranch = cubic(178f, 175f, 214f, 158f, 211f, 103f, 271f, 104f)
    private val testisBranch = cubic(178f, 175f, 214f, 189f, 217f, 241f, 272f, 239f)
    private val trunkTrack = track(trunk)
    private val ovarianTrack = track(ovarianBranch)
    private val testisTrack = track(testisBranch)
    private val ovary = Path().apply {
        moveTo(262f, 107f)
        cubicTo(256f, 87f, 281f, 75f, 304f, 82f)
        cubicTo(322f, 86f, 331f, 103f, 323f, 115f)
        cubicTo(308f, 138f, 271f, 133f, 262f, 107f)
        close()
    }
    private val ovarianFsh = cubic(34f, 115f, 82f, 109f, 104f, 129f, 136f, 156f)
    private val ovarianLh = cubic(331f, 132f, 301f, 126f, 283f, 130f, 260f, 146f)
    private val ovarianFshTrack = track(ovarianFsh)
    private val ovarianLhTrack = track(ovarianLh)
    private val testisFsh = cubic(37f, 103f, 74f, 106f, 99f, 112f, 117f, 136f)
    private val testisLh = cubic(326f, 103f, 280f, 107f, 270f, 138f, 249f, 171f)
    private val testisFshTrack = track(testisFsh)
    private val testisLhTrack = track(testisLh)
    private val sertoliCell = Path().apply {
        moveTo(105f, 137f)
        quadTo(118f, 129f, 133f, 129f)
        cubicTo(130f, 149f, 149f, 161f, 145f, 182f)
        quadTo(143f, 193f, 133f, 187f)
        cubicTo(127f, 180f, 125f, 157f, 105f, 137f)
        close()
    }

    init { tag = "atlas-function-gonadotroph-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> inputPulses(c, t)
            1 -> pairedOutputs(c, t)
            2 -> follicle(c, t)
            else -> tubule(c, t)
        }
    }

    private fun inputPulses(c: Canvas, t: Float) {
        vessel(c, input, 15f)
        for (i in 0..3) {
            line(c, 35f + i * 9f, 114f - i * 5f, 65f + i * 5f, 152f, 0xffa299af, 3f)
            disc(c, 65f + i * 5f, 152f, 5f, 0xff9e8da9, 0xff786b85)
        }
        pituitary(c, 187f, 143f, 1.23f, gnrh)
        for (i in 0..1) {
            val f = (t - .37f * i) / .61f
            trace(c, inputTrack, f - .17f, f, gnrh, 5f)
            marker(c, inputTrack, f, gnrh, 4.5f)
        }
        val arrival = smooth((t - .59f) / .40f)
        if (arrival > 0f) {
            ring(c, 241f, 181f, 8f + arrival * 14f, fade(gnrh, 1f - arrival), 2.4f)
        }
        label(c, string.health_atlas_antgonad_art_terminal, 96f, 76f, 176f)
        label(c, string.health_atlas_antgonad_art_gnrh, 144f, 218f, 218f)
        label(c, string.health_atlas_antgonad_art_cell, 238f, 263f, 173f)
    }

    private fun pairedOutputs(c: Canvas, t: Float) {
        vessel(c, trunk, 18f)
        vessel(c, ovarianBranch, 15f)
        vessel(c, testisBranch, 15f)
        pituitary(c, 18f, 147f, .97f, gnrh)
        shape(c, ovary, 0xffedc1b2, follicleEdge)
        disc(c, 284f, 102f, 10f, 0xfff9dbca, follicleEdge)
        disc(c, 307f, 109f, 7f, 0xfff9dbca, follicleEdge)
        oval(c, 265f, 205f, 320f, 274f, 0xffc5d9d7, tubuleEdge)
        oval(c, 275f, 215f, 310f, 262f, 0xffeaf2e7, tubuleEdge)
        for (i in 0..2) {
            oval(c, 281f, 221f + 12f * i, 303f, 229f + 12f * i, 0xffd2e4dd, tubuleEdge)
        }
        for (i in 0..2) {
            val f = (t - i * .14f) / .66f
            pair(c, trunkTrack, f / .41f)
            pair(c, ovarianTrack, (f - .41f) / .59f)
            pair(c, testisTrack, (f - .41f) / .59f)
        }
        disc(c, 92f, 286f, 4.5f, fsh)
        diamond(c, 181f, 286f, 3.6f, lh)
        label(c, string.health_atlas_antgonad_art_fsh, 119f, 290f, 45f)
        label(c, string.health_atlas_antgonad_art_lh, 205f, 290f, 33f)
        label(c, string.health_atlas_antpit_art_anterior, 65f, 229f, 115f)
        label(c, string.health_atlas_antgonad_art_ovary, 289f, 65f, 115f)
        label(c, string.health_atlas_antgonad_art_testis, 294f, 303f, 110f)
    }

    private fun follicle(c: Canvas, t: Float) {
        vesselApproach(c, ovarianFshTrack, .62f)
        vesselApproach(c, ovarianLhTrack, .70f)
        disc(c, 190f, 181f, 84f, 0xffe5afb7, follicleEdge)
        disc(c, 190f, 181f, 68f, 0xffd38da4, follicleEdge)
        disc(c, 190f, 181f, 49f, 0xfff9e4dd, follicleEdge)
        disc(c, 215f, 210f, 20f, 0xffd99cb2, follicleEdge)
        disc(c, 216f, 210f, 12f, pale, follicleEdge)
        disc(c, 214f, 209f, 4f, 0xffa5688b)
        for (i in 0..19) {
            val f = i / 20f
            disc(c, 190f + 59f * wave(f + .25f), 181f + 59f * wave(f), 3.3f, 0xffaa6b86)
        }
        for (i in 0..2) {
            marker(c, ovarianFshTrack, (t - .09f * i) / .56f, fsh, 4.5f)
            marker(c, ovarianLhTrack, (t - .08f - .09f * i) / .54f, lh, 4.5f, angular = true)
        }
        val inner = smooth((t - .52f) / .43f)
        val outer = smooth((t - .59f) / .35f)
        sweep(c, 190f, 181f, 59f, 201f, 122f * inner, fsh)
        sweep(c, 190f, 181f, 77f, -27f, 121f * outer, lh)
        label(c, string.health_atlas_antgonad_art_fsh_granulosa, 94f, 72f, 164f)
        label(c, string.health_atlas_antgonad_art_lh_theca, 270f, 72f, 150f)
        label(c, string.health_atlas_antgonad_art_follicle, 190f, 308f, 212f)
    }

    private fun tubule(c: Canvas, t: Float) {
        vesselApproach(c, testisFshTrack, .66f)
        vesselApproach(c, testisLhTrack, .82f)
        disc(c, 139f, 197f, 73f, 0xffc2d3cc, tubuleEdge)
        disc(c, 139f, 197f, 40f, 0xffebf1e8, tubuleEdge)
        disc(c, 317f, 168f, 24f, 0xffc2d3cc, tubuleEdge)
        disc(c, 317f, 168f, 13f, 0xffebf1e8, tubuleEdge)
        shape(c, sertoliCell, 0xff93bbb2, fsh)
        disc(c, 124f, 145f, 4.6f, fsh)
        for (i in 0..12) {
            val a = i / 13f
            val x = 139f + 57f * wave(a + .25f)
            val y = 197f + 57f * wave(a)
            if (i != 9 && i != 10) disc(c, x, y, 5.5f, 0xffe9ebdf, tubuleEdge)
        }
        oval(c, 236f, 165f, 257f, 185f, 0xffe6b4b8, follicleEdge)
        oval(c, 252f, 178f, 275f, 199f, 0xffe6b4b8, follicleEdge)
        oval(c, 235f, 196f, 260f, 219f, 0xffe6b4b8, follicleEdge)
        disc(c, 247f, 174f, 3.6f, lh)
        disc(c, 264f, 189f, 3.6f, lh)
        disc(c, 248f, 208f, 3.6f, lh)
        for (i in 0..2) {
            marker(c, testisFshTrack, (t - .11f * i) / .49f, fsh, 4.5f)
            marker(c, testisLhTrack, (t - .10f - .09f * i) / .53f, lh, 4.5f, angular = true)
        }
        val response = smooth((t - .52f) / .43f)
        if (response > 0f) stroke(c, sertoliCell, fade(fsh, 1f - response), 2f + response * 5f)
        for (i in 0..3) {
            val f = (t - .59f - .085f * i) / .38f
            if (f in 0f..1f) {
                disc(c, mix(263f, 297f + 4f * i, f), mix(188f, 230f - i * 11f, f),
                    3.2f, fade(0xffae792e, 1f - .7f * f))
            }
        }
        label(c, string.health_atlas_antgonad_art_fsh_sertoli, 92f, 73f, 156f)
        label(c, string.health_atlas_antgonad_art_lh_leydig, 264f, 73f, 159f)
        label(c, string.health_atlas_antgonad_art_tubule, 121f, 306f, 198f)
        label(c, string.health_atlas_antgonad_art_testosterone, 274f, 269f, 151f)
    }

    private fun vesselApproach(c: Canvas, path: PathMeasure, end: Float) {
        trace(c, path, 0f, end, vesselEdge, 12f)
        trace(c, path, 0f, end, vesselFill, 9f)
    }

    private fun pair(c: Canvas, path: PathMeasure, f: Float) {
        marker(c, path, f + .04f, fsh, 4f)
        marker(c, path, f - .04f, lh, 4.6f, angular = true)
    }

    private fun sweep(c: Canvas, x: Float, y: Float, radius: Float, start: Float, span: Float, color: Long) {
        ink(color, 4.2f)
        c.drawArc(x - radius, y - radius, x + radius, y + radius, start, span, false, paint)
    }
}
