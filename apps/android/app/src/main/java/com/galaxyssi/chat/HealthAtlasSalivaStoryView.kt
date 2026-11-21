package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import androidx.annotation.StringRes

internal class HealthAtlasSalivaStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.SALIVA_SECRETION) {
    private val rose = 0xff9e6574
    private val guide = 0xff62666d
    private val water = 0xffb9e1e8
    private val fluid = 0xff397f95
    private val protein = 0xffe8bb64
    private val skin = shade(16f, 177f, 0xffffe8d8, 0xffedc0b2)
    private val cell = shade(-26f, 26f, 0xffffeadb, 0xffe9acac)
    private val head = shape {
        moveTo(103f, 177f)
        cubicTo(116f, 151f, 113f, 131f, 101f, 105f)
        cubicTo(80f, 58f, 100f, 19f, 143f, 14f)
        cubicTo(178f, 8f, 211f, 16f, 222f, 44f)
        cubicTo(227f, 56f, 222f, 63f, 228f, 72f)
        lineTo(243f, 91f); quadTo(248f, 97f, 238f, 99f)
        quadTo(224f, 99f, 234f, 108f)
        quadTo(246f, 113f, 239f, 119f)
        quadTo(246f, 124f, 238f, 130f)
        cubicTo(234f, 133f, 240f, 143f, 232f, 151f)
        cubicTo(219f, 163f, 177f, 144f, 165f, 177f)
        close()
    }
    private val mouth = shape {
        moveTo(171f, 126f)
        cubicTo(184f, 106f, 216f, 107f, 237f, 117f)
        cubicTo(235f, 131f, 223f, 142f, 205f, 144f)
        cubicTo(186f, 146f, 169f, 140f, 171f, 126f)
        close()
    }
    private val tongue = shape {
        moveTo(172f, 135f)
        cubicTo(184f, 126f, 196f, 121f, 218f, 125f)
        cubicTo(235f, 125f, 227f, 137f, 213f, 139f)
        quadTo(185f, 142f, 172f, 137f)
        close()
    }
    private val jaw = shape {
        moveTo(144f, 109f)
        cubicTo(148f, 132f, 152f, 146f, 177f, 151f)
        quadTo(202f, 155f, 225f, 144f)
    }
    private val parotidDuct = shape {
        moveTo(151f, 96f)
        cubicTo(171f, 96f, 190f, 96f, 198f, 114f)
    }
    private val cheekTrack = track(parotidDuct)
    private val mouthTrack = track(Path(parotidDuct).apply {
        cubicTo(204f, 118f, 212f, 118f, 225f, 120f)
    })
    private val acinarCell = shape {
        moveTo(9f, -5f)
        quadTo(26f, -15f, 40f, -24f)
        cubicTo(53f, -29f, 62f, -15f, 62f, 0f)
        cubicTo(62f, 15f, 53f, 29f, 40f, 24f)
        quadTo(26f, 15f, 9f, 5f)
        quadTo(7f, 0f, 9f, -5f)
        close()
    }
    private val lumen = shape {
        moveTo(330f, 254f); lineTo(171f, 254f)
        cubicTo(143f, 254f, 137f, 262f, 117f, 258f)
        cubicTo(101f, 254f, 97f, 277f, 115f, 276f)
        cubicTo(137f, 270f, 146f, 278f, 171f, 278f)
        lineTo(330f, 278f)
    }
    private val fluidTrack = track(shape {
        moveTo(83f, 267f); lineTo(111f, 267f); quadTo(136f, 267f, 168f, 265f)
    })
    private val proteinTrack = track(shape {
        moveTo(99f, 246f); quadTo(108f, 258f, 112f, 267f); quadTo(128f, 269f, 152f, 268f)
    })

    init { tag = "atlas-function-saliva-secretion-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        map(c, step, t)
        cutaway(c, step, t)
    }

    private fun map(c: Canvas, step: Int, t: Float) {
        ink(cream); paint.shader = skin; c.drawPath(head, paint); paint.shader = null
        stroke(c, head, rose, 1.4f)
        stroke(c, jaw, 0xffeed3b6, 9f)
        stroke(c, jaw, 0xffbf9277, 1.2f)
        oval(c, 111f, 57f, 139f, 90f, 0xffeab5a8, rose)
        oval(c, 117f, 62f, 131f, 81f, 0xffd8978e, rose)
        area(c, mouth, 0xffaf707b, rose)
        area(c, tongue, 0xffe6a0aa, rose)
        rounded(c, 191f, 110f, 218f, 114f, 2f, cream)
        gland(c, 151f, 100f, 12f, 0xffe9bd81)
        gland(c, 165f, 153f, 9f, 0xffd9abd0)
        gland(c, 207f, 144f, 5f, 0xffb7d4b0)
        stroke(c, parotidDuct, sienna, 4.5f)
        stroke(c, parotidDuct, cream, 2.4f)

        when (step) {
            0 -> stream(c, cheekTrack, t, 3, .88f, 2.3f)
            4 -> {
                label(c, R.string.health_atlas_saliva_story_cheek_opening, 296f, 101f, 112f)
                leader(c, 265f, 106f, 246f, 106f, 198f, 114f)
                disc(c, 198f, 114f, 4f, water, fluid)
                stream(c, mouthTrack, t, 4, 1f, 2.4f)
            }
        }
        label(c, R.string.health_atlas_saliva_story_parotid, 53f, 96f, 94f)
        leader(c, 72f, 102f, 108f, 102f, 137f, 104f)
        label(c, R.string.health_atlas_saliva_story_sublingual, 296f, 141f, 106f)
        leader(c, 251f, 146f, 235f, 146f, 213f, 144f)
        label(c, R.string.health_atlas_saliva_story_submandibular, 270f, 170f, 161f)
        leader(c, 209f, 162f, 190f, 162f, 173f, 157f)
    }

    private fun cutaway(c: Canvas, step: Int, t: Float) {
        rounded(c, 17f, 209f, 343f, 324f, 8f, 0xfff7e8df)
        label(c, R.string.health_atlas_saliva_story_example, 180f, 198f, 233f)
        rounded(c, 126f, 251f, 179f, 281f, 11f, 0xffe5bacb)
        for (angle in 60..300 step 60) {
            c.save()
            c.translate(111f, 267f)
            c.rotate(angle.toFloat())
            ink(cream); paint.shader = cell; c.drawPath(acinarCell, paint); paint.shader = null
            stroke(c, acinarCell, rose, 1.25f)
            oval(c, 39f, -9f, 54f, 9f, 0xffcaa6ce, violet)
            disc(c, 24f, -6f, 2.4f, protein, sienna)
            disc(c, 27f, 5f, 2f, protein, sienna)
            if (step == 1 && angle == 240) {
                molecule(c, 29f - 16f * t, 0f)
            }
            c.restore()
        }
        ductWall(c, 237f, 255f)
        ductWall(c, 277f, 295f)
        area(c, lumen, water, fluid)
        when (step) {
            0, 1 -> {
                callout(c, R.string.health_atlas_saliva_story_acinar_cells, 73f, 344f, 120f, 90f, 311f)
                label(c, R.string.health_atlas_saliva_story_duct, 261f, 342f, 150f)
                leader(c, 261f, 327f, 261f, 316f, 261f, 293f)
                if (step == 1) {
                    label(c, R.string.health_atlas_saliva_story_lumen, 174f, 225f, 81f)
                    leader(c, 174f, 230f, 165f, 244f, 151f, 263f)
                }
            }
            2 -> release(c, t)
            3 -> exchange(c, t)
            4 -> {
                ductFlow(c, t)
                label(c, R.string.health_atlas_saliva_story_to_mouth, 252f, 342f, 176f)
            }
        }
    }

    private fun ductWall(c: Canvas, top: Float, bottom: Float) {
        for (i in 0..6) {
            val x = 169f + 23f * i
            rounded(c, x, top, x + 22f, bottom, 4f, 0xffe5bacb)
            oval(c, x + 7f, top + 4f, x + 15f, bottom - 4f, 0xffc6a2cb, violet)
        }
    }

    private fun release(c: Canvas, t: Float) {
        stream(c, fluidTrack, t, 4, 1f, 2.25f)
        at(proteinTrack, t) { x, y -> molecule(c, x, y) }
        at(proteinTrack, (t + .5f) % 1f) { x, y -> molecule(c, x, y) }
        disc(c, 49f, 338f, 2.5f, fluid)
        label(c, R.string.health_atlas_saliva_story_fluid, 110f, 342f, 110f)
        molecule(c, 184f, 338f)
        label(c, R.string.health_atlas_saliva_story_proteins, 263f, 342f, 144f)
    }

    private fun exchange(c: Canvas, t: Float) {
        ductFlow(c, t)
        label(c, R.string.health_atlas_saliva_story_sodium_out, 221f, 226f, 97f)
        arrow(c, 209f, 262f, 220f, 232f, violet)
        disc(c, 209f + 11f * t, 262f - 30f * t, 3f, violet, cream)
        label(c, R.string.health_atlas_saliva_story_potassium_in, 283f, 317f, 110f)
        arrow(c, 284f, 300f, 273f, 270f, teal)
        disc(c, 284f - 11f * t, 300f - 30f * t, 3f, teal, cream)
    }

    private fun ductFlow(c: Canvas, t: Float) {
        for (i in 0..6) {
            val x = 173f + 152f * ((t + i / 7f) % 1f)
            disc(c, x, 265f, 2.4f, fluid)
            if (i % 3 == 0) molecule(c, x, 271f)
        }
    }

    private fun stream(c: Canvas, path: PathMeasure, t: Float, count: Int, end: Float, radius: Float) {
        for (i in 0 until count) {
            at(path, end * ((t + i.toFloat() / count) % 1f)) { x, y -> disc(c, x, y, radius, fluid, cream) }
        }
    }

    private fun molecule(c: Canvas, x: Float, y: Float) = disc(c, x, y, 3.3f, protein, sienna)

    private fun gland(c: Canvas, x: Float, y: Float, r: Float, color: Long) {
        oval(c, x - 1.6f * r, y - r, x + r, y + r, color, rose)
        for (i in -1..1) {
            val lobeX = x + .68f * i * r
            val lobeY = y - (if (i == 0) .55f else .27f) * r
            disc(c, lobeX, lobeY, r * .62f, color, rose)
            disc(c, lobeX - r * .12f, lobeY - r * .2f, r * .13f, cream)
        }
    }

    private fun callout(c: Canvas, @StringRes res: Int, x: Float, y: Float, w: Float, tx: Float, ty: Float) {
        leader(c, x, y - 16f, x, y - 19f, tx, ty)
        label(c, res, x, y, w)
    }

    private fun leader(c: Canvas, x: Float, y: Float, bx: Float, by: Float, tx: Float, ty: Float) {
        line(c, x, y, bx, by, guide, 1f)
        line(c, bx, by, tx, ty, guide, 1f)
        disc(c, tx, ty, 1.65f, guide)
    }

    private fun shape(build: Path.() -> Unit) = Path().apply(build)

    private fun area(c: Canvas, path: Path, fill: Long, edge: Long) {
        ink(fill); c.drawPath(path, paint)
        stroke(c, path, edge, 1.2f)
    }
}
