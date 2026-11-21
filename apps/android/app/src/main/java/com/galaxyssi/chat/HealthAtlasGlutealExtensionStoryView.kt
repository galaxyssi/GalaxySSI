package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasGlutealExtensionStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.GLUTEAL_EXTENSION) {
    private val pelvicTurn = Matrix()
    private val femurTurn = Matrix()
    private val origin = floatArrayOf(128f, 118f, 116f, 138f, 112f, 161f, 117f, 177f)
    private val insertion = floatArrayOf(159f, 207f, 164f, 219f, 158f, 233f)
    private val mappedOrigin = FloatArray(origin.size)
    private val mappedInsertion = FloatArray(insertion.size)
    private val marker = FloatArray(2)
    private val fiber = Path()
    private val muscle = Path()
    private val tendon = Path()
    private val spine = Path()
    private val arc = RectF()
    private val boneInk = 0xff779095
    private val muscleInk = 0xff9e617a
    private val boneFill = shade(112f, 304f, 0xfffff4de, 0xffb8cdcc)
    private val jointFill = shade(144f, 205f, 0xfff2e7d8, 0xffbdd5d2)
    private val gluteFill = shade(121f, 236f, 0xffecc4c7, 0xffb87996)
    private val ilium = Path().apply {
        moveTo(119f, 126f)
        cubicTo(133f, 103f, 165f, 96f, 194f, 102f)
        cubicTo(216f, 105f, 240f, 119f, 245f, 132f)
        quadTo(249f, 142f, 239f, 145f)
        quadTo(230f, 141f, 222f, 148f)
        quadTo(215f, 160f, 219f, 174f)
        quadTo(224f, 185f, 235f, 187f)
        quadTo(244f, 192f, 246f, 204f)
        quadTo(240f, 211f, 229f, 209f)
        quadTo(216f, 204f, 209f, 212f)
        cubicTo(199f, 230f, 178f, 237f, 161f, 227f)
        quadTo(146f, 219f, 154f, 206f)
        quadTo(161f, 195f, 150f, 186f)
        quadTo(135f, 171f, 141f, 160f)
        quadTo(140f, 153f, 127f, 152f)
        quadTo(116f, 145f, 119f, 126f)
        close()
    }
    private val crest = Path().apply {
        moveTo(127f, 130f)
        cubicTo(151f, 105f, 204f, 105f, 236f, 132f)
        moveTo(151f, 135f)
        cubicTo(174f, 121f, 202f, 122f, 221f, 138f)
        moveTo(203f, 201f)
        quadTo(212f, 187f, 227f, 195f)
    }
    private val sacrum = Path().apply {
        moveTo(121f, 124f)
        quadTo(137f, 119f, 147f, 130f)
        cubicTo(137f, 146f, 135f, 164f, 130f, 177f)
        quadTo(125f, 187f, 121f, 176f)
        quadTo(119f, 162f, 114f, 153f)
        quadTo(109f, 139f, 121f, 124f)
        close()
    }
    private val femur = Path().apply {
        moveTo(201f, 159f)
        cubicTo(212f, 167f, 210f, 183f, 199f, 188f)
        quadTo(188f, 192f, 183f, 198f)
        cubicTo(179f, 218f, 175f, 258f, 175f, 306f)
        quadTo(165f, 313f, 153f, 306f)
        cubicTo(152f, 276f, 155f, 244f, 154f, 213f)
        quadTo(150f, 205f, 147f, 199f)
        quadTo(146f, 186f, 156f, 185f)
        quadTo(162f, 183f, 166f, 190f)
        quadTo(173f, 184f, 176f, 170f)
        cubicTo(180f, 157f, 190f, 154f, 201f, 159f)
        close()
    }
    private val femoralRidge = Path().apply {
        moveTo(153f, 195f)
        cubicTo(166f, 209f, 162f, 241f, 161f, 296f)
        moveTo(186f, 164f)
        quadTo(195f, 159f, 202f, 170f)
    }

    init { tag = "atlas-function-gluteal-extension-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val ease = t * t * (3f - 2f * t)
        when (step) {
            0 -> attachments(c, t)
            1 -> movingFemur(c, ease)
            2 -> movingPelvis(c, ease)
            else -> compare(c, ease)
        }
    }

    private fun attachments(c: Canvas, t: Float) {
        anatomy(c, 0f, 0f, 0f)
        val focus = (1f + wave(t - .25f)) / 2f
        ink(muscleInk, 1.4f)
        paint.alpha = (80f + 120f * focus).toInt()
        c.drawCircle(164f, 219f, 6f + 3f * focus, paint)
        key(c, R.string.health_atlas_gluteal_extension_story_gluteus, 64f, 208f, 132f, 178f, muscleInk, 110f)
        key(c, R.string.health_atlas_gluteal_extension_story_pelvis_label, 284f, 103f, 220f, 125f, boneInk, 113f)
        key(c, R.string.health_atlas_gluteal_extension_story_socket, 287f, 170f, HIP_X, HIP_Y, blue, 107f)
        key(c, R.string.health_atlas_gluteal_extension_story_femoral_attachment, 266f, 254f,
            164f, 219f, muscleInk, 128f)
        label(c, R.string.health_atlas_gluteal_extension_story_lateral, 181f, 32f, 216f)
    }

    private fun movingFemur(c: Canvas, ease: Float) {
        ghost(c, femur, -32f)
        anatomy(c, 0f, blend(-32f, 12f, ease), 0f)
        sweep(c, 150f, 58f, 44f, ease)
        key(c, R.string.health_atlas_gluteal_extension_story_pelvis_fixed, 286f, 92f,
            221f, 125f, boneInk, 110f)
        trackedKey(c, R.string.health_atlas_gluteal_extension_story_femur_moves, 76f, 246f,
            femurTurn, 162f, 262f, 114f)
    }

    private fun movingPelvis(c: Canvas, ease: Float) {
        ghost(c, ilium, 29f)
        anatomy(c, blend(29f, -15f, ease), 0f, 0f)
        sweep(c, 131f, -61f, -44f, ease)
        trackedKey(c, R.string.health_atlas_gluteal_extension_story_pelvis_moves, 293f, 218f,
            pelvicTurn, 218f, 139f, 110f)
        key(c, R.string.health_atlas_gluteal_extension_story_femur_fixed, 248f, 307f,
            164f, 269f, boneInk, 104f)
    }

    private fun compare(c: Canvas, ease: Float) {
        line(c, 180f, 76f, 180f, 275f, 0xffbbcecb, 1.1f)
        c.save()
        c.translate(-8f, 70f)
        c.scale(.54f, .54f)
        ghost(c, femur, -32f)
        anatomy(c, 0f, blend(-32f, 12f, ease), 0f)
        sweep(c, 150f, 58f, 44f, ease)
        c.restore()
        c.save()
        c.translate(173f, 70f)
        c.scale(.54f, .54f)
        lumbar(c, 1f, ghost = true)
        anatomy(c, 0f, 0f, 1f - ease)
        arrow(c, 182f, 49f, 147f, 49f, teal)
        c.restore()
        label(c, R.string.health_atlas_gluteal_extension_story_hip_motion, 94f, 71f, 142f)
        label(c, R.string.health_atlas_gluteal_extension_story_spine_motion, 275f, 71f, 142f)
        label(c, R.string.health_atlas_gluteal_extension_story_hip_angle_changes, 94f, 277f, 146f)
        label(c, R.string.health_atlas_gluteal_extension_story_hip_angle_fixed, 275f, 277f, 146f)
    }

    private fun anatomy(c: Canvas, pelvisAngle: Float, femurAngle: Float, lumbarFlex: Float) {
        pelvicTurn.setRotate(pelvisAngle, HIP_X, HIP_Y)
        femurTurn.setRotate(femurAngle, HIP_X, HIP_Y)
        pelvicTurn.mapPoints(mappedOrigin, origin)
        femurTurn.mapPoints(mappedInsertion, insertion)
        c.save()
        c.concat(pelvicTurn)
        lumbar(c, lumbarFlex)
        tissue(c, sacrum, jointFill, boneInk)
        tissue(c, ilium, boneFill, boneInk)
        stroke(c, crest, 0xffa7b8aa, 1.45f)
        oval(c, 165f, 150f, 215f, 196f, jointFill, boneInk)
        c.restore()
        c.save()
        c.concat(femurTurn)
        tissue(c, femur, boneFill, boneInk)
        stroke(c, femoralRidge, 0xffa6b9ad, 1.25f)
        c.restore()
        drawGluteus(c)
        disc(c, HIP_X, HIP_Y, 6.5f, cream, blue)
        disc(c, HIP_X, HIP_Y, 2.6f, blue)
    }

    private fun lumbar(c: Canvas, flex: Float, ghost: Boolean = false) {
        spine.rewind()
        spine.moveTo(139f + 38f * flex, 56f)
        spine.cubicTo(151f + 14f * flex, 79f, 151f + 8f * flex, 104f, 135f, 134f)
        stroke(c, spine, if (ghost) 0xff9db4b8 else boneInk, if (ghost) 1.4f else 3.5f)
        for (i in 0..4) {
            val y = 60f + 14f * i
            val f = i / 5f
            val x = 141f + 7f * sin(PI.toFloat() * f) + 34f * flex * (1f - f) * (1f - f)
            if (ghost) {
                ink(0xff9db4b8, 1.25f)
                c.drawRoundRect(x - 10f, y - 5f, x + 9f, y + 5f, 3.4f, 3.4f, paint)
            } else {
                oval(c, x - 11f, y - 5.5f, x + 9f, y + 5.5f, 0xfff8f1df, boneInk)
                line(c, x - 11f, y, x - 16f, y + 3f, boneInk, 1.4f)
            }
        }
    }

    private fun drawGluteus(c: Canvas) {
        val a = mappedOrigin
        val b = mappedInsertion
        // Oblique fascicles span the two rotating bones behind the hip center.
        muscle.rewind()
        muscle.moveTo(a[0], a[1])
        muscle.cubicTo(a[0] + 22f, a[1] + 9f, b[0] - 10f, b[1] - 20f, b[0], b[1])
        muscle.quadTo(b[2] + 3f, b[3] - 8f, b[2], b[3])
        muscle.quadTo(b[4] - 3f, b[5] - 7f, b[4], b[5])
        muscle.cubicTo(b[4] - 27f, b[5] - 6f, a[6] - 13f, a[7] + 19f, a[6], a[7])
        muscle.cubicTo(a[4] - 10f, a[5] - 3f, a[2] - 13f, a[3] - 6f, a[0], a[1])
        muscle.close()
        tissue(c, muscle, gluteFill, muscleInk)
        c.save()
        c.clipPath(muscle)
        for (i in 1..6) {
            val f = i / 7f
            val x = blend(a[0], a[6], f) - 9f
            val y = blend(a[1], a[7], f)
            val tx = blend(b[0], b[4], f)
            val ty = blend(b[1], b[5], f)
            fiber.rewind()
            fiber.moveTo(x, y)
            fiber.cubicTo(x + 23f, y + 9f, tx - 18f, ty - 15f, tx, ty)
            stroke(c, fiber, if (i % 2 == 0) 0xfff8d9d4 else 0xffb77e93, 1.25f)
        }
        c.restore()
        tendon.rewind()
        tendon.moveTo(b[0], b[1])
        tendon.quadTo(b[2] + 5f, b[3] - 5f, b[2], b[3])
        tendon.quadTo(b[4] + 3f, b[5] - 5f, b[4], b[5])
        stroke(c, tendon, 0xffeedbd5, 3.3f)
        stroke(c, tendon, 0xffa17e8d, 1.15f)
    }

    private fun sweep(c: Canvas, radius: Float, start: Float, span: Float, position: Float) {
        arc.set(HIP_X - radius, HIP_Y - radius, HIP_X + radius, HIP_Y + radius)
        ink(0xff97b4be, 1.6f)
        c.drawArc(arc, start, span, false, paint)
        val theta = radians(start + span * position)
        disc(c, HIP_X + radius * cos(theta), HIP_Y + radius * sin(theta), 4f, blue, cream)
        val end = radians(start + span)
        val near = radians(start + span - if (span > 0f) 4f else -4f)
        arrow(c, HIP_X + radius * cos(near), HIP_Y + radius * sin(near),
            HIP_X + radius * cos(end), HIP_Y + radius * sin(end), blue)
    }

    private fun ghost(c: Canvas, path: Path, angle: Float) {
        c.save()
        c.rotate(angle, HIP_X, HIP_Y)
        stroke(c, path, 0xff98adb0, 1.35f)
        c.restore()
    }

    private fun trackedKey(c: Canvas, res: Int, x: Float, y: Float, turn: Matrix, tx: Float, ty: Float, width: Float) {
        marker[0] = tx
        marker[1] = ty
        turn.mapPoints(marker)
        key(c, res, x, y, marker[0], marker[1], blue, width)
    }

    private fun key(c: Canvas, res: Int, x: Float, y: Float, tx: Float, ty: Float, color: Long, width: Float) {
        line(c, x, if (ty > y) y + 6f else y - 15f, tx, ty, color, 1.1f)
        disc(c, tx, ty, 3f, color, cream)
        label(c, res, x, y, width)
    }

    private fun tissue(c: Canvas, path: Path, fill: Shader, border: Long) {
        ink(cream); paint.shader = fill; c.drawPath(path, paint); paint.shader = null
        stroke(c, path, border, 1.45f)
    }

    private fun radians(degrees: Float) = degrees * (PI.toFloat() / 180f)
    private fun blend(a: Float, b: Float, t: Float) = a + (b - a) * t

    private companion object {
        const val HIP_X = 190f
        const val HIP_Y = 173f
    }
}
