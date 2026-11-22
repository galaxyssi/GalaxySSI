package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader
import com.galaxyssi.chat.HealthAtlasScrotalHeatAssignment as Assignment
import com.galaxyssi.chat.R.string

internal class HealthAtlasScrotalHeatStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val sacTone = shade(111f, 294f, 0xffffefe0, 0xffefd4ca)
    private val cordTone = shade(66f, 160f, 0xffffeac5, 0xffe8bc9a)
    private val testisTone = shade(143f, 270f, 0xffffe3be, 0xffe8b497)
    private val vesselArtery = shade(80f, 285f, 0xffdf9a83, 0xffedc2aa)
    private val vesselVein = shade(80f, 285f, 0xffacafbd, 0xff88b6c6)
    private val sac = Path().apply {
        moveTo(80f, 113f)
        cubicTo(70f, 134f, 45f, 155f, 44f, 205f)
        cubicTo(39f, 260f, 87f, 290f, 131f, 280f)
        quadTo(155f, 276f, 176f, 275f)
        cubicTo(219f, 300f, 283f, 301f, 308f, 254f)
        cubicTo(336f, 206f, 307f, 154f, 280f, 120f)
        quadTo(257f, 112f, 231f, 120f)
        quadTo(178f, 130f, 129f, 113f)
        quadTo(103f, 104f, 80f, 113f)
        close()
    }
    private val dartos = Path().apply {
        moveTo(82f, 126f)
        cubicTo(69f, 151f, 50f, 182f, 55f, 220f)
        cubicTo(60f, 256f, 94f, 276f, 131f, 270f)
        quadTo(157f, 265f, 178f, 264f)
        cubicTo(219f, 287f, 274f, 289f, 298f, 250f)
        cubicTo(324f, 207f, 297f, 160f, 279f, 134f)
    }
    private val septum = Path().apply {
        moveTo(173f, 126f); cubicTo(165f, 171f, 187f, 218f, 178f, 264f)
    }
    private val cord = Path().apply {
        moveTo(77f, 69f)
        cubicTo(76f, 108f, 83f, 144f, 93f, 164f)
        lineTo(120f, 156f)
        cubicTo(109f, 134f, 108f, 98f, 112f, 69f)
        close()
    }
    private val cordCore = Path().apply {
        moveTo(86f, 74f); cubicTo(84f, 102f, 89f, 135f, 100f, 153f)
        moveTo(101f, 74f); cubicTo(96f, 102f, 101f, 128f, 110f, 148f)
    }
    private val tunica = Path().apply {
        // Open at the superior attachment instead of tracing a complete ring across the cord.
        moveTo(99f, 146f)
        cubicTo(73f, 151f, 66f, 187f, 70f, 218f)
        cubicTo(73f, 245f, 93f, 264f, 116f, 259f)
        cubicTo(144f, 253f, 157f, 217f, 149f, 189f)
        cubicTo(145f, 169f, 135f, 153f, 120f, 148f)
    }
    private val testis = Path().apply {
        moveTo(98f, 155f)
        cubicTo(78f, 160f, 74f, 191f, 79f, 217f)
        cubicTo(82f, 237f, 95f, 255f, 114f, 250f)
        cubicTo(136f, 245f, 148f, 215f, 141f, 191f)
        cubicTo(136f, 171f, 119f, 150f, 98f, 155f)
        close()
    }
    private val testisContour = Path().apply {
        moveTo(100f, 166f); cubicTo(90f, 169f, 86f, 188f, 88f, 202f)
        moveTo(124f, 223f); quadTo(119f, 237f, 106f, 239f)
    }
    private val artery = Path().apply {
        moveTo(112f, 74f)
        cubicTo(84f, 108f, 122f, 124f, 112f, 152f)
        cubicTo(93f, 185f, 120f, 206f, 113f, 232f)
        quadTo(107f, 262f, 113f, 286f)
    }
    private val vein = Path().apply {
        moveTo(243f, 286f)
        cubicTo(216f, 261f, 258f, 239f, 242f, 211f)
        cubicTo(221f, 185f, 255f, 163f, 243f, 135f)
        cubicTo(228f, 110f, 254f, 91f, 243f, 74f)
    }
    private val veinBranches = Path().apply {
        moveTo(241f, 278f); cubicTo(272f, 250f, 272f, 227f, 243f, 211f)
        cubicTo(284f, 190f, 223f, 160f, 243f, 135f)
        cubicTo(274f, 114f, 271f, 92f, 243f, 79f)
        moveTo(240f, 269f); cubicTo(203f, 238f, 210f, 221f, 236f, 199f)
        cubicTo(202f, 169f, 209f, 143f, 238f, 126f)
        cubicTo(207f, 108f, 219f, 95f, 242f, 81f)
    }
    private val arterialTrack = track(artery)
    private val venousTrack = track(vein)
    private val tracer = Path()

    init { tag = "atlas-function-scrotal-heat-exchange-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            Assignment.COMPARTMENTS -> section(c, t, coverings = false)
            Assignment.COVERINGS -> section(c, t, coverings = true)
            Assignment.EXCHANGE -> exchange(c, t)
        }
    }

    private fun section(c: Canvas, t: Float, coverings: Boolean) {
        val emphasis = 0.5f + 0.5f * wave(t)
        fill(c, sac, sacTone, 0xffa98089)
        if (coverings) stroke(c, dartos, 0xffedc5cf, 9f + 2f * emphasis)
        stroke(c, dartos, 0xffa36979, if (coverings) 4.4f else 3f)
        stroke(c, septum, 0xffba8995, 3.7f)
        repeat(2) { side ->
            c.save()
            if (side == 1) {
                c.translate(0f, 10f)
                c.scale(-1f, 1f, 180f, 0f)
            }
            fill(c, cord, cordTone, 0xffa48271)
            stroke(c, cordCore, 0xffad847a, 2.4f)
            if (!coverings) stroke(c, cordCore, 0xffffe2af, 0.8f + emphasis)
            if (coverings) stroke(c, tunica, 0xffbedfd7, 8f + 2f * emphasis)
            stroke(c, tunica, 0xff6a9993, 4.3f)
            stroke(c, tunica, 0xffe6f0e9, 1.8f)
            fill(c, testis, testisTone, 0xffb28570)
            stroke(c, testisContour, 0xffd5a487, 1.4f)
            c.restore()
        }
        if (coverings) {
            callout(c, string.health_atlas_scrotal_heat_dartos, 80f, 319f, 127f, 61f, 237f, above = false)
            callout(c, string.health_atlas_scrotal_heat_tunica, 271f, 329f, 132f, 289f, 231f, above = false)
            callout(c, string.health_atlas_scrotal_heat_septum, 179f, 92f, 131f, 173f, 146f)
        } else {
            callout(c, string.health_atlas_scrotal_heat_cord, 110f, 42f, 150f, 95f, 92f)
            callout(c, string.health_atlas_scrotal_heat_septum, 185f, 92f, 131f, 173f, 146f)
            label(c, string.health_atlas_scrotal_heat_testes, 180f, 326f, 130f)
            leader(c, 154f, 310f, 110f, 219f)
            leader(c, 206f, 310f, 250f, 229f)
        }
    }

    private fun exchange(c: Canvas, t: Float) {
        rounded(c, 83f, 64f, 278f, 296f, 28f, 0xfff7e6d8)
        shadedStroke(c, artery, vesselArtery, 0xff9f6359, 20f)
        shadedStroke(c, veinBranches, vesselVein, 0xff648998, 7f)
        shadedStroke(c, vein, vesselVein, 0xff597f93, 16f)
        pulse(c, arterialTrack, t, 0xffffe5c6)
        pulse(c, venousTrack, t, 0xffe8f7f5)
        arrow(c, 65f, 130f, 65f, 222f, coral)
        arrow(c, 296f, 222f, 296f, 130f, blue)
        // Gold marks heat moving across the gap; white tracers stay inside each vessel.
        for (i in 0..2) {
            val y = 130f + 54f * i
            val alpha = (170 + 85 * (0.5f + 0.5f * wave(t * 2f - i * .24f))).toLong()
            arrow(c, 139f, y, 194f, y, (alpha shl 24) or 0x0096652f)
        }
        label(c, string.health_atlas_scrotal_heat_heat_transfer, 169f, 181f, 83f)
        callout(c, string.health_atlas_scrotal_heat_artery, 91f, 43f, 136f, 112f, 74f)
        callout(c, string.health_atlas_scrotal_heat_plexus, 253f, 43f, 167f, 243f, 74f)
        label(c, string.health_atlas_scrotal_heat_to_testis, 104f, 327f, 143f)
        label(c, string.health_atlas_scrotal_heat_from_testis, 253f, 327f, 143f)
    }

    private fun pulse(c: Canvas, route: PathMeasure, t: Float, color: Long) {
        val head = t * (route.length + 22f)
        tracer.rewind()
        if (route.getSegment((head - 22f).coerceAtLeast(0f), head.coerceAtMost(route.length), tracer, true)) {
            stroke(c, tracer, color, 4.5f)
        }
    }

    private fun shadedStroke(c: Canvas, path: Path, tone: Shader, edge: Long, width: Float) {
        stroke(c, path, edge, width + 2.4f)
        ink(cream, width); paint.shader = tone; c.drawPath(path, paint); paint.shader = null
    }

    private fun fill(c: Canvas, path: Path, tone: Shader, edge: Long) {
        ink(cream); paint.shader = tone; c.drawPath(path, paint); paint.shader = null
        stroke(c, path, edge, 1.45f)
    }

    private fun callout(c: Canvas, id: Int, x: Float, y: Float, max: Float, a: Float, b: Float, above: Boolean = true) {
        leader(c, x, y + if (above) 5f else -15f, a, b)
        label(c, id, x, y, max)
    }

    private fun leader(c: Canvas, x: Float, y: Float, a: Float, b: Float) {
        line(c, x, y, a, b, 0xff776873, 1.1f)
        disc(c, a, b, 2f, violet, cream)
    }
}
