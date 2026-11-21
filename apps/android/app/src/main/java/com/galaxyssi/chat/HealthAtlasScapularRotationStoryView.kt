package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Path
import android.graphics.Shader
import androidx.annotation.StringRes

internal class HealthAtlasScapularRotationStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.SCAPULAR_ROTATION) {
    private val turn = Matrix()
    private val armTurn = Matrix()
    private val sites = floatArrayOf(253f, 114f, 243f, 125f, 193f, 143f, 187f, 153f,
        194f, 247f, 251f, 142f, 181f, 177f)
    private val pts = FloatArray(sites.size)
    private val work = Path()
    private val fold = Path()
    private val ribs = arrayOf(
        rib(118f, 118f, 170f, 102f, 224f, 119f, 250f, 145f),
        rib(116f, 143f, 169f, 116f, 240f, 140f, 270f, 170f),
        rib(116f, 166f, 174f, 132f, 251f, 161f, 281f, 192f),
        rib(116f, 190f, 177f, 150f, 254f, 180f, 280f, 212f),
        rib(116f, 215f, 177f, 169f, 250f, 205f, 275f, 234f),
        rib(115f, 240f, 175f, 195f, 242f, 224f, 269f, 254f),
        rib(116f, 263f, 166f, 226f, 234f, 244f, 257f, 272f),
    )
    private val roseInk = 0xff9c5f79
    private val mauveInk = 0xff846280
    private val plumInk = 0xff735d8c
    private val serratusInk = 0xff477e79
    private val boneInk = 0xff6e8c94
    private val bodyFill = shade(51f, 304f, 0xffe1eded, 0xffccdcde)
    private val boneFill = shade(109f, 249f, 0xfff8f6ed, 0xffbccfd4)
    private val upperFill = shade(49f, 125f, 0xffefcbd1, 0xffd49cb4)
    private val middleFill = shade(102f, 159f, 0xffe8d2e9, 0xffc1a0c2)
    private val lowerFill = shade(147f, 274f, 0xffd9cbe7, 0xffaa9bc8)
    private val serratusFill = shade(161f, 245f, 0xffd3ebe3, 0xff96c1b7)
    private val back = Path().apply {
        moveTo(89f, 294f)
        cubicTo(86f, 251f, 75f, 208f, 72f, 165f)
        cubicTo(69f, 140f, 79f, 118f, 89f, 103f)
        quadTo(98f, 89f, 100f, 54f)
        quadTo(113f, 46f, 128f, 54f)
        cubicTo(130f, 91f, 168f, 93f, 209f, 104f)
        cubicTo(239f, 107f, 268f, 125f, 279f, 153f)
        cubicTo(295f, 190f, 284f, 252f, 270f, 287f)
        quadTo(213f, 314f, 89f, 294f)
        close()
    }
    private val blade = Path().apply {
        moveTo(188f, 106f)
        quadTo(211f, 110f, 230f, 124f)
        quadTo(237f, 116f, 242f, 107f)
        quadTo(251f, 101f, 260f, 109f)
        quadTo(263f, 117f, 250f, 122f)
        quadTo(246f, 129f, 253f, 135f)
        quadTo(257f, 143f, 250f, 155f)
        cubicTo(229f, 166f, 214f, 216f, 194f, 247f)
        quadTo(190f, 252f, 188f, 243f)
        cubicTo(186f, 216f, 179f, 189f, 180f, 159f)
        quadTo(179f, 124f, 188f, 106f)
        close()
    }
    private val ridge = Path().apply {
        moveTo(181f, 149f)
        cubicTo(195f, 140f, 225f, 147f, 246f, 121f)
        quadTo(251f, 115f, 256f, 114f)
        moveTo(201f, 154f)
        quadTo(221f, 156f, 238f, 139f)
    }
    private val arm = Path().apply {
        moveTo(251f, 131f)
        cubicTo(258f, 124f, 269f, 126f, 273f, 135f)
        cubicTo(277f, 145f, 268f, 151f, 268f, 161f)
        lineTo(272f, 193f)
        quadTo(265f, 199f, 257f, 195f)
        lineTo(255f, 164f)
        quadTo(248f, 148f, 251f, 131f)
        close()
    }
    private val ribEnds = floatArrayOf(264f, 173f, 276f, 193f, 277f, 214f, 270f, 237f, 265f, 254f)

    init { tag = "atlas-function-scapular-rotation-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val ease = t * t * (3f - 2f * t)
        // Continuous 2D teaching poses, with no fixed force magnitude or on/off muscle phases.
        val pose = when (step) {
            1 -> .18f * ease
            2 -> .18f + .41f * ease
            3 -> .59f + .41f * ease
            4 -> 1f - ease
            else -> 0f
        }
        turn.setRotate(-36f * pose, 212f, 153f)
        turn.postTranslate(2f * pose, -6f * pose)
        turn.mapPoints(pts, sites)
        tissue(c, back, bodyFill, 0xffa4b7bd)
        drawRibs(c)
        if (step == 3 || step == 4) {
            stroke(c, blade, 0xff9baab1, 1.1f)
        }
        drawSerratus(c, if (step == 0) t else 1f)
        drawClavicle(c)

        val socketX = pts[10]
        val socketY = pts[11]
        armTurn.setRotate(-116f * pose, 251f, 142f)
        armTurn.postTranslate(socketX - 251f, socketY - 142f)
        c.save()
        c.concat(armTurn)
        tissue(c, arm, boneFill, boneInk)
        c.restore()
        c.save()
        c.concat(turn)
        tissue(c, blade, boneFill, boneInk)
        stroke(c, ridge, 0xff829ca3, 1.9f)
        oval(c, 247f, 135f, 254f, 151f, 0xffcadcdf, boneInk)
        c.restore()

        drawTrapezius(c, if (step == 0) t else -1f)
        if (step in 1..3) drawPulls(c, step, pose)
        if (step >= 3) drawSocket(c, step == 4)
        if (step == 0 || step == 1) {
            key(c, R.string.health_atlas_scapular_rotation_story_upper, 53f, 74f, 116f, 76f, roseInk,
                if (step == 0) regionFocus(0, t) else 0f)
            key(c, R.string.health_atlas_scapular_rotation_story_middle, 47f, 137f, 137f, 132f, mauveInk,
                if (step == 0) regionFocus(1, t) else 0f)
        }
        if (step <= 2) {
            key(c, R.string.health_atlas_scapular_rotation_story_lower, 59f, 250f, 129f, 224f, plumInk,
                if (step == 0) regionFocus(2, t) else 0f)
            key(c, R.string.health_atlas_scapular_rotation_story_serratus, 282f, 309f, 260f, 233f, serratusInk,
                if (step == 0) regionFocus(3, t) else 0f)
        }
        if (step == 1) {
            key(c, R.string.health_atlas_scapular_rotation_story_clavicle_label, 280f, 70f, pts[0], pts[1], roseInk)
        }
        if (step >= 2) {
            key(c, R.string.health_atlas_scapular_rotation_story_inferior_angle, 202f, 328f, pts[8], pts[9], blue)
        }
    }

    private fun drawRibs(c: Canvas) {
        for (rib in ribs) {
            stroke(c, rib, 0xffa4b8bd, 8.5f)
            stroke(c, rib, 0xfff3f4e8, 6f)
        }
        for (i in 0..10) {
            val y = 77f + i * 18f
            oval(c, 106f, y, 119f, y + 16f, 0xffe9e9dc, 0xffacb4aa)
        }
    }

    private fun drawClavicle(c: Canvas) {
        val x = pts[0]
        val y = pts[1]
        work.rewind()
        work.moveTo(x - 31f, y + 6f)
        work.quadTo(x - 15f, y - 7f, x + 7f, y - 5f)
        work.quadTo(x + 15f, y - 1f, x + 8f, y + 5f)
        work.quadTo(x - 8f, y + 4f, x - 31f, y + 11f)
        work.close()
        tissue(c, work, boneFill, boneInk)
    }

    private fun drawSerratus(c: Canvas, emphasis: Float) {
        for (i in 0..4) {
            val f = i / 4f
            val x = blend(pts[12], pts[8], f)
            val y = blend(pts[13], pts[9], f)
            val rx = ribEnds[i * 2]
            val ry = ribEnds[i * 2 + 1]
            work.rewind()
            work.moveTo(x - 2f, y - 9f)
            work.cubicTo(blend(x, rx, .43f), y - 11f, rx - 9f, ry - 15f, rx, ry)
            work.cubicTo(rx - 11f, ry - 3f, blend(x, rx, .56f), y + 10f, x - 1f, y + 3f)
            work.close()
            tissue(c, work, serratusFill, serratusInk)
            fold.rewind()
            fold.moveTo(x, y - 3f)
            fold.quadTo(blend(x, rx, .65f), y - 1f, rx - 6f, ry - 4f)
            stroke(c, fold, 0xddf1fbef, 1f + .6f * emphasis)
        }
    }

    private fun drawTrapezius(c: Canvas, reveal: Float) {
        drawFan(c, 0, 0, 111f, 54f, 113f, 111f, upperFill, roseInk, reveal)
        drawFan(c, 2, 4, 113f, 111f, 114f, 159f, middleFill, mauveInk, reveal)
        drawFan(c, 4, 6, 114f, 159f, 110f, 275f, lowerFill, plumInk, reveal)
    }

    private fun drawFan(c: Canvas, start: Int, end: Int, ax: Float, ay: Float, bx: Float, by: Float,
        fill: Shader, color: Long, reveal: Float) {
        val x1 = pts[start]
        val y1 = pts[start + 1]
        val x2 = pts[end] - if (start == end) 13f else 0f
        val y2 = pts[end + 1] + if (start == end) 6f else 0f
        work.rewind()
        work.moveTo(ax, ay)
        work.quadTo(blend(ax, x1, .36f), blend(ay, y1, .73f) - 10f, x1, y1)
        work.lineTo(x2, y2)
        work.quadTo(blend(bx, x2, .47f), blend(by, y2, .60f) + 9f, bx, by)
        work.quadTo(bx + 6f, (ay + by) / 2f, ax, ay)
        work.close()
        tissue(c, work, fill, color)
        val focus = regionFocus(start / 2, reveal)
        for (i in 1..5) {
            val f = i / 6f
            val fromX = blend(ax, bx, f) + 4f
            val fromY = blend(ay, by, f)
            val toX = blend(x1, x2, f) - 5f
            val toY = blend(y1, y2, f)
            fold.rewind()
            fold.moveTo(fromX, fromY)
            fold.quadTo(blend(fromX, toX, .44f), blend(fromY, toY, .69f) + f * 10f - 6f, toX, toY)
            stroke(c, fold, if (i % 2 == 0) 0xd9fff3f4 else color, .9f + focus * .9f)
        }
    }

    private fun drawPulls(c: Canvas, step: Int, pose: Float) {
        // Force arrows point from each insertion back toward its origin; blue arrows show motion.
        val span = .38f + .26f * pose
        pull(c, pts[0], pts[1], 118f, 70f, span, roseInk)
        pull(c, pts[2], pts[3], 117f, 134f, span * .76f, mauveInk)
        if (step >= 2) {
            pull(c, pts[4], pts[5], 116f, 235f, span, plumInk)
            pull(c, pts[8], pts[9], 271f, 222f, span, serratusInk)
        }
    }

    private fun pull(c: Canvas, x: Float, y: Float, dx: Float, dy: Float, span: Float, color: Long) {
        val x1 = blend(x, dx, .10f)
        val y1 = blend(y, dy, .10f)
        val x2 = blend(x, dx, span)
        val y2 = blend(y, dy, span)
        line(c, x1, y1, x2, y2, cream, 4.4f)
        arrow(c, x1, y1, x2, y2, color)
    }

    private fun drawSocket(c: Canvas, returning: Boolean) {
        val x = pts[10]
        val y = pts[11]
        val dx = x - pts[4]
        val dy = y - pts[5]
        val inv = 1f / kotlin.math.hypot(dx, dy)
        arrow(c, x + 4f * dx * inv, y + 4f * dy * inv, x + 31f * dx * inv, y + 31f * dy * inv, blue)
        key(c, R.string.health_atlas_scapular_rotation_story_socket, 299f, 61f, x, y, blue)
        val tx = pts[8]
        val ty = pts[9]
        val offset = if (returning) 12f else -12f
        arrow(c, tx + offset, ty + 16f, tx - offset, ty + 16f, blue)
    }

    private fun key(c: Canvas, @StringRes title: Int, x: Float, y: Float, tx: Float, ty: Float,
        color: Long, focus: Float = 0f) {
        if (focus > 0f) {
            ink(color, 1.5f)
            paint.alpha = (180f * focus).toInt()
            c.drawCircle(tx, ty, 5f + 5f * focus, paint)
        }
        val edge = if (ty > y) y + 7f else y - 17f
        line(c, x, edge, tx, ty, color, 1.1f)
        disc(c, tx, ty, 3f, color, cream)
        label(c, title, x, y, if (x < 80f) 86f else 108f)
    }

    private fun regionFocus(band: Int, t: Float) =
        (1f - kotlin.math.abs(4f * t - band - .5f)).coerceAtLeast(0f)

    private fun tissue(c: Canvas, path: Path, fill: Shader, border: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, border, 1.45f)
    }

    private fun rib(x: Float, y: Float, a: Float, b: Float, d: Float, e: Float, endX: Float, endY: Float) =
        Path().apply { moveTo(x, y); cubicTo(a, b, d, e, endX, endY) }

    private fun blend(a: Float, b: Float, t: Float) = a + (b - a) * t
}
