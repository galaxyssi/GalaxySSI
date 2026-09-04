package com.galaxyssi.chat.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.min
import kotlin.math.sin

class VoiceWaveformView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {
    private val density = resources.displayMetrics.density
    private var samples = FloatArray(DEFAULT_SAMPLE_COUNT) { BASELINE }
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = RECORDING_COLOR
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private var smoothed = BASELINE
    private var recordingColor = RECORDING_COLOR
    private var cancelColor = CANCEL_COLOR
    private var denseRecordingStyle = false
    private var densePhase = 0f

    fun pushAmplitude(rawAmplitude: Int) {
        val safe = rawAmplitude.coerceIn(0, 32767)
        val normalized = if (safe == 0) BASELINE else {
            (BASELINE + (ln(safe.toDouble() + 1.0) / ln(32768.0)).toFloat() * (1f - BASELINE))
                .coerceIn(BASELINE, 1f)
        }
        smoothed = (smoothed * 0.58f + normalized * 0.42f).coerceIn(BASELINE, 1f)
        if (denseRecordingStyle) {
            densePhase += 0.34f
            val denominator = (samples.size - 1).coerceAtLeast(1).toFloat()
            samples.indices.forEach { index ->
                val normalizedPosition = index / denominator
                val centerEnvelope = 0.72f + 0.28f * (1f - abs(normalizedPosition - 0.5f) * 2f)
                val primaryWave = ((sin(index * 0.82f + densePhase) + 1f) * 0.5f)
                val secondaryWave = ((sin(index * 0.37f - densePhase * 1.45f) + 1f) * 0.5f)
                val variation = 0.26f + primaryWave * 0.48f + secondaryWave * 0.26f
                val target = BASELINE + (smoothed - BASELINE) * centerEnvelope * variation
                samples[index] = (samples[index] * 0.38f + target * 0.62f).coerceIn(BASELINE, 1f)
            }
        } else {
            System.arraycopy(samples, 1, samples, 0, samples.lastIndex)
            samples[samples.lastIndex] = smoothed
        }
        invalidate()
    }

    fun setCancelPending(cancelPending: Boolean) {
        paint.color = if (cancelPending) cancelColor else recordingColor
        invalidate()
    }

    fun setColors(recording: Int, cancel: Int) {
        recordingColor = recording
        cancelColor = cancel
        paint.color = recordingColor
        invalidate()
    }

    fun useDenseRecordingStyle() {
        denseRecordingStyle = true
        samples = FloatArray(DENSE_SAMPLE_COUNT) { BASELINE }
        smoothed = BASELINE
        densePhase = 0f
        invalidate()
    }

    fun reset() {
        samples.fill(BASELINE)
        smoothed = BASELINE
        densePhase = 0f
        paint.color = recordingColor
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        if (width <= 0 || height <= 0) return
        val centerY = height / 2f
        val targetDenseWidth = resources.displayMetrics.widthPixels * 0.75f
        val horizontalInset = if (denseRecordingStyle) {
            ((width - targetDenseWidth.coerceAtMost(width.toFloat())) / 2f).coerceAtLeast(0f)
        } else {
            0f
        }
        val availableWidth = (width - horizontalInset * 2f).coerceAtLeast(1f)
        val step = availableWidth / samples.size
        paint.strokeWidth = if (denseRecordingStyle) {
            min(1.45f * density, step * 0.32f)
        } else {
            min(2.8f * density, step * 0.38f)
        }
        val minHeight = (if (denseRecordingStyle) 2f else 4f) * density
        val verticalInset = (if (denseRecordingStyle) 8f else 4f) * density
        val maxHeight = (height - verticalInset).coerceAtLeast(minHeight)
        if (denseRecordingStyle) {
            val previousAlpha = paint.alpha
            val previousStrokeWidth = paint.strokeWidth
            paint.alpha = 72
            paint.strokeWidth = 0.8f * density
            canvas.drawLine(horizontalInset, centerY, width - horizontalInset, centerY, paint)
            paint.alpha = previousAlpha
            paint.strokeWidth = previousStrokeWidth
        }
        samples.forEachIndexed { index, amplitude ->
            val barHeight = minHeight + (maxHeight - minHeight) * amplitude
            val x = horizontalInset + step * index + step / 2f
            canvas.drawLine(x, centerY - barHeight / 2f, x, centerY + barHeight / 2f, paint)
        }
    }

    private companion object {
        const val BASELINE = 0.10f
        const val DEFAULT_SAMPLE_COUNT = 24
        const val DENSE_SAMPLE_COUNT = 56
        val RECORDING_COLOR = Color.parseColor("#2D7DFF")
        val CANCEL_COLOR = Color.parseColor("#FF3B30")
    }
}
