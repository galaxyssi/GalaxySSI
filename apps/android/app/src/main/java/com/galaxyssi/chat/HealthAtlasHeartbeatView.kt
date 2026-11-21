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
import kotlin.math.abs
import kotlin.math.sin

internal class HealthAtlasHeartbeatView(context: Context) : HealthAtlasFunctionArt(context, HealthAtlasFunctionStory.HEARTBEAT) {
    private val art = BitmapFactory.decodeResource(resources, R.drawable.health_atlas_heart_section)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val stageBounds = RectF(0f, 0f, FRAME, FRAME)
    private val backdrop = LinearGradient(0f, 0f, 0f, FRAME, 0xffe8f2f6.toInt(), 0xfff8eeee.toInt(), Shader.TileMode.CLAMP)
    private val glyph = Path()
    private val position = FloatArray(2)
    private val tangent = FloatArray(2)
    private val mesh = FloatArray((MESH + 1) * (MESH + 1) * 2)
    private val blue = 0xff286ca0.toInt()
    private val rose = 0xffab304c.toInt()
    private val rightFill = path {
        moveTo(368f, 200f); cubicTo(361f, 310f, 352f, 355f, 375f, 441f)
        cubicTo(387f, 477f, 444f, 506f, 458f, 568f); cubicTo(477f, 635f, 407f, 654f, 451f, 707f)
        cubicTo(477f, 740f, 523f, 813f, 564f, 913f)
    }
    private val leftFill = path {
        moveTo(1083f, 512f); cubicTo(1024f, 507f, 966f, 488f, 906f, 495f)
        cubicTo(828f, 507f, 811f, 583f, 837f, 628f); cubicTo(844f, 651f, 874f, 660f, 859f, 690f)
        cubicTo(841f, 726f, 768f, 819f, 747f, 918f)
    }
    private val rightOut = path {
        moveTo(555f, 895f); cubicTo(526f, 765f, 567f, 719f, 593f, 611f)
        cubicTo(608f, 531f, 583f, 465f, 618f, 404f); cubicTo(643f, 359f, 708f, 339f, 782f, 337f)
    }
    private val leftOutFront = path {
        moveTo(739f, 911f); cubicTo(705f, 832f, 700f, 741f, 713f, 661f)
        cubicTo(719f, 617f, 701f, 571f, 705f, 466f)
    }
    // The pulmonary trunk occludes the intervening section of the aorta.
    private val leftOutArch = path {
        moveTo(695f, 293f); cubicTo(700f, 235f, 747f, 176f, 793f, 171f)
        cubicTo(826f, 165f, 816f, 116f, 823f, 69f)
    }
    private val shortToRight = path {
        moveTo(454f, 565f); cubicTo(472f, 623f, 415f, 650f, 451f, 707f)
        cubicTo(469f, 738f, 529f, 817f, 563f, 903f)
    }
    private val shortToLeft = path {
        moveTo(855f, 544f); cubicTo(814f, 590f, 875f, 652f, 860f, 693f)
        cubicTo(834f, 748f, 765f, 823f, 752f, 908f)
    }
    private val rightLabel = context.getString(R.string.health_atlas_beat_low)
    private val leftLabel = context.getString(R.string.health_atlas_beat_high)

    init { tag = "atlas-function-heartbeat-art" }

    override fun onDraw(canvas: Canvas) {
        val stage = HealthAtlasBeatStage.entries[story.chapter(phase)]
        val time = story.fraction(phase)
        val contraction = stage.ventricularNarrowing(time)
        val scale = minOf(width, height) / FRAME
        if (scale <= 0f) return
        canvas.save()
        canvas.translate((width - FRAME * scale) / 2f, (height - FRAME * scale) / 2f)
        canvas.scale(scale, scale)
        ink(0xffe8f2f6.toInt())
        paint.shader = backdrop
        canvas.drawRoundRect(stageBounds, 8f, 8f, paint)
        paint.shader = null
        canvas.save()
        canvas.translate(4f, 5f)
        canvas.scale(336f / ART_SIZE, 336f / ART_SIZE)
        val atrialSqueeze = if (stage == HealthAtlasBeatStage.ATRIAL_SQUEEZE) sin(time * Math.PI).toFloat() else 0f
        drawHeart(canvas, contraction, atrialSqueeze)
        when (stage) {
            HealthAtlasBeatStage.FILLING -> {
                stream(canvas, rightFill, blue, time, contraction)
                stream(canvas, leftFill, rose, time, contraction)
            }
            HealthAtlasBeatStage.ATRIAL_SQUEEZE -> {
                stream(canvas, shortToRight, blue, time, contraction)
                stream(canvas, shortToLeft, rose, time, contraction)
            }
            HealthAtlasBeatStage.EJECTION -> {
                stream(canvas, rightOut, blue, time, contraction)
                stream(canvas, leftOutFront, rose, time, contraction)
                stream(canvas, leftOutArch, rose, (time - .45f) / .55f, contraction)
            }
            else -> Unit
        }
        HealthAtlasValve.entries.forEach { valve ->
            val open = stage.valveOpenness(valve, time)
            val active = if (stage == HealthAtlasBeatStage.PRESSURE_RISE && valve.openAt(0) ||
                stage == HealthAtlasBeatStage.RELAXATION && valve.openAt(2)) (1f - time) * 21f else 0f
            gate(canvas, valve, open, contraction, active)
        }
        canvas.restore()
        legend(canvas, FRAME / 4f, rightLabel, blue)
        legend(canvas, FRAME * .75f, leftLabel, rose)
        canvas.restore()
    }

    private fun drawHeart(canvas: Canvas, contraction: Float, atrialSqueeze: Float) {
        var i = 0
        for (row in 0..MESH) {
            val y = row * ART_SIZE / MESH
            for (col in 0..MESH) {
                val x = col * ART_SIZE / MESH
                mesh[i++] = warpedX(x, y, contraction)
                val atrialMask = (1f - abs(y - 527f) / 132f).coerceIn(0f, 1f)
                val chamberMask = maxOf(0f, 1f - abs(x - 426f) / 135f, 1f - abs(x - 850f) / 135f)
                mesh[i++] = warpedY(y, contraction) + (527f - y) * atrialMask * chamberMask * atrialSqueeze * .55f
            }
        }
        ink(0xffffffff.toInt())
        canvas.drawBitmapMesh(art, MESH, MESH, mesh, 0, null, 0, paint)
    }

    private fun weight(y: Float) = ((y - 662f) / 390f).coerceIn(0f, 1f)
    private fun warpedX(x: Float, y: Float, amount: Float) = x + (720f - x) * weight(y) * amount * .19f
    private fun warpedY(y: Float, amount: Float) = y - weight(y) * amount * 64f

    private fun stream(canvas: Canvas, route: PathMeasure, color: Int, time: Float, contraction: Float) {
        val progress = ((time - .11f) / .78f).coerceIn(0f, 1f)
        for (i in 0..4) {
            val distance = progress * 1.56f - i * .137f
            if (distance <= 0f || distance >= 1f) continue
            route.getPosTan(distance * route.length, position, tangent)
            val x = warpedX(position[0], position[1], contraction)
            val y = warpedY(position[1], contraction)
            val dx = tangent[0]
            val dy = tangent[1]
            glyph.rewind()
            glyph.moveTo(x - 14f * dx + 11f * dy, y - 14f * dy - 11f * dx)
            glyph.lineTo(x + 7f * dx, y + 7f * dy)
            glyph.lineTo(x - 14f * dx - 11f * dy, y - 14f * dy + 11f * dx)
            ink(0xfff8fcff.toInt(), 14f)
            canvas.drawPath(glyph, paint)
            ink(color, 8f)
            canvas.drawPath(glyph, paint)
        }
    }

    private fun gate(canvas: Canvas, valve: HealthAtlasValve, openness: Float, contraction: Float, emphasis: Float) {
        val px = valve.marker.x * ART_SIZE
        val py = valve.marker.y * ART_SIZE
        val x = warpedX(px, py, contraction)
        val y = warpedY(py, contraction)
        canvas.save()
        canvas.translate(x, y)
        if (!valve.openAt(0)) canvas.rotate(180f)
        ink(0xff263d49.toInt())
        paint.alpha = 156
        canvas.drawCircle(0f, 0f, 42f, paint)
        ink(if (openness > .1f) 0xff17826b.toInt() else 0xff394d59.toInt(), 5f)
        canvas.drawCircle(0f, 0f, 43f + emphasis, paint)
        glyph.rewind()
        val spread = 27f * openness
        val tilt = openness * 25f
        glyph.moveTo(-28f, -10f); glyph.lineTo(-spread, 10f + tilt)
        glyph.moveTo(28f, -10f); glyph.lineTo(spread, 10f + tilt)
        ink(0xfffff9e7.toInt(), 8f)
        canvas.drawPath(glyph, paint)
        canvas.restore()
    }

    private fun legend(canvas: Canvas, center: Float, text: String, color: Int) {
        ink(0xff213d4d.toInt())
        paint.textSize = 11.5f
        val start = center - (paint.measureText(text) + 13f) / 2f
        canvas.drawText(text, start + 13f, 329f, paint)
        ink(color)
        canvas.drawCircle(start + 3.5f, 325f, 3.5f, paint)
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
        const val MESH = 24
    }
}
