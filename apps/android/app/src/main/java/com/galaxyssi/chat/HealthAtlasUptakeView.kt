package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.RectF
import android.graphics.Shader
import android.view.View
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasUptakeView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
    private val shape = Path()
    private val trace = Path()
    private val point = FloatArray(2)
    private val bounds = RectF()
    private val field = LinearGradient(0f, 0f, 0f, 344f, intArrayOf(0xffe5f3f8.toInt(), 0xfffff4df.toInt(), 0xffe5f3f8.toInt()),
        floatArrayOf(0f, .46f, 1f), Shader.TileMode.CLAMP)
    private val membrane = LinearGradient(0f, -2f, 0f, 12f, 0xffdcaa54.toInt(), 0xffffe4a2.toInt(), Shader.TileMode.CLAMP)
    private val receptor = LinearGradient(0f, 35f, 0f, 74f, 0xff9c91d6.toInt(), 0xff52488a.toInt(), Shader.TileMode.CLAMP)
    private val channel = LinearGradient(-16f, 0f, 16f, 0f, 0xff237084.toInt(), 0xff74c5cb.toInt(), Shader.TileMode.MIRROR)
    private val routes = listOf(
        route { moveTo(79f, 42f); cubicTo(126f, 14f, 150f, 19f, 171f, 48f) },
        route { moveTo(171f, 105f); cubicTo(165f, 127f, 138f, 134f, 109f, 139f) },
        route { moveTo(103f, 153f); cubicTo(100f, 180f, 115f, 188f, 146f, 188f); lineTo(276f, 188f) },
        route { moveTo(275f, 204f); cubicTo(278f, 224f, 259f, 234f, 244f, 242f) },
    )
    var phase = 0f
        set(value) {
            val previous = HealthAtlasFunctionStory.chapter(field)
            field = HealthAtlasFunctionStory.safePhase(value)
            if (previous != HealthAtlasFunctionStory.chapter(field)) describe()
            invalidate()
        }

    init {
        tag = "atlas-function-uptake-art"
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        describe()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val maxHeight = (resources.displayMetrics.density * 390).toInt()
        setMeasuredDimension(width, resolveSize(width.coerceAtMost(maxHeight), heightMeasureSpec))
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val chapter = HealthAtlasFunctionStory.chapter(phase)
        val t = HealthAtlasFunctionStory.fraction(phase)
        val scale = minOf(width, height) / 344f
        canvas.save()
        canvas.translate((width - 344f * scale) / 2f, (height - 344f * scale) / 2f)
        canvas.scale(scale, scale)
        style(0xffe5f3f8.toInt())
        paint.shader = field
        bounds.set(0f, 0f, 344f, 344f)
        canvas.drawRoundRect(bounds, 8f, 8f, paint)
        paint.shader = null

        val fused = chapter >= 4 || chapter == 3 && t >= .64f
        val neck = if (chapter == 3 && fused) (1f - t) * 123f else 0f
        bilayer(canvas, 75f, 0f)
        bilayer(canvas, 279f, neck)
        receptor(canvas, chapter > 0 || t >= .88f)
        val insulinRoute = routes[0]
        insulinRoute.getPosTan(insulinRoute.length * if (chapter == 0) t else 1f, point, null)
        insulin(canvas, point[0], point[1])
        label(canvas, context.getString(R.string.health_atlas_uptake_insulin), 14f, 57f, true)
        label(canvas, context.getString(R.string.health_atlas_uptake_receptor), 211f, 60f, true)
        node(canvas, "IRS", 80f, 126f, 57f, chapter >= 1)
        if (chapter >= 1) dot(canvas, 129f, 128f, 4f, 0xffe3a436.toInt())
        node(canvas, "PI3K", 113f, 173f, 63f, chapter >= 2)
        node(canvas, "PIP3", 181f, 173f, 58f, chapter > 2 || chapter == 2 && t >= .55f)
        node(canvas, "AKT", 246f, 173f, 63f, chapter > 2 || chapter == 2 && t >= .86f)
        arrow(canvas, 175f, 207f, 206f, 207f)
        arrow(canvas, 239f, 207f, 272f, 207f)
        if (chapter in 1..3) signal(canvas, routes[chapter], t)
        if (!fused) {
            val move = if (chapter == 3) t / .64f else 0f
            val centerX = 181f + 78f * move
            val centerY = 232f + 22f * move
            vesicle(canvas, centerX, centerY)
            label(canvas, "GLUT4", centerX - 70f, centerY + 11f, true)
        } else {
            transporter(canvas, 259f, 283f - neck, 1f)
            label(canvas, "GLUT4", 286f, 263f, true)
        }
        if (chapter == 4) {
            for (i in 0..2) {
                val passage = (t * 1.55f - i * .30f).coerceIn(0f, 1f)
                val y = 321f - passage * 103f
                val x = 259f + if (y < 257f) (i - 1) * (257f - y) * .42f else (i - 1) * ((y - 297f) / 24f).coerceIn(0f, 1f) * 24f
                glucose(canvas, x, y)
            }
            arrow(canvas, 208f, 317f, 208f, 245f)
        } else for (x in 235..283 step 24) glucose(canvas, x.toFloat(), 321f)
        label(canvas, context.getString(R.string.health_atlas_uptake_outside), 14f, 25f)
        label(canvas, context.getString(R.string.health_atlas_uptake_inside), 14f, 112f)
        label(canvas, context.getString(R.string.health_atlas_uptake_glucose), 14f, 321f)
        canvas.restore()
    }

    private fun bilayer(canvas: Canvas, y: Float, neck: Float) {
        canvas.save()
        canvas.translate(0f, y)
        shape.rewind()
        shape.moveTo(12f, 4f)
        if (neck > 0f) {
            shape.lineTo(235f, 4f)
            shape.cubicTo(247f, 3f, 236f, 4f - neck, 259f, 4f - neck)
            shape.cubicTo(281f, 4f - neck, 267f, 3f, 282f, 4f)
        }
        shape.lineTo(332f, 4f)
        stroke(canvas, shape, 0xffac793e.toInt(), 12f)
        paint.shader = membrane
        paint.strokeWidth = 8f
        canvas.drawPath(shape, paint)
        paint.shader = null
        for (x in 16..328 step 12) {
            if (neck > 0f && x in 231..290) continue
            dot(canvas, x.toFloat(), 1f, 1.6f, 0xfffff1c7.toInt())
            dot(canvas, x.toFloat(), 8f, 1.4f, 0xffba8144.toInt())
        }
        canvas.restore()
    }

    private fun receptor(canvas: Canvas, active: Boolean) {
        for (i in 0..1) {
            val x = 162f + i * 19f
            capsule(canvas, x - 5f, 58f, x + 5f, 101f, 5f, 0xff31887f.toInt())
            dot(canvas, x, 104f, 4f, if (active) 0xffebac43.toInt() else 0xff568c92.toInt())
        }
        shape.rewind()
        shape.moveTo(140f, 41f)
        shape.cubicTo(152f, 71f, 192f, 71f, 204f, 41f)
        style(0xff6c65ab.toInt(), Paint.Style.STROKE)
        paint.strokeWidth = 12f
        paint.shader = receptor
        canvas.drawPath(shape, paint)
        paint.shader = null
    }

    private fun insulin(canvas: Canvas, x: Float, y: Float) {
        for (i in 0..5) {
            val angle = i * 1.05f
            val dx = cos(angle) * 7f
            val dy = sin(angle) * 6f
            dot(canvas, x + dx, y + dy, 4.5f, 0xff357ba9.toInt())
            dot(canvas, x + dx - 1f, y + dy - 1.5f, 2.6f, 0xffabd7ea.toInt())
        }
    }

    private fun vesicle(canvas: Canvas, x: Float, y: Float) {
        dot(canvas, x, y, 25f, 0xffc58f45.toInt())
        dot(canvas, x, y, 22f, 0xfff8df99.toInt())
        dot(canvas, x, y, 19f, 0xfffff4d5.toInt())
        transporter(canvas, x, y + 23f, .74f)
    }

    private fun transporter(canvas: Canvas, x: Float, y: Float, scale: Float) {
        canvas.save()
        canvas.translate(x, y)
        canvas.scale(scale, scale)
        style(0xff246880.toInt())
        paint.shader = channel
        bounds.set(-17f, -13f, 17f, 16f)
        canvas.drawRoundRect(bounds, 8f, 8f, paint)
        capsule(canvas, -5f, -14f, 5f, 16f, 4f, 0xffdff2eb.toInt())
        canvas.restore()
    }

    private fun glucose(canvas: Canvas, x: Float, y: Float) {
        shape.rewind()
        repeat(6) { i ->
            val angle = (i + .5f) * 1.0472f
            val px = x + cos(angle) * 7f
            val py = y + sin(angle) * 7f
            if (i == 0) shape.moveTo(px, py) else shape.lineTo(px, py)
        }
        shape.close()
        style(0xfffaf2d1.toInt())
        canvas.drawPath(shape, paint)
        stroke(canvas, shape, 0xff996019.toInt(), 1.8f)
    }

    private fun signal(canvas: Canvas, path: PathMeasure, t: Float) {
        trace.rewind()
        val distance = t * path.length
        if (path.getSegment(0f, distance, trace, true)) stroke(canvas, trace, 0xff007973.toInt(), 2.5f)
        if (!path.getPosTan(distance, point, null)) return
        dot(canvas, point[0], point[1], 7f, 0xffd8faf0.toInt())
        dot(canvas, point[0], point[1], 4f, 0xff007973.toInt())
    }

    private fun arrow(canvas: Canvas, x: Float, y: Float, toX: Float, toY: Float) {
        val angle = atan2(toY - y, toX - x)
        shape.rewind()
        shape.moveTo(x, y)
        shape.lineTo(toX, toY)
        shape.lineTo(toX - cos(angle - .58f) * 5f, toY - sin(angle - .58f) * 5f)
        shape.moveTo(toX, toY)
        shape.lineTo(toX - cos(angle + .58f) * 5f, toY - sin(angle + .58f) * 5f)
        stroke(canvas, shape, 0xff516f70.toInt(), 1.5f)
    }

    private fun node(canvas: Canvas, text: String, x: Float, y: Float, width: Float, active: Boolean) {
        capsule(canvas, x, y, x + width, y + 26f, 7f, if (active) 0xffb1e0d3.toInt() else 0xffe1e7e9.toInt())
        label(canvas, text, x + 12f, y + 18f, true)
    }

    private fun label(canvas: Canvas, text: String, x: Float, y: Float, strong: Boolean = false) {
        style(0xff21474d.toInt())
        paint.textSize = if (strong) 12f else 11f
        paint.isFakeBoldText = strong
        canvas.drawText(text, x, y, paint)
        paint.isFakeBoldText = false
    }

    private fun dot(canvas: Canvas, x: Float, y: Float, radius: Float, ink: Int) {
        style(ink)
        canvas.drawCircle(x, y, radius, paint)
    }
    private fun capsule(canvas: Canvas, left: Float, top: Float, right: Float, bottom: Float, radius: Float, ink: Int) {
        style(ink)
        bounds.set(left, top, right, bottom)
        canvas.drawRoundRect(bounds, radius, radius, paint)
    }
    private fun stroke(canvas: Canvas, path: Path, ink: Int, width: Float) {
        style(ink, Paint.Style.STROKE)
        paint.strokeWidth = width
        canvas.drawPath(path, paint)
    }
    private fun style(ink: Int, style: Paint.Style = Paint.Style.FILL) {
        paint.shader = null
        paint.color = ink
        paint.style = style
    }
    private fun describe() {
        contentDescription = context.getString(HealthAtlasFunctionStory.chapters[HealthAtlasFunctionStory.chapter(phase)].second)
    }
    private fun route(shape: Path.() -> Unit) = PathMeasure(Path().apply(shape), false)
}
