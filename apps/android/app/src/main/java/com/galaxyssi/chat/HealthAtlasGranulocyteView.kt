package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas

internal enum class HealthAtlasGranulocyte(val owner: String, val art: Int, val scope: Int) {
    NEUTROPHIL("cell-neutrophil", R.drawable.health_atlas_cell_neutrophil, R.string.health_atlas_neutrophil_scope),
    EOSINOPHIL("cell-eosinophil", R.drawable.health_atlas_cell_eosinophil, R.string.health_atlas_eosinophil_scope),
    BASOPHIL("cell-basophil", R.drawable.health_atlas_cell_basophil, R.string.health_atlas_basophil_scope);

    companion object {
        fun forId(id: String) = entries.firstOrNull { it.owner == id }
    }
}

internal class HealthAtlasGranulocyteView(context: Context, val lesson: HealthAtlasGranulocyte,
    stageTitles: List<String>) : HealthAtlasCellSceneView(context, stageTitles, R.string.health_atlas_granulocyte_stage) {
    constructor(context: Context, lesson: HealthAtlasGranulocyte, mechanism: HealthAtlasMechanism) :
        this(context, lesson, mechanism.stages)

    private val art = portrait(lesson.art)
    private val vessel = 0xff64869d.toInt()
    private val plum = 0xff654a7d.toInt()
    private val gold = 0xffab692d.toInt()
    private val coral = 0xffa75144.toInt()
    init { tag = "atlas-granulocyte-diagram" }

    override fun drawScene(canvas: Canvas, t: Float) {
        when (lesson) {
            HealthAtlasGranulocyte.NEUTROPHIL -> neutrophil(canvas, t)
            HealthAtlasGranulocyte.EOSINOPHIL -> eosinophil(canvas, t)
            HealthAtlasGranulocyte.BASOPHIL -> basophil(canvas, t)
        }
    }

    private fun cell(canvas: Canvas, x: Float, y: Float, size: Float, widthRatio: Float = 1f) =
        drawPortrait(canvas, art, x, y, size, widthRatio)

    private fun neutrophil(canvas: Canvas, t: Float) {
        if (stage < 2) {
            fill(0x346c99b7)
            canvas.drawRoundRect(18f, 15f, 342f, 96f, 18f, 18f, paint)
            stroke(vessel, 5f)
            canvas.drawLine(29f, 18f, 331f, 18f, paint)
            canvas.drawLine(29f, 95f, 146f, 95f, paint)
            canvas.drawLine(223f, 95f, 331f, 95f, paint)
            fill(gold)
            for (index in 0..4) canvas.drawCircle(186f + index * 15f, 129f + index * 8f, 2.5f + index * .65f, paint)
            if (stage == 0) cell(canvas, 76f + 109f * t, 57f, 126f)
            else cell(canvas, 185f, 57f + 79f * t, 126f, 1f - 1.1f * t * (1f - t))
            return
        }
        cell(canvas, 178f, 100f, 232f)
        val targetX = if (stage == 2) 271f - 56f * t else 215f
        stroke(plum, 2.8f)
        canvas.drawCircle(targetX, 104f, if (stage == 2) 11f + 5f * t else 16f, paint)
        fill(gold)
        if (stage == 2) canvas.drawRoundRect(targetX - 8f, 100f, targetX + 8f, 108f, 4f, 4f, paint)
        else for (index in -1..1) canvas.drawCircle(targetX + index * (5f + 2f * t),
            104f + index * 3f, 3.4f - t, paint)
    }

    private fun eosinophil(canvas: Canvas, t: Float) {
        val x = when (stage) {
            0 -> 94f + 54f * t
            1 -> 148f + 23f * t
            else -> 171f
        }
        cell(canvas, x, 101f, 205f)
        fill(0xffefc4a5.toInt())
        canvas.drawRoundRect(241f, 31f, 291f, 170f, 22f, 22f, paint)
        stroke(0xff99694d.toInt(), 2.8f)
        canvas.drawRoundRect(241f, 31f, 291f, 170f, 22f, 22f, paint)
        when (stage) {
            0 -> {
                fill(coral)
                for (index in 0..3) canvas.drawCircle(195f + index * 12f, 132f, 2.3f + index, paint)
            }
            1 -> {
                stroke(coral, 2.5f)
                canvas.drawCircle(242f, 101f, 5f + 8f * t, paint)
            }
            2 -> {
                fill(coral)
                for (index in -2..2) canvas.drawCircle(215f + 24f * t, 101f + index * (3f + 7f * t), 3.3f, paint)
            }
            3 -> {
                stroke(coral, 3f)
                for (index in -1..1) canvas.drawLine(242f, 101f + index * 17f, 247f + 8f * t, 96f + index * 17f, paint)
            }
        }
    }

    private fun basophil(canvas: Canvas, t: Float) {
        cell(canvas, 110f, 101f, 209f)
        val response = if (stage == 3) 9f * t else 0f
        fill(0xffd4e5eb.toInt())
        canvas.drawRoundRect(265f - response, 31f, 308f + response, 169f, 19f, 19f, paint)
        stroke(vessel, 3f)
        canvas.drawRoundRect(265f - response, 31f, 308f + response, 169f, 19f, 19f, paint)
        when (stage) {
            0 -> {
                stroke(gold, 2.6f)
                canvas.drawCircle(24f + 16f * t, 101f, 7f, paint)
            }
            1 -> {
                stroke(gold, 2.6f)
                canvas.drawCircle(157f, 94f, 8f + 5f * t, paint)
                canvas.drawCircle(153f, 125f, 6f + 4f * t, paint)
            }
            2 -> {
                fill(plum)
                for (index in -2..2) canvas.drawCircle(166f + t * 88f, 98f + index * (4f + 9f * t), 3.2f, paint)
            }
            3 -> {
                stroke(plum, 2.5f)
                canvas.drawArc(215f - t * 8f, 65f, 255f - t * 8f, 125f, -45f, 90f, false, paint)
            }
        }
    }
}
