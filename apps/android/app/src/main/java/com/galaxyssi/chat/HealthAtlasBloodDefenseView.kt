package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import kotlin.math.cos
import kotlin.math.sin

internal enum class HealthAtlasBloodDefense(val owner: String, val art: Int, val scope: Int,
    val relatedId: String? = null, val relatedArt: Int? = null) {
    T_CELL("cell-t-cell", R.drawable.health_atlas_cell_t, R.string.health_atlas_t_lesson_scope,
        "cell-dendritic-cell", R.drawable.health_atlas_cell_dendritic),
    B_CELL("cell-b-cell", R.drawable.health_atlas_cell_b, R.string.health_atlas_b_lesson_scope,
        "cell-plasma-cell", R.drawable.health_atlas_cell_plasma),
    NK_CELL("cell-natural-killer-cell", R.drawable.health_atlas_cell_nk, R.string.health_atlas_nk_lesson_scope),
    MEGAKARYOCYTE("cell-megakaryocyte", R.drawable.health_atlas_cell_megakaryocyte, R.string.health_atlas_mega_lesson_scope,
        "fragment-platelet", R.drawable.health_atlas_cell_platelet),
    PLATELET("fragment-platelet", R.drawable.health_atlas_cell_platelet, R.string.health_atlas_platelet_lesson_scope,
        "cell-megakaryocyte");

    companion object {
        fun forId(id: String) = entries.firstOrNull { it.owner == id }
    }
}

internal class HealthAtlasBloodDefenseView(context: Context, val lesson: HealthAtlasBloodDefense,
    stageTitles: List<String>) : HealthAtlasCellSceneView(context, stageTitles, R.string.health_atlas_granulocyte_stage) {
    constructor(context: Context, lesson: HealthAtlasBloodDefense, mechanism: HealthAtlasMechanism) :
        this(context, lesson, mechanism.stages)

    private val cell = portrait(lesson.art)
    private val related = lesson.relatedArt?.let(::portrait)
    private val helper = if (lesson == HealthAtlasBloodDefense.B_CELL)
        portrait(R.drawable.health_atlas_cell_t) else null
    private val vessel = 0xff6a869e.toInt()
    private val teal = 0xff347d6e.toInt()
    private val gold = 0xffaf7136.toInt()
    private val mauve = 0xff925571.toInt()

    init { tag = "atlas-blood-defense-diagram" }

    override fun drawScene(canvas: Canvas, t: Float) {
        when (lesson) {
            HealthAtlasBloodDefense.T_CELL, HealthAtlasBloodDefense.B_CELL -> adaptive(canvas, t)
            HealthAtlasBloodDefense.NK_CELL -> naturalKiller(canvas, t)
            HealthAtlasBloodDefense.MEGAKARYOCYTE -> megakaryocyte(canvas, t)
            HealthAtlasBloodDefense.PLATELET -> platelet(canvas, t)
        }
    }

    private fun adaptive(canvas: Canvas, t: Float) {
        val bCell = lesson == HealthAtlasBloodDefense.B_CELL
        when (stage) {
            0 -> {
                drawPortrait(canvas, cell, 94f, 102f, 163f)
                if (!bCell) drawPortrait(canvas, requireNotNull(related), 254f - 29f * t, 102f, 172f)
                fill(gold)
                canvas.drawCircle(if (bCell) 224f - t * 73f else 182f - t * 19f, 105f, 5f, paint)
            }
            1 -> {
                drawPortrait(canvas, cell, 94f, 102f, 162f)
                drawPortrait(canvas, requireNotNull(if (bCell) helper else related), 232f, 103f, 167f)
                stroke(teal, 2.7f)
                canvas.drawArc(154f + 9f * t, 75f, 193f + 9f * t, 130f, -56f, 112f, false, paint)
                canvas.drawArc(162f + 9f * t, 65f, 202f + 9f * t, 140f, -56f, 112f, false, paint)
            }
            2 -> {
                drawPortrait(canvas, cell, 180f, 106f, 125f)
                for (side in -1..1 step 2) {
                    drawPortrait(canvas, cell, 180f + side * (65f + 29f * t), 104f - 22f * t, 85f + 25f * t)
                }
            }
            3 -> {
                drawPortrait(canvas, cell, 79f, 103f, 138f)
                if (bCell) {
                    drawPortrait(canvas, requireNotNull(related), 259f, 55f, 113f)
                    drawPortrait(canvas, cell, 259f, 147f, 106f)
                } else {
                    ring(canvas, 259f, 55f, 21f, teal)
                    ring(canvas, 259f, 147f, 21f, mauve)
                    stroke(teal, 3f)
                    canvas.drawLine(249f, 55f, 269f, 55f, paint)
                    canvas.drawLine(259f, 45f, 259f, 65f, paint)
                    stroke(mauve, 3f)
                    canvas.drawLine(251f, 147f, 267f, 147f, paint)
                }
                stroke(teal, 2.7f)
                canvas.drawLine(137f, 102f, 175f, 102f, paint)
                canvas.drawLine(175f, 102f, 190f + 29f * t, 102f - 34f * t, paint)
                canvas.drawLine(175f, 102f, 190f + 29f * t, 102f + 34f * t, paint)
            }
        }
    }

    private fun naturalKiller(canvas: Canvas, t: Float) {
        drawPortrait(canvas, cell, if (stage == 0) 83f + 26f * t else 109f, 103f, 191f)
        val targetRadius = if (stage == 3) 48f - t * 16f else 48f
        fill(if (stage == 3) 0xffd0b8bd.toInt() else 0xffe2c7bd.toInt())
        canvas.drawCircle(248f, 103f, targetRadius, paint)
        ring(canvas, 248f, 103f, targetRadius, mauve)
        when (stage) {
            0 -> ring(canvas, 183f + 13f * t, 104f, 7f, gold)
            1 -> ring(canvas, 197f, 103f, 9f + 7f * t, gold)
            2 -> {
                fill(mauve)
                for (index in -2..2) canvas.drawCircle(167f + 58f * t, 104f + index * (4f + t * 5f), 3.5f, paint)
            }
            3 -> {
                fill(mauve)
                for (index in -1..1) canvas.drawCircle(248f + index * (8f + t * 11f),
                    103f + index * 7f, 4f - 2f * t, paint)
            }
        }
    }

    private fun megakaryocyte(canvas: Canvas, t: Float) {
        fill(0x346a9cba)
        canvas.drawRoundRect(252f, 19f, 329f, 181f, 19f, 19f, paint)
        stroke(vessel, 3.4f)
        canvas.drawLine(327f, 27f, 327f, 174f, paint)
        canvas.drawLine(252f, 27f, 252f, 73f, paint)
        canvas.drawLine(252f, 128f, 252f, 174f, paint)
        val size = when (stage) { 0 -> 112f + 34f * t; 1 -> 146f + 74f * t; else -> 220f }
        val position = if (stage == 2) 137f + 20f * t else if (stage == 3) 157f else 137f
        drawPortrait(canvas, cell, position, 102f, size)
        if (stage == 2) ring(canvas, 216f + t * 25f, 105f, 12f, teal)
        if (stage == 3) {
            for (index in -1..1) {
                drawPortrait(canvas, requireNotNull(related), 236f + (42f + index * 7f) * t,
                    104f + index * (8f + 35f * t), 42f)
            }
        }
    }

    private fun platelet(canvas: Canvas, t: Float) {
        fill(0xffecd1ce.toInt())
        canvas.drawRoundRect(26f, 139f, 137f, 166f, 12f, 12f, paint)
        canvas.drawRoundRect(225f, 139f, 334f, 166f, 12f, 12f, paint)
        fill(0xffd8adb3.toInt())
        canvas.drawRoundRect(128f, 148f, 234f, 168f, 7f, 7f, paint)
        stroke(mauve, 3.4f)
        canvas.drawLine(35f, 139f, 137f, 139f, paint)
        canvas.drawLine(225f, 139f, 325f, 139f, paint)
        if (stage == 0) {
            drawPortrait(canvas, cell, 181f, 75f + t * 48f, 101f)
            return
        }
        activePlatelet(canvas, 181f, 135f, 15f + 3f * t)
        for (side in -1..1 step 2) {
            val x = if (stage == 1) 181f + side * (100f - 65f * t) else 181f + side * (35f - 12f * t)
            val y = if (stage == 1) 65f + t * 62f else 128f + side * 5f
            activePlatelet(canvas, x, y, 13f)
        }
        if (stage == 3) {
            stroke(vessel, 2.6f)
            for (index in -1..1) canvas.drawLine(139f, 123f + index * 9f, 195f + 30f * t, 142f - index * 11f, paint)
        }
    }

    private fun activePlatelet(canvas: Canvas, x: Float, y: Float, radius: Float) {
        stroke(0xffb37b9e.toInt(), 3.8f)
        for (point in 0..5) {
            val angle = (point * 2 + 1) * Math.PI / 6
            val extent = radius * if (point % 2 == 0) 1.1f else .94f
            canvas.drawLine(x, y, x + extent * cos(angle).toFloat(), y + extent * sin(angle).toFloat(), paint)
        }
        drawPortrait(canvas, cell, x, y, radius * 3.75f)
    }

    private fun ring(canvas: Canvas, x: Float, y: Float, radius: Float, color: Int) {
        stroke(color, 2.7f)
        canvas.drawCircle(x, y, radius, paint)
    }
}
