package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader
import androidx.annotation.StringRes

internal object HealthAtlasPlacentalExchangeLesson {
    val chapters = listOf(
        R.string.health_atlas_placental_exchange_story_orient to R.string.health_atlas_placental_exchange_story_orient_caption,
        R.string.health_atlas_placental_exchange_story_routes to R.string.health_atlas_placental_exchange_story_routes_caption,
        R.string.health_atlas_placental_exchange_story_interface to R.string.health_atlas_placental_exchange_story_interface_caption,
        R.string.health_atlas_placental_exchange_story_gases to R.string.health_atlas_placental_exchange_story_gases_caption,
        R.string.health_atlas_placental_exchange_story_nutrients to R.string.health_atlas_placental_exchange_story_nutrients_caption,
    )
    val references = listOf(
        R.string.health_atlas_placental_exchange_story_ref_anatomy to
            "https://openstax.org/books/anatomy-and-physiology-2e/pages/28-2-embryonic-development",
        R.string.health_atlas_placental_exchange_story_ref_flow to
            "https://doi.org/10.1371/journal.pbio.3000676",
        R.string.health_atlas_placental_exchange_story_ref_interface to "https://pubmed.ncbi.nlm.nih.gov/1287078/",
        R.string.health_atlas_placental_exchange_story_ref_glucose to "https://pubmed.ncbi.nlm.nih.gov/1571954/",
    )
}

internal object HealthAtlasPlacentalExchangeMotion {
    private fun phase(t: Float) = if (t.isFinite()) t.coerceIn(0f, 1f) else 0f

    fun emphasis(t: Float): Float {
        val f = phase(t)
        return 4f * f * (1f - f)
    }

    fun stream(t: Float, index: Int): Float {
        val f = phase(t) + index / 3f
        return f - f.toInt()
    }

    fun transfer(t: Float, start: Float, end: Float): Float {
        val f = ((phase(t) - start) / (end - start)).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }
}

internal class HealthAtlasPlacentalExchangeStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.PLACENTAL_EXCHANGE) {
    private val edge = 0xff8f615f
    private val vesselEdge = 0xff527681
    private val maternalInk = 0xffa66070
    private val fetalInk = 0xff3e7582
    private val oxygenInk = 0xff286556
    private val carbonInk = 0xff765380
    private val glucoseInk = 0xff82511e
    private val guide = 0xff506369
    private val maternalFill = shade(92f, 263f, 0xfff8e6df, 0xffe9bfc0)
    private val outerFill = shade(92f, 257f, 0xffd9a2a2, 0xffb77987)
    private val coreFill = shade(93f, 250f, 0xfff0d8c0, 0xffe6b494)
    private val section = requireNotNull(context.getDrawable(R.drawable.health_atlas_placenta_plate)).apply {
        setBounds(20, 53, 340, 302)
    }

    private val field = Path().apply {
        moveTo(33f, 106f)
        cubicTo(83f, 89f, 156f, 96f, 206f, 93f)
        lineTo(300f, 93f)
        cubicTo(335f, 102f, 339f, 149f, 334f, 197f)
        cubicTo(330f, 232f, 316f, 261f, 280f, 269f)
        cubicTo(223f, 279f, 165f, 269f, 115f, 271f)
        cubicTo(78f, 273f, 39f, 275f, 31f, 249f)
        cubicTo(24f, 221f, 20f, 131f, 33f, 106f)
        close()
    }
    private val maternalRoute = Path().apply {
        moveTo(43f, 257f)
        cubicTo(37f, 222f, 40f, 160f, 61f, 133f)
        cubicTo(78f, 112f, 105f, 113f, 113f, 143f)
        cubicTo(122f, 171f, 104f, 207f, 108f, 258f)
    }
    private val surface = Path().apply {
        moveTo(217f, 93f)
        cubicTo(216f, 115f, 197f, 121f, 176f, 131f)
        cubicTo(151f, 142f, 139f, 154f, 138f, 177f)
        cubicTo(135f, 207f, 143f, 229f, 160f, 244f)
        cubicTo(180f, 262f, 218f, 257f, 247f, 244f)
        cubicTo(277f, 232f, 294f, 208f, 295f, 184f)
        cubicTo(297f, 159f, 281f, 144f, 287f, 122f)
        quadTo(291f, 107f, 300f, 93f)
        close()
    }
    private val core = Path().apply {
        moveTo(225f, 93f)
        cubicTo(223f, 121f, 200f, 127f, 179f, 137f)
        cubicTo(157f, 147f, 147f, 158f, 146f, 178f)
        cubicTo(143f, 205f, 150f, 224f, 166f, 238f)
        cubicTo(184f, 252f, 216f, 249f, 244f, 237f)
        cubicTo(272f, 225f, 287f, 205f, 288f, 183f)
        cubicTo(290f, 160f, 274f, 144f, 280f, 121f)
        quadTo(284f, 105f, 293f, 93f)
        close()
    }
    private val fetalRoute = Path().apply {
        moveTo(233f, 94f)
        cubicTo(226f, 117f, 198f, 127f, 176f, 141f)
        cubicTo(161f, 151f, 158f, 169f, 158f, 187f)
        cubicTo(158f, 216f, 176f, 237f, 205f, 232f)
        cubicTo(231f, 228f, 258f, 217f, 269f, 193f)
        cubicTo(282f, 167f, 264f, 147f, 270f, 122f)
        quadTo(274f, 105f, 284f, 94f)
    }
    private val surfaceLight = Path().apply {
        moveTo(213f, 114f); quadTo(204f, 123f, 189f, 129f)
        moveTo(174f, 137f); quadTo(157f, 147f, 150f, 156f)
        moveTo(141f, 181f); quadTo(139f, 187f, 140f, 196f)
        moveTo(155f, 233f); quadTo(165f, 244f, 176f, 247f)
        moveTo(227f, 248f); quadTo(243f, 244f, 253f, 238f)
        moveTo(278f, 217f); quadTo(286f, 207f, 290f, 190f)
    }
    private val stromalFibers = Path().apply {
        moveTo(179f, 165f); cubicTo(196f, 152f, 220f, 152f, 230f, 140f)
        moveTo(193f, 189f); cubicTo(205f, 184f, 216f, 193f, 229f, 185f)
        moveTo(197f, 219f); quadTo(215f, 217f, 227f, 209f)
        moveTo(231f, 177f); quadTo(249f, 163f, 246f, 147f)
    }
    private val nuclei = arrayOf(
        floatArrayOf(186f, 130f, -26f), floatArrayOf(158f, 146f, -42f),
        floatArrayOf(141f, 168f, -80f), floatArrayOf(142f, 208f, 74f),
        floatArrayOf(160f, 239f, 45f), floatArrayOf(188f, 252f, 8f),
        floatArrayOf(222f, 249f, -14f), floatArrayOf(252f, 239f, -25f),
        floatArrayOf(280f, 218f, -48f), floatArrayOf(291f, 188f, -83f),
        floatArrayOf(288f, 158f, 73f), floatArrayOf(283f, 130f, -84f),
    )
    private val maternalTrack = track(maternalRoute)
    private val fetalTrack = track(fetalRoute)
    private val maternalDash = DashPathEffect(floatArrayOf(3f, 4f), 0f)
    private val position = FloatArray(2)
    private val tangent = FloatArray(2)
    private val symbol = Path()

    init { tag = "atlas-function-placental-exchange-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        if (step == 0) {
            orient(c, t)
            return
        }
        villus(c)
        flows(c, t, step == 1)
        when (step) {
            1 -> routeKey(c)
            2 -> interfaceFocus(c, t)
            3 -> gases(c, t)
            4 -> glucose(c, t)
        }
        anatomyLabels(c)
    }

    private fun orient(c: Canvas, t: Float) {
        section.draw(c)
        val focus = HealthAtlasPlacentalExchangeMotion.emphasis(t)
        ink(0xfffdf4da, 3.4f); c.drawCircle(210.2f, 202.4f, 12f + 6f * focus, paint)
        ink(fetalInk, 1.4f); c.drawCircle(210.2f, 202.4f, 12f + 6f * focus, paint)
        leader(c, R.string.health_atlas_placental_exchange_story_cord, 226f, 42f, 135f,
            226f, 57f, 202.2f, 83.2f, true)
        leader(c, R.string.health_atlas_placental_exchange_story_chorionic_plate, 84f, 111f, 147f,
            84f, 124f, 109f, 142f, true)
        leader(c, R.string.health_atlas_placental_exchange_story_basal_plate, 92f, 318f, 144f,
            92f, 289f, 161f, 265f)
        leader(c, R.string.health_atlas_placental_exchange_story_terminal_villus, 272f, 318f, 148f,
            272f, 284f, 210.2f, 202.4f)
    }

    private fun villus(c: Canvas) {
        shaded(c, field, maternalFill)
        stroke(c, field, 0xffb88c94, 1.1f)
        shaded(c, surface, outerFill)
        stroke(c, surface, edge, 1.5f)
        shaded(c, core, coreFill)
        stroke(c, core, 0xffc18d7e, 1f)
        stroke(c, surfaceLight, 0xfff1cbc0, 1.35f)
        stroke(c, stromalFibers, 0xffc79580, 1.15f)
        for ((x, y, angle) in nuclei) {
            c.save()
            c.rotate(angle, x, y)
            oval(c, x - 3.6f, y - 1.6f, x + 3.6f, y + 1.6f, 0xff93677c, 0xff82586e)
            c.restore()
        }
        c.save()
        c.clipPath(surface)
        stroke(c, fetalRoute, vesselEdge, 18f)
        stroke(c, fetalRoute, 0xffb2d2d2, 14f)
        c.restore()
    }

    private fun flows(c: Canvas, t: Float, routeChapter: Boolean) {
        val maternal = if (routeChapter) maternalInk else 0xffbd8990
        val fetal = if (routeChapter) fetalInk else 0xff6a949b
        paint.pathEffect = maternalDash
        stroke(c, maternalRoute, maternal, 1.35f)
        paint.pathEffect = null
        routeArrow(c, maternalTrack, .10f, maternal)
        routeArrow(c, maternalTrack, .89f, maternal)
        routeArrow(c, fetalTrack, .08f, fetal)
        routeArrow(c, fetalTrack, .87f, fetal)
        val length = if (routeChapter) 3 else 2
        for (i in 0 until length) {
            val progress = HealthAtlasPlacentalExchangeMotion.stream(t, i)
            val size = minOf(1f, progress * 12f, (1f - progress) * 12f)
            if (size > 0f) {
                at(maternalTrack, progress) { x, y ->
                    oval(c, x - 4.1f * size, y - 2.6f * size, x + 4.1f * size, y + 2.6f * size,
                        0xffe3a7a9, maternal)
                }
                at(fetalTrack, progress) { x, y ->
                    oval(c, x - 4.1f * size, y - 2.6f * size, x + 4.1f * size, y + 2.6f * size,
                        0xffd9e9e5, fetal)
                }
            }
        }
    }

    private fun routeArrow(c: Canvas, path: PathMeasure, fraction: Float, color: Long) {
        if (path.getPosTan(path.length * fraction, position, tangent)) {
            val x = position[0]
            val y = position[1]
            arrow(c, x - 6f * tangent[0], y - 6f * tangent[1],
                x + 6f * tangent[0], y + 6f * tangent[1], color)
        }
    }

    private fun interfaceFocus(c: Canvas, t: Float) {
        val highlight = HealthAtlasPlacentalExchangeMotion.emphasis(t)
        // Trace the two adjacent surfaces without suggesting a connecting channel.
        ink(0xfffbe4c1, 1.4f + 1.5f * highlight)
        c.drawArc(137.8f, 161f, 148f, 202f, 110f, 140f, false, paint)
        ink(0xffe1f1ea, 1.4f + 1.5f * highlight)
        c.drawArc(149.2f, 162f, 159f, 200f, 110f, 140f, false, paint)
    }

    private fun gases(c: Canvas, t: Float) {
        arrow(c, 117f, 161f, 163f, 161f, oxygenInk)
        arrow(c, 158f, 196f, 116f, 196f, carbonInk)
        val oxygen = HealthAtlasPlacentalExchangeMotion.transfer(t, .08f, .79f)
        val carbon = HealthAtlasPlacentalExchangeMotion.transfer(t, .20f, .91f)
        gasSymbol(c, 117f + 45f * oxygen, 161f, true)
        gasSymbol(c, 158f - 42f * carbon, 196f, false)
        gasSymbol(c, 55f, 335f, true)
        label(c, R.string.health_atlas_placental_exchange_story_oxygen, 107f, 340f, 92f)
        gasSymbol(c, 192f, 335f, false)
        label(c, R.string.health_atlas_placental_exchange_story_carbon_dioxide, 263f, 340f, 126f)
    }

    private fun glucose(c: Canvas, t: Float) {
        arrow(c, 115f, 179f, 161f, 179f, glucoseInk)
        transporter(c, 138.8f, 179f)
        transporter(c, 146.2f, 179f)
        val travel = HealthAtlasPlacentalExchangeMotion.transfer(t, .07f, .89f)
        diamond(c, 115f + 44f * travel, 179f, 3.3f, 0xfff1ca7e, glucoseInk)
        diamond(c, 55f, 335f, 4f, 0xfff1ca7e, glucoseInk)
        label(c, R.string.health_atlas_placental_exchange_story_glucose, 107f, 340f, 92f)
        transporter(c, 192f, 335f)
        label(c, R.string.health_atlas_placental_exchange_story_glut1, 263f, 340f, 126f)
    }

    private fun gasSymbol(c: Canvas, x: Float, y: Float, oxygen: Boolean) {
        if (oxygen) disc(c, x, y, 3.7f, 0xffb9ddbb, oxygenInk)
        else oval(c, x - 4.1f, y - 2.7f, x + 4.1f, y + 2.7f, 0xffe3d1e9, carbonInk)
    }

    private fun transporter(c: Canvas, x: Float, y: Float) {
        oval(c, x - 2.1f, y - 4.3f, x + 2.1f, y + 4.3f, 0xfff6dcad, glucoseInk)
    }

    private fun diamond(c: Canvas, x: Float, y: Float, size: Float, fill: Long, border: Long) {
        symbol.rewind()
        symbol.moveTo(x, y - size)
        symbol.lineTo(x + size, y)
        symbol.lineTo(x, y + size)
        symbol.lineTo(x - size, y)
        symbol.close()
        ink(fill); c.drawPath(symbol, paint)
        stroke(c, symbol, border, 1.1f)
    }

    private fun routeKey(c: Canvas) {
        for (y in listOf(326f, 346f)) {
            disc(c, 19f, y - 4f, 2.5f, maternalInk)
            disc(c, 178f, y - 4f, 2.5f, fetalInk)
        }
        label(c, R.string.health_atlas_placental_exchange_story_maternal_in, 97f, 326f, 135f)
        label(c, R.string.health_atlas_placental_exchange_story_maternal_out, 97f, 346f, 135f)
        label(c, R.string.health_atlas_placental_exchange_story_fetal_in, 265f, 326f, 155f)
        label(c, R.string.health_atlas_placental_exchange_story_fetal_out, 265f, 346f, 155f)
    }

    private fun anatomyLabels(c: Canvas) {
        leader(c, R.string.health_atlas_placental_exchange_story_intervillous, 84f, 80f, 146f,
            84f, 103f, 55f, 119f, true)
        leader(c, R.string.health_atlas_placental_exchange_story_capillary, 281f, 80f, 140f,
            281f, 103f, 267f, 139f, true)
        leader(c, R.string.health_atlas_placental_exchange_story_syncytium, 98f, 305f, 153f,
            98f, 281f, 150f, 225f)
        leader(c, R.string.health_atlas_placental_exchange_story_endothelium, 254f, 305f, 164f,
            254f, 281f, 204f, 241f)
    }

    private fun shaded(c: Canvas, path: Path, fill: Shader) {
        ink(cream); paint.shader = fill; c.drawPath(path, paint); paint.shader = null
    }

    private fun leader(
        c: Canvas, @StringRes res: Int, x: Float, baseline: Float, width: Float,
        elbowX: Float, elbowY: Float, targetX: Float, targetY: Float, below: Boolean = false,
    ) {
        line(c, x, baseline + if (below) 5f else -15f, elbowX, elbowY, guide, 1.05f)
        line(c, elbowX, elbowY, targetX, targetY, guide, 1.05f)
        disc(c, targetX, targetY, 1.8f, guide)
        label(c, res, x, baseline, width)
    }
}
