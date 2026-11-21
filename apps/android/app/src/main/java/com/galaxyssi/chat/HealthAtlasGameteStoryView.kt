package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.sin

internal object HealthAtlasGameteMotion {
    const val FOLLICLE_OPENS = .30f
    fun release(t: Float) = ((HealthAtlasFunctionStory.safePhase(t) - FOLLICLE_OPENS) / .70f).coerceIn(0f, 1f)
    fun pickup(t: Float): Float {
        val v = HealthAtlasFunctionStory.safePhase(t)
        return v * v * (3f - 2f * v)
    }
    fun ductRadius(x: Float, t: Float): Float {
        val center = 16f + 328f * HealthAtlasFunctionStory.safePhase(t)
        val distance = (x - center) / 26f
        return 28f - 17f * exp(-distance * distance)
    }
}

internal class HealthAtlasGameteStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val spermStory = story == HealthAtlasFunctionStory.SPERM_TRANSPORT
    private val organShade = shade(80f, 306f, 0xfff8d8c8, 0xffd9969b)
    private val follicleShade = shade(88f, 265f, 0xffffedcd, 0xffe5b77d)
    private val cellShade = shade(130f, 200f, 0xfffff4d1, 0xffecc08d)
    private val brushShade = shade(76f, 270f, 0xfff4d4c3, 0xffc98393)
    private val figure = Path()
    private val rete = Path().apply {
        moveTo(94f, 220f)
        cubicTo(132f, 223f, 169f, 214f, 176f, 186f)
        cubicTo(185f, 156f, 172f, 119f, 193f, 111f)
        cubicTo(211f, 104f, 222f, 109f, 243f, 104f)
    }
    private val epididymis = Path().apply {
        moveTo(243f, 104f)
        cubicTo(291f, 94f, 311f, 113f, 286f, 126f)
        cubicTo(254f, 141f, 211f, 122f, 226f, 146f)
        cubicTo(244f, 169f, 306f, 134f, 303f, 167f)
        cubicTo(300f, 194f, 231f, 158f, 236f, 190f)
        cubicTo(242f, 216f, 311f, 183f, 306f, 217f)
        cubicTo(301f, 245f, 251f, 207f, 253f, 238f)
        cubicTo(255f, 260f, 327f, 225f, 305f, 270f)
        cubicTo(288f, 294f, 266f, 289f, 249f, 277f)
    }
    private val vas = Path().apply {
        moveTo(249f, 277f)
        cubicTo(224f, 258f, 211f, 239f, 217f, 212f)
        cubicTo(225f, 165f, 200f, 128f, 217f, 88f)
        cubicTo(226f, 69f, 248f, 62f, 261f, 52f)
    }
    private val reteTrack by lazy { track(rete) }
    private val epiTrack by lazy { track(epididymis) }
    private val fimbriaFlowers = Array(5) { Path() }
    private val pickupPath = Path().apply {
        moveTo(147f, 202f)
        cubicTo(165f, 188f, 175f, 177f, 203f, 156f)
        cubicTo(232f, 134f, 253f, 137f, 275f, 135f)
    }
    private val pickupTrack by lazy { track(pickupPath) }
    private val ampulla = Path().apply {
        moveTo(65f, 173f)
        cubicTo(86f, 130f, 103f, 104f, 137f, 113f)
        cubicTo(184f, 126f, 211f, 173f, 263f, 175f)
        quadTo(294f, 176f, 308f, 173f)
    }
    private val ampullaTrack by lazy { track(ampulla) }

    init {
        tag = if (spermStory) "atlas-function-sperm-transport-art" else "atlas-function-ovum-transport-art"
    }

    override fun scene(c: Canvas, step: Int, t: Float) {
        if (spermStory) {
            when (step) {
                0 -> formation(c, t)
                1, 2, 3 -> ductMap(c, step, t)
                else -> propel(c, t)
            }
        } else {
            when (step) {
                0, 1 -> ovary(c, step == 1, t)
                2 -> pickup(c, t)
                3 -> cilia(c, t)
                else -> destination(c, t)
            }
        }
    }

    private fun formation(c: Canvas, t: Float) {
        oval(c, 43f, 44f, 318f, 319f, organShade, coral)
        oval(c, 105f, 106f, 257f, 258f, 0xfffff4e6, coral)
        for (i in 0 until 10) {
            c.save()
            c.rotate(i * 36f, 180f, 181f)
            oval(c, 163f, 53f, 197f, 90f, sand, sienna)
            disc(c, 179f, 72f, 6f, violet)
            oval(c, 167f, 88f, 193f, 108f, peach, coral)
            disc(c, 180f, 98f, 4f, violet)
            if (i % 2 == 0) sperm(c, 180f, 124f + 35f * t, 90f, .82f, t + i * .22f)
            c.restore()
        }
        figure.rewind()
        figure.moveTo(265f, 238f)
        figure.cubicTo(247f, 207f, 251f, 188f, 264f, 165f)
        figure.cubicTo(273f, 149f, 276f, 153f, 275f, 192f)
        figure.quadTo(278f, 218f, 284f, 232f)
        figure.quadTo(279f, 249f, 265f, 238f)
        ink(0xff7eae9f); c.drawPath(figure, paint)
        disc(c, 275f, 229f, 5f, teal)
        label(c, R.string.health_atlas_sperm_flow_lumen, 181f, 187f, 108f)
        line(c, 272f, 285f, 274f, 243f, teal, 1.3f)
        label(c, R.string.health_atlas_sperm_flow_sertoli, 273f, 303f, 120f)
    }

    private fun ductMap(c: Canvas, step: Int, t: Float) {
        oval(c, 43f, 81f, 212f, 300f, organShade, coral)
        for (i in 0..4) {
            figure.rewind()
            figure.moveTo(67f + i * 9f, 226f)
            figure.cubicTo(37f + i * 24f, 179f, 155f + i * 8f, 189f, 91f + i * 12f, 129f)
            figure.cubicTo(73f + i * 17f, 104f, 110f + i * 13f, 98f, 176f, 135f + i * 10f)
            stroke(c, figure, 0xffbb8185, 3f)
        }
        stroke(c, vas, coral, 12f); stroke(c, vas, peach, 8f)
        stroke(c, rete, coral, 11f); stroke(c, rete, cream, 5f)
        stroke(c, epididymis, sienna, 13f); stroke(c, epididymis, sand, 8f)
        for (i in 0..3) {
            figure.rewind()
            figure.moveTo(194f + i * 3f, 114f + i * 3f)
            figure.quadTo(214f + i * 2f, 90f + 10f * i, 243f, 104f)
            stroke(c, figure, sienna, 1.4f)
        }
        when (step) {
            1 -> flow(c, reteTrack, t, teal, 4)
            2 -> flow(c, epiTrack, t, teal, 4)
            else -> {
                for (i in 0..3) at(epiTrack, .86f + .036f * i + .009f * wave(t + i * .2f)) { x, y ->
                    disc(c, x, y, 3.4f, teal, cream)
                }
                ink(teal, 1.75f); c.drawOval(240f, 242f, 320f, 300f, paint)
            }
        }
        if (step == 1) {
            line(c, 82f, 115f, 172f, 163f, coral, 1.3f)
            label(c, R.string.health_atlas_sperm_flow_rete, 72f, 109f, 117f)
            line(c, 170f, 59f, 216f, 103f, sienna, 1.3f)
            label(c, R.string.health_atlas_sperm_flow_efferent, 145f, 51f, 122f)
        }
        if (step >= 2) {
            line(c, 284f, 65f, 275f, 103f, sienna, 1.3f)
            label(c, R.string.health_atlas_sperm_flow_head, 277f, 59f, 150f)
        }
        if (step == 3) {
            line(c, 275f, 318f, 275f, 299f, teal, 1.3f)
            label(c, R.string.health_atlas_sperm_flow_tail, 272f, 335f, 140f)
        }
        if (step == 2) {
            rounded(c, 40f, 293f, 320f, 343f, 14f, 0xffe2eeea)
            sperm(c, 82f + 212f * t, 318f + 4f * wave(3f * t), 0f, 1.2f, 3f * t)
        }
    }

    private fun propel(c: Canvas, t: Float) {
        figure.rewind()
        figure.moveTo(24f, 155f)
        for (x in 24..336 step 4) figure.lineTo(x.toFloat(), 184f - HealthAtlasGameteMotion.ductRadius(x.toFloat(), t))
        for (x in 336 downTo 24 step 4) figure.lineTo(x.toFloat(), 184f + HealthAtlasGameteMotion.ductRadius(x.toFloat(), t))
        figure.close()
        ink(coral, 18f); c.drawPath(figure, paint)
        ink(peach, 12f); c.drawPath(figure, paint)
        ink(0xfffce4c4); c.drawPath(figure, paint)
        for (i in 0..3) {
            val x = 77f + i * 30f + 135f * t
            sperm(c, x, 181f + if (i % 2 == 0) -6f else 6f, 0f, .63f, t + i * .2f)
        }
        val squeeze = (16f + 328f * t).coerceIn(31f, 328f)
        arrow(c, squeeze, 112f, squeeze, 147f, coral)
        arrow(c, squeeze, 255f, squeeze, 220f, coral)
        arrow(c, 115f, 284f, 170f + 98f * t, 284f, teal)
        label(c, R.string.health_atlas_sperm_flow_vas, 180f, 69f, 206f)
        label(c, R.string.health_atlas_sperm_flow_wall, 180f, 318f, 216f)
    }

    private fun ovary(c: Canvas, releasing: Boolean, t: Float) {
        val outside = if (releasing) HealthAtlasGameteMotion.release(t) else 0f
        val open = releasing && t >= HealthAtlasGameteMotion.FOLLICLE_OPENS
        figure.rewind()
        figure.moveTo(34f, 174f)
        figure.cubicTo(65f, 97f, 144f, 69f, 226f, 103f)
        figure.quadTo(253f, 115f, 264f, 146f)
        if (open) {
            figure.cubicTo(229f, 138f, 219f, 195f, 260f, 195f)
        }
        figure.cubicTo(284f, 248f, 201f, 290f, 119f, 275f)
        figure.cubicTo(52f, 263f, 16f, 228f, 34f, 174f)
        figure.close()
        ink(peach); paint.shader = organShade; c.drawPath(figure, paint); paint.shader = null
        stroke(c, figure, coral, 1.7f)
        for (i in 0..3) {
            val x = 66f + i * 23f
            val y = 196f + 28f * wave(i * .093f)
            val r = 8f + 2f * i
            oval(c, x - r, y - r, x + r, y + r, sand, sienna)
            disc(c, x, y, 3f + i * .6f, 0xfffdf0d6, violet)
        }
        val radius = if (releasing) 48f else 29f + 19f * t
        val x = 209f
        val y = 151f
        if (!open) {
            oval(c, x - radius, y - radius, x + radius, y + radius, follicleShade, coral)
            ink(sienna, 1.1f); c.drawCircle(x, y, radius - 5f, paint)
        } else {
            ink(sienna, 2.2f); c.drawArc(x - radius, y - radius, x + radius, y + radius, 52f, 269f, false, paint)
        }
        val cx = 220f + outside * 95f
        val cy = 159f - outside * 17f
        oocyte(c, cx, cy, 13.5f)
        if (releasing) {
            label(c, R.string.health_atlas_ovum_flow_oocyte, 285f, 80f, 134f)
            line(c, 284f, 91f, cx + 3f, cy - 24f, violet, 1.2f)
        } else {
            label(c, R.string.health_atlas_ovum_flow_cumulus, 241f, 58f, 139f)
            line(c, 240f, 67f, cx + 14f, cy - 15f, violet, 1.2f)
        }
        label(c, R.string.health_atlas_ovum_flow_follicle, 121f, 82f, 125f)
        line(c, 142f, 86f, x - radius * .61f, y - radius * .78f, sienna, 1.2f)
        label(c, R.string.health_atlas_ovum_flow_ovary, 130f, 318f, 135f)
        line(c, 130f, 304f, 130f, 276f, coral, 1.2f)
    }

    private fun pickup(c: Canvas, t: Float) {
        oval(c, 28f, 189f, 137f, 283f, organShade, coral)
        oval(c, 94f, 202f, 131f, 244f, sand, sienna)
        figure.rewind()
        figure.moveTo(196f, 146f); figure.cubicTo(222f, 112f, 278f, 97f, 330f, 113f)
        figure.lineTo(330f, 155f); figure.cubicTo(280f, 161f, 229f, 161f, 202f, 197f)
        figure.close()
        ink(peach); paint.shader = brushShade; c.drawPath(figure, paint); paint.shader = null
        stroke(c, figure, coral, 1.5f)
        for (i in fimbriaFlowers.indices) {
            val x0 = 200f + 6f * i
            val y0 = 146f + 8f * i
            val tipX = 157f + 9f * i + 4f * wave(2f * t + i * .14f)
            val tipY = 152f + 12f * i + 3f * wave(2f * t + i * .19f)
            val strip = fimbriaFlowers[i]
            strip.rewind()
            strip.moveTo(x0, y0)
            strip.quadTo(x0 - 17f, y0 - 3f, tipX, tipY)
            strip.quadTo(tipX + 19f, tipY + 5f, x0 + 8f, y0 + 1f)
            strip.close()
            ink(peach); c.drawPath(strip, paint)
            stroke(c, strip, coral, 1.2f)
        }
        at(pickupTrack, HealthAtlasGameteMotion.pickup(t)) { x, y -> oocyte(c, x, y, 10.5f) }
        label(c, R.string.health_atlas_ovum_flow_fimbriae, 162f, 95f, 115f)
        line(c, 156f, 104f, 175f, 146f, coral, 1.25f)
        label(c, R.string.health_atlas_ovum_flow_tube, 280f, 78f, 138f)
        line(c, 275f, 90f, 275f, 121f, coral, 1.25f)
        label(c, R.string.health_atlas_ovum_flow_ovary, 82f, 314f, 136f)
    }

    private fun cilia(c: Canvas, t: Float) {
        val x0 = 28f
        val x1 = 333f
        rounded(c, x0, 94f, x1, 267f, 23f, 0xffffedd2)
        for (i in 0..21) {
            val x = 42f + i * 13.2f
            val force = 4f * exp(-((x - 14f - 330f * t) / 32f) * ((x - 14f - 330f * t) / 32f))
            val tilt = 6f + 10f * wave(t * 3.3f - i * .11f)
            for (sign in intArrayOf(-1, 1)) {
                val root = 181f + sign * (56f - force)
                oval(c, x - 7f, root + minOf(sign * 26f, 0f), x + 7f, root + maxOf(sign * 26f, 0f), peach, coral)
                disc(c, x, root + sign * 15f, 2.5f, violet)
                figure.rewind(); figure.moveTo(x, root)
                figure.quadTo(x - 3.3f, root - sign * 10.5f, x + tilt, root - sign * 20f)
                stroke(c, figure, teal, 1.5f)
            }
        }
        oocyte(c, 63f + 227f * t, 181f + 4f * wave(t), 14f)
        label(c, R.string.health_atlas_ovum_flow_cilia_label, 103f, 64f, 110f)
        line(c, 103f, 77f, 120f, 138f, teal, 1.2f)
        arrow(c, 127f, 302f, 244f, 302f, teal)
    }

    private fun destination(c: Canvas, t: Float) {
        stroke(c, ampulla, coral, 34f)
        stroke(c, ampulla, peach, 30f)
        stroke(c, ampulla, 0xffffeed1, 17f)
        figure.rewind()
        figure.moveTo(306f, 142f); figure.quadTo(331f, 152f, 347f, 148f)
        figure.lineTo(350f, 265f); figure.lineTo(329f, 265f)
        figure.quadTo(318f, 213f, 299f, 181f); figure.close()
        ink(peach); c.drawPath(figure, paint)
        stroke(c, figure, coral, 1.4f)
        at(ampullaTrack, .13f + .43f * HealthAtlasGameteMotion.pickup(t)) { x, y -> oocyte(c, x, y, 11f) }
        label(c, R.string.health_atlas_ovum_flow_ampulla_label, 175f, 72f, 142f)
        line(c, 176f, 82f, 172f, 120f, sienna, 1.3f)
        label(c, R.string.health_atlas_ovum_flow_uterus, 263f, 286f, 163f)
        arrow(c, 270f, 248f, 315f, 229f, teal)
    }

    private fun flow(c: Canvas, track: android.graphics.PathMeasure, t: Float, color: Long, count: Int) {
        for (i in 0 until count) at(track, t * 1.19f - .062f * i) { x, y ->
            disc(c, x, y, if (i == 0) 4.2f else 3.2f, color, cream)
        }
    }

    private fun sperm(c: Canvas, x: Float, y: Float, rotation: Float, size: Float, t: Float) {
        c.save()
        c.translate(x, y); c.rotate(rotation); c.scale(size, size)
        figure.rewind(); figure.moveTo(-4f, 0f)
        val curl = 7f * wave(t)
        figure.cubicTo(-14f, curl, -20f, -curl, -33f, curl * .66f)
        stroke(c, figure, teal, 1.55f)
        oval(c, -6f, -4f, 7f, 4f, 0xff74ae9d, teal)
        disc(c, 2f, -1f, 1.1f, cream)
        c.restore()
    }

    private fun oocyte(c: Canvas, x: Float, y: Float, r: Float) {
        val halo = r * 1.43f
        for (i in 0..11) {
            val a = i * PI.toFloat() / 6f
            disc(c, x + halo * cos(a), y + halo * sin(a), r * .22f, sand, sienna)
        }
        oval(c, x - r, y - r, x + r, y + r, cellShade, violet)
        disc(c, x + r * .60f, y - r * .54f, r * .12f, violet)
        disc(c, x - r * .27f, y - r * .34f, r * .13f, cream)
    }
}
