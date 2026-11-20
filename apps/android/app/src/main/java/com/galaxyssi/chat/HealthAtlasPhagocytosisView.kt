package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.View

/** Four qualitative drawings of particle handling, controlled by the existing teaching stage. */
internal class HealthAtlasPhagocytosisView(context: Context, private val mechanism: HealthAtlasMechanism) : View(context) {
    private val brush = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeCap = Paint.Cap.ROUND }
    private val membrane = 0xff508975.toInt()
    private val cytoplasm = 0xffb5d4be.toInt()
    private val nucleus = 0xff75668c.toInt()
    private val particle = 0xff9f6c44.toInt()
    private val compartment = 0xffa06476.toInt()
    private val signal = 0xff40827f.toInt()
    private val shape = Path().apply {
        moveTo(47f, 84f)
        cubicTo(47f, 59f, 64f, 49f, 89f, 42f)
        cubicTo(105f, 22f, 134f, 18f, 154f, 32f)
        cubicTo(182f, 29f, 199f, 42f, 211f, 59f)
        cubicTo(228f, 63f, 252f, 55f, 268f, 67f)
        cubicTo(275f, 80f, 249f, 88f, 251f, 102f)
        cubicTo(252f, 113f, 279f, 119f, 271f, 133f)
        cubicTo(261f, 151f, 232f, 136f, 220f, 146f)
        cubicTo(197f, 169f, 158f, 159f, 134f, 160f)
        cubicTo(110f, 160f, 97f, 145f, 76f, 146f)
        cubicTo(57f, 143f, 63f, 120f, 51f, 111f)
        cubicTo(40f, 106f, 43f, 93f, 47f, 84f)
        close()
    }
    var stage = 0
        set(value) {
            require(value in mechanism.stages.indices)
            if (value != field) { field = value; updateDescription(); invalidate() }
        }

    init {
        tag = "atlas-phagocytosis-diagram"
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        updateDescription()
    }
    private fun updateDescription() {
        contentDescription = context.getString(R.string.health_atlas_phagocytosis_visual_stage, mechanism.stages[stage])
    }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        setMeasuredDimension(w, resolveSize((w * .50f).toInt().coerceAtMost(
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
        val scale = minOf(width / 360f, height / 176f)
        canvas.save()
        canvas.translate((width - 360f * scale) / 2f, (height - 176f * scale) / 2f)
        canvas.scale(scale, scale)
        fill(cytoplasm); canvas.drawPath(shape, brush)
        stroke(membrane, 2.5f); canvas.drawPath(shape, brush)
        fill(nucleus); canvas.drawOval(83f, 61f, 159f, 120f, brush)
        when (stage) {
            0 -> {
                target(canvas, 303f, 100f)
                stroke(particle, 2f)
                canvas.drawLine(288f, 100f, 269f, 100f, brush)
                canvas.drawLine(269f, 100f, 276f, 95f, brush)
                canvas.drawLine(269f, 100f, 276f, 105f, brush)
            }
            1 -> {
                stroke(compartment, 3f); canvas.drawCircle(217f, 101f, 25f, brush)
                target(canvas, 217f, 101f)
            }
            2 -> {
                fill(0xffe4bdab.toInt()); canvas.drawCircle(207f, 100f, 29f, brush)
                stroke(compartment, 3f); canvas.drawCircle(207f, 100f, 29f, brush)
                fill(particle)
                canvas.drawCircle(199f, 97f, 4f, brush)
                canvas.drawCircle(208f, 104f, 3f, brush)
                canvas.drawCircle(215f, 96f, 3f, brush)
                fill(compartment)
                canvas.drawCircle(180f, 73f, 6f, brush)
                canvas.drawCircle(176f, 118f, 5f, brush)
            }
            3 -> {
                stroke(compartment, 2.5f); canvas.drawCircle(199f, 100f, 16f, brush)
                fill(particle); canvas.drawCircle(200f, 100f, 3f, brush)
                stroke(signal, 3f)
                canvas.drawArc(262f, 70f, 313f, 125f, -38f, 76f, false, brush)
                canvas.drawArc(258f, 60f, 327f, 135f, -38f, 76f, false, brush)
            }
        }
        canvas.restore()
    }
    companion object { const val OWNER = "cell-macrophage" }
}
