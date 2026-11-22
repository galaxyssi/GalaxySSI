package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import kotlin.math.abs

internal class HealthAtlasEndometriumStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.ENDOMETRIUM_RENEWAL) {
    private val path = Path()
    private val tissue = Path()
    private val profile = Path()
    private val channel = Path()
    private val measure = PathMeasure()
    private val glandSites = floatArrayOf(129f, 177f, 228f)
    private val lining = 0xff96576d
    private val leader = 0xff50686e
    private val cavity = 0xffe1eeea
    private val functional = shade(147f, BASAL, 0xfff9ddd6, 0xffedbec9)
    private val basal = shade(BASAL, MUSCLE, 0xffdda2b3, 0xffd490a6)
    private val muscle = shade(MUSCLE, 325f, 0xffd39083, 0xffe3ad91)
    private val uterus = Path().apply {
        moveTo(133f, 38f)
        cubicTo(146f, 39f, 148f, 27f, 180f, 27f)
        cubicTo(212f, 27f, 214f, 39f, 227f, 38f)
        lineTo(224f, 45f)
        cubicTo(209f, 43f, 212f, 62f, 199f, 77f)
        cubicTo(193f, 84f, 187f, 86f, 187f, 96f)
        quadTo(180f, 99f, 173f, 96f)
        cubicTo(173f, 86f, 167f, 84f, 161f, 77f)
        cubicTo(148f, 62f, 151f, 43f, 136f, 45f)
        close()
    }
    private val uterineCavity = Path().apply {
        moveTo(144f, 41f)
        quadTo(180f, 49f, 216f, 41f)
        cubicTo(199f, 51f, 189f, 67f, 181f, 89f)
        lineTo(179f, 89f)
        cubicTo(171f, 67f, 161f, 51f, 144f, 41f)
        close()
    }
    private val sectionGuide = track(Path().apply {
        moveTo(199f, 54f)
        lineTo(222f, 70f)
        lineTo(243f, 117f)
    })

    init { tag = "atlas-function-endometrium-renewal-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val top = when (step) {
            1 -> BASAL - (BASAL - 161f) * ramp(t, .05f, .91f)
            2 -> 161f - 12f * ramp(t, .02f, .75f)
            3 -> 149f
            4 -> BASAL
            else -> 161f
        }
        val secretory = when (step) {
            2 -> ramp(t, .08f, .78f)
            3 -> 1f
            else -> 0f
        }
        val erosion = if (step == 3) t else null
        drawContext(c, if (step == 0) ramp(t, .06f, .85f) else 1f)
        drawSection(c, top, secretory, erosion, step, t)
        if (step == 3) drawFragments(c, t)
        drawLabels(c, step)
    }

    private fun drawContext(c: Canvas, reveal: Float) {
        line(c, 120f, 39f, 135f, 42f, 0xffbf8a83, 4f)
        line(c, 225f, 42f, 240f, 39f, 0xffbf8a83, 4f)
        ink(0xffeab6a3); c.drawPath(uterus, paint)
        stroke(c, uterus, 0xff9d6268, 1.6f)
        ink(cavity); c.drawPath(uterineCavity, paint)
        stroke(c, uterineCavity, lining, 2.8f)
        path.rewind()
        sectionGuide.getSegment(0f, sectionGuide.length, path, true)
        stroke(c, path, 0xffa8bdb7, 1.2f)
        path.rewind()
        if (sectionGuide.getSegment(0f, sectionGuide.length * reveal, path, true)) {
            stroke(c, path, teal, 2.2f)
        }
        disc(c, 199f, 54f, 2.5f, teal, cream)
    }

    private fun drawSection(c: Canvas, top: Float, secretory: Float, erosion: Float?, step: Int, t: Float) {
        rounded(c, LEFT, 117f, RIGHT, 325f, 6f, cavity)
        ink(cream); paint.shader = muscle
        c.drawRoundRect(LEFT, 273f, RIGHT, 325f, 6f, 6f, paint)
        paint.shader = null
        for (i in 0..11) {
            val x = 112f + i % 4 * 34f
            val y = 289f + i / 4 * 13f + (i % 3) * 1.8f
            path.rewind()
            path.moveTo(x, y)
            path.cubicTo(x + 6f, y - 4f, x + 18f, y + 3f, x + 31f, y - 1f)
            stroke(c, path, 0xffaf736f, 1.5f)
        }
        ink(cream); paint.shader = basal
        c.drawRect(LEFT, BASAL, RIGHT, MUSCLE, paint)
        paint.shader = null

        profile.rewind()
        profile.moveTo(LEFT, surface(LEFT, top, erosion))
        for (i in 1..40) {
            val x = LEFT + (RIGHT - LEFT) * i / 40f
            profile.lineTo(x, surface(x, top, erosion))
        }
        tissue.set(profile)
        tissue.lineTo(RIGHT, MUSCLE)
        tissue.lineTo(LEFT, MUSCLE)
        tissue.close()
        if (top < BASAL) {
            // Fill only the functional layer; the basal tissue stays the same throughout.
            c.save()
            c.clipRect(LEFT, 117f, RIGHT, BASAL)
            ink(cream); paint.shader = functional
            c.drawPath(tissue, paint)
            paint.shader = null
            c.restore()
        }
        line(c, LEFT, BASAL, RIGHT, BASAL, 0xffbf869d, .9f)
        line(c, LEFT, MUSCLE, RIGHT, MUSCLE, 0xffa5707c, 1.1f)
        drawStroma(c, top, secretory, erosion)
        stroke(c, profile, if (erosion != null || step == 4) 0xffb7788a else lining, 3f)
        for ((i, x) in glandSites.withIndex()) {
            drawGland(c, x, surface(x, top, null), secretory, i, t, step == 2)
        }
        if (step == 4) drawRepair(c, t)
        if (erosion != null) {
            // Early repair can already be visible around an exposed gland opening.
            val radius = 8f * ramp(erosion, .56f, .96f)
            c.save()
            c.clipOutPath(tissue)
            repairEdge(c, glandSites[1], radius)
            c.restore()
        }
        ink(0xff9c8586, 1.2f)
        c.drawRoundRect(LEFT, 117f, RIGHT, 325f, 6f, 6f, paint)
    }

    private fun drawStroma(c: Canvas, top: Float, secretory: Float, erosion: Float?) {
        for (i in 0..40) {
            val x = 113f + (i * 31 % 133)
            val inBase = i % 3 == 0
            val y = if (inBase) 248f + (i * 13 % 29) else {
                val upper = surface(x, top, null)
                upper + (BASAL - upper) * (.13f + (i * 19 % 73) / 100f)
            }
            if (!inBase && (y < surface(x, top, erosion) + 3f || top == BASAL)) continue
            val rounding = if (inBase || i % 4 == 0) 0f else secretory
            val w = 3.2f - .5f * rounding
            val h = 1.1f + 1.1f * rounding
            c.save()
            c.rotate(if (i % 2 == 0) 27f else -21f, x, y)
            ink(if (inBase) 0xffac7087 else 0xffb87b92)
            c.drawOval(x - w, y - h, x + w, y + h, paint)
            c.restore()
        }
    }

    private fun drawGland(c: Canvas, x: Float, top: Float, bend: Float, i: Int, t: Float, secreting: Boolean) {
        val depth = BASAL - top
        val sway = (if (i == 1) -1f else 1f) * (2f + 10f * bend)
        channel.rewind()
        channel.moveTo(x, top - 4f)
        if (depth > 0f) {
            channel.cubicTo(
                x, top + depth * .14f, x + 1.45f * sway, top + depth * .16f, x + sway, top + depth * .32f,
            )
            channel.cubicTo(
                x + .55f * sway, top + depth * .52f, x - 1.7f * sway, top + depth * .47f,
                x - sway, top + depth * .69f,
            )
            channel.cubicTo(x - .65f * sway, top + depth * .84f, x + 7f * bend, top + depth * .93f, x, BASAL)
        }
        channel.cubicTo(x - 4f, BASAL + 13f, x + 8f, BASAL + 22f, x + 2f, BASAL + 28f)
        c.save()
        c.clipPath(tissue)
        val width = 10f + 3.4f * bend
        stroke(c, channel, lining, width + 2.4f)
        stroke(c, channel, 0xffefb1b9, width)
        stroke(c, channel, cream, width - 5.3f)
        if (secreting) {
            measure.setPath(channel, false)
            for (j in 0..2) {
                val travel = ramp(t, .14f + .12f * j + .05f * i, .84f + .06f * j)
                if (travel <= 0f) continue
                at(measure, (1f - travel) * (.62f - .17f * j)) { px, py ->
                    disc(c, px, py, 1.2f + 1.2f * ramp(t, .18f, .58f), 0xffad782f)
                }
            }
        }
        c.restore()
    }

    private fun drawFragments(c: Canvas, t: Float) {
        c.save()
        c.clipOutPath(tissue)
        for (i in 0..3) {
            val move = ramp(t, .06f + i * .14f, .6f + i * .12f)
            val opacity = ramp(move, 0f, .18f) * (1f - ramp(move, .64f, 1f))
            if (opacity <= 0f) continue
            val x = 190f - 21f * i + move * (10f - 5f * i)
            val y = 162f + i * 4f - 31f * move
            path.rewind()
            path.moveTo(x - 7f, y)
            path.quadTo(x - 2f, y - 7f, x + 6f, y - 3f)
            path.quadTo(x + 9f, y + 3f, x + 1f, y + 4f)
            path.quadTo(x - 5f, y + 6f, x - 7f, y)
            path.close()
            ink(0xffbb788c); paint.alpha = (215 * opacity).toInt()
            c.drawPath(path, paint)
        }
        c.restore()
    }

    private fun drawRepair(c: Canvas, t: Float) {
        val reach = 5f + 16f * ramp(t, .06f, .82f)
        line(c, LEFT + 2f, BASAL - 1f, LEFT + reach, BASAL - 1f, lining, 4.3f)
        for ((i, x) in glandSites.withIndex()) {
            val radius = 3f + 24f * ramp(t, .04f + i * .07f, .85f + i * .06f)
            repairEdge(c, x, radius)
        }
    }

    private fun repairEdge(c: Canvas, x: Float, radius: Float) {
        // Preserve a small opening where each gland meets the new epithelial surface.
        if (radius <= 3f) return
        line(c, maxOf(LEFT + 2f, x - radius), BASAL - 1f, x - 3f, BASAL - 1f, lining, 4.3f)
        line(c, x + 3f, BASAL - 1f, minOf(RIGHT - 2f, x + radius), BASAL - 1f, lining, 4.3f)
    }

    private fun surface(x: Float, top: Float, erosion: Float?): Float {
        val depth = BASAL - top
        val ripple = 1.6f * wave((x - LEFT) / 52f) * (depth / 95f)
        if (erosion == null) return top + ripple
        val lag = .11f + .24f * abs(wave((x - 182f) / 145f)) + .08f * wave((x - LEFT) / 45f)
        return BASAL - (depth - ripple) * (1f - ramp(erosion, lag, lag + .47f))
    }

    private fun drawLabels(c: Canvas, step: Int) {
        callout(c, R.string.health_atlas_endometrium_story_label_uterus, true, 49f, 153f, 52f)
        callout(c, R.string.health_atlas_endometrium_story_label_cavity, false, 132f, 244f, 132f)
        callout(c, R.string.health_atlas_endometrium_story_label_basal, true, 263f, 114f, 260f)
        callout(c, R.string.health_atlas_endometrium_story_label_muscle, true, 309f, 116f, 305f)
        if (step == 0) {
            callout(c, R.string.health_atlas_endometrium_story_label_functional, true, 201f, 115f, 203f)
        }
        if (step == 1 || step == 2) {
            callout(c, R.string.health_atlas_endometrium_story_label_stroma, false, 211f,
                245f, if (step == 1) 250f else 216f)
        }
        when (step) {
            3 -> callout(c, R.string.health_atlas_endometrium_story_label_gland_base, false, 263f, 230f, 268f)
            4 -> callout(c, R.string.health_atlas_endometrium_story_label_surface, false, 224f, 232f, 243f)
            else -> callout(c, R.string.health_atlas_endometrium_story_label_gland, false, 263f, 234f, 262f)
        }
    }

    private fun callout(c: Canvas, id: Int, left: Boolean, y: Float, anchorX: Float, anchorY: Float) {
        val x = if (left) 51f else 309f
        val start = if (left) 61f else 299f
        val elbow = if (left) 101f else 259f
        line(c, start, y + 5f, elbow, y + 5f, leader, 1.05f)
        line(c, elbow, y + 5f, anchorX, anchorY, leader, 1.05f)
        disc(c, anchorX, anchorY, 1.9f, leader, cream)
        label(c, id, x, y, 89f)
    }

    private fun ramp(t: Float, from: Float, to: Float): Float {
        val p = ((t - from) / (to - from)).coerceIn(0f, 1f)
        return p * p * (3f - 2f * p)
    }

    private companion object {
        const val LEFT = 106f
        const val RIGHT = 254f
        const val BASAL = 244f
        const val MUSCLE = 281f
    }
}
