package com.galaxyssi.chat

import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import android.view.View
import kotlin.math.hypot
import kotlin.math.min

/** A schematic, not an anatomical rendering. Geometry is rebuilt only on size or lesson changes. */
internal class HealthBodyDiagram(context: Context, private val lesson: HealthBodyLesson) : View(context) {
    private data class Track(val x1: Float, val y1: Float, val x2: Float, val y2: Float, val dx: Float, val dy: Float)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
    private val line = Path()
    private val pointX = FloatArray(lesson.nodes.size)
    private val pointY = FloatArray(lesson.nodes.size)
    private val labels = lesson.nodes.map { context.getString(it.label) }
    private var tracks = emptyList<Track>()
    private var radius = 0f
    private var density = resources.displayMetrics.density
    private val dark = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
    private val textColor = context.getColor(R.color.text_primary)
    private val mutedTrack = if (dark) 0xff566469.toInt() else 0xffaebfba.toInt()
    private val inactiveNode = if (dark) 0xff263533.toInt() else 0xfff9fdfb.toInt()

    var position = 0f
        set(value) {
            field = value
            invalidate()
        }

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        tag = "health-body-diagram"
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w == 0 || h == 0) return
        density = resources.displayMetrics.density
        radius = min(27f * density, min(w / 11f, h / 7f))
        val columns = if (lesson.nodes.size == 3) floatArrayOf(.18f, .50f, .82f) else floatArrayOf(.22f, .78f, .78f, .22f)
        val rows = if (lesson.nodes.size == 3) floatArrayOf(.44f, .44f, .44f) else floatArrayOf(.29f, .29f, .71f, .71f)
        for (index in pointX.indices) {
            pointX[index] = columns[index] * w
            pointY[index] = rows[index] * h
        }
        tracks = lesson.steps.map { step ->
            val deltaX = pointX[step.to] - pointX[step.from]
            val deltaY = pointY[step.to] - pointY[step.from]
            val length = hypot(deltaX, deltaY)
            val dx = deltaX / length
            val dy = deltaY / length
            val offset = if (lesson.steps.any { it.from == step.to && it.to == step.from }) radius * .24f else 0f
            val gap = radius + 4f * density
            Track(pointX[step.from] + dx * gap - dy * offset, pointY[step.from] + dy * gap + dx * offset,
                pointX[step.to] - dx * gap - dy * offset, pointY[step.to] - dy * gap + dx * offset, dx, dy)
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (tracks.isEmpty()) return
        val frame = HealthBodyTimeline.frame(position, lesson.steps.size)
        val step = lesson.steps[frame.step]
        val active = color(step.tone)
        tracks.forEachIndexed { index, track -> drawTrack(canvas, track, index == frame.step, active) }
        drawMotion(canvas, tracks[frame.step], frame.fraction, active)
        for (index in pointX.indices) {
            val selected = index == step.from || index == step.to
            val x = pointX[index]
            val y = pointY[index]
            paint.style = Paint.Style.FILL
            paint.color = if (selected) active and 0x00ffffff or (if (dark) 0x39000000 else 0x21000000) else inactiveNode
            canvas.drawCircle(x, y, radius, paint)
            paint.style = Paint.Style.STROKE
            paint.color = if (selected) active else mutedTrack
            paint.strokeWidth = (if (selected) 2.1f else 1.2f) * density
            canvas.drawCircle(x, y, radius, paint)
            drawGlyph(canvas, lesson.nodes[index].glyph, x, y, if (selected) active else textColor)
            drawLabel(canvas, labels[index], x, y, selected, above = lesson.nodes.size == 4 && index < 2)
        }
    }

    private fun drawTrack(canvas: Canvas, track: Track, active: Boolean, tone: Int) {
        paint.style = Paint.Style.STROKE
        paint.color = if (active) tone else mutedTrack
        paint.strokeWidth = (if (active) 2.8f else 1.3f) * density
        canvas.drawLine(track.x1, track.y1, track.x2, track.y2, paint)
        val size = (if (active) 7f else 5f) * density
        val backX = track.x2 - track.dx * size
        val backY = track.y2 - track.dy * size
        val sideX = track.dy * size * .55f
        val sideY = track.dx * size * .55f
        line.reset()
        line.moveTo(backX + sideX, backY - sideY)
        line.lineTo(track.x2, track.y2)
        line.lineTo(backX - sideX, backY + sideY)
        canvas.drawPath(line, paint)
    }

    private fun drawMotion(canvas: Canvas, track: Track, fraction: Float, tone: Int) {
        paint.style = Paint.Style.FILL
        for (index in 2 downTo 0) {
            val f = (.10f + .80f * fraction - .085f * index).coerceIn(.02f, .92f)
            paint.color = tone
            paint.alpha = 255 - 78 * index
            val x = track.x1 + (track.x2 - track.x1) * f
            val y = track.y1 + (track.y2 - track.y1) * f
            canvas.drawCircle(x, y, (5.2f - index * 1.2f) * density, paint)
        }
        paint.alpha = 255
    }

    private fun drawLabel(canvas: Canvas, label: String, x: Float, y: Float, active: Boolean, above: Boolean) {
        paint.style = Paint.Style.FILL
        paint.color = textColor
        paint.typeface = if (active) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        paint.textAlign = Paint.Align.CENTER
        val sp = android.util.TypedValue.applyDimension(android.util.TypedValue.COMPLEX_UNIT_SP, 13f, resources.displayMetrics)
        paint.textSize = sp
        val allowedWidth = width * if (lesson.nodes.size == 3) .29f else .38f
        val gap = 6f * density
        val edge = if (above) y - radius - gap else y + radius + gap
        val allowedHeight = ((if (above) edge else height - edge) - 4f * density).coerceAtLeast(1f)
        val metrics = paint.fontMetrics
        val scale = min(1f, min(allowedWidth / paint.measureText(label), allowedHeight / (metrics.bottom - metrics.top)))
        paint.textSize = sp * scale
        canvas.drawText(label, x, if (above) edge - metrics.bottom * scale else edge - metrics.top * scale, paint)
    }

    private fun drawGlyph(canvas: Canvas, glyph: HealthBodyGlyph, x: Float, y: Float, color: Int) {
        canvas.save()
        canvas.translate(x, y)
        canvas.scale(radius * .62f, radius * .62f)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = .14f
        paint.color = color
        line.reset()
        when (glyph) {
            HealthBodyGlyph.HEART -> {
                line.moveTo(0f, .84f)
                line.cubicTo(-.30f, .55f, -.94f, .15f, -.94f, -.30f)
                line.cubicTo(-.94f, -.86f, -.30f, -1.03f, 0f, -.55f)
                line.cubicTo(.30f, -1.03f, .94f, -.86f, .94f, -.30f)
                line.cubicTo(.94f, .15f, .30f, .55f, 0f, .84f)
                line.close()
            }
            HealthBodyGlyph.LUNG -> {
                canvas.drawOval(-.92f, -.54f, -.18f, .78f, paint)
                canvas.drawOval(.18f, -.54f, .92f, .78f, paint)
                line.moveTo(0f, -.91f); line.lineTo(0f, -.14f); line.lineTo(-.52f, .23f)
                line.moveTo(0f, -.14f); line.lineTo(.52f, .23f)
            }
            HealthBodyGlyph.TISSUE -> {
                canvas.drawCircle(0f, -.49f, .36f, paint)
                canvas.drawCircle(-.44f, .33f, .36f, paint)
                canvas.drawCircle(.44f, .33f, .36f, paint)
            }
            HealthBodyGlyph.AIR -> {
                line.moveTo(-.96f, -.38f); line.lineTo(.43f, -.38f)
                line.cubicTo(.99f, -.38f, .94f, -.96f, .54f, -.85f)
                line.moveTo(-.78f, .10f); line.lineTo(.82f, .10f)
                line.moveTo(-.94f, .58f); line.lineTo(.34f, .58f)
                line.cubicTo(.79f, .58f, .75f, 1f, .45f, .93f)
            }
            HealthBodyGlyph.CELL -> {
                canvas.drawOval(-.92f, -.72f, .92f, .72f, paint)
                canvas.drawCircle(-.20f, .04f, .31f, paint)
                canvas.drawCircle(.43f, -.16f, .12f, paint)
            }
            HealthBodyGlyph.MOLECULE -> {
                canvas.drawCircle(-.49f, -.17f, .40f, paint)
                canvas.drawCircle(.42f, -.44f, .33f, paint)
                canvas.drawCircle(.40f, .53f, .33f, paint)
                line.moveTo(-.09f, -.27f); line.lineTo(.11f, -.36f)
                line.moveTo(-.18f, .09f); line.lineTo(.13f, .36f)
            }
            HealthBodyGlyph.NEURON -> {
                canvas.drawCircle(-.30f, 0f, .36f, paint)
                line.moveTo(-.47f, -.30f); line.lineTo(-.65f, -.83f)
                line.moveTo(-.64f, .12f); line.lineTo(-.91f, .39f)
                line.moveTo(-.30f, .38f); line.lineTo(-.38f, .82f)
                line.moveTo(.06f, 0f); line.lineTo(.56f, 0f); line.lineTo(.90f, -.36f)
                line.moveTo(.56f, 0f); line.lineTo(.90f, .36f)
            }
            HealthBodyGlyph.FOOD -> {
                line.moveTo(-.87f, -.53f); line.lineTo(.87f, -.53f); line.lineTo(.63f, .52f)
                line.quadTo(0f, .99f, -.63f, .52f); line.close()
                line.moveTo(-.55f, -.13f); line.lineTo(.55f, -.13f)
            }
            HealthBodyGlyph.FILTER -> {
                line.moveTo(-.88f, -.67f); line.lineTo(.88f, -.67f); line.lineTo(.22f, .22f)
                line.lineTo(.22f, .79f); line.lineTo(-.22f, .63f); line.lineTo(-.22f, .22f); line.close()
                line.moveTo(-.58f, -.34f); line.lineTo(.58f, -.34f)
            }
        }
        canvas.drawPath(line, paint)
        canvas.restore()
    }

    private fun color(tone: HealthBodyTone) = when (tone) {
        HealthBodyTone.FLOW -> if (dark) 0xff63dbc0.toInt() else 0xff16846d.toInt()
        HealthBodyTone.OXYGEN -> if (dark) 0xffffa499.toInt() else 0xffbb5044.toInt()
        HealthBodyTone.RETURN -> if (dark) 0xff8fbbff.toInt() else 0xff3f71a9.toInt()
        HealthBodyTone.SIGNAL -> if (dark) 0xffd1b7ff.toInt() else 0xff7658a7.toInt()
        HealthBodyTone.ENERGY -> if (dark) 0xfff1c175.toInt() else 0xffa16a17.toInt()
    }
}
