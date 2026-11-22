package com.galaxyssi.chat

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.RectF
import android.graphics.Shader
import kotlin.math.abs

internal class HealthAtlasHearingStoryView(context: Context) :
    HealthAtlasFunctionArt(context, HealthAtlasFunctionStory.HEARING) {
    private val ear = BitmapFactory.decodeResource(resources, R.drawable.health_atlas_ear_section)
    private val hair = BitmapFactory.decodeResource(resources, R.drawable.health_atlas_sensory_cochlear_hair)
    private val brain = BitmapFactory.decodeResource(resources, R.drawable.health_atlas_brain)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val surface = RectF(0f, 0f, SIZE, SIZE)
    private val artBounds = RectF()
    private val field = LinearGradient(0f, 0f, 0f, SIZE, 0xffe9f3f7.toInt(),
        0xfff9f1e6.toInt(), Shader.TileMode.CLAMP)
    private val mesh = FloatArray((COLUMNS + 1) * (ROWS + 1) * 2)
    private val line = Path()
    private val point = FloatArray(2)
    private val airInk = 0xff246681.toInt()
    private val motionInk = 0xff23736e.toInt()
    private val nerveInk = 0xff976021.toInt()
    private val lettering = 0xff203f4a.toInt()
    private val cochlea = Path().apply {
        moveTo(218f, 171f); cubicTo(225f, 138f, 278f, 139f, 281f, 171f)
        cubicTo(284f, 200f, 239f, 207f, 232f, 181f)
        cubicTo(226f, 157f, 270f, 155f, 266f, 177f)
        cubicTo(263f, 189f, 244f, 184f, 245f, 173f)
        cubicTo(246f, 165f, 255f, 165f, 255f, 173f)
    }
    private val coil = PathMeasure(cochlea, false)
    private val nerve = Path().apply {
        moveTo(45f, 246f); cubicTo(77f, 246f, 82f, 216f, 113f, 216f)
        cubicTo(148f, 216f, 144f, 245f, 172f, 245f)
        cubicTo(199f, 245f, 206f, 216f, 232f, 216f)
        cubicTo(262f, 216f, 271f, 245f, 300f, 245f)
    }
    private val neuralPath = PathMeasure(nerve, false)

    init { tag = "atlas-function-hearing-art" }

    override fun onDraw(canvas: Canvas) {
        val scale = minOf(width, height) / SIZE
        if (scale <= 0f) return
        val stage = HealthAtlasSoundStage.entries[story.chapter(phase)]
        val t = story.fraction(phase)
        canvas.save()
        canvas.translate((width - SIZE * scale) / 2f, (height - SIZE * scale) / 2f)
        canvas.scale(scale, scale)
        ink(lettering)
        paint.shader = field
        canvas.drawRoundRect(surface, 8f, 8f, paint)
        paint.shader = null
        when (stage) {
            HealthAtlasSoundStage.SOUND -> sound(canvas, t)
            HealthAtlasSoundStage.MIDDLE_EAR -> middle(canvas, t)
            HealthAtlasSoundStage.COCHLEA -> cochlearWave(canvas, t)
            HealthAtlasSoundStage.HAIR_CELL -> hairMotion(canvas, t)
            HealthAtlasSoundStage.NERVE -> nerveSignal(canvas, t)
        }
        canvas.restore()
    }

    private fun ear(canvas: Canvas) = bitmap(canvas, ear, 16f, 58f, 328f, 266f)

    private fun sound(canvas: Canvas, phase: Float) {
        ear(canvas)
        for (index in 0..5) {
            val distance = loop(phase * 1.7f + index / 6f)
            val x = 25f + distance * 121f
            val half = 12f + 6f * (1f - distance)
            line.rewind()
            line.moveTo(x, 165f - half)
            line.quadTo(x + 12f, 165f, x, 165f + half)
            ink(WHITE, 4f); canvas.drawPath(line, paint)
            ink(airInk, 2f); canvas.drawPath(line, paint)
        }
        annotation(canvas, 88f, 165f, 72f, 287f, R.string.health_atlas_hear_canal, airInk)
        annotation(canvas, 154f, 168f, 207f, 304f, R.string.health_atlas_hear_drum, airInk)
    }

    private fun middle(canvas: Canvas, phase: Float) {
        val motion = HealthAtlasSoundStage.oscillation(phase)
        bitmapMesh(canvas, ear, 16f, 58f, 312f, 208f) { x, y ->
            val drum = influence(x, .444f, .058f) * influence(y, .51f, .17f)
            val chain = influence(x, .56f, .15f) * influence(y, .45f, .14f)
            motion * (5.5f * drum + 4f * chain)
        }
        val shift = motion * 3f
        focus(canvas, 155f + shift, 170f, 17f, motionInk)
        focus(canvas, 192f + shift, 148f, 20f, motionInk)
        focus(canvas, 213f + shift, 163f, 9f, motionInk)
        annotation(canvas, 155f + shift, 170f, 73f, 287f, R.string.health_atlas_hear_drum, motionInk)
        annotation(canvas, 192f + shift, 147f, 189f, 30f, R.string.health_atlas_hear_ossicles, motionInk)
        annotation(canvas, 213f + shift, 163f, 255f, 286f, R.string.health_atlas_hear_window, motionInk)
    }

    private fun cochlearWave(canvas: Canvas, phase: Float) {
        ear(canvas)
        ink(WHITE, 3f); canvas.drawPath(cochlea, paint)
        ink(motionInk, 1.9f); canvas.drawPath(cochlea, paint)
        bead(canvas, coil, loop(phase * 1.14f), motionInk)
        annotation(canvas, 246f, 158f, 266f, 47f, R.string.health_atlas_hear_cochlea_label, motionInk)
        label(canvas, R.string.health_atlas_hear_basilar, 172f, 275f, 12f)
        line.rewind()
        for (step in 0..100) {
            val position = step / 100f
            val y = 300f + 12f * HealthAtlasSoundStage.packet(position, phase)
            if (step == 0) line.moveTo(31f, y) else line.lineTo(31f + position * 282f, y)
        }
        ink(motionInk, 2.7f); canvas.drawPath(line, paint)
        label(canvas, R.string.health_atlas_hear_base, 56f, 330f, 11f)
        label(canvas, R.string.health_atlas_hear_apex, 288f, 330f, 11f)
    }

    private fun hairMotion(canvas: Canvas, phase: Float) {
        val motion = HealthAtlasSoundStage.oscillation(phase)
        bitmapMesh(canvas, hair, 45f, 0f, 222f, 333f) { x, y ->
            val taper = ((.29f - y) / .14f).coerceIn(0f, 1f)
            12f * motion * taper * influence(x, .46f, .34f)
        }
        annotation(canvas, 149f + 7f * motion, 79f, 269f, 64f, R.string.health_atlas_hear_bundle, motionInk)
        annotation(canvas, 160f, 272f, 56f, 306f, R.string.health_atlas_hear_synapse, nerveInk)
        if (motion > 0f) {
            val departure = 15f * motion
            ink(0xfff1a337.toInt())
            canvas.drawCircle(165f, 264f + departure, 3.5f, paint)
            canvas.drawCircle(176f, 268f + departure, 2.5f, paint)
        }
    }

    private fun nerveSignal(canvas: Canvas, phase: Float) {
        bitmap(canvas, brain, 70f, 11f, 274f, 215f)
        ink(nerveInk, 3f); canvas.drawPath(nerve, paint)
        for (index in 0..3) bead(canvas, neuralPath, loop(phase * 1.8f + index / 4f), nerveInk)
        listOf(45f to 246f, 172f to 245f, 300f to 245f).forEach { (x, y) ->
            focus(canvas, x, y, 7f, nerveInk)
        }
        label(canvas, R.string.health_atlas_hear_cochlea_label, 45f, 281f, 11.5f)
        label(canvas, R.string.health_atlas_hear_relays, 172f, 281f, 11.5f)
        label(canvas, R.string.health_atlas_hear_cortex, 289f, 281f, 11.5f)
        label(canvas, R.string.health_atlas_hear_signal, 172f, 315f, 12.5f)
    }

    private fun bitmap(canvas: Canvas, source: Bitmap, l: Float, t: Float, r: Float, b: Float) {
        artBounds.set(l, t, r, b)
        ink(WHITE); canvas.drawBitmap(source, null, artBounds, paint)
    }
    private inline fun bitmapMesh(canvas: Canvas, source: Bitmap, x: Float, y: Float,
        width: Float, height: Float, shift: (Float, Float) -> Float) {
        var i = 0
        for (row in 0..ROWS) {
            val dy = row / ROWS.toFloat()
            for (col in 0..COLUMNS) {
                val dx = col / COLUMNS.toFloat()
                mesh[i++] = x + width * dx + shift(dx, dy)
                mesh[i++] = y + height * dy
            }
        }
        ink(WHITE); canvas.drawBitmapMesh(source, COLUMNS, ROWS, mesh, 0, null, 0, paint)
    }
    private fun bead(canvas: Canvas, route: PathMeasure, t: Float, color: Int) {
        if (!route.getPosTan(route.length * t, point, null)) return
        ink(WHITE); canvas.drawCircle(point[0], point[1], 6f, paint)
        ink(color); canvas.drawCircle(point[0], point[1], 3.4f, paint)
    }
    private fun focus(canvas: Canvas, x: Float, y: Float, radius: Float, color: Int) {
        ink(WHITE, 3f); canvas.drawCircle(x, y, radius, paint)
        ink(color, 1.4f); canvas.drawCircle(x, y, radius, paint)
    }
    private fun annotation(canvas: Canvas, x: Float, y: Float, center: Float, baseline: Float, text: Int, color: Int) {
        val endpoint = if (baseline > y) baseline - 15f else baseline + 6f
        ink(WHITE, 2.8f); canvas.drawLine(x, y, center, endpoint, paint)
        ink(color, 1.3f); canvas.drawLine(x, y, center, endpoint, paint)
        ink(color); canvas.drawCircle(x, y, 2.7f, paint)
        label(canvas, text, center, baseline, 11.5f)
    }
    private fun label(canvas: Canvas, id: Int, center: Float, baseline: Float, size: Float) {
        val text = context.getString(id)
        ink(lettering)
        paint.textSize = size
        canvas.drawText(text, center - paint.measureText(text) / 2f, baseline, paint)
    }
    private fun ink(color: Int, stroke: Float = 0f) {
        paint.color = color
        paint.strokeWidth = stroke
        paint.style = if (stroke == 0f) Paint.Style.FILL else Paint.Style.STROKE
    }
    private fun loop(value: Float) = value - value.toInt()
    private fun influence(value: Float, center: Float, radius: Float): Float =
        (1f - abs(value - center) / radius).coerceIn(0f, 1f)

    private companion object {
        const val COLUMNS = 28
        const val ROWS = 28
        const val WHITE = -1
        const val SIZE = 344f
    }
}
