package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader
import androidx.annotation.StringRes
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

internal class HealthAtlasObliqueRotationStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.OBLIQUE_ROTATION) {
    private val boneInk = 0xff928572
    private val axisInk = 0xff68878d
    private val externalInk = 0xff9b5b63
    private val internalInk = 0xff665a88
    private val pelvisFill = shade(101f, 251f, 0xfffcf6e7, 0xffd6c9b8)
    private val ribsFill = shade(129f, 220f, 0xfff9f5e9, 0xffdce7e3)
    private val externalFill = shade(104f, 178f, 0xffefc9bc, 0xffcf8e94)
    private val internalFill = shade(140f, 220f, 0xffe1d7eb, 0xffac9dc4)
    private val centerX = 180f
    private val centerY = 177f
    private val pelvis = Path().apply {
        fillType = Path.FillType.EVEN_ODD
        moveTo(180f, 98f)
        cubicTo(161f, 96f, 145f, 104f, 132f, 116f)
        cubicTo(105f, 131f, 85f, 150f, 82f, 177f)
        cubicTo(78f, 207f, 104f, 231f, 136f, 232f)
        quadTo(154f, 230f, 165f, 243f)
        quadTo(180f, 257f, 195f, 243f)
        quadTo(206f, 230f, 224f, 232f)
        cubicTo(256f, 231f, 282f, 207f, 278f, 177f)
        cubicTo(275f, 150f, 255f, 131f, 228f, 116f)
        cubicTo(215f, 104f, 199f, 96f, 180f, 98f)
        close()
        moveTo(180f, 116f)
        cubicTo(152f, 116f, 123f, 137f, 111f, 158f)
        cubicTo(97f, 184f, 110f, 215f, 144f, 216f)
        quadTo(160f, 217f, 168f, 227f)
        quadTo(180f, 237f, 192f, 227f)
        quadTo(200f, 217f, 216f, 216f)
        cubicTo(250f, 215f, 263f, 184f, 249f, 158f)
        cubicTo(237f, 137f, 208f, 116f, 180f, 116f)
        close()
    }
    private val hipContours = Path().apply {
        moveTo(180f, 100f); lineTo(180f, 115f)
        moveTo(89f, 182f); cubicTo(88f, 207f, 108f, 223f, 134f, 225f)
        moveTo(271f, 182f); cubicTo(272f, 207f, 252f, 223f, 226f, 225f)
        moveTo(162f, 235f); quadTo(180f, 247f, 198f, 235f)
    }
    private val ribs = Path().apply {
        moveTo(180f, 126f)
        cubicTo(161f, 125f, 131f, 135f, 116f, 151f)
        cubicTo(101f, 167f, 111f, 188f, 127f, 199f)
        cubicTo(144f, 212f, 166f, 214f, 180f, 215f)
        cubicTo(194f, 214f, 216f, 212f, 233f, 199f)
        cubicTo(249f, 188f, 259f, 167f, 244f, 151f)
        cubicTo(229f, 135f, 199f, 125f, 180f, 126f)
        close()
    }
    private val ribContours = Path().apply {
        for (side in intArrayOf(-1, 1)) {
            moveTo(180f, 134f)
            cubicTo(180f + side * 28f, 133f, 180f + side * 64f, 152f, 180f + side * 63f, 174f)
            quadTo(180f + side * 61f, 195f, 180f + side * 14f, 205f)
            moveTo(180f, 145f)
            cubicTo(180f + side * 23f, 143f, 180f + side * 48f, 155f, 180f + side * 51f, 175f)
            quadTo(180f + side * 48f, 193f, 180f + side * 14f, 197f)
        }
    }
    private val turns = floatArrayOf(0f, .12f, 1f, 0f, -1f, 0f)
    private val path = Path()
    private val contours = Path()
    private val moving = FloatArray(8)
    private val focusPoints = FloatArray(8)

    init { tag = "atlas-function-oblique-rotation-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val ease = t * t * (3f - 2f * t)
        val turn = mix(turns[step], turns[step + 1], ease)
        val degrees = 27f * turn
        val angle = degrees * PI.toFloat() / 180f
        tissue(c, pelvis, pelvisFill, boneInk)
        stroke(c, hipContours, 0xffae9b85, 1.5f)
        c.save()
        c.rotate(degrees, centerX, centerY)
        tissue(c, ribs, ribsFill, axisInk)
        stroke(c, ribContours, 0xffc5bba7, 2.75f)
        stroke(c, ribContours, 0xfff9f6ec, 1.15f)
        oval(c, 169f, 199f, 191f, 212f, 0xffe7e0cf, boneInk)
        oval(c, 176f, 127f, 184f, 150f, 0xffe3e9dd, axisInk)
        line(c, 180f, 148f, 180f, 194f, 0xffa4b5b1, 1.05f)
        c.restore()

        // Superior view with anterior up: clockwise turns toward the person's right.
        for (side in -1..1 step 2) {
            val i = if (side < 0) 0 else 4
            rotate(i, side * 59f, -11f, angle)
            rotate(i + 2, side * 45f, -28f, angle)
            val external = (-side * turn).coerceAtLeast(0f)
            val internal = (side * turn).coerceAtLeast(0f)
            band(c, i + 2, centerX + side * 85f, 207f, internal, false)
            band(c, i, centerX + side * 28f, 108f, external, true)
        }
        disc(c, centerX, centerY, 4f, 0xffdde9e3, axisInk)
        line(c, 177f, centerY, 183f, centerY, axisInk, 1f)
        line(c, centerX, 174f, centerX, 180f, axisInk, 1f)
        if (step != 4 || t < .92f) motion(c, degrees, turns[step + 1] > turns[step])

        label(c, R.string.health_atlas_oblique_rotation_story_anterior, 180f, 47f, 90f)
        label(c, R.string.health_atlas_oblique_rotation_story_body_left, 58f, 70f, 101f)
        label(c, R.string.health_atlas_oblique_rotation_story_body_right, 302f, 70f, 101f)
        leader(c, R.string.health_atlas_oblique_rotation_story_left_external, 65f, 109f, 105f,
            focusPoints[0], focusPoints[1], externalInk)
        leader(c, R.string.health_atlas_oblique_rotation_story_right_external, 295f, 109f, 255f,
            focusPoints[4], focusPoints[5], externalInk)
        leader(c, R.string.health_atlas_oblique_rotation_story_left_internal, 65f, 274f, 104f,
            focusPoints[2], focusPoints[3], internalInk)
        leader(c, R.string.health_atlas_oblique_rotation_story_right_internal, 295f, 274f, 256f,
            focusPoints[6], focusPoints[7], internalInk)
        leader(c, R.string.health_atlas_oblique_rotation_story_pelvis, 180f, 312f, 180f, 180f, 244f, boneInk)
    }

    private fun rotate(index: Int, x: Float, y: Float, a: Float) {
        moving[index] = centerX + x * cos(a) - y * sin(a)
        moving[index + 1] = centerY + x * sin(a) + y * cos(a)
    }

    private fun band(c: Canvas, index: Int, x: Float, y: Float, effort: Float, external: Boolean) {
        val endX = moving[index]
        val endY = moving[index + 1]
        val dx = endX - x
        val dy = endY - y
        val length = hypot(dx, dy).coerceAtLeast(1f)
        val nx = -dy / length
        val ny = dx / length
        val mx = mix(x, endX, .5f) + if (x < centerX) -10f else 10f
        val my = mix(y, endY, .5f)
        val spread = 10f + 4f * effort
        val color = if (external) externalInk else internalInk
        path.rewind()
        path.moveTo(x - nx * 3f, y - ny * 3f)
        path.quadTo(mx - nx * spread, my - ny * spread, endX - nx * 5f, endY - ny * 5f)
        path.quadTo(endX + dx * .12f, endY + dy * .12f, endX + nx * 5f, endY + ny * 5f)
        path.quadTo(mx + nx * spread, my + ny * spread, x + nx * 3f, y + ny * 3f)
        path.close()
        tissue(c, path, if (external) externalFill else internalFill, color)
        ink(cream)
        paint.alpha = (86f * (1f - effort)).toInt()
        c.drawPath(path, paint)
        ink(color)
        paint.alpha = (88f * effort).toInt()
        c.drawPath(path, paint)
        contours.rewind()
        for (strand in -1..1) {
            val offset = strand * spread * .5f
            contours.moveTo(x + nx * strand * 1.65f, y + ny * strand * 1.65f)
            contours.quadTo(mx + nx * offset, my + ny * offset,
                endX + nx * strand * 2.25f, endY + ny * strand * 2.25f)
        }
        stroke(c, contours, if (external) 0xfff8ded3 else 0xffeee6f2, .95f + .25f * effort)
        focusPoints[index] = (x + 2f * mx + endX) * .25f
        focusPoints[index + 1] = (y + 2f * my + endY) * .25f
    }

    private fun motion(c: Canvas, degrees: Float, right: Boolean) {
        val d = if (right) 1f else -1f
        val tip = -90f + degrees + 8f * d
        val start = tip - 22f * d
        ink(0xffb4c6c5, 1.1f)
        c.drawArc(79f, 76f, 281f, 278f, -127f, 74f, false, paint)
        ink(blue, 1.85f)
        c.drawArc(79f, 76f, 281f, 278f, minOf(start, tip), 22f, false, paint)
        val a = tip * PI.toFloat() / 180f
        val x = centerX + 101f * cos(a)
        val y = centerY + 101f * sin(a)
        arrow(c, x + 8f * d * sin(a), y - 8f * d * cos(a), x, y, blue)
    }

    private fun leader(c: Canvas, @StringRes res: Int, x: Float, y: Float, elbow: Float,
        tx: Float, ty: Float, color: Long) {
        val edge = if (ty > y) y + 6f else y - 17f
        line(c, x, edge, elbow, edge, color, 1.05f)
        line(c, elbow, edge, tx, ty, color, 1.05f)
        disc(c, tx, ty, 2.75f, color, cream)
        label(c, res, x, y, 110f)
    }

    private fun tissue(c: Canvas, shape: Path, fill: Shader, border: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(shape, paint)
        paint.shader = null
        stroke(c, shape, border, 1.35f)
    }

    private fun mix(a: Float, b: Float, t: Float) = a + (b - a) * t
}
