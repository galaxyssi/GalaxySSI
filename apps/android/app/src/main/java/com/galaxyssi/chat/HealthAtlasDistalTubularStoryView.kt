package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import com.galaxyssi.chat.HealthAtlasDistalTubularCellAssignment as Lesson
import com.galaxyssi.chat.R.string

internal class HealthAtlasDistalTubularStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val membrane = 0xff915957
    private val quietGate = 0xffc1b1ad
    private val sodium = 0xff9c401e
    private val chloride = 0xff685084
    private val potassium = 0xff28684d
    private val water = 0xff1f6484
    private val cellFill = shade(APICAL_Y, BASAL_Y, 0xffffeddd, 0xffe6ad9f)
    private val neighborFill = shade(APICAL_Y, BASAL_Y, 0xfff2e0d3, 0xffd6a7a1)
    private val shell = Path().apply {
        moveTo(107f, APICAL_Y)
        quadTo(100f, 133f, 101f, 178f)
        quadTo(102f, 222f, 111f, BASAL_Y)
        lineTo(276f, BASAL_Y)
        quadTo(287f, 223f, 288f, 175f)
        quadTo(289f, 134f, 281f, APICAL_Y)
        close()
    }
    private val basalFolds = Path().apply {
        for (x in 176..217 step 10) {
            moveTo(x.toFloat(), BASAL_Y)
            cubicTo(x - 3f, 233f, x + 7f, 223f, x + 1f, 217f)
        }
        moveTo(272f, BASAL_Y)
        cubicTo(269f, 232f, 276f, 220f, 273f, 215f)
    }

    init { tag = Lesson.ART_TAG }

    override fun scene(c: Canvas, step: Int, t: Float) {
        lining(c)
        val whole = step == Lesson.NET_SALT
        val ncc = whole || step == Lesson.NCC_ENTRY
        val pump = whole || step == Lesson.PUMP_EXCHANGE
        val channel = whole || step == Lesson.CHLORIDE_EXIT
        gate(c, NCC_X, APICAL_Y, 54f, if (ncc) 0xffa16a54 else quietGate)
        gate(c, 145f, BASAL_Y, 66f, if (pump) 0xffa16a54 else quietGate)
        gate(c, CL_X, BASAL_Y, 36f, if (channel) chloride else quietGate)
        when (step) {
            Lesson.SIDES -> orient(c, t)
            Lesson.NCC_ENTRY -> nccEntry(c, t)
            Lesson.PUMP_EXCHANGE -> pumpExchange(c, t)
            Lesson.CHLORIDE_EXIT -> chlorideExit(c, t)
            Lesson.NET_SALT -> {
                waterAlongLumen(c, t, 26f, 89f)
                nccEntry(c, t)
                pumpExchange(c, (t * 1.35f - .30f).coerceIn(0f, 1f))
                chlorideExit(c, (t * 1.35f - .30f).coerceIn(0f, 1f))
            }
        }
    }

    private fun lining(c: Canvas) {
        rounded(c, 18f, 54f, 342f, 142f, 12f, 0xffd9eef1)
        rounded(c, 18f, 220f, 342f, 302f, 12f, 0xffebeee2)
        ink(cream); paint.shader = neighborFill
        c.drawRect(18f, APICAL_Y, 342f, BASAL_Y, paint)
        paint.shader = cellFill
        c.drawPath(shell, paint)
        paint.shader = null
        line(c, 18f, APICAL_Y, 342f, APICAL_Y, membrane, 2.6f)
        line(c, 18f, BASAL_Y, 342f, BASAL_Y, membrane, 2.6f)
        stroke(c, shell, membrane, 1.8f)
        stroke(c, basalFolds, 0xffbb7d77, 1.45f)
        oval(c, 49f, 166f, 80f, 190f, 0xffc793a1, 0xffa67688)
        oval(c, 302f, 173f, 327f, 194f, 0xffc793a1, 0xffa67688)
        oval(c, 202f, 177f, 237f, 202f, 0xffba8294, 0xff9b6378)
        oval(c, 207f, 182f, 221f, 190f, 0xffd2a6ae, 0xffd2a6ae)
        line(c, 100f, APICAL_Y + 4f, 112f, APICAL_Y + 4f, membrane, 3.6f)
        line(c, 277f, APICAL_Y + 4f, 289f, APICAL_Y + 4f, membrane, 3.6f)
        label(c, string.health_atlas_distal_exchange_lumen, 180f, 40f, 242f)
        label(c, string.health_atlas_distal_exchange_tissue, 180f, 323f, 246f)
    }

    private fun orient(c: Canvas, t: Float) {
        shaft(c, 35f, 323f, 79f, water)
        ion(c, "Na+", 52f + 234f * t, 68f, sodium)
        ion(c, "Cl-", 70f + 234f * t, 91f, chloride)
        ion(c, "H2O", 44f + 234f * t, 90f, water)
        label(c, string.health_atlas_distal_exchange_cell, 192f, 166f, 148f)
        label(c, string.health_atlas_distal_exchange_apical, 62f, 148f, 78f)
        label(c, string.health_atlas_distal_exchange_basolateral, 276f, 281f, 122f)
        line(c, 61f, 133f, 61f, APICAL_Y, membrane, 1.2f)
        line(c, 295f, 265f, 295f, BASAL_Y, membrane, 1.2f)
    }

    private fun nccEntry(c: Canvas, t: Float) {
        val y = transit(75f, 162f, t)
        verticalArrow(c, NCC_X, 66f, 166f, 0xff996455)
        line(c, NCC_X - 10f, y, NCC_X + 10f, y, 0xff996455, 2f)
        ion(c, "Na+", NCC_X - 13f, y, sodium)
        ion(c, "Cl-", NCC_X + 13f, y, chloride)
        label(c, string.health_atlas_distal_exchange_ncc_label, 263f, 114f, 73f)
        line(c, 217f, 118f, 235f, 113f, membrane, 1.1f)
    }

    private fun pumpExchange(c: Canvas, t: Float) {
        verticalArrow(c, 130f, 199f, 279f, sodium)
        verticalArrow(c, 161f, 280f, 200f, potassium)
        ion(c, "Na+", 130f, transit(205f, 270f, t), sodium)
        ion(c, "K+", 161f, transit(268f, 211f, t), potassium)
        label(c, string.health_atlas_distal_exchange_pump_label, 145f, 296f, 110f)
    }

    private fun chlorideExit(c: Canvas, t: Float) {
        verticalArrow(c, CL_X, 203f, 279f, chloride)
        ion(c, "Cl-", CL_X, transit(210f, 271f, t), chloride)
        label(c, string.health_atlas_distal_exchange_channel, CL_X, 296f, 91f)
    }

    private fun waterAlongLumen(c: Canvas, t: Float, from: Float, to: Float) {
        shaft(c, from + 5f, to + 18f, 79f, water)
        ion(c, "H2O", transit(from + 10f, to + 6f, t), 79f, water)
    }

    private fun gate(c: Canvas, x: Float, y: Float, w: Float, color: Long) {
        rounded(c, x - w / 2f, y - 8f, x + w / 2f, y + 8f, 5f, color)
        rounded(c, x - w / 2f + 4f, y - 5f, x + w / 2f - 4f, y + 5f, 3f, 0xfffff1df)
    }

    private fun ion(c: Canvas, symbol: String, x: Float, y: Float, color: Long) {
        rounded(c, x - 12f, y - 8f, x + 12f, y + 8f, 6f, color)
        ink(0xffffffff)
        paint.textSize = 10f
        c.drawText(symbol, x, y + 3.5f, paint)
    }

    private fun verticalArrow(c: Canvas, x: Float, from: Float, to: Float, color: Long) {
        val tail = if (to > from) to - 7f else to + 7f
        line(c, x, from, x, to, color, 1.5f)
        line(c, x - 4f, tail, x, to, color, 1.5f)
        line(c, x + 4f, tail, x, to, color, 1.5f)
    }

    private fun shaft(c: Canvas, from: Float, to: Float, y: Float, color: Long) {
        line(c, from, y, to, y, color, 1.5f)
        line(c, to - 7f, y - 4f, to, y, color, 1.5f)
        line(c, to - 7f, y + 4f, to, y, color, 1.5f)
    }

    private fun transit(from: Float, to: Float, t: Float): Float {
        val u = t.coerceIn(0f, 1f)
        return from + (to - from) * u * u * (3f - 2f * u)
    }

    private companion object {
        // Diagram coordinates and playback fractions, not transport measurements.
        const val APICAL_Y = 124f
        const val BASAL_Y = 242f
        const val NCC_X = 187f
        const val CL_X = 248f
    }
}
