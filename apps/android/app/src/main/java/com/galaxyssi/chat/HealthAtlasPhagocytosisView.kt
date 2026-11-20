package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View

/** Four qualitative stages share the painted structure plate and the native playhead. */
internal class HealthAtlasPhagocytosisView(context: Context, private val mechanism: HealthAtlasMechanism) : View(context) {
    private val brush = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeCap = Paint.Cap.ROUND }
    private val art = requireNotNull(context.getDrawable(R.drawable.health_atlas_cell_macrophage)).mutate().apply {
        setBounds(17, -22, 261, 222)
        setFilterBitmap(true)
    }
    private val particle = 0xff9f6c44.toInt()
    private val compartment = 0xffa06476.toInt()
    private val signal = 0xff40827f.toInt()
    val stage get() = (phase * 4).toInt().coerceAtMost(3)
    var phase = 0f
        set(value) {
            require(value in 0f..1f)
            if (value == field) return
            val previous = stage
            field = value
            if (stage != previous) updateDescription()
            invalidate()
        }

    init {
        require(mechanism.stages.size == 4)
        tag = "atlas-phagocytosis-diagram"
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        updateDescription()
    }
    private fun updateDescription() {
        contentDescription = context.getString(R.string.health_atlas_phagocytosis_visual_stage, mechanism.stages[stage])
    }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        setMeasuredDimension(w, resolveSize((w * .56f).toInt().coerceAtMost(
            (235 * resources.displayMetrics.density).toInt()), heightMeasureSpec))
    }
    private fun fill(color: Int) { brush.style = Paint.Style.FILL; brush.color = color }
    private fun stroke(color: Int, width: Float) { brush.style = Paint.Style.STROKE; brush.color = color; brush.strokeWidth = width }
    private fun target(canvas: Canvas, x: Float, y: Float) {
        fill(particle)
        canvas.save()
        canvas.rotate(-23f, x, y)
        canvas.drawRoundRect(x - 11f, y - 5f, x + 11f, y + 5f, 5f, 5f, brush)
        canvas.restore()
    }
    override fun onDraw(canvas: Canvas) {
        val scale = minOf(width / 360f, height / 200f)
        canvas.save()
        canvas.translate((width - 360f * scale) / 2f, (height - 200f * scale) / 2f)
        canvas.scale(scale, scale)
        art.draw(canvas)
        val progress = phase * 4f - stage
        val ease = progress * progress * (3f - 2f * progress)
        when (stage) {
            0 -> {
                target(canvas, 298f - ease * 80f, 98f)
                stroke(particle, 2f)
                canvas.drawLine(276f, 119f, 215f, 119f, brush)
                canvas.drawLine(215f, 119f, 222f, 114f, brush)
                canvas.drawLine(215f, 119f, 222f, 124f, brush)
            }
            1 -> {
                val x = 218f - ease * 62f
                stroke(compartment, 2.5f)
                brush.alpha = (70f + ease * 185f).toInt()
                canvas.drawCircle(x, 98f, 15f + ease * 8f, brush)
                target(canvas, x, 98f)
            }
            2 -> {
                stroke(compartment, 2.5f); canvas.drawCircle(156f, 98f, 23f, brush)
                fill(particle)
                canvas.drawCircle(146f, 94f, 4.5f - ease * 2f, brush)
                canvas.drawCircle(156f, 105f, 4f - ease * 2f, brush)
                canvas.drawCircle(166f, 96f, 3.5f - ease * 2f, brush)
            }
            3 -> {
                stroke(compartment, 2.5f); canvas.drawCircle(156f, 98f, 10f, brush)
                fill(particle); canvas.drawCircle(156f, 98f, 2.5f, brush)
                stroke(signal, 2.5f)
                val drift = ease * 18f
                canvas.drawArc(220f + drift, 75f, 260f + drift, 121f, -38f, 76f, false, brush)
                canvas.drawArc(218f + drift, 64f, 276f + drift, 132f, -38f, 76f, false, brush)
            }
        }
        canvas.restore()
    }
    companion object { const val OWNER = "cell-macrophage" }
}
