package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View

internal class HealthAtlasVillusAreaView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    var model = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.VILLUS_AREA)
        set(value) {
            field = value
            updateDescription()
            invalidate()
        }

    init {
        tag = "atlas-villus-geometry"
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        updateDescription()
    }
    private fun updateDescription() {
        contentDescription = context.getString(R.string.health_atlas_gut_section_area_views) + ". " +
            context.getString(R.string.health_atlas_gut_section_area_diagram_accessible, model.inputs[0],
                HealthAtlasPhysiologyText.inputNumber("villus-radius", model.input(1)),
                HealthAtlasPhysiologyText.inputNumber("villus-height", model.input(2)))
    }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val available = MeasureSpec.getSize(widthMeasureSpec)
        val limit = (154 * resources.displayMetrics.density).toInt()
        setMeasuredDimension(available, resolveSize((available * .50f).toInt().coerceAtMost(limit), heightMeasureSpec))
    }
    override fun onDraw(canvas: Canvas) {
        val scale = minOf(width / 320f, height / 150f)
        canvas.save()
        canvas.translate((width - 320 * scale) / 2, (height - 150 * scale) / 2)
        canvas.scale(scale, scale)
        val muted = context.getColor(R.color.text_primary)
        val material = 0xff2b9080.toInt()
        val diameterScale = 96f
        paint.style = Paint.Style.FILL
        paint.color = 0xffe3f4ee.toInt()
        canvas.drawRect(28f, 31f, 124f, 127f, paint)
        paint.color = muted
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 1.5f
        canvas.drawRect(28f, 31f, 124f, 127f, paint)
        canvas.drawLine(192f, 127f, 288f, 127f, paint)
        val radius = model.input(1).toFloat() * diameterScale
        paint.color = material
        paint.style = Paint.Style.FILL
        repeat(model.inputs[0]) { index ->
            val slot = (12 + 7 * index) % 25
            canvas.drawCircle(28f + (slot % 5 + .5f) * 19.2f, 31f + (slot / 5 + .5f) * 19.2f, radius, paint)
        }
        if (model.inputs[0] > 0) {
            val top = 127f - model.input(2).toFloat() * diameterScale
            canvas.drawRect(240f - radius, top, 240f + radius, 127f, paint)
            paint.color = 0xff9cd7ca.toInt()
            canvas.drawOval(240f - radius, top - 2.4f, 240f + radius, top + 2.4f, paint)
        }
        canvas.restore()
    }
}
