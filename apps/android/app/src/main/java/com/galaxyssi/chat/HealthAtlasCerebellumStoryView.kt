package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Path
import android.graphics.Shader
import androidx.annotation.StringRes
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.sin
import kotlin.math.sqrt

internal object HealthAtlasCerebellumMotion {
    const val START_X = 212f
    const val START_Y = 187f
    const val TARGET_X = 318f
    const val TARGET_Y = 162f

    fun reachProgress(chapter: Int, phase: Float): Float {
        val t = HealthAtlasFunctionStory.safePhase(phase)
        return when (chapter) {
            0 -> 0f
            1 -> .36f * smooth(t)
            2 -> .36f + .18f * smooth(t)
            3 -> .54f + .46f * smooth(t)
            else -> when {
                t < .18f -> 1f - smooth(t / .18f)
                t < .48f -> smooth((t - .18f) / .30f)
                t < .66f -> 1f - smooth((t - .48f) / .18f)
                else -> smooth((t - .66f) / .34f)
            }
        }
    }

    fun laterDeviation(t: Float) = when {
        t < .18f -> 1f
        t < .66f -> .67f
        else -> .32f
    }

    fun x(progress: Float) = START_X + (TARGET_X - START_X) * progress

    fun y(progress: Float, deviation: Float): Float {
        val arc = sin(PI * progress).toFloat()
        return START_Y + (TARGET_Y - START_Y) * progress - 24f * arc + 22f * deviation * arc * arc
    }

    private fun smooth(t: Float) = t * t * (3f - 2f * t)
}

internal class HealthAtlasCerebellumStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.CEREBELLAR_COORDINATION) {
    private val guide = 0xff657984
    private val prediction = 0xff4b7095
    private val earlier = 0xff8b657e
    private val folia = 0xffa76b83
    private val brainFill = shade(112f, 195f, 0xfffce7d9, 0xffe6b5b9)
    private val cerebellumFill = shade(169f, 223f, 0xffefd0dc, 0xffce92ab)
    private val stemFill = shade(171f, 238f, 0xffe5e1c8, 0xffc7aa93)
    private val armFill = shade(-15f, 18f, 0xffffe1c6, 0xffe4ac98)
    private val sleeveFill = shade(-22f, 28f, 0xffc8e4db, 0xff85b3ab)
    private val dash = DashPathEffect(floatArrayOf(5f, 4f), 0f)
    private val trail = Path()

    // Medial cutaway, with the back of the head to the right.
    private val cerebrum = Path().apply {
        moveTo(27f, 166f)
        cubicTo(23f, 152f, 31f, 129f, 45f, 120f)
        cubicTo(62f, 105f, 84f, 108f, 97f, 119f)
        cubicTo(109f, 127f, 117f, 141f, 114f, 156f)
        cubicTo(114f, 167f, 105f, 175f, 95f, 177f)
        cubicTo(84f, 182f, 77f, 168f, 68f, 175f)
        cubicTo(59f, 181f, 48f, 190f, 38f, 181f)
        quadTo(26f, 179f, 27f, 166f)
        close()
    }
    private val gyri = Path().apply {
        moveTo(36f, 159f); quadTo(37f, 145f, 49f, 139f)
        moveTo(45f, 172f); cubicTo(56f, 168f, 50f, 154f, 61f, 155f)
        moveTo(53f, 129f); cubicTo(67f, 123f, 75f, 121f, 84f, 129f)
        moveTo(76f, 136f); cubicTo(83f, 147f, 97f, 139f, 103f, 152f)
        moveTo(82f, 160f); quadTo(95f, 158f, 102f, 166f)
        moveTo(56f, 147f); cubicTo(64f, 137f, 77f, 144f, 77f, 153f)
    }
    private val brainstem = Path().apply {
        moveTo(62f, 171f)
        quadTo(71f, 167f, 79f, 176f)
        cubicTo(82f, 184f, 77f, 191f, 74f, 198f)
        cubicTo(69f, 210f, 66f, 225f, 69f, 237f)
        lineTo(57f, 239f)
        quadTo(53f, 226f, 57f, 209f)
        cubicTo(59f, 199f, 49f, 197f, 54f, 187f)
        quadTo(58f, 182f, 62f, 171f)
        close()
    }
    private val cerebellum = Path().apply {
        moveTo(75f, 184f)
        cubicTo(81f, 173f, 98f, 169f, 108f, 179f)
        cubicTo(118f, 185f, 119f, 197f, 112f, 204f)
        cubicTo(112f, 211f, 100f, 220f, 92f, 218f)
        cubicTo(83f, 222f, 72f, 214f, 73f, 207f)
        cubicTo(68f, 201f, 70f, 189f, 75f, 184f)
        close()
    }
    private val whiteMatter = Path().apply {
        moveTo(75f, 200f); quadTo(87f, 195f, 99f, 193f)
        moveTo(86f, 197f); quadTo(88f, 190f, 95f, 185f)
        moveTo(88f, 197f); quadTo(91f, 201f, 101f, 202f)
        moveTo(83f, 198f); quadTo(89f, 203f, 90f, 210f)
    }

    private val sleeve = Path().apply {
        moveTo(-10f, -17f)
        cubicTo(1f, -23f, 18f, -18f, 28f, -13f)
        quadTo(34f, 0f, 27f, 15f)
        cubicTo(14f, 18f, 3f, 23f, -9f, 19f)
        quadTo(-20f, 5f, -10f, -17f)
        close()
    }
    private val forearm = Path().apply {
        moveTo(-98f, -10f)
        cubicTo(-81f, -14f, -53f, -10f, -29f, -6f)
        quadTo(-22f, -10f, -14f, -7f)
        lineTo(-2f, -4f); quadTo(3f, -3f, 0f, 1f)
        lineTo(-15f, 1f); quadTo(-16f, 3f, -13f, 5f)
        quadTo(-9f, 9f, -14f, 11f)
        quadTo(-19f, 10f, -25f, 9f)
        cubicTo(-48f, 11f, -83f, 15f, -98f, 10f)
        quadTo(-110f, 2f, -98f, -10f)
        close()
    }

    init { tag = "atlas-function-cerebellar-coordination-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        anatomy(c)
        reach(c, step, t)
    }

    private fun anatomy(c: Canvas) {
        rounded(c, 10f, 22f, 124f, 338f, 7f, 0xfff7eeeb)
        line(c, 131f, 23f, 131f, 337f, 0xffcddcd8, 1f)
        area(c, brainstem, stemFill, 0xff947760)
        area(c, cerebrum, brainFill, coral)
        stroke(c, gyri, 0xffbc818b, 1.2f)
        area(c, cerebellum, cerebellumFill, earlier)
        c.save()
        c.clipPath(cerebellum)
        for (i in 0..5) {
            val y = 179f + 7f * i
            trail.rewind()
            trail.moveTo(73f, y + 6f)
            trail.cubicTo(85f, y - 3f, 105f, y - 5f, 117f, y + 1f)
            stroke(c, trail, folia, 1.15f)
        }
        stroke(c, whiteMatter, 0xfffae6d8, 2.6f)
        c.restore()

        line(c, 66f, 83f, 66f, 112f, guide, 1f)
        disc(c, 66f, 112f, 1.7f, guide)
        label(c, R.string.health_atlas_cerebellum_story_cerebrum, 66f, 76f, 102f)
        line(c, 100f, 215f, 100f, 246f, earlier, 1f)
        line(c, 100f, 246f, 68f, 246f, earlier, 1f)
        disc(c, 100f, 215f, 1.8f, earlier)
        label(c, R.string.health_atlas_cerebellum_story_cerebellum, 67f, 264f, 102f)
        line(c, 59f, 221f, 37f, 246f, guide, 1f)
        line(c, 37f, 246f, 37f, 288f, guide, 1f)
        disc(c, 59f, 221f, 1.7f, guide)
        label(c, R.string.health_atlas_cerebellum_story_brainstem, 66f, 306f, 102f)
    }

    private fun reach(c: Canvas, step: Int, t: Float) {
        val progress = HealthAtlasCerebellumMotion.reachProgress(step, t)
        val deviation = if (step == 4) HealthAtlasCerebellumMotion.laterDeviation(t) else 1f
        val fingerX = HealthAtlasCerebellumMotion.x(progress)
        val fingerY = HealthAtlasCerebellumMotion.y(progress, deviation)

        line(c, 144f, 78f, 345f, 78f, 0xffcddcd8, 1f)
        when (step) {
            0 -> key(c, R.string.health_atlas_cerebellum_story_predicted, 246f, prediction, dashed = true)
            4 -> {
                key(c, R.string.health_atlas_cerebellum_story_earlier, 191f, earlier, dashed = true)
                key(c, R.string.health_atlas_cerebellum_story_later, 296f, teal)
            }
            else -> {
                key(c, R.string.health_atlas_cerebellum_story_predicted, 191f, prediction, dashed = true)
                key(c, R.string.health_atlas_cerebellum_story_actual, 296f, teal)
            }
        }

        val tx = HealthAtlasCerebellumMotion.TARGET_X
        val ty = HealthAtlasCerebellumMotion.TARGET_Y
        line(c, tx, 118f, tx, 140f, guide, 1f)
        label(c, R.string.health_atlas_cerebellum_story_target, tx, 111f, 64f)
        disc(c, tx, ty, 18f, 0xfff8eac7, 0xffc3a477)
        disc(c, tx, ty, 11f, 0xfff2d392, sienna)
        disc(c, tx, ty, 4f, cream, sienna)

        oval(c, 145f, 263f, 308f, 284f, 0xffe2eae1, 0xffdbe5dc)
        arm(c, fingerX, fingerY)
        line(c, 164f, 249f, 182f, 284f, guide, 1f)
        disc(c, 164f, 249f, 1.7f, guide)
        label(c, R.string.health_atlas_cerebellum_story_arm, 198f, 300f, 111f)

        drawTrace(c, 1f, if (step == 4) 1f else 0f, if (step == 4) earlier else prediction, dashed = true)
        val laterReach = step == 4 && ((t >= .18f && t < .48f) || t >= .66f)
        if (step in 1..3 || laterReach) {
            drawTrace(c, progress, deviation, teal)
        }
        val predictedX = if (step == 0) HealthAtlasCerebellumMotion.x(t) else fingerX
        val predictedY = HealthAtlasCerebellumMotion.y(if (step == 0) t else progress, 0f)
        if (step == 2 || (step == 3 && progress < .85f)) {
            line(c, predictedX, predictedY, fingerX, fingerY, earlier, 1.25f)
        }
        if (step == 0 || step == 2 || (step == 3 && progress < .85f)) {
            disc(c, predictedX, predictedY, 3.8f, cream, prediction)
        }
        if (step != 0) disc(c, fingerX, fingerY, 3.3f, teal, cream)
        if (step == 1) feedback(c, t)
        if (step == 2) {
            label(c, R.string.health_atlas_cerebellum_story_mismatch, 247f, 338f, 194f)
        }
    }

    private fun arm(c: Canvas, fingerX: Float, fingerY: Float) {
        val shoulderX = 164f
        val shoulderY = 243f
        val upper = 81f
        val lower = 98f
        val dx = fingerX - shoulderX
        val dy = fingerY - shoulderY
        val distance = hypot(dx, dy)
        // A two-link arm keeps the shoulder fixed and both segment lengths stable.
        val along = (distance * distance + upper * upper - lower * lower) / (2f * distance)
        val bend = sqrt((upper * upper - along * along).coerceAtLeast(0f))
        val ex = shoulderX + (along * dx - bend * dy) / distance
        val ey = shoulderY + (along * dy + bend * dx) / distance
        c.save()
        c.translate(shoulderX, shoulderY)
        c.rotate(degrees(ey - shoulderY, ex - shoulderX))
        oval(c, 1f, -13f, upper + 10f, 13f, armFill, coral)
        area(c, sleeve, sleeveFill, teal)
        c.restore()
        c.save()
        c.translate(fingerX, fingerY)
        c.rotate(degrees(fingerY - ey, fingerX - ex))
        area(c, forearm, armFill, coral)
        line(c, -19f, -2f, -10f, -2f, 0xffc4847e, 1f)
        c.restore()
    }

    private fun degrees(y: Float, x: Float) = atan2(y, x) * (180f / PI.toFloat())

    private fun drawTrace(c: Canvas, progress: Float, deviation: Float, color: Long, dashed: Boolean = false) {
        if (progress <= 0f) return
        trail.rewind()
        trail.moveTo(HealthAtlasCerebellumMotion.START_X, HealthAtlasCerebellumMotion.START_Y)
        for (i in 1..32) {
            val p = progress * i / 32f
            trail.lineTo(HealthAtlasCerebellumMotion.x(p), HealthAtlasCerebellumMotion.y(p, deviation))
        }
        drawLinework(c, trail, color, dashed)
    }

    private fun key(c: Canvas, @StringRes id: Int, x: Float, color: Long, dashed: Boolean = false) {
        trail.rewind(); trail.moveTo(x - 13f, 35f); trail.lineTo(x + 13f, 35f)
        drawLinework(c, trail, color, dashed)
        label(c, id, x, 59f, 102f)
    }

    private fun drawLinework(c: Canvas, path: Path, color: Long, dashed: Boolean) {
        paint.pathEffect = if (dashed) dash else null
        stroke(c, path, color, if (dashed) 1.7f else 2.4f)
        paint.pathEffect = null
    }

    private fun feedback(c: Canvas, t: Float) {
        // The two tracks indicate information arriving, not anatomical pathways.
        line(c, 145f, 311f, 344f, 311f, 0xffcddcd8, 1f)
        cue(c, R.string.health_atlas_cerebellum_story_vision, 188f, t, .18f, prediction)
        cue(c, R.string.health_atlas_cerebellum_story_position, 295f, t, .29f, teal)
    }

    private fun cue(c: Canvas, @StringRes id: Int, x: Float, time: Float, delay: Float, color: Long) {
        label(c, id, x, 332f, 96f)
        line(c, x - 24f, 343f, x + 24f, 343f, 0xffb5ccc4, 1.35f)
        if (time >= delay) {
            val travel = ((time - delay) / (1f - delay)).coerceIn(0f, 1f)
            disc(c, x - 24f + 48f * travel, 343f, 3.5f, color, cream)
        }
    }

    private fun area(c: Canvas, path: Path, fill: Shader, border: Long) {
        ink(cream); paint.shader = fill; c.drawPath(path, paint); paint.shader = null
        stroke(c, path, border, 1.25f)
    }
}
