package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import androidx.annotation.StringRes

internal object HealthAtlasGastricAcidMotion {
    fun locate(t: Float) = ease(t, .04f, .82f)
    fun histamine(t: Float) = ease(t, .02f, .43f)
    fun recruit(t: Float) = ease(t, .26f, .92f)
    fun exchange(t: Float) = ease(t, .10f, .86f)
    fun chloride(t: Float) = ease(t, .04f, .64f)
    fun lumen(t: Float) = ease(t, .18f, .98f)
    fun feedback(t: Float) = ease(t, .06f, .70f)
    fun output(t: Float) = 1f - .74f * ease(t, .32f, .93f)

    private fun ease(t: Float, start: Float, end: Float): Float {
        val f = ((HealthAtlasFunctionStory.safePhase(t) - start) / (end - start)).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }
}

internal class HealthAtlasGastricAcidStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.GASTRIC_ACID_SECRETION) {
    private val tissueEdge = 0xff98606d
    private val rose = 0xffce8b94
    private val guide = 0xff626b70
    private val focus = 0xff9b632e
    private val lumenFill = 0xffd4ebea
    private val lumenEdge = 0xff527b83
    private val acid = 0xffa64337
    private val potassium = 0xff705387
    private val chloride = 0xff28766e
    private val stomachFill = shade(82f, 244f, 0xfff5c8b7, 0xffd9888a)
    private val glandFill = shade(106f, 288f, 0xfff8ddd0, 0xffe0a9aa)
    private val cellFill = shade(74f, 275f, 0xffffead0, 0xffe3a298)
    private val nucleusFill = shade(204f, 248f, 0xffdfb1cc, 0xffb886aa)

    private val stomach = shape {
        moveTo(61f, 84f)
        cubicTo(63f, 108f, 66f, 126f, 56f, 146f)
        cubicTo(45f, 165f, 40f, 183f, 31f, 189f)
        quadTo(24f, 194f, 18f, 191f)
        lineTo(17f, 208f)
        cubicTo(36f, 200f, 41f, 225f, 67f, 234f)
        cubicTo(97f, 245f, 130f, 227f, 141f, 198f)
        cubicTo(156f, 162f, 150f, 131f, 131f, 115f)
        cubicTo(115f, 102f, 96f, 108f, 85f, 118f)
        quadTo(77f, 113f, 78f, 84f)
        quadTo(70f, 79f, 61f, 84f)
        close()
    }
    private val folds = shape {
        moveTo(96f, 130f); cubicTo(130f, 112f, 140f, 156f, 134f, 176f)
        moveTo(82f, 139f); cubicTo(120f, 125f, 131f, 165f, 117f, 191f)
        moveTo(70f, 156f); cubicTo(104f, 141f, 120f, 179f, 100f, 207f)
        moveTo(62f, 177f); cubicTo(80f, 164f, 100f, 181f, 86f, 214f)
        moveTo(45f, 197f); quadTo(61f, 192f, 71f, 220f)
    }
    private val gland = shape {
        moveTo(174f, 116f); quadTo(201f, 104f, 227f, 113f)
        quadTo(240f, 122f, 251f, 113f); quadTo(280f, 104f, 315f, 115f)
        lineTo(315f, 132f); cubicTo(286f, 125f, 278f, 149f, 287f, 176f)
        cubicTo(300f, 218f, 288f, 275f, 253f, 282f)
        cubicTo(207f, 292f, 197f, 245f, 208f, 212f)
        cubicTo(221f, 165f, 219f, 122f, 174f, 135f)
        close()
    }
    private val glandSpace = shape {
        moveTo(224f, 112f)
        quadTo(237f, 119f, 254f, 111f)
        cubicTo(244f, 128f, 260f, 145f, 257f, 165f)
        cubicTo(255f, 190f, 245f, 220f, 252f, 242f)
        quadTo(256f, 260f, 246f, 263f)
        cubicTo(232f, 264f, 231f, 232f, 236f, 213f)
        cubicTo(241f, 188f, 247f, 157f, 238f, 141f)
        quadTo(235f, 122f, 224f, 112f)
        close()
    }
    private val locatorTrack = track(shape {
        moveTo(109f, 151f); quadTo(180f, 153f, 269f, 179f)
    })
    private val cell = shape {
        moveTo(272f, 155f)
        cubicTo(282f, 119f, 241f, 75f, 185f, 77f)
        cubicTo(135f, 78f, 95f, 114f, 98f, 168f)
        cubicTo(91f, 221f, 116f, 263f, 169f, 270f)
        cubicTo(217f, 279f, 259f, 250f, 273f, 200f)
        close()
    }
    private val vessel = shape {
        moveTo(35f, 94f); cubicTo(26f, 150f, 54f, 188f, 46f, 258f)
    }
    // The canaliculus folds into the cell but is open to the gland lumen at the right.
    private val canaliculus = shape {
        moveTo(282f, 80f)
        cubicTo(273f, 100f, 266f, 129f, 272f, 151f)
        cubicTo(244f, 156f, 233f, 146f, 218f, 150f)
        cubicTo(202f, 153f, 195f, 151f, 187f, 137f)
        quadTo(179f, 120f, 162f, 115f)
        quadTo(150f, 113f, 153f, 125f)
        quadTo(168f, 132f, 173f, 146f)
        quadTo(178f, 159f, 184f, 167f)
        cubicTo(169f, 175f, 152f, 177f, 139f, 170f)
        quadTo(128f, 165f, 124f, 175f)
        quadTo(122f, 184f, 136f, 190f)
        quadTo(164f, 202f, 189f, 188f)
        cubicTo(199f, 182f, 210f, 180f, 219f, 181f)
        cubicTo(239f, 183f, 249f, 192f, 272f, 191f)
        cubicTo(276f, 220f, 269f, 249f, 283f, 269f)
        quadTo(301f, 276f, 327f, 267f)
        cubicTo(314f, 216f, 329f, 188f, 326f, 151f)
        quadTo(321f, 108f, 335f, 80f)
        quadTo(304f, 73f, 282f, 80f)
        close()
    }
    private val secretionTrack = track(shape {
        moveTo(219f, 166f)
        cubicTo(245f, 165f, 268f, 179f, 291f, 170f)
        cubicTo(307f, 163f, 299f, 121f, 306f, 91f)
    })
    private val feedbackReturn = shape {
        moveTo(117f, 308f)
        cubicTo(33f, 301f, 40f, 129f, 97f, 102f)
    }

    init { tag = "atlas-function-parietal-secretion-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> locate(c, t)
            1 -> { cellPlate(c); signal(c, t); cellLabels(c) }
            2 -> { cellPlate(c); exchange(c, t); cellLabels(c) }
            3 -> { cellPlate(c, HealthAtlasGastricAcidMotion.lumen(t)); secrete(c, t); cellLabels(c) }
            4 -> feedback(c, t)
        }
    }

    private fun locate(c: Canvas, t: Float) {
        stomachPlate(c)
        for (i in 0..5) {
            val x = 116f + 10f * i
            line(c, x, 147f - 6f * i, x + 4f, 144f - 6f * i, guide, 1f)
            line(c, x, 156f + 16f * i, x + 4f, 163f + 16f * i, guide, 1f)
        }
        ink(cream); paint.shader = glandFill; c.drawPath(gland, paint); paint.shader = null
        stroke(c, gland, tissueEdge, 1.5f)
        for (i in 0..4) {
            glandCell(c, 226f - i * 1.7f, 156f + 21f * i, false)
            glandCell(c, 268f + 1.6f * (i % 2), 157f + 21f * i, i == 1)
        }
        glandCell(c, 232f, 261f, false)
        glandCell(c, 251f, 271f, false)
        glandCell(c, 271f, 255f, false)
        fill(c, glandSpace, lumenFill, lumenEdge)

        val p = HealthAtlasGastricAcidMotion.locate(t)
        ink(focus, 1.4f); c.drawCircle(109f, 151f, 9f + 3f * (1f - p), paint)
        at(locatorTrack, p) { x, y -> disc(c, x, y, 3.4f, focus, cream) }
        ink(focus, 1.6f); c.drawCircle(270f, 178f, 15f + 3f * wave(p * .5f), paint)
        callout(c, R.string.health_atlas_gastric_acid_story_stomach, 77f, 58f, 124f,
            78f, 65f, 83f, 118f)
        callout(c, R.string.health_atlas_gastric_acid_story_gastric_gland, 255f, 76f, 130f,
            251f, 83f, 236f, 127f)
        callout(c, R.string.health_atlas_gastric_acid_story_parietal_cell, 268f, 315f, 143f,
            306f, 299f, 278f, 181f)
    }

    private fun stomachPlate(c: Canvas) {
        ink(cream); paint.shader = stomachFill; c.drawPath(stomach, paint); paint.shader = null
        stroke(c, stomach, tissueEdge, 2f)
        stroke(c, folds, 0xfff9d6c5, 4.3f)
        stroke(c, folds, rose, 1.15f)
    }

    private fun glandCell(c: Canvas, x: Float, y: Float, selected: Boolean) {
        oval(c, x - 11f, y - 10f, x + 11f, y + 10f,
            if (selected) 0xfff1b59e else 0xffebc4c1, if (selected) tissueEdge else rose)
        oval(c, x - 3f, y - 4f, x + 4f, y + 3f, 0xffbe89a9, violet)
    }

    private fun cellPlate(c: Canvas, acidity: Float = 0f) {
        stroke(c, vessel, 0xffa76379, 22f)
        stroke(c, vessel, 0xffecc2c6, 17f)
        oval(c, 29f, 110f, 41f, 117f, rose, tissueEdge)
        oval(c, 33f, 161f, 45f, 169f, rose, tissueEdge)
        oval(c, 42f, 212f, 54f, 220f, rose, tissueEdge)
        oval(c, 40f, 239f, 52f, 246f, rose, tissueEdge)

        ink(cream); paint.shader = cellFill; c.drawPath(cell, paint); paint.shader = null
        stroke(c, cell, tissueEdge, 2f)
        oval(c, 133f, 204f, 183f, 249f, nucleusFill, violet)
        disc(c, 156f, 227f, 5f, 0xffa46f98, violet)
        mitochondrion(c, 130f, 142f, -58f)
        mitochondrion(c, 157f, 99f, -24f)
        mitochondrion(c, 235f, 116f, 27f)
        mitochondrion(c, 224f, 241f, -37f)
        mitochondrion(c, 113f, 203f, 64f)

        ink(lumenFill); c.drawPath(canaliculus, paint)
        if (acidity > 0f) {
            ink(0xffe5a07b)
            paint.alpha = (156f * acidity).toInt()
            c.drawPath(canaliculus, paint)
        }
        stroke(c, canaliculus, lumenEdge, 1.65f)
        for (i in 0..3) {
            val x = 136f + i * 7f
            line(c, x, 189f + i * 1.6f, x + 2f, 184f + i * 1.6f, lumenEdge, 1.1f)
        }
        for (i in 0..5) {
            val x = 231f + i * 7f
            line(c, x, 183f + i * 1.35f, x + 1f, 178f + i * 1.35f, lumenEdge, 1.1f)
        }
    }

    private fun mitochondrion(c: Canvas, x: Float, y: Float, angle: Float) {
        c.save()
        c.rotate(angle, x, y)
        oval(c, x - 12f, y - 4f, x + 12f, y + 4f, 0xffefc2a1, tissueEdge)
        for (i in -1..1) line(c, x + i * 5f - 1f, y - 2f, x + i * 5f + 1f, y + 2f, tissueEdge, 1f)
        c.restore()
    }

    private fun cellLabels(c: Canvas) {
        callout(c, R.string.health_atlas_gastric_acid_story_apical_canaliculus, 120f, 46f, 168f,
            127f, 54f, 160f, 124f)
        callout(c, R.string.health_atlas_gastric_acid_story_blood_side, 78f, 303f, 134f,
            91f, 286f, 109f, 225f)
        callout(c, R.string.health_atlas_gastric_acid_story_gland_lumen, 285f, 303f, 124f,
            294f, 286f, 303f, 252f)
    }

    private fun signal(c: Canvas, t: Float) {
        val p = HealthAtlasGastricAcidMotion.histamine(t)
        val q = HealthAtlasGastricAcidMotion.recruit(t)
        oval(c, 55f, 148f, 75f, 179f, 0xffddc2d4, violet)
        disc(c, 64f, 163f, 4f, violet)
        rounded(c, 93f, 159f, 103f, 177f, 4f, violet)
        if (p < .99f) {
            disc(c, 75f + 22f * p, 158f + 10f * p, 3.6f, focus, cream)
            disc(c, 72f + 21f * p, 169f + 3f * p, 2.6f, focus, cream)
        } else {
            disc(c, 96f, 167f, 3.6f, focus, cream)
        }
        vesicle(c, 198f + 18f * q, 103f + 47f * q, q)
        vesicle(c, 245f - 5f * q, 131f + 20f * q, q)
        callout(c, R.string.health_atlas_gastric_acid_story_histamine, 69f, 70f, 119f,
            70f, 77f, 81f, 153f)
        callout(c, R.string.health_atlas_gastric_acid_story_pump, 249f, 47f, 120f,
            253f, 55f, 240f, 149f)
    }

    private fun vesicle(c: Canvas, x: Float, y: Float, fraction: Float) {
        if (fraction < .92f) disc(c, x, y, 7f * (1f - fraction * .55f), cream, violet)
        pump(c, x, y)
    }

    private fun pump(c: Canvas, x: Float, y: Float) {
        rounded(c, x - 6f, y - 3.8f, x + 6f, y + 3.8f, 3f, violet)
        line(c, x - 1.7f, y, x + 1.7f, y, cream, 1.2f)
    }

    private fun exchange(c: Canvas, t: Float) {
        val p = HealthAtlasGastricAcidMotion.exchange(t)
        // The two lanes separate the directions through one pump for legibility.
        rounded(c, 202f, 145f, 231f, 155f, 4f, 0xffe8d5e5)
        pump(c, 216f, 150f)
        arrow(c, 207f, 117f, 207f, 172f, acid)
        arrow(c, 226f, 172f, 226f, 117f, potassium)
        ion(c, 207f, 117f + 55f * p, acid)
        ion(c, 226f, 172f - 55f * p, potassium)
        callout(c, R.string.health_atlas_gastric_acid_story_pump, 278f, 47f, 124f,
            260f, 55f, 218f, 145f)
        key(c, R.string.health_atlas_gastric_acid_story_proton, 99f, acid)
        key(c, R.string.health_atlas_gastric_acid_story_potassium, 257f, potassium)
    }

    private fun secrete(c: Canvas, t: Float) {
        val p = HealthAtlasGastricAcidMotion.chloride(t)
        val flow = HealthAtlasGastricAcidMotion.lumen(t)
        pump(c, 216f, 150f)
        rounded(c, 201f, 177f, 214f, 185f, 2f, chloride)
        line(c, 208f, 179f, 208f, 183f, cream, 1.2f)
        arrow(c, 208f, 219f, 208f, 170f, chloride)
        ion(c, 208f, 219f - 49f * p, chloride)
        arrow(c, 306f, 124f, 306f, 91f, lumenEdge)
        for (i in 0..3) {
            val f = (flow * 1.16f - .15f * i).coerceIn(0f, 1f)
            if (f > .01f && f < .98f) {
                at(secretionTrack, f) { x, y ->
                    ion(c, x, y + if (i % 2 == 0) -4f else 4f, if (i % 2 == 0) acid else chloride)
                }
            }
        }
        callout(c, R.string.health_atlas_gastric_acid_story_to_stomach, 272f, 47f, 145f,
            288f, 55f, 304f, 87f)
        key(c, R.string.health_atlas_gastric_acid_story_proton, 99f, acid)
        key(c, R.string.health_atlas_gastric_acid_story_chloride, 257f, chloride)
    }

    private fun feedback(c: Canvas, t: Float) {
        val p = HealthAtlasGastricAcidMotion.feedback(t)
        val output = HealthAtlasGastricAcidMotion.output(t)
        c.save()
        c.translate(73f, -44f)
        c.scale(.76f, .76f)
        stomachPlate(c)
        for (i in 0..3) disc(c, 82f + i * 10f, 194f - (i % 2) * 11f, 3.2f, acid, cream)
        c.restore()
        callout(c, R.string.health_atlas_gastric_acid_story_stomach_acid, 266f, 84f, 156f,
            225f, 90f, 166f, 100f)
        arrow(c, 143f, 137f, 143f, 168f, teal)
        disc(c, 143f, 139f + 27f * p, 4f, teal, cream)
        label(c, R.string.health_atlas_gastric_acid_story_somatostatin, 219f, 178f, 151f)
        disc(c, 143f, 174f, 4f, teal, cream)
        line(c, 143f, 181f, 143f, 224f, teal, 1.65f)
        line(c, 134f, 224f, 152f, 224f, teal, 2f + p * 2f)
        if (p > .3f) disc(c, 143f, 181f + 40f * ((p - .3f) / .7f), 4f, teal, cream)
        label(c, R.string.health_atlas_gastric_acid_story_gastrin, 219f, 251f, 145f)
        disc(c, 143f, 247f, 3f + 3f * output, focus, cream)
        arrow(c, 143f, 255f, 143f, 296f, focus)
        disc(c, 143f, 291f - 33f * output, 2f + 3f * output, focus, cream)
        disc(c, 143f, 308f, 3f + 4f * output, acid, cream)
        label(c, R.string.health_atlas_gastric_acid_story_output, 219f, 312f, 145f)
        line(c, 128f, 308f, 117f, 308f, acid, 1.4f)
        stroke(c, feedbackReturn, acid, 1f + output)
        line(c, 97f, 102f, 89f, 102f, acid, 1.5f)
        line(c, 97f, 102f, 93f, 109f, acid, 1.5f)
    }

    private fun key(c: Canvas, @StringRes res: Int, x: Float, color: Long) {
        ion(c, x - 62f, 337f, color)
        label(c, res, x, 342f, 111f)
    }

    private fun ion(c: Canvas, x: Float, y: Float, color: Long) {
        if (color == chloride) {
            rounded(c, x - 3.6f, y - 3.6f, x + 3.6f, y + 3.6f, 1f, color)
            line(c, x - 1.5f, y, x + 1.5f, y, cream, 1.1f)
        } else {
            disc(c, x, y, 4f, color, cream)
            if (color == potassium) disc(c, x, y, 1.25f, cream)
        }
    }

    private fun callout(
        c: Canvas, @StringRes res: Int, x: Float, y: Float, w: Float,
        lx: Float, ly: Float, tx: Float, ty: Float,
    ) {
        line(c, lx, ly, tx, ty, guide, 1.1f)
        disc(c, tx, ty, 1.7f, guide)
        label(c, res, x, y, w)
    }

    private fun shape(build: Path.() -> Unit) = Path().apply(build)

    private fun fill(c: Canvas, path: Path, color: Long, edge: Long) {
        ink(color); c.drawPath(path, paint)
        stroke(c, path, edge, 1.35f)
    }
}
