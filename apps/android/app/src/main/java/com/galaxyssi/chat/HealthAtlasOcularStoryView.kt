package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

internal object HealthAtlasOcularMotion {
    fun transfer(t: Float, returnToRod: Boolean): Float {
        val f = HealthAtlasFunctionStory.safePhase(t)
        return if (returnToRod) 238f - 66f * f else 172f + 66f * f
    }

    fun limbalRadius(t: Float) = 104f - 76f * HealthAtlasFunctionStory.safePhase(t)

    fun relayFraction(t: Float, index: Int) =
        ((HealthAtlasFunctionStory.safePhase(t) - 0.08f * index) * 1.24f).coerceIn(0f, 1f)
}

internal class HealthAtlasOcularStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val outline = Path()
    private val surface = Path()
    private val rodFill = shade(70f, 192f, 0xffd6e8eb, 0xff7296b1)
    private val rpeFill = shade(232f, 294f, 0xff987da2, 0xff5c496b)
    private val opsinFill = shade(126f, 252f, 0xffcbddd6, 0xff7cae9c)
    private val tissueFill = shade(130f, 303f, 0xfff7d8c5, 0xffd39c9e)
    private val corneaFill = shade(57f, 295f, 0xffd3eae7, 0xff97c4cb)
    private val dimFill = shade(36f, 328f, 0xffe0eaf2, 0xffb8d5d4)
    private val transmit = 0xff598f86
    private val suppress = 0xff86598e
    private val retinol = 0xffaa6b31
    private val cisRetinal = 0xff307c6e
    private val rayAngles = FloatArray(8) { (it * PI / 4).toFloat() }
    private val rayColors = longArrayOf(0xff659f9b, 0xffca8d78, 0xff8d8eb3, 0xff6f9fb8)

    init {
        tag = when (story) {
            HealthAtlasFunctionStory.RPE_VISUAL_CYCLE -> "atlas-function-rpe-visual-cycle-art"
            HealthAtlasFunctionStory.DIM_LIGHT_RELAY -> "atlas-function-dim-light-relay-art"
            else -> "atlas-function-corneal-surface-renewal-art"
        }
    }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (story) {
            HealthAtlasFunctionStory.RPE_VISUAL_CYCLE -> when (step) {
                1 -> photon(c, t)
                3 -> conversion(c, t)
                else -> pigmentSection(c, step, t)
            }
            HealthAtlasFunctionStory.DIM_LIGHT_RELAY -> rodRelay(c, step, t)
            else -> if (step == 1 || step == 2) corneaFromFront(c, step == 2, t) else corneaSection(c, step, t)
        }
    }

    private fun pigmentSection(c: Canvas, step: Int, t: Float) {
        label(c, R.string.health_atlas_ocular_pigment_rod, 174f, 46f, 240f)
        rounded(c, 32f, 229f, 328f, 305f, 15f, 0xffe0ccd8)
        for (i in 0..5) {
            val x = 53f + i * 50f
            oval(c, x - 24f, 233f, x + 24f, 294f, rpeFill, violet)
            disc(c, x, 272f, 7f, 0xffd2b6cb, cream)
            for (j in -2..2) {
                val xpos = x + j * 7f
                line(c, xpos, 237f, xpos + (j - 1) * .7f, 224f - (j and 1) * 4f, violet, 1.8f)
            }
        }
        for (k in 0..2) {
            val x = 99f + k * 82f
            drawRod(c, x, 78f, 174f, 23f)
            if (step == 0) {
                val y = 99f + 55f * ((t + k * .22f) % 1f)
                disc(c, x, y, 4.1f, cisRetinal, cream)
            }
        }
        if (step == 2 || step == 4) {
            val returning = step == 4
            val color = if (returning) cisRetinal else retinol
            val x = 181f
            arrow(c, x + 29f, if (returning) 224f else 182f, x + 29f, if (returning) 182f else 222f, color)
            for (i in 0..2) {
                val y = HealthAtlasOcularMotion.transfer(HealthAtlasOcularMotion.relayFraction(t, i), returning)
                val trackX = x + i * 7f - 7f
                molecule(c, trackX, y, .43f, if (returning) .6f else 0f, color)
            }
            label(c, if (returning) R.string.health_atlas_ocular_pigment_cis else R.string.health_atlas_ocular_pigment_trans_retinol,
                263f, 210f, 83f)
        }
        label(c, R.string.health_atlas_ocular_pigment_rpe, 183f, 331f, 234f)
    }

    private fun drawRod(c: Canvas, x: Float, top: Float, bottom: Float, halfWidth: Float) {
        oval(c, x - halfWidth, top, x + halfWidth, bottom, rodFill, blue)
        for (i in 1..6) {
            val y = top + (bottom - top) * i / 7f
            val width = if (i == 1 || i == 6) .64f else .84f
            line(c, x - halfWidth * width, y, x + halfWidth * width, y, 0xff577c98, 1.3f)
        }
    }

    private fun photon(c: Canvas, t: Float) {
        label(c, R.string.health_atlas_ocular_pigment_photon, 174f, 45f, 184f)
        val y = 58f + 63f * t
        outline.rewind()
        outline.moveTo(164f, y); outline.lineTo(178f, y + 8f); outline.lineTo(171f, y + 14f)
        outline.lineTo(186f, y + 23f)
        stroke(c, outline, retinol, 2.6f)
        oval(c, 75f, 131f, 291f, 255f, opsinFill, transmit)
        oval(c, 132f, 166f, 236f, 218f, cream, transmit)
        val moved = ((t - .34f) / .58f).coerceIn(0f, 1f)
        molecule(c, 184f, 193f, 1.85f, .88f * (1f - moved), if (t < .42f) cisRetinal else retinol)
        label(c, R.string.health_atlas_ocular_pigment_opsin, 182f, 286f, 172f)
        label(c, if (t < .42f) R.string.health_atlas_ocular_pigment_cis else R.string.health_atlas_ocular_pigment_trans_retinal,
            182f, 322f, 220f)
    }

    private fun conversion(c: Canvas, t: Float) {
        label(c, R.string.health_atlas_ocular_pigment_rpe, 183f, 46f, 240f)
        rounded(c, 26f, 81f, 334f, 271f, 24f, 0xffdccee2)
        val y = 172f
        arrow(c, 92f, y, 151f, y, retinol)
        arrow(c, 211f, y, 273f, y, cisRetinal)
        disc(c, 72f, y, 24f, 0xfff0ded0, retinol)
        disc(c, 183f, y, 24f, 0xfff1e8da, sienna)
        disc(c, 292f, y, 24f, 0xffcde5d9, cisRetinal)
        molecule(c, 73f + 219f * t, 141f, .9f, .72f * ((t - .52f) * 2.1f).coerceIn(0f, 1f),
            if (t < .67f) retinol else cisRetinal)
        label(c, R.string.health_atlas_ocular_pigment_trans_retinol, 73f, 221f, 91f)
        label(c, R.string.health_atlas_ocular_pigment_ester, 183f, 221f, 91f)
        label(c, R.string.health_atlas_ocular_pigment_cis, 292f, 221f, 86f)
        ink(violet); paint.textSize = 14f
        c.drawText("RPE65", 238f, 117f, paint)
    }

    private fun molecule(c: Canvas, x: Float, y: Float, size: Float, bend: Float, color: Long) {
        val a = x - 12f * size
        val b = x + 12f * size
        val dy = bend * 10f * size
        line(c, a, y + dy, x, y, color, 3f * size)
        line(c, x, y, b, y + dy, color, 3f * size)
        disc(c, a, y + dy, 3.4f * size, color, cream)
        disc(c, b, y + dy, 3.4f * size, color, cream)
    }

    private fun rodRelay(c: Canvas, step: Int, t: Float) {
        oval(c, 23f, 24f, 338f, 336f, dimFill, 0xffa2bab9)
        val left = 104f
        val right = 256f
        val middle = 180f
        for (i in 0..2) {
            val x = 124f + i * 56f
            drawRod(c, x, 58f, 94f, 7f)
            line(c, x, 94f, middle, 124f, blue, 1.55f)
            if (step == 0) {
                disc(c, x, 46f + ((t + i * .21f) % 1f) * 31f, 3.4f, retinol, cream)
            } else if (step == 1) {
                pulse(c, x, 94f, middle, 124f, t, i, blue)
            }
        }
        label(c, R.string.health_atlas_ocular_relay_rod, 74f, 74f, 76f)
        disc(c, middle, 133f, 11f, blue, cream)
        label(c, R.string.health_atlas_ocular_relay_rod_bipolar, 258f, 135f, 111f)
        line(c, middle, 144f, middle, 171f, blue, 1.8f)
        disc(c, middle, 181f, 12f, violet, cream)
        label(c, R.string.health_atlas_ocular_relay_aii_label, 88f, 178f, 118f)
        if (step == 2) pulse(c, middle, 146f, middle, 170f, t, 0, blue)
        arrow(c, 172f, 192f, left, 231f, transmit)
        line(c, 190f, 192f, right, 231f, suppress, 1.65f)
        line(c, right - 5f, 237f, right + 5f, 225f, suppress, 2.2f)
        if (step == 3) {
            pulse(c, 172f, 192f, left, 228f, t, 0, transmit)
            pulse(c, 190f, 192f, right - 3f, 230f, t, 0, suppress)
            label(c, R.string.health_atlas_ocular_relay_gap, 76f, 213f, 93f)
            label(c, R.string.health_atlas_ocular_relay_glycine, 284f, 213f, 102f)
        }
        disc(c, left, 249f, 11f, transmit, cream)
        disc(c, right, 249f, 11f, suppress, cream)
        label(c, R.string.health_atlas_ocular_relay_on, 56f, 253f, 66f)
        label(c, R.string.health_atlas_ocular_relay_off, 303f, 253f, 68f)
        if (step == 4) {
            arrow(c, left, 261f, left, 295f, transmit)
            arrow(c, right, 261f, right, 295f, suppress)
            pulse(c, left, 264f, left, 294f, t, 0, transmit)
            pulse(c, right, 264f, right, 294f, t, 2, suppress)
            disc(c, left, 305f, 8f, transmit, cream)
            disc(c, right, 305f, 8f, suppress, cream)
            label(c, R.string.health_atlas_ocular_relay_ganglion, 179f, 310f, 122f)
        }
    }

    private fun pulse(c: Canvas, x1: Float, y1: Float, x2: Float, y2: Float, t: Float, index: Int, color: Long) {
        val f = HealthAtlasOcularMotion.relayFraction(t, index)
        disc(c, x1 + (x2 - x1) * f, y1 + (y2 - y1) * f, 4.5f, color, cream)
    }

    private fun corneaFromFront(c: Canvas, migrating: Boolean, t: Float) {
        oval(c, 55f, 56f, 305f, 306f, 0xffe6ece5, 0xffa9b8b5)
        oval(c, 73f, 74f, 287f, 288f, corneaFill, blue)
        ink(transmit, 7f); c.drawCircle(180f, 181f, 105f, paint)
        for (i in rayAngles.indices) {
            val angle = rayAngles[i]
            val x = cos(angle)
            val y = sin(angle)
            val color = rayColors[i % rayColors.size]
            if (migrating) {
                val radius = HealthAtlasOcularMotion.limbalRadius((t - i * .029f).coerceAtLeast(0f))
                line(c, 180f + x * 100f, 181f + y * 100f, 180f + x * radius, 181f + y * radius, color, 7f)
                disc(c, 180f + x * radius, 181f + y * radius, 5.8f, color, cream)
            } else {
                val r = 4f + 2f * wave(t + i * .095f)
                disc(c, 180f + x * 104f, 181f + y * 104f, r, color, cream)
            }
        }
        label(c, R.string.health_atlas_ocular_cornea_limbal_ring, 86f, 37f, 121f)
        line(c, 100f, 47f, 122f, 88f, teal, 1.2f)
        label(c, R.string.health_atlas_ocular_cornea_center, 183f, 333f, 167f)
    }

    private fun corneaSection(c: Canvas, step: Int, t: Float) {
        val tearRipple = if (step == 0) wave(t) * 6f else 0f
        rounded(c, 26f, 110f, 334f, 276f, 16f, 0xffdce9dd)
        for (i in 0..7) {
            val x = 44f + 38f * i
            oval(c, x - 16f, 193f, x + 16f, 253f, tissueFill, coral)
            disc(c, x, 224f, 5.3f, violet, cream)
        }
        for (i in 0..6) {
            val x = 52f + 41f * i
            oval(c, x - 18f, 155f, x + 18f, 193f, 0xffecc1ac, coral)
            disc(c, x, 174f, 3.9f, violet, cream)
        }
        for (i in 0..7) {
            val x = 45f + 38f * i
            val leaving = if (step == 4 && i in 2..4) t * (35f + i * 4f) else 0f
            oval(c, x - 17f, 128f - leaving, x + 17f, 152f - leaving, 0xffe7beb0, coral)
            if (step == 4 && i in 2..4) {
                oval(c, x - 17f, 155f - 21f * t, x + 17f, 163f - 13f * t, 0xffedc5b3, coral)
            }
        }
        if (step == 3) {
            val y = 219f - t * 77f
            val r = 16f - t * 9f
            oval(c, 164f - t * 4f, y - r, 196f + t * 4f, y + r, 0xff89bdb1, transmit)
            disc(c, 180f, y, 4.3f, teal, cream)
            arrow(c, 211f, 220f, 211f, y - 4f, teal)
        }
        surface.rewind()
        surface.moveTo(34f, 118f)
        surface.cubicTo(100f, 111f + tearRipple, 214f, 127f - tearRipple, 325f, 118f)
        if (step != 4) stroke(c, surface, 0xff6da7b9, 4f)
        if (step == 0) {
            label(c, R.string.health_atlas_ocular_cornea_tear, 105f, 72f, 130f)
            line(c, 106f, 83f, 106f, 118f, blue, 1.2f)
            label(c, R.string.health_atlas_ocular_cornea_epithelium, 176f, 318f, 248f)
        } else {
            label(c, R.string.health_atlas_ocular_cornea_flat, 277f, 67f, 141f)
            line(c, 294f, 77f, 309f, 128f, coral, 1.2f)
            label(c, R.string.health_atlas_ocular_cornea_basal, 100f, 318f, 150f)
            line(c, 100f, 298f, 100f, 252f, coral, 1.2f)
        }
    }
}
