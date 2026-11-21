package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import com.galaxyssi.chat.HealthAtlasEnteroendocrineSignalAssignment as Chapter
import com.galaxyssi.chat.R.string

internal class HealthAtlasEnteroendocrineSignalStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasCryptWallArt(context, story) {
    private val cueInk = 0xff267a7b
    private val hormoneInk = 0xff694776
    private val vesselInk = 0xffb16e78
    private val body = Path().apply {
        moveTo(-2.2f, .3f)
        quadTo(-2.4f, 5f, -5.4f, 9.6f)
        quadTo(-9.5f, 15.5f, -8.8f, 19.2f)
        quadTo(0f, 20f, 8.8f, 19.2f)
        quadTo(9.1f, 14f, 5.2f, 9.4f)
        quadTo(2.4f, 5f, 2.2f, .3f)
        close()
    }
    private val capillary = Path().apply {
        moveTo(-77f, 73f)
        cubicTo(-52f, 64f, -25f, 56f, 0f, 58f)
        cubicTo(27f, 60f, 54f, 80f, 82f, 83f)
    }
    private val blood = track(capillary)
    private val bloodLength = blood.length
    private val bloodPosition = FloatArray(2)
    private val delivery = Path().apply {
        moveTo(0f, 19.5f)
        cubicTo(-5.5f, 28f, 6f, 42f, 0f, 58f)
    }
    private val interstitialTrack = track(delivery)
    private val interstitialLength = interstitialTrack.length
    private val interstitialPosition = FloatArray(2)

    init { tag = Chapter.artTag }

    override fun scene(c: Canvas, step: Int, t: Float) {
        wall(c, endocrineSlot)
        val cell = center(endocrineSlot)
        atPose(c, cell) {
            vessel(c, step, t)
            filled(c, body, 0xffcea8d2)
            stroke(c, body, hormoneInk, 1.2f)
            flatOval(c, -2.65f, 6f, 2.65f, 12.5f, nucleusInk)
            line(c, -2.3f, -.5f, 2.3f, -.5f, cueInk, 1.8f)
            when (step) {
                Chapter.SENSE -> {
                    vesicles(c, 0f)
                    sense(c, t)
                }
                Chapter.BASAL_VESICLES -> vesicles(c, ease(t, .07f, .97f))
                Chapter.TISSUE_RELEASE -> release(c, t)
                Chapter.BLOOD_SIGNAL -> dot(c, -4.6f, 15.6f, 1.4f, hormoneInk)
            }
        }
        lumenLabel(c)
        leader(c, string.health_atlas_enteroendocrine_signal_cell, cell.xAt(-5f, 5f), cell.yAt(-5f, 5f),
            201f, 207f, 153f, 94f, hormoneInk)
        label(c, string.health_atlas_enteroendocrine_signal_capillary, 298f, 266f, 74f)
        when (step) {
            Chapter.SENSE -> label(c, string.health_atlas_enteroendocrine_signal_cue, 167f, 130f, 122f)
            Chapter.BASAL_VESICLES -> leader(c, string.health_atlas_enteroendocrine_signal_basal,
                cell.xAt(4f, 18f), cell.yAt(4f, 18f), 216f, 133f, 180f, 105f, hormoneInk)
            Chapter.TISSUE_RELEASE, Chapter.BLOOD_SIGNAL -> {
                dot(c, 263f, 288f, 2.9f, hormoneInk)
                label(c, string.health_atlas_enteroendocrine_signal_hormone, 297f, 292f, 59f)
            }
        }
    }

    private fun vessel(c: Canvas, step: Int, t: Float) {
        stroke(c, capillary, vesselInk, 17f)
        stroke(c, capillary, 0xfff4bdba, 13.5f)
        for (i in 0..4) {
            val p = if (step == Chapter.BLOOD_SIGNAL) (i * .19f + .43f * t) % 1f else .08f + i * .2f
            if (blood.getPosTan(bloodLength * p, bloodPosition, null)) {
                val x = bloodPosition[0]
                val y = bloodPosition[1]
                flatOval(c, x - 4.4f, y - 2.3f, x + 4.4f, y + 2.3f, 0xffce777e)
            }
        }
        if (step == Chapter.BLOOD_SIGNAL) {
            for (i in 0..2) {
                val p = ease(t, i * .12f, .76f + .12f * i)
                val distance = bloodLength * (.49f + .48f * p)
                if (blood.getPosTan(distance, bloodPosition, null)) {
                    dot(c, bloodPosition[0], bloodPosition[1] + (i - 1) * 2.2f, 2.25f, hormoneInk)
                }
            }
        }
    }

    private fun sense(c: Canvas, t: Float) {
        for (i in 0..2) {
            val p = ease(t, .12f * i, .76f + .11f * i)
            val x = (i - 1) * (25f - 19f * p)
            val y = mix(-72f - 5f * i, -5f, p)
            for (side in -1..1 step 2) {
                line(c, x - 3.2f, y, x, y + 3.2f * side, cueInk, 1.5f)
                line(c, x, y + 3.2f * side, x + 3.2f, y, cueInk, 1.5f)
            }
        }
        val arrived = ease(t, .64f, 1f)
        ring(c, 0f, 0f, 3f + 5f * arrived, alpha(cueInk, arrived * .85f), 1.65f)
    }

    private fun vesicles(c: Canvas, p: Float) {
        for (i in 0..3) {
            val x = (i - 1.5f) * 3.9f
            val y = mix(12.5f + (i % 2) * 2f, 17.2f - i * .35f, p)
            dot(c, x, y, 1.55f, hormoneInk)
        }
    }

    private fun release(c: Canvas, t: Float) {
        dot(c, -4.6f, 15.6f, 1.4f, hormoneInk)
        for (i in 0..2) {
            val p = ease(t, .14f * i, .66f + .16f * i)
            if (p == 0f) {
                dot(c, (i - 1) * 4f, 17f, 1.55f, hormoneInk)
            } else if (interstitialTrack.getPosTan(interstitialLength * p, interstitialPosition, null)) {
                dot(c, interstitialPosition[0] + (i - 1) * 3.1f * (1f - p),
                    interstitialPosition[1], 2f, hormoneInk)
            }
        }
    }
}
