package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import com.galaxyssi.chat.HealthAtlasPanethBarrierAssignment as Chapter
import com.galaxyssi.chat.R.string

internal class HealthAtlasPanethBarrierStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasCryptWallArt(context, story) {
    private val cargoInk = 0xff9c4938
    private val cargoLight = 0xfffbc978
    private val granuleX = floatArrayOf(-3.5f, .2f, 3.9f, -.7f)
    private val granuleY = floatArrayOf(5.5f, 4.1f, 6.2f, 9f)

    init { tag = Chapter.artTag }

    override fun scene(c: Canvas, step: Int, t: Float) {
        wall(c, panethSlot)
        lumenLabel(c)
        val base = center(panethSlot)
        atPose(c, base) {
            panethBody(c, active = true)
            when (step) {
                Chapter.AT_BASE -> {
                    stored(c, 0f)
                    ring(c, 0f, 9f, 14f + 5f * t, alpha(cargoInk, .72f * (1f - t)), 1.7f)
                }
                Chapter.GRANULES -> stored(c, ease(t, .06f, .96f))
                Chapter.RELEASE -> release(c, t)
                Chapter.LOCAL_BARRIER -> spread(c, t)
            }
        }
        leader(c, string.health_atlas_paneth_barrier_cell, base.xAt(-5f, 14f), base.yAt(-5f, 14f),
            111f, 319f, 66f, 89f, cargoInk)
        when (step) {
            Chapter.GRANULES -> leader(c, string.health_atlas_paneth_barrier_apical, base.xAt(5f, 2f),
                base.yAt(5f, 2f), 124f, 251f, 166f, 98f, cargoInk)
            Chapter.RELEASE, Chapter.LOCAL_BARRIER -> label(c, string.health_atlas_paneth_barrier_peptides,
                167f, 154f, 119f)
        }
    }

    private fun stored(c: Canvas, towardApex: Float) {
        for (i in granuleX.indices) {
            val x = granuleX[i]
            val y = mix(granuleY[i], 2.2f + (i % 2) * 2.4f, towardApex)
            dot(c, x, y, 2.25f, cargoInk)
            dot(c, x - .35f, y - .45f, .9f, cargoLight)
        }
    }

    private fun release(c: Canvas, t: Float) {
        dot(c, -.9f, 8.8f, 1.7f, cargoInk)
        for (i in 0..2) {
            val p = ease(t, i * .14f, .76f + i * .095f)
            val mouth = granuleX[i]
            if (p < .28f) {
                dot(c, mouth, mix(2.2f + (i % 2) * 2.4f, .5f, p / .28f), 2.2f, cargoInk)
            } else {
                val released = (p - .28f) / .72f
                ring(c, mouth, .5f, 2.5f + released, alpha(cargoInk, 1f - released), 1.25f)
                peptide(c, mouth + (i - 1) * 9f * released, -2f - (20f + i * 8f) * released, 1f)
                peptide(c, mouth + (i - .8f) * 12f * released, -2f - (13f + i * 7f) * released, .83f)
            }
        }
    }

    private fun spread(c: Canvas, t: Float) {
        dot(c, -.9f, 8.8f, 1.7f, cargoInk)
        // The dispersal stays above the apical edge, in the crypt lumen.
        val p = ease(t)
        for (i in 0..10) {
            val offset = (i % 5 - 2).toFloat()
            val x = offset * (4f + 12f * p) + (i % 2) * 7f
            val y = -19f - i * 3.1f - (18f + (i % 3) * 8f) * p
            peptide(c, x, y, (.95f - .3f * p) * (if (i < 6) 1f else ease(t, .03f, .4f)))
        }
    }

    private fun peptide(c: Canvas, x: Float, y: Float, opacity: Float) {
        line(c, x - 1.5f, y + .8f, x + 1.5f, y - .8f, alpha(cargoInk, opacity), 2.65f)
    }
}
