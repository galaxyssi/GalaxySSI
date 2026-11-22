package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path

internal class HealthAtlasRedCellStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.RED_CELL_OXYGEN) {
    private val cellEdge = 0xffa35264
    private val wallEdge = 0xffb47983
    private val oxygenInk = 0xff1c746d
    private val richRed = shade(-14f, 14f, 0xfff6a49e, 0xffc65f6e)
    private val mutedRed = shade(-14f, 14f, 0xffe6a3ac, 0xffa96177)
    private val dimple = shade(-7f, 6f, 0xffc77884, 0xfff6b8ad)
    private val air = shade(66f, 156f, 0xfffcf6eb, 0xffffddd6)
    private val tissueFill = shade(246f, 307f, 0xffe6eee3, 0xffb6d6c6)
    private val alveolus = Path().apply {
        moveTo(324f, 78f)
        cubicTo(291f, 78f, 293f, 91f, 269f, 89f)
        cubicTo(242f, 87f, 241f, 66f, 207f, 69f)
        cubicTo(181f, 70f, 170f, 88f, 144f, 86f)
        cubicTo(119f, 84f, 100f, 64f, 72f, 79f)
        cubicTo(42f, 94f, 44f, 126f, 64f, 143f)
        cubicTo(74f, 151f, 89f, 155f, 110f, 155f)
        lineTo(324f, 155f)
    }

    init { tag = "atlas-function-red-cell-oxygen-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> closeUp(c, t)
            1 -> lung(c, t)
            2 -> transport(c, t)
            3 -> peripheral(c, t, false)
            else -> peripheral(c, t, true)
        }
    }

    private fun closeUp(c: Canvas, t: Float) {
        redCell(c, 112f, 168f, 3.35f, -11f + 24f * t)
        line(c, 144f, 166f, 220f, 166f, wallEdge, 1.3f)
        disc(c, 144f, 166f, 4.5f, cream, cellEdge)
        disc(c, 266f, 166f, 46f, 0xfffbe5e4, wallEdge)
        for (i in 0..3) {
            val x = 254f + 24f * (i % 2)
            val y = 154f + 24f * (i / 2)
            oval(c, x - 14f, y - 13f, x + 14f, y + 13f,
                if (i % 2 == 0) 0xffd7979f else 0xffc596ae, cellEdge)
            disc(c, x, y, 3f, cellEdge, cream)
        }
        label(c, R.string.health_atlas_red_cell_story_label_red_cell, 112f, 252f, 145f)
        label(c, R.string.health_atlas_red_cell_story_label_hemoglobin, 266f, 252f, 145f)
    }

    private fun lung(c: Canvas, t: Float) {
        ink(cream)
        paint.shader = air
        c.drawPath(alveolus, paint)
        paint.shader = null
        stroke(c, alveolus, wallEdge, 2.3f)
        vessel(c, 160f, 249f)
        val x = 141f + 49f * t
        redCell(c, 59f + 32f * t, 211f, .8f, -8f, 1, false)
        redCell(c, x, 208f, 1.05f, 0f)
        redCell(c, 255f + 35f * t, 211f, .88f, 8f, 3)
        for (i in 0..2) {
            val f = ease((t - .09f * i) / .77f)
            oxygen(c, mix(116f + 42f * i, x + 10f * (i - 1), f),
                mix(113f - 12f * (i % 2), 208f - 4f * (i % 2), f))
        }
        label(c, R.string.health_atlas_red_cell_story_label_alveolus, 180f, 53f, 200f)
        label(c, R.string.health_atlas_red_cell_story_label_oxygen, 270f, 112f, 94f)
        line(c, 180f, 251f, 180f, 274f, wallEdge, 1.2f)
        label(c, R.string.health_atlas_red_cell_story_label_lung_capillary, 180f, 296f, 200f)
    }

    private fun transport(c: Canvas, t: Float) {
        vessel(c, 105f, 248f, 11f)
        for (i in 0..2) {
            redCell(c, 65f + 85f * i + 55f * t, 159f + 33f * (i % 2), 1.28f,
                14f * wave(t * .6f + .3f * i), 3)
        }
        label(c, R.string.health_atlas_red_cell_story_label_vessel, 180f, 77f, 210f)
        arrow(c, 136f, 279f, 224f, 279f, teal)
        label(c, R.string.health_atlas_red_cell_story_label_flow, 180f, 305f, 190f)
    }

    private fun peripheral(c: Canvas, t: Float, diffuse: Boolean) {
        val flow = (t + if (diffuse) 1f else 0f) * .5f
        val exchangeX = 166f
        val x = exchangeX + 58f * (flow - .5f)
        vessel(c, 98f, 189f)
        redCell(c, 57f + 25f * flow, 145f, .88f, -9f, 3)
        redCell(c, x, 145f, 1.12f, 0f)
        redCell(c, 252f + 31f * flow, 145f, .84f, 10f, 1, false)
        oxygen(c, x, 137f)
        for (i in 0..2) tissueCell(c, 86f + 94f * i)
        for (i in 0..2) {
            val lane = i - 1
            val plasmaY = 173f + 3f * (i % 2)
            // The second chapter starts at the previous chapter's plasma positions.
            if (diffuse) {
                val f = ease((t - .09f * i) / .78f)
                oxygen(c, mix(exchangeX + 20f * lane, 86f + 94f * i, f * f), mix(plasmaY, 268f, f))
            } else {
                val f = ease((t - .09f * i) / .77f)
                oxygen(c, x + mix(10f * lane, 20f * lane, f), mix(146f + 4f * (i % 2), plasmaY, f))
            }
        }
        label(c, R.string.health_atlas_red_cell_story_label_tissue_capillary, 180f, 69f, 220f)
        label(c, R.string.health_atlas_red_cell_story_label_plasma, 69f, 123f, 76f)
        if (diffuse) label(c, R.string.health_atlas_red_cell_story_label_tissue_fluid, 267f, 216f, 124f)
        label(c, R.string.health_atlas_red_cell_story_label_tissue, 180f, 330f, 200f)
    }

    private fun vessel(c: Canvas, top: Float, bottom: Float, wall: Float = 5f) {
        ink(0xfffaeef1)
        c.drawRect(28f, top, 332f, bottom, paint)
        lining(c, top, 54f, wall)
        lining(c, bottom, 62f, wall)
    }

    private fun lining(c: Canvas, y: Float, firstX: Float, wall: Float) {
        line(c, 28f, y, 332f, y, wallEdge, wall + 2f)
        line(c, 28f, y, 332f, y, 0xffe9b5be, wall)
        for (i in 0..5) {
            val x = firstX + 50f * i
            oval(c, x - 8f, y - 2.8f, x + 8f, y + 2.8f, 0xffc993a4, wallEdge)
        }
    }

    private fun tissueCell(c: Canvas, x: Float) {
        oval(c, x - 41f, 247f, x + 41f, 304f, tissueFill, teal)
        oval(c, x - 13f, 275f, x + 13f, 291f, 0xffb4a3bf, violet)
        disc(c, x + 4f, 283f, 2.4f, violet)
        line(c, x - 30f, 273f, x - 23f, 263f, 0xfff7fbf4, 2f)
    }

    private fun redCell(c: Canvas, x: Float, y: Float, size: Float, angle: Float, bound: Int = 0, rich: Boolean = true) {
        c.save()
        c.translate(x, y)
        c.rotate(angle)
        c.scale(size, size)
        oval(c, -24f, -13f, 24f, 13f, if (rich) richRed else mutedRed, cellEdge)
        oval(c, -13f, -6f, 13f, 6f, dimple, 0xffcb8290)
        ink(0xfffbc5b9, 1.2f)
        c.drawArc(-20f, -10f, 20f, 10f, 196f, 123f, false, paint)
        for (i in 0 until bound) oxygen(c, if (bound == 1) 0f else 10f * (i - 1), -4f * (i % 2))
        c.restore()
    }

    private fun oxygen(c: Canvas, x: Float, y: Float) {
        disc(c, x - 2f, y, 2.9f, oxygenInk, cream)
        disc(c, x + 2f, y, 2.9f, oxygenInk, cream)
    }

    private fun mix(from: Float, to: Float, f: Float) = from + (to - from) * f

    private fun ease(value: Float): Float {
        val f = value.coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }
}
