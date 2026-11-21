package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import com.galaxyssi.chat.HealthAtlasIntestinalStemRenewalAssignment as Chapter
import com.galaxyssi.chat.R.string

internal class HealthAtlasIntestinalStemRenewalStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasCryptWallArt(context, story) {
    private val lineageInk = 0xff286b62
    private val baseFill = 0xff92c4a6
    private val daughterFill = 0xffb5d5aa
    private val matureFill = 0xffcfdf9f
    private val moving = Pose()

    init { tag = Chapter.artTag }

    override fun scene(c: Canvas, step: Int, t: Float) {
        wall(c, stemSlot)
        lumenLabel(c)
        val niche = center(stemSlot)
        val neighbor = center(panethSlot)
        atPose(c, neighbor) {
            panethBody(c, active = false)
            dot(c, -3.3f, 4.6f, 1.65f, 0xffa96253)
            dot(c, 1f, 5.4f, 1.65f, 0xffa96253)
            dot(c, 3.7f, 8f, 1.3f, 0xffa96253)
        }
        atPose(c, niche) {
            when (step) {
                Chapter.NICHE -> {
                    renewalCell(c, baseFill)
                    val junction = -cellSpan * .46f
                    line(c, junction, 2.2f, junction, mix(5.5f, 18.7f, ease(t)), lineageInk, 2.45f)
                }
                Chapter.DIVISION -> dividing(c, t)
                else -> renewalCell(c, baseFill)
            }
        }
        leader(c, string.health_atlas_intestinal_stem_renewal_cell, niche.xAt(0f, 16f), niche.yAt(0f, 16f),
            232f, 326f, 271f, 93f, lineageInk)
        when (step) {
            Chapter.NICHE -> leader(c, string.health_atlas_intestinal_stem_renewal_paneth,
                neighbor.xAt(-2f, 12f), neighbor.yAt(-2f, 12f), 114f, 319f, 71f, 99f, 0xffa96253)
            Chapter.DIVISION -> drawDaughter(c, 15.5f - .52f * (1f - ease(t, .55f, 1f)), ease(t, .55f, 1f))
            Chapter.UPWARD -> {
                advance(c, t)
                val shoulder = center(24)
                leader(c, string.health_atlas_intestinal_stem_renewal_toward_villus,
                    shoulder.xAt(0f, 3f), shoulder.yAt(0f, 3f), 216f, 58f, 172f, 115f, lineageInk)
            }
            Chapter.VILLUS_LINING -> {
                mature(c, t)
                val villus = center(lastVillusSlot)
                leader(c, string.health_atlas_intestinal_stem_renewal_lining,
                    villus.xAt(0f, 2f), villus.yAt(0f, 2f), 238f, 50f, 195f, 100f, lineageInk)
            }
        }
    }

    private fun cellBody(c: Canvas, fill: Long, half: Float) {
        rounded(c, -half, .6f, half, 19.5f, 3.1f, fill)
        ink(lineageInk, 1.1f)
        c.drawRoundRect(-half, .6f, half, 19.5f, 3.1f, 3.1f, paint)
    }

    private fun renewalCell(c: Canvas, fill: Long, brush: Float = 0f) {
        cellBody(c, fill, cellSpan * .43f)
        flatOval(c, -3.15f, 8.5f, 3.15f, 15.1f, lineageInk)
        if (brush > 0f) {
            line(c, -7.5f, 1f, 7.5f, 1f, lineageInk, 1.15f)
            for (i in -3..3) {
                val x = i * 2.25f
                line(c, x, .5f, x, .5f - brush * (3.5f + (i and 1)), lineageInk, 1.3f)
            }
        }
    }

    private fun dividing(c: Canvas, t: Float) {
        val split = ease(t, .08f, .65f)
        val retained = ease(t, .61f, .94f)
        cellBody(c, baseFill, cellSpan * (.43f + .06f * split * (1f - retained)))
        if (split == 0f) {
            flatOval(c, -3.15f, 8.5f, 3.15f, 15.1f, lineageInk)
        } else {
            val x = 3.8f * split
            val a = x * (1f - retained)
            val r = mix(1.9f, 3.1f, retained)
            flatOval(c, -a - r, 8.5f, -a + r, 15.1f, lineageInk)
            flatOval(c, x - 1.85f, 9.1f, x + 1.85f, 14.7f, alpha(lineageInk, 1f - retained))
            line(c, 0f, .7f, 0f, 7.5f * split, alpha(lineageInk, 1f - retained), 1.35f)
            line(c, 0f, 19.1f - 6.7f * split, 0f, 19.1f, alpha(lineageInk, 1f - retained), 1.35f)
        }
    }

    private fun drawDaughter(c: Canvas, slotPosition: Float, amount: Float) {
        if (amount <= 0f) return
        sample(slotPosition, moving)
        atPose(c, moving) {
            val s = .65f + .35f * amount
            c.scale(s, s, 0f, 10f)
            renewalCell(c, daughterFill)
        }
    }

    private fun advance(c: Canvas, t: Float) {
        // The cohort follows the apical curve as part of the lining, not in the lumen.
        for (i in 2 downTo 0) {
            val p = ease(t, i * .085f, .86f + i * .07f)
            val slot = mix(15.5f, 26.5f - i, p)
            val appear = if (i == 0) 1f else ease(t, .13f + .13f * i, .24f + .13f * i)
            drawDaughter(c, slot, appear)
        }
    }

    private fun mature(c: Canvas, t: Float) {
        for (i in 2 downTo 0) {
            val p = ease(t, .1f + i * .11f, .76f + i * .11f)
            sample(26.5f - i + ease(t) * .65f, moving)
            atPose(c, moving) { renewalCell(c, if (p > .52f) matureFill else daughterFill, p) }
        }
    }
}
