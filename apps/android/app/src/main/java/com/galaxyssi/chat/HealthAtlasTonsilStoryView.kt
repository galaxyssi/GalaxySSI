package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader

internal object HealthAtlasTonsilMotion {
    fun adenoidFocus(t: Float) = 1f - ease(t, .18f, .55f)
    fun palatineFocus(t: Float) = ease(t, .32f, .69f)
    fun cryptScale(t: Float) = 1f + .18f * ease(t, .08f, .80f)
    fun cryptTrace(t: Float) = ease(t, .18f, .88f)
    fun encounter(t: Float, lag: Float = 0f) = ease(t - lag, .06f, .87f)
    fun uptake(t: Float) = ease(t, .24f, .83f)
    fun contact(t: Float) = ease(t, .10f, .66f)
    fun signal(t: Float) = ease(t, .57f, .86f)

    private fun ease(t: Float, start: Float, end: Float): Float {
        val p = ((HealthAtlasFunctionStory.safePhase(t) - start) / (end - start)).coerceIn(0f, 1f)
        return p * p * (3f - 2f * p)
    }
}

internal class HealthAtlasTonsilStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.TONSILLAR_SAMPLING) {
    private val contour = 0xff855d67
    private val guide = 0xff526c71
    private val palatine = 0xff8f4b66
    private val adenoid = 0xff6c557e
    private val lining = 0xffefb7a5
    private val lymphEdge = 0xffa9788c
    private val amber = 0xff9e601d
    private val headShade = shade(46f, 316f, 0xfff7dfcc, 0xffd8a69d)
    private val airwayShade = shade(95f, 288f, 0xfffcfaf0, 0xffd4e5e4)
    private val tissueShade = shade(110f, 301f, 0xfff5d9df, 0xffdbadc1)
    private val follicleShade = shade(155f, 282f, 0xfff3d3df, 0xffbf8ba9)

    // Near-side palatine tonsil is projected onto the cutaway, lateral to the tongue.
    private val head = shape {
        moveTo(101f, 315f)
        cubicTo(103f, 278f, 109f, 267f, 89f, 254f)
        cubicTo(73f, 249f, 58f, 246f, 56f, 232f)
        quadTo(54f, 223f, 58f, 215f)
        quadTo(45f, 210f, 54f, 203f)
        quadTo(44f, 197f, 51f, 191f)
        quadTo(58f, 184f, 56f, 173f)
        cubicTo(38f, 174f, 31f, 168f, 37f, 159f)
        cubicTo(44f, 149f, 55f, 137f, 58f, 125f)
        cubicTo(57f, 87f, 82f, 53f, 119f, 47f)
        cubicTo(184f, 31f, 226f, 69f, 229f, 123f)
        cubicTo(233f, 170f, 212f, 199f, 199f, 228f)
        cubicTo(187f, 257f, 185f, 283f, 205f, 315f)
        quadTo(153f, 328f, 101f, 315f)
        close()
    }
    private val airway = shape {
        moveTo(48f, 164f)
        cubicTo(63f, 148f, 62f, 131f, 79f, 121f)
        cubicTo(96f, 109f, 129f, 104f, 153f, 111f)
        cubicTo(184f, 121f, 182f, 154f, 176f, 180f)
        cubicTo(171f, 204f, 172f, 230f, 170f, 251f)
        quadTo(168f, 271f, 169f, 292f)
        lineTo(151f, 293f)
        cubicTo(151f, 263f, 149f, 246f, 137f, 226f)
        cubicTo(125f, 217f, 99f, 221f, 76f, 212f)
        quadTo(65f, 206f, 53f, 202f)
        cubicTo(74f, 192f, 101f, 183f, 130f, 183f)
        quadTo(145f, 187f, 151f, 176f)
        quadTo(123f, 158f, 83f, 166f)
        quadTo(66f, 171f, 48f, 164f)
        close()
    }
    private val palate = shape {
        moveTo(64f, 177f)
        cubicTo(93f, 166f, 127f, 160f, 148f, 169f)
        quadTo(158f, 174f, 153f, 184f)
        quadTo(148f, 185f, 143f, 180f)
        cubicTo(126f, 169f, 87f, 174f, 64f, 181f)
        close()
    }
    private val tongue = shape {
        moveTo(70f, 207f)
        cubicTo(94f, 201f, 120f, 188f, 137f, 206f)
        quadTo(145f, 214f, 149f, 235f)
        cubicTo(133f, 221f, 92f, 234f, 70f, 207f)
        close()
    }
    private val nasalRidges = shape {
        moveTo(74f, 146f); cubicTo(86f, 133f, 110f, 128f, 136f, 130f)
        moveTo(63f, 156f); cubicTo(85f, 145f, 111f, 145f, 141f, 143f)
        moveTo(78f, 159f); quadTo(107f, 152f, 128f, 153f)
    }
    private val adenoidPatch = shape {
        moveTo(145f, 110f)
        quadTo(165f, 105f, 177f, 121f)
        quadTo(184f, 133f, 178f, 147f)
        quadTo(170f, 149f, 170f, 140f)
        quadTo(162f, 141f, 164f, 133f)
        quadTo(155f, 134f, 157f, 125f)
        quadTo(145f, 125f, 145f, 110f)
        close()
    }

    private val smallCrypt = shape { traceSmallCrypt() }
    private val smallCryptTrack = track(smallCrypt)
    private val palatineCut = shape {
        moveTo(36f, 135f); quadTo(62f, 125f, 84f, 134f)
        traceSmallCrypt(join = true)
        quadTo(134f, 124f, 154f, 136f)
        cubicTo(173f, 191f, 150f, 244f, 102f, 248f)
        cubicTo(57f, 252f, 22f, 207f, 36f, 135f)
        close()
    }
    private val folds = shape { traceFolds() }
    private val adenoidCut = shape {
        traceFolds()
        cubicTo(335f, 186f, 346f, 230f, 298f, 244f)
        cubicTo(242f, 262f, 190f, 229f, 199f, 135f)
        close()
    }

    private val cryptSurface = shape { traceCrypt() }
    private val surfaceTrack = track(cryptSurface)
    private val cryptSection = shape {
        traceCrypt()
        cubicTo(338f, 182f, 331f, 256f, 299f, 279f)
        cubicTo(272f, 303f, 217f, 303f, 175f, 296f)
        cubicTo(132f, 300f, 83f, 301f, 52f, 277f)
        cubicTo(26f, 255f, 24f, 170f, 34f, 116f)
        close()
    }
    private val approachTrack = track(shape {
        moveTo(87f, 74f)
        cubicTo(121f, 69f, 157f, 99f, 174f, 136f)
        quadTo(187f, 170f, 181f, 201f)
    })
    private val epithelialSurface = shape { traceLining() }
    private val epithelialTrack = track(epithelialSurface)
    private val localTissue = shape {
        traceLining()
        cubicTo(332f, 212f, 338f, 261f, 308f, 290f)
        cubicTo(274f, 308f, 209f, 299f, 178f, 303f)
        cubicTo(133f, 298f, 83f, 307f, 49f, 289f)
        cubicTo(24f, 270f, 21f, 208f, 29f, 132f)
        close()
    }
    private val pickupTrack = track(shape {
        moveTo(161f, 95f)
        cubicTo(167f, 139f, 151f, 161f, 139f, 195f)
        quadTo(135f, 206f, 129f, 224f)
    })
    private val highlight = Path()
    private val process = Path()

    init { tag = "atlas-function-tonsillar-sampling-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> locate(c, t)
            1 -> compare(c, t)
            2 -> encounter(c, t)
            3 -> cellular(c, t, present = false)
            else -> cellular(c, t, present = true)
        }
    }

    private fun locate(c: Canvas, t: Float) {
        pane(c, head, headShade)
        for (i in 0..4) {
            val x = 190f - i * 1.4f
            val y = 210f + i * 19f
            oval(c, x - 7f, y, x + 9f, y + 15f, 0xffedcfb7, 0xffbf9381)
        }
        pane(c, airway, airwayShade)
        stroke(c, nasalRidges, 0xffb1797d, 1.5f)
        pane(c, palate, 0xffe6af96)
        pane(c, tongue, 0xffd598a0)
        line(c, 64f, 121f, 80f, 119f, contour, 1.3f)
        line(c, 53f, 164f, 61f, 163f, contour, 1.3f)
        line(c, 61f, 202f, 75f, 199f, cream, 2.6f)
        pane(c, adenoidPatch, 0xffad91b5, adenoid)
        oval(c, 141f, 181f, 158f, 204f, 0xffcd8ba4, palatine)
        for (i in 0..2) disc(c, 146f + i * 3f, 188f + i * 4f, 1.05f, palatine)

        focus(c, 165f, 125f, 22f, adenoid, HealthAtlasTonsilMotion.adenoidFocus(t))
        focus(c, 150f, 192f, 15f, palatine, HealthAtlasTonsilMotion.palatineFocus(t))
        label(c, R.string.health_atlas_tonsil_story_pharyngeal, 278f, 84f, 144f)
        label(c, R.string.health_atlas_tonsil_story_adenoids, 278f, 100f, 135f)
        leader(c, 278f, 107f, 236f, 117f, 167f, 125f)
        label(c, R.string.health_atlas_tonsil_story_palatine, 278f, 217f, 146f)
        leader(c, 278f, 203f, 230f, 192f, 150f, 192f)
    }

    private fun compare(c: Canvas, t: Float) {
        val scale = HealthAtlasTonsilMotion.cryptScale(t)
        c.save()
        c.scale(scale, scale, 94f, 134f)
        pane(c, palatineCut, tissueShade)
        follicle(c, 65f, 178f, 15f, 21f)
        follicle(c, 129f, 181f, 17f, 25f)
        follicle(c, 99f, 227f, 23f, 12f)
        stroke(c, smallCrypt, palatine, 6f)
        stroke(c, smallCrypt, cream, 3.5f)
        highlight.rewind()
        if (smallCryptTrack.getSegment(0f, smallCryptTrack.length * HealthAtlasTonsilMotion.cryptTrace(t),
                highlight, true)) {
            stroke(c, highlight, palatine, 2.4f)
        }
        c.restore()

        pane(c, adenoidCut, tissueShade, adenoid)
        follicle(c, 225f, 179f, 14f, 18f)
        follicle(c, 274f, 181f, 19f, 23f)
        follicle(c, 306f, 217f, 14f, 13f)
        follicle(c, 248f, 221f, 20f, 13f)
        stroke(c, folds, adenoid, 5f)
        stroke(c, folds, lining, 2.7f)

        label(c, R.string.health_atlas_tonsil_story_crypt, 94f, 78f, 150f)
        leader(c, 94f, 85f, 94f, 111f, 94f, 138f)
        label(c, R.string.health_atlas_tonsil_story_folds, 267f, 78f, 155f)
        leader(c, 267f, 85f, 267f, 103f, 250f, 130f)
        label(c, R.string.health_atlas_tonsil_story_palatine, 94f, 289f, 155f)
        label(c, R.string.health_atlas_tonsil_story_adenoids, 267f, 289f, 155f)
    }

    private fun encounter(c: Canvas, t: Float) {
        pane(c, cryptSection, tissueShade)
        follicle(c, 81f, 170f, 25f, 34f)
        follicle(c, 104f, 246f, 34f, 32f)
        follicle(c, 254f, 234f, 40f, 39f)
        follicle(c, 282f, 155f, 22f, 25f)
        epithelium(c, cryptSurface, surfaceTrack, 44)

        val f = HealthAtlasTonsilMotion.encounter(t)
        at(approachTrack, HealthAtlasTonsilMotion.encounter(t, .24f) * .56f) { x, y ->
            antigen(c, x + 18f, y - 10f, 2.5f, 0xffbc9463)
        }
        at(approachTrack, f) { x, y -> antigen(c, x, y, 5.2f) }
        antigenKey(c)
        label(c, R.string.health_atlas_tonsil_story_lumen, 265f, 80f, 147f)
        leader(c, 248f, 87f, 232f, 94f, 207f, 111f)
        label(c, R.string.health_atlas_tonsil_story_lymphoid, 258f, 329f, 153f)
        leader(c, 258f, 315f, 258f, 295f, 258f, 264f)
    }

    private fun cellular(c: Canvas, t: Float, present: Boolean) {
        pane(c, localTissue, tissueShade)
        follicle(c, 284f, 236f, 29f, 34f)
        for (i in 0..4) {
            val x = 52f + i * 11f
            disc(c, x, 239f + (i % 3) * 12f, 2.3f, lymphEdge)
        }
        epithelium(c, epithelialSurface, epithelialTrack, 34, 16f)

        val reach = if (present) HealthAtlasTonsilMotion.contact(t) else 0f
        val tip = 172f + 33f * reach
        presenter(c, tip)
        if (present) {
            oval(c, 204f, 203f, 250f, 249f, 0xffbbdcd7, teal)
            oval(c, 214f, 210f, 243f, 239f, 0xff669e98, teal)
            antigen(c, tip - 1.5f, 225f, 3.6f)
            val glow = HealthAtlasTonsilMotion.signal(t)
            if (glow > 0f) {
                ink(teal, 1.45f)
                paint.alpha = (200f * (1f - .65f * glow)).toInt()
                val spread = 6f + 10f * glow
                c.drawArc(204f - spread, 225f - spread, 204f + spread, 225f + spread, 221f, 56f, false, paint)
                c.drawArc(204f - spread, 225f - spread, 204f + spread, 225f + spread, 83f, 56f, false, paint)
            }
            label(c, R.string.health_atlas_tonsil_story_t_cell, 241f, 331f, 104f)
            leader(c, 241f, 316f, 241f, 280f, 227f, 245f)
        } else {
            val f = HealthAtlasTonsilMotion.uptake(t)
            at(pickupTrack, f) { x, y -> antigen(c, x, y, 5f - 1.3f * f) }
            antigenKey(c)
        }

        label(c, R.string.health_atlas_tonsil_story_lining, 252f, 95f, 166f)
        leader(c, 252f, 103f, 252f, 121f, 237f, 143f)
        label(c, R.string.health_atlas_tonsil_story_dendritic, 104f, 331f, 148f)
        leader(c, 104f, 315f, 104f, 273f, 124f, 242f)
    }

    private fun presenter(c: Canvas, tip: Float) {
        process.rewind()
        process.moveTo(105f, 223f); process.quadTo(95f, 216f, 90f, 205f)
        process.moveTo(115f, 213f); process.quadTo(111f, 201f, 114f, 187f)
        process.moveTo(132f, 215f); process.quadTo(145f, 208f, 151f, 198f)
        process.moveTo(108f, 234f); process.quadTo(98f, 243f, 92f, 243f)
        process.moveTo(124f, 238f); process.quadTo(126f, 253f, 136f, 259f)
        process.moveTo(145f, 231f); process.quadTo(155f, 234f, 162f, 244f)
        process.moveTo(142f, 222f); process.quadTo(158f, 215f, tip, 225f)
        stroke(c, process, violet, 5.6f)
        stroke(c, process, 0xffcfb0d4, 3.4f)
        oval(c, 103f, 210f, 149f, 244f, 0xffcfb0d4, violet)
        oval(c, 113f, 216f, 134f, 231f, 0xff9975a6, violet)
    }

    private fun focus(c: Canvas, x: Float, y: Float, radius: Float, color: Long, strength: Float) {
        if (strength <= 0f) return
        ink(color, 1.65f)
        paint.alpha = (215f * strength).toInt()
        c.drawCircle(x, y, radius + 4f * (1f - strength), paint)
    }

    private fun antigenKey(c: Canvas) {
        antigen(c, 43f, 40f, 4.8f)
        label(c, R.string.health_atlas_tonsil_story_antigen, 120f, 45f, 130f)
    }

    private fun antigen(c: Canvas, x: Float, y: Float, r: Float, edge: Long = amber) {
        c.save()
        c.rotate(-27f, x, y)
        oval(c, x - r, y - .67f * r, x + r, y + .67f * r, 0xffecc17e, edge)
        c.restore()
    }

    private fun epithelium(c: Canvas, edge: Path, measure: PathMeasure, count: Int, width: Float = 9f) {
        stroke(c, edge, contour, width + 2f)
        stroke(c, edge, lining, width)
        for (i in 1 until count) {
            at(measure, i.toFloat() / count) { x, y ->
                disc(c, x, y, 1.35f, palatine)
                if (width > 10f) disc(c, x + 2f, y + 4f, 1.15f, palatine)
            }
        }
    }

    private fun follicle(c: Canvas, x: Float, y: Float, rx: Float, ry: Float) {
        oval(c, x - rx, y - ry, x + rx, y + ry, follicleShade, lymphEdge)
        oval(c, x - rx * .60f, y - ry * .64f, x + rx * .70f, y + ry * .43f, 0xfff3d7df, 0xffcc9cb2)
        for (i in 0..5) {
            val dx = (i % 3 - 1) * rx * .36f + i / 3 * 2f
            val dy = (i / 3 - .5f) * ry * .74f + i % 2 * 2f
            disc(c, x + dx, y + dy, 1.25f, lymphEdge)
        }
    }

    private fun leader(c: Canvas, x: Float, y: Float, ex: Float, ey: Float, tx: Float, ty: Float) {
        line(c, x, y, ex, ey, guide, 1.05f)
        line(c, ex, ey, tx, ty, guide, 1.05f)
        disc(c, tx, ty, 1.8f, guide, cream)
    }

    private fun pane(c: Canvas, path: Path, shader: Shader, edge: Long = contour) {
        ink(cream); paint.shader = shader; c.drawPath(path, paint); paint.shader = null
        stroke(c, path, edge, 1.5f)
    }

    private fun pane(c: Canvas, path: Path, fill: Long, edge: Long = contour) {
        ink(fill); c.drawPath(path, paint)
        stroke(c, path, edge, 1.5f)
    }

    private fun Path.traceSmallCrypt(join: Boolean = false) {
        if (!join) moveTo(84f, 134f)
        cubicTo(89f, 156f, 92f, 165f, 83f, 178f)
        quadTo(81f, 186f, 94f, 182f)
        cubicTo(95f, 195f, 101f, 208f, 106f, 207f)
        cubicTo(113f, 203f, 105f, 182f, 106f, 167f)
        quadTo(106f, 145f, 114f, 133f)
    }

    private fun Path.traceFolds() {
        moveTo(199f, 135f)
        quadTo(216f, 110f, 230f, 131f); quadTo(236f, 146f, 243f, 137f)
        quadTo(255f, 109f, 269f, 128f); quadTo(273f, 142f, 283f, 138f)
        quadTo(301f, 114f, 314f, 133f); quadTo(319f, 141f, 325f, 141f)
    }

    private fun Path.traceCrypt() {
        moveTo(34f, 116f)
        cubicTo(74f, 98f, 127f, 102f, 143f, 118f)
        cubicTo(157f, 134f, 151f, 177f, 164f, 201f)
        cubicTo(172f, 221f, 192f, 222f, 202f, 194f)
        cubicTo(213f, 164f, 207f, 124f, 225f, 115f)
        quadTo(267f, 93f, 326f, 111f)
    }

    private fun Path.traceLining() {
        moveTo(29f, 132f)
        cubicTo(84f, 118f, 126f, 147f, 176f, 151f)
        cubicTo(229f, 156f, 259f, 126f, 330f, 134f)
    }

    private fun shape(build: Path.() -> Unit) = Path().apply(build)
}
