package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path

internal class HealthAtlasHairCycleStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.HAIR_FOLLICLE_CYCLE) {
    private val dermis = shade(SURFACE, 329f, 0xffffe1d7, 0xffead5e1)
    private val wall = shade(SURFACE, 296f, 0xffffeadb, 0xffdba1ba)
    private val wallEdge = 0xff9e647c
    private val hairInk = 0xff534057
    private val hairLight = 0xffba8e94
    private val leader = 0xff6b6376
    private val path = Path()
    private val epidermis = Path().apply {
        moveTo(24f, SURFACE)
        lineTo(336f, SURFACE)
        lineTo(336f, 149f)
        for (x in 336 downTo 48 step 24) {
            cubicTo(x - 8f, 149f, x - 10f, 159f, x - 15f, 154f)
            quadTo(x - 20f, 149f, x - 24f, 149f)
        }
        close()
    }

    init { tag = "atlas-function-hair-follicle-cycle-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val f = ease(t)
        val renew = if (step == 4) ease((t - .45f) / .55f) else 0f
        val bulb = when (step) {
            2 -> 282f - 81f * f
            3, 4 -> 201f + 81f * renew
            else -> 282f
        }
        val matrix = when (step) {
            2 -> 1f - ease(2f * t)
            3, 4 -> renew
            else -> 1f
        }
        drawSkin(c)
        drawFollicle(c, bulb, matrix, t, step == 0)
        callout(c, R.string.health_atlas_hair_cycle_story_label_epidermis, 76f, 108f, 101f, 141f)
        callout(c, R.string.health_atlas_hair_cycle_story_label_follicle, 76f, 216f, 163f, 169f)

        if (step == 4) {
            drawRenewal(c, t, renew, bulb)
            return
        }
        val club = when (step) {
            2 -> f
            3 -> 1f
            else -> 0f
        }
        val root = bulb - 8f - 10f * club
        val tip = when (step) {
            0 -> 93f
            1 -> 93f - 19f * f
            else -> 74f
        }
        if (step == 3) {
            // A moving focus cue, not motion of the resting follicle or its hair.
            val halo = 13f + 5f * wave(t - .25f)
            ink(teal, 2f)
            paint.alpha = (145f - 6f * (halo - 8f)).toInt()
            c.drawOval(axis(root) - halo, root - halo, axis(root) + halo, root + halo, paint)
        }
        drawHair(c, tip, root, club)
        if (step == 1) arrow(c, 127f, 109f - 13f * f, 120f - 4f * f, 96f - 16f * f, teal)
        callout(c, R.string.health_atlas_hair_cycle_story_label_shaft, 273f, 76f, axis(104f), 104f)
        when (step) {
            0, 1 -> callout(c, R.string.health_atlas_hair_cycle_story_label_matrix, 273f, 284f,
                axis(bulb) + 10f, bulb - 4f)
            2 -> callout(c, R.string.health_atlas_hair_cycle_story_label_lower, 273f, 241f,
                axis(bulb) + 7f, bulb - 4f)
            3 -> callout(c, R.string.health_atlas_hair_cycle_story_label_club, 273f, 195f, axis(root), root)
        }
    }

    private fun drawSkin(c: Canvas) {
        ink(cream)
        paint.shader = dermis
        c.drawRoundRect(24f, SURFACE, 336f, 329f, 14f, 14f, paint)
        paint.shader = null
        ink(0xffbe8694, 1.3f)
        c.drawRoundRect(24f, SURFACE, 336f, 329f, 14f, 14f, paint)
        for (side in 0..1) {
            for (i in 0..5) {
                val x = 39f + side * 200f + (i % 3) * 23f
                val y = 175f + i * 23f
                path.rewind()
                path.moveTo(x, y)
                path.cubicTo(x + 11f, y - 6f, x + 22f, y + 8f, x + 39f, y + 1f)
                stroke(c, path, 0xffd8aab4, 1.15f)
            }
        }
        ink(0xfff4c1b6)
        c.drawPath(epidermis, paint)
        stroke(c, epidermis, 0xffbc8186, 1.3f)
        line(c, 26f, 137f, 334f, 137f, 0xffffe5d6, 2f)

        // The small sebaceous gland and its duct mark the unchanging upper follicle.
        line(c, 187f, 161f, 219f, 155f, 0xffd59c79, 5f)
        for (i in 0..2) {
            val x = 204f + i * 10f
            val y = if (i == 1) 159f else 152f
            oval(c, x, y - 9f, x + 14f, y + 7f, 0xffffdab2, 0xffbd8b72)
        }
    }

    private fun drawFollicle(c: Canvas, bulb: Float, matrix: Float, t: Float, divide: Boolean) {
        val center = axis(bulb)
        val middle = (170f + bulb) / 2f
        val width = 9f + 11f * (bulb - 201f) / 81f
        val curve = 10f + 5f * matrix
        path.rewind()
        path.moveTo(163f, SURFACE)
        path.cubicTo(160f, 147f, 163f, 158f, 163f, 170f)
        path.cubicTo(163f, middle, center - width, middle, center - width, bulb)
        path.cubicTo(center - width, bulb + curve, center + width, bulb + curve, center + width, bulb)
        path.cubicTo(center + width, middle, 196f, middle, 196f, 170f)
        path.cubicTo(196f, 158f, 188f, 147f, 183f, SURFACE)
        path.close()
        ink(cream)
        paint.shader = wall
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, wallEdge, 1.7f)
        line(c, axis(SURFACE), SURFACE, axis(bulb - 13f), bulb - 13f, 0xffecc1c8, 12f)
        line(c, 164f, SURFACE, 182f, SURFACE, 0xffaf7686, 1.1f)

        if (matrix > 0f) {
            for (i in -2..2) {
                val x = center + i * (2f + 3f * matrix)
                val y = bulb - 9f + i * i * 2.5f
                val split = if (divide) 2.6f * (1f + wave(t + .18f * i)) else 1.3f
                disc(c, x, y, 3.3f * matrix, 0xffa65883, cream)
                disc(c, x, y - split, 2.4f * matrix, 0xffe79db8, cream)
            }
        }
        val papilla = 4f + 3f * matrix
        oval(c, center - papilla, bulb - 3f, center + papilla, bulb + 8f,
            0xffcec6e6, 0xff78628e)
    }

    private fun drawHair(c: Canvas, tip: Float, root: Float, club: Float, opacity: Float = 1f) {
        path.rewind()
        path.moveTo(axis(tip), tip)
        if (tip < SURFACE) {
            val middle = (tip + SURFACE) / 2f
            path.quadTo(axis(SURFACE) + SLOPE * (middle - SURFACE), middle, axis(SURFACE), SURFACE)
        }
        path.lineTo(axis(root), root)
        ink(hairInk, 6.8f)
        paint.alpha = (255f * opacity).toInt()
        c.drawPath(path, paint)
        ink(hairLight, 1.4f)
        paint.alpha = (220f * opacity).toInt()
        c.save()
        c.translate(-1.2f, 0f)
        c.drawPath(path, paint)
        c.restore()
        if (club > 0f) {
            ink(hairInk)
            paint.alpha = (255f * opacity).toInt()
            val r = 3.1f + 2.1f * club
            c.drawOval(axis(root) - r, root - 5f, axis(root) + r, root + r, paint)
        }
    }

    private fun drawRenewal(c: Canvas, t: Float, renew: Float, bulb: Float) {
        // Move the old hair along the pore before lifting it clear of the skin.
        val release = ease(t / .56f)
        val lift = 65f * release
        val drift = SLOPE * lift + 10f * ease((release - .78f) / .22f)
        val opacity = 1f - ease((t - .58f) / .21f)
        if (opacity > 0f) {
            c.save()
            c.translate(-drift, -lift)
            drawHair(c, 74f, 183f, 1f, opacity)
            c.restore()
        }
        if (opacity > .18f) callout(c, R.string.health_atlas_hair_cycle_story_label_shedding,
            273f, 54f, axis(106f) - drift, 106f - lift)
        if (renew > 0f) {
            val root = bulb - 8f
            val tip = root + (93f - root) * renew
            drawHair(c, tip, root, 0f)
            val y = (tip + root) / 2f
            if (renew > .08f) callout(c, R.string.health_atlas_hair_cycle_story_label_replacement,
                273f, 251f, axis(y), y)
        }
    }

    private fun callout(c: Canvas, id: Int, x: Float, y: Float, anchorX: Float, anchorY: Float) {
        label(c, id, x, y, 116f)
        line(c, x, y + 6f, x + if (x < 180f) 23f else -29f, y + 6f, leader, 1.25f)
        line(c, x + if (x < 180f) 23f else -29f, y + 6f, anchorX, anchorY, leader, 1.25f)
        disc(c, anchorX, anchorY, 2.1f, leader, cream)
    }

    private fun axis(y: Float): Float {
        val d = y - SURFACE
        return 173f + SLOPE * d - if (d < 0f) .005f * d * d else 0f
    }

    private fun ease(t: Float): Float {
        val f = t.coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }

    private companion object {
        const val SURFACE = 132f
        const val SLOPE = .19f
    }
}
