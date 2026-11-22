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
import kotlin.math.sin

internal enum class HealthAtlasLymphPumpStage(val inletOpen: Boolean, val outletOpen: Boolean) {
    FILLING(true, false), HOLDING(false, false), EMPTYING(false, true);

    companion object {
        fun cycle(progress: Float): Float {
            val time = HealthAtlasFunctionStory.safePhase(progress) * 1.75f
            return time % 1f
        }
        fun at(cycle: Float) = when {
            cycle < .41f -> FILLING
            cycle < .57f || cycle >= .97f -> HOLDING
            else -> EMPTYING
        }
        fun expansion(cycle: Float) = when {
            cycle < .41f -> cycle / .41f
            cycle < .57f -> 1f
            cycle < .97f -> 1f - (cycle - .57f) / .40f
            else -> 0f
        }.coerceIn(0f, 1f)
    }
}

internal class HealthAtlasLymphImmuneStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasFunctionArt(context, story) {
    private val lymph = story == HealthAtlasFunctionStory.LYMPH_RETURN
    private val drawables = mutableMapOf<Int, Drawable>()
    private val lymphSections = if (lymph) listOf("lymph-nodes", "thoracic-duct").associateWith { id ->
        val lesson = requireNotNull(HealthAtlasLymphOrgans[id])
        lesson.plate.drawable to lesson.tracks.map { PathMeasure(it(), false) }
    } else emptyMap()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    }
    private val paper = gradient(0f, 360f, 0xffeaf6f5, 0xfffcf5e9)
    private val blood = gradient(64f, 120f, 0xfff4c9cc, 0xffc98495)
    private val fluid = gradient(133f, 222f, 0xffd0ebe6, 0xff86b8b3)
    private val tissue = gradient(200f, 300f, 0xffeee6dc, 0xffd8c3b4)
    private val rose = 0xffa85363
    private val teal = 0xff236d69
    private val blue = 0xff2f6f95
    private val gold = 0xffa77532
    private val cream = 0xfffcfbef
    private val text = 0xff23444b
    private val scratch = Path()
    private val point = FloatArray(2)
    private val rect = RectF(0f, 0f, 360f, 360f)

    init { tag = if (lymph) "atlas-function-lymph-return-art" else "atlas-function-antibody-response-art" }

    override fun onDraw(canvas: Canvas) {
        val scale = minOf(width, height) / 360f
        if (scale <= 0f) return
        val chapter = story.chapter(phase)
        val t = story.fraction(phase)
        canvas.save()
        canvas.translate((width - 360f * scale) / 2f, (height - 360f * scale) / 2f)
        canvas.scale(scale, scale)
        ink(cream)
        paint.shader = paper
        canvas.drawRoundRect(rect, 8f, 8f, paint)
        paint.shader = null
        if (lymph) when (chapter) {
            0 -> tissueFluid(canvas, t)
            1 -> capillaryEntry(canvas, t)
            2 -> collectingVessel(canvas, t)
            3 -> lymphSection(canvas, "lymph-nodes", t)
            else -> lymphSection(canvas, "thoracic-duct", t)
        } else when (chapter) {
            0 -> recognize(canvas, t)
            1 -> helperSignal(canvas, t)
            2 -> expand(canvas, t)
            3 -> specialize(canvas, t)
            else -> release(canvas, t)
        }
        canvas.restore()
    }

    private fun tissueFluid(c: Canvas, t: Float) {
        wave {
            moveTo(24f, 67f); cubicTo(122f, 86f, 186f, 51f, 336f, 63f)
            lineTo(336f, 113f); cubicTo(186f, 102f, 122f, 138f, 24f, 118f); close()
        }
        shaded(c, blood, rose)
        for (i in 0..5) {
            val x = 37f + 286f * loop(t * 1.04f + i / 6f)
            val y = 91f + 6f * sin(x / 65f)
            oval(c, x, y, 13f, 7.5f, rose)
            oval(c, x - 1f, y - 1f, 7.1f, 3f, 0xffe4a0a4)
        }
        for (i in 0..5) {
            val f = loop(t * 1.24f + i / 6f)
            val x = 58f + 43f * i + 9f * sin(f * 3f)
            tracer(c, x, 100f + 96f * f, blue, 3.6f)
        }
        for (i in 0..3) {
            val x = 60f + i * 77f
            val y = 253f + (i % 2) * 31f
            wave {
                moveTo(x - 27f, y - 5f); cubicTo(x - 21f, y - 31f, x + 21f, y - 30f, x + 29f, y - 7f)
                cubicTo(x + 43f, y + 22f, x - 37f, y + 33f, x - 27f, y - 5f); close()
            }
            shaded(c, tissue, 0xffad918a)
            oval(c, x + 4f, y, 11f, 6f, 0xffad8c9d)
            oval(c, x + 2f, y - 1f, 5f, 2.8f, 0xffd5bcc5)
        }
        label(c, 180f, 40f, R.string.health_atlas_lymph_flow_blood)
        leader(c, 169f, 219f, 185f, 177f, R.string.health_atlas_lymph_flow_fluid, blue)
    }

    private fun capillaryEntry(c: Canvas, t: Float) {
        val flap = 6f + 7f * sin(PI.toFloat() * t)
        wave {
            moveTo(337f, 142f); lineTo(83f, 142f); cubicTo(35f, 142f, 24f, 170f, 44f, 196f)
            quadTo(57f, 217f, 94f, 217f); lineTo(337f, 217f); close()
        }
        shaded(c, fluid, teal)
        for (i in 0..15) oval(c, 55f + i * 17.5f, 210f, 4.4f, 2.2f, 0xff568d87)
        for (x in listOf(120f, 222f)) {
            // Leave a visible gap at the free edge, not at the blind end.
            line(c, x - 15f, 142f, x + 14f, 142f, 0xffd1e9e4, 5f)
            wave { moveTo(x - 17f, 141f); quadTo(x - 6f, 140f, x + 5f, 141f + flap) }
            ink(teal, 3.5f); c.drawPath(scratch, paint)
            wave { moveTo(x + 18f, 141f); quadTo(x + 12f, 142f, x + 9f, 145f) }
            ink(teal, 2.8f); c.drawPath(scratch, paint)
            for (i in 0..3) {
                val f = loop(t * 1.5f + i * .25f)
                val dx = if (f < .62f) (f - .62f) * 9f else (f - .62f) * 70f
                tracer(c, x + 9f + dx, 72f + minOf(f, .75f) * 145f, blue, 3.0f)
            }
        }
        for (i in 0..4) tracer(c, 100f + 215f * loop(t * 1.38f + i / 5f), 190f, teal, 4f)
        label(c, 103f, 54f, R.string.health_atlas_lymph_flow_fluid)
        leader(c, 263f, 52f, 221f, 143f, R.string.health_atlas_lymph_flow_flaps, teal)
        label(c, 180f, 267f, R.string.health_atlas_lymph_flow_capillary)
    }

    private fun collectingVessel(c: Canvas, t: Float) {
        val cycle = HealthAtlasLymphPumpStage.cycle(t)
        val stage = HealthAtlasLymphPumpStage.at(cycle)
        val center = 176f
        val edge = center - 22f
        val bulge = 9f + 19f * HealthAtlasLymphPumpStage.expansion(cycle)
        wave {
            moveTo(25f, edge); lineTo(84f, edge)
            cubicTo(124f, edge - bulge, 214f, edge - bulge, 273f, edge); lineTo(335f, edge)
            lineTo(335f, 2 * center - edge); lineTo(273f, 2 * center - edge)
            cubicTo(214f, 2 * center - edge + bulge, 124f, 2 * center - edge + bulge, 84f, 2 * center - edge)
            lineTo(25f, 2 * center - edge); close()
        }
        shaded(c, fluid, teal, 2.8f)
        valve(c, 84f, center, stage.inletOpen)
        valve(c, 273f, center, stage.outletOpen)
        for (i in 0..3) {
            val fraction = loop(t * 2.6f + i * .25f)
            val x = when (stage) {
                HealthAtlasLymphPumpStage.FILLING -> 36f + fraction * 153f
                HealthAtlasLymphPumpStage.HOLDING -> 143f + i * 22f
                HealthAtlasLymphPumpStage.EMPTYING -> 160f + fraction * 165f
            }
            tracer(c, x, 166f + (i % 2) * 20f, teal, 3.8f)
        }
        label(c, 180f, 91f, when (stage) {
            HealthAtlasLymphPumpStage.FILLING -> R.string.health_atlas_lymph_flow_filling
            HealthAtlasLymphPumpStage.HOLDING -> R.string.health_atlas_lymph_flow_holding
            HealthAtlasLymphPumpStage.EMPTYING -> R.string.health_atlas_lymph_flow_contracting
        })
        label(c, 180f, 263f, R.string.health_atlas_lymph_flow_capillary_collecting)
    }

    private fun valve(c: Canvas, x: Float, y: Float, open: Boolean) {
        val gap = if (open) 12f else 0f
        for (direction in listOf(-1, 1)) {
            wave {
                moveTo(x, y + direction * 22f)
                quadTo(x + 11f, y + direction * 19f, x + 16f, y + direction * gap)
            }
            ink(cream, 6f); c.drawPath(scratch, paint)
            ink(teal, 2f); c.drawPath(scratch, paint)
        }
    }

    private fun lymphSection(c: Canvas, id: String, t: Float) {
        val (resource, tracks) = requireNotNull(lymphSections[id])
        c.save()
        c.translate(0f, 42f)
        picture(c, resource, 0, 0, 360, 280)
        val length = tracks.sumOf { it.length.toDouble() }.toFloat()
        for (i in 0..8) {
            var rem = loop(t * 1.08f + i / 9f) * length
            for (segment in tracks) {
                if (rem <= segment.length && segment.getPosTan(rem, point, null)) {
                    tracer(c, point[0], point[1], teal, 3.7f)
                    break
                }
                rem -= segment.length
            }
        }
        c.restore()
        if (id == "lymph-nodes") {
            leader(c, 81f, 54f, 94f, 85f, R.string.health_atlas_lymph_flow_in, teal)
            leader(c, 281f, 274f, 299f, 230f, R.string.health_atlas_lymph_flow_out, teal)
        } else {
            leader(c, 70f, 204f, 175f, 208f, R.string.health_atlas_lymph_flow_duct, teal)
            leader(c, 233f, 67f, 231f, 103f, R.string.health_atlas_lymph_flow_vein, teal)
        }
    }

    private fun recognize(c: Canvas, t: Float) {
        cell(c, R.drawable.health_atlas_cell_b, 112f, 181f, 220f)
        val x = 294f - 101f * t
        antigen(c, x, 182f, 9f)
        label(c, 106f, 288f, R.string.health_atlas_antibody_story_b_cell)
        leader(c, 265f, 123f, x, 173f, R.string.health_atlas_antibody_story_antigen, gold)
    }

    private fun helperSignal(c: Canvas, t: Float) {
        val right = 264f - 15f * t
        cell(c, R.drawable.health_atlas_cell_b, 98f, 177f, 176f)
        c.save()
        c.scale(-1f, 1f, right, 177f)
        cell(c, R.drawable.health_atlas_cell_t, right, 177f, 176f)
        c.restore()
        line(c, 149f, 174f, right - 61f, 174f, teal, 2.3f)
        antigen(c, 153f, 174f, 4f)
        for (i in 0..2) {
            val f = loop(t * 1.4f + i / 3f)
            tracer(c, right - 62f - f * (right - 221f), 185f + i * 5f, gold, 2.9f)
        }
        label(c, 95f, 270f, R.string.health_atlas_antibody_story_b_cell)
        label(c, 263f, 270f, R.string.health_atlas_antibody_story_helper)
        leader(c, 179f, 78f, 173f, 176f, R.string.health_atlas_antibody_story_signal, teal)
    }

    private fun expand(c: Canvas, t: Float) {
        val split = t < .47f
        val phase = if (split) t / .47f else (t - .47f) / .53f
        val shift = sin(phase * PI.toFloat() / 2f)
        val spreadX = if (split) 31f * shift else 31f + 27f * shift
        val diameter = if (split) 121f - 16f * shift else 105f - 20f * shift
        for (x in listOf(180f - spreadX, 180f + spreadX)) {
            if (split) cell(c, R.drawable.health_atlas_cell_b, x, 175f, diameter)
            else for (d in listOf(-1, 1)) cell(c, R.drawable.health_atlas_cell_b, x, 175f + d * 49f * shift, diameter)
        }
        label(c, 180f, 287f, R.string.health_atlas_antibody_story_clone)
    }

    private fun specialize(c: Canvas, t: Float) {
        cell(c, R.drawable.health_atlas_cell_b, 180f, 86f, 93f)
        wave { moveTo(180f, 125f); quadTo(157f, 150f, 113f, 185f) }
        ink(teal, 2.6f); c.drawPath(scratch, paint)
        wave { moveTo(180f, 125f); quadTo(203f, 150f, 247f, 185f) }
        ink(teal, 2.6f); c.drawPath(scratch, paint)
        val f = loop(t * 1.35f)
        for (d in listOf(-1, 1)) tracer(c, 180f + d * 67f * f, 125f + 60f * f, gold, 3.5f)
        cell(c, R.drawable.health_atlas_cell_plasma, 107f, 234f, 102f + 17f * t)
        cell(c, R.drawable.health_atlas_cell_b, 253f, 234f, 98f + 13f * t)
        label(c, 101f, 320f, R.string.health_atlas_antibody_story_plasma)
        label(c, 257f, 320f, R.string.health_atlas_antibody_story_memory)
    }

    private fun release(c: Canvas, t: Float) {
        cell(c, R.drawable.health_atlas_cell_plasma, 101f, 180f, 156f)
        oval(c, 290f, 180f, 37f, 51f, 0xffecd6a3)
        oval(c, 303f, 182f, 13f, 27f, 0xfff3e6bf)
        for (i in 0..2) {
            val y = 158f + i * 22f
            val x = 158f + (74f - i * 5f) * loop(t * 1.5f + i / 3f)
            antibody(c, x, y, teal)
            antigen(c, 253f + (if (i == 1) 0f else 4f), y, 5f)
            if (t > .23f + i * .19f) antibody(c, 240f, y, teal)
        }
        label(c, 99f, 286f, R.string.health_atlas_antibody_story_plasma)
        leader(c, 216f, 100f, 235f, 148f, R.string.health_atlas_antibody_story_antibody, teal)
        label(c, 291f, 265f, R.string.health_atlas_antibody_story_antigen)
    }

    private fun antigen(c: Canvas, x: Float, y: Float, r: Float) {
        wave { moveTo(x - r, y); lineTo(x, y - r); lineTo(x + r, y); lineTo(x, y + r); close() }
        ink(0xffe8b66e); c.drawPath(scratch, paint)
        ink(gold, 1.2f); c.drawPath(scratch, paint)
    }

    private fun antibody(c: Canvas, x: Float, y: Float, color: Long) {
        wave { moveTo(x - 8f, y); lineTo(x + 1f, y); lineTo(x + 9f, y - 6f)
            moveTo(x + 1f, y); lineTo(x + 9f, y + 6f) }
        ink(cream, 5f); c.drawPath(scratch, paint)
        ink(color, 2.8f); c.drawPath(scratch, paint)
    }

    private fun cell(c: Canvas, drawable: Int, x: Float, y: Float, diameter: Float) {
        val half = diameter / 2
        picture(c, drawable, (x - half).toInt(), (y - half).toInt(), (x + half).toInt(), (y + half).toInt())
    }

    private fun picture(c: Canvas, drawable: Int, left: Int, top: Int, right: Int, bottom: Int) {
        drawables.getOrPut(drawable) { requireNotNull(context.getDrawable(drawable)).mutate() }.apply {
            setBounds(left, top, right, bottom); draw(c)
        }
    }

    private fun label(c: Canvas, x: Float, y: Float, res: Int) {
        ink(text)
        val label = context.getString(res)
        paint.textSize = 13f
        val available = 2f * minOf(x - 8f, 352f - x)
        val measured = paint.measureText(label)
        if (measured > available) paint.textSize *= available / measured
        c.drawText(label, x, y, paint)
    }

    private fun leader(c: Canvas, x: Float, y: Float, tx: Float, ty: Float, res: Int, color: Long) {
        val labelEdge = if (ty < y) y - 16f else y + 6f
        line(c, x, labelEdge, tx, ty, color, 1.1f)
        tracer(c, tx, ty, color, 2.9f)
        label(c, x, y, res)
    }

    private fun tracer(c: Canvas, x: Float, y: Float, fill: Long, r: Float) {
        oval(c, x, y, r + .8f, r + .8f, cream)
        oval(c, x, y, r, r, fill)
    }

    private fun shaded(c: Canvas, shade: Shader, stroke: Long, width: Float = 1.5f) {
        ink(cream)
        paint.shader = shade
        c.drawPath(scratch, paint)
        paint.shader = null
        ink(stroke, width); c.drawPath(scratch, paint)
    }

    private fun oval(c: Canvas, x: Float, y: Float, rx: Float, ry: Float, fill: Long) {
        ink(fill)
        c.drawOval(x - rx, y - ry, x + rx, y + ry, paint)
    }

    private fun line(c: Canvas, x1: Float, y1: Float, x2: Float, y2: Float, color: Long, width: Float) {
        ink(color, width)
        c.drawLine(x1, y1, x2, y2, paint)
    }

    private fun ink(color: Long, width: Float = 0f) {
        paint.color = color.toInt()
        paint.style = if (width == 0f) Paint.Style.FILL else Paint.Style.STROKE
        paint.strokeWidth = width
    }

    private inline fun wave(build: Path.() -> Unit) { scratch.rewind(); scratch.build() }
    private fun loop(t: Float) = t % 1f
    private fun gradient(top: Float, bottom: Float, a: Long, b: Long) =
        LinearGradient(0f, top, 0f, bottom, a.toInt(), b.toInt(), Shader.TileMode.CLAMP)
}
