package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.drawable.Drawable
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasDigestiveStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasFunctionArt(context, story) {
    private val isMeal = story == HealthAtlasFunctionStory.DIGESTION
    private val scenes = if (isMeal) HealthAtlasDigestionStage.meal else HealthAtlasDigestionStage.colon
    private val illustrations = mutableMapOf<Int, Drawable>()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val bounds = RectF(0f, 0f, FRAME, FRAME)
    private val field = LinearGradient(0f, 0f, 0f, FRAME, 0xffeaf5f5.toInt(), 0xfffff4e7.toInt(), Shader.TileMode.CLAMP)
    private val stroke = Path()
    private val point = FloatArray(2)
    private val tangent = FloatArray(2)
    private val contents = 0xff9b5828.toInt()
    private val muscle = 0xffa54f67.toInt()
    private val blood = 0xffa73552.toInt()
    private val lymph = 0xff087966.toInt()
    private val water = 0xff27669d.toInt()
    private val lettering = 0xff253f48.toInt()

    // The vector cutaways and their motion paths share the original 360 x 280 coordinate space.
    private val swallow = path {
        moveTo(100f, 144f); cubicTo(140f, 127f, 203f, 127f, 231f, 141f)
        cubicTo(256f, 149f, 271f, 165f, 278f, 180f)
    }
    private val downEsophagus = path {
        moveTo(180f, 48f); quadTo(176f, 64f, 176f, 82f); quadTo(169f, 106f, 174f, 129f)
        cubicTo(182f, 146f, 189f, 172f, 195f, 195f); cubicTo(199f, 225f, 199f, 233f, 228f, 244f)
    }
    private val stomachExit = path {
        moveTo(223f, 156f); quadTo(169f, 196f, 110f, 180f); quadTo(89f, 172f, 62f, 194f)
    }
    private val smallBowel = path {
        moveTo(177f, 65f); quadTo(235f, 58f, 260f, 65f); cubicTo(294f, 78f, 293f, 115f, 272f, 153f)
        quadTo(247f, 199f, 190f, 201f); quadTo(135f, 194f, 110f, 211f)
    }
    private val bile = path {
        moveTo(203f, 73f); quadTo(209f, 87f, 211f, 101f); quadTo(214f, 121f, 239f, 129f); lineTo(257f, 134f)
    }
    private val enzymes = path {
        moveTo(121f, 151f); quadTo(168f, 151f, 185f, 148f); quadTo(203f, 144f, 225f, 139f); lineTo(257f, 134f)
    }
    // These paths terminate on the painted blood vessel and central lacteal, respectively.
    private val waterSoluble = path {
        moveTo(139f, 81f); cubicTo(137f, 98f, 137f, 126f, 152f, 145f)
        cubicTo(159f, 155f, 157f, 176f, 152f, 193f); cubicTo(145f, 224f, 122f, 227f, 85f, 237f)
    }
    private val dietaryFat = path {
        moveTo(191f, 95f); cubicTo(189f, 132f, 174f, 141f, 173f, 161f)
        cubicTo(170f, 201f, 170f, 232f, 125f, 241f); lineTo(113f, 241f)
    }
    private val colonEntry = path {
        moveTo(44f, 173f); cubicTo(58f, 171f, 67f, 178f, 82f, 185f); quadTo(90f, 183f, 83f, 164f)
    }
    private val ascending = path { moveTo(83f, 164f); lineTo(83f, 96f) }
    private val transverse = path { moveTo(117f, 57f); lineTo(222f, 57f) }
    private val descending = path { moveTo(270f, 101f); quadTo(274f, 153f, 261f, 178f) }
    private val colonFlow = path {
        moveTo(83f, 170f); lineTo(83f, 95f); quadTo(83f, 57f, 112f, 57f); lineTo(233f, 57f)
        quadTo(270f, 58f, 272f, 98f); lineTo(269f, 164f); quadTo(264f, 181f, 244f, 192f)
        quadTo(228f, 207f, 203f, 206f); quadTo(177f, 202f, 178f, 233f)
    }
    private val waterTracks = listOf(
        path { moveTo(84f, 122f); quadTo(119f, 118f, 134f, 107f) },
        path { moveTo(156f, 58f); quadTo(157f, 88f, 172f, 102f) },
        path { moveTo(271f, 136f); quadTo(239f, 139f, 223f, 148f) },
    )
    private val rectal = path {
        moveTo(125f, 62f); cubicTo(155f, 99f, 177f, 88f, 196f, 120f)
        quadTo(224f, 157f, 203f, 188f); quadTo(204f, 209f, 201f, 235f)
    }

    init { tag = if (isMeal) "atlas-function-meal-art" else "atlas-function-colon-art" }

    override fun onDraw(canvas: Canvas) {
        val scale = minOf(width, height) / FRAME
        if (scale <= 0) return
        val chapter = scenes[story.chapter(phase)]
        val t = story.fraction(phase)
        canvas.save()
        canvas.translate((width - FRAME * scale) / 2f, (height - FRAME * scale) / 2f)
        canvas.scale(scale, scale)
        ink(WHITE); paint.shader = field
        canvas.drawRoundRect(bounds, 8f, 8f, paint)
        paint.shader = null
        if (chapter == HealthAtlasDigestionStage.VILLUS) villus(canvas, t) else {
            canvas.save()
            canvas.translate(12f, 41f)
            canvas.scale(.89f, .89f)
            when (chapter) {
                HealthAtlasDigestionStage.SWALLOW -> {
                    picture(canvas, R.drawable.health_atlas_gut_mouth)
                    bolus(canvas, swallow, .03f + .93f * t, 9f)
                }
                HealthAtlasDigestionStage.PERISTALSIS -> {
                    picture(canvas, R.drawable.health_atlas_gut_esophagus)
                    squeeze(canvas, downEsophagus, (.91f * t - .13f).coerceAtLeast(0f), 14f, 27f, 5f)
                    bolus(canvas, downEsophagus, .04f + .92f * t, 7.5f)
                }
                HealthAtlasDigestionStage.STOMACH -> stomach(canvas, t)
                HealthAtlasDigestionStage.DUODENUM -> duodenum(canvas, t)
                HealthAtlasDigestionStage.CECUM -> {
                    picture(canvas, R.drawable.health_atlas_gut_large)
                    flow(canvas, colonEntry, contents, t, 3, 4f)
                }
                HealthAtlasDigestionStage.MIX -> mix(canvas, t)
                HealthAtlasDigestionStage.WATER -> recoverWater(canvas, t)
                HealthAtlasDigestionStage.PROPULSION -> {
                    picture(canvas, R.drawable.health_atlas_gut_large)
                    squeeze(canvas, colonFlow, (.96f * t - .085f).coerceAtLeast(0f), 14f, 26f, 9f)
                    bolus(canvas, colonFlow, .06f + .9f * t, 10f)
                }
                HealthAtlasDigestionStage.RECTUM -> {
                    picture(canvas, R.drawable.health_atlas_gut_rectum)
                    val advance = if (t < .58f) .52f + .24f * t else .66f + .66f * (t - .58f)
                    bolus(canvas, rectal, advance, 12f)
                    squeeze(canvas, rectal, .98f, 14f + 7f * t, 29f, 4.5f)
                }
                HealthAtlasDigestionStage.VILLUS -> Unit
            }
            canvas.restore()
        }
        labels(canvas, chapter)
        canvas.restore()
    }

    private fun picture(canvas: Canvas, id: Int, square: Boolean = false) {
        val drawable = illustrations.getOrPut(id) {
            requireNotNull(context.getDrawable(id)).mutate().apply { setBounds(0, 0, 360, if (square) 360 else 280) }
        }
        drawable.draw(canvas)
    }

    private fun stomach(canvas: Canvas, t: Float) {
        picture(canvas, R.drawable.health_atlas_gut_stomach)
        repeat(11) { index ->
            val angle = index * (2f * PI.toFloat() / 11f) + t * 10f
            val band = 12f + (index % 4) * 6f
            val radius = (4.3f - 2f * t) + (index % 3) * .7f
            dot(canvas, 232f + cos(angle) * band, 133f + sin(angle) * band * 1.15f, radius, contents)
        }
        if (t > .53f) flow(canvas, stomachExit, contents, (t - .53f) / .47f, 4, 3.4f)
        squeeze(canvas, stomachExit, t * .69f, 15f, 24f, 7f)
    }

    private fun duodenum(canvas: Canvas, t: Float) {
        picture(canvas, R.drawable.health_atlas_gut_duodenum)
        flow(canvas, bile, lymph, t, 3, 3.4f)
        flow(canvas, enzymes, water, t, 4, 3.4f)
        for (i in 0..5) {
            val progress = loop(t * 1.2f + i / 6f)
            if (!smallBowel.getPosTan(progress * smallBowel.length, point, null)) continue
            if (progress < .47f) dot(canvas, point[0], point[1], 6f, contents)
            else {
                dot(canvas, point[0] - 4f, point[1], 3.3f, contents)
                dot(canvas, point[0] + 3f, point[1] + 3f, 2.5f, contents)
            }
        }
    }

    private fun villus(canvas: Canvas, t: Float) {
        canvas.save()
        canvas.translate(4f, -16f)
        canvas.scale(.93f, .93f)
        picture(canvas, R.drawable.health_atlas_gut_jejunum, square = true)
        flow(canvas, waterSoluble, blood, t, 5, 4.3f)
        flow(canvas, dietaryFat, lymph, t, 4, 4.3f)
        canvas.restore()
    }

    private fun mix(canvas: Canvas, t: Float) {
        picture(canvas, R.drawable.health_atlas_gut_large)
        val phase = t * PI.toFloat() * 4f
        squeeze(canvas, ascending, .53f, 9f + 8f * (sin(phase) + 1f), 29f, 6f)
        squeeze(canvas, transverse, .38f, 9f + 8f * (sin(phase - 1.6f) + 1f), 29f, 6f)
        squeeze(canvas, descending, .57f, 9f + 8f * (sin(phase - 2.9f) + 1f), 29f, 6f)
        bolus(canvas, ascending, .55f + sin(phase) * .21f, 6f)
        bolus(canvas, transverse, .41f + sin(phase - 1.6f) * .19f, 6f)
        bolus(canvas, descending, .51f + sin(phase - 2.9f) * .21f, 6f)
    }

    private fun recoverWater(canvas: Canvas, t: Float) {
        picture(canvas, R.drawable.health_atlas_gut_large)
        waterTracks.forEach { flow(canvas, it, water, t, 3, 3.4f) }
        bolus(canvas, colonFlow, .20f + .19f * t, 9f - t * 3f)
        bolus(canvas, colonFlow, .53f + .15f * t, 8f - t * 3f)
    }

    private fun squeeze(canvas: Canvas, route: PathMeasure, t: Float, inside: Float, outer: Float, breadth: Float) {
        if (!route.getPosTan(t * route.length, point, tangent)) return
        val x = point[0]; val y = point[1]
        val nx = -tangent[1]; val ny = tangent[0]
        stroke.rewind()
        for (side in intArrayOf(-1, 1)) {
            stroke.moveTo(x + nx * side * outer - tangent[0] * breadth,
                y + ny * side * outer - tangent[1] * breadth)
            stroke.quadTo(x + nx * side * inside, y + ny * side * inside,
                x + nx * side * outer + tangent[0] * breadth,
                y + ny * side * outer + tangent[1] * breadth)
        }
        ink(0xfffae6dc.toInt(), 9f); canvas.drawPath(stroke, paint)
        ink(muscle, 4.4f); canvas.drawPath(stroke, paint)
    }

    private fun bolus(canvas: Canvas, route: PathMeasure, t: Float, radius: Float) {
        if (!route.getPosTan(t * route.length, point, null)) return
        val x = point[0]; val y = point[1]
        dot(canvas, x, y, radius, contents)
        dot(canvas, x - radius * .23f, y - radius * .22f, radius * .42f, 0xffedaf6f.toInt())
    }

    private fun flow(canvas: Canvas, route: PathMeasure, color: Int, t: Float, count: Int, size: Float) {
        repeat(count) { i ->
            val position = loop(t * 1.25f + i / count.toFloat())
            if (!route.getPosTan(route.length * position, point, tangent)) return@repeat
            val x = point[0]; val y = point[1]
            val dx = tangent[0]; val dy = tangent[1]
            stroke.rewind()
            stroke.moveTo(x - (dx - dy) * size, y - (dy + dx) * size)
            stroke.lineTo(x + dx * size, y + dy * size)
            stroke.lineTo(x - (dx + dy) * size, y - (dy - dx) * size)
            ink(WHITE, size * 1.22f); canvas.drawPath(stroke, paint)
            ink(color, size * .64f); canvas.drawPath(stroke, paint)
        }
    }

    private fun labels(canvas: Canvas, stage: HealthAtlasDigestionStage) {
        when (stage) {
            HealthAtlasDigestionStage.SWALLOW -> key(canvas, 172f, R.string.health_atlas_meal_bolus, contents)
            HealthAtlasDigestionStage.PERISTALSIS -> {
                key(canvas, 88f, R.string.health_atlas_meal_bolus, contents)
                key(canvas, 250f, R.string.health_atlas_meal_contraction, muscle)
            }
            HealthAtlasDigestionStage.STOMACH -> key(canvas, 172f, R.string.health_atlas_meal_chyme, contents)
            HealthAtlasDigestionStage.DUODENUM -> {
                key(canvas, 80f, R.string.health_atlas_meal_enzymes, water)
                key(canvas, 253f, R.string.health_atlas_meal_bile, lymph)
            }
            HealthAtlasDigestionStage.VILLUS -> {
                key(canvas, 92f, R.string.health_atlas_meal_blood, blood)
                key(canvas, 254f, R.string.health_atlas_meal_lymph, lymph)
            }
            HealthAtlasDigestionStage.WATER -> key(canvas, 172f, R.string.health_atlas_colon_story_water_key, water)
            else -> key(canvas, 172f, R.string.health_atlas_colon_story_contents, contents)
        }
    }

    private fun key(canvas: Canvas, center: Float, id: Int, color: Int) {
        val text = context.getString(id)
        paint.textSize = 11.5f
        val x = center - (paint.measureText(text) + 14f) / 2f
        dot(canvas, x + 4f, 321f, 3.6f, color)
        ink(lettering)
        canvas.drawText(text, x + 14f, 325f, paint)
    }
    private fun dot(canvas: Canvas, x: Float, y: Float, radius: Float, color: Int) {
        ink(color)
        canvas.drawCircle(x, y, radius, paint)
    }
    private fun ink(color: Int, width: Float = 0f) {
        paint.color = color
        paint.strokeWidth = width
        paint.style = if (width == 0f) Paint.Style.FILL else Paint.Style.STROKE
    }
    private fun loop(value: Float) = value - value.toInt()
    private fun path(init: Path.() -> Unit) = PathMeasure(Path().apply(init), false)

    private companion object {
        const val FRAME = 344f
        const val WHITE = -1
    }
}
