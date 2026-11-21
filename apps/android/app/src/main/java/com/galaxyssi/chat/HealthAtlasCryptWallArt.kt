package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import kotlin.math.atan2

// Synthetic section coordinates, wall depth, and playback phase are educational, not measurements.
internal abstract class HealthAtlasCryptWallArt(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    protected class Pose {
        var x = 0f
        var y = 0f
        var dx = 1f
        var dy = 0f
        var angle = 0f

        fun xAt(along: Float, outward: Float) = x + dx * along - dy * outward
        fun yAt(along: Float, outward: Float) = y + dy * along + dx * outward
    }

    protected val wallInk = 0xff906272
    protected val nucleusInk = 0xff805675
    protected val cellDepth = 20f
    protected val panethSlot = 13
    protected val stemSlot = 14
    protected val endocrineSlot = 21
    protected val lastVillusSlot = 27

    private val apical = Path().apply {
        moveTo(35f, 74f)
        cubicTo(67f, 73f, 95f, 84f, 102f, 121f)
        cubicTo(110f, 162f, 101f, 211f, 112f, 248f)
        cubicTo(121f, 279f, 147f, 291f, 175f, 289f)
        cubicTo(202f, 287f, 227f, 270f, 233f, 239f)
        cubicTo(239f, 210f, 224f, 174f, 232f, 142f)
        cubicTo(240f, 110f, 269f, 104f, 278f, 75f)
        cubicTo(286f, 51f, 298f, 42f, 318f, 44f)
    }
    private val laminaPropria = Path(apical).apply {
        lineTo(332f, 53f)
        quadTo(339f, 57f, 339f, 73f)
        lineTo(339f, 303f)
        quadTo(339f, 326f, 318f, 326f)
        lineTo(48f, 326f)
        quadTo(21f, 326f, 21f, 306f)
        lineTo(21f, 93f)
        quadTo(21f, 78f, 35f, 74f)
        close()
    }
    private val measure = PathMeasure(apical, false)
    private val samplePosition = FloatArray(2)
    private val sampleTangent = FloatArray(2)
    private val slots = 29
    protected val cellSpan = measure.length / slots
    private val boundaries = Array(slots + 1) { index -> Pose().also { sample(index.toFloat(), it) } }
    private val centers = Array(slots) { index -> Pose().also { sample(index + .5f, it) } }
    private val basement = Path().apply {
        for (i in boundaries.indices) {
            val b = boundaries[i]
            if (i == 0) moveTo(b.xAt(0f, cellDepth), b.yAt(0f, cellDepth))
            else lineTo(b.xAt(0f, cellDepth), b.yAt(0f, cellDepth))
        }
    }
    private val cells = Array(slots) { i ->
        val a = boundaries[i]
        val b = boundaries[i + 1]
        val middle = centers[i]
        Path().apply {
            moveTo(a.x, a.y)
            lineTo(middle.x, middle.y)
            lineTo(b.x, b.y)
            lineTo(b.xAt(0f, cellDepth), b.yAt(0f, cellDepth))
            lineTo(a.xAt(0f, cellDepth), a.yAt(0f, cellDepth))
            close()
        }
    }
    private val panethShape = Path().apply {
        moveTo(-5.9f, .6f)
        quadTo(-6.2f, 6f, -8.4f, 13f)
        quadTo(-10f, 20f, 0f, 19.5f)
        quadTo(10f, 20f, 8.4f, 13f)
        quadTo(6.2f, 6f, 5.9f, .6f)
        close()
    }

    protected fun center(slot: Int) = centers[slot]

    protected fun sample(slotPosition: Float, pose: Pose) {
        measure.getPosTan(slotPosition.coerceIn(0f, slots.toFloat()) * cellSpan, samplePosition, sampleTangent)
        pose.x = samplePosition[0]
        pose.y = samplePosition[1]
        pose.dx = sampleTangent[0]
        pose.dy = sampleTangent[1]
        pose.angle = Math.toDegrees(atan2(pose.dy, pose.dx).toDouble()).toFloat()
    }

    protected inline fun atPose(c: Canvas, pose: Pose, draw: () -> Unit) {
        val saved = c.save()
        c.translate(pose.x, pose.y)
        c.rotate(pose.angle)
        draw()
        c.restoreToCount(saved)
    }

    protected fun wall(c: Canvas, feature: Int) {
        rounded(c, 21f, 24f, 339f, 326f, 16f, 0xffe8f4f0)
        filled(c, laminaPropria, 0xfff1dbd5)
        for (i in 0..8) {
            val x = 47f + (i % 2) * 11f
            val y = 115f + i * 21f
            line(c, x, y, x + 18f, y + 7f, 0xffe1bbb8, 1f)
        }
        for (i in cells.indices) {
            val fill = when {
                i == feature -> 0xfff5d7c4
                i % 4 == 1 -> 0xfff2c4b6
                i % 4 == 3 -> 0xfff7d7c4
                else -> 0xffefbbae
            }
            filled(c, cells[i], fill)
            stroke(c, cells[i], 0xffb58489, .75f)
            if (i != feature) atPose(c, centers[i]) {
                flatOval(c, -2.7f, 9f, 2.7f, 16.2f, 0xffa77792)
                line(c, -cellSpan * .39f, 2f, cellSpan * .39f, 2f, 0xfffae6cf, 1.25f)
            }
        }
        stroke(c, apical, 0xffb38387, 1.05f)
        stroke(c, basement, wallInk, 1.45f)
    }

    protected fun panethBody(c: Canvas, active: Boolean) {
        val edge = if (active) 0xff9f514b else 0xffaa7270
        filled(c, panethShape, if (active) 0xffefa77c else 0xffe6ab95)
        stroke(c, panethShape, edge, 1.2f)
        flatOval(c, -4.4f, 12.2f, 4.4f, 17.8f, nucleusInk)
    }

    protected fun lumenLabel(c: Canvas) = label(c, R.string.health_atlas_crypt_lumen, 166f, 97f, 122f)

    protected fun leader(
        c: Canvas, text: Int, x: Float, y: Float, x2: Float, y2: Float, labelX: Float, maxWidth: Float, color: Long,
    ) {
        line(c, x, y, x2, y2, color, 1.15f)
        dot(c, x, y, 2f, color)
        label(c, text, labelX, y2 - 4f, maxWidth)
    }

    protected fun filled(c: Canvas, path: Path, color: Long) {
        ink(color)
        c.drawPath(path, paint)
    }

    protected fun dot(c: Canvas, x: Float, y: Float, radius: Float, color: Long) {
        ink(color)
        c.drawCircle(x, y, radius, paint)
    }

    protected fun ring(c: Canvas, x: Float, y: Float, radius: Float, color: Long, width: Float) {
        ink(color, width)
        c.drawCircle(x, y, radius, paint)
    }

    protected fun flatOval(c: Canvas, x1: Float, y1: Float, x2: Float, y2: Float, color: Long) {
        ink(color)
        c.drawOval(x1, y1, x2, y2, paint)
    }

    protected fun alpha(color: Long, opacity: Float) =
        (color and 0x00ffffff) or ((255f * opacity.coerceIn(0f, 1f)).toLong() shl 24)

    protected fun mix(a: Float, b: Float, t: Float) = a + (b - a) * t

    protected fun ease(t: Float, start: Float = 0f, end: Float = 1f): Float {
        val p = ((t - start) / (end - start)).coerceIn(0f, 1f)
        return p * p * (3f - 2f * p)
    }
}
