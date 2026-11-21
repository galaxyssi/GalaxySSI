package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas

internal enum class HealthAtlasImmuneLink(val owner: String, val portrait: Int, val relatedId: String,
    val relatedPortrait: Int, val scope: Int) {
    MONOCYTE("cell-monocyte", R.drawable.health_atlas_cell_monocyte, "cell-macrophage",
        R.drawable.health_atlas_cell_macrophage, R.string.health_atlas_monocyte_lesson_scope),
    DENDRITIC("cell-dendritic-cell", R.drawable.health_atlas_cell_dendritic, "cell-t-cell",
        R.drawable.health_atlas_cell_t, R.string.health_atlas_dendritic_lesson_scope),
    PLASMA("cell-plasma-cell", R.drawable.health_atlas_cell_plasma, "cell-b-cell",
        R.drawable.health_atlas_cell_b, R.string.health_atlas_plasma_lesson_scope);

    companion object {
        fun forId(id: String) = entries.firstOrNull { it.owner == id }
    }
}

internal class HealthAtlasImmuneLinkView(context: Context, val lesson: HealthAtlasImmuneLink,
    mechanism: HealthAtlasMechanism) : HealthAtlasCellSceneView(context, mechanism, R.string.health_atlas_granulocyte_stage) {
    private val cell = portrait(lesson.portrait)
    private val related = portrait(lesson.relatedPortrait)
    private val teal = 0xff38796b.toInt()
    private val gold = 0xffaf7136.toInt()
    private val vessel = 0xff64869d.toInt()
    private val blue = 0xff375b8a.toInt()

    init { tag = "atlas-immune-link-diagram" }

    override fun drawScene(canvas: Canvas, t: Float) {
        when (lesson) {
            HealthAtlasImmuneLink.MONOCYTE -> monocyte(canvas, t)
            HealthAtlasImmuneLink.DENDRITIC -> dendritic(canvas, t)
            HealthAtlasImmuneLink.PLASMA -> plasma(canvas, t)
        }
    }

    private fun monocyte(canvas: Canvas, t: Float) {
        if (stage == 3) {
            drawPortrait(canvas, cell, 91f, 101f, 155f)
            drawPortrait(canvas, related, 269f, 101f, 183f)
            arrow(canvas, 159f, 201f, 101f, t)
            return
        }
        fill(0x326c99b7)
        canvas.drawRoundRect(21f, 12f, 339f, 97f, 20f, 20f, paint)
        stroke(vessel, 4f)
        canvas.drawLine(34f, 15f, 325f, 15f, paint)
        canvas.drawLine(34f, 96f, 210f, 96f, paint)
        canvas.drawLine(277f, 96f, 325f, 96f, paint)
        if (stage > 0) {
            fill(gold)
            for (index in 0..3) canvas.drawCircle(243f + index * 9f, 123f + index * 14f, 2.3f + index * .7f, paint)
        }
        val x = when (stage) { 0 -> 64f + 85f * t; 1 -> 149f + 94f * t; else -> 243f }
        val y = if (stage < 2) 55f else 55f + 89f * t
        drawPortrait(canvas, cell, x, y, 103f, if (stage == 2) 1f - 1.1f * t * (1f - t) else 1f)
    }

    private fun dendritic(canvas: Canvas, t: Float) {
        if (stage < 2) {
            drawPortrait(canvas, cell, 166f, 103f, 202f)
            val target = if (stage == 0) 296f - 73f * t else 223f
            fill(gold)
            if (stage == 0) canvas.drawCircle(target, 108f, 6f, paint)
            else for (index in -1..1) canvas.drawCircle(target + index * 5.5f, 107f + index * (3f + 4f * t), 3.4f, paint)
            return
        }
        drawPortrait(canvas, cell, 113f, 108f, 170f)
        drawPortrait(canvas, related, 254f - 20f * t, 100f, 177f)
        stroke(if (stage == 2) gold else teal, 2.5f)
        canvas.drawCircle(179f, 96f, if (stage == 2) 5f + t * 3f else 7f, paint)
        if (stage == 3) {
            val move = 8f * t
            canvas.drawArc(183f + move, 69f, 215f + move, 126f, -58f, 116f, false, paint)
            canvas.drawArc(190f + move, 59f, 226f + move, 137f, -58f, 116f, false, paint)
        }
    }

    private fun plasma(canvas: Canvas, t: Float) {
        if (stage == 0) {
            drawPortrait(canvas, related, 89f, 101f, 168f)
            drawPortrait(canvas, cell, 272f, 101f, 164f)
            arrow(canvas, 151f, 205f, 101f, t)
            return
        }
        drawPortrait(canvas, cell, 119f, 101f, 202f)
        if (stage == 1) {
            stroke(teal, 2.8f)
            canvas.drawOval(158f - t * 3f, 81f - t * 3f, 176f + t * 3f, 124f + t * 3f, paint)
            return
        }
        if (stage == 2) {
            for (index in -1..1) antibody(canvas, 190f + t * (79f + index * 4f), 102f + index * (10f + t * 13f))
        } else {
            fill(0xffeddfb1.toInt())
            canvas.drawOval(252f, 62f, 313f, 143f, paint)
            stroke(gold, 2.5f)
            canvas.drawOval(252f, 62f, 313f, 143f, paint)
            antibody(canvas, 237f + 12f * t, 104f)
            antibody(canvas, 260f, 58f)
        }
    }

    private fun antibody(canvas: Canvas, x: Float, y: Float) {
        stroke(blue, 2.8f)
        canvas.drawLine(x - 7f, y, x, y, paint)
        canvas.drawLine(x, y, x + 7f, y - 7f, paint)
        canvas.drawLine(x, y, x + 7f, y + 7f, paint)
    }

    private fun arrow(canvas: Canvas, from: Float, to: Float, y: Float, progress: Float) {
        val head = from + (to - from) * (.25f + .75f * progress)
        stroke(teal, 2.7f)
        canvas.drawLine(from, y, head, y, paint)
        canvas.drawLine(head - 7f, y - 6f, head, y, paint)
        canvas.drawLine(head - 7f, y + 6f, head, y, paint)
    }
}
