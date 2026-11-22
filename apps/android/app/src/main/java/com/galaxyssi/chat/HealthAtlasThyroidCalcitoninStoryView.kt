package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import com.galaxyssi.chat.R.string
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasThyroidCalcitoninStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasEndocrineCellStoryView(context, story, HealthAtlasEndocrineCellAssignments.C_CELL) {
    private val calcitonin = 0xff396957
    private val mineral = 0xffa17127
    private val boneInk = 0xffa07b54
    private val cellEdge = 0xffa3616d
    private val resorption = Path()
    private val capillary = curve {
        moveTo(30f, 228f)
        cubicTo(104f, 199f, 239f, 271f, 330f, 227f)
    }
    private val capillaryTrack = track(capillary)
    private val bone = curve {
        moveTo(26f, 233f)
        cubicTo(68f, 228f, 91f, 235f, 112f, 236f)
        cubicTo(130f, 236f, 136f, 263f, 168f, 266f)
        cubicTo(208f, 273f, 221f, 250f, 235f, 238f)
        cubicTo(258f, 232f, 294f, 232f, 334f, 237f)
        lineTo(334f, 286f)
        quadTo(176f, 310f, 26f, 287f)
        close()
    }
    private val osteoclast = curve {
        moveTo(109f, 224f)
        cubicTo(108f, 197f, 126f, 175f, 147f, 182f)
        cubicTo(158f, 158f, 191f, 160f, 199f, 181f)
        cubicTo(223f, 172f, 241f, 196f, 235f, 226f)
        quadTo(220f, 231f, 210f, 247f)
        quadTo(180f, 268f, 151f, 247f)
        quadTo(131f, 226f, 109f, 224f)
        close()
    }
    private val boneIcon = curve {
        moveTo(53f, 181f)
        cubicTo(38f, 181f, 38f, 160f, 50f, 159f)
        quadTo(53f, 146f, 65f, 153f)
        lineTo(82f, 167f)
        quadTo(99f, 164f, 98f, 177f)
        quadTo(103f, 192f, 89f, 192f)
        quadTo(85f, 202f, 75f, 194f)
        lineTo(61f, 180f)
        close()
    }
    private val kidneyIcon = curve {
        moveTo(172f, 151f)
        cubicTo(197f, 147f, 211f, 175f, 188f, 178f)
        cubicTo(177f, 183f, 197f, 193f, 184f, 200f)
        cubicTo(155f, 215f, 145f, 165f, 172f, 151f)
        close()
    }
    private val gutIcon = curve {
        moveTo(266f, 153f)
        cubicTo(300f, 145f, 324f, 158f, 305f, 170f)
        cubicTo(290f, 179f, 258f, 168f, 259f, 183f)
        cubicTo(261f, 198f, 319f, 179f, 304f, 200f)
        quadTo(298f, 209f, 276f, 204f)
    }
    private val contextX = floatArrayOf(72f, 180f, 288f)

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> locate(c, t)
            1 -> release(c, t)
            2 -> mineralRelease(c, t)
            else -> mineralContext(c, t)
        }
    }

    private fun follicle(c: Canvas, x: Float, y: Float, r: Float) {
        disc(c, x, y, r, 0xffe4ada5, cellEdge)
        for (i in 0..17) {
            val a = i * .349066f
            disc(c, x + (r - 10f) * cos(a), y + (r - 10f) * sin(a), 2.7f, cellEdge)
        }
        disc(c, x, y, r - 18f, 0xffffdbb4, boneInk)
    }

    private fun locate(c: Canvas, t: Float) {
        follicle(c, 91f, 160f, 63f)
        follicle(c, 269f, 161f, 59f)
        oval(c, 151f, 152f, 191f, 180f, 0xffb2cdb5, calcitonin)
        disc(c, 172f, 166f, 5.5f, calcitonin)
        ink(calcitonin, 2f)
        c.drawArc(143f, 141f, 200f, 192f, -140f, 36f + 315f * t, false, paint)
        label(c, string.health_atlas_c_cell_art_c_cell, 180f, 86f, 160f)
        line(c, 175f, 96f, 172f, 137f, calcitonin, 1.2f)
        label(c, string.health_atlas_c_cell_art_lumen, 91f, 164f, 80f)
        label(c, string.health_atlas_c_cell_art_lumen, 269f, 165f, 77f)
        label(c, string.health_atlas_c_cell_art_follicles, 180f, 274f, 255f)
    }

    private fun release(c: Canvas, t: Float) {
        vessel(c, capillary, 26f)
        oval(c, 127f, 109f, 223f, 177f, 0xffb2cdb5, calcitonin)
        disc(c, 166f, 143f, 10f, calcitonin, cream)
        label(c, string.health_atlas_c_cell_art_c_cell, 175f, 91f, 166f)
        for (i in 0..3) {
            val f = (t * 1.37f - i * .17f).coerceIn(0f, 1f)
            diamond(c, 190f + i * 5f + 28f * f, 164f + 76f * f, 3.8f, calcitonin)
        }
        for (i in 0..3) {
            at(capillaryTrack, (.22f * t + i * .14f) % .63f) { x, y -> disc(c, x, y, 3f, mineral) }
        }
        label(c, string.health_atlas_c_cell_art_blood_calcium, 89f, 286f, 146f)
        label(c, string.health_atlas_c_cell_art_calcitonin, 267f, 286f, 146f)
        disc(c, 89f, 303f, 3.8f, mineral)
        diamond(c, 267f, 303f, 4.5f, calcitonin)
    }

    private fun mineralRelease(c: Canvas, t: Float) {
        ink(0xffeed2a7); c.drawPath(bone, paint)
        stroke(c, bone, boneInk, 1.6f)
        for (i in 0..10) {
            val x = 40f + i * 28f
            line(c, x, 279f, x + 8f, 275f, 0xffbd9563, 1.4f)
        }
        ink(0xffe1afbc); c.drawPath(osteoclast, paint)
        stroke(c, osteoclast, cellEdge, 1.6f)
        for (i in 0..3) disc(c, 133f + i * 25f, 209f - 14f * wave(i / 6f), 6f, cellEdge, cream)
        val ruffle = 10f - 6.6f * t
        resorption.rewind()
        resorption.moveTo(145f, 241f)
        for (i in 1..12) {
            val f = i / 12f
            resorption.lineTo(145f + 73f * f, 242f + 13f * sin(f * 3.14159f) + (i % 2) * ruffle)
        }
        stroke(c, resorption, cellEdge, 2.2f)
        for (i in 0..3) {
            val f = (.8f * t + i * .24f) % 1f
            disc(c, 150f + i * 17f, 266f - f * (27f - 14f * t), 2.1f, mineral)
        }
        val x = 65f + 51f * t
        diamond(c, x, 184f + 19f * t, 5.5f, calcitonin)
        label(c, string.health_atlas_c_cell_art_calcitonin, 78f, 146f, 135f)
        label(c, string.health_atlas_c_cell_art_osteoclast, 180f, 108f, 230f)
        label(c, string.health_atlas_c_cell_art_bone_surface, 180f, 326f, 252f)
    }

    private fun mineralContext(c: Canvas, t: Float) {
        label(c, string.health_atlas_c_cell_art_context_calcitonin, 180f, 73f, 296f)
        line(c, 72f, 93f, 72f, 139f, divider, 1.4f)
        diamond(c, 72f, 93f + 44f * t, 4.5f, calcitonin)
        ink(0xffeed2a7); c.drawPath(boneIcon, paint)
        stroke(c, boneIcon, boneInk, 1.4f)
        ink(0xffdeb6b8); c.drawPath(kidneyIcon, paint)
        stroke(c, kidneyIcon, cellEdge, 1.4f)
        stroke(c, gutIcon, boneInk, 11f)
        stroke(c, gutIcon, 0xffeed2a7, 7f)
        label(c, string.health_atlas_c_cell_art_bone_label, 72f, 232f, 95f)
        label(c, string.health_atlas_c_cell_art_kidney_label, 180f, 232f, 95f)
        label(c, string.health_atlas_c_cell_art_gut_label, 288f, 232f, 95f)
        line(c, 72f, 268f, 288f, 268f, divider, 1.4f)
        for (x in contextX) {
            line(c, x, 243f, x, 268f, divider, 1.4f)
            disc(c, x, 266f - 23f * t, 3.4f, blue)
        }
        label(c, string.health_atlas_c_cell_art_context_main, 180f, 307f, 296f)
    }
}
