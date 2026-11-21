package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

internal object HealthAtlasHomeostasisMotion {
    fun liquidRemaining(fraction: Float, humid: Boolean): Float =
        1f - HealthAtlasFunctionStory.safePhase(fraction) * (if (humid) .35f else .91f)

    fun glycogenRemaining(fraction: Float): Float = 1f - .72f * HealthAtlasFunctionStory.safePhase(fraction)
}

internal class HealthAtlasHomeostasisStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasFunctionArt(context, story) {
    private val cooling = story == HealthAtlasFunctionStory.SWEAT_COOLING
    private val paper = gradient(0f, 360f, 0xffeaf4f5, 0xfffcf1df)
    private val blood = gradient(95f, 151f, 0xfff5c8c9, 0xffdc9ba6)
    private val tissue = gradient(162f, 332f, 0xfffae4cb, 0xffe5c3ad)
    private val skin = gradient(200f, 303f, 0xffeac0b2, 0xffcc918d)
    private val field = RectF(0f, 0f, 360f, 360f)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val shape = Path()
    private val trace = Path()
    private val point = FloatArray(2)
    private val plates = mutableMapOf<Int, Drawable>()
    private val cream = 0xfffbf7e9
    private val water = 0xff3f85a4
    private val salt = 0xffa36735
    private val violet = 0xff775889
    private val gold = 0xffa87329
    private val red = 0xffaa657b
    private val teal = 0xff397a71
    private val text = 0xff22434d
    private val sweatDuct by lazy { PathMeasure(eccrineDuctPath(), false) }
    private val nerve by lazy { route {
        moveTo(63f, 234f); cubicTo(95f, 240f, 102f, 190f, 145f, 194f)
    } }
    private val alphaExit by lazy { route {
        moveTo(207f, 158f); cubicTo(220f, 182f, 224f, 211f, 216f, 231f)
        quadTo(257f, 229f, 308f, 236f)
    } }
    private val liverEntry by lazy { route {
        moveTo(40f, 205f); cubicTo(98f, 205f, 145f, 209f, 172f, 211f)
        quadTo(180f, 215f, 180f, 230f)
    } }
    private val glucoseExit by lazy { route {
        moveTo(176f, 281f); quadTo(180f, 244f, 180f, 216f)
        lineTo(180f, 128f); quadTo(206f, 115f, 266f, 121f)
        lineTo(313f, 121f)
    } }

    init { tag = if (cooling) "atlas-function-sweat-cooling-art" else "atlas-function-glucagon-response-art" }

    override fun onDraw(c: Canvas) {
        val scale = minOf(width, height) / 360f
        if (scale <= 0f) return
        val chapter = story.chapter(phase)
        val t = story.fraction(phase)
        c.save()
        c.translate((width - 360f * scale) / 2f, (height - 360f * scale) / 2f)
        c.scale(scale, scale)
        ink(cream); paint.shader = paper; c.drawRoundRect(field, 8f, 8f, paint); paint.shader = null
        if (cooling) {
            if (chapter == 4) evaporation(c, t) else gland(c, chapter, t)
        } else when (chapter) {
            0, 1 -> alphaCell(c, chapter == 1, t)
            2 -> liverSignal(c, t)
            3 -> glycogen(c, t)
            else -> exportGlucose(c, t)
        }
        c.restore()
    }

    private fun alphaCell(c: Canvas, release: Boolean, t: Float) {
        c.save()
        c.translate(0f, 42f)
        picture(c, R.drawable.health_atlas_digestive_alpha, 0, 0, 360, 280)
        if (release) {
            ring(c, 204f, 154f, 13f + 5f * sin(t * PI.toFloat()), violet)
            for (i in 0..5) marker(c, alphaExit, loop(t * 1.24f + i / 6f), ::hormone)
        } else {
            val count = 6 - (t * 4f).toInt()
            for (i in 0 until count) {
                val x = 62f + 233f * loop(t + i / 6f)
                sugar(c, x, 236f - 8f * sin((x - 50f) * PI.toFloat() / 255f), 4.8f)
            }
        }
        c.restore()
        leader(c, 80f, 99f, 147f, 145f, R.string.health_atlas_home_glucagon_alpha, red)
        if (release) key(c, 203f, 324f, R.string.health_atlas_home_glucagon_hormone, true)
        else key(c, 203f, 324f, R.string.health_atlas_home_glucagon_glucose, false)
    }

    private fun liverSignal(c: Canvas, t: Float) {
        picture(c, R.drawable.health_atlas_liver, 77, 17, 283, 223)
        label(c, 180f, 36f, R.string.health_atlas_home_glucagon_liver)
        line(c, 28f, 203f, 328f, 203f, 0xffe4acb5, 30f)
        line(c, 27f, 203f, 329f, 203f, 0xfff5d0d0, 16f)
        rounded(c, 23f, 244f, 337f, 314f, 14f, 0xffebc8af)
        line(c, 27f, 244f, 334f, 244f, red, 3.5f)
        tube(c, 167f, 236f, 193f, 264f, violet)
        path { moveTo(160f, 225f); quadTo(180f, 245f, 200f, 225f) }
        ink(violet, 5f); c.drawPath(shape, paint)
        for (i in 0..3) marker(c, liverEntry, loop(t * 1.30f + i / 4f), ::hormone)
        if (t > .38f) {
            val f = loop(t * 2.1f)
            ring(c, 180f, 266f + 15f * f, 6f + 4f * f, red)
        }
        label(c, 61f, 174f, R.string.health_atlas_home_glucagon_blood)
        leader(c, 246f, 339f, 194f, 250f, R.string.health_atlas_home_glucagon_receptor, violet)
    }

    private fun glycogen(c: Canvas, t: Float) {
        shadedBox(c, 20f, 100f, 340f, 328f, 22f, tissue)
        val count = (12f * HealthAtlasHomeostasisMotion.glycogenRemaining(t)).toInt().coerceAtLeast(3)
        for (i in 0 until count) {
            val column = i % 4
            val x = 58f + 21f * column
            val y = 173f + 34f * (i / 4) + (column % 2) * 6f
            if (column > 0) line(c, x - 21f, y - if (column % 2 == 0) -6f else 6f, x, y, gold, 2.0f)
            if (column == 1 && i >= 4) line(c, x, y - 34f, x, y, gold, 2f)
            sugar(c, x, y, 7.5f)
        }
        arrow(c, 152f, 211f, 207f, 211f, gold)
        for (i in 0..3) {
            val f = loop(t * 1.14f + i * .25f)
            sugar(c, 219f + 67f * f, 194f + 15f * (i % 3) + 9f * sin(f * 3f), 7.4f)
        }
        label(c, 93f, 134f, R.string.health_atlas_home_glucagon_glycogen)
        label(c, 258f, 134f, R.string.health_atlas_home_glucagon_glucose)
        label(c, 178f, 305f, R.string.health_atlas_home_glucagon_cell)
    }

    private fun exportGlucose(c: Canvas, t: Float) {
        shadedBox(c, 23f, 92f, 337f, 151f, 16f, blood)
        for (i in 0..3) {
            val x = 37f + 280f * loop(t + i * .25f)
            oval(c, x, 138f, 10f, 3.6f, red)
        }
        shadedBox(c, 23f, 165f, 337f, 311f, 18f, tissue)
        line(c, 28f, 175f, 165f, 175f, red, 3f)
        line(c, 195f, 175f, 333f, 175f, red, 3f)
        tube(c, 161f, 155f, 171f, 195f, teal)
        tube(c, 189f, 155f, 199f, 195f, teal)
        for (i in 0..5) marker(c, glucoseExit, loop(t * 1.19f + i / 6f)) { canvas, x, y -> sugar(canvas, x, y, 5.5f) }
        label(c, 180f, 61f, R.string.health_atlas_home_glucagon_blood)
        label(c, 102f, 284f, R.string.health_atlas_home_glucagon_cell)
        leader(c, 266f, 236f, 198f, 176f, R.string.health_atlas_home_glucagon_transporter, teal)
    }

    private fun gland(c: Canvas, chapter: Int, t: Float) {
        c.save()
        c.translate(0f, 56f)
        picture(c, R.drawable.health_atlas_cell_sweat_gland_section, 0, 0, 360, 280)
        when (chapter) {
            0 -> {
                trace.rewind()
                nerve.getSegment(0f, nerve.length, trace, true)
                ink(0xffd9ab6a, 5.5f); c.drawPath(trace, paint)
                ink(gold, 1.3f); c.drawPath(trace, paint)
                for (i in 0..3) marker(c, nerve, loop(t * 1.35f + i / 4f)) { cv, x, y -> dot(cv, x, y, gold, 4.3f) }
                ring(c, 150f, 198f, 10f + 7f * sin(PI.toFloat() * t), gold)
            }
            1 -> {
                for (i in 0..5) marker(c, sweatDuct, 1f - .68f * loop(t * 1.1f + i / 6f)) { cv, x, y ->
                    dot(cv, x, y, water, 3.6f)
                }
            }
            2 -> {
                for (i in 0..4) marker(c, sweatDuct, .43f * (1f - loop(t * 1.23f + i / 5f))) { cv, x, y ->
                    dot(cv, x, y, water, 3.5f)
                }
                for (i in 0..5) {
                    val f = loop(t * 1.08f + i / 6f)
                    val side = if (i % 2 == 0) 1 else -1
                    val x = 173f + side * (6f + 49f * f)
                    val y = 101f + 12f * i + sin(f * 3f) * 5f
                    rounded(c, x - 2.8f, y - 2.8f, x + 2.8f, y + 2.8f, .8f, salt)
                }
            }
            3 -> {
                for (i in 0..3) marker(c, sweatDuct, .24f * (1f - loop(t * 1.17f + i / 4f))) { cv, x, y ->
                    dot(cv, x, y, water, 3.4f)
                }
                drop(c, 173f, 60f, 5.5f + 12f * t)
            }
        }
        c.restore()
        when (chapter) {
            0 -> {
                leader(c, 60f, 314f, 91f, 267f, R.string.health_atlas_home_sweat_nerve, gold)
                leader(c, 251f, 312f, 198f, 274f, R.string.health_atlas_home_sweat_coil, teal)
            }
            1 -> {
                leader(c, 260f, 72f, 178f, 179f, R.string.health_atlas_home_sweat_duct, teal)
                leader(c, 254f, 317f, 192f, 272f, R.string.health_atlas_home_sweat_coil, teal)
            }
            2 -> leader(c, 251f, 76f, 218f, 187f, R.string.health_atlas_home_sweat_salt_label, salt)
            3 -> {
                leader(c, 112f, 66f, 169f, 111f, R.string.health_atlas_home_sweat_droplet, water)
                leader(c, 264f, 74f, 180f, 119f, R.string.health_atlas_home_sweat_pore, teal)
            }
        }
    }

    private fun evaporation(c: Canvas, t: Float) {
        line(c, 180f, 69f, 180f, 279f, 0xffb6c8c7, 1.2f)
        for (humid in listOf(false, true)) {
            val x = if (humid) 270f else 90f
            val radius = 21f * sqrt(HealthAtlasHomeostasisMotion.liquidRemaining(t, humid))
            shadedBox(c, x - 71f, 221f, x + 71f, 284f, 9f, skin)
            line(c, x - 65f, 221f, x + 65f, 221f, red, 3.2f)
            drop(c, x, 220f, radius)
            val count = if (humid) 2 else 5
            for (i in 0 until count) {
                val f = loop(t * (if (humid) .85f else 1.43f) + i / count.toFloat())
                val dx = (i - (count - 1) / 2f) * (if (humid) 15f else 12f)
                val y = 181f - f * (if (humid) 44f else 66f)
                ring(c, x + dx, y, 2.9f + (1f - f) * 1.5f, water)
            }
            val arrowX = x - 57f
            val lift = 8f * sin(t * 8f)
            arrow(c, arrowX, 217f, arrowX, 178f + lift, gold)
            if (!humid) arrow(c, x + 57f, 217f, x + 57f, 169f + lift, gold)
            label(c, x, 64f, if (humid) R.string.health_atlas_home_sweat_humid else R.string.health_atlas_home_sweat_dry)
        }
        label(c, 180f, 329f, R.string.health_atlas_home_sweat_heat)
    }

    private fun tube(c: Canvas, l: Float, t: Float, r: Float, b: Float, colour: Long) {
        rounded(c, l, t, r, b, 6f, colour)
        line(c, l + 3f, t + 5f, l + 3f, b - 5f, cream, 1.1f)
    }

    private fun drop(c: Canvas, x: Float, baseY: Float, r: Float) {
        path {
            moveTo(x, baseY - 2.2f * r)
            cubicTo(x - .5f * r, baseY - 1.7f * r, x - 1.15f * r, baseY - .8f * r, x - .87f * r, baseY - .47f * r)
            cubicTo(x - .64f * r, baseY + .15f * r, x + .61f * r, baseY + .16f * r, x + .86f * r, baseY - .43f * r)
            cubicTo(x + 1.14f * r, baseY - .91f * r, x + .41f * r, baseY - 1.74f * r, x, baseY - 2.2f * r)
            close()
        }
        ink(0xff93c5d5); c.drawPath(shape, paint)
        ink(water, 1.45f); c.drawPath(shape, paint)
        oval(c, x - r * .32f, baseY - .82f * r, r * .15f, r * .28f, 0xffd8eaf0)
    }

    private fun sugar(c: Canvas, x: Float, y: Float, r: Float) {
        path {
            for (i in 0..5) {
                val a = i * PI.toFloat() / 3f
                val px = x + r * cos(a)
                val py = y + r * sin(a)
                if (i == 0) moveTo(px, py) else lineTo(px, py)
            }
            close()
        }
        ink(0xfff1c879); c.drawPath(shape, paint)
        ink(gold, 1.2f); c.drawPath(shape, paint)
    }

    private fun hormone(c: Canvas, x: Float, y: Float) {
        oval(c, x - 3.1f, y, 3.8f, 3.3f, violet)
        oval(c, x + 2.5f, y - 2.5f, 3.4f, 3.5f, 0xff9c79a7)
        oval(c, x + 3.8f, y + 2.5f, 3.6f, 2.7f, violet)
        oval(c, x - 1.6f, y - 1.1f, 1.5f, 1.1f, 0xffdfcbe4)
    }

    private fun key(c: Canvas, x: Float, y: Float, res: Int, isHormone: Boolean) {
        if (isHormone) hormone(c, x - 63f, y - 4f) else sugar(c, x - 63f, y - 4f, 5f)
        label(c, x, y, res)
    }

    private fun leader(c: Canvas, x: Float, y: Float, tx: Float, ty: Float, res: Int, colour: Long) {
        line(c, x, if (ty < y) y - 16f else y + 5f, tx, ty, colour, 1.05f)
        dot(c, tx, ty, colour, 2.2f)
        label(c, x, y, res)
    }

    private fun label(c: Canvas, x: Float, y: Float, res: Int) {
        ink(text)
        val value = context.getString(res)
        paint.textSize = 13f
        val available = 2f * minOf(x - 8f, 352f - x)
        val actual = paint.measureText(value)
        if (actual > available) paint.textSize *= available / actual
        c.drawText(value, x, y, paint)
    }

    private fun picture(c: Canvas, id: Int, l: Int, t: Int, r: Int, b: Int) {
        plates.getOrPut(id) { requireNotNull(context.getDrawable(id)).mutate() }.apply {
            setBounds(l, t, r, b); draw(c)
        }
    }

    private fun marker(c: Canvas, track: PathMeasure, f: Float, draw: (Canvas, Float, Float) -> Unit) {
        if (track.getPosTan(track.length * f, point, null)) draw(c, point[0], point[1])
    }

    private fun shadedBox(c: Canvas, l: Float, t: Float, r: Float, b: Float, radius: Float, shade: Shader) {
        ink(cream); paint.shader = shade
        c.drawRoundRect(l, t, r, b, radius, radius, paint)
        paint.shader = null
    }

    private fun rounded(c: Canvas, l: Float, t: Float, r: Float, b: Float, radius: Float, colour: Long) {
        ink(colour); c.drawRoundRect(l, t, r, b, radius, radius, paint)
    }

    private fun arrow(c: Canvas, x: Float, y: Float, tx: Float, ty: Float, colour: Long) {
        val dx = tx - x
        val dy = ty - y
        val distance = sqrt(dx * dx + dy * dy)
        val ux = dx / distance
        val uy = dy / distance
        line(c, x, y, tx, ty, colour, 1.9f)
        line(c, tx, ty, tx - ux * 6f + uy * 4f, ty - uy * 6f - ux * 4f, colour, 1.9f)
        line(c, tx, ty, tx - ux * 6f - uy * 4f, ty - uy * 6f + ux * 4f, colour, 1.9f)
    }

    private fun ring(c: Canvas, x: Float, y: Float, radius: Float, colour: Long) {
        ink(colour, 1.45f); c.drawCircle(x, y, radius, paint)
    }

    private fun oval(c: Canvas, x: Float, y: Float, rx: Float, ry: Float, colour: Long) {
        ink(colour); c.drawOval(x - rx, y - ry, x + rx, y + ry, paint)
    }

    private fun dot(c: Canvas, x: Float, y: Float, colour: Long, radius: Float) {
        oval(c, x, y, radius + .6f, radius + .6f, cream)
        oval(c, x, y, radius, radius, colour)
    }

    private fun line(c: Canvas, x: Float, y: Float, tx: Float, ty: Float, colour: Long, width: Float) {
        ink(colour, width); c.drawLine(x, y, tx, ty, paint)
    }

    private fun ink(colour: Long, width: Float = 0f) {
        paint.color = colour.toInt()
        paint.style = if (width == 0f) Paint.Style.FILL else Paint.Style.STROKE
        paint.strokeWidth = width
    }

    private inline fun path(build: Path.() -> Unit) { shape.rewind(); shape.build() }
    private inline fun route(build: Path.() -> Unit) = PathMeasure(Path().apply(build), false)
    private fun loop(t: Float) = t % 1f
    private fun gradient(y0: Float, y1: Float, a: Long, b: Long) =
        LinearGradient(0f, y0, 0f, y1, a.toInt(), b.toInt(), Shader.TileMode.CLAMP)
}
