package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Path
import com.galaxyssi.chat.HealthAtlasLatissimusActionAssignment as Chapter
import com.galaxyssi.chat.HealthAtlasLatissimusActionMotion as Motion
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.sin

internal class HealthAtlasLatissimusActionStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val jointX = 220f
    private val jointY = 121f
    private val guideRadius = 140f
    private val outline = 0xff637f82
    private val muscleInk = 0xff95574e
    private val fasciaInk = 0xff557e80
    private val muscle = shade(133f, 273f, 0xffc78079, 0xffe9b097)
    private val body = shade(64f, 296f, 0xffd5e5e2, 0xffeaf0e4)
    private val fascia = shade(151f, 269f, 0xffd1e3dd, 0xffa3c4bf)
    private val scratch = Path()
    private val direction = FloatArray(2)
    private val hidden = DashPathEffect(floatArrayOf(3f, 2.5f), 0f)
    private val torso = Path().apply {
        moveTo(69f, 276f)
        cubicTo(60f, 254f, 74f, 222f, 66f, 188f)
        cubicTo(58f, 163f, 50f, 143f, 51f, 123f)
        cubicTo(54f, 101f, 75f, 96f, 96f, 89f)
        quadTo(115f, 82f, 118f, 63f)
        quadTo(138f, 60f, 154f, 67f)
        cubicTo(157f, 84f, 170f, 89f, 196f, 94f)
        cubicTo(220f, 97f, 237f, 117f, 227f, 137f)
        cubicTo(219f, 156f, 201f, 163f, 189f, 183f)
        cubicTo(179f, 209f, 182f, 243f, 192f, 264f)
        cubicTo(174f, 289f, 91f, 296f, 69f, 276f)
        close()
    }
    private val scapula = Path().apply {
        moveTo(139f, 107f)
        cubicTo(161f, 108f, 185f, 95f, 211f, 107f)
        quadTo(222f, 114f, 217f, 124f)
        quadTo(212f, 128f, 205f, 124f)
        cubicTo(195f, 137f, 179f, 163f, 163f, 178f)
        cubicTo(148f, 169f, 138f, 139f, 139f, 107f)
        close()
    }
    private val fasciaField = Path().apply {
        moveTo(115f, 144f)
        cubicTo(115f, 168f, 123f, 196f, 142f, 227f)
        quadTo(155f, 249f, 170f, 267f)
        cubicTo(142f, 286f, 101f, 282f, 80f, 264f)
        cubicTo(97f, 251f, 113f, 222f, 115f, 144f)
        close()
    }
    private val farSheet = Path().apply {
        moveTo(114f, 150f)
        cubicTo(91f, 149f, 72f, 138f, 62f, 130f)
        cubicTo(66f, 171f, 78f, 185f, 80f, 217f)
        quadTo(81f, 238f, 78f, 259f)
        cubicTo(102f, 244f, 113f, 194f, 114f, 150f)
        close()
    }
    private val arm = Path().apply {
        moveTo(-12f, -12f)
        cubicTo(14f, -21f, 48f, -16f, 83f, -12f)
        cubicTo(102f, -15f, 115f, -12f, 128f, -8f)
        quadTo(136f, -1f, 129f, 6f)
        cubicTo(119f, 10f, 102f, 15f, 82f, 13f)
        cubicTo(54f, 16f, 25f, 18f, -9f, 14f)
        quadTo(-22f, 4f, -12f, -12f)
        close()
    }
    private val armBone = Path().apply {
        moveTo(-10f, -9f)
        cubicTo(4f, -18f, 14f, -9f, 24f, -7f)
        cubicTo(43f, -3f, 65f, -6f, 80f, -7f)
        quadTo(93f, -6f, 91f, 3f)
        quadTo(87f, 12f, 77f, 8f)
        cubicTo(58f, 4f, 36f, 6f, 19f, 9f)
        cubicTo(11f, 15f, -8f, 15f, -12f, 8f)
        quadTo(-16f, 1f, -10f, -9f)
        close()
    }
    private val extensionTrace = guide(0f, 1f)
    private val adductionTrace = guide(1f, 2f)

    init { tag = "atlas-function-latissimus-extension-adduction-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val pose = Motion.pose(step, t)
        Motion.project(pose, direction)
        val dx = direction[0]
        val dy = direction[1]
        val scale = hypot(dx, dy)
        val attachX = jointX + dx * 25f + dy / scale * 7f
        val attachY = jointY + dy * 25f - dx / scale * 7f
        drawBack(c)
        if (step >= Chapter.EXTEND) drawTrails(c, step)
        c.save()
        c.translate(jointX, jointY)
        c.rotate(atan2(dy, dx) * (180f / Math.PI.toFloat()))
        c.scale(scale, 1f)
        ink(0xffcadbd7)
        c.drawPath(arm, paint)
        stroke(c, arm, outline, 1.4f)
        ink(0xfff3e8d4)
        c.drawPath(armBone, paint)
        stroke(c, armBone, 0xff9e8b73, 1.2f)
        line(c, 94f, 0f, 124f, -2f, 0xffac9e84, 3.5f)
        line(c, 24f, -6f, 40f, -5f, 0xffb59a7b, 1.5f)
        c.restore()
        drawSheet(c, attachX, attachY, step, t)
        disc(c, jointX, jointY, 3.4f, cream, outline)
        label(c, R.string.health_atlas_latissimus_action_oblique, 180f, 37f, 250f)

        if (step >= Chapter.EXTEND) {
            drawDirection(c, step, pose)
        } else if (step == Chapter.INSERTION) {
            ink(muscleInk, 1.5f)
            c.drawCircle(attachX, attachY, 6f + 5f * sin(t * Math.PI.toFloat()), paint)
            line(c, 272f, 69f, 254f, 69f, muscleInk, 1.15f)
            line(c, 254f, 69f, attachX, attachY, muscleInk, 1.15f)
            label(c, R.string.health_atlas_latissimus_action_tendon, 272f, 61f, 152f)
        } else {
            line(c, 99f, 300f, 118f, 300f, fasciaInk, 1.15f)
            line(c, 118f, 300f, 118f, 257f, fasciaInk, 1.15f)
            label(c, R.string.health_atlas_latissimus_action_fascia, 99f, 318f, 178f)
        }
    }

    private fun drawBack(c: Canvas) {
        ink(cream)
        paint.shader = body
        c.drawPath(torso, paint)
        paint.shader = null
        stroke(c, torso, outline, 1.5f)
        ink(0xffeee9d9)
        c.drawPath(scapula, paint)
        stroke(c, scapula, 0xffa09b87, 1.4f)
        scratch.rewind()
        scratch.moveTo(143f, 123f)
        scratch.quadTo(174f, 123f, 205f, 109f)
        stroke(c, scratch, 0xffaaa18c, 2.1f)
        ink(0xffcb9b91)
        c.drawPath(farSheet, paint)
        stroke(c, farSheet, 0xffac817b, 1.2f)
        ink(cream)
        paint.shader = fascia
        c.drawPath(fasciaField, paint)
        paint.shader = null
        stroke(c, fasciaField, fasciaInk, 1.3f)
        scratch.rewind()
        scratch.moveTo(119f, 84f)
        scratch.cubicTo(110f, 137f, 124f, 211f, 118f, 277f)
        stroke(c, scratch, 0xff879d98, 1.5f)
        for (i in 0..7) {
            val y = 102f + i * 22f
            line(c, 113f, y, 121f, y + 2f, 0xff91a39a, 1.1f)
        }
        scratch.rewind()
        scratch.moveTo(81f, 264f)
        scratch.quadTo(120f, 284f, 168f, 264f)
        stroke(c, scratch, 0xffeee5cf, 5f)
        stroke(c, scratch, 0xff9f9884, 1.3f)
    }

    private fun drawSheet(c: Canvas, tx: Float, ty: Float, step: Int, t: Float) {
        val wrapX = 205f + .27f * (tx - jointX)
        val wrapY = 151f + .37f * (ty - jointY)
        scratch.rewind()
        scratch.moveTo(118f, 154f)
        scratch.cubicTo(150f, 154f, 181f, 168f, wrapX - 4f, wrapY - 6f)
        scratch.quadTo(wrapX + 2f, wrapY - 2f, wrapX - 1f, wrapY + 6f)
        scratch.cubicTo(178f, 198f, 184f, 234f, 170f, 263f)
        scratch.quadTo(146f, 276f, 123f, 272f)
        scratch.cubicTo(142f, 238f, 126f, 207f, 118f, 154f)
        scratch.close()
        ink(cream)
        paint.shader = muscle
        c.drawPath(scratch, paint)
        paint.shader = null
        stroke(c, scratch, muscleInk, 1.55f)
        for (i in 0..6) {
            val f = i / 6f
            scratch.rewind()
            scratch.moveTo(123f + 19f * f * f, 159f + 107f * f)
            scratch.cubicTo(149f + 20f * f, 163f + 93f * f, wrapX - 18f,
                wrapY + 17f + 33f * f, wrapX - 4f, wrapY - 4f + 8f * f)
            val focus = if (step == Chapter.ORIGINS) sin(t * Math.PI.toFloat()) else 0f
            stroke(c, scratch, if (i % 2 == 0) 0xbaffebe0 else muscleInk, 1.05f + .45f * focus)
        }
        // The dashed continuation reaches the anterior groove, hidden in a posterior view.
        val rimX = (wrapX + tx) / 2f + 3f
        val rimY = (wrapY + ty) / 2f + 2f
        scratch.rewind()
        scratch.moveTo(wrapX - 5f, wrapY)
        scratch.quadTo(wrapX + 3f, wrapY + 3f, rimX, rimY)
        stroke(c, scratch, muscleInk, 7f)
        stroke(c, scratch, 0xfff1dfbe, 4.5f)
        scratch.rewind()
        scratch.moveTo(rimX, rimY)
        scratch.quadTo(tx + 3f, rimY - 3f, tx, ty)
        ink(muscleInk, 2.2f)
        paint.pathEffect = hidden
        c.drawPath(scratch, paint)
        paint.pathEffect = null
        disc(c, tx, ty, 2.4f, cream, muscleInk)
    }

    private fun drawTrails(c: Canvas, step: Int) {
        stroke(c, extensionTrace, if (step == Chapter.ADDUCT) 0xff94aaaa else blue, 1.7f)
        stroke(c, adductionTrace, if (step == Chapter.EXTEND) 0xff94aaaa else teal, 1.7f)
        Motion.project(0f, direction)
        disc(c, jointX + direction[0] * guideRadius, jointY + direction[1] * guideRadius, 2.8f, cream, blue)
        label(c, R.string.health_atlas_latissimus_action_forward_pose, 298f, 108f, 111f)
        Motion.project(2f, direction)
        disc(c, jointX + direction[0] * guideRadius, jointY + direction[1] * guideRadius, 2.8f, cream, teal)
        label(c, R.string.health_atlas_latissimus_action_side_pose, 251f, 275f, 118f)
    }

    private fun drawDirection(c: Canvas, step: Int, pose: Float) {
        val returning = step == Chapter.RETURN
        val extension = step == Chapter.EXTEND || (returning && pose < 1f)
        val start = if (extension) 0f else 1f
        val end = start + 1f
        val before = (pose - .04f).coerceAtLeast(start)
        val after = (pose + .04f).coerceAtMost(end)
        Motion.project(before, direction)
        val startX = direction[0]
        val startY = direction[1]
        Motion.project(after, direction)
        val sign = if (returning) -1f else 1f
        val dx = direction[0] - startX
        val dy = direction[1] - startY
        val scale = sign * 8f / hypot(dx, dy).coerceAtLeast(.001f)
        Motion.project(pose, direction)
        val x = jointX + guideRadius * direction[0]
        val y = jointY + guideRadius * direction[1]
        arrow(c, x - dx * scale, y - dy * scale, x, y, if (extension) blue else teal)
    }

    private fun guide(from: Float, to: Float) = Path().apply {
        for (i in 0..20) {
            Motion.project(from + (to - from) * i / 20f, direction)
            val x = jointX + direction[0] * guideRadius
            val y = jointY + direction[1] * guideRadius
            if (i == 0) moveTo(x, y) else lineTo(x, y)
        }
    }
}
