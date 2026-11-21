package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import com.galaxyssi.chat.R.string

internal class HealthAtlasCorticotrophStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasAnteriorPituitaryArt(context, story) {
    private val crh = 0xff52768c
    private val acth = 0xff75508b
    private val cortisol = 0xffa5612c
    private val adrenalEdge = 0xffa16148
    private val hypothalamus = Path().apply {
        moveTo(65f, 93f)
        cubicTo(87f, 58f, 144f, 58f, 169f, 86f)
        cubicTo(183f, 103f, 162f, 116f, 148f, 116f)
        quadTo(124f, 143f, 109f, 113f)
        cubicTo(85f, 119f, 64f, 113f, 65f, 93f)
        close()
    }
    private val portal = cubic(132f, 118f, 119f, 156f, 206f, 148f, 211f, 217f)
    private val portalTrack = track(portal)
    private val systemic = Path().apply {
        moveTo(78f, 137f)
        cubicTo(139f, 150f, 98f, 242f, 182f, 239f)
        cubicTo(239f, 237f, 220f, 136f, 264f, 127f)
    }
    private val systemicTrack = track(systemic)
    private val kidney = Path().apply {
        moveTo(290f, 136f)
        cubicTo(320f, 140f, 334f, 168f, 323f, 196f)
        cubicTo(317f, 212f, 324f, 224f, 312f, 238f)
        cubicTo(285f, 269f, 249f, 235f, 255f, 204f)
        cubicTo(258f, 186f, 276f, 183f, 273f, 166f)
        quadTo(272f, 135f, 290f, 136f)
        close()
    }
    private val adrenal = Path().apply {
        moveTo(258f, 133f)
        quadTo(272f, 115f, 279f, 96f)
        quadTo(284f, 82f, 292f, 98f)
        cubicTo(307f, 120f, 308f, 130f, 320f, 143f)
        quadTo(287f, 132f, 263f, 141f)
        quadTo(253f, 143f, 258f, 133f)
        close()
    }
    private val cortexSection = Path().apply {
        moveTo(41f, 231f)
        cubicTo(80f, 214f, 107f, 102f, 165f, 93f)
        cubicTo(220f, 84f, 255f, 175f, 314f, 215f)
        quadTo(327f, 226f, 309f, 242f)
        cubicTo(264f, 270f, 214f, 246f, 170f, 249f)
        cubicTo(126f, 249f, 80f, 286f, 41f, 251f)
        quadTo(32f, 243f, 41f, 231f)
        close()
    }
    private val fasciculata = Path().apply {
        moveTo(48f, 239f)
        cubicTo(86f, 225f, 117f, 116f, 167f, 108f)
        cubicTo(216f, 101f, 251f, 185f, 310f, 225f)
        quadTo(304f, 244f, 271f, 245f)
        cubicTo(215f, 244f, 172f, 232f, 131f, 247f)
        quadTo(73f, 267f, 48f, 246f)
        close()
    }
    private val reticularis = Path().apply {
        moveTo(84f, 242f)
        cubicTo(110f, 224f, 135f, 153f, 168f, 146f)
        cubicTo(204f, 138f, 244f, 205f, 276f, 235f)
        quadTo(230f, 237f, 192f, 232f)
        cubicTo(146f, 226f, 109f, 252f, 84f, 242f)
        close()
    }
    private val medulla = Path().apply {
        moveTo(114f, 234f)
        cubicTo(132f, 225f, 148f, 175f, 174f, 170f)
        cubicTo(202f, 165f, 225f, 208f, 248f, 226f)
        quadTo(207f, 225f, 182f, 220f)
        quadTo(149f, 222f, 114f, 234f)
        close()
    }
    private val cortexArc = cubic(73f, 231f, 140f, 83f, 164f, 79f, 223f, 156f).apply {
        quadTo(253f, 198f, 289f, 224f)
    }
    private val cortexArcTrack = track(cortexArc)
    private val cortisolBlood = cubic(238f, 88f, 203f, 155f, 277f, 204f, 313f, 264f)
    private val cortisolTrack = track(cortisolBlood)
    private val cortisolEntries = Array(5) { i ->
        FloatArray(2).also { cortisolTrack.getPosTan(cortisolTrack.length * entry(i), it, null) }
    }

    init { tag = "atlas-function-corticotroph-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> portalInput(c, t)
            1 -> adrenalDelivery(c, t)
            2 -> corticalLayers(c, t)
            else -> cortisolOutput(c, t)
        }
    }

    private fun portalInput(c: Canvas, t: Float) {
        vessel(c, portal, 16f)
        shape(c, hypothalamus, 0xffc8c6d4, 0xff857b95, 2f)
        pituitary(c, 151f, 177f, 1.37f, acth)
        for (i in 0..4) marker(c, portalTrack, (t - i * .095f) / .56f, crh, 3.2f)
        val response = smooth((t - .53f) / .41f)
        if (response > 0f) ring(c, 211f, 219f, 9f + 15f * response, fade(acth, 1f - response), 2.8f)
        label(c, string.health_atlas_antcort_art_hypothalamus, 114f, 53f, 191f)
        label(c, string.health_atlas_antcort_art_crh_portal, 236f, 130f, 194f)
        label(c, string.health_atlas_antcort_art_cell, 194f, 296f, 219f)
    }

    private fun adrenalDelivery(c: Canvas, t: Float) {
        vessel(c, systemic, 13f)
        pituitary(c, 18f, 98f, .96f, acth)
        shape(c, kidney, 0xffd99b9b, 0xff965c6c, 2f)
        shape(c, adrenal, 0xffeed19c, adrenalEdge, 2.2f)
        for (i in 0..4) {
            val f = (t - i * .082f) / .65f
            marker(c, systemicTrack, f, acth, 4.1f, angular = true)
        }
        val arrived = (t - .64f) / .31f
        if (arrived in 0f..1f) stroke(c, adrenal, fade(acth, 1f - arrived), 2.3f + arrived * 3f)
        label(c, string.health_atlas_antpit_art_anterior, 67f, 185f, 119f)
        label(c, string.health_atlas_antcort_art_adrenal, 277f, 68f, 140f)
        label(c, string.health_atlas_antcort_art_acth_blood, 157f, 285f, 190f)
        label(c, string.health_atlas_antcort_art_kidney, 283f, 279f, 73f)
    }

    private fun corticalLayers(c: Canvas, t: Float) {
        shape(c, cortexSection, 0xffe5b477, adrenalEdge, 2.2f)
        shape(c, fasciculata, 0xfff5d9a5, 0xffc18a55)
        shape(c, reticularis, 0xffdca38d, 0xffa66b62)
        shape(c, medulla, 0xffbc8e9f, 0xff875875)
        val f = smooth((t - .07f) / .84f)
        c.save()
        c.clipPath(fasciculata)
        trace(c, cortexArcTrack, f - .32f, f, fade(cortisol, .34f), 15f)
        c.restore()
        line(c, 227f, 69f, 201f, 127f, adrenalEdge, 1.4f)
        line(c, 183f, 265f, 183f, 207f, 0xff875875, 1.4f)
        label(c, string.health_atlas_antcort_art_cortex, 92f, 56f, 137f)
        label(c, string.health_atlas_antcort_art_fasciculata, 258f, 56f, 175f)
        label(c, string.health_atlas_antcort_art_medulla, 183f, 287f, 125f)
    }

    private fun cortisolOutput(c: Canvas, t: Float) {
        vessel(c, cortisolBlood, 21f)
        for (row in 0..3) {
            for (col in 0..6) {
                val x = 64f + col * 21f
                val y = 116f + row * 28f + col % 2 * 8f
                oval(c, x - 10f, y - 13f, x + 10f, y + 14f, 0xfff4d5a5, 0xffc99669)
                disc(c, x, y, 3.6f, 0xffbb8874)
            }
        }
        for (i in 0..4) {
            val p = (t - .07f - .115f * i) / .36f
            if (p in 0f..1f) {
                val target = cortisolEntries[i]
                val y = target[1] - 5f
                val f = smooth(p)
                val origin = if (i % 2 == 0) 187f else 191f
                disc(c, mix(origin, target[0], f), y + 5f * f, 3.5f, cortisol)
                if (p < .55f) ring(c, origin, y, 5f + p * 11f, fade(cortisol, 1f - p / .55f), 1.5f)
            }
            val exit = t - .43f - .115f * i
            if (exit >= 0f) marker(c, cortisolTrack, entry(i) + exit * 1.25f, cortisol, 3.7f)
        }
        label(c, string.health_atlas_antcort_art_fasciculata, 122f, 71f, 196f)
        label(c, string.health_atlas_antcort_art_cortisol_blood, 231f, 303f, 232f)
    }

    private fun entry(i: Int) = .19f + .077f * i
}
