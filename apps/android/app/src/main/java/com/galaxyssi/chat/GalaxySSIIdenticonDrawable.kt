package com.galaxyssi.chat

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import kotlin.math.min

internal class GalaxySSIIdenticonDrawable(identityFingerprint: String) : Drawable() {
    private val pattern = GalaxySSIIdenticon.fromIdentityFingerprint(identityFingerprint)
    private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(246, 248, 250)
        style = Paint.Style.FILL
    }
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(208, 215, 222)
        style = Paint.Style.STROKE
    }
    private val cellPaint = Paint().apply {
        color = pattern.color
        style = Paint.Style.FILL
        isAntiAlias = false
    }

    override fun draw(canvas: Canvas) {
        val size = min(bounds.width(), bounds.height()).toFloat()
        if (size <= 0f) return
        val left = bounds.exactCenterX() - size / 2f
        val top = bounds.exactCenterY() - size / 2f
        val radius = size / 2f
        val centerX = bounds.exactCenterX()
        val centerY = bounds.exactCenterY()

        canvas.drawCircle(centerX, centerY, radius, backgroundPaint)

        val clip = Path().apply { addCircle(centerX, centerY, radius, Path.Direction.CW) }
        val checkpoint = canvas.save()
        canvas.clipPath(clip)
        val gridInset = size * 0.12f
        val cellSize = (size - gridInset * 2f) / GalaxySSIIdenticonPattern.GRID_SIZE
        for (row in 0 until GalaxySSIIdenticonPattern.GRID_SIZE) {
            for (column in 0 until GalaxySSIIdenticonPattern.GRID_SIZE) {
                if (!pattern.isFilled(row, column)) continue
                val cellLeft = left + gridInset + column * cellSize
                val cellTop = top + gridInset + row * cellSize
                canvas.drawRect(cellLeft, cellTop, cellLeft + cellSize, cellTop + cellSize, cellPaint)
            }
        }
        canvas.restoreToCount(checkpoint)

        borderPaint.strokeWidth = maxOf(1f, size * 0.025f)
        canvas.drawCircle(centerX, centerY, radius - borderPaint.strokeWidth / 2f, borderPaint)
    }

    override fun setAlpha(alpha: Int) {
        backgroundPaint.alpha = alpha
        borderPaint.alpha = alpha
        cellPaint.alpha = alpha
        invalidateSelf()
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        backgroundPaint.colorFilter = colorFilter
        borderPaint.colorFilter = colorFilter
        cellPaint.colorFilter = colorFilter
        invalidateSelf()
    }

    @Deprecated("Deprecated in the Android SDK")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}
