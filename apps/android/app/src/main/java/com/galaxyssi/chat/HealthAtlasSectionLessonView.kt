package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.view.View

internal class HealthAtlasSectionLessonView(context: Context, val lesson: HealthAtlasSectionLesson,
    private val mechanism: HealthAtlasMechanism) : View(context) {
    private val art = requireNotNull(context.getDrawable(lesson.plate.drawable)).mutate()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val point = FloatArray(2)
    private val direction = FloatArray(2)
    private val trail = Path()
    private val tip = Path()
    private val routes = lesson.tracks.map { PathMeasure(it(), false) }
    var phase = 0f
        set(value) {
            val previous = stage
            field = value.coerceIn(0f, 1f)
            if (stage != previous) describe()
            invalidate()
        }
    val stage get() = (phase * 4f).toInt().coerceIn(0, 3)

    init {
        tag = "atlas-section-diagram"
        art.setBounds(0, 0, lesson.artWidth, lesson.artHeight)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        describe()
    }

    private fun describe() {
        val feature = lesson.plate.features[lesson.stageFeatures[stage]]
        contentDescription = context.getString(feature.title) + ". " + mechanism.stages[stage]
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val available = MeasureSpec.getSize(widthMeasureSpec)
        val maximum = ((if (lesson.artHeight > lesson.artWidth) 280 else 226) * resources.displayMetrics.density).toInt()
        val desired = (available * (lesson.artHeight.toFloat() / lesson.artWidth)).toInt().coerceAtMost(maximum)
        setMeasuredDimension(available, resolveSize(desired, heightMeasureSpec))
    }

    override fun onDraw(canvas: Canvas) {
        val scale = minOf(width / lesson.artWidth.toFloat(), height / lesson.artHeight.toFloat())
        canvas.save()
        canvas.translate((width - lesson.artWidth * scale) / 2, (height - lesson.artHeight * scale) / 2)
        canvas.scale(scale, scale)
        art.draw(canvas)
        val marker = lesson.plate.features[lesson.stageFeatures[stage]].marker
        val x = marker.x * lesson.artWidth
        val y = marker.y * lesson.artHeight
        val fraction = (phase * 4f - stage).coerceIn(0f, 1f)
        paint.style = Paint.Style.STROKE
        paint.color = 0xfff9fcf9.toInt()
        paint.strokeWidth = 5f
        val radius = if (routes.isEmpty()) 14f + 4f * fraction else 12f
        canvas.drawCircle(x, y, radius, paint)
        paint.color = 0xff176a5a.toInt()
        paint.strokeWidth = 2.6f
        canvas.drawCircle(x, y, radius, paint)
        routes.getOrNull(stage)?.let { drawFlow(canvas, it, fraction) }
        canvas.restore()
    }

    private fun drawFlow(canvas: Canvas, route: PathMeasure, fraction: Float) {
        val distance = route.length * fraction
        val stroke = 0xff285f82.toInt()
        trail.rewind()
        if (route.getSegment(0f, distance, trail, true)) {
            paint.style = Paint.Style.STROKE
            paint.strokeCap = Paint.Cap.ROUND
            paint.color = 0xeaf9fcff.toInt()
            paint.strokeWidth = 5.6f
            canvas.drawPath(trail, paint)
            paint.color = stroke
            paint.strokeWidth = 2.7f
            canvas.drawPath(trail, paint)
        }
        if (!route.getPosTan(distance, point, direction)) return
        val x = point[0]
        val y = point[1]
        val dx = direction[0]
        val dy = direction[1]
        tip.rewind()
        tip.moveTo(x + dx * 6.5f, y + dy * 6.5f)
        tip.lineTo(x - dx * 5.5f - dy * 4.3f, y - dy * 5.5f + dx * 4.3f)
        tip.lineTo(x - dx * 5.5f + dy * 4.3f, y - dy * 5.5f - dx * 4.3f)
        tip.close()
        paint.style = Paint.Style.FILL_AND_STROKE
        paint.strokeJoin = Paint.Join.ROUND
        paint.color = 0xfff9fcff.toInt()
        paint.strokeWidth = 2.6f
        canvas.drawPath(tip, paint)
        paint.style = Paint.Style.FILL
        paint.color = stroke
        canvas.drawPath(tip, paint)
    }
}
