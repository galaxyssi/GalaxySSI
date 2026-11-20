package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View

internal class HealthAtlasAlveolarSurfaceView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        textAlign = Paint.Align.CENTER
    }
    private val accent = context.getColor(R.color.health_atlas_ear_input)
    private val ink = context.getColor(R.color.text_secondary)
    private val dp = resources.displayMetrics.density
    private var pressures = emptyList<String>()
    var model = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.ALVEOLAR_SURFACE)
        set(value) {
            require(value.kind == HealthAtlasPhysiologyKind.ALVEOLAR_SURFACE)
            field = value
            describe()
            invalidate()
        }

    init {
        tag = "atlas-alveolar-surface-diagram"
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        describe()
    }
    private fun describe() {
        val radius = model.input(1)
        val pressure = HealthAtlasPhysiologyText.number(model.result)
        val half = HealthAtlasPhysiologyText.number(model.companionValue)
        pressures = listOf("$pressure Pa", "$half Pa")
        contentDescription = context.getString(R.string.health_atlas_alveolar_surface_diagram,
            HealthAtlasPhysiologyText.number(radius), pressure, HealthAtlasPhysiologyText.number(radius * 2), half)
    }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), resolveSize((138 * dp).toInt(), heightMeasureSpec))
    }
    override fun onDraw(canvas: Canvas) {
        val largeRadius = minOf(width * .17f, height * .28f)
        val y = height * .36f
        for (i in 0..1) {
            val x = (2 * i + 1) * width / 4f
            val radius = largeRadius * (i + 1) / 2f
            paint.color = accent
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 2 * dp
            canvas.drawCircle(x, y, radius, paint)
            canvas.drawLine(x, y, x + radius, y, paint)
            paint.style = Paint.Style.FILL
            canvas.drawCircle(x, y, 2.2f * dp, paint)
            paint.color = ink
            paint.textSize = minOf(13 * resources.displayMetrics.scaledDensity, width * .046f)
            canvas.drawText(if (i == 0) "r" else "2r", x, y + largeRadius + 17 * dp, paint)
            canvas.drawText(pressures[i], x, height - 5 * dp, paint)
        }
    }
}
