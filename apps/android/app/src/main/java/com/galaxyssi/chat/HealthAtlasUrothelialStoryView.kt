package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader
import com.galaxyssi.chat.HealthAtlasUrothelialCellAssignment as Lesson
import com.galaxyssi.chat.R.string
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasUrothelialStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val edge = 0xff995b6e
    private val sealedEdge = 0xff287565
    private val lumenFill = shade(57f, 211f, 0xffe8f6f4, 0xffc4e3df)
    private val umbrellaFill = shade(123f, 241f, 0xffffdfc6, 0xffdd9791)
    private val middleFill = shade(165f, 280f, 0xfff5ccba, 0xffcb8d9a)
    private val basalFill = shade(213f, 310f, 0xffeeb4ab, 0xffad788d)
    private val outline = Path()
    private val x = FloatArray(SAMPLES + 1)
    private val foldY = FloatArray(SAMPLES + 1)
    private val surfaceY = FloatArray(SAMPLES + 1)
    private val foldShape = FloatArray(SAMPLES + 1) { cos(it * 4.0 * PI / SAMPLES).toFloat() }
    private val domeShape = FloatArray(SAMPLES + 1) {
        sin((it % UMBRELLA_SPAN) * PI / UMBRELLA_SPAN).toFloat()
    }

    init { tag = Lesson.ART_TAG }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val stretch = stretchFor(step, t)
        val width = 252f + 62f * stretch
        val topDepth = 34f - 17f * stretch
        val middleDepth = topDepth + 30f - 12f * stretch
        val basalDepth = middleDepth + 18f - 6f * stretch
        for (i in 0..SAMPLES) {
            x[i] = 180f + width * (i / SAMPLES.toFloat() - .5f)
            foldY[i] = 174f + 19f * stretch + 27f * (1f - stretch) * foldShape[i]
            surfaceY[i] = foldY[i] - (13f - 10f * stretch) * domeShape[i]
        }
        lumen(c)
        support(c, basalDepth)
        for (i in 0 until SAMPLES step 4) {
            cell(c, i, i + 4, middleDepth, basalDepth, basalFill, 5f, 4f - stretch)
        }
        for (i in 0 until SAMPLES step 6) {
            cell(c, i, i + 6, topDepth, middleDepth, middleFill, 7f + 2f * stretch, 6f - 2f * stretch)
        }
        for (i in 0 until SAMPLES step UMBRELLA_SPAN) {
            cell(c, i, i + UMBRELLA_SPAN, 0f, topDepth, umbrellaFill, 9f + 3f * stretch, 6f - 3f * stretch)
        }
        apicalBarrier(c, step == Lesson.SEALED)
        label(c, string.health_atlas_urothelial_geometry_lumen, 180f, 40f, 222f)
        label(c, string.health_atlas_urothelial_geometry_support, 180f, 326f, 236f)
        when (step) {
            Lesson.FOLDED -> foldLabel(c)
            Lesson.UNFOLD -> {
                umbrellaLabel(c)
                spanCue(c, 114f, false, t)
                spanCue(c, 246f, true, t)
            }
            Lesson.SEALED -> {
                tracerMotion(c, t)
                label(c, string.health_atlas_urothelial_geometry_junction, 180f, 85f, 150f)
                line(c, 180f, 94f, x[24], surfaceY[24] - 4f, sealedEdge, 1.4f)
            }
            Lesson.REFOLD -> {
                foldLabel(c)
                spanCue(c, 57f, true, t)
                spanCue(c, 303f, false, t)
            }
        }
    }

    private fun lumen(c: Canvas) {
        outline.rewind()
        outline.moveTo(x[0], 56f)
        outline.lineTo(x[SAMPLES], 56f)
        for (i in SAMPLES downTo 0) outline.lineTo(x[i], surfaceY[i])
        outline.close()
        ink(cream); paint.shader = lumenFill
        c.drawPath(outline, paint)
        paint.shader = null
    }

    private fun support(c: Canvas, basalDepth: Float) {
        outline.rewind()
        outline.moveTo(x[0], foldY[0] + basalDepth)
        for (i in 1..SAMPLES) outline.lineTo(x[i], foldY[i] + basalDepth)
        for (i in SAMPLES downTo 0) outline.lineTo(x[i], foldY[i] + basalDepth + 23f)
        outline.close()
        ink(0xffe6cbc0)
        c.drawPath(outline, paint)
        for (i in 2 until SAMPLES step 4) {
            val y = foldY[i] + basalDepth + 12f
            line(c, x[i] - 4f, y - 1f, x[i] + 4f, y + 1f, 0xffb88580, 1.3f)
        }
    }

    private fun cell(
        c: Canvas, left: Int, right: Int, top: Float, bottom: Float, fill: Shader,
        nucleusW: Float, nucleusH: Float,
    ) {
        // Reuse identical contour samples on both sides of every contact.
        outline.rewind()
        val upper = if (top == 0f) surfaceY else foldY
        outline.moveTo(x[left], upper[left] + top)
        for (i in left + 1..right) outline.lineTo(x[i], upper[i] + top)
        for (i in right downTo left) outline.lineTo(x[i], foldY[i] + bottom)
        outline.close()
        ink(cream); paint.shader = fill
        c.drawPath(outline, paint)
        paint.shader = null
        stroke(c, outline, edge, 1.15f)
        val i = (left + right) / 2
        val y = (upper[i] + top + foldY[i] + bottom) / 2f
        oval(c, x[i] - nucleusW, y - nucleusH, x[i] + nucleusW, y + nucleusH, 0xffac7594, 0xff925d80)
    }

    private fun apicalBarrier(c: Canvas, highlightJunctions: Boolean) {
        outline.rewind()
        outline.moveTo(x[0], surfaceY[0])
        for (i in 1..SAMPLES) outline.lineTo(x[i], surfaceY[i])
        stroke(c, outline, sealedEdge, 2.4f)
        for (i in UMBRELLA_SPAN until SAMPLES step UMBRELLA_SPAN) {
            val y = surfaceY[i] + 3f
            if (highlightJunctions) disc(c, x[i], y, 6f, 0xffffe7ae)
            line(c, x[i] - 3f, y, x[i] + 3f, y, sealedEdge, 2.9f)
            line(c, x[i], y - 2f, x[i], y + 4f, sealedEdge, 2.2f)
        }
    }

    private fun foldLabel(c: Canvas) {
        label(c, string.health_atlas_urothelial_geometry_fold, 117f, 88f, 134f)
        line(c, 117f, 97f, x[10], surfaceY[10] - 3f, sealedEdge, 1.25f)
    }

    private fun umbrellaLabel(c: Canvas) {
        label(c, string.health_atlas_urothelial_geometry_umbrella, 190f, 88f, 185f)
        line(c, 190f, 97f, x[28], surfaceY[28] - 3f, sealedEdge, 1.25f)
    }

    private fun tracerMotion(c: Canvas, t: Float) {
        for (i in 5 until SAMPLES step 7) {
            val approach = (t * 1.36f - i % 3 * .10f).coerceIn(0f, 1f)
            val gap = 67f - 51f * approach
            val cx = (x[i] + 3f * wave(t + i / 11f)).coerceIn(x[0] + 5f, x[SAMPLES] - 12f)
            disc(c, cx, surfaceY[i] - gap, 3.5f, 0xff508594)
            disc(c, cx + 7f, surfaceY[i] - gap - 12f, 2.3f, 0xff7ca8ad)
        }
    }

    private fun spanCue(c: Canvas, start: Float, right: Boolean, t: Float) {
        val direction = if (right) 1f else -1f
        val tip = start + direction * (16f + 18f * t)
        line(c, start, 119f, tip, 119f, sealedEdge, 1.7f)
        line(c, tip, 119f, tip - direction * 6f, 115f, sealedEdge, 1.7f)
        line(c, tip, 119f, tip - direction * 6f, 123f, sealedEdge, 1.7f)
    }

    private companion object {
        const val SAMPLES = 48
        const val UMBRELLA_SPAN = 8

        // Continuous teaching geometry, not bladder volume, elapsed time, or a measured specimen.
        fun stretchFor(step: Int, t: Float): Float {
            val s = t * t * (3f - 2f * t)
            return when (step) {
                Lesson.FOLDED -> .12f * s
                Lesson.UNFOLD -> .12f + .68f * s
                Lesson.SEALED -> .80f + .20f * s
                else -> 1f - s
            }
        }
    }
}
