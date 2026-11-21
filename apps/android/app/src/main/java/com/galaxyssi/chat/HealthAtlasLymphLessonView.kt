package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.view.View

internal class HealthAtlasLymphLessonView(context: Context, val lesson: HealthAtlasLymphOrgans.Lesson,
    private val mechanism: HealthAtlasMechanism) : View(context) {
    private val art = requireNotNull(context.getDrawable(lesson.plate.drawable)).mutate()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val point = FloatArray(2)
    private val routes = when (lesson.owner) {
        "lymph-nodes" -> listOf(
            path(94f, 40f) { cubicTo(92f, 69f, 94f, 82f, 100f, 103f) },
            path(100f, 103f) { cubicTo(98f, 123f, 104f, 148f, 123f, 170f) },
            path(123f, 170f) { cubicTo(146f, 192f, 166f, 199f, 200f, 183f) },
            path(200f, 183f) { cubicTo(222f, 174f, 252f, 181f, 272f, 188f); quadTo(295f, 191f, 320f, 169f) },
        )
        "thoracic-duct" -> listOf(
            path(126f, 230f) { quadTo(140f, 221f, 163f, 224f) },
            path(163f, 224f) { quadTo(153f, 214f, 164f, 198f); cubicTo(178f, 177f, 173f, 145f, 180f, 139f) },
            path(180f, 139f) { cubicTo(184f, 124f, 192f, 110f, 205f, 99f) },
            path(205f, 99f) { quadTo(214f, 76f, 231f, 61f) },
        )
        else -> emptyList()
    }
    var phase = 0f
        set(value) {
            val previous = stage
            field = value.coerceIn(0f, 1f)
            if (stage != previous) describe()
            invalidate()
        }
    val stage get() = (phase * 4f).toInt().coerceIn(0, 3)

    init {
        tag = "atlas-lymph-diagram"
        art.setBounds(0, 0, 360, 280)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        describe()
    }

    private fun describe() {
        val feature = lesson.plate.features[lesson.stageFeatures[stage]]
        contentDescription = context.getString(feature.title) + ". " + mechanism.stages[stage]
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val available = MeasureSpec.getSize(widthMeasureSpec)
        val maximum = (226 * resources.displayMetrics.density).toInt()
        setMeasuredDimension(available, resolveSize((available * .78f).toInt().coerceAtMost(maximum), heightMeasureSpec))
    }

    override fun onDraw(canvas: Canvas) {
        val scale = minOf(width / 360f, height / 280f)
        canvas.save()
        canvas.translate((width - 360 * scale) / 2, (height - 280 * scale) / 2)
        canvas.scale(scale, scale)
        art.draw(canvas)
        val marker = lesson.plate.features[lesson.stageFeatures[stage]].marker
        val x = marker.x * 360f
        val y = marker.y * 280f
        val fraction = (phase * 4f - stage).coerceIn(0f, 1f)
        paint.style = Paint.Style.STROKE
        paint.color = 0xfff9fcf9.toInt()
        paint.strokeWidth = 5f
        val radius = if (routes.isEmpty()) 14f + 4f * fraction else 12f
        canvas.drawCircle(x, y, radius, paint)
        paint.color = 0xff176a5a.toInt()
        paint.strokeWidth = 2.6f
        canvas.drawCircle(x, y, radius, paint)
        routes.getOrNull(stage)?.let {
            if (it.getPosTan(it.length * fraction, point, null)) {
                paint.style = Paint.Style.FILL
                paint.color = 0xfff9fcf9.toInt()
                canvas.drawCircle(point[0], point[1], 7f, paint)
                paint.color = 0xff215675.toInt()
                canvas.drawCircle(point[0], point[1], 4.8f, paint)
            }
        }
        canvas.restore()
    }

    private fun path(x: Float, y: Float, draw: Path.() -> Unit) =
        PathMeasure(Path().apply { moveTo(x, y); draw() }, false)
}
