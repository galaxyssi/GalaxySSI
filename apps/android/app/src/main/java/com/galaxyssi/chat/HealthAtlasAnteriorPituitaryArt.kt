package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure

/** Drawing coordinates, symbols, and phase timings are schematic educational inputs. */
internal abstract class HealthAtlasAnteriorPituitaryArt(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    protected val vesselEdge = 0xffb17a86
    protected val vesselFill = 0xfff6d9dc
    protected val pale = 0xfffffcf3
    private val sample = FloatArray(2)
    private val segment = Path()

    private val adenohypophysis = Path().apply {
        moveTo(38f, 12f)
        cubicTo(23f, 7f, 6f, 17f, 4f, 35f)
        cubicTo(2f, 54f, 20f, 63f, 39f, 60f)
        cubicTo(57f, 57f, 65f, 47f, 61f, 33f)
        cubicTo(58f, 22f, 53f, 16f, 38f, 12f)
        close()
    }
    private val neuralLobe = Path().apply {
        moveTo(52f, 0f)
        cubicTo(49f, 10f, 53f, 20f, 65f, 26f)
        cubicTo(82f, 34f, 79f, 51f, 61f, 55f)
        cubicTo(55f, 55f, 53f, 52f, 55f, 47f)
        cubicTo(63f, 30f, 47f, 25f, 42f, 15f)
        quadTo(40f, 8f, 41f, 0f)
        close()
    }

    protected fun pituitary(c: Canvas, x: Float, y: Float, scale: Float, highlight: Long) {
        c.save()
        c.translate(x, y)
        c.scale(scale, scale)
        shape(c, neuralLobe, 0xffcbbecd, 0xff887989)
        shape(c, adenohypophysis, 0xffefbdad, 0xff9a626a)
        for (i in 0..2) {
            oval(c, 11f + i * 11f, 35f - 2f * i, 18f + i * 11f, 43f - 2f * i, 0xffd88e8f, 0xffb3767e)
            disc(c, 21f + i * 10f, 49f - 2f * i, 2.3f, 0xffb3767e)
        }
        disc(c, 44f, 31f, 6f, highlight, pale)
        c.restore()
    }

    protected fun shape(c: Canvas, path: Path, fill: Long, edge: Long, weight: Float = 1.6f) {
        ink(fill)
        c.drawPath(path, paint)
        stroke(c, path, edge, weight)
    }

    protected fun vessel(c: Canvas, path: Path, width: Float = 18f) {
        stroke(c, path, vesselEdge, width + 3f)
        stroke(c, path, vesselFill, width)
    }

    protected fun cubic(x: Float, y: Float, a: Float, b: Float, d: Float, e: Float, u: Float, v: Float) =
        Path().apply { moveTo(x, y); cubicTo(a, b, d, e, u, v) }

    protected fun diamond(c: Canvas, x: Float, y: Float, radius: Float, color: Long) {
        c.save()
        c.rotate(45f, x, y)
        ink(color)
        c.drawRect(x - radius, y - radius, x + radius, y + radius, paint)
        c.restore()
    }

    protected fun marker(
        c: Canvas, route: PathMeasure, f: Float, color: Long, radius: Float = 3.6f, angular: Boolean = false,
    ) {
        if (f !in 0f..1f || !route.getPosTan(route.length * f, sample, null)) return
        if (angular) diamond(c, sample[0], sample[1], radius * .8f, color)
        else disc(c, sample[0], sample[1], radius, color)
    }

    protected fun trace(c: Canvas, route: PathMeasure, start: Float, end: Float, color: Long, width: Float) {
        segment.rewind()
        val length = route.length
        if (route.getSegment(length * unit(start), length * unit(end), segment, true)) {
            stroke(c, segment, color, width)
        }
    }

    protected fun ring(c: Canvas, x: Float, y: Float, radius: Float, color: Long, width: Float = 1.6f) {
        ink(color, width)
        c.drawCircle(x, y, radius, paint)
    }

    protected fun unit(t: Float) = t.coerceIn(0f, 1f)
    protected fun smooth(t: Float): Float = unit(t).let { it * it * (3f - 2f * it) }
    protected fun fade(color: Long, t: Float) = (color and 0x00ff_ffffL) or ((unit(t) * 255).toLong() shl 24)
    protected fun mix(a: Float, b: Float, t: Float) = a + (b - a) * t
}
