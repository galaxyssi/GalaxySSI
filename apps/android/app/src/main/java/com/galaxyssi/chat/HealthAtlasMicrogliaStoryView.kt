package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import kotlin.math.hypot

internal class HealthAtlasMicrogliaStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.MICROGLIA_SURVEILLANCE) {
    private val paper = shade(6f, 354f, 0xffeef3fa, 0xffe2f0ea)
    private val cellFill = shade(149f, 195f, 0xffcce9dd, 0xff7db8aa)
    private val brainFill = shade(-28f, 32f, 0xffddd9eb, 0xffaea8c9)
    private val arborEdge = 0xff36786c
    private val arborLight = 0xff83c2b1
    private val nerve = 0xff8e86ad
    private val debrisInk = 0xff9b6458
    private val path = Path()
    private val field = Path().apply { addRoundRect(1f, 1f, 359f, 359f, 8f, 8f, Path.Direction.CW) }
    private val soma = Path().apply {
        moveTo(125f, 170f)
        cubicTo(131f, 159f, 138f, 153f, 153f, 154f)
        cubicTo(164f, 153f, 179f, 161f, 181f, 169f)
        cubicTo(183f, 178f, 172f, 188f, 157f, 191f)
        cubicTo(142f, 195f, 119f, 184f, 125f, 170f)
        close()
    }
    private val neuron = Path().apply {
        moveTo(-29f, -24f)
        cubicTo(-16f, -15f, -10f, -28f, 9f, -26f)
        cubicTo(28f, -25f, 30f, -9f, 49f, -15f)
        cubicTo(34f, -3f, 25f, 3f, 25f, 15f)
        cubicTo(30f, 32f, 41f, 34f, 52f, 43f)
        cubicTo(32f, 39f, 25f, 24f, 9f, 24f)
        cubicTo(-12f, 24f, -16f, 13f, -33f, 21f)
        cubicTo(-19f, 8f, -20f, -9f, -29f, -24f)
        close()
    }
    private val neuropil = listOf(
        Path().apply { moveTo(0f, 112f); cubicTo(39f, 133f, 31f, 188f, 0f, 222f) },
        Path().apply { moveTo(43f, 0f); cubicTo(19f, 41f, 91f, 48f, 117f, 24f); quadTo(136f, 9f, 160f, 4f) },
        Path().apply { moveTo(64f, 0f); cubicTo(45f, 47f, 136f, 31f, 145f, 81f) },
        Path().apply { moveTo(0f, 241f); cubicTo(40f, 224f, 49f, 249f, 72f, 280f); quadTo(99f, 312f, 137f, 325f) },
        Path().apply { moveTo(182f, 355f); cubicTo(207f, 304f, 185f, 277f, 152f, 263f); quadTo(128f, 252f, 131f, 230f) },
        Path().apply { moveTo(356f, 75f); cubicTo(307f, 52f, 302f, 113f, 259f, 99f); quadTo(242f, 93f, 232f, 73f) },
        Path().apply { moveTo(356f, 190f); cubicTo(331f, 161f, 295f, 180f, 284f, 208f); quadTo(275f, 230f, 243f, 239f) },
        Path().apply { moveTo(356f, 268f); cubicTo(322f, 251f, 307f, 287f, 314f, 329f); quadTo(316f, 346f, 307f, 356f) },
    )

    override fun scene(c: Canvas, step: Int, t: Float) {
        ink(0xffffffff); paint.shader = paper
        c.drawPath(field, paint)
        paint.shader = null
        c.save()
        c.clipPath(field)
        val close = step == 3
        val scale = if (close) 1.55f else 1f
        val offsetX = if (close) -138f else 0f
        val offsetY = if (close) -80f else 0f
        c.translate(offsetX, offsetY)
        c.scale(scale, scale)
        for ((i, fiber) in neuropil.withIndex()) {
            stroke(c, fiber, if (i % 2 == 0) 0x509490b5 else 0x4091b8ae, 5f)
            stroke(c, fiber, 0x99f8fafc, 1.2f)
        }
        for (i in 0..45) {
            val x = 18f + (i * 73 % 328)
            val y = 18f + (i * 57 % 319)
            disc(c, x, y, if (i % 5 == 0) 2.3f else 1.25f, 0x5796aab6)
        }
        neuron(c, 59f, 93f, .94f, -18f)
        neuron(c, 281f, 285f, 1.05f, 165f)
        if (step == 0) {
            neuron(c, 287f, 77f, .64f, 16f)
            c.save()
            c.translate(286f, 217f); c.rotate(151f); c.scale(.48f, .48f); c.translate(-153f, -172f)
            arbor(c, 0, t + .31f)
            c.restore()
        }

        arbor(c, step, t)
        when (step) {
            2 -> fragments(c, 263f, 150f, 1f)
            3 -> {
                val closure = ease(t, .24f, .77f)
                pocket(c, 263f, 150f, closure)
                fragments(c, 263f, 150f, 1f)
            }
            4 -> digestion(c, t)
        }
        c.restore()
        when (step) {
            0 -> {
                callout(c, R.string.health_atlas_microglia_story_neuron, 68f, 38f, 108f, 63f, 91f, nerve)
                callout(c, R.string.health_atlas_microglia_story_soma, 101f, 298f, 166f, 142f, 185f, arborEdge)
            }
            1 -> callout(c, R.string.health_atlas_microglia_story_process, 237f, 45f, 184f, 183f, 116f, arborEdge)
            2 -> callout(c, R.string.health_atlas_microglia_story_debris, 270f, 68f, 154f, 261f, 146f, debrisInk)
            3 -> callout(c, R.string.health_atlas_microglia_story_pouch, 273f, 68f, 155f,
                offsetX + 247f * scale, offsetY + 151f * scale, arborEdge)
            4 -> callout(c, R.string.health_atlas_microglia_story_pouch, 270f, 37f, 161f, 270f, 68f, arborEdge)
        }
    }

    private fun neuron(c: Canvas, x: Float, y: Float, size: Float, angle: Float) {
        c.save()
        c.translate(x, y); c.rotate(angle); c.scale(size, size)
        ink(0xffffffff); paint.shader = brainFill; c.drawPath(neuron, paint); paint.shader = null
        stroke(c, neuron, nerve, 1.2f)
        oval(c, -15f, -12f, 15f, 11f, 0xffada6c9, nerve)
        disc(c, 2f, -1f, 3.6f, 0xff82729d)
        for (i in -1..1) line(c, -10f + 6f * i, 15f, -7f + 6f * i, 14f, 0xffe5e1f0, 1.9f)
        c.restore()
    }

    private fun arbor(c: Canvas, step: Int, t: Float) {
        val reach = when (step) {
            2 -> ease(t, .08f, .88f)
            3, 4 -> 1f
            else -> 0f
        }
        val cycle = if (step == 1) 1.55f * t else t
        val motion = when (step) {
            1 -> 1f
            2, 3 -> .28f
            else -> .58f
        }
        val a = motion * wave(cycle)
        val b = motion * wave(cycle + .31f)
        val d = motion * wave(cycle + .62f)
        // Proximal forks stay fixed; the terminal segments change length and direction.
        branch(c, 135f, 168f, 105f, 133f, 101f, 143f, 5.5f, 3f)
        branch(c, 101f, 143f, 78f, 141f, 54f + 12f * a, 159f - 7f * a, 3.1f, .9f)
        branch(c, 77.75f + 3f * a, 146f - 1.75f * a, 67f, 142f, 51f + 7f * b, 129f + 5f * b, 1.8f, .7f)
        branch(c, 101f, 143f, 89f, 117f, 102f + 5f * b, 99f - 14f * b, 3f, .8f)
        branch(c, 95.25f + 1.25f * b, 119f - 3.5f * b, 83f, 117f, 80f + 4f * d, 98f - 7f * d, 1.6f, .65f)

        branch(c, 155f, 162f, 148f, 129f, 159f, 121f, 5.6f, 2.7f)
        branch(c, 159f, 121f, 151f, 95f, 137f + 4f * d, 78f + 10f * d, 2.8f, .85f)
        branch(c, 149.5f + d, 97.25f + 2.5f * d, 149f, 84f, 159f - 6f * a, 67f - 8f * a, 1.8f, .65f)
        branch(c, 159f, 121f, 170f, 119f, 183f, 116f, 2.7f, 2f)
        branch(c, 183f, 116f, 197f, 108f, 201f + 9f * a, 89f - 10f * a, 2f, .75f)
        branch(c, 183f, 116f, 206f, 115f, 220f + 10f * b, 100f + 8f * b, 2.1f, .75f)

        branch(c, 171f, 169f, 200f, 155f, 212f, 159f, 5.8f, 3.3f)
        branch(c, 212f, 159f, 225f, 150f, 228f + 25f * reach + 5f * b * (1f - reach),
            133f + 17f * reach - 10f * a * (1f - reach), 3.3f, 1.45f)
        branch(c, 212f, 159f, 226f, 167f, 243f + 8f * a, 176f + 8f * a, 2.7f, .8f)
        branch(c, 226.75f + 2f * a, 167.25f + 2f * a, 239f, 163f, 247f + 6f * d, 169f + 6f * d, 1.45f, .6f)

        branch(c, 153f, 184f, 164f, 208f, 158f, 225f, 5.7f, 2.65f)
        branch(c, 158f, 225f, 161f, 248f, 177f + 7f * b, 267f + 8f * b, 2.7f, .8f)
        branch(c, 158f, 225f, 141f, 238f, 142f - 9f * d, 258f + 7f * d, 2.4f, .7f)
        branch(c, 168.1f + 3.24f * b, 254.4f + 3.7f * b, 185f, 250f, 199f + 10f * b, 261f + 7f * b, 1.5f, .6f)
        branch(c, 135f, 181f, 114f, 206f, 95f, 209f, 4.5f, 2.55f)
        branch(c, 95f, 209f, 73f, 202f, 54f - 9f * b, 212f + 8f * b, 2.55f, .8f)
        branch(c, 95f, 209f, 89f, 221f, 79f + 7f * a, 241f + 8f * a, 2.4f, .75f)
        branch(c, 87.2f + 2.1f * a, 224.6f + 2.42f * a, 104f, 231f, 103f + 5f * d, 249f + 6f * d, 1.55f, .6f)

        ink(0xffffffff); paint.shader = cellFill; c.drawPath(soma, paint); paint.shader = null
        stroke(c, soma, arborEdge, 1.2f)
        c.save()
        c.rotate(-14f, 151f, 173f)
        oval(c, 134f, 163f, 164f, 182f, 0xff8792b6, 0xff565f87)
        oval(c, 141f, 166f, 153f, 174f, 0xffacb5d0, 0xff939ec0)
        disc(c, 155f, 174f, 2.6f, 0xff60678d)
        c.restore()
        disc(c, 169f, 174f, 2.1f, 0xffdcf2e8)
        disc(c, 157f, 184f, 1.5f, 0xffe7f6ef)
    }

    private fun branch(c: Canvas, x: Float, y: Float, cx: Float, cy: Float,
        endX: Float, endY: Float, base: Float, tip: Float) {
        val dx = endX - x
        val dy = endY - y
        val length = hypot(dx, dy)
        val nx = -dy / length
        val ny = dx / length
        path.rewind()
        path.moveTo(x + nx * base / 2f, y + ny * base / 2f)
        path.quadTo(cx + nx * base / 2f, cy + ny * base / 2f, endX + nx * tip / 2f, endY + ny * tip / 2f)
        path.lineTo(endX - nx * tip / 2f, endY - ny * tip / 2f)
        path.quadTo(cx - nx * base / 2f, cy - ny * base / 2f, x - nx * base / 2f, y - ny * base / 2f)
        path.close()
        ink(arborLight); c.drawPath(path, paint)
        stroke(c, path, arborEdge, .85f)
    }

    private fun pocket(c: Canvas, x: Float, y: Float, closure: Float) {
        if (closure >= .98f) {
            oval(c, x - 19f, y - 14f, x + 17f, y + 14f, 0xffc1e0d3, arborEdge)
            return
        }
        val rimX = x - 13f + 30f * closure
        val gap = 11f - 9f * closure
        path.rewind()
        path.moveTo(rimX, y - gap)
        path.cubicTo(x - 17f, y - 16f, x - 20f, y - 10f, x - 15f, y + 4f)
        path.cubicTo(x - 14f, y + 14f, x + 1f, y + 16f, rimX, y + gap)
        stroke(c, path, arborEdge, 4.8f)
        stroke(c, path, arborLight, 2.7f)
    }

    private fun fragments(c: Canvas, x: Float, y: Float, scale: Float) {
        c.save(); c.translate(x, y); c.scale(scale, scale)
        oval(c, -8f, -6f, 3f, 4f, 0xffe8bdaf, debrisInk)
        disc(c, 5f, 4f, 2.8f, 0xffe7ae9e, debrisInk)
        disc(c, 6f, -4f, 1.9f, 0xffb67b74)
        c.restore()
    }

    private fun digestion(c: Canvas, t: Float) {
        pocket(c, 263f, 150f, 1f)
        line(c, 276f, 139f, 285f, 119f, arborEdge, 1.25f)
        disc(c, 270f, 88f, 38f, 0xfff7fbfa, arborEdge)
        oval(c, 243f, 68f, 297f, 108f, 0xffc8e4d8, arborEdge)
        val remain = 1f - ease(t, .15f, .88f)
        if (remain > .04f) {
            fragments(c, 268f, 87f, remain * 1.45f)
            fragments(c, 263f, 150f, remain)
        }
        for (i in 0..4) {
            val x = 254f + 8f * i + 1.3f * wave(t + i * .22f)
            val y = 86f + (1f - remain) * (i % 3 - 1) * 11f
            disc(c, x, y, 1.65f, 0xff729e9f)
        }
    }

    private fun callout(c: Canvas, id: Int, x: Float, y: Float, width: Float,
        tx: Float, ty: Float, color: Long) {
        val fromY = y + if (ty > y) 5f else -14f
        line(c, x, fromY, tx, ty, color, 1.15f)
        disc(c, tx, ty, 2.4f, 0xfff7fbfa, color)
        label(c, id, x, y, width)
    }

    private fun ease(t: Float, start: Float, end: Float): Float {
        val f = ((t - start) / (end - start)).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }

    init { tag = "atlas-function-microglia-surveillance-art" }
}
