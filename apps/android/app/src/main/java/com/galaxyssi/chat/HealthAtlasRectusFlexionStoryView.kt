package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader
import androidx.annotation.StringRes
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasRectusFlexionStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.RECTUS_TRUNK_FLEXION) {
    private val wallInk = 0xff91a7a5
    private val boneInk = 0xff998a77
    private val rectusInk = 0xffa06269
    private val wallFill = shade(69f, 281f, 0xffe7f2ee, 0xffccdedb)
    private val ribFill = shade(80f, 169f, 0xfffcf8eb, 0xffdfd7c5)
    private val pelvicFill = shade(239f, 306f, 0xfff8f4e7, 0xffd7cbb5)
    private val muscleFill = shade(137f, 260f, 0xffedc4bd, 0xffc08788)
    private val wall = Path().apply {
        moveTo(110f, 73f)
        cubicTo(132f, 55f, 177f, 62f, 200f, 76f)
        cubicTo(224f, 90f, 231f, 116f, 230f, 144f)
        cubicTo(228f, 175f, 237f, 210f, 224f, 243f)
        quadTo(222f, 254f, 215f, 266f)
        quadTo(155f, 282f, 111f, 269f)
        cubicTo(105f, 241f, 123f, 206f, 117f, 174f)
        cubicTo(115f, 153f, 100f, 134f, 98f, 111f)
        quadTo(95f, 88f, 110f, 73f)
        close()
    }
    private val ribCage = Path().apply {
        moveTo(111f, 87f)
        cubicTo(139f, 70f, 191f, 78f, 212f, 100f)
        quadTo(224f, 114f, 218f, 141f)
        cubicTo(192f, 151f, 180f, 139f, 163f, 156f)
        quadTo(130f, 175f, 119f, 151f)
        cubicTo(106f, 132f, 99f, 103f, 111f, 87f)
        close()
    }
    private val ribLines = Path().apply {
        moveTo(108f, 97f); cubicTo(143f, 89f, 185f, 114f, 215f, 110f)
        moveTo(106f, 108f); cubicTo(145f, 102f, 184f, 125f, 218f, 121f)
        moveTo(108f, 119f); cubicTo(146f, 115f, 184f, 136f, 219f, 132f)
        moveTo(112f, 130f); cubicTo(148f, 126f, 183f, 146f, 218f, 141f)
        moveTo(116f, 142f); cubicTo(145f, 139f, 173f, 150f, 194f, 147f)
        moveTo(121f, 153f); quadTo(150f, 147f, 174f, 152f)
    }
    private val cartilage = Path().apply {
        moveTo(217f, 116f)
        quadTo(224f, 128f, 220f, 138f)
        quadTo(215f, 147f, 199f, 152f)
        quadTo(202f, 144f, 210f, 136f)
        quadTo(216f, 130f, 217f, 116f)
        close()
    }
    private val spine = Path().apply {
        moveTo(123f, 148f)
        cubicTo(124f, 180f, 145f, 204f, 139f, 237f)
        quadTo(136f, 251f, 128f, 269f)
        lineTo(140f, 273f)
        cubicTo(153f, 253f, 160f, 232f, 154f, 206f)
        cubicTo(149f, 183f, 141f, 164f, 140f, 149f)
        close()
    }
    private val discs = Path().apply {
        moveTo(126f, 169f); lineTo(143f, 167f)
        moveTo(133f, 189f); lineTo(148f, 186f)
        moveTo(139f, 210f); lineTo(155f, 207f)
        moveTo(139f, 231f); lineTo(155f, 232f)
        moveTo(135f, 251f); lineTo(150f, 255f)
    }
    private val pelvis = Path().apply {
        moveTo(118f, 245f)
        cubicTo(138f, 233f, 166f, 236f, 184f, 247f)
        cubicTo(193f, 252f, 196f, 260f, 205f, 258f)
        quadTo(219f, 253f, 221f, 265f)
        cubicTo(220f, 276f, 201f, 281f, 190f, 290f)
        quadTo(169f, 310f, 140f, 299f)
        cubicTo(124f, 293f, 119f, 277f, 113f, 265f)
        quadTo(108f, 251f, 118f, 245f)
        close()
    }
    private val pelvicDetail = Path().apply {
        moveTo(121f, 250f); cubicTo(141f, 241f, 165f, 243f, 181f, 252f)
        moveTo(143f, 280f); cubicTo(150f, 289f, 168f, 290f, 181f, 280f)
        moveTo(207f, 259f); quadTo(212f, 263f, 211f, 271f)
    }
    private val rectus = Path().apply {
        moveTo(211f, 138f)
        quadTo(216f, 137f, 224f, 136f)
        cubicTo(226f, 155f, 227f, 184f, 226f, 201f)
        cubicTo(225f, 227f, 219f, 245f, 214f, 260f)
        lineTo(205f, 260f)
        cubicTo(206f, 239f, 210f, 221f, 209f, 201f)
        cubicTo(210f, 176f, 208f, 156f, 211f, 138f)
        close()
    }
    private val intersections = Path().apply {
        moveTo(210f, 166f); quadTo(217f, 169f, 225f, 165f)
        moveTo(210f, 198f); quadTo(217f, 201f, 226f, 196f)
        moveTo(208f, 228f); quadTo(215f, 230f, 221f, 225f)
    }
    private val fascicles = Path().apply {
        moveTo(215f, 143f); quadTo(213f, 157f, 215f, 165f)
        moveTo(220f, 141f); quadTo(220f, 154f, 222f, 165f)
        moveTo(215f, 169f); quadTo(214f, 181f, 215f, 196f)
        moveTo(221f, 169f); quadTo(223f, 185f, 221f, 196f)
        moveTo(214f, 201f); quadTo(214f, 217f, 212f, 226f)
        moveTo(221f, 201f); quadTo(220f, 217f, 217f, 226f)
        moveTo(215f, 231f); quadTo(212f, 246f, 210f, 255f)
    }
    private val poses = floatArrayOf(0f, .07f, .33f, 1f, .25f, 0f)
    private val effort = floatArrayOf(0f, .16f, .67f, 1f, .33f, 0f)
    private val formed = Path()
    private val measure = PathMeasure()
    private val sample = FloatArray(2)
    private val mapped = FloatArray(2)
    private var bend = 0f

    init { tag = "atlas-function-rectus-trunk-flexion-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val ease = t * t * (3f - 2f * t)
        bend = .57f * lerp(poses[step], poses[step + 1], ease)
        val tone = lerp(effort[step], effort[step + 1], ease)
        tissue(c, deflect(wall), wallFill, wallInk)
        tissue(c, deflect(ribCage), ribFill, boneInk)
        val ribs = deflect(ribLines)
        stroke(c, ribs, 0xffc4b49f, 3.6f)
        stroke(c, ribs, 0xfffcf5e7, 2.05f)
        tissue(c, deflect(cartilage), ribFill, boneInk)
        tissue(c, deflect(spine), ribFill, boneInk)
        stroke(c, deflect(discs), 0xffa0b6b6, 2.4f)
        tissue(c, pelvis, pelvicFill, boneInk)
        stroke(c, pelvicDetail, 0xffb7a68f, 1.65f)
        line(c, 105f, 308f, 226f, 308f, wallInk, 1.25f)

        val belly = deflect(rectus)
        tissue(c, belly, muscleFill, rectusInk)
        ink(0xffa25361)
        paint.alpha = (50f * tone).toInt()
        c.drawPath(belly, paint)
        stroke(c, deflect(fascicles), 0xfff6dcd1, 1f + .6f * tone)
        stroke(c, deflect(intersections), 0xfff2dfcf, 2.5f)
        if (step != 4 || t < .92f) motion(c, step >= 3)

        leader(c, R.string.health_atlas_rectus_flexion_story_costal, 295f, 92f, 282f, 216f, 132f, boneInk, 116f)
        leader(c, R.string.health_atlas_rectus_flexion_story_lumbar, 63f, 183f, 99f, 145f, 210f, blue, 103f)
        leader(c, R.string.health_atlas_rectus_flexion_story_belly, 299f, 222f, 272f, 219f, 209f, rectusInk, 112f)
        leader(c, R.string.health_atlas_rectus_flexion_story_pubis, 276f, 303f, 242f, 209f, 260f, rectusInk, 118f)
        leader(c, R.string.health_atlas_rectus_flexion_story_pelvis, 77f, 326f, 109f, 138f, 274f, boneInk, 112f)
    }

    // Progressively turn the lumbar centerline and carry the rib cage with its tangent.
    // The front wall is inside this bend; below the pubic attachment the map is stationary.
    private fun point(x: Float, y: Float) {
        if (y >= 260f || bend < .0001f) {
            mapped[0] = x
            mapped[1] = y
            return
        }
        val rise = 260f - y
        val arc = minOf(104f, rise)
        val angle = bend * arc / 104f
        val radius = 104f / bend
        val side = x - 150f
        val upper = rise - arc
        val halfSin = sin(angle * .5f)
        mapped[0] = 150f + 2f * radius * halfSin * halfSin + upper * sin(angle) + side * cos(angle)
        mapped[1] = 260f - radius * sin(angle) - upper * cos(angle) + side * sin(angle)
    }

    private fun deflect(source: Path): Path {
        if (bend < .0001f) return source
        formed.rewind()
        measure.setPath(source, false)
        do {
            val length = measure.length
            val count = (length / 3f).toInt().coerceAtLeast(1)
            for (i in 0..count) {
                if (!measure.getPosTan(length * i / count, sample, null)) continue
                point(sample[0], sample[1])
                if (i == 0) formed.moveTo(mapped[0], mapped[1]) else formed.lineTo(mapped[0], mapped[1])
            }
            if (measure.isClosed) formed.close()
        } while (measure.nextContour())
        return formed
    }

    private fun motion(c: Canvas, returning: Boolean) {
        formed.rewind()
        formed.moveTo(233f, 46f)
        formed.quadTo(269f, 38f, 297f, 68f)
        stroke(c, formed, blue, 1.8f)
        if (returning) arrow(c, 243f, 44f, 233f, 46f, blue) else arrow(c, 290f, 61f, 297f, 68f, blue)
    }

    private fun leader(c: Canvas, @StringRes res: Int, x: Float, y: Float, elbow: Float,
        tx: Float, ty: Float, color: Long, width: Float) {
        point(tx, ty)
        val edge = if (ty > y) y + 6f else y - 17f
        line(c, x, edge, elbow, edge, color, 1.05f)
        line(c, elbow, edge, mapped[0], mapped[1], color, 1.05f)
        disc(c, mapped[0], mapped[1], 2.75f, color, cream)
        label(c, res, x, y, width)
    }

    private fun tissue(c: Canvas, path: Path, fill: Shader, border: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, border, 1.4f)
    }

    private fun lerp(a: Float, b: Float, t: Float) = a + (b - a) * t
}
