package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import androidx.annotation.StringRes

internal class HealthAtlasMelaninStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.MELANIN_TRANSFER) {
    private data class Point(val x: Float, val y: Float)
    private data class Cell(val x: Float, val y: Float, val rx: Float, val ry: Float)

    private val tissue = shade(104f, 284f, 0xffffeedc, 0xffeecac1)
    private val cellFill = shade(122f, 282f, 0xffffe9d8, 0xfff0bfb8)
    private val recipientFill = shade(142f, 220f, 0xffffedde, 0xfff2c3a8)
    private val donorFill = shade(227f, 282f, 0xffcef0dd, 0xffa5d3c6)
    private val membrane = 0xff548e83
    private val branchFill = 0xffbde4d2
    private val pigment = 0xff774723
    private val leader = 0xff635c69
    private val path = Path()
    private val cells = arrayOf(
        Cell(56f, 137f, 29f, 13f), Cell(115f, 135f, 28f, 12f), Cell(177f, 134f, 31f, 12f),
        Cell(246f, 133f, 33f, 11f), Cell(307f, 137f, 25f, 13f),
        Cell(53f, 173f, 27f, 22f), Cell(109f, 169f, 25f, 21f), Cell(172f, 169f, 29f, 24f),
        Cell(308f, 176f, 25f, 24f), Cell(49f, 220f, 23f, 22f), Cell(111f, 207f, 24f, 18f),
        Cell(312f, 224f, 21f, 22f), Cell(52f, 263f, 27f, 19f),
        Cell(205f, 258f, 28f, 24f), Cell(260f, 253f, 26f, 29f), Cell(309f, 265f, 24f, 17f),
    )
    private val recipient = Path().apply {
        moveTo(240f, 142f)
        cubicTo(263f, 141f, 279f, 153f, 280f, 172f)
        cubicTo(282f, 188f, 276f, 207f, 263f, 215f)
        cubicTo(247f, 224f, 225f, 219f, 211f, 209f)
        cubicTo(202f, 202f, 202f, 189f, 204f, 176f)
        cubicTo(203f, 157f, 219f, 143f, 240f, 142f)
        close()
    }
    private val donor = Path().apply {
        moveTo(94f, 265f)
        cubicTo(92f, 248f, 113f, 228f, 132f, 228f)
        cubicTo(151f, 224f, 166f, 238f, 169f, 253f)
        cubicTo(176f, 272f, 154f, 281f, 134f, 281f)
        cubicTo(115f, 282f, 97f, 279f, 94f, 265f)
        close()
    }
    private val tip = Point(197f, 200f)
    private val branches = arrayOf(
        Path().apply {
            moveTo(145f, 242f)
            cubicTo(169f, 239f, 172f, 208f, tip.x, tip.y)
        },
        Path().apply {
            moveTo(111f, 250f)
            cubicTo(87f, 244f, 83f, 217f, 79f, 192f)
        },
        Path().apply {
            moveTo(132f, 238f)
            cubicTo(145f, 227f, 135f, 211f, 144f, 190f)
        },
    )
    private val branchTracks = branches.map { track(it) }
    private val storage = arrayOf(
        Point(106f, 256f), Point(111f, 266f), Point(143f, 270f),
        Point(114f, 244f), Point(126f, 235f), Point(139f, 237f), Point(155f, 248f),
    )
    private val arrivals = arrayOf(Point(219f, 198f), Point(218f, 187f), Point(222f, 177f))
    private val transferTracks = arrivals.map { target ->
        track(Path().apply {
            moveTo(tip.x, tip.y)
            cubicTo(206f, 197f, 213f, target.y + 3f, target.x, target.y)
        })
    }
    private val residentPigment = arrayOf(Point(247f, 153f), Point(267f, 171f), Point(268f, 193f))
    private val capTracks = (arrivals + residentPigment.take(2)).mapIndexed { index, start ->
        val endX = floatArrayOf(228f, 236f, 243f, 251f, 259f)[index]
        val endY = floatArrayOf(168f, 163f, 162f, 163f, 168f)[index]
        track(Path().apply {
            moveTo(start.x, start.y)
            val guideX = if (index < 3) 216f + 3f * index else start.x
            cubicTo(guideX, endY + 4f, guideX, endY - 3f, endX, endY)
        })
    }

    init { tag = "atlas-function-melanin-transfer-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        drawTissue(c, if (step == 0) t else null)
        if (step < 4) {
            residentPigment.forEach { core(c, it.x, it.y, .73f) }
        }
        when (step) {
            0 -> drawStorage(c, 0f, 3)
            1 -> drawStorage(c, t, storage.size)
            2 -> {
                drawStorage(c, 1f, 3)
                drawDendriteCargo(c, t)
            }
            3 -> {
                drawStorage(c, 1f, 3)
                drawDendriteCargo(c, 1f, sideBranchesOnly = true)
                drawTransfer(c, t)
            }
            4 -> {
                drawStorage(c, 1f, 3)
                drawDendriteCargo(c, 1f, sideBranchesOnly = true)
                drawCap(c, t)
            }
        }
        drawLabels(c, step)
    }

    private fun drawTissue(c: Canvas, focus: Float?) {
        rounded(c, 24f, 272f, 336f, 302f, 10f, 0xffddd9e6)
        ink(cream)
        paint.shader = tissue
        c.drawRoundRect(24f, 105f, 336f, 284f, 9f, 9f, paint)
        paint.shader = null
        for (row in 0..1) for (col in 0..6) {
            val x = 27f + col * 46f + row * 10f
            val y = 105f + row * 9f
            val right = minOf(x + 42f, 333f)
            rounded(c, x, y, right, y + 7f, 3.5f, if ((row + col) % 2 == 0) sand else 0xfff6dbb1)
            line(c, x + 3f, y + 2f, right - 3f, y + 2f, cream, 1f)
        }
        cells.forEachIndexed { index, cell ->
            wafer(cell)
            ink(cream)
            paint.shader = cellFill
            c.drawPath(path, paint)
            paint.shader = null
            stroke(c, path, 0xffc78e90, 1.1f)
            val nx = cell.x + if (index % 2 == 0) -3f else 3f
            oval(c, nx - cell.rx * .28f, cell.y - cell.ry * .30f, nx + cell.rx * .28f,
                cell.y + cell.ry * .40f, 0xffd1abd0, 0xffad85b1)
        }
        ink(cream)
        paint.shader = recipientFill
        c.drawPath(recipient, paint)
        paint.shader = null
        stroke(c, recipient, 0xffbb7d82, 1.7f)
        nucleus(c, 242f, 186f, 14f, 12f)

        if (focus != null) {
            ink(teal, 21f)
            paint.alpha = (31f + 22f * wave(focus - .25f)).toInt()
            c.drawPath(donor, paint)
            branches.forEach { c.drawPath(it, paint) }
        }
        branches.forEachIndexed { index, branch ->
            val width = if (index == 0) 11f else 8f
            stroke(c, branch, membrane, width)
            stroke(c, branch, branchFill, width - 2.5f)
        }
        ink(cream)
        paint.shader = donorFill
        c.drawPath(donor, paint)
        paint.shader = null
        stroke(c, donor, membrane, 1.5f)
        nucleus(c, 128f, 258f, 12f, 10f)
        line(c, 30f, 285f, 330f, 285f, 0xff9c8099, 2f)
        line(c, 32f, 289f, 328f, 289f, 0xfff5edf1, 1.2f)
    }

    private fun wafer(cell: Cell) {
        val (x, y, rx, ry) = cell
        path.rewind()
        path.moveTo(x - rx, y)
        path.cubicTo(x - rx, y - ry * .7f, x - rx * .6f, y - ry, x + rx * .15f, y - ry)
        path.cubicTo(x + rx * .7f, y - ry, x + rx, y - ry * .5f, x + rx, y + ry * .12f)
        path.cubicTo(x + rx, y + ry * .85f, x + rx * .52f, y + ry, x - rx * .20f, y + ry)
        path.cubicTo(x - rx * .84f, y + ry, x - rx, y + ry * .5f, x - rx, y)
        path.close()
    }

    private fun nucleus(c: Canvas, x: Float, y: Float, rx: Float, ry: Float) {
        oval(c, x - rx, y - ry, x + rx, y + ry, 0xffb49ac4, 0xff876899)
        disc(c, x - 3f, y - 2f, 3.1f, 0xff9070a2)
        disc(c, x + 4f, y + 3f, 2f, 0xffe6cde0)
    }

    private fun drawStorage(c: Canvas, t: Float, count: Int) {
        for (i in 0 until count) {
            val point = storage[i]
            val fill = .22f + .78f * progress(t, i * .07f, .52f + i * .07f)
            melanosome(c, point.x, point.y, fill)
        }
    }

    private fun drawDendriteCargo(c: Canvas, t: Float, sideBranchesOnly: Boolean = false) {
        if (!sideBranchesOnly) for (i in arrivals.indices) {
            val f = progress(t, .11f * i, .69f + .13f * i)
            at(branchTracks[0], f * (.99f - .15f * i)) { x, y -> melanosome(c, x, y) }
        }
        for (i in 1..2) {
            at(branchTracks[i], .84f * progress(t, .11f * i, .95f)) { x, y -> melanosome(c, x, y) }
        }
    }

    private fun drawTransfer(c: Canvas, t: Float) {
        arrivals.indices.forEach { i ->
            val event = (t - i * .21f) / .52f
            if (event < .24f) {
                val advance = progress(event, 0f, .24f)
                val parked = .99f - .15f * i
                at(branchTracks[0], parked + (1f - parked) * advance) { x, y -> melanosome(c, x, y) }
            } else {
                val f = progress(event, .24f, 1f)
                at(transferTracks[i], f) { x, y -> core(c, x, y) }
            }
        }
    }

    private fun drawCap(c: Canvas, t: Float) {
        val dispersed = residentPigment.last()
        core(c, dispersed.x, dispersed.y, .73f)
        capTracks.forEachIndexed { i, track ->
            at(track, progress(t, .04f * i, .58f + .04f * i)) { x, y -> core(c, x, y) }
        }
        // Faint tracks continue past the cap; the animated dashes are qualitative UV cues.
        val uv = 0xff7963a7
        for (i in 0..2) {
            val x = 223f + 17f * i
            val y = 159f + if (i == 1) 2f else 7f
            val f = progress(t, .27f + .07f * i, .83f + .07f * i)
            ink(uv, 1.05f)
            paint.alpha = 43
            c.drawLine(x, 83f, x + 5f, if (i == 2) 209f else y + 16f, paint)
            val end = 83f + (if (i == 2) 122f else y - 70f) * f
            val endX = x + 5f * f
            ink(uv, 2.2f)
            paint.alpha = if (i == 2) 170 else (195f - 155f * progress(end, y - 5f, y + 9f)).toInt()
            c.drawLine(endX - .7f, (end - 12f).coerceAtLeast(80f), endX, end, paint)
        }
    }

    private fun melanosome(c: Canvas, x: Float, y: Float, amount: Float = 1f) {
        oval(c, x - 4.1f, y - 3.1f, x + 4.1f, y + 3.1f, 0xffffd99e, 0xffad794d)
        core(c, x, y, amount)
    }

    private fun core(c: Canvas, x: Float, y: Float, amount: Float = 1f) {
        val r = 1f + 1.9f * amount
        ink(pigment)
        c.drawOval(x - r, y - .73f * r, x + r, y + .73f * r, paint)
    }

    private fun drawLabels(c: Canvas, step: Int) {
        callout(c, R.string.health_atlas_melanin_story_label_surface, 77f, 72f, 77f, 105f)
        callout(c, R.string.health_atlas_melanin_story_label_keratinocyte, 282f, 72f, 279f, 167f, 294f, 143f)
        callout(c, R.string.health_atlas_melanin_story_label_melanocyte, 93f, 324f, 119f, 277f, 93f, 305f)
        callout(c, R.string.health_atlas_melanin_story_label_basement, 266f, 324f, 266f, 285f)
        val key = when (step) {
            0 -> {
                line(c, 108f, 342f, 120f, 342f, membrane, 4f)
                R.string.health_atlas_melanin_story_label_dendrite
            }
            1, 2 -> {
                melanosome(c, 114f, 342f)
                R.string.health_atlas_melanin_story_label_melanosome
            }
            3 -> {
                core(c, 114f, 342f)
                R.string.health_atlas_melanin_story_label_core
            }
            else -> {
                for (i in -1..1) core(c, 114f + i * 5f, 341f + i * i)
                R.string.health_atlas_melanin_story_label_cap
            }
        }
        label(c, key, 183f, 347f, 110f)
    }

    private fun callout(
        c: Canvas, @StringRes id: Int, x: Float, baseline: Float, ax: Float, ay: Float,
        elbowX: Float = x, elbowY: Float = (baseline + ay) / 2f,
    ) {
        label(c, id, x, baseline, 150f)
        val start = baseline + if (ay > baseline) 6f else -16f
        line(c, x, start, elbowX, elbowY, leader, 1.05f)
        line(c, elbowX, elbowY, ax, ay, leader, 1.05f)
        disc(c, ax, ay, 2f, leader, cream)
    }

    private fun progress(t: Float, start: Float, end: Float): Float {
        val f = ((t - start) / (end - start)).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }
}
