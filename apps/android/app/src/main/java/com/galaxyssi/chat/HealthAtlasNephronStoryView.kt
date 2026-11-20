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
        canvas.translate(55f, 17f)
        canvas.scale(.20f, .20f)
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
            HealthAtlasNephronStage.FILTER -> {
                label(canvas, R.string.health_atlas_nephron_story_glomerulus, 84f, 122f)
                legend(canvas, 78f, R.string.health_atlas_nephron_story_blood, blood)
                legend(canvas, 231f, R.string.health_atlas_nephron_story_filtrate, crosses)
            }
            HealthAtlasNephronStage.PROXIMAL -> {
                label(canvas, R.string.health_atlas_nephron_story_capillary, 95f, 150f)
                legend(canvas, 84f, R.string.health_atlas_nephron_story_filtrate, fluid)
                legend(canvas, 249f, R.string.health_atlas_nephron_story_reabsorb, crosses)
            }
            HealthAtlasNephronStage.LOOP -> {
                label(canvas, R.string.health_atlas_nephron_story_water, 113f, 168f, crosses)
                label(canvas, R.string.health_atlas_nephron_story_salt, 236f, 200f, salt)
                legend(canvas, 172f, R.string.health_atlas_nephron_story_filtrate, fluid)
            }
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
