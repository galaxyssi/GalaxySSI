package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.RectF
import com.galaxyssi.chat.HealthAtlasThecaCooperationAssignment.ANDROGEN_SOURCE
import com.galaxyssi.chat.HealthAtlasThecaCooperationAssignment.FOLLICULAR_HANDOFF
import com.galaxyssi.chat.HealthAtlasThecaCooperationAssignment.GRANULOSA_CONVERSION
import com.galaxyssi.chat.HealthAtlasThecaCooperationAssignment.VASCULAR_LAYER
import com.galaxyssi.chat.R.string
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasThecaCooperationStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val centerX = 134f
    private val centerY = 160f
    private val externaInk = 0xff796071
    private val internaInk = 0xffa15d37
    private val basalInk = 0xff695957
    private val granulosaInk = 0xff3e776e
    private val vesselInk = 0xffa55369
    private val androgenInk = 0xff965412
    private val estradiolInk = 0xff135669

    // These radii, marker counts and chapter fractions are schematic teaching values.
    private val internaCells = ring(85f, 25)
    private val granulosaCells = ring(63f, 32)
    private val vascularArc = bounds(85f)
    private val focusArc = bounds(93f)
    private val boundaryArc = bounds(73f)
    private val sourceRoute = track(Path().apply {
        arcTo(vascularArc, -146f, 124f, true)
        quadTo(219f, 135f, 221f, 149f)
    })
    private val sourceTrace = Path()
    private val triangle = Path().apply {
        moveTo(0f, -5.3f)
        lineTo(4.8f, 3.7f)
        lineTo(-4.8f, 3.7f)
        close()
    }

    init { tag = "atlas-function-theca-cooperation-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        label(c, string.health_atlas_theca_cooperation_art_follicle, centerX, 31f, 215f)
        follicle(c)
        layerLabel(c, string.health_atlas_theca_cooperation_art_externa, 208f, 88f, 82f, externaInk)
        layerLabel(c, string.health_atlas_theca_cooperation_art_interna, 215f, 126f, 127f, internaInk)
        layerLabel(c, string.health_atlas_theca_cooperation_art_boundary, 197f, 197f, 205f, basalInk)
        layerLabel(c, string.health_atlas_theca_cooperation_art_granulosa, 172f, 211f, 251f, granulosaInk)

        val key = when (step) {
            VASCULAR_LAYER -> {
                ink(vesselInk, 2.5f)
                c.drawArc(focusArc, -162f, 26f + 116f * t, false, paint)
                string.health_atlas_theca_cooperation_art_vascular
            }
            ANDROGEN_SOURCE -> {
                androgenSource(c, t)
                string.health_atlas_theca_cooperation_art_androgen
            }
            FOLLICULAR_HANDOFF -> {
                handoff(c, t)
                string.health_atlas_theca_cooperation_art_handoff
            }
            GRANULOSA_CONVERSION -> {
                conversion(c, t)
                string.health_atlas_theca_cooperation_art_estradiol
            }
            else -> return
        }
        rounded(c, 32f, 296f, 328f, 324f, 7f, 0xfffbf8ee)
        label(c, key, 180f, 314f, 278f)
        label(c, string.health_atlas_gonadal_story_art_educational, 180f, 345f, 255f)
    }

    private fun follicle(c: Canvas) {
        disc(c, centerX, centerY, 109f, 0xffe3cbd2, externaInk)
        disc(c, centerX, centerY, 95f, 0xfff0cba6, internaInk)
        for (i in 0 until internaCells.size step 2) {
            disc(c, internaCells[i], internaCells[i + 1], 4.3f, 0xffc08062)
        }
        disc(c, centerX, centerY, 73f, 0xffb5d6c2, basalInk)
        disc(c, centerX, centerY, 55f, 0xffe5f5f0, granulosaInk)
        for (i in 0 until granulosaCells.size step 2) {
            disc(c, granulosaCells[i], granulosaCells[i + 1], 3.8f, 0xff619b8b)
        }
        // The oocyte sits in a small mound of granulosa cells at the antral margin.
        oval(c, 68f, 146f, 118f, 180f, 0xffa9ceba, granulosaInk)
        disc(c, 103f, 163f, 12f, 0xfff1d3bc, internaInk)
        disc(c, 103f, 163f, 4f, 0xffae7b78)
        vessel(c, -170f, 148f)
        vessel(c, 39f, 103f)
    }

    private fun vessel(c: Canvas, start: Float, sweep: Float) {
        ink(vesselInk, 6.3f)
        c.drawArc(vascularArc, start, sweep, false, paint)
        ink(0xfff4b9bd, 2.7f)
        c.drawArc(vascularArc, start, sweep, false, paint)
    }

    private fun layerLabel(c: Canvas, text: Int, x: Float, y: Float, baseline: Float, color: Long) {
        line(c, x, y, 245f, baseline - 4f, cream, 3.2f)
        line(c, x, y, 245f, baseline - 4f, color, 1.05f)
        disc(c, x, y, 2.6f, cream, color)
        label(c, text, 300f, baseline, 104f)
    }

    private fun androgenSource(c: Canvas, t: Float) {
        val progress = (t / .72f).coerceAtMost(1f)
        sourceTrace.rewind()
        if (sourceRoute.getSegment(0f, sourceRoute.length * progress, sourceTrace, true)) {
            stroke(c, sourceTrace, 0xff713751, 2.1f)
        }
        at(sourceRoute, progress) { x, y -> disc(c, x, y, 3.3f, cream, vesselInk) }
        if (t >= .6f) {
            val reveal = ((t - .6f) / .4f).coerceIn(0f, 1f)
            androgen(c, 221f, 157f, .35f + .65f * reveal)
        }
    }

    private fun handoff(c: Canvas, t: Float) {
        ink(basalInk, 2.7f)
        c.drawArc(boundaryArc, -12f, 24f, false, paint)
        line(c, 221f, 157f, 197f, 157f, cream, 2.4f)
        line(c, 221f, 157f, 197f, 157f, androgenInk, .9f)
        val eased = t * t * (3f - 2f * t)
        androgen(c, 221f - 24f * eased, 157f, 1f)
    }

    private fun conversion(c: Canvas, t: Float) {
        val crossing = ((t - .22f) / .56f).coerceIn(0f, 1f)
        if (crossing < 1f) androgen(c, 197f, 157f, 1f - crossing)
        if (crossing > 0f) {
            ink(estradiolInk, 1.45f)
            paint.alpha = (200f * (1f - crossing)).toInt()
            c.drawCircle(197f, 157f, 6f + 8f * crossing, paint)
            disc(c, 197f, 157f, 2f + 3.2f * crossing, cream, estradiolInk)
        }
    }

    private fun androgen(c: Canvas, x: Float, y: Float, scale: Float) {
        c.save()
        c.translate(x, y)
        c.scale(scale, scale)
        ink(androgenInk)
        c.drawPath(triangle, paint)
        stroke(c, triangle, cream, 1.1f)
        c.restore()
    }

    private fun bounds(radius: Float) =
        RectF(centerX - radius, centerY - radius, centerX + radius, centerY + radius)

    private fun ring(radius: Float, cells: Int) = FloatArray(cells * 2) { i ->
        val angle = (i / 2) * 2.0 * PI / cells
        if (i % 2 == 0) centerX + radius * cos(angle).toFloat() else centerY + radius * sin(angle).toFloat()
    }
}
