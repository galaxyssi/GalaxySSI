package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.RectF
import com.galaxyssi.chat.HealthAtlasPectoralActionAssignment as Chapter
import com.galaxyssi.chat.HealthAtlasPectoralActionMotion as Motion
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasPectoralActionStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val jointX = 223f
    private val jointY = 147f
    private val traceRadius = 125f
    private val trackBounds = RectF(jointX - traceRadius, jointY - traceRadius,
        jointX + traceRadius, jointY + traceRadius)
    private val trace = Path()
    private val fan = Path()
    private val cutInk = 0xff637d81
    private val clavicularInk = 0xff945964
    private val sternocostalInk = 0xffa65f55
    private val clavicularFill = shade(149f, 203f, 0xffe8b7c0, 0xffcb8e9d)
    private val sternocostalFill = shade(158f, 206f, 0xffdf9c90, 0xffedc2ad)
    private val bodyFill = shade(83f, 216f, 0xffd3e4e3, 0xffeef2e9)
    private val chest = Path().apply {
        moveTo(60f, 146f)
        cubicTo(62f, 112f, 111f, 85f, 149f, 84f)
        cubicTo(193f, 82f, 237f, 107f, 242f, 142f)
        cubicTo(249f, 180f, 217f, 202f, 174f, 210f)
        cubicTo(122f, 220f, 63f, 193f, 60f, 146f)
        close()
    }
    private val thorax = Path().apply {
        moveTo(82f, 147f)
        cubicTo(87f, 121f, 122f, 103f, 147f, 103f)
        cubicTo(180f, 100f, 215f, 119f, 220f, 148f)
        cubicTo(225f, 177f, 185f, 192f, 151f, 192f)
        cubicTo(119f, 192f, 75f, 176f, 82f, 147f)
        close()
    }
    private val farFan = Path().apply {
        moveTo(146f, 169f)
        cubicTo(117f, 168f, 104f, 159f, 85f, 154f)
        cubicTo(88f, 179f, 116f, 202f, 147f, 204f)
        quadTo(151f, 188f, 146f, 169f)
        close()
    }
    private val arm = Path().apply {
        moveTo(-8f, -12f)
        cubicTo(24f, -18f, 60f, -14f, 83f, -10f)
        quadTo(93f, -7f, 99f, 3f)
        lineTo(117f, 20f)
        quadTo(122f, 28f, 113f, 34f)
        quadTo(107f, 37f, 101f, 29f)
        lineTo(80f, 13f)
        quadTo(38f, 16f, -7f, 15f)
        quadTo(-21f, 4f, -8f, -12f)
        close()
    }
    private val humerus = Path().apply {
        moveTo(-8f, -8f)
        quadTo(4f, -15f, 17f, -6f)
        cubicTo(38f, -3f, 59f, -5f, 78f, -6f)
        quadTo(89f, -6f, 88f, 4f)
        quadTo(85f, 11f, 76f, 8f)
        cubicTo(55f, 5f, 38f, 4f, 17f, 7f)
        quadTo(4f, 15f, -8f, 8f)
        quadTo(-15f, 1f, -8f, -8f)
        close()
    }

    init { tag = "atlas-function-pectoral-horizontal-adduction-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val angle = Motion.angle(step, t)
        val radians = radians(angle)
        val attachX = jointX + 29f * cos(radians) - 8f * sin(radians)
        val attachY = jointY + 29f * sin(radians) + 8f * cos(radians)
        drawChest(c)
        if (step >= Chapter.SWEEP) drawSweep(c, angle, step == Chapter.RETURN)
        c.save()
        c.translate(jointX, jointY)
        c.rotate(angle)
        ink(0xffcadbd9)
        c.drawPath(arm, paint)
        stroke(c, arm, cutInk, 1.4f)
        ink(0xfff7eddb)
        c.drawPath(humerus, paint)
        stroke(c, humerus, 0xff9d8a74, 1.35f)
        line(c, 89f, 5f, 108f, 24f, 0xffb0a188, 4f)
        line(c, 29f, 7f, 38f, 7f, 0xffad9273, 1.7f)
        c.restore()

        drawPectoralFan(c, attachX, attachY, step, t)
        disc(c, jointX, jointY, 3.4f, cream, cutInk)
        label(c, R.string.health_atlas_pectoral_action_overhead, 180f, 36f, 224f)
        arrow(c, 103f, 273f, 103f, 289f, cutInk)
        label(c, R.string.health_atlas_pectoral_action_front, 103f, 311f, 146f)
        when (step) {
            Chapter.ORIGINS -> {
                leader(c, 82f, 69f, 104f, 164f, 165f, clavicularInk)
                label(c, R.string.health_atlas_pectoral_action_clavicular, 82f, 61f, 140f)
                leader(c, 70f, 229f, 104f, 157f, 190f, sternocostalInk)
                label(c, R.string.health_atlas_pectoral_action_sternocostal, 77f, 246f, 142f)
            }
            Chapter.INSERTION -> {
                val highlight = sin(t * Math.PI.toFloat())
                ink(sternocostalInk, 1.4f)
                c.drawCircle(attachX, attachY, 6f + 5f * highlight, paint)
                leader(c, 271f, 76f, 247f, attachX, attachY, sternocostalInk)
                label(c, R.string.health_atlas_pectoral_action_tendon, 271f, 68f, 150f)
            }
            else -> {
                leader(c, 245f, 77f, 224f, jointX, jointY, cutInk)
                label(c, R.string.health_atlas_pectoral_action_joint, 245f, 69f, 148f)
            }
        }
    }

    private fun drawChest(c: Canvas) {
        ink(cream)
        paint.shader = bodyFill
        c.drawPath(chest, paint)
        paint.shader = null
        stroke(c, chest, cutInk, 1.6f)
        ink(0xffe8eddf)
        c.drawPath(thorax, paint)
        stroke(c, thorax, 0xffadac98, 1.5f)
        oval(c, 102f, 118f, 143f, 178f, 0xffcadbd6, 0xff9eb5b0)
        oval(c, 157f, 118f, 200f, 178f, 0xffcadbd6, 0xff9eb5b0)
        oval(c, 136f, 93f, 158f, 113f, 0xffefe5d1, 0xff9d8a74)
        oval(c, 142f, 182f, 157f, 205f, 0xffefe5d1, 0xff9d8a74)
        ink(0xffd2a29c)
        c.drawPath(farFan, paint)
        stroke(c, farFan, 0xffb47e79, 1.3f)
    }

    private fun drawPectoralFan(c: Canvas, tx: Float, ty: Float, step: Int, t: Float) {
        val joinX = tx - 15f
        val joinY = ty + 4f
        fan.rewind()
        fan.moveTo(153f, 171f)
        fan.cubicTo(174f, 153f, 191f, 151f, 205f, 154f)
        fan.cubicTo(218f, 155f, joinX - 7f, joinY - 11f, joinX + 2f, joinY - 4f)
        fan.cubicTo(joinX - 15f, joinY + 2f, 177f, 171f, 153f, 181f)
        fan.close()
        ink(cream)
        paint.shader = clavicularFill
        c.drawPath(fan, paint)
        paint.shader = null
        stroke(c, fan, clavicularInk, 1.35f)

        fan.rewind()
        fan.moveTo(153f, 179f)
        fan.cubicTo(184f, 174f, joinX - 18f, joinY + 1f, joinX + 2f, joinY - 4f)
        fan.lineTo(joinX + 4f, joinY + 4f)
        fan.cubicTo(joinX - 17f, joinY + 17f, 180f, 206f, 155f, 206f)
        fan.quadTo(159f, 196f, 153f, 179f)
        fan.close()
        ink(cream)
        paint.shader = sternocostalFill
        c.drawPath(fan, paint)
        paint.shader = null
        stroke(c, fan, sternocostalInk, 1.35f)
        for (i in 0..4) {
            fan.rewind()
            fan.moveTo(158f, 183f + 4.4f * i)
            fan.cubicTo(183f, 181f + 4f * i, joinX - 15f, joinY + 3f * i - 3f,
                joinX + 1f, joinY - 2f + i)
            val focus = if (step == Chapter.ORIGINS) t else 0f
            stroke(c, fan, if (i % 2 == 0) 0xaafff0e6 else sternocostalInk, 1f + .4f * focus)
        }
        fan.rewind()
        fan.moveTo(163f, 169f)
        fan.quadTo(187f, 152f, joinX, joinY - 4f)
        stroke(c, fan, 0xcffff1e9, 1.35f)

        line(c, joinX + 2f, joinY, tx, ty, clavicularInk, 7f)
        line(c, joinX + 2f, joinY, tx, ty, 0xfff3ddbb, 4.5f)
        disc(c, tx, ty, 2.3f, cream, clavicularInk)
    }

    private fun drawSweep(c: Canvas, angle: Float, returning: Boolean) {
        trace.rewind()
        trace.addArc(trackBounds, Motion.START_ANGLE, Motion.SWEEP_ANGLE)
        stroke(c, trace, 0xff9aafb1, 1.45f)
        val start = if (returning) angle else Motion.START_ANGLE
        val length = if (returning) Motion.START_ANGLE + Motion.SWEEP_ANGLE - angle else angle - Motion.START_ANGLE
        trace.rewind()
        trace.addArc(trackBounds, start, length)
        stroke(c, trace, teal, 2.75f)
        val a = radians(angle)
        val tail = radians(angle + if (returning) 4f else -4f)
        arrow(c, jointX + traceRadius * cos(tail), jointY + traceRadius * sin(tail),
            jointX + traceRadius * cos(a), jointY + traceRadius * sin(a), teal)
    }

    private fun leader(c: Canvas, x: Float, y: Float, elbow: Float, tx: Float, ty: Float, color: Long) {
        line(c, x, y, elbow, y, color, 1.15f)
        line(c, elbow, y, tx, ty, color, 1.15f)
    }

    private fun radians(degrees: Float) = degrees * (Math.PI.toFloat() / 180f)
}
