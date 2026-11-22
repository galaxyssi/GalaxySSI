package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.PointF
import android.graphics.Shader
import kotlin.math.cos
import kotlin.math.sin

internal object HealthAtlasKneeMotion {
    data class Pose(val bend: Float, val extensor: Float, val flexor: Float)

    private val poses = listOf(
        Pose(.12f, .14f, .14f), Pose(.17f, .16f, .27f),
        Pose(.84f, .18f, .85f), Pose(.92f, .36f, .43f),
        Pose(.18f, .74f, .17f), Pose(.12f, .14f, .14f),
    )

    fun at(step: Int, t: Float): Pose {
        val index = step.coerceIn(0, poses.lastIndex - 1)
        val from = poses[index]
        val to = poses[index + 1]
        val f = HealthAtlasFunctionStory.safePhase(t)
        val ease = f * f * (3f - 2f * f)
        fun between(a: Float, b: Float) = a + (b - a) * ease
        return Pose(between(from.bend, to.bend), between(from.extensor, to.extensor), between(from.flexor, to.flexor))
    }
}

internal class HealthAtlasKneeStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.KNEE_ARTICULATION) {
    private val kneeX = 178f
    private val kneeY = 192f
    private val shape = Path()
    private val linePath = PathMeasure()
    private val mark = FloatArray(2)
    private val boneLip = 0xffa9815e
    private val boneShade = shade(27f, 200f, 0xfffff0d6, 0xffd7b28b)
    private val shinShade = shade(0f, 124f, 0xffffecd0, 0xffddbc96)
    private val quadShade = shade(38f, 165f, 0xfff4c0a9, 0xffcc765f)
    private val flexorShade = shade(40f, 170f, 0xffe4bac7, 0xffab627e)
    private val femur = Path().apply {
        moveTo(160f, 28f)
        cubicTo(154f, 64f, 162f, 126f, 157f, 151f)
        cubicTo(152f, 171f, 145f, 178f, 150f, 187f)
        cubicTo(157f, 200f, 179f, 200f, 193f, 193f)
        cubicTo(213f, 182f, 204f, 167f, 196f, 145f)
        cubicTo(192f, 122f, 198f, 60f, 192f, 28f)
        quadTo(176f, 22f, 160f, 28f)
        close()
    }
    private val tibia = Path().apply {
        moveTo(-23f, 12f)
        cubicTo(-16f, 5f, 9f, 4f, 22f, 9f)
        cubicTo(27f, 16f, 18f, 26f, 12f, 37f)
        cubicTo(5f, 58f, 12f, 88f, 11f, 121f)
        quadTo(-1f, 131f, -13f, 121f)
        cubicTo(-13f, 99f, -10f, 62f, -19f, 39f)
        cubicTo(-28f, 35f, -26f, 20f, -23f, 12f)
        close()
    }
    private val fibula = Path().apply {
        moveTo(24f, 27f)
        cubicTo(39f, 21f, 38f, 37f, 29f, 47f)
        cubicTo(26f, 66f, 26f, 98f, 24f, 118f)
        quadTo(18f, 123f, 16f, 117f)
        cubicTo(13f, 95f, 19f, 62f, 18f, 43f)
        quadTo(17f, 30f, 24f, 27f)
        close()
    }

    init { tag = "atlas-function-knee-articulation-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val pose = HealthAtlasKneeMotion.at(step, t)
        val angle = -58f * pose.bend
        val shinAnchor = local(-23f, 32f, angle)
        val flexorAnchor = local(24f, 24f, angle)
        val patellaX = 143f + pose.bend * 6f
        val patellaY = 175f + pose.bend * 21f
        val quad = muscle(c, false, pose.extensor)
        val ham = muscle(c, true, pose.flexor)

        bone(c, femur, boneShade)
        line(c, 176f, 42f, 175f, 141f, 0xffb68f6c, 1.3f)
        curve(c, 150f, 185f, 160f, 204f, 199f, 192f, 205f, 178f, teal, 3.3f)
        c.save()
        c.translate(kneeX, kneeY)
        c.rotate(angle)
        bone(c, fibula, shinShade)
        bone(c, tibia, shinShade)
        curve(c, -22f, 11f, -16f, 4f, 11f, 3f, 21f, 9f, teal, 3f)
        line(c, -4f, 47f, -1f, 114f, 0xffb68f6c, 1.3f)
        c.restore()

        val quadPath = 0xffb66a45
        val hamPath = 0xff955572
        curve(c, quad.x, quad.y, quad.x - 2f, quad.y + 12f,
            patellaX - 8f, patellaY - 8f, patellaX, patellaY, quadPath, 7f)
        curve(c, patellaX, patellaY + 4f, patellaX - 2f, patellaY + 19f,
            shinAnchor.x - 6f, shinAnchor.y - 5f, shinAnchor.x, shinAnchor.y, quadPath, 6f)
        if (step == 0 || step >= 2) pulse(c, (1f - t) * .82f + .08f, if (step == 3) quadPath else 0xffefa366)
        curve(c, ham.x, ham.y, ham.x + 1f, ham.y + 22f,
            flexorAnchor.x + 10f, flexorAnchor.y - 16f, flexorAnchor.x, flexorAnchor.y, hamPath, 5f)
        if (step == 1) pulse(c, 1f - t, 0xffd39cae)
        oval(c, patellaX - 9f, patellaY - 13f, patellaX + 9f, patellaY + 12f, 0xfffae0bb, boneLip)

        label(c, R.string.health_atlas_knee_quadriceps, 60f, 58f, 102f)
        line(c, 58f, 64f, 116f, 91f, quadPath, 1.15f)
        label(c, R.string.health_atlas_knee_hamstrings, 292f, 58f, 104f)
        line(c, 281f, 64f, 227f, 90f, hamPath, 1.15f)
        label(c, R.string.health_atlas_knee_patella, 58f, 189f, 101f)
        line(c, 61f, 195f, patellaX - 12f, patellaY, boneLip, 1.15f)
        val shin = local(0f, 100f, angle)
        line(c, 311f, 312f, shin.x + 9f, shin.y, boneLip, 1.15f)
        label(c, R.string.health_atlas_knee_tibia, 309f, 331f, 92f)

        if (step == 1 || step == 3) {
            val before = local(-18f, 99f, angle + if (step == 1) 10f else -10f)
            val after = local(-18f, 99f, angle + if (step == 1) -5f else 5f)
            arrow(c, before.x, before.y, after.x, after.y, if (step == 1) hamPath else quadPath)
        }
    }

    private fun muscle(c: Canvas, behind: Boolean, activation: Float): PointF {
        val x = if (behind) 216f else 133f
        val width = 12f + activation * 8f
        val tip = if (behind) 167f - activation * 9f else 159f - activation * 9f
        shape.rewind()
        shape.moveTo(x + if (behind) 2f else -4f, 35f)
        shape.cubicTo(x + width * 1.4f, 59f, x + width, 120f, x, tip)
        shape.cubicTo(x - width, 128f, x - width * 1.4f, 67f, x + if (behind) 2f else -4f, 35f)
        shape.close()
        bone(c, shape, if (behind) flexorShade else quadShade, if (behind) 0xff99566f else 0xffbf7359)
        for (i in -1..1) {
            val shift = i * width / 2f
            curve(c, x + 1f + shift * .3f, 55f, x + shift * 1.3f, 86f,
                x + shift, tip - 27f, x + shift * .31f, tip - 11f, 0xffffdacb, 1.15f)
        }
        return PointF(x, tip)
    }

    private fun bone(c: Canvas, path: Path, fill: Shader, border: Long = boneLip) {
        ink(cream)
        paint.shader = fill
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, border, 1.35f)
    }

    private fun pulse(c: Canvas, t: Float, color: Long) {
        linePath.setPath(shape, false)
        if (linePath.getPosTan(linePath.length * t, mark, null)) disc(c, mark[0], mark[1], 3.6f, color, cream)
    }

    private fun curve(c: Canvas, x: Float, y: Float, a: Float, b: Float, d: Float, e: Float, f: Float, g: Float, color: Long, width: Float) {
        shape.rewind()
        shape.moveTo(x, y)
        shape.cubicTo(a, b, d, e, f, g)
        stroke(c, shape, color, width)
    }

    private fun local(x: Float, y: Float, angle: Float): PointF {
        val radians = angle * .017453293f
        return PointF(kneeX + x * cos(radians) - y * sin(radians), kneeY + x * sin(radians) + y * cos(radians))
    }
}
