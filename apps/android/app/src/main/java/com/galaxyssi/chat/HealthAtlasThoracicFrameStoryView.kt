package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Path
import android.graphics.Shader
import androidx.annotation.StringRes
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasThoracicFrameStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.THORACIC_FRAME) {
    private val curve = Path()
    private val detail = Path()
    private val dashes = DashPathEffect(floatArrayOf(4f, 4f), 0f)
    private val backdrop = shade(6f, 354f, 0xffeaf5f7, 0xfff9f7f2)
    private val sternumFill = shade(65f, 211f, 0xfffff0e3, 0xffceb5bd)
    private val lungFill = shade(75f, 255f, 0xffe3eff5, 0xffadc9db)
    private val diaphragmFill = shade(205f, 261f, 0xffe6cacd, 0xffb88395)
    private val guide = 0xff526c79
    private val reference = 0xff8197a4
    private val liftInk = 0xff8b536b
    private val widthInk = 0xff2c766e
    private val heightInk = 0xff466a9c
    private val ribEdge = 0xff81949b
    private val ribFill = 0xfff1f1e7
    private val cartilageEdge = 0xff658893
    private val cartilageFill = 0xffbddee3
    private val spineEdge = 0xff9ba8af
    private val lateral = floatArrayOf(53f, 74f, 91f, 104f, 112f, 117f, 118f, 116f, 111f, 103f, 94f, 83f)
    private val join = floatArrayOf(29f, 33f, 37f, 40f, 43f, 47f, 52f, 65f, 77f, 88f, 69f, 48f)

    init { tag = "atlas-function-thoracic-frame-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        ink(cream)
        paint.shader = backdrop
        c.drawRoundRect(0f, 0f, 360f, 360f, 8f, 8f, paint)
        paint.shader = null
        val eased = t * t * (3f - 2f * t)
        when (step) {
            0 -> overview(c, .38f * sin(PI * t).toFloat().let { it * it })
            1 -> pump(c, eased)
            2 -> bucket(c, eased)
            3 -> volume(c, eased, returning = false)
            else -> volume(c, 1f - eased, returning = true)
        }
    }

    private fun overview(c: Canvas, b: Float) {
        front(c, b)
        callout(c, R.string.health_atlas_thoracic_frame_story_art_sternum, 180f, 30f, 110f,
            180f, 70f - 6f * b)
        callout(c, R.string.health_atlas_thoracic_frame_story_art_ribs, 65f, 57f, 106f,
            180f - frontX(lateral[2], b), frontY(lateral[2], outerY(2), b))
        callout(c, R.string.health_atlas_thoracic_frame_story_art_cartilage, 260f, 302f, 151f,
            180f + frontX(join[8], b), frontY(join[8], joinY(8), b), below = true)
        label(c, R.string.health_atlas_thoracic_frame_story_art_front, 180f, 337f, 144f)
    }

    private fun pump(c: Canvas, b: Float) {
        profile(c, b, cutaway = false)
        callout(c, R.string.health_atlas_thoracic_frame_story_art_joint, 85f, 29f, 153f,
            rearX(2), rearY(2))
        callout(c, R.string.health_atlas_thoracic_frame_story_art_sternum, 265f, 29f, 115f,
            sideSternumX(77f, b), 77f - 9f * b)
        val x = sideSternumX(116f, b)
        val y = 116f - 9f * b
        arrow(c, x + 13f, y + 14f, x + 33f, y - 6f, liftInk)
        label(c, R.string.health_atlas_thoracic_frame_story_art_side, 180f, 284f, 120f)
        axis(c, 180f, 306f, 129f, 57f + 58f * b, liftInk,
            R.string.health_atlas_thoracic_frame_story_art_depth)
    }

    private fun bucket(c: Canvas, b: Float) {
        front(c, b, bucket = true)
        callout(c, R.string.health_atlas_thoracic_frame_story_art_sternum, 180f, 30f, 110f,
            180f, 70f - 6f * b)
        val radius = frontX(lateral[7], b)
        val y = frontY(lateral[7], outerY(7), b)
        for (side in -1..1 step 2) {
            arrow(c, 180f + side * (radius + 4f), y + 10f,
                180f + side * (radius + 25f), y - 9f, widthInk)
        }
        callout(c, R.string.health_atlas_thoracic_frame_story_art_side_ribs, 88f, 278f, 156f,
            180f - radius, y, below = true)
        axis(c, 180f, 306f, 150f, 70f + 64f * b, widthInk,
            R.string.health_atlas_thoracic_frame_story_art_width)
    }

    private fun volume(c: Canvas, b: Float, returning: Boolean) {
        if (returning) {
            profile(c, b, cutaway = true)
            callout(c, R.string.health_atlas_thoracic_frame_story_art_sternum, 265f, 29f, 115f,
                sideSternumX(77f, b), 77f - 9f * b)
            val x = sideSternumX(128f, b)
            arrow(c, x + 36f, 111f - 9f * b, x + 14f, 130f - 9f * b, liftInk)
            arrow(c, 210f, 246f + 17f * b, 210f, 227f + 17f * b, heightInk)
        } else {
            front(c, b, cutaway = true)
            callout(c, R.string.health_atlas_thoracic_frame_story_art_chest_space, 80f, 29f, 153f,
                150f - 4f * b, 115f)
            callout(c, R.string.health_atlas_thoracic_frame_story_art_sternum, 261f, 29f, 116f,
                180f, 73f - 6f * b)
            arrow(c, 180f, 253f + 13f * b, 180f, 270f + 13f * b, heightInk)
        }
        callout(c, R.string.health_atlas_thoracic_frame_story_art_diaphragm, 279f, 280f, 139f,
            if (returning) 178f else 228f + 5f * b,
            if (returning) 210f + 17f * b else 222f + 14f * b, below = true)
        axis(c, 66f, 306f, 87f, 39f + 35f * b, liftInk, R.string.health_atlas_thoracic_frame_story_art_depth)
        axis(c, 180f, 306f, 87f, 42f + 36f * b, widthInk, R.string.health_atlas_thoracic_frame_story_art_width)
        axis(c, 294f, 306f, 87f, 45f + 37f * b, heightInk, R.string.health_atlas_thoracic_frame_story_art_height)
    }

    private fun front(c: Canvas, b: Float, bucket: Boolean = false, cutaway: Boolean = false) {
        spine(c, 180f, 60f, 14.7f, side = false)
        for (side in -1..1 step 2) {
            c.save()
            c.translate(180f, 0f)
            c.scale(side.toFloat(), 1f)
            for (i in lateral.indices) {
                val x = lateral[i]
                val y = outerY(i)
                curve.rewind()
                curve.moveTo(12f, 62f + 14.7f * i)
                curve.cubicTo(x * .44f, y - 32f, frontX(x - 10f, b), frontY(x - 10f, y - 24f, b),
                    frontX(x, b), frontY(x, y, b))
                ribbon(c, curve, 0xffaebdc4, 0xffdce5e6, 5.8f)
            }
            if (cutaway) frontLung(c, b, heartSide = side > 0)
            if (bucket) {
                frontRib(7, 0f)
                dashed(c, curve, reference, 1.25f)
            }
            for (i in lateral.indices) {
                frontRib(i, b)
                val strong = bucket && i in 5..8
                ribbon(c, curve, if (strong) widthInk else if (cutaway) 0xffa3b3ba else ribEdge,
                    if (strong) 0xffd1e9dc else if (cutaway) 0xffe3edef else ribFill,
                    if (strong) 8.1f else if (i == 0 || i >= 10) 5.4f else 7.1f)
            }
            frontCartilages(c, b)
            c.restore()
        }
        c.save()
        c.translate(180f, -6f * b)
        frontSternum(c)
        c.restore()
    }

    private fun frontX(x: Float, b: Float) = x + (x - 13f).coerceAtLeast(0f) * .14f * b
    private fun frontY(x: Float, y: Float, b: Float) = y - (6f + (x - 13f).coerceAtLeast(0f) * .045f) * b
    private fun outerY(i: Int) = 84f + 15f * i
    private fun joinY(i: Int) = if (i < 10) 99f + 16.2f * i else 254f + 7f * (i - 10)
    private fun contactY(i: Int) = 85f + 17f * i

    private fun frontRib(i: Int, b: Float) {
        val x = lateral[i]
        val y = outerY(i)
        val tip = join[i]
        val tipY = joinY(i)
        val bend = x - (x - tip) * .52f
        curve.rewind()
        curve.moveTo(frontX(x, b), frontY(x, y, b))
        curve.cubicTo(frontX(x + 6f, b), frontY(x + 6f, y + 17f, b), frontX(bend, b),
            frontY(bend, tipY + 8f, b), frontX(tip, b), frontY(tip, tipY, b))
    }

    private fun frontCartilages(c: Canvas, b: Float) {
        for (i in 0..5) {
            val x = join[i]
            val y = joinY(i)
            curve.rewind()
            curve.moveTo(frontX(x, b), frontY(x, y, b))
            curve.quadTo(frontX(x - 11f, b), frontY(x - 11f, y - 3f, b), 8f, contactY(i) - 6f * b)
            ribbon(c, curve, cartilageEdge, cartilageFill, 5.8f)
        }
        // The lower cartilages continue along a shared costal margin rather than reaching the sternum separately.
        curve.rewind()
        curve.moveTo(8f, contactY(6) - 6f * b)
        curve.quadTo(frontX(32f, b), frontY(32f, 188f, b), frontX(join[6], b), frontY(join[6], joinY(6), b))
        for (i in 7..9) {
            val x = join[i]
            val y = joinY(i)
            curve.quadTo(frontX(x - 5f, b), frontY(x - 5f, y - 10f, b), frontX(x, b), frontY(x, y, b))
        }
        ribbon(c, curve, cartilageEdge, cartilageFill, 6.3f)
    }

    private fun frontSternum(c: Canvas) {
        curve.rewind()
        curve.moveTo(-18f, 67f)
        curve.quadTo(-15f, 59f, -7f, 65f)
        curve.quadTo(0f, 70f, 7f, 65f)
        curve.quadTo(15f, 59f, 18f, 67f)
        curve.cubicTo(21f, 75f, 12f, 84f, 10f, 99f)
        curve.cubicTo(9f, 130f, 14f, 163f, 10f, 186f)
        curve.quadTo(7f, 194f, 4f, 195f)
        curve.quadTo(5f, 204f, 0f, 210f)
        curve.quadTo(-6f, 204f, -4f, 195f)
        curve.quadTo(-10f, 193f, -11f, 182f)
        curve.cubicTo(-14f, 159f, -10f, 131f, -10f, 99f)
        curve.cubicTo(-11f, 87f, -21f, 76f, -18f, 67f)
        curve.close()
        washed(c, curve, sternumFill, liftInk)
        line(c, -10f, 99f, 10f, 99f, 0xffb791a0, 1.3f)
        line(c, -4f, 195f, 4f, 195f, 0xffb791a0, 1.1f)
        detail.rewind()
        detail.moveTo(-5f, 108f)
        detail.cubicTo(-3f, 132f, -7f, 158f, -4f, 180f)
        stroke(c, detail, 0xfff9e8e4, 2.6f)
    }

    private fun frontLung(c: Canvas, b: Float, heartSide: Boolean) {
        val reach = 105f + 12f * b
        val base = 239f + 5f * b
        val notch = if (heartSide) 11f else 0f
        curve.rewind()
        curve.moveTo(27f, 83f)
        curve.cubicTo(49f, 69f, 83f, 112f, 96f, 161f)
        curve.quadTo(reach + 4f, 194f, reach, base)
        curve.cubicTo(74f, base - 18f, 58f, 205f + 20f * b, 36f, 217f + 16f * b)
        curve.quadTo(22f, 223f + 16f * b, 9f, 234f + 9f * b)
        curve.cubicTo(10f + notch, 208f, 7f + notch, 187f, 17f + notch, 172f)
        curve.cubicTo(32f + notch, 149f, 12f, 114f, 27f, 83f)
        curve.close()
        washed(c, curve, lungFill, 0xff7f9fae)
        detail.rewind()
        detail.moveTo(31f, 139f)
        detail.quadTo(62f, 180f, reach - 3f, 194f + 5f * b)
        if (!heartSide) {
            detail.moveTo(45f, 160f)
            detail.quadTo(70f, 156f, 93f, 162f)
        }
        stroke(c, detail, 0xff8caeba, 1.2f)
        curve.rewind()
        curve.moveTo(9f, 234f + 9f * b)
        curve.quadTo(22f, 223f + 16f * b, 36f, 217f + 16f * b)
        curve.cubicTo(58f, 205f + 20f * b, 74f, base - 18f, reach, base)
        curve.cubicTo(78f, base - 8f, 61f, 216f + 20f * b, 39f, 228f + 16f * b)
        curve.quadTo(22f, 233f + 16f * b, 9f, 243f + 9f * b)
        curve.close()
        washed(c, curve, diaphragmFill, liftInk)
    }

    private fun rearX(i: Int) = 107f + .8f * i
    private fun rearY(i: Int) = 73f + 16f * i
    private fun sideSternumX(y: Float, b: Float) = 251f + (y - 90f) * .085f + 14f * b

    private fun profile(c: Canvas, b: Float, cutaway: Boolean) {
        spine(c, 95f, 67f, 16f, side = true)
        if (cutaway) {
            profileLung(c, b)
        } else {
            for (i in 1..3) {
                sideRib(i)
                dashed(c, curve, reference, 1.15f)
            }
            sideSternumPath(0f)
            dashed(c, curve, reference, 1.4f)
        }
        val angle = -8f * b
        val radians = angle * PI.toFloat() / 180f
        val cosine = cos(radians)
        val sine = sin(radians)
        // Rotate each bony rib around its stationary rear contact; cartilage bridges to the moving sternum.
        for (i in 6 downTo 0) {
            val strong = !cutaway && i in 1..3
            val px = rearX(i)
            val py = rearY(i)
            val endX = 207f + 4.5f * i
            val endY = 101f + 17f * i
            sideRib(i)
            c.save()
            c.rotate(angle, px, py)
            ribbon(c, curve, if (strong) liftInk else if (cutaway) 0xffa0b2b9 else ribEdge,
                if (strong) 0xfff4dad8 else if (cutaway) 0xffe1ebec else ribFill, if (strong) 8.8f else 6.9f)
            c.restore()
            val x = px + (endX - px) * cosine - (endY - py) * sine
            val y = py + (endX - px) * sine + (endY - py) * cosine
            val s = contactY(i)
            curve.rewind()
            curve.moveTo(x, y)
            curve.quadTo(x + 11f, y + 2f, sideSternumX(s, b) - 4f, s - 9f * b)
            ribbon(c, curve, cartilageEdge, cartilageFill, if (strong) 6.7f else 5.2f)
        }
        if (!cutaway) {
            for (i in 1..3) disc(c, rearX(i), rearY(i), 3.5f, 0xfff8e4df, liftInk)
        }
        sideSternumPath(b)
        c.save()
        c.translate(0f, -9f * b)
        washed(c, curve, sternumFill, liftInk)
        line(c, sideSternumX(100f, b) - 4f, 100f, sideSternumX(100f, b) + 5f, 100f, 0xffb791a0, 1.25f)
        line(c, sideSternumX(194f, b) - 4f, 194f, sideSternumX(194f, b) + 4f, 194f, 0xffb791a0, 1.1f)
        c.restore()
    }

    private fun sideRib(i: Int) {
        val x = rearX(i)
        val y = rearY(i)
        val endX = 207f + 4.5f * i
        val endY = 101f + 17f * i
        curve.rewind()
        curve.moveTo(x, y)
        curve.cubicTo(x + 22f, y - 8f, endX - 54f, endY + 9f, endX, endY)
    }

    private fun sideSternumPath(b: Float) {
        val x = 251f + 14f * b
        curve.rewind()
        curve.moveTo(x - 9f, 67f)
        curve.quadTo(x - 2f, 60f, x + 3f, 67f)
        curve.cubicTo(x + 5f, 88f, x + 13f, 148f, x + 15f, 190f)
        curve.quadTo(x + 13f, 200f, x + 18f, 208f)
        curve.quadTo(x + 10f, 207f, x + 7f, 196f)
        curve.cubicTo(x + 4f, 169f, x + 1f, 133f, x - 4f, 99f)
        curve.quadTo(x - 11f, 76f, x - 9f, 67f)
        curve.close()
    }

    private fun profileLung(c: Canvas, b: Float) {
        val front = 248f + 12f * b
        val dome = 210f + 17f * b
        curve.rewind()
        curve.moveTo(130f, 83f)
        curve.cubicTo(158f, 67f, front - 29f, 102f, front - 15f, 146f)
        curve.quadTo(front - 1f, 178f, front, 225f + 6f * b)
        curve.cubicTo(224f, dome + 5f, 182f, dome - 15f, 153f, dome + 4f)
        curve.quadTo(127f, dome + 14f, 115f, 251f + 2f * b)
        curve.cubicTo(103f, 215f, 112f, 105f, 130f, 83f)
        curve.close()
        washed(c, curve, lungFill, 0xff7f9fae)
        detail.rewind()
        detail.moveTo(130f, 148f)
        detail.quadTo(163f, 169f, 177f, dome - 5f)
        detail.moveTo(152f, 165f)
        detail.quadTo(191f, 158f, front - 11f, 172f)
        stroke(c, detail, 0xff8caeba, 1.2f)
        curve.rewind()
        curve.moveTo(front, 225f + 6f * b)
        curve.cubicTo(224f, dome + 5f, 182f, dome - 15f, 153f, dome + 4f)
        curve.quadTo(127f, dome + 14f, 115f, 251f + 2f * b)
        curve.lineTo(117f, 260f + 2f * b)
        curve.quadTo(138f, dome + 19f, 158f, dome + 12f)
        curve.cubicTo(188f, dome - 6f, 224f, dome + 15f, front, 234f + 6f * b)
        curve.close()
        washed(c, curve, diaphragmFill, liftInk)
    }

    private fun spine(c: Canvas, center: Float, top: Float, gap: Float, side: Boolean) {
        for (i in 0..11) {
            val x = center + if (side) 6f * sin(i * .26f) else 0f
            val y = top + gap * i
            val w = 8.5f + i * .29f
            rounded(c, x - w - 1f, y - 5.5f, x + w + 1f, y + 6.5f, 3.8f, spineEdge)
            rounded(c, x - w, y - 4.5f, x + w, y + 5.4f, 3.1f, 0xffe4e7e2)
            line(c, x - w + 3f, y - 2.4f, x + w - 3f, y - 2.4f, 0xfff9faf2, 1.35f)
            if (side) line(c, x - w, y, x - w - 9f, y + 5f, spineEdge, 2.8f)
        }
    }

    private fun ribbon(c: Canvas, path: Path, edge: Long, fill: Long, width: Float) {
        stroke(c, path, edge, width)
        stroke(c, path, fill, width - 2f)
        stroke(c, path, 0x88ffffff, (width - 3f) * .35f)
    }

    private fun washed(c: Canvas, path: Path, fill: Shader, edge: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, edge, 1.45f)
    }

    private fun dashed(c: Canvas, path: Path, tint: Long, width: Float) {
        paint.pathEffect = dashes
        stroke(c, path, tint, width)
        paint.pathEffect = null
    }

    private fun callout(c: Canvas, @StringRes id: Int, x: Float, y: Float, width: Float,
        targetX: Float, targetY: Float, below: Boolean = false) {
        line(c, x, y + if (below) -17f else 6f, targetX, targetY, guide, 1.05f)
        disc(c, targetX, targetY, 2.1f, guide, 0xfff4f7f3)
        label(c, id, x, y, width)
    }

    private fun axis(c: Canvas, x: Float, y: Float, trackWidth: Float, span: Float, tint: Long,
        @StringRes id: Int) {
        line(c, x - trackWidth / 2f, y, x + trackWidth / 2f, y, 0xffbccbcd, 1.4f)
        line(c, x - span / 2f, y, x + span / 2f, y, tint, 2.6f)
        for (side in -1..1 step 2) {
            val end = x + side * span / 2f
            line(c, end, y - 4f, end, y + 4f, tint, 2f)
        }
        label(c, id, x, y + 24f, 109f)
    }
}
