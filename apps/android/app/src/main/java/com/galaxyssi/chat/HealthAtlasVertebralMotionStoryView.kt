package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Matrix
import android.graphics.Path
import android.graphics.Shader
import androidx.core.graphics.PathParser

internal class HealthAtlasVertebralMotionStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val edge = 0xff897468
    private val guide = 0xff506e78
    private val facetInk = 0xff34766e
    private val motionInk = 0xff7e526a
    private val bodyWash = shade(58f, 139f, 0xffffeed8, 0xffc9a68b)
    private val archWash = shade(42f, 159f, 0xfff1dcc4, 0xffb59683)
    private val discWash = shade(134f, 174f, 0xffd7edf0, 0xff85b1be)
    private val body = path("M73 63 Q117 56 163 62 Q172 63 174 70 L171 122 Q173 134 166 139 L73 139 Q63 136 64 126 L63 79 Q63 67 73 63 Z")
    private val arch = path("M168 84 C183 81 197 76 207 68 L213 53 Q215 44 220 46 L246 60 Q251 63 247 68 L240 75 Q246 80 257 81 L289 82 Q301 83 300 92 L295 103 Q289 109 276 108 L252 109 Q237 111 234 124 L247 150 Q251 156 245 158 Q240 158 234 155 L215 145 Q207 141 209 133 L209 122 Q208 109 197 109 Q183 109 170 116 Z")
    private val bodyLight = path("M70 80 Q71 69 81 68 Q119 64 161 69 M70 91 L71 124 Q71 132 77 133")
    private val bodyGrain = path("M81 78 Q89 90 82 106 T85 126 M104 76 Q112 88 104 106 T108 129 M128 76 Q137 90 129 109 T132 128 M151 76 Q160 89 151 108 T151 129")
    private val archLight = path("M177 91 Q197 89 212 75 Q222 71 234 79 Q252 90 286 89 M218 122 Q220 130 216 136")
    private val upperJoint = path("M216 145 Q232 152 244 157")
    private val lowerJoint = path("M219 46 L246 60")
    private val endplateTop = path("M73 139 L166 139")
    private val endplateBottom = path("M73 63 Q117 56 163 62")
    private val neutralEndplate = path("M61 139 L177 139")
    private val neutralJoint = path("M215 145 Q232 152 247 158")
    private val dash = DashPathEffect(floatArrayOf(3f, 4f), 0f)
    private val upper = Matrix()
    private val tracker = FloatArray(2)
    private val corners = FloatArray(4)
    private val discOutline = Path()
    private val lamella = Path()
    private val nucleus = Path()

    init { tag = "atlas-function-vertebral-motion-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val eased = t * t * (3f - 2f * t)
        val bend = when (step) {
            HealthAtlasAxialProtectionAssignment.Vertebral.FLEXION -> eased
            HealthAtlasAxialProtectionAssignment.Vertebral.EXTENSION -> 1f - 2f * eased
            else -> 0f
        }
        val angle = if (bend >= 0f) -6.5f * bend else -3f * bend
        val glide = if (bend >= 0f) -4f * bend else -2.2f * bend
        upper.setRotate(angle, 119f, 151f)
        upper.postTranslate(glide, 0f)
        c.save()
        c.translate(0f, 40f)
        segmentDisc(c)
        c.save()
        c.translate(0f, 108f)
        vertebra(c, isUpper = false)
        c.restore()
        c.save()
        c.concat(upper)
        vertebra(c, isUpper = true)
        c.restore()

        point(232f, 152f)
        val facetX = (tracker[0] + 232f) / 2f
        val facetY = (tracker[1] + 161f) / 2f
        if (step == HealthAtlasAxialProtectionAssignment.Vertebral.FIT) {
            val focus = (t * 3f).toInt().coerceAtMost(2)
            val intensity = (80L + 100f * (1f - kotlin.math.abs(2f * (t * 3f - focus) - 1f))).toLong()
            val tint = intensity shl 24 or 0x357d83
            val x = when (focus) { 0 -> 117f; 1 -> 121f; else -> facetX }
            val y = when (focus) { 0 -> 97f; 1 -> 151f; else -> facetY }
            ink(tint, 1.5f)
            c.drawCircle(x, y, if (focus == 0) 22f else 10f, paint)
        } else {
            paint.pathEffect = dash
            stroke(c, neutralEndplate, 0x9d616d78, 1.25f)
            stroke(c, neutralJoint, 0x9d616d78, 1.25f)
            paint.pathEffect = null
            if (bend > .12f) {
                arrow(c, 61f, 100f, 39f, 108f, motionInk)
                arrow(c, 271f, 157f, 262f, 136f, facetInk)
            } else if (bend < -.12f) {
                arrow(c, 39f, 108f, 61f, 100f, motionInk)
                arrow(c, 262f, 136f, 271f, 157f, facetInk)
            }
        }
        c.restore()

        label(c, R.string.health_atlas_vertebral_motion_art_anterior, 79f, 54f, 133f)
        label(c, R.string.health_atlas_vertebral_motion_art_posterior, 279f, 54f, 133f)
        point(114f, 96f)
        if (step == HealthAtlasAxialProtectionAssignment.Vertebral.FIT) {
            callout(c, R.string.health_atlas_vertebral_motion_art_body, 117f, 89f, 126f, tracker[0], tracker[1] + 40f, 96f)
        }
        callout(c, R.string.health_atlas_vertebral_motion_art_facet, 285f, 285f, 140f, facetX, facetY + 40f, 269f)
        val discX = (corners[0] + 73f) * .5f
        val discY = (corners[1] + 171f) * .5f
        line(c, 43f, 213f, 47f, 40f + discY, guide, 1f)
        callout(c, R.string.health_atlas_vertebral_motion_art_disc, 43f, 232f, 81f, discX, discY + 40f, 40f + discY, 47f)
        val pose = when {
            bend > .12f -> R.string.health_atlas_vertebral_motion_art_flexion
            bend < -.12f -> R.string.health_atlas_vertebral_motion_art_extension
            else -> R.string.health_atlas_vertebral_motion_art_neutral
        }
        label(c, pose, 180f, 328f, 204f)
    }

    private fun point(x: Float, y: Float) {
        tracker[0] = x
        tracker[1] = y
        upper.mapPoints(tracker)
    }

    private fun segmentDisc(c: Canvas) {
        // Attach the disc's upper edge to the rotating endplate. The lower edge stays seated.
        corners[0] = 73f
        corners[1] = 139f
        corners[2] = 166f
        corners[3] = 139f
        upper.mapPoints(corners)
        val (lx, ly, rx, ry) = corners
        discOutline.rewind()
        discOutline.moveTo(lx, ly)
        discOutline.lineTo(rx, ry)
        discOutline.quadTo(maxOf(rx, 163f) + 6f, (ry + 170f) / 2f, 163f, 170f)
        discOutline.quadTo(117f, 164f, 73f, 171f)
        discOutline.quadTo(minOf(lx, 73f) - 6f, (ly + 171f) / 2f, lx, ly)
        discOutline.close()
        wash(c, discOutline, discWash, 0xff577e88)
        c.save()
        c.clipPath(discOutline)
        val center = (ly + ry + 165f * 2f) / 4f
        nucleus.rewind()
        nucleus.moveTo(91f, center + 1f)
        nucleus.cubicTo(99f, center - 7f, 137f, center - 7f, 149f, center - 1f)
        nucleus.cubicTo(140f, center + 6f, 105f, center + 8f, 91f, center + 1f)
        ink(0xffd2eceb)
        c.drawPath(nucleus, paint)
        for (i in 1..3) {
            val f = i / 4f
            val y = ly + (171f - ly) * f
            val y2 = ry + (170f - ry) * f
            lamella.rewind()
            lamella.moveTo(lx + (73f - lx) * f - 4f, y)
            lamella.quadTo(85f, y + 2.2f, 93f + i * 2f, y - 1f)
            lamella.moveTo(rx + (163f - rx) * f + 4f, y2)
            lamella.quadTo(156f, y2 + 2.2f, 145f - i * 2f, y2 - 1f)
            stroke(c, lamella, 0xff6895a2, 1.25f)
        }
        c.restore()
    }

    private fun vertebra(c: Canvas, isUpper: Boolean) {
        wash(c, arch, archWash, edge)
        stroke(c, archLight, 0x96fff4e4, 2.8f)
        wash(c, body, bodyWash, edge)
        stroke(c, bodyLight, 0xfff8e9d9, 2.3f)
        stroke(c, bodyGrain, 0x53a37a65, 1.05f)
        stroke(c, if (isUpper) endplateTop else endplateBottom, edge, 1.9f)
        val surface = if (isUpper) upperJoint else lowerJoint
        stroke(c, surface, facetInk, 3.2f)
        stroke(c, surface, 0xffa4cbbd, 1.55f)
    }

    private fun callout(c: Canvas, id: Int, x: Float, y: Float, width: Float,
        tx: Float, ty: Float, fromY: Float, fromX: Float = x) {
        line(c, fromX, fromY, tx, ty, guide, 1f)
        disc(c, tx, ty, 2.3f, 0xfff8f7ec, guide)
        label(c, id, x, y, width)
    }

    private fun wash(c: Canvas, shape: Path, fill: Shader, edge: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(shape, paint)
        paint.shader = null
        stroke(c, shape, edge, 1.25f)
    }

    private fun path(data: String) = PathParser.createPathFromPathData(data)
}
