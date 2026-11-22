package com.galaxyssi.chat

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.RectF
import android.graphics.Shader

internal class HealthAtlasNephronStoryView(context: Context) :
    HealthAtlasFunctionArt(context, HealthAtlasFunctionStory.NEPHRON) {
    private val nephron = BitmapFactory.decodeResource(resources, R.drawable.health_atlas_nephron)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val bounds = RectF(0f, 0f, FRAME, FRAME)
    private val art = RectF(0f, 0f, 1173f, 1341f)
    private val field = LinearGradient(0f, 0f, 0f, FRAME, 0xffecf5f6.toInt(), 0xfffaf1e4.toInt(), Shader.TileMode.CLAMP)
    private val glyph = Path()
    private val point = FloatArray(2)
    private val tangent = FloatArray(2)
    private val blood = 0xffa84554.toInt()
    private val fluid = 0xff19796f.toInt()
    private val crosses = 0xff355f9e.toInt()
    private val salt = 0xff98601c.toInt()
    private val secreted = 0xff76508e.toInt()
    private val labelInk = 0xff27424c.toInt()

    private val throughGlomerulus = path {
        moveTo(87f, 110f); cubicTo(160f, 108f, 171f, 193f, 234f, 205f)
        cubicTo(327f, 212f, 349f, 232f, 332f, 277f)
        cubicTo(297f, 335f, 233f, 302f, 222f, 259f)
        cubicTo(196f, 192f, 124f, 205f, 89f, 269f)
    }
    private val filter = path {
        moveTo(304f, 274f); cubicTo(335f, 297f, 344f, 336f, 375f, 324f)
        quadTo(397f, 313f, 420f, 306f)
    }
    private val proximal = path {
        moveTo(382f, 306f); cubicTo(407f, 272f, 446f, 293f, 408f, 378f)
        cubicTo(391f, 427f, 440f, 455f, 477f, 398f)
        cubicTo(507f, 360f, 551f, 400f, 530f, 444f)
        cubicTo(510f, 471f, 479f, 487f, 501f, 541f)
    }
    private val returnToBlood = path {
        moveTo(435f, 425f); cubicTo(413f, 465f, 364f, 477f, 304f, 490f)
    }
    private val periProximal = path {
        moveTo(271f, 434f); cubicTo(283f, 455f, 296f, 482f, 315f, 497f)
        quadTo(344f, 523f, 372f, 525f)
    }
    private val periProximalLine = segment(periProximal)
    private val loop = path {
        moveTo(500f, 531f); cubicTo(533f, 642f, 496f, 794f, 514f, 913f)
        cubicTo(535f, 1027f, 481f, 1196f, 571f, 1209f)
        cubicTo(659f, 1223f, 648f, 1030f, 655f, 937f)
        cubicTo(652f, 830f, 675f, 753f, 659f, 644f); lineTo(655f, 550f)
    }
    private val waterFromLoop = path {
        moveTo(511f, 765f); quadTo(487f, 743f, 435f, 739f)
    }
    private val saltFromLoop = path {
        moveTo(663f, 821f); quadTo(704f, 805f, 763f, 804f)
    }
    private val distal = path {
        moveTo(654f, 552f); cubicTo(642f, 477f, 692f, 424f, 742f, 392f)
        cubicTo(792f, 354f, 724f, 346f, 752f, 310f)
        cubicTo(781f, 288f, 802f, 349f, 817f, 316f)
        cubicTo(826f, 291f, 792f, 259f, 812f, 228f)
        cubicTo(856f, 206f, 832f, 291f, 868f, 298f)
        cubicTo(896f, 302f, 889f, 257f, 901f, 255f)
        cubicTo(929f, 247f, 919f, 296f, 960f, 311f); quadTo(997f, 330f, 990f, 390f)
    }
    private val intoDistal = path {
        moveTo(1081f, 207f); cubicTo(1024f, 186f, 930f, 164f, 908f, 257f)
    }
    private val periDistal = path {
        moveTo(1001f, 165f); cubicTo(1035f, 176f, 1077f, 193f, 1105f, 221f)
    }
    private val periDistalLine = segment(periDistal)
    private val drain = path {
        moveTo(990f, 341f); cubicTo(990f, 641f, 981f, 866f, 994f, 1127f); lineTo(992f, 1228f)
    }
    private val waterFromDuct = path {
        moveTo(987f, 850f); quadTo(926f, 828f, 870f, 836f)
    }

    init { tag = "atlas-function-nephron-art" }

    override fun onDraw(canvas: Canvas) {
        val scale = minOf(width, height) / FRAME
        if (scale <= 0f) return
        val stage = HealthAtlasNephronStage.entries[story.chapter(phase)]
        val t = story.fraction(phase)
        canvas.save()
        canvas.translate((width - FRAME * scale) / 2f, (height - FRAME * scale) / 2f)
        canvas.scale(scale, scale)
        ink(WHITE); paint.shader = field
        canvas.drawRoundRect(bounds, 8f, 8f, paint)
        paint.shader = null
        canvas.save()
        val cutaway = stage == HealthAtlasNephronStage.FILTER || stage == HealthAtlasNephronStage.LOOP
        if (cutaway) {
            canvas.translate(96f, 2f)
            canvas.scale(.13f, .13f)
        } else {
            canvas.translate(55f, 17f)
            canvas.scale(.20f, .20f)
        }
        canvas.drawBitmap(nephron, null, art, paint)
        if (stage == HealthAtlasNephronStage.PROXIMAL) vessel(canvas, periProximalLine, periProximal, t)
        if (stage == HealthAtlasNephronStage.DISTAL) vessel(canvas, periDistalLine, periDistal, t)
        for (route in stage.routes) {
            when (route) {
                HealthAtlasNephronRoute.BLOOD -> stream(canvas, throughGlomerulus, blood, t, 5)
                HealthAtlasNephronRoute.FILTER -> stream(canvas, filter, crosses, t, 2)
                HealthAtlasNephronRoute.FILTRATE -> when (stage) {
                    HealthAtlasNephronStage.PROXIMAL -> stream(canvas, proximal, fluid, t, 5)
                    HealthAtlasNephronStage.LOOP -> stream(canvas, loop, fluid, t, 8)
                    HealthAtlasNephronStage.DISTAL -> stream(canvas, distal, fluid, t, 7)
                    else -> Unit
                }
                HealthAtlasNephronRoute.REABSORB -> stream(canvas, returnToBlood, crosses, t, 2)
                HealthAtlasNephronRoute.LOOP_WATER -> stream(canvas, waterFromLoop, crosses, t, 2)
                HealthAtlasNephronRoute.LOOP_SALT -> stream(canvas, saltFromLoop, salt, t, 2)
                HealthAtlasNephronRoute.SECRETE -> stream(canvas, intoDistal, secreted, t, 3)
                HealthAtlasNephronRoute.DUCT_WATER -> stream(canvas, waterFromDuct, crosses, t, 2)
                HealthAtlasNephronRoute.URINE -> stream(canvas, drain, salt, t, 7)
            }
        }
        canvas.restore()
        when (stage) {
            HealthAtlasNephronStage.FILTER -> filtrationBarrier(canvas, t)
            HealthAtlasNephronStage.PROXIMAL -> {
                label(canvas, R.string.health_atlas_nephron_story_capillary, 95f, 150f)
                legend(canvas, 84f, R.string.health_atlas_nephron_story_filtrate, fluid)
                legend(canvas, 249f, R.string.health_atlas_nephron_story_reabsorb, crosses)
            }
            HealthAtlasNephronStage.LOOP -> loopCutaway(canvas, t)
            HealthAtlasNephronStage.DISTAL -> {
                label(canvas, R.string.health_atlas_nephron_story_capillary, 246f, 29f)
                legend(canvas, 84f, R.string.health_atlas_nephron_story_filtrate, fluid)
                legend(canvas, 243f, R.string.health_atlas_nephron_story_secretion, secreted)
            }
            HealthAtlasNephronStage.COLLECT -> {
                label(canvas, R.string.health_atlas_nephron_story_water, 215f, 173f, crosses)
                legend(canvas, 220f, R.string.health_atlas_nephron_story_urine, salt)
            }
        }
        canvas.restore()
    }

    private fun filtrationBarrier(canvas: Canvas, t: Float) {
        rounded(canvas, 10f, 178f, 334f, 336f, 0xfffdfbf7.toInt())
        rounded(canvas, 121f, 189f, 321f, 229f, 0xfff0cece.toInt())
        rounded(canvas, 121f, 276f, 321f, 319f, 0xffd9eee9.toInt())
        for (index in 0..6) {
            val x = 123f + 29f * index
            rounded(canvas, x, 232f, x + 23f, 243f, 0xffc57e81.toInt())
            rounded(canvas, x + 1f, 253f, x + 24f, 272f, 0xff80b9ad.toInt())
            if (index < 6) {
                ink(fluid, 1.4f)
                canvas.drawLine(x + 24f, 260f, x + 30f, 260f, paint)
            }
        }
        rounded(canvas, 121f, 245f, 321f, 251f, 0xffdfbb89.toInt())
        val cellX = 137f + 109f * t
        ink(blood)
        canvas.drawOval(cellX - 12f, 199f, cellX + 12f, 215f, paint)
        ink(0xffee8d94.toInt(), 2f)
        canvas.drawOval(cellX - 6f, 204f, cellX + 6f, 210f, paint)
        for (index in 0..2) {
            ink(secreted)
            canvas.drawCircle(270f + index * 10f, 206f + (index % 2) * 7f, 4f, paint)
            val x = 148f + index * 58f
            transfer(canvas, x, 220f, x, 297f, crosses, t + index * .12f)
        }
        label(canvas, R.string.health_atlas_nephron_story_blood, 64f, 211f)
        label(canvas, R.string.health_atlas_nephron_barrier_endothelium, 64f, 241f, blood)
        label(canvas, R.string.health_atlas_nephron_barrier_basement, 64f, 254f, salt)
        label(canvas, R.string.health_atlas_nephron_barrier_slits, 64f, 269f, fluid)
        label(canvas, R.string.health_atlas_nephron_story_filtrate, 64f, 302f)
    }

    private fun loopCutaway(canvas: Canvas, t: Float) {
        rounded(canvas, 10f, 178f, 334f, 336f, 0xfffdfbf7.toInt())
        for (i in 0..3) {
            ink(0xffbda176.toInt())
            paint.alpha = 24 + i * 22
            canvas.drawRect(31f, 204f + i * 23f, 313f, 227f + i * 23f, paint)
        }
        glyph.rewind()
        glyph.moveTo(128f, 208f)
        glyph.lineTo(128f, 276f)
        glyph.cubicTo(128f, 313f, 215f, 313f, 215f, 276f)
        glyph.lineTo(215f, 208f)
        ink(0xff84b7ab.toInt(), 14f); canvas.drawPath(glyph, paint)
        ink(0xffeaf5f3.toInt(), 8f); canvas.drawPath(glyph, paint)
        for (i in 0..1) {
            val y = 230f + i * 31f
            transfer(canvas, 121f, y, 74f, y, crosses, t + i * .25f)
            transfer(canvas, 223f, y, 269f, y, salt, t + i * .25f)
        }
        label(canvas, R.string.health_atlas_nephron_loop_descending, 87f, 197f)
        label(canvas, R.string.health_atlas_nephron_loop_ascending, 254f, 197f)
        label(canvas, R.string.health_atlas_nephron_story_water, 82f, 321f, crosses)
        label(canvas, R.string.health_atlas_nephron_story_salt, 263f, 321f, salt)
        label(canvas, R.string.health_atlas_nephron_loop_gradient, 172f, 273f, salt)
    }

    private fun rounded(canvas: Canvas, left: Float, top: Float, right: Float, bottom: Float, color: Int) {
        ink(color)
        canvas.drawRoundRect(left, top, right, bottom, 3f, 3f, paint)
    }

    private fun transfer(canvas: Canvas, x: Float, y: Float, endX: Float, endY: Float, color: Int, t: Float) {
        val horizontal = y == endY
        val end = if (horizontal) endX - 6f * kotlin.math.sign(endX - x) else endY - 6f
        ink(color, 1.7f)
        canvas.drawLine(x, y, endX, endY, paint)
        if (horizontal) {
            canvas.drawLine(endX, endY, end, endY - 4f, paint)
            canvas.drawLine(endX, endY, end, endY + 4f, paint)
        } else {
            canvas.drawLine(endX, endY, endX - 4f, end, paint)
            canvas.drawLine(endX, endY, endX + 4f, end, paint)
        }
        val time = (t * 1.27f) % 1f
        ink(WHITE); canvas.drawCircle(x + (endX - x) * time, y + (endY - y) * time, 4.2f, paint)
        ink(color); canvas.drawCircle(x + (endX - x) * time, y + (endY - y) * time, 3f, paint)
    }

    private fun vessel(canvas: Canvas, outline: Path, route: PathMeasure, t: Float) {
        ink(0xffdf9f9c.toInt(), 37f)
        canvas.drawPath(outline, paint)
        stream(canvas, route, blood, t, 2)
    }
    private fun stream(canvas: Canvas, route: PathMeasure, color: Int, time: Float, count: Int) {
        repeat(count) { index ->
            val p = time * 1.3f + index / count.toFloat()
            if (!route.getPosTan(route.length * (p - p.toInt()), point, tangent)) return@repeat
            val x = point[0]; val y = point[1]
            val dx = tangent[0]; val dy = tangent[1]
            glyph.rewind()
            glyph.moveTo(x - 14f * dx + 10f * dy, y - 14f * dy - 10f * dx)
            glyph.lineTo(x + 7f * dx, y + 7f * dy)
            glyph.lineTo(x - 14f * dx - 10f * dy, y - 14f * dy + 10f * dx)
            ink(WHITE, 13f); canvas.drawPath(glyph, paint)
            ink(color, 7.5f); canvas.drawPath(glyph, paint)
        }
    }
    private fun label(canvas: Canvas, text: Int, x: Float, y: Float, color: Int = labelInk) {
        val value = context.getString(text)
        ink(color); paint.textSize = 11.5f
        canvas.drawText(value, x - paint.measureText(value) / 2f, y, paint)
    }
    private fun legend(canvas: Canvas, center: Float, text: Int, color: Int) {
        paint.textSize = 11.5f
        val dot = center - (paint.measureText(context.getString(text)) + 13f) / 2f + 3.5f
        ink(color); canvas.drawCircle(dot, 322f, 3.5f, paint)
        label(canvas, text, center + 6f, 326f)
    }
    private fun ink(color: Int, stroke: Float = 0f) {
        paint.color = color
        paint.strokeWidth = stroke
        paint.style = if (stroke == 0f) Paint.Style.FILL else Paint.Style.STROKE
    }
    private fun path(init: Path.() -> Unit) = PathMeasure(Path().apply(init), false)
    private fun segment(route: PathMeasure) = Path().also { route.getSegment(0f, route.length, it, true) }

    private companion object {
        const val WHITE = -1
        const val FRAME = 344f
    }
}
