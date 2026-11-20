package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View

/** The three layers remain visible in every phase of this qualitative filtration walkthrough. */
internal class HealthAtlasPodocyteView(context: Context, private val mechanism: HealthAtlasMechanism) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeCap = Paint.Cap.ROUND }
    private val ink = context.getColor(R.color.text_secondary)
    private val labels = listOf(R.string.health_atlas_podocyte_blood, R.string.health_atlas_podocyte_endothelium,
        R.string.health_atlas_podocyte_basement, R.string.health_atlas_podocyte_slits, R.string.health_atlas_podocyte_filtrate)
        .map(context::getString)
    private val labelBaselines = floatArrayOf(34f, 75f, 104f, 135f, 185f)
    private val arrowEnds = floatArrayOf(57f, 116f, 135f, 181f)
    var stage = 0
        set(value) {
            require(value in mechanism.stages.indices)
            if (field != value) {
                field = value
                describe()
                invalidate()
            }
        }
    init {
        tag = "atlas-podocyte-diagram"
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        describe()
    }
    private fun describe() {
        contentDescription = mechanism.stages[stage] + ". " + context.getString(R.string.health_atlas_podocyte_scope)
    }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        setMeasuredDimension(w, resolveSize((w * .57f).toInt().coerceAtMost(
            (235 * resources.displayMetrics.density).toInt()), heightMeasureSpec))
    }
    override fun onDraw(canvas: Canvas) {
        val scale = minOf(width / 360f, height / 201f)
        canvas.save()
        canvas.translate((width - 360f * scale) / 2f, (height - 201f * scale) / 2f)
        canvas.scale(scale, scale)
        paint.color = ink
        paint.textSize = 13f
        labels.forEachIndexed { index, label -> canvas.drawText(label, 11f, labelBaselines[index], paint) }
        paint.color = 0xffb66076.toInt()
        for (i in 0..3) {
            val x = 138f + i * 51f
            canvas.drawRoundRect(x, 62f, x + 43f, 79f, 5f, 5f, paint)
        }
        paint.color = 0xffdeb86d.toInt()
        canvas.drawRoundRect(138f, 93f, 334f, 109f, 4f, 4f, paint)
        for (i in 0..7) {
            val x = 138f + i * 25f
            paint.color = if (i % 2 == 0) 0xff57837b.toInt() else 0xff648ade.toInt()
            canvas.drawRoundRect(x, 108f, x + 19f, 133f, 5f, 5f, paint)
            canvas.drawRoundRect(x + 5f, 127f, x + 14f, 151f, 3f, 3f, paint)
        }
        if (stage >= 2) {
            paint.color = 0xff68827e.toInt()
            for (i in 0..6) {
                val x = 157f + i * 25f
                canvas.drawRect(x, 119f, x + 6f, 123f, paint)
            }
        }
        // A cell remains in the capillary while the arrow follows filtrate across the barrier.
        paint.color = 0xffc76578.toInt()
        canvas.drawOval(166f, 17f, 199f, 37f, paint)
        paint.color = 0xffea9a9e.toInt()
        canvas.drawOval(174f, 23f, 191f, 31f, paint)
        paint.color = ink
        paint.strokeWidth = 2.5f
        val end = arrowEnds[stage]
        val x = 235f
        canvas.drawLine(x, 20f, x, end, paint)
        canvas.drawLine(x - 5f, end - 6f, x, end, paint)
        canvas.drawLine(x + 5f, end - 6f, x, end, paint)
        canvas.restore()
    }

    companion object { const val OWNER = "cell-podocyte" }
}
