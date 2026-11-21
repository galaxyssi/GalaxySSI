package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Path.Direction

internal class HealthAtlasEndothelialStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.ENDOTHELIAL_EXCHANGE) {
    private val tissueFill = shade(24f, 314f, 0xffeff5e8, 0xffdeeade)
    private val lumenFill = shade(64f, 133f, 0xffffeae2, 0xfff7c8c0)
    private val liningFill = shade(0f, 24f, 0xfff6cebb, 0xffdf9da8)
    private val lymphFill = shade(264f, 305f, 0xffe0f3ea, 0xffaed5c9)
    private val tileSeam = Path().apply {
        moveTo(-3f, 0f)
        cubicTo(3f, 6f, -2f, 17f, 4f, 24f)
    }
    private val field = Path().apply { addRoundRect(18f, 24f, 342f, 314f, 12f, 12f, Direction.CW) }
    private val lymph = Path().apply {
        moveTo(352f, 267f)
        cubicTo(260f, 258f, 204f, 263f, 153f, 267f)
        cubicTo(113f, 270f, 64f, 259f, 54f, 281f)
        cubicTo(48f, 299f, 85f, 306f, 121f, 304f)
        cubicTo(192f, 304f, 243f, 286f, 352f, 299f)
        close()
    }
    private val tissueCell = Path().apply {
        moveTo(-24f, 1f)
        cubicTo(-12f, -3f, -8f, -11f, 3f, -8f)
        cubicTo(13f, -7f, 15f, -1f, 25f, 1f)
        cubicTo(14f, 2f, 9f, 9f, 0f, 8f)
        cubicTo(-10f, 9f, -14f, 3f, -24f, 1f)
        close()
    }
    private val soluteShape = Path().apply {
        moveTo(0f, -4.5f)
        lineTo(4.5f, 0f)
        lineTo(0f, 4.5f)
        lineTo(-4.5f, 0f)
        close()
    }
    private val proteinShape = Path().apply {
        moveTo(-8f, 0f)
        cubicTo(-10f, -5f, -5f, -9f, 0f, -6f)
        cubicTo(4f, -9f, 10f, -5f, 7f, 0f)
        cubicTo(11f, 4f, 4f, 9f, 0f, 6f)
        cubicTo(-4f, 9f, -10f, 4f, -8f, 0f)
        close()
    }
    private val lymphRoutes = List(3) { i ->
        val x = waterTissueX(i)
        val y = waterTissueY(i)
        track(Path().apply {
            moveTo(x, y)
            cubicTo(x - 6f, y + 34f, x - 4f, 262f, x + 2f, 275f)
            quadTo(x + 9f, 292f, x + 31f, 287f - 2f * i)
        })
    }

    init { tag = "atlas-function-endothelial-exchange-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        c.save()
        c.clipPath(field)
        anatomy(c)
        when (step) {
            0 -> {
                val x = 33f + 237f * t
                line(c, x, 153f, x + 55f, 153f, cream, 3f)
            }
            1 -> arrow(c, 176f, 118f, 176f, 187f, blue)
            2 -> {
                // Opposing solute paths are diffusion, not bulk water moving back into blood.
                arrow(c, 86f, 117f, 86f, 191f, sienna)
                arrow(c, 201f, 191f, 201f, 117f, sienna)
            }
            4 -> arrow(c, 103f, 226f, 103f, 281f, teal)
        }
        particles(c, step, t)
        c.restore()
        stroke(c, field, 0xffa6c1b6, 1.1f)

        label(c, R.string.health_atlas_endothelium_lumen, 270f, 87f, 134f)
        line(c, 268f, 151f, 268f, 166f, coral, 1.1f)
        disc(c, 268f, 151f, 1.8f, coral)
        label(c, R.string.health_atlas_endothelium_lining, 268f, 181f, 138f)
        label(c, R.string.health_atlas_endothelium_interstitium, 268f, 214f, 138f)
        label(c, R.string.health_atlas_endothelium_lymph_capillary, 263f, 283f, 133f)
        legend(c)
    }

    private fun anatomy(c: Canvas) {
        ink(cream)
        paint.shader = tissueFill
        c.drawPath(field, paint)
        paint.shader = lumenFill
        c.drawRect(18f, 63f, 342f, 134f, paint)
        paint.shader = null
        lining(c, 40f)
        lining(c, 133f)

        redCell(c, 53f, 87f, -19f)
        redCell(c, 226f, 99f, 13f)
        tissueCell(c, 55f, 230f, -21f)
        tissueCell(c, 241f, 241f, -17f)
        tissueCell(c, 314f, 233f, 24f)

        ink(cream)
        paint.shader = lymphFill
        c.drawPath(lymph, paint)
        paint.shader = null
        stroke(c, lymph, teal, 1.6f)
    }

    private fun lining(c: Canvas, y: Float) {
        c.save()
        c.translate(0f, y)
        ink(peach)
        paint.shader = liningFill
        c.drawRect(18f, 0f, 342f, 24f, paint)
        paint.shader = null
        for (i in 0..5) {
            val x = 18f + 54f * i
            if (i > 0) {
                c.save()
                c.translate(x, 0f)
                stroke(c, tileSeam, coral, 1.05f)
                c.restore()
            }
            oval(c, x + 16f, 8f, x + 36f, 16f, 0xffc5899c, coral)
        }
        line(c, 18f, 0f, 342f, 0f, coral, 1.25f)
        line(c, 18f, 24f, 342f, 24f, coral, 1.25f)
        c.restore()
    }

    private fun redCell(c: Canvas, x: Float, y: Float, angle: Float) {
        c.save()
        c.rotate(angle, x, y)
        oval(c, x - 16f, y - 8f, x + 16f, y + 8f, 0xffeaa4a3, coral)
        oval(c, x - 7f, y - 3f, x + 7f, y + 3f, 0xfff7c8c0, 0xffd48e91)
        c.restore()
    }

    private fun tissueCell(c: Canvas, x: Float, y: Float, angle: Float) {
        c.save()
        c.translate(x, y)
        c.rotate(angle)
        ink(0xffc0d6c1)
        c.drawPath(tissueCell, paint)
        stroke(c, tissueCell, 0xff91b3a1, 1f)
        oval(c, -6f, -3f, 6f, 3f, 0xff8ab1a7, 0xff749a8d)
        c.restore()
    }

    private fun particles(c: Canvas, step: Int, t: Float) {
        water(c, 266f, 119f)
        water(c, 307f, 99f)
        for (i in lymphRoutes.indices) {
            if (step == 4) {
                at(lymphRoutes[i], travel(t, i)) { x, y -> water(c, x, y) }
            } else {
                val f = when (step) {
                    0 -> 0f
                    1 -> travel(t, i)
                    else -> 1f
                }
                val startY = 96f + 6f * i
                water(c, waterTissueX(i) - 2f * (1f - f), startY + (waterTissueY(i) - startY) * f)
            }
        }

        val down = when {
            step < 2 -> 0f
            step == 2 -> travel(t)
            else -> 1f
        }
        val up = if (step == 2) travel(t, 1) else down
        solute(c, 99f, 82f + 121f * down)
        solute(c, 189f, 197f - 113f * up)

        val drift = when {
            step < 3 -> 0f
            step == 3 -> travel(t)
            else -> 1f
        }
        protein(c, 72f + 19f * drift, 118f, step == 3)
        protein(c, 214f + 20f * drift, 117f, step == 3)
        protein(c, 285f + 23f * drift, 116f, step == 3)
    }

    private fun travel(t: Float, delay: Int = 0): Float {
        val f = ((t - .08f - .09f * delay) / .66f).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }

    private fun waterTissueX(i: Int) = 121f + 17f * i
    private fun waterTissueY(i: Int) = 194f + 9f * i

    private fun water(c: Canvas, x: Float, y: Float) {
        disc(c, x, y, 4.5f, 0xff86bed7, blue)
        disc(c, x - 1f, y - 1.3f, 1.2f, 0xffe2f5fb)
    }

    private fun solute(c: Canvas, x: Float, y: Float) {
        c.save()
        c.translate(x, y)
        ink(0xfff1c17d)
        c.drawPath(soluteShape, paint)
        stroke(c, soluteShape, sienna, 1.1f)
        c.restore()
    }

    private fun protein(c: Canvas, x: Float, y: Float, active: Boolean = false) {
        c.save()
        c.translate(x, y)
        ink(if (active) 0xffbc92cd else 0xffd8b6dd)
        c.drawPath(proteinShape, paint)
        stroke(c, proteinShape, violet, if (active) 1.6f else 1.1f)
        disc(c, -3f, -2.5f, 1.5f, cream)
        c.restore()
    }

    private fun legend(c: Canvas) {
        water(c, 29f, 336f)
        label(c, R.string.health_atlas_endothelium_water, 60f, 340f, 48f)
        solute(c, 106f, 336f)
        label(c, R.string.health_atlas_endothelium_solutes, 157f, 340f, 89f)
        protein(c, 218f, 336f)
        label(c, R.string.health_atlas_endothelium_proteins, 285f, 340f, 108f)
    }
}
