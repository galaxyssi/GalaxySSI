package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader

internal enum class HealthAtlasIntercalatedStage(val title: Int, val caption: Int) {
    ORIENTATION(
        R.string.health_atlas_intercalated_story_orientation,
        R.string.health_atlas_intercalated_story_orientation_caption,
    ),
    PROTON_SECRETION(
        R.string.health_atlas_intercalated_story_protons,
        R.string.health_atlas_intercalated_story_protons_caption,
    ),
    BICARBONATE_RETURN(
        R.string.health_atlas_intercalated_story_bicarbonate,
        R.string.health_atlas_intercalated_story_bicarbonate_caption,
    ),
    LUMINAL_BUFFERS(
        R.string.health_atlas_intercalated_story_buffers,
        R.string.health_atlas_intercalated_story_buffers_caption,
    ),
    ACID_EXCRETION(
        R.string.health_atlas_intercalated_story_excretion,
        R.string.health_atlas_intercalated_story_excretion_caption,
    );

    fun progress(t: Float): Float {
        val f = HealthAtlasFunctionStory.safePhase(t)
        return when (this) {
            ORIENTATION -> f * f * (3f - 2f * f)
            PROTON_SECRETION -> f * f
            BICARBONATE_RETURN -> f * (2f - f)
            LUMINAL_BUFFERS -> ((f - .07f) / .86f).coerceIn(0f, 1f)
            ACID_EXCRETION -> f
        }
    }
}

internal class HealthAtlasIntercalatedStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.INTERCALATED_BALANCE) {
    private val leaderInk = 0xff52686b
    private val fluidInk = 0xff4c7d86
    private val principalInk = 0xff668780
    private val cellInk = 0xff97606e
    private val vesselInk = 0xffa4616a
    private val protonInk = 0xffa02e40
    private val baseInk = 0xff246e61
    private val ammoniaInk = 0xff865e2b
    private val phosphateInk = 0xff66517d

    private val fluidFill = shade(64f, 157f, 0xffd1e8e9, 0xffebf6f1)
    private val principalFill = shade(147f, 232f, 0xffe6f0e7, 0xffb9d1c3)
    private val cellFill = shade(134f, 231f, 0xfff8ddd0, 0xffe5aeb0)
    private val vesselFill = shade(265f, 304f, 0xfff7ddd2, 0xffedc1bf)
    private val brush = Path()

    // The two duct walls bound the lumen. The capillary is a separate compartment.
    private val lumen = Path().apply {
        moveTo(23f, 73f)
        cubicTo(104f, 72f, 254f, 66f, 337f, 72f)
        lineTo(337f, 157f)
        lineTo(23f, 157f)
        close()
    }
    private val oppositeWall = Path().apply {
        moveTo(23f, 51f)
        cubicTo(112f, 48f, 255f, 42f, 337f, 49f)
        lineTo(337f, 72f)
        cubicTo(254f, 66f, 104f, 72f, 23f, 73f)
        close()
    }
    private val nearWall = Path().apply {
        moveTo(23f, 154f)
        quadTo(76f, 145f, 129f, 149f)
        quadTo(172f, 151f, 218f, 149f)
        quadTo(268f, 146f, 337f, 153f)
        lineTo(337f, 229f)
        quadTo(179f, 235f, 23f, 227f)
        close()
    }
    private val typeA = Path().apply {
        moveTo(129f, 149f)
        cubicTo(139f, 133f, 157f, 128f, 179f, 131f)
        quadTo(204f, 133f, 220f, 149f)
        cubicTo(218f, 173f, 229f, 197f, 211f, 224f)
        quadTo(200f, 237f, 168f, 231f)
        cubicTo(137f, 232f, 123f, 217f, 125f, 189f)
        quadTo(123f, 166f, 129f, 149f)
        close()
    }
    private val capillary = Path().apply {
        moveTo(25f, 273f)
        cubicTo(101f, 259f, 148f, 272f, 216f, 269f)
        quadTo(287f, 264f, 335f, 271f)
        lineTo(335f, 301f)
        quadTo(284f, 294f, 218f, 301f)
        cubicTo(143f, 308f, 92f, 290f, 25f, 306f)
        close()
    }
    private val protonRoute = track(Path().apply {
        moveTo(148f, 174f)
        cubicTo(146f, 156f, 153f, 142f, 151f, 132f)
        quadTo(151f, 120f, 165f, 107f)
    })
    private val bicarbonateRoute = track(Path().apply {
        moveTo(193f, 182f)
        cubicTo(186f, 201f, 201f, 214f, 201f, 230f)
        cubicTo(201f, 250f, 218f, 259f, 227f, 274f)
        quadTo(235f, 290f, 281f, 285f)
    })

    init { tag = "atlas-function-intercalated-balance-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val stage = HealthAtlasIntercalatedStage.entries[step]
        val f = stage.progress(t)
        drawDuct(c)
        drawCapillary(c, if (stage == HealthAtlasIntercalatedStage.ACID_EXCRETION) f else 0f)
        when (stage) {
            HealthAtlasIntercalatedStage.ORIENTATION -> drawTubularFlow(c, f)
            HealthAtlasIntercalatedStage.PROTON_SECRETION -> drawProtons(c, f)
            HealthAtlasIntercalatedStage.BICARBONATE_RETURN -> drawBicarbonate(c, f)
            HealthAtlasIntercalatedStage.LUMINAL_BUFFERS -> {
                drawBuffer(c, f, phosphate = false)
                drawBuffer(c, ((f - .14f) / .86f).coerceIn(0f, 1f), phosphate = true)
            }
            HealthAtlasIntercalatedStage.ACID_EXCRETION -> {
                drawBicarbonate(c, f)
                drawBufferedOutflow(c, f)
            }
        }
        drawLabels(c)
    }

    private fun drawDuct(c: Canvas) {
        wash(c, lumen, fluidFill)
        ink(0xffd9e4d8); c.drawPath(oppositeWall, paint)
        stroke(c, oppositeWall, principalInk, 1.2f)
        for (i in 0..4) {
            val x = 55f + i * 55f
            val y = 60f - i * .65f
            oval(c, x - 10f, y - 3.2f, x + 10f, y + 3.2f, 0xff94ada1, principalInk)
            line(c, x + 26f, y - 11f, x + 28f, y + 11f, 0xffa3b7a9, 1f)
        }

        wash(c, nearWall, principalFill)
        stroke(c, nearWall, principalInk, 1.3f)
        line(c, 278f, 149f, 274f, 231f, principalInk, 1.2f)
        nucleus(c, 71f, 181f, 0xff9cb9ad, principalInk)
        nucleus(c, 249f, 189f, 0xff9cb9ad, principalInk)
        nucleus(c, 308f, 191f, 0xff9cb9ad, principalInk)
        for (i in 0..2) {
            val x = 57f + i * 7f
            line(c, x, 150f, x + 1f, 146f, principalInk, 1.1f)
        }

        wash(c, typeA, cellFill)
        stroke(c, typeA, cellInk, 1.6f)
        nucleus(c, 169f, 185f, 0xffbd8999, cellInk)
        for (i in 0..4) {
            val x = 164f + 8f * i
            val y = 131f + .01f * (x - 167f) * (x - 167f)
            line(c, x, y + .2f, x + 1f, y - 5.5f, cellInk, 1.45f)
        }
        for (i in 0..2) {
            val x = 179f + i * 8f
            oval(c, x - 3f, 152f + 3f * i, x + 3f, 156f + 3f * i, 0xffe1aa9f, cellInk)
        }

        // Membrane symbols: a luminal proton pump and a basolateral AE1 exchanger.
        rounded(c, 145f, 132f, 157f, 143f, 3f, protonInk)
        oval(c, 146f, 140f, 156f, 148f, 0xffe5a7a4, protonInk)
        rounded(c, 194f, 224f, 208f, 233f, 2.5f, baseInk)
        line(c, 198f, 228f, 204f, 228f, 0xffebf6ea, 1.2f)
    }

    private fun nucleus(c: Canvas, x: Float, y: Float, color: Long, border: Long) {
        oval(c, x - 12f, y - 8f, x + 12f, y + 8f, color, border)
        disc(c, x - 3f, y + 1f, 2.4f, border)
    }

    private fun drawCapillary(c: Canvas, f: Float) {
        wash(c, capillary, vesselFill)
        stroke(c, capillary, vesselInk, 1.55f)
        c.save()
        c.clipPath(capillary)
        for (i in 0..4) {
            val x = 23f + (16f + i * 64f + f * 132f) % 320f
            val y = 282f + 6f * (i % 2)
            c.save()
            c.rotate(if (i % 2 == 0) -13f else 17f, x, y)
            oval(c, x - 10f, y - 4.7f, x + 10f, y + 4.7f, 0xffd7898b, vesselInk)
            oval(c, x - 5f, y - 1.8f, x + 5f, y + 1.8f, 0xffefb3a9, 0xffc58083)
            c.restore()
        }
        c.restore()
    }

    private fun drawTubularFlow(c: Canvas, f: Float) {
        arrow(c, 126f, 106f, 321f, 106f, fluidInk)
        c.save()
        c.clipRect(116f, 79f, 331f, 127f)
        for (i in 0..4) {
            val x = 116f + (i * 47f + f * 148f) % 217f
            val y = if (i % 2 == 0) 93f else 118f
            line(c, x - 9f, y, x, y, 0xff8ab1b5, 1.65f)
            disc(c, x + 4f, y, 1.7f, fluidInk)
        }
        c.restore()
    }

    private fun drawProtons(c: Canvas, f: Float) {
        arrow(c, 153f, 127f, 164f, 110f, protonInk)
        for (i in 0..2) {
            val phase = (f * 1.22f + i * .31f + .08f) % 1f
            at(protonRoute, phase) { x, y -> proton(c, x, y) }
        }
    }

    private fun drawBicarbonate(c: Canvas, f: Float) {
        arrow(c, 203f, 238f, 221f, 265f, baseInk)
        for (i in 0..1) {
            val phase = (f * .91f + i * .49f + .12f) % 1f
            at(bicarbonateRoute, phase) { x, y -> bicarbonate(c, x, y) }
        }
    }

    private fun drawBuffer(c: Canvas, f: Float, phosphate: Boolean) {
        val y = if (phosphate) 115f else 88f
        val rise = if (phosphate) 9f else 16f
        val meeting = if (phosphate) 230f else 211f
        val approach = (f / .54f).coerceAtMost(1f)
        val startX = if (phosphate) 186f else 169f
        if (approach < 1f) {
            proton(c, mix(startX, meeting + 4f, approach), mix(y + rise, y - 4f, approach))
            buffer(c, mix(startX + 22f, meeting, approach), y, phosphate, bound = false)
        } else {
            buffer(c, mix(meeting, 313f, (f - .54f) / .46f), y, phosphate, bound = true)
        }
    }

    private fun drawBufferedOutflow(c: Canvas, f: Float) {
        arrow(c, 180f, 104f, 326f, 104f, fluidInk)
        label(c, R.string.health_atlas_intercalated_story_label_urine, 286f, 88f, 94f)
        leader(c, 286f, 93f, 286f, 104f)
        c.save()
        c.clipRect(164f, 105f, 337f, 128f)
        for (i in 0..3) {
            val x = 165f + (i * 43f + f * 153f) % 174f
            buffer(c, x, 119f, phosphate = i % 2 != 0, bound = true)
        }
        c.restore()
    }

    private fun drawLabels(c: Canvas) {
        label(c, R.string.health_atlas_intercalated_story_label_duct, 180f, 29f, 245f)
        leader(c, 180f, 34f, 180f, 47f)
        label(c, R.string.health_atlas_intercalated_story_label_lumen, 71f, 105f, 90f)
        leader(c, 71f, 110f, 86f, 123f)
        label(c, R.string.health_atlas_intercalated_story_label_apical, 280f, 140f, 100f)
        leader(c, 244f, 136f, 216f, 145f)
        label(c, R.string.health_atlas_intercalated_story_label_principal, 74f, 213f, 96f)
        leader(c, 74f, 201f, 76f, 188f)
        label(c, R.string.health_atlas_intercalated_story_label_type_a, 115f, 248f, 91f)
        leader(c, 153f, 243f, 153f, 222f)
        label(c, R.string.health_atlas_intercalated_story_label_basolateral, 272f, 248f, 122f)
        leader(c, 225f, 243f, 212f, 225f)
        label(c, R.string.health_atlas_intercalated_story_label_blood, 94f, 321f, 143f)
        leader(c, 94f, 308f, 96f, 296f)

        line(c, 24f, 330f, 336f, 330f, 0xffb8cbc1, 1f)
        proton(c, 34f, 344f)
        label(c, R.string.health_atlas_intercalated_story_label_h, 53f, 349f, 30f)
        bicarbonate(c, 104f, 344f)
        label(c, R.string.health_atlas_intercalated_story_label_hco3, 136f, 349f, 54f)
        buffer(c, 185f, 344f, phosphate = false, bound = true)
        label(c, R.string.health_atlas_intercalated_story_label_nh4, 215f, 349f, 48f)
        buffer(c, 265f, 344f, phosphate = true, bound = true)
        label(c, R.string.health_atlas_intercalated_story_label_h2po4, 303f, 349f, 59f)
    }

    private fun leader(c: Canvas, fromX: Float, fromY: Float, x: Float, y: Float) {
        line(c, fromX, fromY, x, y, leaderInk, 1f)
        disc(c, x, y, 1.65f, cream, leaderInk)
    }

    private fun proton(c: Canvas, x: Float, y: Float) =
        disc(c, x, y, 3.2f, protonInk, cream)

    private fun bicarbonate(c: Canvas, x: Float, y: Float) {
        brush.rewind()
        brush.moveTo(x, y - 4.6f)
        brush.lineTo(x + 4.6f, y)
        brush.lineTo(x, y + 4.6f)
        brush.lineTo(x - 4.6f, y)
        brush.close()
        ink(baseInk); c.drawPath(brush, paint)
        stroke(c, brush, cream, .9f)
    }

    private fun buffer(c: Canvas, x: Float, y: Float, phosphate: Boolean, bound: Boolean) {
        if (phosphate) {
            rounded(c, x - 6f, y - 3.5f, x + 5.5f, y + 3.5f, 1.5f, phosphateInk)
            disc(c, x - 2f, y, 1.1f, 0xffe9daef)
        } else {
            disc(c, x, y, 4.7f, 0xffd5ac66, ammoniaInk)
        }
        if (bound) proton(c, x + 4f, y - 4f)
    }

    private fun wash(c: Canvas, path: Path, shader: Shader) {
        ink(cream); paint.shader = shader; c.drawPath(path, paint); paint.shader = null
    }

    private fun mix(from: Float, to: Float, f: Float) = from + (to - from) * f

    companion object {
        const val DURATION_MS = 20_000L
        const val POLARITY_SOURCE = "https://pubmed.ncbi.nlm.nih.gov/9890303/"
        const val BUFFER_SOURCE = "https://www.jci.org/articles/view/101923"
    }
}
