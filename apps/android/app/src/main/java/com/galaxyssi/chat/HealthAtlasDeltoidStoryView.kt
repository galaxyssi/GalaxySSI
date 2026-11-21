package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Path
import android.graphics.Shader
import androidx.annotation.StringRes
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasDeltoidStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.DELTOID_LIFT) {
    private val scapulaPose = Matrix()
    private val armPose = Matrix()
    private val head = FloatArray(2)
    private val bladeAnchor = FloatArray(2)
    private val origins = FloatArray(8)
    private val roots = floatArrayOf(148f, 129f, 186f, 112f, 216f, 109f, 231f, 124f)
    private val controls = FloatArray(8)
    private val neutralControls = floatArrayOf(148f, 167f, 184f, 162f, 223f, 154f, 245f, 151f)
    private val ends = FloatArray(8)
    private val tangents = FloatArray(8)
    private val restingEnds = floatArrayOf(211f, 224f, 214f, 225f, 217f, 225f, 220f, 223f)
    private val clavicleEnd = FloatArray(2)
    private val work = Path()
    private val violetInk = 0xff795b85
    private val plumInk = 0xff9e607f
    private val salmonInk = 0xff9f645f
    private val fiberInks = longArrayOf(violetInk, plumInk, salmonInk)
    private val quietOutline = 0xff7d9699
    private val boneInk = 0xff948777
    private val ivory = shade(101f, 277f, 0xfffffbef, 0xffdfd7c3)
    private val bladeFill = shade(113f, 242f, 0xffdcecef, 0xffb5cfd4)
    private val bodyFill = shade(68f, 315f, 0xffe5f0ee, 0xffd3e3e1)
    private val cap = arrayOf(
        shade(110f, 230f, 0xffd5c6e4, 0xffae97c5),
        shade(106f, 231f, 0xffedc6d7, 0xffc987a6),
        shade(114f, 224f, 0xfff1d1c8, 0xffdba099),
    )
    private val torso = Path().apply {
        moveTo(55f, 306f)
        cubicTo(63f, 268f, 66f, 214f, 64f, 177f)
        cubicTo(61f, 141f, 66f, 112f, 103f, 101f)
        cubicTo(125f, 94f, 129f, 85f, 131f, 71f)
        quadTo(145f, 66f, 157f, 77f)
        cubicTo(158f, 93f, 177f, 101f, 207f, 104f)
        cubicTo(220f, 114f, 211f, 150f, 185f, 176f)
        cubicTo(164f, 222f, 181f, 268f, 185f, 306f)
        quadTo(118f, 322f, 55f, 306f)
        close()
    }
    private val blade = Path().apply {
        moveTo(111f, 124f)
        cubicTo(124f, 113f, 151f, 129f, 180f, 118f)
        quadTo(188f, 106f, 208f, 105f)
        quadTo(224f, 104f, 223f, 113f)
        quadTo(218f, 118f, 201f, 121f)
        cubicTo(195f, 129f, 197f, 131f, 204f, 134f)
        cubicTo(208f, 138f, 208f, 151f, 200f, 158f)
        cubicTo(188f, 164f, 181f, 174f, 169f, 192f)
        quadTo(145f, 219f, 126f, 240f)
        cubicTo(113f, 242f, 106f, 174f, 107f, 146f)
        quadTo(106f, 132f, 111f, 124f)
        close()
    }
    private val ridge = Path().apply {
        moveTo(113f, 150f)
        cubicTo(141f, 139f, 172f, 132f, 190f, 115f)
        quadTo(203f, 106f, 218f, 109f)
        moveTo(120f, 158f)
        quadTo(148f, 153f, 175f, 134f)
    }
    private val bladeContour = Path().apply {
        moveTo(116f, 160f)
        cubicTo(125f, 160f, 149f, 153f, 166f, 143f)
        moveTo(119f, 169f)
        quadTo(118f, 198f, 126f, 222f)
    }
    private val arm = Path().apply {
        moveTo(185f, 142f)
        cubicTo(184f, 127f, 199f, 119f, 212f, 121f)
        cubicTo(234f, 123f, 242f, 142f, 238f, 158f)
        cubicTo(230f, 189f, 235f, 224f, 227f, 267f)
        quadTo(207f, 277f, 185f, 270f)
        cubicTo(183f, 230f, 190f, 194f, 186f, 172f)
        quadTo(182f, 157f, 185f, 142f)
        close()
    }
    private val humerus = Path().apply {
        moveTo(188f, 139f)
        cubicTo(191f, 125f, 204f, 124f, 212f, 130f)
        quadTo(228f, 130f, 225f, 151f)
        cubicTo(214f, 174f, 224f, 202f, 219f, 226f)
        quadTo(216f, 239f, 218f, 261f)
        quadTo(209f, 265f, 199f, 261f)
        cubicTo(201f, 221f, 201f, 177f, 193f, 159f)
        quadTo(185f, 149f, 188f, 139f)
        close()
    }
    private val armContour = Path().apply {
        moveTo(212f, 166f)
        cubicTo(208f, 191f, 215f, 211f, 210f, 250f)
    }

    init { tag = "atlas-function-deltoid-lift-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val ease = t * t * (3f - 2f * t)
        // These are overlapping teaching poses, not measured joint angles or recruitment phases.
        val pose = when (step) {
            1 -> .36f * ease
            2 -> .36f + .64f * ease
            3 -> 1f - ease
            else -> 0f
        }
        setPose(pose)
        tissue(c, torso, bodyFill, 0xffa5bcbc)
        c.save()
        c.concat(scapulaPose)
        tissue(c, blade, bladeFill, quietOutline)
        stroke(c, ridge, 0xff86a3ab, 2f)
        stroke(c, bladeContour, 0xffe6f1f1, 2f)
        c.restore()
        drawClavicle(c)
        c.save()
        c.concat(armPose)
        tissue(c, arm, bodyFill, 0xffa5bcbc)
        tissue(c, humerus, ivory, boneInk)
        stroke(c, armContour, 0xffb9ac94, 1.4f)
        c.restore()
        for (band in 0..2) drawBand(c, band, step, t, pose)

        if (step == 0) {
            partCallout(c, R.string.health_atlas_deltoid_story_spinal, 71f, 60f, 98f, 0, t)
            partCallout(c, R.string.health_atlas_deltoid_story_acromial, 176f, 47f, 178f, 1, t)
            partCallout(c, R.string.health_atlas_deltoid_story_clavicular, 288f, 68f, 263f, 2, t)
        } else {
            if (step >= 2) {
                callout(c, R.string.health_atlas_deltoid_story_blade, 66f, 215f, 99f, bladeAnchor[0], bladeAnchor[1], blue)
            }
            drawSweep(c, pose, step == 3)
        }
        callout(c, R.string.health_atlas_deltoid_story_tuberosity, 271f, 325f, 265f, ends[4], ends[5], plumInk)
    }

    private fun setPose(pose: Float) {
        val bladeTurn = -33f * pose * (.45f + .55f * pose)
        scapulaPose.setRotate(bladeTurn, 157f, 141f)
        scapulaPose.postTranslate(5f * pose, -4f * pose)
        scapulaPose.mapPoints(origins, roots)
        bladeAnchor[0] = 138f
        bladeAnchor[1] = 170f
        scapulaPose.mapPoints(bladeAnchor)
        head[0] = 204f
        head[1] = 142f
        scapulaPose.mapPoints(head)
        armPose.setRotate(-119f * pose, 204f, 142f)
        armPose.postTranslate(head[0] - 204f, head[1] - 142f)
        armPose.mapPoints(ends, restingEnds)

        // Offset the first control points with the moving cap; the far ends stay on the humerus.
        scapulaPose.mapPoints(controls, neutralControls)
        for (i in 0..3) {
            val k = i * 2
            controls[k] += pose * (17f - 2f * i)
            controls[k + 1] -= pose * (18f + 5f * i)
            tangents[k] = ends[k] + blend(-14f + 5.3f * i, -16f, pose)
            tangents[k + 1] = ends[k + 1] + blend(-13f, 4f, pose)
        }
        clavicleEnd[0] = 226f
        clavicleEnd[1] = 117f
        scapulaPose.mapPoints(clavicleEnd)
    }

    private fun drawClavicle(c: Canvas) {
        val x = clavicleEnd[0]
        val y = clavicleEnd[1]
        work.rewind()
        work.moveTo(102f, 108f)
        work.cubicTo(144f, 77f, x - 43f, y - 33f, x, y - 4f)
        work.quadTo(x + 8f, y, x + 1f, y + 7f)
        work.cubicTo(x - 41f, y - 18f, 148f, 86f, 106f, 116f)
        work.quadTo(99f, 120f, 102f, 108f)
        work.close()
        tissue(c, work, ivory, boneInk)
    }

    private fun drawBand(c: Canvas, band: Int, step: Int, t: Float, pose: Float) {
        val left = band * 2
        val right = left + 2
        work.rewind()
        work.moveTo(origins[left], origins[left + 1])
        work.cubicTo(controls[left], controls[left + 1], tangents[left], tangents[left + 1],
            ends[left], ends[left + 1])
        work.lineTo(ends[right], ends[right + 1])
        work.cubicTo(tangents[right], tangents[right + 1], controls[right], controls[right + 1],
            origins[right], origins[right + 1])
        work.close()
        tissue(c, work, cap[band], fiberInks[band])
        val reveal = if (step == 0) partFocus(band, t) else 0f
        for (row in 1..4) {
            val f = row / 5f
            val x = blend(ends[left], ends[right], f)
            val y = blend(ends[left + 1], ends[right + 1], f)
            work.rewind()
            work.moveTo(blend(origins[left], origins[right], f), blend(origins[left + 1], origins[right + 1], f) + 4f)
            work.cubicTo(blend(controls[left], controls[right], f), blend(controls[left + 1], controls[right + 1], f),
                blend(tangents[left], tangents[right], f), blend(tangents[left + 1], tangents[right + 1], f),
                x - 2f * pose, y - 4f * (1f - pose))
            stroke(c, work, if (row % 2 == 0) 0xaafff4f7 else fiberInks[band],
                0.85f + .85f * reveal + if (step == 1 && band == 1) .65f * pose else 0f)
        }
    }

    private fun drawSweep(c: Canvas, pose: Float, lowering: Boolean) {
        val angle = (90f - 119f * pose) * PI.toFloat() / 180f
        val cx = head[0]
        val cy = head[1]
        val radius = 141f
        val start = angle + if (lowering) -.2f else .2f
        val tip = angle + if (lowering) .16f else -.16f
        work.rewind()
        work.moveTo(cx + radius * cos(start), cy + radius * sin(start))
        work.quadTo(cx + (radius + 2f) * cos(angle), cy + (radius + 2f) * sin(angle),
            cx + radius * cos(tip), cy + radius * sin(tip))
        stroke(c, work, blue, 1.8f)
        val nearTip = tip + if (lowering) -.08f else .08f
        arrow(c, cx + radius * cos(nearTip), cy + radius * sin(nearTip),
            cx + radius * cos(tip), cy + radius * sin(tip), blue)
    }

    private fun partCallout(c: Canvas, @StringRes title: Int, x: Float, y: Float, elbow: Float, band: Int, t: Float) {
        val i = band * 2
        val tx = blend(origins[i], origins[i + 2], .53f)
        val ty = blend(origins[i + 1], origins[i + 3], .53f) + 3f
        val focus = partFocus(band, t)
        if (focus > 0f) {
            ink(fiberInks[band], 1.5f)
            paint.alpha = (180f * focus).toInt()
            c.drawCircle(tx, ty, 5f + 5f * focus, paint)
        }
        callout(c, title, x, y, elbow, tx, ty, fiberInks[band])
    }

    private fun partFocus(band: Int, t: Float) =
        (1f - kotlin.math.abs(3f * t - band - .5f)).coerceAtLeast(0f)

    private fun callout(c: Canvas, @StringRes title: Int, x: Float, y: Float, elbow: Float,
        tx: Float, ty: Float, color: Long) {
        val edge = if (ty > y) y + 7f else y - 17f
        line(c, x, edge, elbow, edge, color, 1.1f)
        line(c, elbow, edge, tx, ty, color, 1.1f)
        disc(c, tx, ty, 3f, color, cream)
        label(c, title, x, y, 124f)
    }

    private fun tissue(c: Canvas, path: Path, fill: Shader, border: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, border, 1.5f)
    }

    private fun blend(a: Float, b: Float, t: Float) = a + (b - a) * t
}
