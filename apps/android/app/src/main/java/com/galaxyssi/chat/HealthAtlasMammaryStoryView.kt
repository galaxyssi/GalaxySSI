package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasMammaryStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.MAMMARY_MILK_FLOW) {
    private val sacX = 138f
    private val sacY = 177f
    private val ductEnd = 333f
    private val rim = 0xff9d626d
    private val seam = 0xffb67581
    private val nucleus = 0xffba8da7
    private val basal = 0xff609c90
    private val guide = 0xff546f73
    private val milk = 0xfffff5d6
    private val milkEdge = 0xffa67847
    private val wall = shade(78f, 279f, 0xfff7d4c5, 0xffe6a5ae)
    private val fluid = shade(100f, 245f, 0xfffffcf4, 0xfff7ecda)
    private val milkTint = LinearGradient(82f, 0f, 253f, 0f,
        0xffeccd93.toInt(), 0x00eccd93, Shader.TileMode.CLAMP)
    private val outline = Path()
    private val detail = Path()

    init { tag = "atlas-function-mammary-milk-flow-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val squeeze = when (step) {
            3 -> ease((t - .32f) / .68f)
            4 -> 1f - ease((t - .68f) / .32f)
            else -> 0f
        }
        val radius = 88f - 15f * squeeze
        val amount = when (step) {
            0 -> .14f
            1 -> .14f + .24f * t
            2 -> .38f + .62f * ease(t)
            3 -> 1f
            else -> 1f - .65f * ease(t)
        }
        tissue(c, radius, amount, squeeze)
        when (step) {
            0 -> {
                detail.rewind()
                detail.arcTo(sacX - radius + 15f, sacY - radius + 15f,
                    sacX + radius - 15f, sacY + radius - 15f, 100f + 126f * t, 42f, true)
                stroke(c, detail, teal, 2.5f)
            }
            1 -> for (i in 0..3) {
                val travel = (t * 1.35f - i * .11f).coerceIn(0f, 1f)
                val a = 202f + 29f * i
                disc(c, x(radius - 7f - 25f * travel, a), y(radius - 7f - 25f * travel, a),
                    1.6f + 1.6f * travel, milk, milkEdge)
            }
            3 -> signal(c, radius, t)
            4 -> flow(c, t)
        }
        leader(c, 91f, 61f, x(radius, 249f), y(radius, 249f))
        label(c, R.string.health_atlas_mammary_story_luminal_epithelium, 91f, 55f, 150f)
        leader(c, 289f, 121f, 300f, 153f)
        label(c, R.string.health_atlas_mammary_story_duct, 289f, 115f, 109f)
        label(c, R.string.health_atlas_mammary_story_lumen, sacX, 181f, 100f)
        leader(c, 102f, 308f, x(radius + 16f, 106f), y(radius + 16f, 106f))
        label(c, R.string.health_atlas_mammary_story_myoepithelial_cells, 102f, 325f, 177f)
    }

    private fun tissue(c: Canvas, r: Float, amount: Float, squeeze: Float) {
        // The sac deforms into a fixed duct through a continuous open neck.
        outline.rewind()
        outline.moveTo(ductEnd, 201f)
        outline.lineTo(275f, 201f)
        outline.cubicTo(246f, 201f, x(r, 40f) + 14f, y(r, 40f) - 17f, x(r, 40f), y(r, 40f))
        outline.arcTo(sacX - r, sacY - r, sacX + r, sacY + r, 40f, 280f, false)
        outline.cubicTo(x(r, 320f) + 14f, y(r, 320f) + 17f, 246f, 153f, 275f, 153f)
        outline.lineTo(ductEnd, 153f)
        ink(cream)
        paint.shader = fluid
        c.drawPath(outline, paint)
        paint.shader = milkTint
        paint.alpha = (165f * amount).toInt()
        c.drawPath(outline, paint)
        paint.shader = null

        paint.strokeCap = Paint.Cap.BUTT
        stroke(c, outline, rim, 27f)
        paint.shader = wall
        stroke(c, outline, peach, 24.5f)
        paint.shader = null
        paint.strokeCap = Paint.Cap.ROUND
        for (i in 0..15) {
            val a = 48f + 17.6f * i
            cell(c, x(r + 4f, a), y(r + 4f, a), a + 90f)
            if (i < 15) {
                val b = a + 8.8f
                line(c, x(r - 12f, b - 1f), y(r - 12f, b - 1f),
                    x(r + 12f, b + 1f), y(r + 12f, b + 1f), seam, .9f)
            }
        }
        for (row in 0..1) {
            val y = 153f + 48f * row
            for (i in 0..3) {
                val x = 267f + 17f * i
                cell(c, x, y - 4f + 8f * row, 0f)
                if (i < 3) line(c, x + 8.5f, y - 11f, x + 8.5f, y + 11f, seam, .9f)
            }
        }
        for (a in 66..306 step 40) {
            val reach = r + 16f
            val half = 13f - 2f * squeeze
            detail.rewind()
            detail.arcTo(sacX - reach, sacY - reach, sacX + reach, sacY + reach,
                a - half, 2f * half, true)
            stroke(c, detail, basal, 5.8f)
            stroke(c, detail, 0xffa8cbb7, 2f)
            c.save()
            c.translate(x(reach, a.toFloat()), y(reach, a.toFloat()))
            c.rotate(a + 90f)
            ink(teal)
            c.drawOval(-5.5f, -2.9f, 5.5f, 2.9f, paint)
            c.restore()
        }
        for (i in 0..18) {
            val size = ((amount - i / 21f) * 12f).coerceIn(0f, 1f)
            if (size == 0f) continue
            val a = i * 137.5f + 16f
            val distance = r * (.37f + .09f * (i % 4))
            if (kotlin.math.abs(y(distance, a) - sacY) < 11f) continue
            disc(c, x(distance, a), y(distance, a), (2.3f + .5f * (i % 3)) * size, milk, milkEdge)
        }
    }

    private fun cell(c: Canvas, x: Float, y: Float, angle: Float) {
        c.save()
        c.translate(x, y)
        c.rotate(angle)
        oval(c, -5.2f, -3.6f, 5.2f, 3.6f, nucleus, violet)
        disc(c, -1.6f, -.6f, 1.15f, 0xffdec4d2)
        c.restore()
    }

    private fun signal(c: Canvas, r: Float, t: Float) {
        label(c, R.string.health_atlas_mammary_story_oxytocin_signal, 264f, 335f, 136f)
        for (i in 0..2) {
            val travel = ((t - .065f * i) / .38f).coerceIn(0f, 1f)
            val reach = r + 22f + (1f - travel) * (44f - i * 11f)
            val a = 58f + 4f * i
            val px = x(reach, a)
            val py = y(reach, a)
            val size = 3.5f * (1f - ease((t - .4f) / .36f))
            detail.rewind()
            detail.moveTo(px, py - size)
            detail.lineTo(px + size, py)
            detail.lineTo(px, py + size)
            detail.lineTo(px - size, py)
            detail.close()
            ink(violet)
            c.drawPath(detail, paint)
        }
    }

    private fun flow(c: Canvas, t: Float) {
        for (i in 0..5) {
            val travel = t * 1.52f - i * .115f
            if (travel !in 0f..1f) continue
            val x = 193f + (ductEnd - 197f) * travel
            val y = sacY + (i % 3 - 1) * 6.5f * (1f - .45f * travel)
            disc(c, x, y, 3.4f, milk, milkEdge)
        }
        arrow(c, 269f, 226f, 320f, 226f, teal)
    }

    private fun leader(c: Canvas, x: Float, y: Float, targetX: Float, targetY: Float) {
        line(c, x, y, targetX, targetY, guide, 1.1f)
        disc(c, targetX, targetY, 2.15f, guide)
    }

    private fun x(r: Float, angle: Float) = sacX + r * cos(angle * .017453293f)
    private fun y(r: Float, angle: Float) = sacY + r * sin(angle * .017453293f)
    private fun ease(t: Float) = t.coerceIn(0f, 1f).let { it * it * (3f - 2f * it) }
}
