package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

internal object HealthAtlasSinusDrainageMotion {
    fun highlight(t: Float, group: Int): Float {
        val p = interval(t, group * .21f, group * .21f + .37f)
        return sin(PI.toFloat() * p).coerceAtLeast(0f)
    }

    fun heightReveal(t: Float) = ease(interval(t, .10f, .88f))

    fun secretion(t: Float, index: Int) = ease(interval(t, .07f + .21f * index, .42f + .21f * index))

    fun ciliumBend(t: Float, index: Int): Float {
        val angle = 2f * PI.toFloat() * (2.65f * phase(t) - index * .09f)
        return .35f + .65f * cos(angle)
    }

    fun ascent(t: Float, index: Int) = interval(t, .03f + .17f * index, .62f + .17f * index)

    fun exit(t: Float, index: Int) = ease(interval(t, .03f + .14f * index, .77f + .10f * index))

    private fun phase(t: Float) = if (t.isFinite()) t.coerceIn(0f, 1f) else 0f
    private fun interval(t: Float, start: Float, end: Float) = ((phase(t) - start) / (end - start)).coerceIn(0f, 1f)
    private fun ease(p: Float) = p * p * (3f - 2f * p)
}

internal class HealthAtlasSinusDrainageStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.SINUS_DRAINAGE) {
    private val contourInk = 0xff886762
    private val leaderInk = 0xff576e71
    private val channelInk = 0xff9b655e
    private val channelLight = 0xfffcdfc6
    private val liningInk = 0xff457970
    private val mucusInk = 0xff12695f
    private val mucusLight = 0xff9bc8b6
    private val faceFill = shade(64f, 281f, 0xfff8e8d7, 0xffe5b29e)
    private val boneFill = shade(66f, 290f, 0xffffead5, 0xffddb59a)
    private val cavityFill = shade(128f, 266f, 0xfff3f6e8, 0xffd6e9da)
    private val noseFill = shade(84f, 266f, 0xffffe9da, 0xffe8ad9c)
    private val tissueFill = shade(224f, 279f, 0xfff5d0b6, 0xffcb8b86)
    private val scratch = Path()
    private val position = FloatArray(2)
    private val tangent = FloatArray(2)

    private val front = Path().apply {
        moveTo(90f, 65f)
        cubicTo(48f, 64f, 25f, 92f, 24f, 130f)
        lineTo(24f, 158f)
        cubicTo(8f, 151f, 9f, 183f, 20f, 195f)
        quadTo(25f, 200f, 30f, 197f)
        cubicTo(35f, 235f, 51f, 252f, 71f, 269f)
        quadTo(90f, 282f, 109f, 269f)
        cubicTo(129f, 252f, 145f, 235f, 150f, 197f)
        quadTo(155f, 200f, 160f, 195f)
        cubicTo(171f, 183f, 172f, 151f, 156f, 158f)
        lineTo(156f, 130f)
        cubicTo(155f, 92f, 132f, 64f, 90f, 65f)
        close()
    }
    private val orbitFront = Path().apply {
        moveTo(33f, 144f)
        cubicTo(38f, 131f, 61f, 129f, 71f, 143f)
        cubicTo(77f, 156f, 69f, 166f, 57f, 167f)
        cubicTo(42f, 169f, 31f, 159f, 33f, 144f)
        close()
    }
    private val frontalFront = Path().apply {
        moveTo(86f, 124f)
        cubicTo(78f, 128f, 63f, 124f, 61f, 116f)
        cubicTo(60f, 108f, 66f, 103f, 71f, 105f)
        cubicTo(75f, 98f, 84f, 100f, 86f, 108f)
        quadTo(89f, 117f, 86f, 124f)
        close()
    }
    private val maxillaryFront = Path().apply {
        moveTo(35f, 179f)
        cubicTo(42f, 174f, 59f, 173f, 70f, 177f)
        cubicTo(77f, 182f, 70f, 212f, 60f, 222f)
        cubicTo(52f, 230f, 42f, 214f, 37f, 205f)
        quadTo(29f, 189f, 35f, 179f)
        close()
    }
    private val profile = Path().apply {
        moveTo(208f, 125f)
        cubicTo(208f, 91f, 228f, 72f, 261f, 71f)
        cubicTo(301f, 69f, 331f, 91f, 334f, 130f)
        cubicTo(338f, 163f, 327f, 184f, 315f, 204f)
        quadTo(307f, 219f, 313f, 273f)
        lineTo(254f, 273f)
        quadTo(259f, 257f, 253f, 247f)
        cubicTo(238f, 253f, 221f, 252f, 216f, 244f)
        quadTo(214f, 237f, 216f, 229f)
        quadTo(204f, 223f, 214f, 217f)
        quadTo(207f, 210f, 210f, 201f)
        cubicTo(190f, 203f, 191f, 194f, 198f, 183f)
        lineTo(212f, 159f)
        quadTo(218f, 150f, 211f, 144f)
        quadTo(208f, 140f, 208f, 125f)
        close()
    }
    private val noseProfile = Path().apply {
        moveTo(207f, 193f)
        cubicTo(217f, 171f, 235f, 157f, 254f, 158f)
        cubicTo(273f, 157f, 287f, 166f, 288f, 180f)
        quadTo(285f, 211f, 296f, 239f)
        lineTo(286f, 243f)
        cubicTo(277f, 224f, 278f, 205f, 268f, 199f)
        cubicTo(249f, 197f, 223f, 194f, 211f, 198f)
        quadTo(205f, 199f, 207f, 193f)
        close()
    }
    private val mouthProfile = Path().apply {
        moveTo(217f, 216f)
        cubicTo(235f, 202f, 262f, 202f, 274f, 218f)
        quadTo(280f, 230f, 281f, 240f)
        cubicTo(270f, 231f, 249f, 227f, 224f, 226f)
        quadTo(212f, 226f, 217f, 216f)
        close()
    }
    private val frontalProfile = Path().apply {
        moveTo(219f, 133f)
        cubicTo(214f, 122f, 218f, 109f, 225f, 106f)
        cubicTo(233f, 105f, 236f, 113f, 235f, 120f)
        quadTo(231f, 130f, 223f, 137f)
        close()
    }
    private val sphenoid = Path().apply {
        moveTo(258f, 149f)
        cubicTo(258f, 141f, 268f, 135f, 279f, 137f)
        cubicTo(290f, 138f, 293f, 146f, 287f, 153f)
        cubicTo(283f, 159f, 263f, 160f, 258f, 154f)
        close()
    }
    private val bone = Path().apply {
        moveTo(33f, 169f)
        cubicTo(37f, 143f, 44f, 140f, 49f, 117f)
        cubicTo(52f, 91f, 72f, 72f, 98f, 69f)
        cubicTo(129f, 64f, 160f, 67f, 186f, 77f)
        quadTo(209f, 86f, 222f, 82f)
        cubicTo(256f, 58f, 299f, 62f, 319f, 86f)
        cubicTo(336f, 105f, 324f, 147f, 325f, 176f)
        cubicTo(331f, 225f, 323f, 256f, 311f, 269f)
        cubicTo(296f, 283f, 252f, 279f, 226f, 274f)
        cubicTo(203f, 270f, 171f, 266f, 155f, 280f)
        cubicTo(140f, 293f, 115f, 292f, 102f, 276f)
        cubicTo(90f, 264f, 83f, 233f, 61f, 219f)
        cubicTo(42f, 207f, 27f, 194f, 33f, 169f)
        close()
    }
    private val orbitSection = Path().apply {
        moveTo(56f, 111f)
        cubicTo(66f, 84f, 103f, 77f, 130f, 79f)
        cubicTo(161f, 80f, 192f, 90f, 201f, 109f)
        quadTo(206f, 124f, 188f, 126f)
        cubicTo(149f, 119f, 87f, 119f, 64f, 129f)
        quadTo(51f, 129f, 56f, 111f)
        close()
    }
    private val maxillarySection = Path().apply {
        moveTo(54f, 158f)
        cubicTo(65f, 139f, 107f, 129f, 143f, 131f)
        cubicTo(165f, 131f, 194f, 132f, 204f, 144f)
        cubicTo(214f, 155f, 201f, 173f, 203f, 191f)
        cubicTo(207f, 224f, 186f, 256f, 150f, 265f)
        cubicTo(119f, 275f, 103f, 255f, 93f, 231f)
        cubicTo(84f, 210f, 47f, 187f, 54f, 158f)
        close()
    }
    private val nasalSection = Path().apply {
        moveTo(228f, 108f)
        cubicTo(239f, 87f, 272f, 77f, 293f, 88f)
        cubicTo(307f, 97f, 309f, 117f, 307f, 148f)
        lineTo(308f, 244f)
        cubicTo(309f, 262f, 290f, 268f, 267f, 264f)
        cubicTo(245f, 261f, 229f, 263f, 226f, 248f)
        cubicTo(225f, 230f, 231f, 210f, 230f, 190f)
        cubicTo(228f, 170f, 216f, 135f, 228f, 108f)
        close()
    }
    private val middleTurbinate = Path().apply {
        moveTo(224f, 124f)
        cubicTo(238f, 115f, 258f, 121f, 267f, 133f)
        cubicTo(277f, 145f, 275f, 158f, 266f, 161f)
        cubicTo(258f, 163f, 253f, 157f, 249f, 150f)
        quadTo(241f, 139f, 222f, 139f)
        close()
    }
    private val lowerTurbinate = Path().apply {
        moveTo(230f, 202f)
        cubicTo(247f, 194f, 267f, 201f, 276f, 213f)
        cubicTo(284f, 222f, 276f, 235f, 266f, 233f)
        cubicTo(252f, 231f, 252f, 218f, 228f, 220f)
        close()
    }
    private val outlet = Path().apply {
        moveTo(200f, 151f)
        cubicTo(207f, 146f, 215f, 145f, 220f, 153f)
        quadTo(225f, 163f, 239f, 171f)
    }
    private val outletEdges = Path().apply {
        moveTo(198f, 146f)
        cubicTo(208f, 140f, 219f, 142f, 224f, 150f)
        quadTo(230f, 160f, 241f, 166f)
        moveTo(202f, 156f)
        cubicTo(208f, 151f, 213f, 151f, 216f, 156f)
        quadTo(221f, 166f, 237f, 175f)
    }
    // One surface route is shown; the full sinus clears along multiple walls.
    private val ascentTrack = track(Path().apply {
        moveTo(121f, 254f)
        cubicTo(135f, 265f, 159f, 256f, 173f, 245f)
        cubicTo(191f, 229f, 198f, 211f, 197f, 191f)
        cubicTo(196f, 173f, 197f, 161f, 203f, 149f)
    })
    private val exitTrack = track(Path(outlet).apply {
        cubicTo(251f, 179f, 266f, 173f, 281f, 183f)
    })

    init { tag = "atlas-function-sinus-drainage-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> locate(c, t)
            1 -> crossSection(c, t, step)
            2 -> secretionDetail(c, t)
            3, 4 -> crossSection(c, t, step)
        }
    }

    private fun locate(c: Canvas, t: Float) {
        shaded(c, front, faceFill)
        for (side in 0..1) {
            c.save()
            if (side == 1) c.scale(-1f, 1f, 90f, 0f)
            area(c, orbitFront, 0xffeecbc0, contourInk)
            oval(c, 39f, 143f, 66f, 157f, 0xfffcf3e6, contourInk)
            disc(c, 53f, 150f, 4.8f, 0xff718b8a)
            disc(c, 53f, 150f, 2.1f, contourInk)
            sinus(c, frontalFront, 0xffbbd6e0, blue, HealthAtlasSinusDrainageMotion.highlight(t, 0))
            sinus(c, maxillaryFront, 0xffbadbc9, liningInk, HealthAtlasSinusDrainageMotion.highlight(t, 3))
            for (i in 0..2) {
                val x = 78f + (i % 2) * 3f
                val y = 139f + i * 8f
                oval(c, x - 5f, y - 4f, x + 5f, y + 4f, 0xffefd5a1, sienna)
            }
            disc(c, 84f, 202f, 2.7f, contourInk)
            c.restore()
        }
        scratch.rewind()
        scratch.moveTo(90f, 150f)
        scratch.quadTo(91f, 178f, 98f, 191f)
        scratch.quadTo(103f, 202f, 90f, 208f)
        scratch.moveTo(70f, 235f)
        scratch.quadTo(90f, 229f, 110f, 235f)
        scratch.quadTo(90f, 244f, 70f, 235f)
        stroke(c, scratch, contourInk, 1.35f)

        shaded(c, profile, faceFill)
        area(c, mouthProfile, 0xffe3a999, contourInk)
        area(c, noseProfile, 0xfff4cfb4, channelInk)
        scratch.rewind()
        scratch.moveTo(219f, 187f)
        scratch.cubicTo(234f, 174f, 256f, 171f, 273f, 177f)
        scratch.moveTo(232f, 190f)
        scratch.quadTo(258f, 181f, 278f, 188f)
        stroke(c, scratch, channelInk, 1.2f)
        sinus(c, frontalProfile, 0xffbbd6e0, blue, HealthAtlasSinusDrainageMotion.highlight(t, 0))
        for (i in 0..3) {
            val x = 231f + i * 6f
            val y = 149f - (i % 2) * 4f
            val radius = 4.3f + 1.5f * HealthAtlasSinusDrainageMotion.highlight(t, 1)
            disc(c, x, y, radius, 0xffefd5a1, sienna)
        }
        sinus(c, sphenoid, 0xffd7c8e2, violet, HealthAtlasSinusDrainageMotion.highlight(t, 2))

        leader(c, R.string.health_atlas_sinus_drainage_frontal, 81f, 47f, 142f, 81f, 55f, 81f, 88f, 75f, 111f)
        leader(c, R.string.health_atlas_sinus_drainage_maxillary_pair, 90f, 304f, 150f, 53f, 290f, 41f, 256f, 57f, 200f)
        leader(c, R.string.health_atlas_sinus_drainage_ethmoid, 230f, 47f, 102f, 230f, 55f, 243f, 93f, 242f, 145f)
        leader(c, R.string.health_atlas_sinus_drainage_sphenoid, 269f, 304f, 150f, 312f, 291f, 320f, 180f, 279f, 149f)
        label(c, R.string.health_atlas_sinus_drainage_front_view, 90f, 335f, 136f)
        label(c, R.string.health_atlas_sinus_drainage_side_view, 269f, 335f, 136f)
    }

    private fun sectionArt(c: Canvas) {
        shaded(c, bone, boneFill)
        area(c, orbitSection, 0xfff7ddcf, contourInk)
        oval(c, 99f, 84f, 150f, 116f, 0xfff8ebe1, 0xffbd9288)
        oval(c, 118f, 90f, 142f, 110f, 0xffd9b7ac, 0xffbd9288)
        shaded(c, nasalSection, noseFill)
        area(c, middleTurbinate, 0xffdba693, channelInk)
        area(c, lowerTurbinate, 0xffdba693, channelInk)
        shaded(c, maxillarySection, cavityFill, liningInk)
        stroke(c, outlet, channelLight, 10f)
        stroke(c, outletEdges, channelInk, 1.15f)
    }

    private fun crossSection(c: Canvas, t: Float, step: Int) {
        sectionArt(c)
        when (step) {
            1 -> heightCue(c, t)
            3 -> rise(c, t)
            4 -> enterNose(c, t)
        }
        label(c, R.string.health_atlas_sinus_drainage_maxillary, 125f, 191f, 108f)
        leader(c, R.string.health_atlas_sinus_drainage_opening, 212f, 42f, 190f, 212f, 51f, 211f, 113f, 205f, 149f)
        leader(c, R.string.health_atlas_sinus_drainage_floor, 105f, 318f, 160f, 105f, 302f, 110f, 290f, 137f, 266f)
        leader(c, R.string.health_atlas_sinus_drainage_nasal_passage, 276f, 318f, 150f, 283f, 303f, 298f, 282f, 292f, 225f)
        label(c, R.string.health_atlas_sinus_drainage_coronal_view, 180f, 341f, 210f)
    }

    private fun heightCue(c: Canvas, t: Float) {
        val top = 149f
        val bottom = 266f
        val x = 25f
        val end = bottom - (bottom - top) * HealthAtlasSinusDrainageMotion.heightReveal(t)
        line(c, x, top, x, bottom, 0xffb5a394, 1f)
        line(c, x - 5f, top, x + 7f, top, sienna, 1.5f)
        line(c, x - 5f, bottom, x + 7f, bottom, sienna, 1.5f)
        line(c, x, bottom, x, end, sienna, 2.8f)
        disc(c, x, end, 3.1f, sienna, cream)
        if (t > .21f) {
            val radius = 8f + 3f * HealthAtlasSinusDrainageMotion.heightReveal(t)
            ink(sienna, 1.4f)
            c.drawCircle(205f, 149f, radius, paint)
        }
    }

    private fun rise(c: Canvas, t: Float) {
        filmSegment(c, ascentTrack, 0f, 1f, mucusLight, 4f)
        for (i in 0..15) {
            if (!ascentTrack.getPosTan(ascentTrack.length * (.05f + i * .057f), position, tangent)) continue
            val bend = HealthAtlasSinusDrainageMotion.ciliumBend(t, i) * 4f
            val x = position[0] - 2f * tangent[1]
            val y = position[1] + 2f * tangent[0]
            scratch.rewind()
            scratch.moveTo(x, y)
            scratch.quadTo(x + 3f * tangent[1], y - 3f * tangent[0],
                x + 6f * tangent[1] + bend * tangent[0], y - 6f * tangent[0] + bend * tangent[1])
            stroke(c, scratch, liningInk, 1.15f)
        }
        for (i in 0..2) {
            val head = HealthAtlasSinusDrainageMotion.ascent(t, i)
            filmSegment(c, ascentTrack, head - .10f, head, mucusInk, 4.4f)
        }
        arrow(c, 178f, 228f, 187f, 207f, mucusInk)
        arrow(c, 185f, 195f, 187f, 174f, mucusInk)
    }

    private fun enterNose(c: Canvas, t: Float) {
        filmSegment(c, ascentTrack, .06f, 1f, mucusLight, 3.3f)
        filmSegment(c, exitTrack, 0f, 1f, mucusLight, 4f)
        for (i in 0..2) {
            val head = HealthAtlasSinusDrainageMotion.exit(t, i)
            filmSegment(c, exitTrack, head - .12f, head, mucusInk, 4.4f)
        }
        arrow(c, 241f, 185f, 267f, 185f, mucusInk)
    }

    private fun secretionDetail(c: Canvas, t: Float) {
        c.save()
        c.translate(108f, 4f)
        c.scale(.43f, .43f)
        sectionArt(c)
        c.restore()
        disc(c, 165f, 115f, 10f, 0xffd4e9db, liningInk)
        disc(c, 165f, 115f, 2.5f, liningInk)
        line(c, 157f, 123f, 36f, 173f, 0xff89a8a1, 1.1f)
        line(c, 173f, 123f, 324f, 173f, 0xff89a8a1, 1.1f)

        rounded(c, 31f, 217f, 329f, 293f, 7f, 0xffecd1c2)
        rounded(c, 34f, 208f, 326f, 232f, 5f, 0xffe1eff0)
        for (i in 0..7) {
            val x = 35f + 36f * i
            if (i != 3) {
                oval(c, x, 222f, x + 38f, 280f, tissueFill, contourInk)
                oval(c, x + 12f, 253f + i % 2 * 4f, x + 26f, 268f + i % 2 * 4f, 0xffad7d9b, violet)
                for (j in 0..3) detailCilium(c, x + 7f + 7f * j, i * 4 + j, t)
            }
        }
        scratch.rewind()
        scratch.moveTo(151f, 222f)
        scratch.cubicTo(150f, 232f, 143f, 238f, 146f, 252f)
        scratch.cubicTo(148f, 263f, 156f, 264f, 156f, 275f)
        scratch.quadTo(162f, 283f, 168f, 275f)
        scratch.cubicTo(168f, 264f, 179f, 258f, 180f, 247f)
        scratch.cubicTo(182f, 235f, 173f, 232f, 173f, 222f)
        scratch.close()
        area(c, scratch, 0xffb8d6be, liningInk)
        oval(c, 157f, 260f, 168f, 273f, 0xffad7d9b, violet)

        rounded(c, 34f, 197f, 326f, 210f, 6f, mucusLight)
        line(c, 44f, 200f, 316f, 200f, 0xffd7ebd6, 1.2f)
        for (i in 0..2) {
            val release = HealthAtlasSinusDrainageMotion.secretion(t, i)
            val x = 162f + (i - 1) * 6f
            val y = 244f + 4f * i - (40f + 4f * i) * release
            val spread = ((release - .78f) / .22f).coerceIn(0f, 1f)
            oval(c, x - 3f - 10f * spread, y - 3.9f, x + 3f + 10f * spread, y + 3.9f, 0xff68aa92, liningInk)
        }
        leader(c, R.string.health_atlas_sinus_drainage_mucus_film, 259f, 181f, 144f, 259f, 185f, 252f, 192f, 246f, 204f)
        leader(c, R.string.health_atlas_sinus_drainage_secretory_cell, 156f, 325f, 150f, 156f, 309f, 158f, 291f, 162f, 255f)
        leader(c, R.string.health_atlas_sinus_drainage_cilia, 50f, 325f, 68f, 39f, 309f, 23f, 236f, 43f, 216f)
    }

    private fun detailCilium(c: Canvas, x: Float, index: Int, t: Float) {
        val bend = HealthAtlasSinusDrainageMotion.ciliumBend(t * .43f, index) * 6f
        scratch.rewind()
        scratch.moveTo(x, 227f)
        scratch.cubicTo(x, 222f, x + bend * .5f, 217f, x + bend, 212f)
        stroke(c, scratch, liningInk, 1.35f)
    }

    private fun filmSegment(c: Canvas, route: PathMeasure, from: Float, to: Float, color: Long, width: Float) {
        scratch.rewind()
        if (route.getSegment(route.length * from.coerceAtLeast(0f), route.length * to, scratch, true)) {
            stroke(c, scratch, color, width)
        }
    }

    private fun shaded(c: Canvas, path: Path, fill: Shader, border: Long = contourInk) {
        ink(cream)
        paint.shader = fill
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, border, 1.45f)
    }

    private fun area(c: Canvas, path: Path, fill: Long, border: Long) {
        ink(fill)
        c.drawPath(path, paint)
        stroke(c, path, border, 1.2f)
    }

    private fun sinus(c: Canvas, path: Path, fill: Long, border: Long, emphasis: Float) {
        ink(fill)
        c.drawPath(path, paint)
        stroke(c, path, border, 1.25f + emphasis * 2.5f)
    }

    private fun leader(
        c: Canvas, res: Int, x: Float, baseline: Float, width: Float,
        startX: Float, startY: Float, bendX: Float, bendY: Float, targetX: Float, targetY: Float,
    ) {
        scratch.rewind()
        scratch.moveTo(startX, startY)
        scratch.lineTo(bendX, bendY)
        scratch.lineTo(targetX, targetY)
        stroke(c, scratch, leaderInk, 1.05f)
        disc(c, targetX, targetY, 1.85f, leaderInk)
        label(c, res, x, baseline, width)
    }

    companion object {
        const val OPENING_REFERENCE_URL = "https://pubmed.ncbi.nlm.nih.gov/22319687/"
        const val CLEARANCE_REFERENCE_URL = "https://pubmed.ncbi.nlm.nih.gov/1874632/"
    }
}
