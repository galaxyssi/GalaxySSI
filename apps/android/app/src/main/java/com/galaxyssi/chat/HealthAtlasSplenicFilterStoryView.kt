package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.RectF
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasSplenicFilterStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.SPLENIC_FILTER) {
    private val rose = 0xffa35669
    private val plum = 0xff80475e
    private val sinusEdge = 0xff67988e
    private val fiber = 0xffeac3b5
    private val leader = 0xff627a77
    private val ironInk = 0xff97632d
    private val pulpFill = shade(30f, 110f, 0xfff2a9a7, 0xffbd7188)
    private val cordFill = shade(141f, 311f, 0xfffff1e7, 0xfff6d9d0)
    private val sinusFill = shade(141f, 311f, 0xfff0faf4, 0xffcfe9e2)
    private val wallFill = shade(0f, 18f, 0xffb9dbcf, 0xff8ebbb0)
    private val macrophageFill = shade(226f, 300f, 0xffeddfb7, 0xffd9b680)
    private val redFill = shade(-14f, 14f, 0xffffb0ab, 0xffd56c79)
    private val mutedFill = shade(-14f, 14f, 0xffe8a8b5, 0xffad627d)
    private val dimple = shade(-7f, 6f, 0xffc77784, 0xfff1a8aa)
    private val field = RectF(24f, 141f, 336f, 311f)
    private val fieldClip = Path().apply { addRoundRect(field, 17f, 17f, Path.Direction.CW) }
    private val spleen = Path().apply {
        moveTo(31f, 85f)
        cubicTo(23f, 65f, 41f, 36f, 67f, 28f)
        cubicTo(87f, 22f, 110f, 30f, 116f, 41f)
        cubicTo(121f, 52f, 107f, 56f, 100f, 63f)
        cubicTo(92f, 71f, 100f, 77f, 93f, 86f)
        cubicTo(81f, 104f, 42f, 110f, 31f, 85f)
        close()
    }
    private val approach = track(Path().apply {
        moveTo(61f, 192f)
        cubicTo(86f, 194f, 103f, 211f, 128f, SLIT_Y)
    })
    private val sinusRun = track(Path().apply {
        moveTo(228f, SLIT_Y)
        cubicTo(258f, 211f, 278f, 196f, 328f, 203f)
    })
    private val reuseRun = track(Path().apply {
        moveTo(109f, 259f)
        cubicTo(137f, 265f, 160f, 271f, 207f, 271f)
        cubicTo(248f, 271f, 263f, 253f, 315f, 252f)
    })
    private val wallSegments = floatArrayOf(139f, 164f, 172f, 203f, 217f, 264f, 278f, 313f)
    private val cellOutline = Path()
    private val cellMembrane = Path()

    init { tag = "atlas-function-splenic-filter-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        locator(c, step, t)
        c.save()
        c.clipPath(fieldClip)
        anatomy(c)
        if (step != 1) {
            at(sinusRun, .32f + .51f * t) { x, y -> redCell(c, x, y - 5f, .60f, -10f) }
        }

        when (step) {
            0 -> {
                macrophage(c, 0f)
                at(approach, ease(t)) { x, y -> redCell(c, x, y, 1f, 12f * (1f - t)) }
            }
            1 -> {
                macrophage(c, 0f)
                passingCell(c, mix(128f, 307f, ease(t)))
            }
            2 -> {
                macrophage(c, 0f)
                val f = ease(t / .67f)
                redCell(c, mix(116f, RETAINED_X, f), SLIT_Y - 10f * (1f - f), .96f,
                    mix(-13f, 0f, f), lessFlexible = true)
            }
            3 -> engulf(c, t)
            else -> recycle(c, t)
        }
        c.restore()
        ink(sinusEdge, 1.3f)
        c.drawRoundRect(field, 17f, 17f, paint)
        callouts(c, step)
    }

    private fun locator(c: Canvas, step: Int, t: Float) {
        ink(cream)
        paint.shader = pulpFill
        c.drawPath(spleen, paint)
        paint.shader = null
        stroke(c, spleen, plum, 1.6f)
        oval(c, 42f, 67f, 54f, 77f, 0xfff8dbcf, rose)
        oval(c, 59f, 43f, 71f, 53f, 0xfff8dbcf, rose)
        oval(c, 58f, 84f, 68f, 92f, 0xfff8dbcf, rose)
        ink(0xfff8cfbf, 1.7f)
        c.drawArc(34f, 33f, 100f, 97f, 185f, 97f, false, paint)
        val highlight = if (step == 0) 2.5f * ease(t) else 2.5f
        disc(c, 80f, 72f, 8.5f + highlight, 0xfff8c9b9, plum)
        disc(c, 80f, 72f, 2.7f, plum)
        line(c, 87f, 67f, 121f, 49f, leader, 1.15f)
        line(c, 121f, 49f, 139f, 49f, leader, 1.15f)
        line(c, 82f, 83f, 92f, 101f, leader, 1.15f)
        line(c, 92f, 101f, 151f, 101f, leader, 1.15f)
        line(c, 151f, 101f, 151f, 141f, leader, 1.15f)
        label(c, R.string.health_atlas_splenic_filter_story_label_spleen, 57f, 113f, 57f)
        label(c, R.string.health_atlas_splenic_filter_story_label_red_pulp, 178f, 53f, 70f)
    }

    private fun anatomy(c: Canvas) {
        ink(cream)
        paint.shader = cordFill
        c.drawRect(24f, 141f, WALL_LEFT, 311f, paint)
        paint.shader = sinusFill
        c.drawRect(WALL_LEFT, 141f, 336f, 311f, paint)
        paint.shader = null
        for (i in 0..3) {
            val y = 155f + 43f * i
            line(c, 24f, y, 50f, y + 15f, fiber, 1.25f)
            line(c, 50f, y + 15f, 87f, y + 7f, fiber, 1.25f)
            line(c, 50f, y + 15f, 74f, y + 37f, fiber, 1.25f)
            disc(c, 50f, y + 15f, 2.2f, fiber)
        }
        for (i in 0..2) {
            val x = 116f + 31f * i
            line(c, x, 146f, x + 15f, 172f, fiber, 1.25f)
            line(c, x + 15f, 172f, x - 3f, 187f, fiber, 1.25f)
            disc(c, x + 15f, 172f, 2.2f, fiber)
        }
        for (i in 0 until wallSegments.size step 2) {
            val top = wallSegments[i]
            val bottom = wallSegments[i + 1]
            c.save()
            c.translate(WALL_LEFT, top)
            c.rotate(-90f)
            ink(cream)
            paint.shader = wallFill
            c.drawRoundRect(top - bottom, 0f, 0f, WALL_RIGHT - WALL_LEFT, 5f, 5f, paint)
            paint.shader = null
            ink(sinusEdge, 1.2f)
            c.drawRoundRect(top - bottom, 0f, 0f, WALL_RIGHT - WALL_LEFT, 5f, 5f, paint)
            c.restore()
            val cy = (top + bottom) / 2f
            oval(c, 203f, cy - 6f, 211f, cy + 6f, 0xff80afa3, sinusEdge)
        }
        for (i in 0..2) {
            val y = 233f + 29f * i
            line(c, 244f + 15f * i, y, 264f + 15f * i, y, 0xffb9d8cf, 1.2f)
            line(c, 297f + 7f * i, y, 310f + 7f * i, y, 0xffb9d8cf, 1.2f)
        }
    }

    private fun callouts(c: Canvas, step: Int) {
        label(c, R.string.health_atlas_splenic_filter_story_label_cord, 87f, 132f, 120f)
        label(c, R.string.health_atlas_splenic_filter_story_label_sinus, 266f, 132f, 128f)
        line(c, 210f, 203f, 233f, 177f, leader, 1.1f)
        line(c, 233f, 177f, 260f, 177f, leader, 1.1f)
        disc(c, 210f, 203f, 1.8f, leader)
        label(c, R.string.health_atlas_splenic_filter_story_label_slit, 274f, 170f, 100f)
        line(c, 91f, 289f, 91f, 320f, leader, 1.1f)
        disc(c, 91f, 289f, 2f, leader)
        label(c, R.string.health_atlas_splenic_filter_story_label_macrophage, 108f, 337f, 165f)
        when (step) {
            0, 1 -> {
                redCell(c, 208f, 333f, .36f, 0f)
                label(c, R.string.health_atlas_splenic_filter_story_label_red_cell, 277f, 337f, 115f)
            }
            2, 3 -> {
                redCell(c, 208f, 333f, .36f, 0f, lessFlexible = true)
                label(c, R.string.health_atlas_splenic_filter_story_label_less_flexible, 277f, 337f, 115f)
            }
            else -> {
                iron(c, 208f, 333f, 1f)
                label(c, R.string.health_atlas_splenic_filter_story_label_iron, 277f, 337f, 115f)
            }
        }
    }

    private fun passingCell(c: Canvas, x: Float) {
        val pinch = ease(1f - abs(x - 207f) / 41f)
        if (pinch == 0f) {
            redCell(c, x, SLIT_Y, 1f, 0f)
            return
        }

        c.save()
        c.translate(x, SLIT_Y)
        cellOutline.rewind()
        val reach = mix(22f, 33f, pinch)
        // The neck follows the opening while the two ends relax on either side.
        for (i in 0 until 64) {
            val angle = 2f * PI.toFloat() * i / 64f
            val dx = reach * cos(angle)
            val px = x + dx
            val fromWall = maxOf(WALL_LEFT - px, px - WALL_RIGHT, 0f)
            val height = mix(5f, 13f, ease(fromWall / 13f))
            val dy = height * sin(angle)
            if (i == 0) cellOutline.moveTo(dx, dy) else cellOutline.lineTo(dx, dy)
        }
        cellOutline.close()
        ink(cream)
        paint.shader = redFill
        c.drawPath(cellOutline, paint)
        paint.shader = null
        stroke(c, cellOutline, rose, 1.3f)
        val centerHeight = mix(1.9f, 5.5f, ease(maxOf(WALL_LEFT - x, x - WALL_RIGHT, 0f) / 13f))
        oval(c, -10f, -centerHeight, 10f, centerHeight, dimple, 0xffd48e94)
        c.restore()
    }

    private fun engulf(c: Canvas, t: Float) {
        val f = ease(t)
        val extension = ease(t / .48f) * (1f - ease((t - .56f) / .44f))
        val x = mix(RETAINED_X, 109f, f)
        val y = mix(SLIT_Y, 259f, ease(t / .82f))
        macrophage(c, extension)
        redCell(c, x, y, mix(.96f, .85f, f), -18f * f, lessFlexible = true)
        if (t > .43f) {
            ink(0xfff5e5bd, 2.5f)
            val spread = (1f - f) * 5f
            c.drawArc(x - 22f - spread, y - 14f - spread, x + 22f + spread, y + 14f + spread,
                100f, 360f * ease((t - .43f) / .57f), false, paint)
        }
    }

    private fun recycle(c: Canvas, t: Float) {
        macrophage(c, 0f)
        val breakdown = ease(t / .30f)
        if (breakdown < 1f) {
            redCell(c, 109f, 259f, .85f * (1f - breakdown), -18f, lessFlexible = true)
            ink(0xfff5e5bd, 2.5f * (1f - breakdown))
            c.drawOval(87f + 14f * breakdown, 245f + 8f * breakdown,
                131f - 14f * breakdown, 273f - 8f * breakdown, paint)
        }
        for (i in 0..2) {
            val f = ease((t - .14f - .08f * i) / .67f)
            val size = ease((t - .14f - .08f * i) / .16f)
            if (size > 0f) at(reuseRun, f * (1f - .10f * i)) { x, y -> iron(c, x, y, size) }
        }
    }

    private fun macrophage(c: Canvas, extension: Float) {
        cellMembrane.rewind()
        cellMembrane.apply {
            moveTo(59f, 271f)
            cubicTo(56f, 252f, 69f, 249f, 76f, 241f)
            cubicTo(82f, 231f, 97f, 224f, 111f, 232f)
            cubicTo(126f, 242f - 10f * extension, 141f + 17f * extension, 234f - 9f * extension,
                145f + 20f * extension, 245f - 7f * extension)
            cubicTo(146f + 18f * extension, 251f - 5f * extension, 133f, 252f, 134f, 258f)
            cubicTo(135f, 266f, 146f + 15f * extension, 259f + 7f * extension,
                148f + 17f * extension, 269f + 6f * extension)
            cubicTo(150f, 284f, 131f, 280f, 125f, 289f)
            cubicTo(115f, 301f, 102f, 300f, 92f, 295f)
            cubicTo(79f, 289f, 61f, 295f, 59f, 271f)
            close()
        }
        ink(cream)
        paint.shader = macrophageFill
        c.drawPath(cellMembrane, paint)
        paint.shader = null
        stroke(c, cellMembrane, ironInk, 1.5f)
        oval(c, 72f, 254f, 93f, 275f, 0xffb79ab1, plum)
        disc(c, 80f, 261f, 2.7f, plum)
        disc(c, 113f, 280f, 3.2f, 0xffe9ca93, ironInk)
        disc(c, 122f, 273f, 2.4f, 0xffedd5a5, ironInk)
    }

    private fun redCell(c: Canvas, x: Float, y: Float, scale: Float, angle: Float, lessFlexible: Boolean = false) {
        c.save()
        c.translate(x, y)
        c.rotate(angle)
        c.scale(scale, scale)
        val halfHeight = if (lessFlexible) 14f else 13f
        oval(c, -22f, -halfHeight, 22f, halfHeight, if (lessFlexible) mutedFill else redFill,
            if (lessFlexible) plum else rose)
        oval(c, -10f, -5.5f, 10f, 5.5f, dimple, 0xffcb8090)
        ink(0xffffc7be, 1.4f)
        c.drawArc(-18f, -10f, 18f, 10f, 196f, 119f, false, paint)
        c.restore()
    }

    private fun iron(c: Canvas, x: Float, y: Float, scale: Float) {
        disc(c, x, y, 5f * scale, 0xfff3cd7d, ironInk)
        disc(c, x - 1f * scale, y - 1f * scale, 1.5f * scale, 0xffffefd1)
    }

    private fun mix(a: Float, b: Float, f: Float) = a + (b - a) * f

    private fun ease(value: Float): Float {
        val f = value.coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }

    private companion object {
        const val WALL_LEFT = 198f
        const val WALL_RIGHT = 216f
        const val SLIT_Y = 210f
        const val RETAINED_X = WALL_LEFT - 22f
    }
}
