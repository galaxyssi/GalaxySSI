package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.RectF
import android.graphics.Shader
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

internal data class HealthAtlasUptakeMotion(val chapter: Int, val fraction: Float) {
    val approach = if (chapter >= 3) ease(if (chapter == 3) fraction / .58f else 1f) else 0f
    val flatten = if (chapter >= 3) ease(if (chapter == 3) (fraction - .58f) / .42f else 1f) else 0f
    val radiusY = RADIUS * (1f - flatten)
    val opening = 90f * flatten
    val vesicleX = 158f + 87f * approach
    val vesicleY = 210f + (SURFACE - RADIUS - 210f) * approach +
        RADIUS - radiusY * cos(opening * DEGREES)
    val transporterX = vesicleX + RADIUS
    val transporterY = vesicleY
    val transporterRotation = -90f * (1f - flatten)

    fun glucoseTravel(index: Int) =
        if (chapter == 4) ease(fraction * 1.63f - index * .21f) else 0f

    private fun ease(value: Float): Float {
        val bounded = value.coerceIn(0f, 1f)
        return bounded * bounded * (3f - 2f * bounded)
    }

    companion object {
        const val SURFACE = 275f
        const val RADIUS = 23f
        const val DEGREES = .017453293f
    }
}

internal class HealthAtlasUptakeView(context: Context) : HealthAtlasFunctionArt(context, HealthAtlasFunctionStory.GLUCOSE) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
    private val shape = Path()
    private val trace = Path()
    private val point = FloatArray(2)
    private val bounds = RectF()
    private val field = LinearGradient(0f, 0f, 0f, 344f, intArrayOf(0xffdceef7.toInt(), 0xfffff8e8.toInt(), 0xffe4f1f7.toInt()),
        floatArrayOf(0f, .54f, 1f), Shader.TileMode.CLAMP)
    private val receptor = LinearGradient(0f, 35f, 0f, 74f, 0xff9c91d6.toInt(), 0xff52488a.toInt(), Shader.TileMode.CLAMP)
    private val channel = LinearGradient(-16f, 0f, 16f, 0f, 0xff237084.toInt(), 0xff74c5cb.toInt(), Shader.TileMode.MIRROR)
    private val routes = listOf(
        route { moveTo(87f, 40f); cubicTo(119f, 14f, 151f, 21f, 169f, 45f) },
        route { moveTo(171f, 98f); cubicTo(170f, 114f, 142f, 113f, 127f, 114f) },
        route { moveTo(123f, 124f); cubicTo(132f, 126f, 138f, 133f, 138f, 165f) },
        route { moveTo(293f, 179f); cubicTo(293f, 203f, 228f, 186f, 228f, 214f) },
    )
    init { tag = "atlas-function-uptake-art" }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val chapter = story.chapter(phase)
        val t = story.fraction(phase)
        val motion = HealthAtlasUptakeMotion(chapter, t)
        val scale = minOf(width, height) / 344f
        canvas.save()
        canvas.translate((width - 344f * scale) / 2f, (height - 344f * scale) / 2f)
        canvas.scale(scale, scale)
        style(0xffe5f3f8.toInt())
        paint.shader = field
        bounds.set(0f, 0f, 344f, 344f)
        canvas.drawRoundRect(bounds, 8f, 8f, paint)
        paint.shader = null

        bilayer(canvas, 71f)
        bilayer(canvas, HealthAtlasUptakeMotion.SURFACE, motion)
        if (motion.flatten == 0f) vesicle(canvas, motion.vesicleX, motion.vesicleY)
        val bound = chapter > 0 || t >= .95f
        receptor(canvas, bound)
        val insulinRoute = routes[0]
        insulinRoute.getPosTan(insulinRoute.length * if (chapter == 0) minOf(t / .95f, 1f) else 1f, point, null)
        insulin(canvas, point[0], point[1])
        label(canvas, context.getString(R.string.health_atlas_uptake_insulin), 14f, 48f, true)
        label(canvas, context.getString(R.string.health_atlas_uptake_receptor), 217f, 62f, true)

        val irsActive = chapter > 1 || chapter == 1 && t >= .82f
        val relay = if (chapter > 2) 1f else if (chapter == 2) t else 0f
        for (i in 1..3) {
            val progress = when (i) {
                2 -> relay * 3.5f
                else -> if (chapter > i) 1f else if (chapter == i) t else 0f
            }.coerceIn(0f, 1f)
            signal(canvas, routes[i], progress, chapter == i && progress < 1f)
        }
        node(canvas, "IRS", 73f, 103f, 54f, irsActive, 0xffb9cce9.toInt())
        if (irsActive) dot(canvas, 124f, 105f, 4f, 0xffdb9f31.toInt())
        transfer(canvas, 80f, 160f, relay, .29f, .57f)
        transfer(canvas, 222f, 262f, relay, .57f, .90f)
        node(canvas, "PI3K", 111f, 132f, 54f, relay >= .26f, 0xffb9cce9.toInt())
        node(canvas, "PIP2", 23f, 157f, 54f, relay >= .29f, 0xffc6cde9.toInt())
        node(canvas, "PIP3", 164f, 157f, 54f, relay >= .57f, 0xffa9dbe0.toInt())
        node(canvas, "AKT", 266f, 157f, 54f, relay >= .90f, 0xffb8dec1.toInt())
        transporter(canvas, motion.transporterX, motion.transporterY, .79f + .11f * motion.flatten, motion.transporterRotation)
        label(canvas, "GLUT4", motion.transporterX - 54f, motion.transporterY - 17f, true)
        for (i in 0..2) {
            val travel = motion.glucoseTravel(i)
            val y = 314f - travel * 88f
            val spread = (abs(y - HealthAtlasUptakeMotion.SURFACE) / 34f).coerceIn(0f, 1f) * 18f
            glucose(canvas, 268f + (i - 1) * spread, y)
        }
        label(canvas, context.getString(R.string.health_atlas_uptake_outside), 14f, 25f)
        label(canvas, context.getString(R.string.health_atlas_uptake_inside), 14f, 92f)
        label(canvas, context.getString(R.string.health_atlas_uptake_glucose), 14f, 317f)
        canvas.restore()
    }

    private fun bilayer(canvas: Canvas, y: Float, motion: HealthAtlasUptakeMotion? = null) {
        shape.rewind()
        shape.moveTo(5f, y)
        val curved = motion != null && motion.flatten > 0f && motion.radiusY > .1f
        if (motion != null && curved) {
            // Open the bottom of the vesicle into the bilayer, then flatten the cap.
            val opening = motion.opening.coerceAtLeast(.5f)
            val r = HealthAtlasUptakeMotion.RADIUS
            val x = motion.vesicleX
            val cy = y - motion.radiusY * cos(opening * HealthAtlasUptakeMotion.DEGREES)
            bounds.set(x - r, cy - motion.radiusY, x + r, cy + motion.radiusY)
            shape.arcTo(bounds, 90f + opening, 360f - 2f * opening, false)
        }
        shape.lineTo(339f, y)
        stroke(canvas, shape, 0xffb98545.toInt(), 9f)
        stroke(canvas, shape, 0xfff7d589.toInt(), 6.5f)
        stroke(canvas, shape, 0xffffedbd.toInt(), 2f)
    }

    private fun receptor(canvas: Canvas, active: Boolean) {
        for (i in 0..1) {
            val x = 160f + i * 18f
            capsule(canvas, x - 5f, 55f, x + 5f, 96f, 5f, 0xff31887f.toInt())
            dot(canvas, x, 99f, 4f, if (active) 0xffebac43.toInt() else 0xff568c92.toInt())
        }
        shape.rewind()
        shape.moveTo(141f, 38f)
        shape.cubicTo(150f, 64f, 188f, 64f, 197f, 38f)
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
        val r = HealthAtlasUptakeMotion.RADIUS
        style(0xffb98545.toInt(), Paint.Style.STROKE)
        paint.strokeWidth = 9f
        canvas.drawCircle(x, y, r, paint)
        paint.color = 0xfff7d589.toInt()
        paint.strokeWidth = 6.5f
        canvas.drawCircle(x, y, r, paint)
        paint.color = 0xffffedbd.toInt()
        paint.strokeWidth = 2f
        canvas.drawCircle(x, y, r, paint)
    }

    private fun transporter(canvas: Canvas, x: Float, y: Float, scale: Float, rotation: Float) {
        canvas.save()
        canvas.translate(x, y)
        canvas.rotate(rotation)
        canvas.scale(scale, scale)
        style(0xff246880.toInt())
        paint.shader = channel
        bounds.set(-17f, -13f, 17f, 16f)
        canvas.drawRoundRect(bounds, 8f, 8f, paint)
        capsule(canvas, -4f, -15f, 4f, 17f, 3f, 0xffdff2eb.toInt())
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

    private fun signal(canvas: Canvas, path: PathMeasure, t: Float, moving: Boolean) {
        trace.rewind()
        if (path.getSegment(0f, path.length, trace, true)) stroke(canvas, trace, 0xffa0b4bb.toInt(), 1.3f)
        trace.rewind()
        val distance = t * path.length
        if (path.getSegment(0f, distance, trace, true)) stroke(canvas, trace, 0xff007973.toInt(), 2.5f)
        if (!moving || t <= 0f || !path.getPosTan(distance, point, null)) return
        dot(canvas, point[0], point[1], 7f, 0xffd8faf0.toInt())
        dot(canvas, point[0], point[1], 4f, 0xff007973.toInt())
    }

    private fun arrow(canvas: Canvas, x: Float, y: Float, toX: Float, active: Boolean) {
        shape.rewind()
        shape.moveTo(x, y)
        shape.lineTo(toX, y)
        shape.lineTo(toX - 4f, y - 3f)
        shape.moveTo(toX, y)
        shape.lineTo(toX - 4f, y + 3f)
        stroke(canvas, shape, if (active) 0xff007973.toInt() else 0xff728d92.toInt(), 1.5f)
    }

    private fun transfer(canvas: Canvas, from: Float, to: Float, relay: Float, start: Float, finish: Float) {
        arrow(canvas, from, 168f, to, relay >= finish)
        val travel = ((relay - start) / (finish - start)).coerceIn(0f, 1f)
        if (travel > 0f && travel < 1f) dot(canvas, from + (to - from) * travel, 168f, 3f, 0xff007973.toInt())
    }

    private fun node(canvas: Canvas, text: String, x: Float, y: Float, width: Float, active: Boolean, accent: Int) {
        capsule(canvas, x, y, x + width, y + 22f, 7f, if (active) accent else 0xffe1e7e9.toInt())
        label(canvas, text, x + 13f, y + 15f, true)
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
    private fun route(shape: Path.() -> Unit) = PathMeasure(Path().apply(shape), false)
}
