package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import com.galaxyssi.chat.R.string
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasLactotrophStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasAnteriorPituitaryArt(context, story) {
    private val dopamine = 0xff477c8b
    private val prl = 0xff9e4873
    private val glandEdge = 0xffa05b73
    private val lumen = 0xfffff7ea
    private val milk = 0xfff0d392
    private val milkEdge = 0xffab7840
    private val cell = Path().apply {
        moveTo(103f, 191f)
        cubicTo(90f, 165f, 108f, 137f, 135f, 125f)
        cubicTo(174f, 105f, 243f, 127f, 254f, 160f)
        cubicTo(281f, 214f, 194f, 237f, 136f, 218f)
        quadTo(112f, 213f, 103f, 191f)
        close()
    }
    private val topPortal = cubic(32f, 89f, 103f, 68f, 168f, 102f, 326f, 87f)
    private val releaseBlood = cubic(32f, 265f, 103f, 245f, 203f, 276f, 328f, 254f)
    private val releaseTrack = track(releaseBlood)
    private val mammaryBlood = Path().apply {
        moveTo(73f, 149f)
        cubicTo(170f, 95f, 184f, 209f, 113f, 220f)
        cubicTo(67f, 229f, 90f, 274f, 170f, 254f)
        cubicTo(202f, 245f, 233f, 229f, 275f, 220f)
    }
    private val mammaryTrack = track(mammaryBlood)
    private val ducts = Path().apply {
        moveTo(263f, 151f)
        quadTo(297f, 163f, 327f, 128f)
        moveTo(251f, 116f)
        quadTo(266f, 143f, 279f, 152f)
        moveTo(255f, 184f)
        quadTo(268f, 171f, 281f, 153f)
        moveTo(285f, 106f)
        quadTo(284f, 132f, 296f, 148f)
        moveTo(302f, 185f)
        quadTo(297f, 168f, 300f, 145f)
    }
    private val nearAlveolus = cubic(34f, 267f, 119f, 244f, 271f, 282f, 327f, 249f)
    private val nearTrack = track(nearAlveolus)
    private val epitheliumX = FloatArray(16) { cos(it * PI / 8.0).toFloat() }
    private val epitheliumY = FloatArray(16) { sin(it * PI / 8.0).toFloat() }
    private val lumenClip = Path().apply { addCircle(170f, 171f, 47f, Path.Direction.CW) }

    init { tag = "atlas-function-lactotroph-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> disinhibition(c, t)
            1 -> mammaryDelivery(c, t)
            2 -> epithelialFace(c, t)
            else -> luminalSecretion(c, t)
        }
    }

    private fun disinhibition(c: Canvas, t: Float) {
        vessel(c, topPortal, 14f)
        vessel(c, releaseBlood, 18f)
        shape(c, cell, 0xffedbec7, glandEdge, 2.2f)
        oval(c, 118f, 159f, 164f, 196f, 0xffc891aa, 0xff966487)
        for (i in 0..4) {
            val x = 143f + i * 18f
            val relief = smooth((t - .09f - i * .035f) / .43f)
            line(c, x - 4f, 122f, x + 4f, 122f, dopamine, 2.2f)
            diamond(c, x, mix(113f, 90f, relief), 4.3f, fade(dopamine, 1f - relief))
        }
        for (i in 0..3) {
            val p = (t - .41f - i * .085f) / .46f
            val x = 173f + i * 13f
            if (p < .57f) {
                disc(c, x, mix(185f + i * 3f, 258f, smooth(p / .57f)), 4f, prl, pale)
            } else {
                marker(c, releaseTrack, .51f + i * .045f + (p - .57f) * .53f, prl)
            }
        }
        label(c, string.health_atlas_antlacto_art_dopamine, 180f, 60f, 255f)
        label(c, string.health_atlas_antlacto_art_cell, 187f, 156f, 125f)
        label(c, string.health_atlas_antlacto_art_prl_blood, 180f, 309f, 271f)
    }

    private fun mammaryDelivery(c: Canvas, t: Float) {
        vessel(c, mammaryBlood, 15f)
        pituitary(c, 18f, 105f, .88f, prl)
        stroke(c, ducts, glandEdge, 9f)
        stroke(c, ducts, 0xffedbcc4, 6f)
        smallAlveolus(c, 245f, 111f, 18f)
        smallAlveolus(c, 286f, 98f, 17f)
        smallAlveolus(c, 254f, 181f, 21f)
        smallAlveolus(c, 305f, 190f, 17f)
        smallAlveolus(c, 258f, 144f, 15f)
        for (i in 0..5) marker(c, mammaryTrack, t * 1.6f - i * .16f, prl)
        val arrival = smooth((t - .57f) / .3f)
        if (arrival > 0f) ring(c, 254f, 181f, 22f + arrival * 7f, fade(prl, 1f - arrival), 2.8f)
        label(c, string.health_atlas_antpit_art_anterior, 54f, 181f, 100f)
        label(c, string.health_atlas_antlacto_art_alveoli, 269f, 65f, 150f)
        label(c, string.health_atlas_antlacto_art_prl_blood, 173f, 298f, 260f)
    }

    private fun epithelialFace(c: Canvas, t: Float) {
        vessel(c, nearAlveolus, 17f)
        alveolus(c)
        for (i in 0..3) {
            val f = (t - i * .105f) / .56f
            marker(c, nearTrack, (f + .23f * i) * .59f, prl)
            val approach = (t - .33f - .09f * i) / .32f
            if (approach in 0f..1f) {
                val x = 127f + i * 27f
                val y = 242f - 8f * (if (i == 0 || i == 3) 1f else 0f)
                disc(c, x, mix(262f, y, smooth(approach)), 4.2f, prl)
            }
            val bound = smooth((approach - .68f) * 2.5f)
            if (bound > 0f) {
                val x = 127f + i * 27f
                val y = if (i == 0 || i == 3) 234f else 242f
                ring(c, x, y, 5.8f + 3f * bound, fade(prl, .85f * bound), 2f)
            }
        }
        label(c, string.health_atlas_antlacto_art_wall, 166f, 67f, 252f)
        label(c, string.health_atlas_antlacto_art_lumen, 169f, 175f, 82f)
        label(c, string.health_atlas_antlacto_art_prl_blood, 177f, 307f, 260f)
    }

    private fun luminalSecretion(c: Canvas, t: Float) {
        alveolus(c)
        c.save()
        c.clipPath(lumenClip)
        val pool = smooth((t - .30f) / .59f)
        if (pool > 0f) {
            val surface = mix(218f, 192f, pool)
            rounded(c, 120f, surface, 220f, 226f, 8f, milk)
            line(c, 128f, surface + 1f, 213f, surface + 1f, milkEdge, 1.35f)
        }
        for (i in 0..5) {
            val f = (t - .11f - .093f * i) / .38f
            if (f in 0f..1f) {
                val k = (i * 2 + 9) % 16
                val radius = mix(50f, 13f, smooth(f))
                disc(c, 170f + epitheliumX[k] * radius, 171f + epitheliumY[k] * radius,
                    3f + 2.5f * f, milk, milkEdge)
            }
        }
        c.restore()
        label(c, string.health_atlas_antlacto_art_wall, 166f, 67f, 250f)
        label(c, string.health_atlas_antlacto_art_milk_lumen, 178f, 280f, 275f)
        line(c, 170f, 262f, 170f, 215f, milkEdge, 1.4f)
    }

    private fun smallAlveolus(c: Canvas, x: Float, y: Float, r: Float) {
        disc(c, x, y, r, 0xffedb9c1, glandEdge)
        disc(c, x, y, r * .56f, lumen, glandEdge)
    }

    private fun alveolus(c: Canvas) {
        line(c, 225f, 145f, 300f, 110f, glandEdge, 23f)
        line(c, 225f, 145f, 300f, 110f, 0xffe9aebd, 20f)
        disc(c, 170f, 171f, 71f, 0xffecbdc5, glandEdge)
        for (i in epitheliumX.indices) {
            val dx = epitheliumX[i]
            val dy = epitheliumY[i]
            line(c, 170f + dx * 49f, 171f + dy * 49f, 170f + dx * 69f, 171f + dy * 69f, glandEdge, 1.25f)
            val next = (i + 1) % epitheliumX.size
            disc(c, 170f + 31f * (dx + epitheliumX[next]), 171f + 31f * (dy + epitheliumY[next]),
                3f, glandEdge)
        }
        disc(c, 170f, 171f, 47f, lumen, glandEdge)
        line(c, 204f, 155f, 300f, 110f, lumen, 9f)
    }
}
