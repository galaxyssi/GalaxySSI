package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Rect
import android.graphics.Shader
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.pow
import kotlin.math.sin

internal class HealthAtlasErectorSupportStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.ERECTOR_SUPPORT) {
    private val posteriorPlate = checkNotNull(context.getDrawable(R.drawable.health_atlas_erector_spinae_plate))
        .apply { bounds = Rect(0, POSTERIOR_TOP, 360, POSTERIOR_TOP + 280) }
    private val outline = Path()
    private val spine = Path()
    private val nearBand = Path()
    private val farBand = Path()
    private val work = Path()
    private val measure = PathMeasure()
    private val boneEdge = 0xff7e9898
    private val farInk = 0xff896d91
    private val nearInk = 0xffa3667c
    private val contour = shade(62f, 292f, 0xffe8f3ef, 0xffcbdee0)
    private val bone = shade(218f, 296f, 0xfffbf3e3, 0xffbdcfc9)
    private val pelvis = Path().apply {
        moveTo(149f, 245f)
        cubicTo(162f, 224f, 195f, 222f, 222f, 232f)
        cubicTo(235f, 237f, 234f, 251f, 223f, 261f)
        quadTo(217f, 269f, 217f, 281f)
        quadTo(213f, 289f, 200f, 286f)
        quadTo(192f, 278f, 182f, 287f)
        quadTo(169f, 301f, 153f, 291f)
        quadTo(143f, 279f, 150f, 266f)
        close()
    }
    private val sacrum = Path().apply {
        moveTo(149f, 248f)
        quadTo(159f, 247f, 166f, 253f)
        quadTo(163f, 269f, 152f, 282f)
        quadTo(147f, 283f, 144f, 276f)
        quadTo(150f, 262f, 149f, 248f)
        close()
    }

    init { tag = "atlas-function-erector-support-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val ease = t * t * (3f - 2f * t)
        if (step == 0) {
            posterior(c, t)
            return
        }

        // The last two chapters deliberately share identical neutral geometry.
        val flexion = if (step == 1) 1f - ease else 0f
        if (step == 2) drawSupport(c)
        if (step == 3) drawLoad(c)
        drawTrunk(c, flexion)
        drawBands(c, step, flexion, ease)
        if (step == 1) {
            extensionArc(c, ease)
            key(c, R.string.health_atlas_erector_support_story_paired, 61f, 194f,
                spineX(185f, flexion) - 19f, 185f, nearInk, 105f)
            key(c, R.string.health_atlas_erector_support_story_fixed_pelvis, 203f, 329f,
                189f, 269f, boneEdge, 112f)
        } else {
            key(c, R.string.health_atlas_erector_support_story_neutral_curve, 195f, 329f,
                spineX(222f, 0f), 222f, blue, 138f, bendX = 242f)
        }
    }

    private fun posterior(c: Canvas, t: Float) {
        posteriorPlate.draw(c)
        label(c, R.string.health_atlas_erector_support_story_posterior, 180f, 35f, 178f)
        val emphasis = (1f + wave(t - .25f)) / 2f
        for (side in -1..1 step 2) {
            ink(nearInk, 1.25f)
            paint.alpha = (70f + 110f * emphasis).toInt()
            val x = 180f + side * 25f
            c.drawOval(x - 8f, 147f, x + 8f, 184f, paint)
        }
        key(c, R.string.health_atlas_erector_spinae_plate_spinalis, 61f, 89f,
            168f, 80f + POSTERIOR_TOP, farInk, 88f)
        key(c, R.string.health_atlas_erector_spinae_plate_longissimus, 302f, 119f,
            206f, 127f + POSTERIOR_TOP, nearInk, 94f)
        key(c, R.string.health_atlas_erector_spinae_plate_iliocostalis, 307f, 233f,
            223f, 154f + POSTERIOR_TOP, coral, 88f)
        key(c, R.string.health_atlas_erector_spinae_plate_origin, 169f, 328f,
            171f, 218f + POSTERIOR_TOP, boneEdge, 116f)
    }

    private fun drawSupport(c: Canvas) {
        rounded(c, 84f, 112f, 122f, 201f, 11f, 0xff8aaea9)
        rounded(c, 88f, 116f, 115f, 197f, 8f, 0xffc3dfd6)
        line(c, 92f, 198f, 92f, 267f, 0xff87a7a7, 4f)
        key(c, R.string.health_atlas_erector_support_story_contact, 59f, 98f, 107f, 131f, teal, 100f)
    }

    private fun drawLoad(c: Canvas) {
        line(c, 222f, 121f, 278f, 121f, blue, 2f)
        rounded(c, 262f, 87f, 295f, 120f, 5f, 0xff8eb2c3)
        rounded(c, 266f, 91f, 291f, 105f, 3f, 0xffc5dce4)
        arrow(c, 279f, 124f, 279f, 163f, blue)
        label(c, R.string.health_atlas_erector_support_story_external, 279f, 69f, 118f)
    }

    private fun drawTrunk(c: Canvas, flexion: Float) {
        outline.rewind()
        outline.moveTo(142f + shift(59f, flexion), 59f)
        outline.cubicTo(133f + shift(88f, flexion), 88f, 117f + shift(103f, flexion), 103f,
            116f + shift(139f, flexion), 139f)
        outline.cubicTo(112f + shift(189f, flexion), 189f, 141f + shift(212f, flexion), 212f, 130f, 251f)
        outline.quadTo(114f, 278f, 136f, 295f)
        outline.quadTo(181f, 310f, 229f, 293f)
        outline.cubicTo(242f, 281f, 223f, 247f, 225f + shift(214f, flexion), 214f)
        outline.cubicTo(240f + shift(185f, flexion), 185f, 238f + shift(140f, flexion), 140f,
            226f + shift(114f, flexion), 114f)
        outline.quadTo(210f + shift(82f, flexion), 82f, 181f + shift(54f, flexion), 54f)
        outline.quadTo(157f + shift(47f, flexion), 47f, 142f + shift(59f, flexion), 59f)
        outline.close()
        tissue(c, outline, contour, 0xff97b1b2)
        tissue(c, pelvis, bone, boneEdge)
        tissue(c, sacrum, bone, boneEdge)
        oval(c, 177f, 255f, 204f, 282f, 0xffc9d9d5, boneEdge)

        trace(spine, flexion, 0f, 72f, 252f)
        stroke(c, spine, boneEdge, 3f)
        for (y in 76..244 step 14) {
            val fy = y.toFloat()
            val x = spineX(fy, flexion)
            val tilt = atan2(spineX(fy + 1f, flexion) - x, 1f) * (-180f / PI.toFloat())
            c.save()
            c.rotate(tilt, x, fy)
            oval(c, x - 9f, fy - 5.6f, x + 11f, fy + 5.6f, 0xfff6f0df, boneEdge)
            line(c, x - 9f, fy, x - 15f, fy + 3f, boneEdge, 1.4f)
            c.restore()
        }
    }

    private fun drawBands(c: Canvas, step: Int, flexion: Float, ease: Float) {
        trace(farBand, flexion, -23f, 77f, 258f)
        trace(nearBand, flexion, -16f, 71f, 258f)
        val emphasis = when (step) {
            1 -> .42f + .58f * sin(PI.toFloat() * ease)
            3 -> .42f + .58f * ease
            else -> .25f + .12f * ease
        }
        band(c, farBand, farInk, 0xffd8c3d6, emphasis)
        band(c, nearBand, nearInk, 0xffe9bbc2, emphasis)
    }

    private fun band(c: Canvas, path: Path, edge: Long, fill: Long, emphasis: Float) {
        stroke(c, path, edge, 7.3f)
        stroke(c, path, fill, 5f)
        ink(edge, 2.8f)
        paint.alpha = (25f + 155f * emphasis).toInt()
        c.drawPath(path, paint)
    }

    private fun extensionArc(c: Canvas, ease: Float) {
        work.rewind()
        work.moveTo(207f, 52f)
        work.quadTo(181f, 27f, 139f, 50f)
        stroke(c, work, 0xff85a9b8, 1.3f)
        measure.setPath(work, false)
        at(measure, ease) { x, y -> disc(c, x, y, 3.3f, blue, cream) }
        arrow(c, 151f, 44f, 139f, 50f, blue)
    }

    private fun trace(path: Path, flexion: Float, offset: Float, top: Float, bottom: Float) {
        path.rewind()
        path.moveTo(spineX(top, flexion) + offset, top)
        for (i in 1..32) {
            val y = top + (bottom - top) * i / 32f
            path.lineTo(spineX(y, flexion) + offset * (1f - .3f * i / 32f), y)
        }
    }

    private fun spineX(y: Float, flexion: Float) =
        151f - 13f * sin((y - 69f) * (2f * PI.toFloat() / 198f)) + shift(y, flexion)

    private fun shift(y: Float, flexion: Float) =
        49f * flexion * ((250f - y) / 185f).coerceAtLeast(0f).pow(1.45f)

    private fun tissue(c: Canvas, path: Path, fill: Shader, border: Long) {
        ink(cream); paint.shader = fill; c.drawPath(path, paint); paint.shader = null
        stroke(c, path, border, 1.4f)
    }

    private fun key(c: Canvas, res: Int, x: Float, y: Float, tx: Float, ty: Float,
        color: Long, maxWidth: Float, bendX: Float = x) {
        val edge = if (ty > y) y + 6f else y - 15f
        if (bendX != x) line(c, x, edge, bendX, edge, color, 1.1f)
        line(c, bendX, edge, tx, ty, color, 1.1f)
        disc(c, tx, ty, 3f, color, cream)
        label(c, res, x, y, maxWidth)
    }

    private companion object {
        const val POSTERIOR_TOP = 42
    }
}
