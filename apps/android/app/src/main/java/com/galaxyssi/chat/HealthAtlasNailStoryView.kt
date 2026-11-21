package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path

internal class HealthAtlasNailStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.NAIL_MATRIX_GROWTH) {
    private val skinShade = shade(140f, 286f, 0xfff7d6bf, 0xffe8ad9e)
    private val boneShade = shade(190f, 255f, 0xffffefd1, 0xffe3bd95)
    private val plateShade = shade(151f, 189f, 0xfffdf5e5, 0xffd9bec8)
    private val skinEdge = 0xffa76e64
    private val plateEdge = 0xff725d70
    private val cellInk = 0xff8c526b
    private val leader = 0xff655f6b
    private val work = Path()
    private val plate = Path()
    private val finger = Path().apply {
        moveTo(22f, 149f)
        cubicTo(55f, 152f, 84f, 177f, ROOT_X, plateY(ROOT_X) + THICKNESS)
        plateArc(this, ROOT_X, BED_END, THICKNESS)
        cubicTo(278f, 178f, 289f, 185f, 295f, 202f)
        cubicTo(301f, 220f, 295f, 245f, 280f, 259f)
        cubicTo(264f, 275f, 243f, 283f, 212f, 285f)
        cubicTo(153f, 289f, 113f, 271f, 22f, 278f)
        close()
    }
    private val outerSkin = Path().apply {
        moveTo(BED_END, plateY(BED_END) + THICKNESS)
        cubicTo(278f, 178f, 289f, 185f, 295f, 202f)
        cubicTo(301f, 220f, 295f, 245f, 280f, 259f)
        cubicTo(264f, 275f, 243f, 283f, 212f, 285f)
        cubicTo(153f, 289f, 113f, 271f, 22f, 278f)
    }
    private val fold = Path().apply {
        moveTo(22f, 149f)
        cubicTo(50f, 151f, 75f, 143f, 96f, 140f)
        cubicTo(121f, 136f, 139f, 142f, 150f, 155f)
        quadTo(143f, 160f, 129f, 162f)
        cubicTo(113f, 166f, 101f, 173f, 94f, 179f)
        cubicTo(61f, 172f, 42f, 177f, 22f, 181f)
        close()
    }
    private val dorsalSkin = Path().apply {
        moveTo(22f, 149f)
        cubicTo(50f, 151f, 75f, 143f, 96f, 140f)
        cubicTo(121f, 136f, 139f, 142f, 150f, 155f)
        quadTo(145f, 159f, 137f, 160f)
    }
    private val phalanx = Path().apply {
        moveTo(63f, 236f)
        cubicTo(74f, 222f, 112f, 224f, 143f, 219f)
        cubicTo(178f, 213f, 212f, 193f, 246f, 195f)
        cubicTo(260f, 193f, 270f, 203f, 264f, 217f)
        cubicTo(257f, 231f, 234f, 235f, 211f, 240f)
        cubicTo(167f, 250f, 119f, 251f, 93f, 254f)
        cubicTo(75f, 256f, 60f, 249f, 63f, 236f)
        close()
    }
    private val matrix = Path().apply {
        moveTo(94f, 182f)
        cubicTo(100f, 173f, 113f, 169f, ROOT_X, plateY(ROOT_X) + THICKNESS - 2f)
        plateArc(this, ROOT_X, MATRIX_END, THICKNESS - 2f)
        lineTo(MATRIX_END, plateY(MATRIX_END) + THICKNESS + 6f)
        cubicTo(151f, 177f, 152f, 185f, 143f, 186f)
        cubicTo(134f, 187f, 137f, 195f, 126f, 195f)
        cubicTo(117f, 194f, 114f, 204f, 104f, 202f)
        quadTo(91f, 201f, 94f, 182f)
        close()
    }

    init { tag = "atlas-function-nail-matrix-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val slide = when (step) {
            3 -> 12f * ease(t / .9f)
            4 -> 12f + 23f * ease((t - .09f) / .85f)
            else -> 0f
        }
        drawSection(c, step == 4)
        if (step == 1) drawDivision(c, t)
        drawPlate(c, 306f + slide)
        when (step) {
            0 -> drawOrientation(c, t)
            2 -> drawMaturation(c, t)
            3, 4 -> drawPlateLandmarks(c, slide, step, t)
        }
        drawFold(c)

        callout(c, R.string.health_atlas_nail_story_label_fold, 75f, 99f, 91f, 118f, 124f, 145f)
        callout(c, R.string.health_atlas_nail_story_label_plate, 179f, 76f, 179f, 95f, 181f, 154f)
        callout(c, R.string.health_atlas_nail_story_label_bed, 237f, 116f, 237f, 133f, 245f, 170f)
        callout(c, R.string.health_atlas_nail_story_label_edge, 302f, 99f, 302f, 119f, 301f, 168f)
        callout(c, R.string.health_atlas_nail_story_label_matrix, 58f, 316f, 43f, 248f, 101f, 197f)
    }

    private fun drawSection(c: Canvas, emphasizeBed: Boolean) {
        ink(peach)
        paint.shader = skinShade
        c.drawPath(finger, paint)
        paint.shader = null
        stroke(c, outerSkin, skinEdge, 9f)
        stroke(c, outerSkin, 0xffe9b09b, 6f)
        ink(sand)
        paint.shader = boneShade
        c.drawPath(phalanx, paint)
        paint.shader = null
        stroke(c, phalanx, 0xffad8465, 1.7f)
        for (i in 0..11) {
            val x = 82f + i * 14f
            val y = 241f - .0009f * (x - 81f) * (x - 81f)
            line(c, x, y, x + 5f, y - 5f, 0xffd1a781, 1.2f)
        }
        for (i in 0..6) {
            val x = 173f + i * 15f
            val y = 265f - .0036f * (x - 199f) * (x - 199f)
            line(c, x, y, x + 3f, y - 11f, 0xffc68f7d, 1f)
        }

        work.rewind()
        work.moveTo(MATRIX_END, plateY(MATRIX_END) + THICKNESS - 1f)
        plateArc(work, MATRIX_END, BED_END, THICKNESS - 1f)
        work.lineTo(BED_END, plateY(BED_END) + THICKNESS + 6f)
        plateArc(work, BED_END, MATRIX_END, THICKNESS + 6f)
        work.close()
        ink(if (emphasizeBed) 0xffb66d77 else 0xffd68f95)
        c.drawPath(work, paint)
        stroke(c, work, 0xffab6a78, 1.1f)
        for (x in 168..265 step 8) {
            val y = plateY(x.toFloat()) + THICKNESS
            line(c, x.toFloat(), y + 2f, x + 2f, y + 4.5f, 0xfff4c5bd, 1.2f)
        }
        ink(0xffcd8fa2)
        c.drawPath(matrix, paint)
        stroke(c, matrix, cellInk, 1.4f)
        for (i in 0..5) {
            val x = 103f + i * 9f
            val y = 192f - i * 3.2f
            oval(c, x - 2.5f, y - 2f, x + 2.5f, y + 2f, 0xffecc0c5, cellInk)
        }
    }

    private fun drawPlate(c: Canvas, tip: Float) {
        plate.rewind()
        plate.moveTo(ROOT_X, plateY(ROOT_X))
        plateArc(plate, ROOT_X, tip - 3f, 0f)
        plate.quadTo(tip, plateY(tip), tip, plateY(tip) + 3f)
        plate.lineTo(tip, plateY(tip) + 7f)
        plate.quadTo(tip, plateY(tip) + 10f, tip - 3f, plateY(tip - 3f) + THICKNESS)
        plateArc(plate, tip - 3f, ROOT_X, THICKNESS)
        plate.cubicTo(113f, 176f, 105f, 187f, 96f, 186f)
        plate.cubicTo(89f, 184f, 92f, 177f, 97f, 175f)
        plate.cubicTo(106f, 169f, 116f, 166f, ROOT_X, plateY(ROOT_X))
        plate.close()
        ink(cream)
        paint.shader = plateShade
        c.drawPath(plate, paint)
        paint.shader = null
        c.save()
        c.clipPath(plate)
        band(c, BED_END, tip, THICKNESS / 2f, THICKNESS + 2f, 0xfff5e9da)
        band(c, ROOT_X, tip, 3f, 1.2f, 0xfffffbf0)
        band(c, ROOT_X, tip, 7f, 1f, 0xffcbb2b3)
        c.restore()
        stroke(c, plate, plateEdge, 1.7f)
    }

    private fun drawFold(c: Canvas) {
        ink(0xfff6d3b9)
        c.drawPath(fold, paint)
        stroke(c, dorsalSkin, skinEdge, 7f)
        stroke(c, dorsalSkin, 0xffe7ab94, 4.5f)
        line(c, 149f, 154f, 157f, plateY(157f), 0xffb78573, 2.2f)
    }

    private fun drawOrientation(c: Canvas, t: Float) {
        // A sweep of attention across the section; no tissue moves in this chapter.
        val x = 142f + 143f * ease(t)
        c.save()
        c.clipPath(plate)
        band(c, x - 13f, x + 13f, 2f, 6f, 0xffa4c6bb)
        c.restore()
    }

    private fun drawDivision(c: Canvas, t: Float) {
        c.save()
        c.clipPath(matrix)
        for (i in 0..2) {
            val split = ease((t - .13f - .12f * i) / .5f)
            val x = 108f + i * 12f
            val y = 190f - i * 4f
            val separation = 3.6f * split
            val radius = 4.5f - 1.2f * split
            for (side in -1..1 step 2) {
                val dx = side * separation
                oval(c, x + dx - radius, y - radius - dx * .26f,
                    x + dx + radius, y + radius - dx * .26f, 0xfff7d3cf, cellInk)
                disc(c, x + dx, y - dx * .26f, 1.3f, cellInk)
            }
        }
        c.restore()
    }

    private fun drawMaturation(c: Canvas, t: Float) {
        for (i in 0..2) {
            val enter = ease((t - i * .09f) / .8f)
            val flatten = ease((enter - .15f) / .78f)
            val x = 110f + 10f * i + 29f * enter
            val startY = 190f - 3.4f * i
            val y = startY + (plateY(x) + 5.5f - startY) * enter
            val rx = 3.5f + 4f * flatten
            val ry = 4.4f - 3.1f * flatten
            oval(c, x - rx, y - ry, x + rx, y + ry, 0xffe6e3c9, teal)
            ink(teal)
            paint.alpha = (255f * (1f - flatten)).toInt()
            c.drawCircle(x, y, 1.45f, paint)
        }
    }

    private fun drawPlateLandmarks(c: Canvas, slide: Float, step: Int, t: Float) {
        c.save()
        c.clipPath(plate)
        for (i in 0..2) {
            val x = 168f + 45f * i + slide
            val color = if (step == 4 && i < 2) 0xffb4a1a1 else teal
            line(c, x - 1.6f, plateY(x) + 2.5f, x + 1.6f, plateY(x) + 8.5f, color, 2.3f)
        }
        c.restore()
        if (step == 3) {
            val offset = 11f * ease(t)
            arrow(c, 251f + offset, 140f, 271f + offset, 140f, teal)
        }
    }

    private fun band(c: Canvas, from: Float, to: Float, offset: Float, width: Float, color: Long) {
        work.rewind()
        work.moveTo(from, plateY(from) + offset)
        plateArc(work, from, to, offset)
        stroke(c, work, color, width)
    }

    private fun callout(
        c: Canvas, id: Int, x: Float, y: Float, elbowX: Float, elbowY: Float, anchorX: Float, anchorY: Float,
    ) {
        val start = y + if (elbowY < y) -15f else 5f
        line(c, x, start, elbowX, elbowY, leader, 1.15f)
        line(c, elbowX, elbowY, anchorX, anchorY, leader, 1.15f)
        disc(c, anchorX, anchorY, 2f, leader, cream)
        label(c, id, x, y, 118f)
    }

    private fun plateY(x: Float): Float {
        val d = x - 206f
        return 154f + CURVE * d * d
    }

    // The same parabolic arc locates both the stationary bed and the sliding plate landmarks.
    private fun plateArc(path: Path, from: Float, to: Float, offset: Float) {
        val half = (to - from) / 2f
        val middle = from + half
        path.quadTo(middle, plateY(middle) - CURVE * half * half + offset, to, plateY(to) + offset)
    }

    private fun ease(t: Float): Float {
        val f = t.coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }

    private companion object {
        const val CURVE = .0011f
        const val ROOT_X = 126f
        const val MATRIX_END = 161f
        const val BED_END = 274f
        const val THICKNESS = 10f
    }
}
