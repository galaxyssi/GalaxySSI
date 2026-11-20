package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.view.View

/** Educational visualization of an eccrine duct, with motion tied to the atlas playback controls. */
internal class HealthAtlasSweatView(context: Context, private val mechanism: HealthAtlasMechanism) : View(context) {
    private val diagram = requireNotNull(context.getDrawable(R.drawable.health_atlas_cell_sweat_gland_section)).mutate()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val droplet = 0xff206782.toInt()
    private val point = FloatArray(2)
    private val duct = PathMeasure(Path().apply {
        moveTo(173f, 66f)
        lineTo(173f, 83f)
        quadTo(152f, 93f, 173f, 103f)
        quadTo(194f, 113f, 170f, 125f)
        quadTo(149f, 136f, 174f, 145f)
        lineTo(174f, 170f)
        quadTo(145f, 181f, 144f, 199f)
        quadTo(145f, 227f, 181f, 230f)
        quadTo(214f, 231f, 210f, 204f)
        quadTo(208f, 183f, 183f, 190f)
        quadTo(159f, 194f, 168f, 211f)
        quadTo(177f, 223f, 192f, 216f)
    }, false)
    var phase = 0f
        set(value) {
            val previous = stage
            field = value.coerceIn(0f, 1f)
            if (stage != previous) describe()
            invalidate()
        }
    val stage get() = (phase * 4f).toInt().coerceIn(0, 3)

    init {
        tag = "atlas-sweat-diagram"
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        diagram.setBounds(0, 0, 360, 280)
        describe()
    }
    private fun describe() {
        contentDescription = mechanism.stages[stage] + ". " + context.getString(R.string.health_atlas_context_sweat_scope)
    }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val measuredWidth = MeasureSpec.getSize(widthMeasureSpec)
        val maxHeight = (234 * resources.displayMetrics.density).toInt()
        setMeasuredDimension(measuredWidth, resolveSize((measuredWidth * .75f).toInt().coerceAtMost(maxHeight), heightMeasureSpec))
    }
    override fun onDraw(canvas: Canvas) {
        val scale = minOf(width / 360f, height / 280f)
        canvas.save()
        canvas.translate((width - 360 * scale) / 2, (height - 280 * scale) / 2)
        canvas.scale(scale, scale)
        diagram.draw(canvas)
        val fraction = (phase * 4f - stage).coerceIn(0f, 1f)
        paint.color = droplet
        paint.alpha = 255
        paint.style = Paint.Style.FILL
        when (stage) {
            0, 1 -> {
                val position = if (stage == 0) 1f - .25f * fraction else .75f * (1f - fraction)
                if (duct.getPosTan(duct.length * position, point, null)) canvas.drawCircle(point[0], point[1], 7f, paint)
            }
            2 -> {
                val radius = 5f + fraction * 3f
                canvas.drawOval(173f - radius, 47f - radius, 173f + radius, 51f + radius, paint)
            }
            3 -> {
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = 2.8f
                paint.alpha = 210 - (fraction * 135).toInt()
                for (i in -1..1) {
                    val x = 173f + 14 * i
                    val y = 39f - 20f * fraction + 4f * kotlin.math.abs(i)
                    canvas.drawCircle(x, y, 4.5f, paint)
                }
            }
        }
        canvas.restore()
    }

    companion object { const val OWNER = "sweat-glands" }
}
