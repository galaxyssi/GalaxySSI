package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.drawable.Drawable
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

internal object HealthAtlasRodResponse {
    fun light(t: Float) = transition(t, .24f, .36f)
    fun messenger(t: Float) = 1f - .86f * transition(t, .30f, .61f)
    fun opening(t: Float) = 1f - transition(t, .38f, .72f)
    fun release(t: Float) = 1f - .77f * transition(t, .56f, .92f)

    private fun transition(t: Float, start: Float, end: Float): Float {
        val f = ((t - start) / (end - start)).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }
}

internal class HealthAtlasVisionStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasFunctionArt(context, story) {
    private val adaptation = story == HealthAtlasFunctionStory.LIGHT_ADAPTATION
    private val scenes = if (adaptation) HealthAtlasVisionStage.adaptation else HealthAtlasVisionStage.pathway
    private val drawables = mutableMapOf<Int, Drawable>()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val frame = RectF(0f, 0f, SIZE, SIZE)
    private val field = LinearGradient(0f, 0f, 0f, SIZE, 0xffe9f4f7.toInt(), 0xfffaf0e3.toInt(), Shader.TileMode.CLAMP)
    private val shape = Path()
    private val point = FloatArray(2)
    private val gold = 0xffa5651b.toInt()
    private val neural = 0xff137568.toInt()
    private val rod = 0xff675393.toInt()
    private val cone = 0xffa84759.toInt()
    private val text = 0xff23434c.toInt()
    private val rays = listOf(-12f, 0f, 12f).map { offset ->
        path {
            moveTo(20f, 160f + offset * 1.8f)
            lineTo(56f, 160f + offset * 1.55f)
            lineTo(87f, 164f + offset * .55f)
            lineTo(117f, 164f + offset * .42f)
            lineTo(255f, 149f)
        }
    }
    private val lightInRetina = path { moveTo(66f, 108f); lineTo(66f, 232f) }
    private val coneRelay = path {
        moveTo(222f, 211f); lineTo(222f, 132f); quadTo(212f, 114f, 222f, 93f)
        lineTo(222f, 77f); quadTo(269f, 64f, 313f, 75f)
    }
    private val nerve = Path().apply {
        moveTo(48f, 244f); cubicTo(93f, 244f, 121f, 217f, 153f, 231f)
        cubicTo(197f, 249f, 225f, 244f, 291f, 229f)
    }
    private val nerveTrack = PathMeasure(nerve, false)
    private val spectralColours = intArrayOf(0xff565cbb.toInt(), 0xff118575.toInt(), 0xffbf5661.toInt())

    init { tag = if (adaptation) "atlas-function-light-adaptation-art" else "atlas-function-vision-art" }

    override fun onDraw(canvas: Canvas) {
        val scale = minOf(width, height) / SIZE
        if (scale <= 0f) return
        val stage = scenes[story.chapter(phase)]
        val t = story.fraction(phase)
        canvas.save()
        canvas.translate((width - SIZE * scale) / 2f, (height - SIZE * scale) / 2f)
        canvas.scale(scale, scale)
        ink(WHITE)
        paint.shader = field
        canvas.drawRoundRect(frame, 8f, 8f, paint)
        paint.shader = null
        if (adaptation) compareLight(canvas, stage, t) else when (stage) {
            HealthAtlasVisionStage.ENTRY, HealthAtlasVisionStage.FOCUS -> optics(canvas, stage, t)
            HealthAtlasVisionStage.CAPTURE -> capture(canvas, t)
            HealthAtlasVisionStage.RELAY -> relay(canvas, t)
            HealthAtlasVisionStage.OUTPUT -> axons(canvas, t)
            else -> Unit
        }
        canvas.restore()
    }

    private fun optics(canvas: Canvas, stage: HealthAtlasVisionStage, t: Float) {
        picture(canvas, R.drawable.health_atlas_eye_section, 6, 54, 338, 275)
        val focus = stage == HealthAtlasVisionStage.FOCUS
        for (ray in rays) {
            shape.rewind()
            val drawn = ray.length * if (focus) 1f else .43f + t * .37f
            ray.getSegment(0f, drawn, shape, true)
            ink(WHITE, 3.5f); canvas.drawPath(shape, paint)
            ink(gold, 1.7f); canvas.drawPath(shape, paint)
            repeat(2) { i ->
                val fraction = loop(t * 1.28f + i * .5f)
                pulse(canvas, ray, fraction * drawn / ray.length, gold, 2.7f)
            }
        }
        if (focus) {
            ink(gold, 2f)
            canvas.drawCircle(255f, 149f, 6f + sin(PI.toFloat() * t) * 3f, paint)
            leader(canvas, 255f, 149f, 279f, 46f, R.string.health_atlas_vision_story_retina, gold)
        } else {
            leader(canvas, 54f, 174f, 55f, 293f, R.string.health_atlas_vision_story_cornea, gold)
            leader(canvas, 87f, 165f, 119f, 309f, R.string.health_atlas_vision_story_pupil, gold)
            leader(canvas, 115f, 157f, 155f, 49f, R.string.health_atlas_vision_story_lens, gold)
        }
        key(canvas, 251f, 301f, R.string.health_atlas_vision_story_light, gold)
    }

    private fun capture(canvas: Canvas, t: Float) {
        picture(canvas, R.drawable.health_atlas_sensory_rod, 4, 43, 142, 290)
        val light = HealthAtlasRodResponse.light(t)
        val target = 73f
        if (t in .10f.. .24f) {
            val incident = (t - .10f) / .14f
            dot(canvas, target, 26f + 66f * incident, 4f, gold)
        }
        val count = (6f * HealthAtlasRodResponse.release(t)).toInt().coerceAtLeast(1)
        repeat(count) { i ->
            val move = loop(t * 2.4f + i / count.toFloat())
            dot(canvas, target + (i % 3 - 1) * 9f, 284f + move * 17f, 2.6f, neural)
        }
        ink(if (light > .5f) gold else rod, 1.6f)
        canvas.drawCircle(target, 92f, 19f, paint)
        canvas.drawLine(target + 19f, 92f, 147f, 108f, paint)
        label(canvas, target, 326f, if (count > 3) R.string.health_atlas_vision_story_dark_release
            else R.string.health_atlas_vision_story_light_release, 11.5f)
        rodMembrane(canvas, t, light)
    }

    private fun rodMembrane(canvas: Canvas, t: Float, light: Float) {
        ink(0xffeef7f5.toInt())
        canvas.drawRoundRect(142f, 38f, 333f, 306f, 8f, 8f, paint)
        ink(0xfff6ecdf.toInt())
        canvas.drawRoundRect(142f, 150f, 333f, 306f, 8f, 8f, paint)
        label(canvas, 237f, 59f, if (light > .5f) R.string.health_atlas_vision_story_lit
            else R.string.health_atlas_vision_story_unlit, 12.5f)
        label(canvas, 237f, 91f, R.string.health_atlas_vision_story_dark_current, 11f)

        val gate = HealthAtlasRodResponse.opening(t)
        val gap = 9f * gate
        ink(0xffad7a70.toInt(), 3f)
        for (row in 0..1) {
            val y = 136f + 15f * row
            canvas.drawLine(151f, y, 214f, y, paint)
            canvas.drawLine(260f, y, 324f, y, paint)
        }
        ink(rod)
        canvas.drawRoundRect(211f, 125f, 237f - gap, 162f, 7f, 7f, paint)
        canvas.drawRoundRect(237f + gap, 125f, 263f, 162f, 7f, 7f, paint)
        for (i in 0 until (gate * 4f + .5f).toInt()) {
            val f = loop(t * 2.2f + i * .25f)
            dot(canvas, 237f, 104f + 74f * f, 3.1f, neural)
        }
        label(canvas, 238f, 190f, if (gate > .22f) R.string.health_atlas_vision_story_cng_open
            else R.string.health_atlas_vision_story_cng_closed, 11.5f)

        val messenger = HealthAtlasRodResponse.messenger(t)
        for (i in 0..6) {
            val x = 169f + i * 22f
            dot(canvas, x, 216f + sin(t * 6f + i) * 3f, 4.3f,
                if (i < messenger * 7f) gold else 0xffc9bcae.toInt())
        }
        label(canvas, 237f, 241f, R.string.health_atlas_vision_story_cgmp, 11.5f)
        label(canvas, 237f, 274f, if (gate <= .22f) R.string.health_atlas_vision_story_hyperpolarized
            else R.string.health_atlas_vision_story_resting, 11.5f)
    }

    private fun relay(canvas: Canvas, t: Float) {
        picture(canvas, R.drawable.health_atlas_sensory_retina_section, 5, 16, 339, 278)
        repeat(4) { i ->
            pulse(canvas, lightInRetina, loop(t * 1.4f + i * .25f), gold, 3.5f)
            pulse(canvas, coneRelay, loop(t * 1.4f - .12f + i * .25f + 1f), neural, 3.5f)
        }
        key(canvas, 97f, 293f, R.string.health_atlas_vision_story_light_down, gold)
        key(canvas, 254f, 293f, R.string.health_atlas_vision_story_relay_up, neural)
        label(canvas, 172f, 321f, R.string.health_atlas_vision_story_cone_route, 11f)
    }

    private fun axons(canvas: Canvas, t: Float) {
        picture(canvas, R.drawable.health_atlas_brain, 61, 12, 282, 233)
        ink(neural, 3f); canvas.drawPath(nerve, paint)
        repeat(5) { i -> pulse(canvas, nerveTrack, loop(t * 1.6f + i * .2f), neural, 3.8f) }
        dot(canvas, 48f, 244f, 5f, neural)
        dot(canvas, 153f, 231f, 5f, neural)
        dot(canvas, 291f, 229f, 5f, neural)
        label(canvas, 55f, 270f, R.string.health_atlas_vision_story_nerve, 11.5f)
        label(canvas, 156f, 270f, R.string.health_atlas_vision_story_thalamus, 11.5f)
        label(canvas, 286f, 270f, R.string.health_atlas_vision_story_cortex, 11.5f)
        key(canvas, 172f, 311f, R.string.health_atlas_vision_story_spikes, neural)
    }

    private fun compareLight(canvas: Canvas, stage: HealthAtlasVisionStage, t: Float) {
        val light = stage.displayLight(t)
        val rodCount = when (stage) {
            HealthAtlasVisionStage.ROD -> 1 + (t * 4f).toInt()
            HealthAtlasVisionStage.DIM -> 1 + (t * 2f).toInt()
            HealthAtlasVisionStage.MIXED -> 3 - t.toInt()
            else -> 0
        }
        val coneCount = when (stage) {
            HealthAtlasVisionStage.BRIGHT, HealthAtlasVisionStage.COLOR -> 5
            HealthAtlasVisionStage.DIM -> 4 - (t * 3f).toInt()
            HealthAtlasVisionStage.MIXED -> 1 + (t * 3f).toInt()
            else -> 0
        }
        ink(blend(0xff29404a.toInt(), 0xfff1e9d4.toInt(), light))
        canvas.drawRoundRect(24f, 19f, 320f, 92f, 8f, 8f, paint)
        val chroma = ((light - .24f) / .54f).coerceIn(0f, 1f)
        spectralColours.forEachIndexed { i, colour ->
            val x = 92f + i * 80f
            val shade = blend(0xff8d9c9d.toInt(), colour, chroma)
            ink(shade)
            when (i) {
                0 -> canvas.drawCircle(x, 54f, 16f, paint)
                1 -> canvas.drawRoundRect(x - 16f, 38f, x + 16f, 70f, 4f, 4f, paint)
                else -> {
                    shape.rewind(); shape.moveTo(x, 36f); shape.lineTo(x + 18f, 70f)
                    shape.lineTo(x - 18f, 70f); shape.close(); canvas.drawPath(shape, paint)
                }
            }
            if (stage == HealthAtlasVisionStage.COLOR) {
                val emphasis = (t * 3f).toInt().coerceAtMost(2)
                if (emphasis == i) {
                    ink(WHITE, 2f)
                    canvas.drawRoundRect(x - 22f, 32f, x + 22f, 76f, 5f, 5f, paint)
                }
            }
        }
        picture(canvas, R.drawable.health_atlas_sensory_rod, 34, 102, 142, 264)
        picture(canvas, R.drawable.health_atlas_sensory_cone, 198, 102, 306, 264)
        response(canvas, 87f, rodCount, t, rod)
        response(canvas, 251f, coneCount, t, cone)
        key(canvas, 87f, 293f, R.string.health_atlas_vision_story_rod_label, rod)
        key(canvas, 251f, 293f, R.string.health_atlas_vision_story_cone_label, cone)
        label(canvas, 172f, 321f, R.string.health_atlas_vision_story_relative, 11f)
    }

    private fun response(canvas: Canvas, x: Float, count: Int, t: Float, color: Int) {
        repeat(count) { i ->
            val travel = loop(t * 2f + i * .24f)
            val dx = (i % 3 - 1) * 9f
            dot(canvas, x + dx, 260f + travel * 15f, (4f - abs(i - 2) * .25f), color)
        }
    }
    private fun picture(canvas: Canvas, id: Int, l: Int, t: Int, r: Int, b: Int) {
        val drawable = drawables.getOrPut(id) { requireNotNull(context.getDrawable(id)).mutate() }
        drawable.setBounds(l, t, r, b); drawable.draw(canvas)
    }
    private fun pulse(canvas: Canvas, path: PathMeasure, t: Float, color: Int, radius: Float) {
        if (path.getPosTan(t * path.length, point, null)) {
            dot(canvas, point[0], point[1], radius + 1.4f, WHITE)
            dot(canvas, point[0], point[1], radius, color)
        }
    }
    private fun leader(canvas: Canvas, x: Float, y: Float, lx: Float, ly: Float, id: Int, color: Int) {
        val stop = if (ly > y) ly - 14f else ly + 5f
        ink(WHITE, 2.7f); canvas.drawLine(x, y, lx, stop, paint)
        ink(color, 1.25f); canvas.drawLine(x, y, lx, stop, paint)
        dot(canvas, x, y, 2.7f, color)
        label(canvas, lx, ly, id, 11.5f)
    }
    private fun key(canvas: Canvas, center: Float, y: Float, id: Int, color: Int) {
        val label = context.getString(id)
        paint.textSize = 11.5f
        val x = center - (paint.measureText(label) + 14f) / 2f
        dot(canvas, x + 4f, y - 4f, 3.6f, color)
        ink(text); canvas.drawText(label, x + 14f, y, paint)
    }
    private fun label(canvas: Canvas, x: Float, y: Float, id: Int, size: Float) {
        val value = context.getString(id)
        ink(text); paint.textSize = size
        canvas.drawText(value, x - paint.measureText(value) / 2, y, paint)
    }
    private fun dot(canvas: Canvas, x: Float, y: Float, radius: Float, color: Int) {
        ink(color); canvas.drawCircle(x, y, radius, paint)
    }
    private fun ink(color: Int, stroke: Float = 0f) {
        paint.color = color
        paint.strokeWidth = stroke
        paint.style = if (stroke == 0f) Paint.Style.FILL else Paint.Style.STROKE
    }
    private fun blend(a: Int, b: Int, t: Float): Int {
        fun mix(x: Int, y: Int) = (x + (y - x) * t).toInt()
        return Color.rgb(mix(Color.red(a), Color.red(b)), mix(Color.green(a), Color.green(b)), mix(Color.blue(a), Color.blue(b)))
    }
    private fun loop(value: Float) = value - value.toInt()
    private fun path(init: Path.() -> Unit) = PathMeasure(Path().apply(init), false)

    private companion object {
        const val SIZE = 344f
        const val WHITE = -1
    }
}
