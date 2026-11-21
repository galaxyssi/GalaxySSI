package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import com.galaxyssi.chat.HealthAtlasLangerhansSentinelAssignment.COMMUNICATION
import com.galaxyssi.chat.HealthAtlasLangerhansSentinelAssignment.PRESENTATION
import com.galaxyssi.chat.HealthAtlasLangerhansSentinelAssignment.SAMPLING
import com.galaxyssi.chat.R.string

internal class HealthAtlasLangerhansSentinelStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val sentinelFill = 0xff84bdb1
    private val sentinelEdge = 0xff246c66
    private val keratinFill = 0xffedb39e
    private val keratinLight = 0xfff3c8ae
    private val keratinEdge = 0xffad7172
    private val cellNucleus = 0xffbc8184
    private val epidermalBed = 0xfff8e6d1
    private val skinBed = 0xffeed0b9
    private val tCellFill = 0xffb6c7e5
    private val tCellEdge = 0xff4e638a
    private val cueFill = 0xfff7ce73
    private val cueEdge = 0xff905d2f
    private val guide = 0xff526064
    private val tip = Path()
    private val diamond = Path().apply {
        moveTo(0f, -1f)
        lineTo(1f, 0f)
        lineTo(0f, 1f)
        lineTo(-1f, 0f)
        close()
    }
    private val body = Path().apply {
        moveTo(-28f, 3f)
        cubicTo(-24f, -10f, -17f, -12f, -12f, -21f)
        cubicTo(-2f, -31f, 11f, -24f, 17f, -15f)
        cubicTo(25f, -11f, 27f, -1f, 28f, 7f)
        cubicTo(23f, 17f, 18f, 17f, 10f, 21f)
        cubicTo(-8f, 31f, -14f, 17f, -22f, 14f)
        quadTo(-29f, 11f, -28f, 3f)
        close()
    }
    private val tissueBranches = Path().apply {
        moveTo(-11f, 11f)
        cubicTo(-23f, 18f, -39f, 21f, -48f, 11f)
        quadTo(-53f, 7f, -60f, 10f)
        moveTo(-37f, 17f)
        quadTo(-32f, 25f, -24f, 35f)
        moveTo(14f, 14f)
        cubicTo(27f, 19f, 37f, 6f, 49f, 10f)
        quadTo(54f, 11f, 60f, 12f)
        moveTo(35f, 13f)
        quadTo(43f, 2f, 53f, 1f)
        moveTo(-7f, 16f)
        quadTo(-9f, 36f, 1f, 55f)
    }
    private val detailBranches = Path().apply {
        moveTo(-11f, 11f)
        cubicTo(-28f, 23f, -34f, 28f, -53f, 29f)
        quadTo(-62f, 30f, -69f, 40f)
        moveTo(-39f, 26f)
        quadTo(-49f, 18f, -64f, 20f)
        moveTo(-7f, 16f)
        quadTo(-9f, 36f, 1f, 55f)
    }
    private val displayBranches = Path().apply {
        moveTo(14f, 14f)
        cubicTo(28f, 19f, 38f, 35f, 52f, 39f)
        quadTo(58f, 41f, 66f, 39f)
        moveTo(36f, 28f)
        quadTo(50f, 25f, 59f, 16f)
    }
    private val keratinocyte = Path().apply {
        moveTo(-.95f, -.29f)
        quadTo(-.88f, -.88f, -.48f, -.95f)
        quadTo(-.06f, -1.05f, .55f, -.89f)
        quadTo(.95f, -.83f, .99f, -.36f)
        quadTo(1.06f, .2f, .79f, .66f)
        quadTo(.36f, 1.02f, -.14f, .99f)
        quadTo(-.81f, .91f, -.91f, .45f)
        quadTo(-1.04f, .13f, -.95f, -.29f)
        close()
    }

    init { tag = "atlas-function-langerhans-sentinel-art" }

    private enum class Portrait { TISSUE, DISPLAY, CONTACT }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            SAMPLING -> sampling(c, t)
            PRESENTATION -> presentation(c, t)
            COMMUNICATION -> communication(c, t)
            else -> location(c, t)
        }
    }

    private fun location(c: Canvas, t: Float) {
        rounded(c, 28f, 91f, 332f, 293f, 10f, epidermalBed)
        rounded(c, 28f, 265f, 332f, 293f, 8f, skinBed)
        for (row in 0..1) for (col in 0..5) {
            val x = 36f + 48f * col + 9f * row
            val y = 95f + 14f * row
            rounded(c, x, y, x + 43f, y + 10f, 4f, if (row == 0) 0xffd9a17f else keratinFill)
        }
        c.save()
        c.rotate(-24f, 193f, 207f)
        sentinel(c, 193f, 207f, .55f, .40f + .14f * wave(t))
        c.restore()
        for (row in 0..3) for (col in 0..5) {
            if (row == 2 && col == 3) continue
            val x = 52f + 47f * col + 12f * (row % 2)
            val y = 139f + 35f * row
            keratinocyte(c, x, y, 21f, 15f, (row + col) % 2 == 0)
        }
        line(c, 34f, 263f, 326f, 263f, keratinEdge, 1.4f)
        callout(c, string.health_atlas_langerhans_sentinel_art_surface, 180f, 65f, 170f, 181f, 95f)
        line(c, 25f, 95f, 25f, 263f, guide, 1.2f)
        line(c, 25f, 95f, 32f, 95f, guide, 1.2f)
        line(c, 25f, 263f, 32f, 263f, guide, 1.2f)
        callout(c, string.health_atlas_langerhans_sentinel_art_epidermis, 72f, 321f, 110f, 25f, 263f)
        callout(c, string.health_atlas_langerhans_sentinel_art_cell, 241f, 321f, 151f, 196f, 208f)
    }

    private fun sampling(c: Canvas, t: Float) {
        rounded(c, 28f, 71f, 332f, 292f, 10f, epidermalBed)
        for (i in 0..2) {
            val y = 107f + 72f * i
            val dx = 14f * (i % 2)
            keratinocyte(c, 100f - dx, y, 55f, 29f, i % 2 == 0)
            keratinocyte(c, 260f + dx, y, 49f, 29f, i % 2 != 0)
        }
        val reach = .5f + .5f * wave(t - .25f)
        sentinel(c, 180f, 208f, 1f, reach)
        sample(c, 193f, 114f, 4.5f)
        sample(c, 169f, 102f, 3f)
        if (reach > .68f) {
            ink(cueEdge, 1.2f); c.drawCircle(193f, 114f, 9f + 3f * reach, paint)
        }
        callout(c, string.health_atlas_langerhans_sentinel_art_sample, 180f, 46f, 185f, 193f, 107f)
        callout(c, string.health_atlas_langerhans_sentinel_art_keratinocyte, 86f, 320f, 134f, 98f, 254f)
        callout(c, string.health_atlas_langerhans_sentinel_art_branch, 269f, 320f, 119f, 240f, 220f)
    }

    private fun presentation(c: Canvas, t: Float) {
        rounded(c, 34f, 86f, 326f, 277f, 12f, 0xfff6f1dd)
        sentinel(c, 163f, 176f, 1.44f, .22f, Portrait.DISPLAY)
        sample(c, 184f, 163f, 4.2f)
        sample(c, 181f, 177f, 3.2f)
        display(c, 197f, 170f)
        display(c, 200f, 187f)
        val pulse = 1f + wave(t - .25f)
        ink(cueEdge, 1.6f); c.drawCircle(208f, 179f, 17f + 4f * pulse, paint)
        callout(c, string.health_atlas_langerhans_sentinel_art_sample, 92f, 64f, 144f, 180f, 160f)
        callout(c, string.health_atlas_langerhans_sentinel_art_display, 255f, 303f, 161f, 214f, 189f)
        label(c, string.health_atlas_langerhans_sentinel_art_cell, 92f, 303f, 139f)
    }

    private fun communication(c: Canvas, t: Float) {
        rounded(c, 29f, 88f, 331f, 278f, 12f, 0xfff6f1dd)
        sentinel(c, 123f, 177f, 1.46f, .20f, Portrait.CONTACT)
        display(c, 162f, 176f)
        val close = (t / .58f).coerceAtMost(1f)
        val x = 241f - 19f * close * close * (3f - 2f * close)
        oval(c, x - 46f, 136f, x + 42f, 218f, tCellFill, tCellEdge)
        oval(c, x - 24f, 150f, x + 23f, 199f, 0xff889fc8, tCellEdge)
        line(c, x - 45f, 176f, x - 49f, 176f, tCellEdge, 2.3f)
        line(c, x - 49f, 176f, x - 52f, 171f, tCellEdge, 1.7f)
        line(c, x - 49f, 176f, x - 52f, 181f, tCellEdge, 1.7f)
        if (close >= .86f) {
            val pulse = 1f + wave(t - .25f)
            ink(cueEdge, 1.6f); c.drawCircle(170f, 176f, 10f + 3f * pulse, paint)
        }
        callout(c, string.health_atlas_langerhans_sentinel_art_cell, 88f, 69f, 140f, 117f, 164f)
        callout(c, string.health_atlas_langerhans_sentinel_art_t_cell, 263f, 69f, 125f, x + 14f, 146f)
        callout(c, string.health_atlas_langerhans_sentinel_art_contact, 180f, 311f, 153f, 170f, 191f)
    }

    private fun sentinel(c: Canvas, x: Float, y: Float, scale: Float, reach: Float, portrait: Portrait = Portrait.TISSUE) {
        c.save()
        c.translate(x, y)
        c.scale(scale, scale)
        val inTissue = portrait == Portrait.TISSUE
        val length = if (inTissue) 74f else 52f
        tip.rewind()
        tip.moveTo(3f, -12f)
        tip.cubicTo(-7f, -33f, 15f, -48f, 12f, -length - 15f * reach)
        tip.moveTo(8f, -40f)
        tip.quadTo(-1f, -46f, -17f, 15f - length - 7f * reach)
        tip.moveTo(-14f, -8f)
        if (inTissue) {
            tip.cubicTo(-28f, -14f, -33f, -50f, -47f, -59f - 6f * reach)
            tip.moveTo(-30f, -36f)
            tip.quadTo(-35f, -39f, -40f, -49f)
        } else {
            tip.cubicTo(-38f, -10f, -31f, -33f, -58f, -39f - 6f * reach)
            tip.moveTo(-35f, -24f)
            tip.quadTo(-46f, -17f, -63f, -21f)
        }
        branch(c, if (inTissue) tissueBranches else detailBranches)
        if (portrait == Portrait.DISPLAY) branch(c, displayBranches)
        branch(c, tip)
        ink(sentinelFill); c.drawPath(body, paint)
        stroke(c, body, sentinelEdge, 1.5f)
        oval(c, -12f, -13f, 9f, 12f, 0xff498c84, sentinelEdge)
        c.restore()
    }

    private fun branch(c: Canvas, path: Path) {
        stroke(c, path, sentinelEdge, 7f)
        stroke(c, path, sentinelFill, 4.6f)
    }

    private fun keratinocyte(c: Canvas, x: Float, y: Float, rx: Float, ry: Float, light: Boolean) {
        c.save()
        c.translate(x, y)
        c.scale(rx, ry)
        ink(if (light) keratinLight else keratinFill); c.drawPath(keratinocyte, paint)
        stroke(c, keratinocyte, keratinEdge, 1.2f / rx)
        c.restore()
        oval(c, x - .2f * rx, y - .32f * ry, x + .24f * rx, y + .25f * ry, cellNucleus, keratinEdge)
    }

    private fun display(c: Canvas, x: Float, y: Float) {
        line(c, x, y, x + 4f, y, sentinelEdge, 2.4f)
        line(c, x + 4f, y - 3f, x + 4f, y + 3f, sentinelEdge, 1.8f)
        sample(c, x + 7f, y, 3.5f)
    }

    private fun sample(c: Canvas, x: Float, y: Float, size: Float) {
        c.save()
        c.translate(x, y)
        c.scale(size, size)
        ink(cueFill); c.drawPath(diamond, paint)
        stroke(c, diamond, cueEdge, 1.15f / size)
        c.restore()
    }

    private fun callout(c: Canvas, res: Int, x: Float, y: Float, width: Float, tipX: Float, tipY: Float) {
        val tail = if (y > tipY) y - 15f else y + 5f
        line(c, x, tail, tipX, tipY, guide, 1.1f)
        disc(c, tipX, tipY, 2.1f, cream, guide)
        label(c, res, x, y, width)
    }
}
