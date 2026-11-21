package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader
import androidx.annotation.StringRes

internal object HealthAtlasPinealMotion {
    fun zoom(t: Float) = ease(t, .04f, .9f)
    fun retinalSignal(t: Float, index: Int) =
        ease(t, .22f + .11f * index, .55f + .12f * index)
    fun relay(t: Float, index: Int) =
        ease(t, .03f + .22f * index, .24f + .22f * index)
    fun transmitter(t: Float, index: Int) = ease(t, .025f + .04f * index, .23f + .04f * index)
    fun synthesis(t: Float, index: Int) = ease(t, .29f + .21f * index, .49f + .21f * index)
    fun secretion(t: Float, index: Int) = ease(t, .71f + .052f * index, .89f + .052f * index)
    fun cycle(t: Float) = phase(t)
    fun melatonin(t: Float) = .08f + .82f * ease(t, .29f, .45f) * (1f - ease(t, .64f, .81f))

    private fun phase(t: Float) = if (t.isFinite()) t.coerceIn(0f, 1f) else 0f

    private fun ease(t: Float, start: Float, end: Float): Float {
        val f = ((phase(t) - start) / (end - start)).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }
}

internal class HealthAtlasPinealStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.PINEAL_DARK_SIGNAL) {
    private val pinealPlate = requireNotNull(context.getDrawable(R.drawable.health_atlas_pineal_plate)).apply {
        setBounds(0, 0, 360, 280)
    }
    private val page = shade(0f, 360f, 0xfff8fbfc, 0xffe7f1f1)
    private val nightPage = shade(0f, 360f, 0xfff0f1f9, 0xffe7f1f3)
    private val guide = 0xff55727d
    private val signal = 0xff267d78
    private val quietSignal = 0xff8caeb0
    private val spinalSignal = 0xff5c709a
    private val sympathetic = 0xff81609c
    private val cellInk = 0xff637e8b
    private val cellFill = shade(110f, 268f, 0xfff0f6ee, 0xffb0d2cc)
    private val vesselFill = shade(204f, 284f, 0xffecd6e0, 0xffc7a0b8)
    private val cerebro = shade(56f, 284f, 0xffeef3f5, 0xffcbd9e3)
    private val serotonin = 0xffa56a35
    private val intermediate = 0xff317c79
    private val melatonin = 0xff73518e
    private val glint = 0xfffaffff
    private val opticWall = path {
        moveTo(35f, 170f)
        cubicTo(35f, 151f, 57f, 126f, 86f, 126f)
        cubicTo(116f, 126f, 136f, 145f, 139f, 168f)
        cubicTo(138f, 194f, 117f, 212f, 87f, 213f)
        cubicTo(60f, 213f, 36f, 191f, 35f, 170f); close()
    }
    private val eyeFill = shade(126f, 213f, 0xfffbfbfb, 0xffc7dbe6)
    private val vitreous = path {
        moveTo(61f, 151f)
        cubicTo(82f, 130f, 119f, 134f, 130f, 159f)
        cubicTo(147f, 197f, 91f, 218f, 63f, 192f)
        quadTo(75f, 172f, 61f, 151f); close()
    }
    private val retinaEdge = path {
        moveTo(97f, 136f)
        cubicTo(117f, 139f, 131f, 151f, 133f, 168f)
        cubicTo(135f, 182f, 127f, 191f, 115f, 199f)
    }
    private val retinaFiber = path {
        moveTo(130f, 158f)
        cubicTo(136f, 169f, 129f, 177f, 136f, 183f)
        cubicTo(159f, 205f, 182f, 213f, 203f, 197f)
        quadTo(208f, 192f, 221f, 184f)
    }
    private val retinaTrack = track(retinaFiber)
    private val eyeRays = (-1..1).map { i ->
        track(path {
            moveTo(15f, 170f + i * 7f)
            lineTo(51f, 170f + i * 6f)
            lineTo(if (i == 1) 128f else 132f, 166f - i * 9f)
        })
    }
    private val cranialProfile = path {
        moveTo(127f, 51f)
        cubicTo(150f, 27f, 201f, 31f, 223f, 57f)
        cubicTo(242f, 79f, 234f, 112f, 225f, 132f)
        cubicTo(220f, 148f, 217f, 174f, 227f, 198f)
        quadTo(242f, 220f, 263f, 231f)
        quadTo(277f, 244f, 280f, 271f)
        quadTo(209f, 303f, 121f, 266f)
        cubicTo(134f, 253f, 149f, 234f, 150f, 212f)
        cubicTo(151f, 198f, 143f, 180f, 140f, 158f)
        cubicTo(128f, 162f, 113f, 154f, 113f, 144f)
        lineTo(111f, 131f); quadTo(96f, 130f, 104f, 119f)
        lineTo(115f, 101f); cubicTo(113f, 83f, 115f, 66f, 127f, 51f); close()
    }
    private val canal = path {
        moveTo(187f, 130f)
        cubicTo(189f, 162f, 179f, 181f, 183f, 207f)
        quadTo(187f, 238f, 196f, 270f)
    }
    private val relays = listOf(
        path { moveTo(147f, 105f); quadTo(144f, 98f, 152f, 90f) },
        path { moveTo(152f, 90f); cubicTo(191f, 107f, 187f, 135f, 185f, 163f)
            cubicTo(183f, 185f, 179f, 208f, 187f, 232f) },
        path { moveTo(187f, 232f); cubicTo(179f, 232f, 166f, 224f, 164f, 210f)
            quadTo(162f, 183f, 145f, 167f) },
        path { moveTo(145f, 167f); cubicTo(150f, 143f, 161f, 123f, 183f, 117f)
            quadTo(209f, 110f, 197f, 98f) },
    )
    private val relayTracks = relays.map(::track)
    private val trace = Path()
    private val cell = path {
        moveTo(85f, 155f); cubicTo(94f, 139f, 98f, 135f, 118f, 128f)
        cubicTo(132f, 114f, 129f, 103f, 149f, 104f)
        cubicTo(153f, 105f, 154f, 111f, 151f, 117f)
        cubicTo(179f, 111f, 208f, 120f, 221f, 134f)
        cubicTo(233f, 147f, 226f, 159f, 251f, 162f)
        cubicTo(269f, 164f, 281f, 154f, 289f, 160f)
        cubicTo(298f, 169f, 287f, 179f, 273f, 181f)
        cubicTo(253f, 184f, 245f, 181f, 244f, 197f)
        cubicTo(244f, 221f, 262f, 218f, 273f, 230f)
        quadTo(282f, 242f, 269f, 246f)
        cubicTo(252f, 241f, 240f, 237f, 220f, 246f)
        cubicTo(193f, 257f, 153f, 253f, 130f, 241f)
        cubicTo(110f, 234f, 94f, 247f, 77f, 239f)
        cubicTo(66f, 233f, 70f, 226f, 84f, 221f)
        cubicTo(96f, 217f, 99f, 211f, 93f, 203f)
        cubicTo(83f, 190f, 77f, 172f, 85f, 155f); close()
    }
    private val axon = path {
        moveTo(19f, 93f); cubicTo(35f, 92f, 37f, 110f, 53f, 116f)
        quadTo(67f, 121f, 69f, 134f)
        moveTo(45f, 112f); quadTo(42f, 129f, 51f, 140f)
        moveTo(35f, 103f); quadTo(47f, 102f, 55f, 103f)
    }
    private val vessel = path {
        moveTo(186f, 278f); cubicTo(232f, 298f, 276f, 250f, 337f, 230f)
        lineTo(340f, 200f); cubicTo(281f, 222f, 235f, 278f, 182f, 256f); close()
    }
    private val vesselLight = path {
        moveTo(192f, 263f); cubicTo(239f, 279f, 293f, 227f, 334f, 210f)
    }
    private val outgoing = track(path {
        moveTo(210f, 204f); cubicTo(225f, 209f, 228f, 242f, 247f, 260f)
        quadTo(272f, 257f, 285f, 243f)
    })
    private val curve = path {
        for (i in 0..110) {
            val t = i / 110f
            if (i == 0) moveTo(cycleX(t), cycleY(t)) else lineTo(cycleX(t), cycleY(t))
        }
    }
    private val curveArea = Path(curve).apply { lineTo(326f, 269f); lineTo(34f, 269f); close() }
    private val curveFill = shade(130f, 278f, 0xffcabce0, 0xfff0edf5)

    init { tag = "atlas-function-pineal-dark-signal-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        ink(glint)
        paint.shader = if (step in 2..3) nightPage else page
        c.drawRoundRect(0f, 0f, 360f, 360f, 8f, 8f, paint)
        paint.shader = null
        when (step) {
            0 -> orient(c, t)
            1 -> retinalInput(c, t)
            2 -> nerveRelay(c, t)
            3 -> produce(c, t)
            4 -> rhythm(c, t)
        }
    }

    private fun orient(c: Canvas, t: Float) {
        val zoom = HealthAtlasPinealMotion.zoom(t)
        val size = .91f + .57f * zoom
        val x = 242f - 32f * zoom - 249f * size
        val y = 180f - 146f * size
        c.save()
        c.clipRect(12f, 45f, 348f, 293f)
        brain(c, x, y, size)
        c.restore()
        val ventricleX = x + 138f * size
        val ventricleY = y + 140f * size
        val pinealX = x + 249f * size
        ink(0xfffcf7ff, 1.6f)
        c.drawOval(pinealX - 20f * size, 180f - 12f * size,
            pinealX + 20f * size, 180f + 12f * size, paint)
        label(c, R.string.health_atlas_pineal_story_label_anterior, 65f, 33f, 91f)
        label(c, R.string.health_atlas_pineal_story_label_posterior, 295f, 33f, 91f)
        leader(c, R.string.health_atlas_pineal_plate_third_ventricle,
            86f, 328f, 131f, 299f, ventricleX, ventricleY)
        leader(c, R.string.health_atlas_pineal_plate_body,
            266f, 328f, 117f, 299f, pinealX, 180f)
    }

    private fun retinalInput(c: Canvas, t: Float) {
        brain(c, 159f, 100f, .53f)
        solar(c, 41f, 98f, 9f)
        fill(c, opticWall, eyeFill)
        stroke(c, opticWall, cellInk, 1.5f)
        fill(c, vitreous, 0xffe3f3f7)
        oval(c, 47f, 150f, 61f, 189f, 0xffcee8e9, 0xff7b9ca9)
        line(c, 42f, 151f, 42f, 162f, guide, 2.5f)
        line(c, 42f, 176f, 42f, 187f, guide, 2.5f)
        stroke(c, retinaEdge, 0xff9e747d, 4.3f)
        stroke(c, retinaEdge, 0xfff3c9c8, 1.45f)
        val light = HealthAtlasPinealMotion.zoom((t * 2.55f).coerceAtMost(1f))
        for (ray in eyeRays) segment(c, ray, light, 0xffb98639, 1.55f)
        stroke(c, retinaFiber, 0xffd5e7eb, 7f)
        stroke(c, retinaFiber, quietSignal, 2.5f)
        for (i in 0..2) {
            val f = HealthAtlasPinealMotion.retinalSignal(t, i)
            if (f > 0f && f < 1f) at(retinaTrack, f) { x, y -> disc(c, x, y, 3.7f, signal, glint) }
        }
        val arrival = HealthAtlasPinealMotion.retinalSignal(t, 0)
        disc(c, 221f, 184f, 4.7f + 2.1f * arrival, signal, glint)
        leader(c, R.string.health_atlas_pineal_story_label_light, 42f, 68f, 64f, 78f, 41f, 89f, true)
        leader(c, R.string.health_atlas_pineal_story_label_retina, 97f, 286f, 106f, 255f, 117f, 196f)
        leader(c, R.string.health_atlas_pineal_story_label_scn, 249f, 286f, 130f, 252f, 221f, 184f)
    }

    private fun nerveRelay(c: Canvas, t: Float) {
        fill(c, cranialProfile, cerebro)
        stroke(c, cranialProfile, 0xff8fa5b4, 1.35f)
        brain(c, 104f, 43f, .374f)
        stroke(c, canal, 0xffbac7d5, 17f)
        stroke(c, canal, 0xffeaf0f5, 12f)
        for (i in 0..10) {
            val y = 150f + i * 10f
            val x = 191f - i * 2.1f + i * i * .23f
            line(c, x + 1f, y, x + 7f, y + 1.5f, 0xff9faec0, 1.2f)
        }
        stroke(c, canal, 0xff6b80a1, 2.7f)
        oval(c, 140f, 160f, 150f, 173f, 0xffdeceea, sympathetic)
        for ((i, route) in relayTracks.withIndex()) {
            val color = when (i) { 0 -> signal; 1 -> spinalSignal; else -> sympathetic }
            val f = HealthAtlasPinealMotion.relay(t, i)
            stroke(c, relays[i], 0xffaebac6, 1.7f)
            segment(c, route, f, color, 2.4f)
            direction(c, route, if (f > .98f) color else 0xff8194a6)
            if (f > 0f && f < 1f) at(route, f) { x, y -> disc(c, x, y, 4f, color, glint) }
        }
        disc(c, 147f, 105f, 3.8f, signal, glint)
        disc(c, 152f, 90f, 3.8f, spinalSignal, glint)
        disc(c, 187f, 232f, 4.2f, spinalSignal, glint)
        disc(c, 145f, 167f, 4.2f, sympathetic, glint)
        disc(c, 197f, 98f, 3.6f, melatonin, glint)
        crescent(c, 295f, 144f, 11f, 0xffebf2f6)
        label(c, R.string.health_atlas_pineal_story_label_night, 295f, 174f, 100f)
        leader(c, R.string.health_atlas_pineal_story_label_pvn, 84f, 42f, 149f, 55f, 152f, 90f, true)
        leader(c, R.string.health_atlas_pineal_story_label_scn, 61f, 91f, 104f, 101f, 147f, 105f, true)
        leader(c, R.string.health_atlas_pineal_plate_body, 282f, 65f, 118f, 78f, 197f, 98f, true)
        leader(c, R.string.health_atlas_pineal_story_label_scg, 81f, 210f, 142f, 192f, 145f, 167f)
        leader(c, R.string.health_atlas_pineal_story_label_spinal, 269f, 309f, 147f, 286f, 187f, 232f)
    }

    private fun produce(c: Canvas, t: Float) {
        fill(c, vessel, vesselFill)
        stroke(c, vessel, 0xff9f7f98, 1.35f)
        stroke(c, vesselLight, 0xfffaebf0, 1.5f)
        for (i in 0..3) {
            val x = 220f + i * 31f
            val y = 272f - i * (5f + i * 2f)
            c.save()
            c.rotate(4f - 14f * i, x, y)
            oval(c, x - 8f, y - 3.8f, x + 8f, y + 3.8f, 0xffd7a3b1, 0xffa0758c)
            c.restore()
        }
        fill(c, cell, cellFill)
        stroke(c, cell, cellInk, 1.65f)
        stroke(c, axon, 0xffcfbddf, 6f)
        stroke(c, axon, sympathetic, 1.55f)
        disc(c, 69f, 134f, 5.9f, 0xffd6c2e1, sympathetic)
        disc(c, 51f, 140f, 4.7f, 0xffd6c2e1, sympathetic)
        disc(c, 55f, 103f, 3.8f, 0xffd6c2e1, sympathetic)
        oval(c, 144f, 126f, 193f, 161f, 0xffaac2d1, 0xff77929f)
        oval(c, 149f, 130f, 188f, 157f, 0xffc4d7e0, 0xffa2b9c8)
        disc(c, 171f, 143f, 4.3f, 0xff8ca7b8)
        for (i in 0..6) {
            val x = 99f + i * 19f
            val y = if (i % 2 == 0) 226f else 232f
            oval(c, x + 3f, y - 1f, x + 8f, y + 1.7f, 0xffdceee7, 0xff9ebdbd)
        }
        ink(sympathetic, 2.15f)
        c.drawArc(82f, 146f, 97f, 162f, 168f, 132f, false, paint)
        for (i in 0..2) {
            val f = HealthAtlasPinealMotion.transmitter(t, i)
            if (f > 0f) {
                val x = 70f + (16f - 2f * i) * f
                val y = 134f + (12f + 4f * i) * f
                disc(c, x - i * (1f - f), y, 2.5f, sympathetic, glint)
            }
        }
        val first = HealthAtlasPinealMotion.synthesis(t, 0)
        val second = HealthAtlasPinealMotion.synthesis(t, 1)
        val sX = 108f
        val nX = 159f
        val mX = 210f
        val y = 204f
        molecule(c, sX, y, 0, true)
        molecule(c, nX, y, 1, first >= .98f)
        molecule(c, mX, y, 2, second >= .98f)
        arrow(c, sX + 10f, y, nX - 10f, y, if (first > 0f) intermediate else quietSignal)
        arrow(c, nX + 10f, y, mX - 10f, y, if (second > 0f) melatonin else quietSignal)
        if (first > 0f && first < 1f) molecule(c, sX + (nX - sX) * first, y, 1, true)
        if (second > 0f && second < 1f) molecule(c, nX + (mX - nX) * second, y, 2, true)
        for (i in 0..2) {
            val f = HealthAtlasPinealMotion.secretion(t, i)
            if (f > 0f) at(outgoing, f * (1f - .10f * i)) { x, cy -> disc(c, x, cy, 3.1f, melatonin, glint) }
        }
        leader(c, R.string.health_atlas_pineal_story_label_norepinephrine, 96f, 67f, 124f, 91f, 77f, 144f, true)
        leader(c, R.string.health_atlas_pineal_story_label_pinealocyte, 250f, 77f, 128f, 99f, 211f, 132f, true)
        label(c, R.string.health_atlas_pineal_story_label_aanat, 134f, 188f, 48f)
        label(c, R.string.health_atlas_pineal_story_label_asmt, 184f, 188f, 48f)
        leader(c, R.string.health_atlas_pineal_story_label_serotonin, 62f, 315f, 84f, 289f, sX, 211f)
        leader(c, R.string.health_atlas_pineal_story_label_intermediate, 171f, 315f, 124f, 289f, nX, 211f)
        leader(c, R.string.health_atlas_pineal_story_label_melatonin, 278f, 315f, 82f, 291f, mX, 211f)
        leader(c, R.string.health_atlas_pineal_story_label_capillary, 317f, 126f, 80f, 153f, 320f, 224f, true)
    }

    private fun rhythm(c: Canvas, t: Float) {
        rounded(c, 34f, 123f, 326f, 270f, 6f, 0xfffbf6e8)
        rounded(c, 119f, 123f, 250f, 270f, 0f, 0xffe6e7f1)
        fill(c, curveArea, curveFill)
        for (y in 151..241 step 30) line(c, 34f, y.toFloat(), 326f, y.toFloat(), 0xffcbd5dc, .9f)
        line(c, 34f, 126f, 34f, 270f, guide, 1.3f)
        line(c, 34f, 270f, 326f, 270f, guide, 1.3f)
        stroke(c, curve, melatonin, 3.2f)
        val f = HealthAtlasPinealMotion.cycle(t)
        val x = cycleX(f)
        val y = cycleY(f)
        line(c, x, 122f, x, 270f, 0xff8393a7, 1.05f)
        disc(c, x, y, 6.2f, melatonin, glint)
        solar(c, 76f, 75f, 9f)
        crescent(c, 184f, 75f, 10f, 0xfff4f8fa)
        solar(c, 288f, 75f, 9f)
        label(c, R.string.health_atlas_pineal_story_label_relative, 180f, 40f, 275f)
        label(c, R.string.health_atlas_pineal_story_label_day, 76f, 106f, 76f)
        label(c, R.string.health_atlas_pineal_story_label_night, 184f, 106f, 102f)
        label(c, R.string.health_atlas_pineal_story_label_day, 288f, 106f, 67f)
    }

    private fun brain(c: Canvas, x: Float, y: Float, size: Float) {
        c.save(); c.translate(x, y); c.scale(size, size)
        pinealPlate.draw(c)
        c.restore()
    }

    private fun cycleX(t: Float) = 34f + 292f * t
    private fun cycleY(t: Float) = 269f - 145f * HealthAtlasPinealMotion.melatonin(t)

    private fun solar(c: Canvas, x: Float, y: Float, r: Float) {
        disc(c, x, y, r, 0xfff0d499, 0xffa6783d)
        for (i in 0..7) {
            c.save(); c.rotate(45f * i, x, y)
            line(c, x, y - r - 3.3f, x, y - r - 6.7f, 0xffa6783d, 1.3f)
            c.restore()
        }
    }

    private fun crescent(c: Canvas, x: Float, y: Float, r: Float, sky: Long) {
        disc(c, x, y, r, 0xff8293b5)
        disc(c, x + r * .51f, y - r * .39f, r * .86f, sky)
    }

    private fun molecule(c: Canvas, x: Float, y: Float, form: Int, active: Boolean) {
        val color = when (form) { 0 -> serotonin; 1 -> intermediate; else -> melatonin }
        val fill = if (active) color else 0xffe1eceb
        when (form) {
            0 -> disc(c, x, y, 5.4f, fill, color)
            1 -> oval(c, x - 6.1f, y - 4.5f, x + 6.1f, y + 4.5f, fill, color)
            else -> {
                c.save(); c.rotate(45f, x, y)
                rounded(c, x - 4.1f, y - 4.1f, x + 4.1f, y + 4.1f, 1.5f, fill)
                ink(color, 1.05f)
                c.drawRoundRect(x - 4.1f, y - 4.1f, x + 4.1f, y + 4.1f, 1.5f, 1.5f, paint)
                c.restore()
            }
        }
    }

    private fun direction(c: Canvas, route: PathMeasure, color: Long) {
        at(route, .63f) { x, y ->
            at(route, (.63f + 8f / route.length).coerceAtMost(.94f)) { nx, ny ->
                arrow(c, x, y, nx, ny, color)
            }
        }
    }

    private fun segment(c: Canvas, route: PathMeasure, fraction: Float, color: Long, width: Float) {
        trace.rewind()
        if (route.getSegment(0f, route.length * fraction, trace, true)) stroke(c, trace, color, width)
    }

    private fun fill(c: Canvas, path: Path, shader: Shader) {
        ink(glint); paint.shader = shader; c.drawPath(path, paint); paint.shader = null
    }

    private fun fill(c: Canvas, path: Path, color: Long) {
        ink(color); c.drawPath(path, paint)
    }

    private fun leader(
        c: Canvas, @StringRes res: Int, x: Float, baseline: Float, width: Float,
        elbowY: Float, targetX: Float, targetY: Float, pointsDown: Boolean = false,
    ) {
        line(c, x, baseline + if (pointsDown) 5f else -13f, x, elbowY, guide, 1.1f)
        line(c, x, elbowY, targetX, targetY, guide, 1.1f)
        disc(c, targetX, targetY, 1.8f, guide)
        label(c, res, x, baseline, width)
    }

    private fun path(build: Path.() -> Unit) = Path().apply(build)
}
