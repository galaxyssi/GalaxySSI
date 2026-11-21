package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader
import androidx.annotation.StringRes

internal class HealthAtlasSebaceousStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.SEBUM_RELEASE) {
    private val dermis = shade(68f, 299f, 0xfff7d9ca, 0xffecc2bb)
    private val follicle = shade(75f, 290f, 0xfff1bab0, 0xffcf8994)
    private val gland = shade(79f, 288f, 0xffffead0, 0xffe2b99e)
    private val membrane = 0xff99696b
    private val guide = 0xff668181
    private val hairInk = 0xff875344
    private val lipid = 0xffd69742
    private val lipidInk = 0xff9b651e
    private val nucleus = 0xff9773a0

    private val skin = Path().apply {
        moveTo(15f, 69f)
        cubicTo(37f, 62f, 54f, 66f, 73f, 69f)
        cubicTo(95f, 73f, 127f, 64f, 151f, 68f)
        lineTo(151f, 283f)
        quadTo(151f, 295f, 139f, 295f)
        lineTo(27f, 295f)
        quadTo(15f, 295f, 15f, 283f)
        close()
    }
    private val skinSurface = Path().apply {
        moveTo(15f, 69f)
        cubicTo(37f, 62f, 54f, 66f, 73f, 69f)
        cubicTo(95f, 73f, 127f, 64f, 151f, 68f)
    }
    private val skinEdge = Path().apply {
        moveTo(15f, 86f)
        cubicTo(38f, 80f, 50f, 85f, 73f, 86f)
        cubicTo(95f, 93f, 125f, 80f, 151f, 85f)
    }
    private val follicleWall = Path().apply {
        moveTo(67f, 69f)
        cubicTo(70f, 99f, 83f, 108f, 82f, 154f)
        cubicTo(81f, 194f, 91f, 215f, 92f, 252f)
        cubicTo(90f, 271f, 102f, 285f, 115f, 280f)
        cubicTo(133f, 275f, 133f, 258f, 124f, 245f)
        cubicTo(108f, 208f, 116f, 170f, 104f, 139f)
        cubicTo(101f, 113f, 91f, 86f, 87f, 69f)
        close()
    }
    private val shaft = Path().apply {
        moveTo(55f, 39f)
        cubicTo(67f, 55f, 74f, 86f, 84f, 117f)
        cubicTo(98f, 147f, 90f, 192f, 105f, 233f)
        quadTo(106f, 248f, 112f, 265f)
    }
    private val locatorGland = Path().apply {
        moveTo(103f, 133f)
        cubicTo(104f, 121f, 115f, 117f, 122f, 121f)
        cubicTo(141f, 112f, 151f, 125f, 145f, 138f)
        cubicTo(159f, 145f, 149f, 161f, 138f, 160f)
        cubicTo(134f, 172f, 110f, 169f, 112f, 154f)
        quadTo(103f, 148f, 103f, 133f)
        close()
    }
    private val canal = Path().apply {
        moveTo(135f, 147f)
        quadTo(116f, 146f, 91f, 121f)
        cubicTo(87f, 101f, 77f, 84f, 74f, 68f)
        quadTo(63f, 64f, 36f, 67f)
    }
    private val canalTrack = track(canal)
    private val locatorCells = listOf(Point(126f, 130f), Point(138f, 139f), Point(126f, 154f))
    private val lobule = Path().apply {
        moveTo(180f, 182f)
        cubicTo(184f, 155f, 196f, 156f, 198f, 137f)
        cubicTo(186f, 105f, 213f, 78f, 242f, 92f)
        cubicTo(266f, 67f, 306f, 80f, 311f, 107f)
        cubicTo(338f, 116f, 350f, 144f, 337f, 166f)
        cubicTo(350f, 194f, 329f, 224f, 309f, 222f)
        cubicTo(297f, 254f, 257f, 258f, 239f, 236f)
        cubicTo(219f, 244f, 192f, 225f, 196f, 202f)
        quadTo(181f, 198f, 180f, 182f)
        close()
    }
    private val duct = Path().apply {
        moveTo(253f, 176f)
        cubicTo(229f, 169f, 218f, 191f, 197f, 185f)
        quadTo(182f, 182f, 168f, 170f)
    }
    private val ductTrack = track(duct)
    private val basal = listOf(
        Point(205f, 119f), Point(219f, 104f), Point(239f, 101f), Point(266f, 94f),
        Point(291f, 96f), Point(309f, 118f), Point(325f, 137f), Point(329f, 164f),
        Point(332f, 188f), Point(313f, 211f), Point(290f, 229f), Point(264f, 238f),
        Point(237f, 225f), Point(211f, 216f),
    )
    private val mature = listOf(
        Point(224f, 132f), Point(245f, 118f), Point(273f, 116f), Point(302f, 137f),
        Point(307f, 178f), Point(293f, 204f), Point(261f, 215f), Point(228f, 202f),
        Point(220f, 158f), Point(267f, 148f), Point(264f, 188f),
    )
    private val lipidLocations = listOf(Point(-.48f, -.09f), Point(.2f, -.47f), Point(.48f, .11f),
        Point(.01f, .34f), Point(-.45f, .42f), Point(.42f, .53f))

    init { tag = "atlas-function-sebaceous-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        label(c, R.string.health_atlas_sebaceous_skin_view, 83f, 26f, 145f)
        label(c, R.string.health_atlas_sebaceous_acinar_view, 259f, 26f, 168f)
        drawSkin(c, step, t)
        drawLobule(c, step, t)
        leader(c, R.string.health_atlas_sebaceous_young, 267f, 57f, 150f, 290f, 96f)
        leader(c, R.string.health_atlas_sebaceous_mature, 282f, 277f, 140f, 292f, 202f)
        leader(c, R.string.health_atlas_sebaceous_duct, 191f, 313f, 103f, 193f, 185f)
        disc(c, 213f, 337f, 3.3f, lipid, lipidInk)
        label(c, R.string.health_atlas_sebaceous_lipids, 266f, 341f, 92f)
    }

    private fun drawSkin(c: Canvas, step: Int, t: Float) {
        fill(c, skin, dermis, 0xffc29390)
        c.save()
        c.clipPath(skin)
        stroke(c, skinEdge, 0xffedaaa6, 21f)
        stroke(c, skinEdge, 0xffcf999c, 1.2f)
        stroke(c, skinSurface, 0xffd39389, 5f)
        c.restore()
        fill(c, follicleWall, follicle, membrane)
        stroke(c, shaft, hairInk, 9f)
        stroke(c, shaft, 0xffae7858, 3.2f)
        fill(c, locatorGland, gland, membrane)
        for ((x, y) in locatorCells) {
            disc(c, x, y, 5.3f, 0xffffe4ae, 0xffcf9c62)
            disc(c, x + 1f, y - 1f, 1.8f, lipid)
        }
        line(c, 111f, 140f, 94f, 124f, membrane, 7f)
        line(c, 111f, 140f, 94f, 124f, 0xffe6bb7f, 4.1f)
        line(c, 146f, 140f, 161f, 140f, guide, 1.1f)
        line(c, 161f, 140f, 175f, 166f, guide, 1.1f)
        leader(c, R.string.health_atlas_sebaceous_follicle, 56f, 268f, 84f, 93f, 227f)
        label(c, R.string.health_atlas_sebaceous_surface, 117f, 55f, 80f)
        line(c, 117f, 59f, 117f, 67f, guide, 1.1f)
        if (step == 0) {
            val target = 18f + 12f * t
            ink(teal, 1.8f)
            c.drawArc(130f - target, 140f - target, 130f + target, 140f + target, -100f,
                130f + t * 220f, false, paint)
        }
        if (step == 4) {
            for (i in 0..3) {
                val distance = ((t + i * .24f) % 1f) * .93f + .02f
                at(canalTrack, distance) { x, y -> disc(c, x, y, 3f, lipid, lipidInk) }
            }
        }
    }

    private fun drawLobule(c: Canvas, step: Int, t: Float) {
        fill(c, lobule, gland, membrane)
        stroke(c, duct, membrane, 15f)
        stroke(c, duct, 0xffeed39e, 11f)
        basal.forEachIndexed { index, point ->
            if (step == 1 && index == 3) return@forEachIndexed
            oval(c, point.x - 4.8f, point.y - 3.8f, point.x + 4.8f, point.y + 3.8f, 0xffd7a8b6, membrane)
            disc(c, point.x, point.y, 1.65f, nucleus)
        }
        mature.forEachIndexed { index, point ->
            if (step in 2..3 && index == 9) return@forEachIndexed
            cell(c, point.x, point.y, 8.1f + index % 3, .36f + index % 4 * .14f, 1f)
        }
        when (step) {
            1 -> {
                val spread = 1.2f + 6f * t
                cell(c, 266f - spread, 94f, 4.3f, 0f, 1f)
                cell(c, 266f + spread, 96f + 7f * t, 4.3f + t, .18f * t, 1f)
                ink(teal, 1.5f)
                c.drawOval(251f - t * 2f, 84f, 282f + t * 2f, 108f + t * 2f, paint)
            }
            2 -> {
                val focus = eased(t)
                cell(c, 266f + 6f * focus, 129f + 31f * focus, 7.4f + 6f * focus, focus, 1f)
            }
            3 -> {
                val open = eased(t)
                val x = 261f - 13f * open
                val y = 151f + 23f * open
                cell(c, x, y, 13.2f, .92f, 1f - open)
                for (index in 0..3) {
                    val f = (open * .74f + index * .072f).coerceAtMost(.95f)
                    at(ductTrack, f) { px, py -> disc(c, px, py, 2.4f + (index % 2) * .7f, lipid, lipidInk) }
                }
            }
            4 -> {
                for (i in 0..3) {
                    val f = ((t * .78f + i / 4f) % 1f) * .93f + .03f
                    at(ductTrack, f) { x, y -> disc(c, x, y, 3f, lipid, lipidInk) }
                }
            }
        }
    }

    private fun cell(c: Canvas, x: Float, y: Float, radius: Float, stored: Float, intact: Float) {
        if (intact <= 0f) return
        val alpha = (255f * intact).toLong()
        fun color(base: Long) = (base and 0xffffffL) or (alpha shl 24)
        oval(c, x - radius, y - radius * .92f, x + radius, y + radius * .92f,
            color(0xfff6d6ad), color(membrane))
        val nuclearRadius = radius * (.31f - .16f * stored)
        disc(c, x - radius * .2f, y + radius * .17f, nuclearRadius, color(nucleus))
        lipidLocations.forEachIndexed { index, offset ->
            val volume = (stored * 1.32f - index * .12f).coerceIn(0f, 1f)
            if (volume > 0f) {
                disc(c, x + radius * offset.x, y + radius * offset.y, radius * (.05f + .16f * volume),
                    color(lipid), color(0xffc0843f))
            }
        }
    }

    private fun leader(c: Canvas, @StringRes text: Int, x: Float, baseline: Float, width: Float,
        targetX: Float, targetY: Float) {
        val anchorY = baseline + if (targetY > baseline) 6f else -16f
        line(c, x, anchorY, targetX, targetY, guide, 1f)
        disc(c, targetX, targetY, 1.7f, guide, cream)
        label(c, text, x, baseline, width)
    }

    private fun fill(c: Canvas, shape: Path, shader: Shader, outline: Long) {
        ink(cream)
        paint.shader = shader
        c.drawPath(shape, paint)
        paint.shader = null
        stroke(c, shape, outline, 1.4f)
    }

    private fun eased(t: Float) = t * t * (3f - 2f * t)
    private data class Point(val x: Float, val y: Float)
}
