package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure

internal class HealthAtlasCartilageStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.CARTILAGE_LOAD) {
    private val band = Path()
    private val surface = Path()
    private val bone = Path()
    private val detail = Path()
    private val fluidRoute = PathMeasure()
    private val patellaFill = shade(76f, 152f, 0xffffeddb, 0xffe1ba99)
    private val trochleaFill = shade(227f, 283f, 0xffe4bd9e, 0xffffebcf)
    private val cartilageFill = shade(174f, 246f, 0xffd4efe6, 0xffa3cabe)
    private val boneEdge = 0xff9b745c
    private val fluidInk = 0xff346f98
    private val loadInk = 0xffa26030
    private val spaceInk = 0xff739292

    init { tag = "atlas-function-cartilage-load-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val f = t * t * (3f - 2f * t)
        val depth = when (step) {
            1 -> (23f * f - GAP).coerceAtLeast(0f)
            2 -> 7f + 14f * f
            3 -> 21f - 4f * f
            4 -> 17f * (1f - f)
            else -> 0f
        }
        val travel = when (step) {
            1 -> 23f * f
            2 -> GAP + depth
            3 -> 37f * (1f - f)
            else -> 0f
        }
        val pressure = when (step) {
            1 -> depth / 7f
            2 -> 1f - .83f * f
            3 -> .17f * (1f - f)
            else -> 0f
        }
        drawTrochlea(c, depth, pressure, step, t)
        drawPatella(c, travel)
        if (step == 1 || step == 2) drawLoad(c, travel, t, step == 1)
        if (step == 2 || step == 4) drawFlow(c, depth, t, returning = step == 4)
        drawLabels(c, depth, travel)
    }

    private fun drawTrochlea(c: Canvas, depth: Float, pressure: Float, step: Int, t: Float) {
        bone.rewind()
        bone.moveTo(32f, baseY(32f))
        for (x in 36..328 step 4) bone.lineTo(x.toFloat(), baseY(x.toFloat()))
        bone.cubicTo(326f, 255f, 315f, 278f, 284f, 281f)
        bone.lineTo(76f, 281f)
        bone.cubicTo(45f, 278f, 34f, 255f, 32f, baseY(32f))
        bone.close()
        ink(cream); paint.shader = trochleaFill; c.drawPath(bone, paint); paint.shader = null
        c.save()
        c.clipPath(bone)
        for (i in 0..13) {
            val x = 43f + 21f * i
            val y = baseY(x) + 7f + 6f * (i % 3)
            line(c, x, y, x + 16f, y + 11f, 0xffc79b7e, 1.5f)
            line(c, x + 16f, y + 11f, x + 23f, y + 5f, 0xffc79b7e, 1.5f)
        }
        c.restore()
        stroke(c, bone, boneEdge, 1.6f)

        surface.rewind()
        surface.moveTo(32f, faceY(32f, depth))
        for (x in 36..328 step 4) surface.lineTo(x.toFloat(), faceY(x.toFloat(), depth))
        band.set(surface)
        for (x in 328 downTo 32 step 4) band.lineTo(x.toFloat(), baseY(x.toFloat()))
        band.close()
        ink(cream); paint.shader = cartilageFill; c.drawPath(band, paint); paint.shader = null
        c.save()
        c.clipPath(band)
        if (pressure > 0f) {
            ink(0xff75bacc)
            paint.alpha = (150f * pressure).toInt()
            val y = faceY(CENTER, depth)
            c.drawOval(107f, y - 7f, 253f, y + 27f, paint)
        }
        for (row in 1..3) {
            val fraction = row * .23f
            detail.rewind()
            detail.moveTo(32f, matrixY(32f, depth, fraction))
            for (x in 36..328 step 4) detail.lineTo(x.toFloat(), matrixY(x.toFloat(), depth, fraction))
            stroke(c, detail, 0xff79afa0, 1.25f)
        }
        for (i in 0..11) {
            val drift = if (step == 0) 8f * wave(t + i * .21f) else 0f
            val x = 48f + 24f * i + drift
            val fraction = .32f + .20f * (i % 3) + if (step == 0) .08f * wave(t + i * .21f + .25f) else 0f
            disc(c, x, matrixY(x, depth, fraction), 3.3f, fluidInk, cream)
        }
        c.restore()
        stroke(c, band, teal, 1.4f)
        stroke(c, surface, teal, 2.6f)
    }

    private fun drawPatella(c: Canvas, travel: Float) {
        c.save()
        c.translate(0f, travel)
        bone.rewind()
        bone.moveTo(68f, patellarFaceY(68f) - 18f)
        bone.cubicTo(87f, 81f, 131f, 76f, CENTER, 76f)
        bone.cubicTo(229f, 76f, 273f, 81f, 292f, patellarFaceY(292f) - 18f)
        for (x in 292 downTo 68 step 4) bone.lineTo(x.toFloat(), patellarFaceY(x.toFloat()) - 18f)
        bone.close()
        ink(cream); paint.shader = patellaFill; c.drawPath(bone, paint); paint.shader = null
        stroke(c, bone, boneEdge, 1.6f)

        band.rewind()
        band.moveTo(68f, patellarFaceY(68f))
        for (x in 72..292 step 4) band.lineTo(x.toFloat(), patellarFaceY(x.toFloat()))
        for (x in 292 downTo 68 step 4) band.lineTo(x.toFloat(), patellarFaceY(x.toFloat()) - 18f)
        band.close()
        ink(0xffb7ddcf); c.drawPath(band, paint)
        stroke(c, band, teal, 1.6f)
        c.restore()
    }

    private fun drawLoad(c: Canvas, travel: Float, t: Float, arriving: Boolean) {
        for (i in -1..1) {
            val x = CENTER + i * 25f
            val y = 68f + travel - if (arriving) 9f * (1f - t) else 0f
            forceArrow(c, x, y - 24f, y, loadInk)
        }
    }

    private fun drawFlow(c: Canvas, depth: Float, t: Float, returning: Boolean) {
        // The illustrative routes turn at exposed shoulders, not through the contact or bone.
        for (side in -1..1 step 2) {
            val start = CENTER + side * 22f
            val bend = CENTER + side * 76f
            val exit = CENTER + side * 110f
            detail.rewind()
            detail.moveTo(start, matrixY(start, depth, .43f))
            detail.cubicTo(bend, matrixY(bend, depth, .55f), exit, faceY(exit, depth) + 25f,
                exit, faceY(exit, depth) - 8f)
            fluidRoute.setPath(detail, false)
            val opacity = if (returning) ((1f - t) * 4f).coerceAtMost(1f) else 1f
            val color = (fluidInk and 0x00ffffff) or ((255f * opacity).toLong() shl 24)
            for (i in 0..1) {
                val f = .04f + .92f * ((t * 1.4f + i * .5f) % 1f)
                val head = if (returning) 1f - f else f
                val tail = head + if (returning) .18f else -.18f
                at(fluidRoute, tail) { x1, y1 ->
                    at(fluidRoute, head) { x2, y2 -> arrow(c, x1, y1, x2, y2, color) }
                }
            }
        }
    }

    private fun drawLabels(c: Canvas, depth: Float, travel: Float) {
        label(c, R.string.health_atlas_cartilage_story_label_patella, 83f, 42f, 104f)
        line(c, 83f, 49f, 113f, 92f + travel, boneEdge, 1.1f)
        disc(c, 113f, 92f + travel, 2.2f, boneEdge, cream)

        val space = (patellarFaceY(303f) + travel + faceY(303f, depth)) / 2f
        label(c, R.string.health_atlas_cartilage_story_label_joint_space, 290f, 42f, 116f)
        line(c, 318f, 49f, 318f, space, spaceInk, 1.1f)
        line(c, 318f, space, 303f, space, spaceInk, 1.1f)
        disc(c, 303f, space, 2.2f, spaceInk, cream)

        label(c, R.string.health_atlas_cartilage_story_label_trochlea, 98f, 309f, 145f)
        line(c, 98f, 295f, 107f, 262f, boneEdge, 1.1f)
        disc(c, 107f, 262f, 2.2f, boneEdge, cream)
        label(c, R.string.health_atlas_cartilage_story_label_matrix, 263f, 309f, 147f)
        line(c, 305f, 296f, 336f, 273f, teal, 1.1f)
        line(c, 336f, 273f, 336f, 216f, teal, 1.1f)
        line(c, 336f, 216f, 305f, 216f, teal, 1.1f)
        disc(c, 305f, 216f, 2.2f, teal, cream)

        line(c, 23f, 323f, 337f, 323f, 0xffc6c9b8, 1f)
        disc(c, 35f, 342f, 3.6f, fluidInk, cream)
        label(c, R.string.health_atlas_cartilage_story_label_fluid, 112f, 347f, 132f)
        forceArrow(c, 211f, 335f, 348f, loadInk)
        label(c, R.string.health_atlas_cartilage_story_label_load, 270f, 347f, 100f)
    }

    private fun forceArrow(c: Canvas, x: Float, from: Float, tip: Float, color: Long) {
        line(c, x, from, x, tip - 1f, color, 3f)
        line(c, x - 5f, tip - 6f, x, tip, color, 3f)
        line(c, x + 5f, tip - 6f, x, tip, color, 3f)
    }

    private fun patellarFaceY(x: Float) = 168f - .0034f * offsetSquared(x)
    private fun baseY(x: Float) = 245f - .0007f * offsetSquared(x)

    private fun faceY(x: Float, depth: Float): Float {
        val radiusSquared = offsetSquared(x)
        val rest = 184f - .0005f * radiusSquared
        if (depth <= 0f) return rest
        // Smooth the edge of the local indentation; the bone attachment does not move.
        val overlap = depth - .0029f * radiusSquared
        val edge = minOf(3f, depth * .5f)
        val localDepth = when {
            overlap >= edge -> overlap
            overlap <= -edge -> 0f
            else -> (overlap + edge) * (overlap + edge) / (4f * edge)
        }
        return rest + localDepth
    }

    private fun matrixY(x: Float, depth: Float, fraction: Float): Float {
        val top = faceY(x, depth)
        return top + (baseY(x) - top) * fraction
    }

    private fun offsetSquared(x: Float) = (x - CENTER) * (x - CENTER)

    private companion object {
        const val CENTER = 180f
        const val GAP = 16f
    }
}
