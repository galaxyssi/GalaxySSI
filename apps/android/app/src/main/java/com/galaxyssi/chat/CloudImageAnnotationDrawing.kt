package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import kotlin.math.abs
import kotlin.math.min

/** Bounds locate answers; only compact grading ink is added, never boxes or a second page. */
internal object CloudImageAnnotationDrawing {
    fun render(source: Bitmap, plan: CloudImageAnnotationPlan, checkpoint: () -> Unit): Bitmap {
        val output = source.copy(Bitmap.Config.ARGB_8888, true) ?: error("Cannot copy input image")
        try {
            val canvas = Canvas(output)
            val bounds = plan.marks.map { RectF(it.left * source.width, it.top * source.height,
                it.right * source.width, it.bottom * source.height) }
            val occupied = mutableListOf<RectF>()
            plan.marks.forEachIndexed { index, mark ->
                checkpoint()
                val answer = bounds[index]
                val size = min(source.width * 0.024f, answer.height() * 0.48f)
                    .coerceIn(12f, 36f).coerceAtMost(min(source.width, source.height) * 0.25f)
                val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = when (mark.verdict) {
                        "correct" -> Color.rgb(0, 125, 75)
                        "incorrect" -> Color.rgb(195, 35, 40)
                        "uncertain" -> Color.rgb(145, 95, 0)
                        else -> Color.rgb(35, 85, 160)
                    }
                    strokeWidth = (size * 0.10f).coerceAtLeast(1.5f)
                    strokeCap = Paint.Cap.ROUND
                    strokeJoin = Paint.Join.ROUND
                    textSize = size
                }
                val correction = mark.correction.takeIf { mark.verdict == "incorrect" }.orEmpty()
                val maximumLabel = (source.width * 0.32f).coerceAtLeast(size)
                while (paint.measureText(correction) > maximumLabel && paint.textSize > size * 0.6f) {
                    paint.textSize -= 0.5f
                }
                val labelWidth = paint.measureText(correction)
                val gap = (size * 0.25f).coerceAtLeast(2f)
                require(labelWidth + size + gap <= source.width) { "Shorten the correction to fit beside the answer" }
                val width = (size + if (correction.isBlank()) 0f else gap + labelWidth)
                    .coerceAtMost(source.width.toFloat())
                val height = size * 1.2f
                val at = placement(answer, width, height, gap, source.width, source.height, bounds + occupied)
                occupied += at
                val x = at.left
                val y = at.top + size * 0.2f
                paint.style = Paint.Style.STROKE
                when (mark.verdict) {
                    "correct" -> canvas.drawPath(Path().apply {
                        moveTo(x, y + size * 0.45f)
                        lineTo(x + size * 0.32f, y + size * 0.8f)
                        lineTo(x + size, y)
                    }, paint)
                    "incorrect" -> {
                        canvas.drawLine(x, y, x + size * 0.8f, y + size * 0.8f, paint)
                        canvas.drawLine(x + size * 0.8f, y, x, y + size * 0.8f, paint)
                    }
                    else -> {
                        paint.style = Paint.Style.FILL
                        canvas.drawText(if (mark.verdict == "uncertain") "?" else "*", x, y + size * 0.8f, paint)
                    }
                }
                if (correction.isNotBlank()) {
                    paint.style = Paint.Style.FILL
                    canvas.drawText(correction, x + size + gap, y + size * 0.8f, paint)
                }
            }
            return output
        } catch (error: Throwable) { output.recycle(); throw error }
    }

    private fun placement(answer: RectF, width: Float, height: Float, gap: Float,
        imageWidth: Int, imageHeight: Int, occupied: List<RectF>): RectF {
        fun candidate(left: Float, top: Float): RectF {
            val x = left.coerceIn(0f, (imageWidth - width).coerceAtLeast(0f))
            val y = top.coerceIn(0f, (imageHeight - height).coerceAtLeast(0f))
            return RectF(x, y, x + width, y + height)
        }
        val candidates = listOf(
            candidate(answer.right + gap, answer.centerY() - height / 2),
            candidate(answer.left - gap - width, answer.centerY() - height / 2),
            candidate(answer.right - width, answer.bottom + gap),
            candidate(answer.left, answer.bottom + gap),
            candidate(answer.right - width, answer.top - gap - height),
            candidate(answer.left, answer.top - gap - height)
        )
        return candidates.withIndex().minBy { (preference, rect) ->
            val overlap = occupied.sumOf {
                (minOf(rect.right, it.right) - maxOf(rect.left, it.left)).coerceAtLeast(0f).toDouble() *
                    (minOf(rect.bottom, it.bottom) - maxOf(rect.top, it.top)).coerceAtLeast(0f)
            }
            overlap * 1000 + abs(rect.centerY() - answer.centerY()) + preference
        }.value
    }
}
