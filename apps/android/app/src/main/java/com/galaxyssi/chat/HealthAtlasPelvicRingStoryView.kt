package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.view.View
import kotlin.math.sin

internal class HealthAtlasPelvicRingStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.PELVIC_LOAD_TRANSFER) {
    private val plate = requireNotNull(context.getDrawable(R.drawable.health_atlas_pelvic_ring)).apply {
        setBounds(0, 49, 360, 329)
    }
    private val entry = Path().apply {
        moveTo(180f, 44f); lineTo(180f, 106f)
    }
    private val left = pelvicRoute(-1f)
    private val right = pelvicRoute(1f)
    private val ring = Path().apply {
        moveTo(145f, 123f); cubicTo(123f, 112f, 82f, 117f, 78f, 166f)
        cubicTo(72f, 203f, 104f, 229f, 144f, 238f)
        quadTo(180f, 245f, 216f, 238f)
        cubicTo(256f, 229f, 288f, 203f, 282f, 166f)
        cubicTo(278f, 117f, 237f, 112f, 215f, 123f)
    }
    private val input = track(entry)
    private val leftMeasure = track(left)
    private val rightMeasure = track(right)
    private val routeInk = 0xff307b75
    private val routeTint = 0xffd3eee3
    private val highlight = 0xffffe491

    init {
        tag = "atlas-function-pelvic-ring-art"
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
    }

    override fun scene(c: Canvas, step: Int, t: Float) {
        plate.draw(c)
        when (step) {
            0 -> orientation(c, t)
            1 -> transfer(c, t, 0f)
            2 -> transfer(c, t, .8f * smooth(t))
            else -> transfer(c, t, .8f * (1f - smooth(t)))
        }
    }

    private fun orientation(c: Canvas, t: Float) {
        val pulse = sin(t * Math.PI).toFloat()
        ink(0xff78ada3, 2.2f + 1.8f * pulse)
        paint.alpha = (125 + 115 * pulse).toInt()
        c.drawPath(ring, paint)
        paint.alpha = 255
        guide(c, R.string.health_atlas_pelvic_ring_sacrum, 180f, 27f, 180f, 131f)
        guide(c, R.string.health_atlas_pelvic_ring_joint, 69f, 27f, 147f, 125f)
        guide(c, R.string.health_atlas_pelvic_ring_socket, 293f, 27f, 267f, 198f)
        line(c, 180f, 248f, 180f, 315f, routeInk, 1f)
        disc(c, 180f, 237f, 3.5f, routeInk, cream)
        label(c, R.string.health_atlas_pelvic_ring_symphysis, 180f, 339f, 214f)
    }

    private fun transfer(c: Canvas, t: Float, shift: Float) {
        val fraction = .5f + shift / 2f
        stroke(c, entry, routeTint, 8f)
        stroke(c, entry, routeInk, 3.4f)
        drawRoute(c, left, leftMeasure, 1f - fraction, t)
        drawRoute(c, right, rightMeasure, fraction, t)
        if (t < .24f) trace(c, input, t / .24f, 4.7f)
        val scaleY = 340f
        line(c, 83f, scaleY, 277f, scaleY, 0xff85a4a3, 1.5f)
        disc(c, 83f, scaleY, 3.4f, 0xffb1cac5)
        disc(c, 277f, scaleY, 3.4f, 0xffb1cac5)
        disc(c, 180f + shift * 97f, scaleY, 5.2f, routeInk, cream)
        label(c, R.string.health_atlas_pelvic_ring_incoming, 180f, 24f, 290f)
    }

    private fun drawRoute(c: Canvas, route: Path, measure: PathMeasure, share: Float, t: Float) {
        stroke(c, route, routeTint, 5f + 5f * share)
        stroke(c, route, routeInk, 1.15f + 4f * share)
        val endX = if (route === left) 62f else 298f
        arrow(c, endX, 286f, endX, 310f, routeInk)
        if (t >= .24f) trace(c, measure, (t - .24f) / .76f, 2.8f + 2.8f * share)
    }

    private fun trace(c: Canvas, route: PathMeasure, t: Float, radius: Float) {
        at(route, t) { x, y ->
            disc(c, x, y, radius, highlight, routeInk)
        }
    }

    private fun guide(c: Canvas, title: Int, x: Float, y: Float, xx: Float, yy: Float) {
        val start = y + 7f
        val elbowX = x + if (xx < x) -13f else if (xx > x) 13f else 0f
        line(c, x, start, elbowX, start + 13f, 0xff709593, 1f)
        line(c, elbowX, start + 13f, xx, yy, 0xff709593, 1f)
        disc(c, xx, yy, 3.1f, routeInk, cream)
        label(c, title, x, y, 107f)
    }

    private fun pelvicRoute(side: Float) = Path().apply {
        moveTo(180f, 106f)
        cubicTo(180f + side * 20f, 113f, 180f + side * 29f, 118f, 180f + side * 40f, 128f)
        cubicTo(180f + side * 58f, 148f, 180f + side * 66f, 175f, 180f + side * 84f, 197f)
        cubicTo(180f + side * 99f, 215f, 180f + side * 109f, 223f, 180f + side * 111f, 251f)
        quadTo(180f + side * 114f, 276f, 180f + side * 118f, 287f)
    }

    private fun smooth(t: Float) = t * t * (3f - 2f * t)
}
