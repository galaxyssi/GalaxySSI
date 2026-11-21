package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import kotlin.math.cos

internal class HealthAtlasEpendymalStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.EPENDYMAL_FLOW) {
    private val lumenFill = shade(0f, 248f, 0xffedf6fb, 0xffc0e0ec)
    private val tissueFill = shade(246f, 355f, 0xffc4bfdc, 0xffeef0f6)
    private val cellFill = shade(191f, 277f, 0xffe6eef8, 0xffadb9d4)
    private val focusFill = shade(187f, 292f, 0xffdbf3eb, 0xff8ac6c2)
    private val membrane = 0xff647c9a
    private val cilium = 0xff3f848c
    private val flowInk = 0xff3c839e
    private val path = Path()
    private val field = Path().apply { addRoundRect(1f, 1f, 359f, 359f, 8f, 8f, Path.Direction.CW) }
    private val brainSection = Path().apply {
        moveTo(74f, 52f)
        cubicTo(53f, 35f, 24f, 56f, 24f, 83f)
        cubicTo(23f, 103f, 41f, 117f, 60f, 109f)
        quadTo(74f, 103f, 88f, 109f)
        cubicTo(107f, 117f, 125f, 103f, 124f, 83f)
        cubicTo(124f, 56f, 95f, 35f, 74f, 52f)
        close()
    }
    private val ventricularHorn = Path().apply {
        moveTo(69f, 78f)
        cubicTo(61f, 70f, 51f, 68f, 44f, 78f)
        quadTo(54f, 74f, 60f, 86f)
        cubicTo(63f, 94f, 70f, 96f, 69f, 78f)
        close()
    }
    private val bulkGuide = Path().apply {
        moveTo(27f, 124f)
        cubicTo(113f, 109f, 203f, 133f, 328f, 103f)
    }
    private val channel = Path().apply {
        moveTo(28f, 156f)
        cubicTo(106f, 131f, 204f, 164f, 331f, 135f)
    }
    private val leftChannel = Path().apply {
        moveTo(167f, 148f)
        cubicTo(126f, 134f, 76f, 137f, 29f, 156f)
    }
    private val rightChannel = Path().apply {
        moveTo(193f, 153f)
        cubicTo(233f, 166f, 290f, 158f, 331f, 137f)
    }
    private val singleRoute = track(channel)
    private val leftRoute = track(leftChannel)
    private val rightRoute = track(rightChannel)

    override fun scene(c: Canvas, step: Int, t: Float) {
        c.save()
        c.clipPath(field)
        ink(0xffffffff); paint.shader = lumenFill; c.drawPath(field, paint); paint.shader = null
        if (step != 0) stroke(c, bulkGuide, 0x65f9fdff, 2f)
        val close = step == 1
        val depth = if (close) 94f else 62f
        val top = if (close) 193f else 202f
        tissue(c, top, depth)

        val count = if (close) 5 else 7
        val left = if (close) 24f else 19f
        val width = (360f - 2f * left) / count
        for (i in -1..count) {
            val x = left + i * width
            wallCell(c, x, x + width, top, depth, i, close && i == 2)
        }
        for (i in -1..count) {
            val x = left + i * width
            val bundle = x + width / 2f
            val direction = if (step == 4 && i < 3) -1f else 1f
            // Offset the same beat along the row; the bases do not travel with the wave.
            val phase = when (step) {
                0 -> 2f * t - i * .19f
                1 -> 1.55f * t - i * .18f
                2 -> 2f * t - i * .29f
                else -> 3f * t - i * .23f
            }
            val length = when (step) {
                1 -> if (i == 2) 52f else 39f
                2 -> 41f
                else -> 31f
            }
            tuft(c, bundle, top, length, phase, direction, close && i == 2)
        }
        when (step) {
            0 -> {
                locator(c)
                callout(c, R.string.health_atlas_ependymal_story_lumen, 254f, 73f, 172f, 245f, 105f)
                callout(c, R.string.health_atlas_ependymal_story_lining, 203f, 330f, 224f, 182f, 249f)
            }
            1 -> {
                callout(c, R.string.health_atlas_ependymal_story_cilia, 179f, 104f, 166f, 180f, rim(180f, top) - 2f)
                callout(c, R.string.health_atlas_ependymal_story_apical_surface, 244f, 324f, 211f, 198f, rim(198f, top) + 2f)
            }
            2 -> {
                label(c, R.string.health_atlas_ependymal_story_wave_front, 180f, 89f, 264f)
                line(c, 180f, 97f, 180f, 131f, membrane, 1.15f)
                line(c, 60f, 131f, 300f, 131f, membrane, 1.15f)
                line(c, 60f, 131f, 60f, 138f, membrane, 1.15f)
                line(c, 300f, 131f, 300f, 138f, membrane, 1.15f)
            }
            3 -> {
                stream(c, channel, singleRoute, t, 1.4f, 6)
                callout(c, R.string.health_atlas_ependymal_story_near_wall, 167f, 93f, 230f, 164f, 147f)
            }
            4 -> {
                stream(c, leftChannel, leftRoute, t, 1.25f, 4)
                stream(c, rightChannel, rightRoute, t + .23f, 1.25f, 4)
                callout(c, R.string.health_atlas_ependymal_story_local_routes, 180f, 88f, 237f, 250f, 158f)
                line(c, 180f, 94f, 106f, 140f, membrane, 1.15f)
                disc(c, 106f, 140f, 2.3f, 0xfff3fbff, membrane)
            }
        }
        c.restore()
    }

    private fun rim(x: Float, top: Float): Float {
        val offset = x - 180f
        return top + .00063f * offset * offset - .026f * offset
    }

    private fun tissue(c: Canvas, top: Float, depth: Float) {
        path.rewind()
        path.moveTo(0f, rim(0f, top) + depth - 8f)
        path.quadTo(180f, top + depth - 48f, 360f, rim(360f, top) + depth - 8f)
        path.lineTo(360f, 360f); path.lineTo(0f, 360f); path.close()
        ink(0xffffffff); paint.shader = tissueFill; c.drawPath(path, paint); paint.shader = null
        c.save()
        c.clipPath(path)
        for (i in 0..10) {
            val x = 21f + i * 32f
            val y = rim(x, top) + depth + 17f + i % 3 * 8f
            path.rewind()
            path.moveTo(x - 36f, y + 14f)
            path.cubicTo(x - 22f, y - 10f, x + 11f, y + 9f, x + 24f, y - 9f)
            path.quadTo(x + 34f, y - 19f, x + 46f, y - 16f)
            stroke(c, path, 0x60928eaf, 4.7f)
            stroke(c, path, 0x93f2f1f8, 1.4f)
            oval(c, x - 7f, y - 3f, x + 7f, y + 3f, 0xffb6afcd, 0xffa29ab8)
        }
        c.restore()
    }

    private fun wallCell(c: Canvas, left: Float, right: Float, top: Float,
        depth: Float, index: Int, focused: Boolean) {
        val high = rim(left, top)
        val low = rim(right, top)
        val center = (left + right) / 2f
        val middleY = rim(center, top)
        path.rewind()
        path.moveTo(left, high)
        path.quadTo(center, middleY - 1.1f, right, low)
        path.cubicTo(right - 3f, low + 22f, right + 3f, low + depth - 18f, right, low + depth)
        path.quadTo(center - 2f, middleY + depth + 5f, left, high + depth)
        path.cubicTo(left + 3f, high + depth - 18f, left - 3f, high + 22f, left, high)
        path.close()
        ink(0xffffffff); paint.shader = if (focused) focusFill else cellFill; c.drawPath(path, paint); paint.shader = null
        stroke(c, path, membrane, 1.2f)
        path.rewind()
        path.moveTo(left + 3f, high + 4f)
        path.quadTo(center, middleY + 3f, right - 3f, low + 4f)
        stroke(c, path, 0xfff2f8f8, 2.2f)
        val nx = center + (index % 3 - 1) * 2f
        val ny = middleY + depth * .64f
        c.save()
        c.rotate((index % 3 - 1) * 13f, nx, ny)
        oval(c, nx - 10f, ny - 12f, nx + 10f, ny + 12f, 0xffa59fc3, 0xff73698f)
        disc(c, nx - 2f, ny + 1f, 3.1f, 0xff7f749c)
        c.restore()
        line(c, center - 9f, ny - 20f, center - 3f, ny - 22f, 0xffb6c9dc, 1.7f)
        line(c, center + 3f, ny - 24f, center + 10f, ny - 21f, 0xffb6c9dc, 1.7f)
        disc(c, right - 1f, low + 6f, 1.8f, membrane)
    }

    private fun tuft(c: Canvas, x: Float, top: Float, length: Float, phase: Float, direction: Float,
        focused: Boolean) {
        for (i in -2..2) {
            val base = x + i * 5f
            val y = rim(base, top)
            val beat = phase - i * .046f
            val sweep = wave(beat)
            val recover = (1f - cos(beat * 2f * kotlin.math.PI.toFloat())) * .5f
            val span = length - 2f * kotlin.math.abs(i)
            val tipX = base + direction * span * (.20f + .53f * sweep)
            val tipY = y - span * (1f - .38f * recover)
            path.rewind()
            path.moveTo(base, y)
            path.cubicTo(base + direction * (.16f - .32f * recover) * span, y - span * .30f,
                tipX - direction * span * .28f * recover, tipY + .14f * span, tipX, tipY)
            stroke(c, path, if (focused) 0xff266e75 else cilium, if (focused) 2.55f else 1.85f)
            disc(c, base, y + 1f, if (focused) 1.7f else 1.3f, 0xff437389)
        }
    }

    private fun stream(c: Canvas, guide: Path, route: PathMeasure, t: Float, speed: Float, beads: Int) {
        stroke(c, guide, 0x4477b9d1, 13f)
        stroke(c, guide, 0xa0eefbff, 2f)
        for (i in 0 until beads) {
            val f = (i.toFloat() / beads + speed * t) % 1f
            val size = minOf(f * 8f, (1f - f) * 8f, 1f)
            at(route, f) { x, y ->
                disc(c, x, y, (2.1f + i % 2 * .7f) * size, flowInk)
            }
        }
        at(route, .77f) { x, y ->
            at(route, .85f) { tx, ty -> arrow(c, x, y, tx, ty, flowInk) }
        }
    }

    private fun locator(c: Canvas) {
        disc(c, 74f, 83f, 56f, 0xfff7f9fd, 0xffc2cde0)
        ink(0xffd9d8ec); c.drawPath(brainSection, paint)
        stroke(c, brainSection, 0xff8d88ae, 1.1f)
        line(c, 74f, 54f, 74f, 72f, 0xff9992b3, 1.2f)
        for (mirror in 0..1) {
            c.save()
            if (mirror == 1) c.scale(-1f, 1f, 74f, 83f)
            ink(0xff70b1c6); c.drawPath(ventricularHorn, paint)
            stroke(c, ventricularHorn, flowInk, 1.1f)
            c.restore()
        }
        oval(c, 71f, 85f, 77f, 99f, 0xff70b1c6, flowInk)
        label(c, R.string.health_atlas_ependymal_story_ventricles, 74f, 156f, 135f)
        line(c, 119f, 116f, 145f, 172f, membrane, 1.1f)
        line(c, 145f, 172f, 155f, 172f, membrane, 1.1f)
    }

    private fun callout(c: Canvas, id: Int, x: Float, y: Float, width: Float, tx: Float, ty: Float) {
        val fromY = y + if (ty > y) 6f else -15f
        line(c, x, fromY, tx, ty, membrane, 1.15f)
        disc(c, tx, ty, 2.3f, 0xfff3fbff, membrane)
        label(c, id, x, y, width)
    }

    init { tag = "atlas-function-ependymal-flow-art" }
}
