package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader
import androidx.annotation.StringRes
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.sin
import kotlin.math.sqrt

internal object HealthAtlasCerebralSensorimotorMotion {
    private const val MID_REACH = .52f

    fun tissueTrace(t: Float) = window(t, .06f, .86f)
    fun touch(t: Float) = window(t, .08f, .59f)
    fun position(t: Float) = window(t, .22f, .92f)
    fun planning(t: Float) = window(t, .04f, .76f)
    fun reply(t: Float) = window(t, .28f, .95f)
    fun preview(t: Float) = ease(window(t, .18f, .93f))
    fun command(t: Float) = window(t, .03f, .72f)
    fun ongoingInput(t: Float) = cycle(t, 0f, .46f)
    fun ongoingOutput(t: Float) = cycle(t, .15f, .34f)

    fun reach(chapter: Int, t: Float): Float = when (chapter) {
        3 -> MID_REACH * ease(window(t, .19f, 1f))
        4 -> MID_REACH + (1f - MID_REACH) * ease(window(t, 0f, .94f))
        else -> 0f
    }

    fun fingerX(reach: Float) = 218f + 56f * reach
    fun fingerY(reach: Float) = 277f - 2f * reach - 22f * sin(PI * reach).toFloat()

    private fun window(t: Float, from: Float, to: Float) =
        ((HealthAtlasFunctionStory.safePhase(t) - from) / (to - from)).coerceIn(0f, 1f)

    private fun cycle(t: Float, delay: Float, period: Float) =
        ((HealthAtlasFunctionStory.safePhase(t) - delay).coerceAtLeast(0f) % period) / period

    private fun ease(t: Float) = t * t * (3f - 2f * t)
}

internal class HealthAtlasCerebralSensorimotorStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.CEREBRAL_SENSORIMOTOR) {
    private val guide = 0xff65747b
    private val sulcusInk = 0xff8a5968
    private val motorInk = 0xff9b4945
    private val sensoryInk = 0xff386c8b
    private val premotorInk = 0xffa3723c
    private val planningInk = 0xff4d796a
    private val positionInk = 0xff5a688e
    private val skin = shade(-13f, 15f, 0xffffdeca, 0xffe3ab94)
    private val cortex = shade(57f, 205f, 0xffffe6d9, 0xffe3adb5)
    private val cupFill = shade(262f, 312f, 0xffe6efdc, 0xffafc5a4)
    private val sleeveFill = shade(-17f, 18f, 0xffb9d6d1, 0xff80a8a2)
    private val dash = DashPathEffect(floatArrayOf(3.5f, 3.5f), 0f)
    private val trace = Path()
    private val positionPath = Path()
    private val positionTrack = PathMeasure()

    // Lateral view of the left hemisphere; frontal pole at left, occipital pole at right.
    private val hemisphere = Path().apply {
        moveTo(36f, 134f)
        cubicTo(25f, 121f, 38f, 109f, 42f, 101f)
        cubicTo(43f, 91f, 57f, 81f, 70f, 78f)
        cubicTo(78f, 67f, 94f, 64f, 105f, 65f)
        cubicTo(118f, 54f, 139f, 57f, 152f, 60f)
        cubicTo(165f, 52f, 187f, 54f, 200f, 62f)
        cubicTo(215f, 56f, 238f, 62f, 249f, 70f)
        cubicTo(272f, 69f, 291f, 80f, 299f, 94f)
        cubicTo(316f, 103f, 329f, 118f, 326f, 134f)
        cubicTo(335f, 152f, 317f, 172f, 299f, 174f)
        cubicTo(285f, 184f, 260f, 182f, 242f, 177f)
        cubicTo(223f, 177f, 213f, 189f, 191f, 195f)
        cubicTo(172f, 201f, 151f, 208f, 132f, 202f)
        cubicTo(114f, 201f, 108f, 192f, 107f, 181f)
        cubicTo(109f, 173f, 123f, 170f, 124f, 163f)
        cubicTo(108f, 163f, 96f, 171f, 78f, 165f)
        cubicTo(58f, 165f, 37f, 155f, 36f, 134f)
        close()
    }
    private val folds = Path().apply {
        moveTo(50f, 113f); cubicTo(61f, 107f, 60f, 95f, 79f, 93f)
        moveTo(40f, 133f); cubicTo(56f, 118f, 64f, 131f, 75f, 119f)
        cubicTo(83f, 108f, 96f, 114f, 101f, 105f)
        moveTo(51f, 147f); cubicTo(65f, 155f, 76f, 145f, 88f, 147f)
        cubicTo(99f, 149f, 105f, 145f, 113f, 137f)
        moveTo(84f, 81f); cubicTo(99f, 86f, 108f, 76f, 123f, 78f)
        quadTo(135f, 84f, 143f, 76f)
        moveTo(79f, 134f); cubicTo(94f, 128f, 96f, 134f, 111f, 123f)
        moveTo(117f, 96f); cubicTo(131f, 100f, 128f, 118f, 139f, 125f)
        moveTo(213f, 77f); cubicTo(221f, 89f, 239f, 84f, 253f, 91f)
        quadTo(270f, 86f, 278f, 98f)
        moveTo(197f, 107f); cubicTo(207f, 99f, 221f, 104f, 228f, 112f)
        cubicTo(239f, 122f, 259f, 108f, 277f, 122f)
        moveTo(292f, 102f); cubicTo(284f, 113f, 301f, 124f, 300f, 137f)
        quadTo(298f, 145f, 308f, 153f)
        moveTo(209f, 135f); cubicTo(227f, 133f, 228f, 151f, 246f, 147f)
        quadTo(266f, 136f, 282f, 144f)
        moveTo(239f, 162f); cubicTo(258f, 150f, 262f, 170f, 286f, 164f)
        moveTo(142f, 163f); cubicTo(154f, 174f, 179f, 158f, 187f, 160f)
        quadTo(202f, 164f, 219f, 151f)
        moveTo(117f, 182f); cubicTo(135f, 170f, 138f, 199f, 170f, 181f)
        quadTo(184f, 172f, 205f, 174f)
    }
    private val lateralSulcus = Path().apply {
        moveTo(124f, 163f)
        cubicTo(141f, 160f, 141f, 151f, 155f, 149f)
        cubicTo(178f, 144f, 191f, 145f, 213f, 128f)
    }
    private val centralSulcus = Path().apply {
        moveTo(176f, 58f)
        cubicTo(165f, 71f, 176f, 80f, 164f, 93f)
        cubicTo(152f, 104f, 158f, 116f, 152f, 125f)
        quadTo(148f, 133f, 149f, 140f)
    }
    private val motor = Path().apply {
        moveTo(160f, 62f)
        quadTo(164f, 59f, 172f, 60f)
        cubicTo(164f, 72f, 172f, 81f, 161f, 91f)
        cubicTo(150f, 102f, 154f, 116f, 148f, 124f)
        quadTo(145f, 131f, 145f, 141f)
        cubicTo(131f, 133f, 142f, 119f, 141f, 109f)
        cubicTo(138f, 95f, 148f, 85f, 151f, 80f)
        quadTo(151f, 70f, 160f, 62f)
        close()
    }
    private val sensory = Path().apply {
        moveTo(180f, 59f)
        quadTo(188f, 58f, 194f, 64f)
        cubicTo(184f, 74f, 192f, 89f, 179f, 101f)
        cubicTo(169f, 110f, 175f, 126f, 155f, 140f)
        cubicTo(152f, 130f, 162f, 120f, 160f, 111f)
        cubicTo(159f, 97f, 177f, 93f, 174f, 77f)
        quadTo(173f, 70f, 180f, 59f)
        close()
    }
    private val premotor = Path().apply {
        moveTo(101f, 94f)
        cubicTo(106f, 87f, 125f, 83f, 136f, 92f)
        cubicTo(140f, 99f, 131f, 107f, 130f, 119f)
        quadTo(119f, 122f, 114f, 112f)
        quadTo(101f, 110f, 101f, 94f)
        close()
    }
    private val parietal = Path().apply {
        moveTo(211f, 85f)
        cubicTo(224f, 91f, 230f, 88f, 246f, 97f)
        cubicTo(257f, 98f, 263f, 106f, 260f, 114f)
        cubicTo(248f, 117f, 237f, 125f, 228f, 116f)
        cubicTo(217f, 105f, 206f, 107f, 197f, 109f)
        quadTo(197f, 94f, 211f, 85f)
        close()
    }

    private val centralTrack = track(centralSulcus)
    private val plansAcross = Path().apply {
        moveTo(228f, 100f); cubicTo(207f, 62f, 146f, 61f, 117f, 98f)
    }
    private val plansBack = Path().apply {
        moveTo(117f, 107f); cubicTo(146f, 84f, 199f, 84f, 228f, 107f)
    }
    private val touchPath = Path().apply {
        moveTo(218f, 277f); cubicTo(230f, 253f, 206f, 249f, 199f, 222f)
        cubicTo(189f, 190f, 201f, 153f, 177f, 102f)
    }
    private val commandPath = Path().apply {
        moveTo(145f, 106f); cubicTo(127f, 154f, 139f, 190f, 139f, 211f)
        cubicTo(139f, 244f, 87f, 250f, 55f, 270f)
    }
    private val acrossTrack = track(plansAcross)
    private val backTrack = track(plansBack)
    private val touchTrack = track(touchPath)
    private val commandTrack = track(commandPath)

    private val upperArm = Path().apply {
        moveTo(-6f, -14f)
        cubicTo(22f, -16f, 62f, -11f, 86f, -10f)
        cubicTo(103f, -9f, 103f, 12f, 88f, 12f)
        cubicTo(58f, 13f, 20f, 17f, -6f, 15f)
        quadTo(-18f, 1f, -6f, -14f)
        close()
    }
    private val sleeve = Path().apply {
        moveTo(-12f, -17f)
        quadTo(1f, -21f, 25f, -15f)
        quadTo(32f, 1f, 26f, 15f)
        quadTo(8f, 21f, -12f, 18f)
        quadTo(-22f, 2f, -12f, -17f)
        close()
    }
    private val forearm = Path().apply {
        moveTo(-151f, -10f)
        cubicTo(-106f, -15f, -67f, -6f, -37f, -5f)
        cubicTo(-29f, -7f, -18f, -8f, -11f, -6f)
        lineTo(-3f, -5f); quadTo(1f, -4f, 0f, 0f)
        quadTo(-2f, 3f, -17f, 2f)
        quadTo(-20f, 3f, -16f, 5f)
        quadTo(-11f, 10f, -15f, 12f)
        quadTo(-18f, 13f, -30f, 10f)
        cubicTo(-61f, 9f, -111f, 12f, -151f, 11f)
        quadTo(-161f, 1f, -151f, -10f)
        close()
    }
    private val cup = Path().apply {
        moveTo(273f, 270f)
        lineTo(278f, 307f)
        cubicTo(279f, 315f, 312f, 315f, 313f, 307f)
        lineTo(318f, 270f)
        close()
    }
    private val handle = Path().apply {
        moveTo(316f, 277f); cubicTo(343f, 267f, 340f, 303f, 314f, 300f)
    }

    init { tag = "atlas-function-cerebral-sensorimotor-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val motion = HealthAtlasCerebralSensorimotorMotion
        val reach = motion.reach(step, t)
        val x = motion.fingerX(reach)
        val y = motion.fingerY(reach)
        val sx = 41f
        val sy = 266f
        val upper = 88f
        val lower = 151f
        val dx = x - sx
        val dy = y - sy
        val distance = hypot(dx, dy)
        // Fixed segment lengths keep the elbow bend grounded as the fingertip follows its arc.
        val along = (distance * distance + upper * upper - lower * lower) / (2f * distance)
        val bend = sqrt((upper * upper - along * along).coerceAtLeast(0f))
        val ex = sx + (dx * along - dy * bend) / distance
        val ey = sy + (dy * along + dx * bend) / distance
        val positionX = sx + (ex - sx) * .69f
        val positionY = sy + (ey - sy) * .69f

        anatomy(c)
        line(c, 16f, 228f, 344f, 228f, 0xffcad2c8, 1f)
        target(c)
        if (step == 2) reachTrace(c, motion.preview(t), planningInk, dashed = true)
        if (step in 3..4) reachTrace(c, reach, planningInk, dashed = false)
        arm(c, sx, sy, ex, ey, x, y)
        when (step) {
            0 -> pulse(c, centralTrack, motion.tissueTrace(t), sulcusInk)
            1 -> {
                input(c, positionX, positionY, motion.position(t))
                signal(c, touchPath, touchTrack, motion.touch(t), sensoryInk)
                cue(c, x, y, sensoryInk)
                leader(c, R.string.health_atlas_cerebral_sensorimotor_story_touch, 255f, 246f, 53f, 255f, 252f, 222f, 271f)
                leader(c, R.string.health_atlas_cerebral_sensorimotor_story_position, 63f, 246f, 94f, 97f, 249f, 116f, 258f)
            }
            2 -> {
                signal(c, plansAcross, acrossTrack, motion.planning(t), planningInk)
                signal(c, plansBack, backTrack, motion.reply(t), premotorInk)
                leader(c, R.string.health_atlas_cerebral_sensorimotor_story_reach_plan, 244f, 246f, 88f, 244f, 250f, 246f, 254f)
            }
            3 -> {
                signal(c, commandPath, commandTrack, motion.command(t), motorInk)
                leader(c, R.string.health_atlas_cerebral_sensorimotor_story_motor_output, 70f, 246f, 104f, 115f, 250f, 123f, 238f)
            }
            4 -> {
                input(c, positionX, positionY, motion.ongoingInput(t))
                signal(c, commandPath, commandTrack, motion.ongoingOutput(t), motorInk)
                if (reach > .96f) cue(c, x, y, sensoryInk)
                leader(c, R.string.health_atlas_cerebral_sensorimotor_story_sensory_feedback, 253f, 246f, 112f, 194f, 251f, 170f, 226f)
            }
        }
        anatomyLabels(c)
        leader(c, R.string.health_atlas_cerebral_sensorimotor_story_cup, 307f, 344f, 76f, 307f, 331f, 307f, 315f)
    }

    private fun anatomy(c: Canvas) {
        area(c, hemisphere, cortex, coral)
        patch(c, premotor, 0xffebc99b, premotorInk)
        patch(c, parietal, 0xffbbd6bf, planningInk)
        patch(c, motor, 0xffdb9a8e, motorInk)
        patch(c, sensory, 0xffb0cad9, sensoryInk)
        stroke(c, folds, 0xffb47f85, 1.15f)
        stroke(c, lateralSulcus, sulcusInk, 1.65f)
        stroke(c, centralSulcus, sulcusInk, 2f)
    }

    private fun anatomyLabels(c: Canvas) {
        leader(c, R.string.health_atlas_cerebral_sensorimotor_story_central_sulcus, 175f, 20f, 142f, 175f, 26f, 176f, 57f)
        leader(c, R.string.health_atlas_cerebral_sensorimotor_story_motor_cortex, 83f, 43f, 148f, 114f, 48f, 150f, 90f)
        leader(c, R.string.health_atlas_cerebral_sensorimotor_story_sensory_cortex, 274f, 43f, 152f, 220f, 48f, 183f, 92f)
        leader(c, R.string.health_atlas_cerebral_sensorimotor_story_premotor, 71f, 219f, 128f, 66f, 151f, 113f, 101f)
        leader(c, R.string.health_atlas_cerebral_sensorimotor_story_parietal, 282f, 219f, 145f, 285f, 179f, 232f, 108f)
    }

    private fun target(c: Canvas) {
        line(c, 261f, 318f, 345f, 318f, 0xffbdc8b7, 1.2f)
        rounded(c, 206f, 279f, 231f, 285f, 2f, 0xffb7c4b6)
        stroke(c, handle, planningInk, 7f)
        stroke(c, handle, 0xffcbdac0, 4.5f)
        area(c, cup, cupFill, planningInk)
        oval(c, 273f, 262f, 318f, 278f, 0xffeff2dc, planningInk)
        oval(c, 277f, 265f, 314f, 275f, 0xffc5d3b3, 0xff8ca189)
    }

    private fun arm(c: Canvas, sx: Float, sy: Float, ex: Float, ey: Float, x: Float, y: Float) {
        c.save()
        c.translate(sx, sy)
        c.rotate(degrees(ey - sy, ex - sx))
        area(c, upperArm, skin, coral)
        area(c, sleeve, sleeveFill, planningInk)
        line(c, 23f, -12f, 25f, 12f, planningInk, 1f)
        c.restore()
        c.save()
        c.translate(x, y)
        c.rotate(degrees(y - ey, x - ex))
        area(c, forearm, skin, coral)
        line(c, -29f, 1f, -22f, 2f, 0xffc18476, 1f)
        c.restore()
    }

    private fun degrees(y: Float, x: Float) = atan2(y, x) * (180f / PI.toFloat())

    private fun input(c: Canvas, x: Float, y: Float, progress: Float) {
        positionPath.rewind()
        positionPath.moveTo(x, y)
        positionPath.cubicTo(x + 14f, y - 31f, 106f, 253f, 150f, 237f)
        positionPath.cubicTo(206f, 213f, 165f, 174f, 172f, 110f)
        positionTrack.setPath(positionPath, false)
        signal(c, positionPath, positionTrack, progress, positionInk)
        cue(c, x, y, positionInk)
    }

    private fun cue(c: Canvas, x: Float, y: Float, color: Long) {
        ink(cream, 2.9f); c.drawCircle(x, y, 5f, paint)
        ink(color, 1.3f); c.drawCircle(x, y, 5f, paint)
    }

    private fun reachTrace(c: Canvas, progress: Float, color: Long, dashed: Boolean) {
        val motion = HealthAtlasCerebralSensorimotorMotion
        trace.rewind()
        trace.moveTo(motion.fingerX(0f), motion.fingerY(0f))
        for (i in 1..20) {
            val p = progress * i / 20f
            trace.lineTo(motion.fingerX(p), motion.fingerY(p))
        }
        paint.pathEffect = if (dashed) dash else null
        stroke(c, trace, color, if (dashed) 1.7f else 1.25f)
        paint.pathEffect = null
        if (dashed && progress > 0f) disc(c, motion.fingerX(progress), motion.fingerY(progress), 3.5f, color, cream)
    }

    // These dashed tracks show information direction, not the course of individual nerves.
    private fun signal(c: Canvas, path: Path, measure: PathMeasure, progress: Float, color: Long) {
        paint.pathEffect = dash
        stroke(c, path, color, 1.25f)
        paint.pathEffect = null
        at(measure, (1f - 7f / measure.length).coerceAtLeast(0f)) { x, y ->
            at(measure, 1f) { endX, endY -> arrow(c, x, y, endX, endY, color) }
        }
        pulse(c, measure, progress, color)
    }

    private fun pulse(c: Canvas, path: PathMeasure, progress: Float, color: Long) {
        if (progress <= 0f || progress >= 1f) return
        at(path, progress) { x, y ->
            val radius = 4.6f * minOf(1f, progress * 9f, (1f - progress) * 9f)
            if (radius >= .6f) disc(c, x, y, radius, color, cream)
        }
    }

    private fun leader(c: Canvas, @StringRes id: Int, x: Float, y: Float, width: Float,
                       kneeX: Float, kneeY: Float, endX: Float, endY: Float) {
        line(c, x, y + if (kneeY >= y) 4f else -14f, kneeX, kneeY, guide, .9f)
        line(c, kneeX, kneeY, endX, endY, guide, .9f)
        disc(c, endX, endY, 1.65f, guide, cream)
        label(c, id, x, y, width)
    }

    private fun patch(c: Canvas, path: Path, fill: Long, border: Long) {
        ink(fill); c.drawPath(path, paint)
        stroke(c, path, border, 1.05f)
    }

    private fun area(c: Canvas, path: Path, fill: Shader, border: Long) {
        ink(cream); paint.shader = fill; c.drawPath(path, paint); paint.shader = null
        stroke(c, path, border, 1.3f)
    }
}
