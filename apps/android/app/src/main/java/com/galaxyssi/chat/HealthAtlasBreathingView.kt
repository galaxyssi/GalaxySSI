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
import kotlin.math.atan2

internal class HealthAtlasBreathingView(context: Context) :
    HealthAtlasFunctionArt(context, HealthAtlasFunctionStory.BREATHING) {
    private val lungs = BitmapFactory.decodeResource(resources, R.drawable.health_atlas_lungs)
    private val alveolus = BitmapFactory.decodeResource(resources, R.drawable.health_atlas_alveolus)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val bounds = RectF(0f, 0f, FRAME, FRAME)
    private val rect = RectF()
    private val glyph = Path()
    private val pos = FloatArray(2)
    private val tangent = FloatArray(2)
    private val sky = LinearGradient(0f, 0f, 0f, FRAME, 0xffeaf4f6.toInt(), 0xfffaf1ee.toInt(), Shader.TileMode.CLAMP)
    private val teal = 0xff087a78.toInt()
    private val gold = 0xff92531d.toInt()
    private val textInk = 0xff234450.toInt()
    private val toRightLung = path {
        moveTo(172f, 43f); lineTo(172f, 133f)
        cubicTo(172f, 143f, 159f, 148f, 151f, 158f)
    }
    private val toLeftLung = path {
        moveTo(172f, 43f); lineTo(172f, 133f)
        cubicTo(172f, 143f, 185f, 148f, 193f, 158f)
    }
    private val blood = path {
        moveTo(115f, 103f); cubicTo(183f, 206f, 212f, 261f, 171f, 351f)
        cubicTo(147f, 415f, 134f, 484f, 126f, 548f)
        cubicTo(98f, 593f, 79f, 638f, 113f, 701f)
        cubicTo(155f, 768f, 122f, 812f, 157f, 871f)
        cubicTo(183f, 931f, 253f, 944f, 293f, 958f)
        cubicTo(365f, 971f, 390f, 1037f, 476f, 1081f)
        cubicTo(547f, 1122f, 610f, 1096f, 678f, 1053f)
        cubicTo(750f, 1012f, 804f, 982f, 866f, 1026f)
        cubicTo(945f, 1093f, 1059f, 1072f, 1160f, 1172f)
    }
    private val oxygen = path {
        moveTo(482f, 817f); cubicTo(445f, 866f, 422f, 941f, 411f, 1003f); lineTo(395f, 1064f)
    }
    private val carbon = path {
        moveTo(625f, 819f); cubicTo(642f, 891f, 671f, 967f, 702f, 1011f); lineTo(724f, 1052f)
    }
    private val airLabel = context.getString(R.string.health_atlas_breathe_alveolar_air)
    private val diaphragmLabel = context.getString(R.string.health_atlas_breathe_muscle)
    private val oxygenLabel = context.getString(R.string.health_atlas_breathe_oxygen)
    private val carbonLabel = context.getString(R.string.health_atlas_breathe_carbon)
    private val inhalingLabel = context.getString(R.string.health_atlas_breathe_air_in)
    private val exhalingLabel = context.getString(R.string.health_atlas_breathe_air_out)

    init { tag = "atlas-function-breathing-art" }

    override fun onDraw(canvas: Canvas) {
        val scale = minOf(width, height) / FRAME
        if (scale <= 0f) return
        val stage = HealthAtlasBreathingStage.entries[story.chapter(phase)]
        val fraction = story.fraction(phase)
        val zoom = stage.closeUp(fraction)
        val expansion = stage.expansion(fraction)
        canvas.save()
        canvas.translate((width - FRAME * scale) / 2f, (height - FRAME * scale) / 2f)
        canvas.scale(scale, scale)
        ink(textInk)
        paint.shader = sky
        canvas.drawRoundRect(bounds, 8f, 8f, paint)
        paint.shader = null
        if (zoom < 1f) {
            val layer = canvas.saveLayerAlpha(0f, 0f, FRAME, FRAME, ((1f - zoom) * 255).toInt())
            whole(canvas, expansion, phase, stage.exhales)
            canvas.restoreToCount(layer)
        }
        if (zoom > 0f) {
            val layer = canvas.saveLayerAlpha(0f, 0f, FRAME, FRAME, (zoom * 255).toInt())
            detail(canvas, zoom, phase)
            canvas.restoreToCount(layer)
        }
        canvas.restore()
    }

    private fun whole(canvas: Canvas, expansion: Float, time: Float, exhale: Boolean) {
        canvas.save()
        canvas.scale(1f + .077f * expansion, 1f + .045f * expansion, 172f, 38f)
        ink(WHITE)
        rect.set(49f, 38f, 295f, 284f)
        canvas.drawBitmap(lungs, null, rect, paint)
        for (i in 0..3) {
            val t = loop(time * 6f + i / 4f)
            // Both branches share the trachea. Draw it only once.
            val position = if (exhale) 1f - t else t
            arrow(canvas, toRightLung, position, teal, exhale, 3f)
            if (position > .78f) arrow(canvas, toLeftLung, position, teal, exhale, 3f)
        }
        canvas.restore()
        val down = expansion * 10f
        glyph.rewind()
        glyph.moveTo(42f, 310f + down)
        glyph.cubicTo(109f, 262f + down * 2.4f, 235f, 262f + down * 2.4f, 302f, 310f + down)
        ink(0xff85445a.toInt(), 3f)
        canvas.drawPath(glyph, paint)
        label(canvas, diaphragmLabel, 172f, 331f, 12f)
        label(canvas, if (exhale) exhalingLabel else inhalingLabel, 172f, 23f, 13f)
    }

    private fun detail(canvas: Canvas, zoom: Float, time: Float) {
        canvas.save()
        val span = 54f + 232f * zoom
        canvas.translate(214f - 183f * zoom, 175f - 157f * zoom)
        canvas.scale(span / ART_SIZE, span / ART_SIZE)
        ink(WHITE)
        rect.set(0f, 0f, ART_SIZE, ART_SIZE)
        canvas.drawBitmap(alveolus, null, rect, paint)
        for (i in 0..6) {
            val t = loop(time * 3f + i / 7f)
            sample(blood, t)
            val angle = atan2(tangent[1], tangent[0]) * (180f / Math.PI.toFloat())
            canvas.save()
            canvas.translate(pos[0], pos[1])
            canvas.rotate(angle)
            ink(if (t < .42f) 0xffa64455.toInt() else 0xffc55455.toInt())
            canvas.drawOval(-35f, -17f, 35f, 17f, paint)
            ink(0xfff5a795.toInt(), 4f)
            canvas.drawOval(-35f, -17f, 35f, 17f, paint)
            canvas.drawLine(-13f, 0f, 13f, 0f, paint)
            canvas.restore()
        }
        // The two diffusion routes use the same clock, with opposite directions.
        for (i in 0..2) {
            val t = loop(time * 7f + i / 3f)
            arrow(canvas, oxygen, HealthAtlasGasExchange.position(HealthAtlasGas.OXYGEN, t), teal, false, 17f)
            arrow(canvas, carbon, HealthAtlasGasExchange.position(HealthAtlasGas.CARBON_DIOXIDE, t), gold, true, 17f)
        }
        canvas.restore()
        if (zoom > .8f) {
            label(canvas, airLabel, 162f, 158f, 13f)
            legend(canvas, 87f, oxygenLabel, teal)
            legend(canvas, 252f, carbonLabel, gold)
        }
    }

    private fun arrow(canvas: Canvas, route: PathMeasure, t: Float, color: Int, reverse: Boolean, size: Float) {
        sample(route, t)
        val x = pos[0]
        val y = pos[1]
        val dx = tangent[0] * if (reverse) -1f else 1f
        val dy = tangent[1] * if (reverse) -1f else 1f
        glyph.rewind()
        glyph.moveTo(x - (dx - dy) * size, y - (dy + dx) * size)
        glyph.lineTo(x + dx * size, y + dy * size)
        glyph.lineTo(x - (dx + dy) * size, y - (dy - dx) * size)
        ink(WHITE, size * 1.25f)
        canvas.drawPath(glyph, paint)
        ink(color, size * .66f)
        canvas.drawPath(glyph, paint)
    }

    private fun sample(route: PathMeasure, t: Float) { route.getPosTan(t * route.length, pos, tangent) }
    private fun loop(value: Float) = value - value.toInt()
    private fun legend(canvas: Canvas, center: Float, text: String, color: Int) {
        ink(textInk)
        paint.textSize = 11.5f
        val offset = (paint.measureText(text) + 13f) / 2f
        ink(color)
        canvas.drawCircle(center - offset + 4f, 324f, 3.5f, paint)
        label(canvas, text, center + 6f, 328f, 11.5f)
    }
    private fun label(canvas: Canvas, text: String, center: Float, baseline: Float, size: Float) {
        ink(textInk)
        paint.textSize = size
        canvas.drawText(text, center - paint.measureText(text) / 2f, baseline, paint)
    }
    private fun ink(color: Int, stroke: Float = 0f) {
        paint.color = color
        paint.strokeWidth = stroke
        paint.style = if (stroke == 0f) Paint.Style.FILL else Paint.Style.STROKE
    }
    private fun path(init: Path.() -> Unit) = PathMeasure(Path().apply(init), false)

    private companion object {
        const val FRAME = 344f
        const val ART_SIZE = 1254f
        const val WHITE = -1
    }
}
