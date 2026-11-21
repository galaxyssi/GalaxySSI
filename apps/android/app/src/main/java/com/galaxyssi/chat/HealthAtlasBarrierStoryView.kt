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
import androidx.annotation.StringRes
import kotlin.math.PI
import kotlin.math.sin

internal object HealthAtlasBarrierMotion {
    fun ascent(t: Float) = 277f - 129f * HealthAtlasFunctionStory.safePhase(t)

    fun escape(t: Float, disrupted: Boolean, index: Int): Float {
        val time = (HealthAtlasFunctionStory.safePhase(t) - .05f * index).coerceAtLeast(0f)
        val rate = when {
            disrupted -> 1.55f
            index == 0 -> .98f
            else -> .36f
        }
        return (time * rate).coerceAtMost(1f)
    }
}

internal class HealthAtlasBarrierStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.EPIDERMAL_BARRIER) {
    private val cellFill = shade(126f, 300f, 0xffffe6d5, 0xffd99b9a)
    private val bedFill = shade(98f, 315f, 0xffffefdd, 0xffd9a5a1)

    init { tag = "atlas-function-epidermal-barrier-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> epidermis(c, t, false, false)
            1 -> epidermis(c, t, true, false)
            2 -> lipids(c, t)
            3 -> compareWater(c, t)
            else -> epidermis(c, t, true, true)
        }
    }

    private fun epidermis(c: Canvas, t: Float, flatten: Boolean, shed: Boolean) {
        // From living basal cells to the thin, nonnucleated surface plates.
        val x = 45f
        ink(coral); paint.shader = bedFill
        c.drawRoundRect(x, 110f, 315f, 296f, 15f, 15f, paint)
        paint.shader = null
        for (row in 0..4) {
            val y = 277f - row * 31f
            for (col in 0..6) {
                val cx = 65f + col * 38f + if (row % 2 == 1) 12f else 0f
                if (cx > 304f || (col == 3 && flatten && !shed)) continue
                cell(c, cx, y, 15f + row, 13.5f - row * 1.7f, if (row > 2) sand else peach, violet)
            }
        }
        for (row in 0..2) {
            for (col in 0..5) {
                if (shed && row == 0 && col == 3) continue
                val shift = if (shed && row == 1 && col == 3) 14f * t else 0f
                plate(c, 53f + col * 44f + row % 2 * 8f, 106f + row * 14f - shift, 40f, 10f)
            }
        }
        line(c, x + 7f, 297f, 308f, 297f, coral, 2f)
        if (!flatten) {
            val gap = 9f + 8f * t
            cell(c, 163f - gap, 274f, 13f, 13f, sand, violet)
            cell(c, 163f + gap, 273f - 12f * t, 13f, 13f, sand, violet)
            arrow(c, 162f, 252f, 162f, 226f - 33f * t, teal)
        } else if (!shed) {
            val y = HealthAtlasBarrierMotion.ascent(t)
            if (t < .88f) cell(c, 181f, y, 16f + 6f * t, 13f - 8f * t, sand, violet)
            else plate(c, 159f, y - 5f, 44f, 10f)
        } else {
            c.save()
            c.rotate(18f * t, 207f + 23f * t, 111f - 47f * t)
            plate(c, 185f + 23f * t, 106f - 47f * t, 44f, 10f)
            c.restore()
            arrow(c, 268f, 91f, 268f, 63f - 15f * t, sienna)
            arrow(c, 185f, 239f, 185f, 203f - 21f * t, teal)
        }
        label(c, R.string.health_atlas_barrier_basal, 94f, 329f, 133f)
        line(c, 94f, 314f, 94f, 296f, coral, 1.2f)
        label(c, R.string.health_atlas_barrier_cornea, 104f, 66f, 153f)
        line(c, 104f, 73f, 104f, 105f, sienna, 1.2f)
    }

    private fun lipids(c: Canvas, t: Float) {
        label(c, R.string.health_atlas_barrier_cornea, 180f, 48f, 240f)
        for (row in 0..2) for (col in 0..3) {
            plate(c, 31f + col * 80f + row % 2 * 13f, 74f + row * 33f, 68f, 24f)
        }
        for (row in 0..2) for (index in 0..3) {
            val x = 43f + index * 75f
            val v = (t * 1.45f - index * .12f).coerceIn(0f, 1f)
            val y = 108f + row * 32f
            line(c, x, y - 1f, x + 20f + 30f * v, y - 1f, teal, 2.4f)
            line(c, x, y + 4f, x + 20f + 30f * v, y + 4f, blue, 1.6f)
        }
        for (i in 0..4) {
            val x = 56f + i * 62f
            oval(c, x - 27f, 221f, x + 27f, 275f, cellFill, coral)
            disc(c, x, 254f, 8f, violet)
            val f = (t * 1.15f - .07f * i).coerceIn(0f, 1f)
            val y = 234f - 45f * f
            for (j in 0..2) line(c, x - 5f, y + 4f * j, x + 5f, y + 4f * j, teal, 2f)
        }
        label(c, R.string.health_atlas_barrier_intercellular, 180f, 195f, 235f)
        label(c, R.string.health_atlas_barrier_granular, 180f, 310f, 225f)
    }

    private fun compareWater(c: Canvas, t: Float) {
        for (i in 0..1) {
            val broken = i == 1
            val x = 22f + i * 162f
            rounded(c, x, 92f, x + 154f, 281f, 9f, 0xfff9f6ea)
            for (row in 0..1) {
                plate(c, x + 8f, 153f + 20f * row, 54f, 15f)
                plate(c, x + 64f, 153f + 20f * row, 26f, 15f)
                plate(c, x + 92f, 153f + 20f * row, 54f, 15f)
                if (!broken) {
                    line(c, x + 10f, 171f + row * 20f, x + 144f, 171f + row * 20f, teal, 2.2f)
                } else {
                    line(c, x + 10f, 171f + row * 20f, x + 60f, 171f + row * 20f, teal, 2.2f)
                    line(c, x + 93f, 171f + row * 20f, x + 144f, 171f + row * 20f, teal, 2.2f)
                }
            }
            for (j in 0..5) {
                val f = HealthAtlasBarrierMotion.escape(t, broken, j)
                val cx = x + 62f + (j % 2) * 29f + 2f * wave(f)
                disc(c, cx, (228f + j * 8f - 128f * f).coerceAtLeast(105f + 4f * j),
                    3.8f + (j % 2), blue, cream)
            }
            label(c, if (broken) R.string.health_atlas_barrier_disrupted else R.string.health_atlas_barrier_intact,
                x + 77f, 309f, 150f)
        }
        line(c, 180f, 97f, 180f, 278f, 0xffc1ccca, 1.1f)
    }

    private fun cell(c: Canvas, x: Float, y: Float, rx: Float, ry: Float, fill: Long, nucleus: Long) {
        oval(c, x - rx, y - ry, x + rx, y + ry, fill, coral)
        disc(c, x - rx * .12f, y + .5f, (ry * .34f).coerceAtLeast(2f), nucleus)
        disc(c, x - rx * .30f, y - ry * .51f, 1.4f, cream)
    }

    private fun plate(c: Canvas, x: Float, y: Float, w: Float, h: Float) {
        rounded(c, x, y, x + w, y + h, 4f, sand)
        line(c, x + 4f, y + 2.5f, x + w - 4f, y + 2.5f, cream, 1.1f)
    }
}

internal abstract class HealthAtlasIllustratedStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasFunctionArt(context, story) {
    protected val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    protected val cream = 0xfffff8eb
    protected val coral = 0xffac6673
    protected val peach = 0xffedb8a5
    protected val sand = 0xffebcc9f
    protected val sienna = 0xff9d6334
    protected val violet = 0xff795489
    protected val teal = 0xff337b6d
    protected val blue = 0xff407c9c
    private val lettering = 0xff23444e
    private val field = RectF(0f, 0f, 360f, 360f)
    private val paper = shade(0f, 360f, 0xffe8f4f3, 0xfffbf0df)
    private val point = FloatArray(2)
    private val labels = mutableMapOf<Int, String>()

    final override fun onDraw(c: Canvas) {
        val scale = minOf(width, height) / 360f
        if (scale <= 0f) return
        c.save()
        c.translate((width - scale * 360f) / 2f, (height - scale * 360f) / 2f)
        c.scale(scale, scale)
        ink(cream); paint.shader = paper; c.drawRoundRect(field, 8f, 8f, paint); paint.shader = null
        scene(c, story.chapter(phase), story.fraction(phase))
        c.restore()
    }

    protected abstract fun scene(c: Canvas, step: Int, t: Float)

    protected fun ink(color: Long, weight: Float = 0f) {
        paint.color = color.toInt()
        paint.style = if (weight > 0f) Paint.Style.STROKE else Paint.Style.FILL
        paint.strokeWidth = weight
    }

    protected fun shade(y1: Float, y2: Float, from: Long, to: Long) =
        LinearGradient(0f, y1, 0f, y2, from.toInt(), to.toInt(), Shader.TileMode.CLAMP)

    protected fun oval(c: Canvas, x1: Float, y1: Float, x2: Float, y2: Float, fill: Shader, border: Long) {
        ink(cream); paint.shader = fill; c.drawOval(x1, y1, x2, y2, paint); paint.shader = null
        ink(border, 1.3f); c.drawOval(x1, y1, x2, y2, paint)
    }

    protected fun oval(c: Canvas, x1: Float, y1: Float, x2: Float, y2: Float, fill: Long, border: Long) {
        ink(fill); c.drawOval(x1, y1, x2, y2, paint)
        ink(border, 1.05f); c.drawOval(x1, y1, x2, y2, paint)
    }

    protected fun rounded(c: Canvas, x1: Float, y1: Float, x2: Float, y2: Float, radius: Float, fill: Long) {
        ink(fill); c.drawRoundRect(x1, y1, x2, y2, radius, radius, paint)
    }

    protected fun disc(c: Canvas, x: Float, y: Float, radius: Float, fill: Long, border: Long? = null) {
        ink(fill); c.drawCircle(x, y, radius, paint)
        if (border != null) { ink(border, 1.15f); c.drawCircle(x, y, radius, paint) }
    }

    protected fun line(c: Canvas, x1: Float, y1: Float, x2: Float, y2: Float, color: Long, width: Float) {
        ink(color, width); c.drawLine(x1, y1, x2, y2, paint)
    }

    protected fun arrow(c: Canvas, x1: Float, y1: Float, x2: Float, y2: Float, color: Long) {
        line(c, x1, y1, x2, y2, color, 1.8f)
        val length = kotlin.math.hypot(x2 - x1, y2 - y1).coerceAtLeast(1f)
        val dx = (x2 - x1) / length
        val dy = (y2 - y1) / length
        for (side in intArrayOf(-1, 1)) {
            line(c, x2, y2, x2 - 7f * dx + side * 4f * dy, y2 - 7f * dy - side * 4f * dx, color, 1.8f)
        }
    }

    protected fun label(c: Canvas, @StringRes res: Int, x: Float, baseline: Float, maxWidth: Float) {
        val value = labels.getOrPut(res) { context.getString(res) }
        ink(lettering)
        paint.textSize = 13f
        paint.textSize *= minOf(1f, maxWidth / paint.measureText(value))
        c.drawText(value, x, baseline, paint)
    }

    protected fun stroke(c: Canvas, path: Path, color: Long, width: Float) {
        ink(color, width); c.drawPath(path, paint)
    }

    protected fun at(path: PathMeasure, fraction: Float, draw: (Float, Float) -> Unit) {
        if (path.getPosTan(path.length * fraction.coerceIn(0f, 1f), point, null)) draw(point[0], point[1])
    }

    protected fun track(path: Path) = PathMeasure(path, false)

    protected fun wave(t: Float) = sin(t * 2f * PI.toFloat())
}
