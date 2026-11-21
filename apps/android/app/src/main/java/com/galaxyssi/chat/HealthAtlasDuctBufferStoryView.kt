package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader
import androidx.annotation.StringRes

internal object HealthAtlasDuctBufferMotion {
    fun orient(t: Float) = ease(t, .04f, .95f)
    fun acidArrival(t: Float) = ease(t, .01f, .39f)
    fun secretin(t: Float) = ease(t, .39f, .94f)
    fun secretion(t: Float, outlet: Int) = ease(t, .06f + outlet * .13f, .62f + outlet * .11f)
    fun delivery(t: Float) = ease(t, .02f, .97f)
    fun bufferInflow(t: Float) = ease(t, .01f, .41f)
    fun buffering(t: Float) = ease(t, .39f, .99f)

    private fun ease(t: Float, start: Float, end: Float): Float {
        val p = ((HealthAtlasFunctionStory.safePhase(t) - start) / (end - start)).coerceIn(0f, 1f)
        return p * p * (3f - 2f * p)
    }
}

internal class HealthAtlasDuctBufferStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.PANCREATIC_DUCT_BUFFER) {
    private val motion = HealthAtlasDuctBufferMotion
    private val guide = 0xff526569
    private val tissueEdge = 0xff975e64
    private val gutWall = 0xffd49b95
    private val gutMiddle = 0xffefbeb0
    private val gutLumen = 0xfff9e5cb
    private val ductEdge = 0xff547c7b
    private val ductLumen = 0xffd8eee8
    private val fluidInk = 0xff236e71
    private val acidFill = 0xffe9b976
    private val acidInk = 0xffa66539
    private val signalInk = 0xff694b82
    private val acinarFill = shade(-17f, 17f, 0xfff6c9b4, 0xffd99aa1)
    private val organFill = shade(109f, 235f, 0xfff6d4aa, 0xffd79a84)

    private val acinarWedge = shape {
        moveTo(5f, -3f)
        quadTo(17f, -8f, 29f, -16f)
        cubicTo(38f, -19f, 40f, -10f, 40f, 0f)
        cubicTo(40f, 11f, 37f, 18f, 29f, 16f)
        quadTo(17f, 7f, 5f, 3f)
        close()
    }
    private val lobule = shape {
        moveTo(48f, 73f)
        cubicTo(88f, 49f, 135f, 62f, 154f, 94f)
        cubicTo(184f, 83f, 219f, 89f, 248f, 120f)
        cubicTo(265f, 149f, 249f, 182f, 269f, 213f)
        cubicTo(306f, 233f, 327f, 271f, 296f, 290f)
        cubicTo(267f, 308f, 229f, 270f, 193f, 288f)
        cubicTo(156f, 304f, 131f, 280f, 109f, 297f)
        cubicTo(78f, 311f, 50f, 284f, 54f, 259f)
        cubicTo(26f, 234f, 36f, 201f, 46f, 184f)
        cubicTo(22f, 149f, 20f, 103f, 48f, 73f)
        close()
    }
    private val lobuleBranches = listOf(
        shape { moveTo(85f, 107f); cubicTo(144f, 106f, 175f, 141f, 225f, 139f) },
        shape { moveTo(86f, 180f); cubicTo(146f, 173f, 168f, 188f, 230f, 183f) },
        shape { moveTo(93f, 254f); cubicTo(164f, 255f, 196f, 233f, 244f, 225f) },
    )
    private val collecting = shape {
        moveTo(223f, 119f)
        cubicTo(226f, 157f, 226f, 196f, 242f, 223f)
        quadTo(260f, 250f, 301f, 265f)
    }
    private val orientationTrack = track(shape {
        moveTo(86f, 180f)
        cubicTo(146f, 173f, 168f, 188f, 230f, 183f)
        quadTo(233f, 209f, 242f, 223f)
        quadTo(260f, 250f, 301f, 265f)
    })

    private val mucosa = shape {
        moveTo(31f, 145f)
        cubicTo(111f, 147f, 153f, 143f, 217f, 145f)
        quadTo(272f, 148f, 327f, 143f)
        lineTo(327f, 185f)
        cubicTo(264f, 211f, 107f, 182f, 31f, 196f)
        close()
    }
    private val sCell = shape {
        moveTo(214f, 147f)
        lineTo(223f, 147f)
        cubicTo(222f, 159f, 233f, 170f, 228f, 178f)
        quadTo(219f, 185f, 208f, 178f)
        cubicTo(204f, 167f, 215f, 160f, 214f, 147f)
        close()
    }
    private val bloodCourse = shape {
        moveTo(219f, 190f)
        cubicTo(220f, 221f, 185f, 229f, 146f, 225f)
        cubicTo(103f, 222f, 78f, 229f, 85f, 256f)
        quadTo(92f, 269f, 130f, 266f)
    }
    private val signalTrack = track(bloodCourse)
    private val acidTrack = track(shape {
        moveTo(38f, 115f); cubicTo(109f, 109f, 163f, 113f, 218f, 137f)
    })

    private val pancreas = shape {
        moveTo(27f, 142f)
        cubicTo(24f, 130f, 46f, 121f, 62f, 125f)
        cubicTo(77f, 124f, 103f, 112f, 117f, 122f)
        cubicTo(132f, 126f, 140f, 116f, 156f, 125f)
        cubicTo(171f, 136f, 186f, 133f, 200f, 130f)
        cubicTo(220f, 123f, 239f, 130f, 250f, 144f)
        cubicTo(267f, 139f, 267f, 154f, 264f, 166f)
        cubicTo(278f, 180f, 263f, 199f, 256f, 207f)
        cubicTo(255f, 224f, 235f, 233f, 218f, 226f)
        cubicTo(206f, 228f, 206f, 208f, 189f, 207f)
        cubicTo(172f, 202f, 175f, 191f, 157f, 192f)
        cubicTo(140f, 191f, 130f, 180f, 116f, 182f)
        cubicTo(94f, 182f, 84f, 165f, 66f, 168f)
        quadTo(37f, 161f, 27f, 142f)
        close()
    }
    private val organDetails = shape {
        moveTo(61f, 127f); quadTo(53f, 139f, 63f, 146f)
        moveTo(95f, 122f); quadTo(83f, 137f, 92f, 142f)
        moveTo(127f, 125f); quadTo(116f, 139f, 128f, 148f)
        moveTo(159f, 128f); quadTo(148f, 140f, 152f, 154f)
        moveTo(191f, 132f); quadTo(176f, 142f, 183f, 150f)
        moveTo(223f, 129f); quadTo(211f, 142f, 218f, 156f)
        moveTo(74f, 167f); quadTo(77f, 156f, 86f, 156f)
        moveTo(107f, 178f); quadTo(103f, 166f, 120f, 163f)
        moveTo(145f, 188f); quadTo(138f, 175f, 155f, 175f)
        moveTo(177f, 197f); quadTo(186f, 187f, 177f, 179f)
        moveTo(210f, 215f); quadTo(220f, 205f, 211f, 195f)
        moveTo(245f, 220f); quadTo(234f, 210f, 243f, 198f)
    }
    private val duodenum = shape {
        moveTo(204f, 100f)
        cubicTo(265f, 81f, 307f, 110f, 305f, 167f)
        cubicTo(304f, 235f, 275f, 264f, 221f, 261f)
        quadTo(187f, 260f, 160f, 268f)
    }
    private val organBranches = shape {
        moveTo(82f, 133f); quadTo(91f, 145f, 107f, 152f)
        moveTo(131f, 172f); quadTo(136f, 163f, 149f, 160f)
        moveTo(177f, 143f); quadTo(182f, 158f, 195f, 174f)
        moveTo(227f, 211f); quadTo(228f, 194f, 240f, 187f)
    }
    private val mainDuct = shape { traceDuct() }
    private val deliveryTrack = track(shape {
        traceDuct()
        cubicTo(304f, 194f, 304f, 203f, 293f, 219f)
        quadTo(271f, 260f, 226f, 261f)
    })

    private val bufferBowel = shape {
        moveTo(53f, 182f)
        cubicTo(112f, 165f, 151f, 172f, 190f, 185f)
        quadTo(253f, 209f, 310f, 188f)
    }
    private val acidStream = track(bufferBowel)
    private val bufferInlet = shape {
        moveTo(215f, 97f); cubicTo(215f, 121f, 188f, 131f, 192f, 165f)
    }
    private val inflowTrack = track(shape {
        moveTo(215f, 97f); cubicTo(215f, 121f, 188f, 131f, 192f, 165f)
        quadTo(192f, 180f, 201f, 189f)
    })
    private val mixingTrack = track(shape {
        moveTo(199f, 188f); quadTo(255f, 208f, 310f, 188f)
    })
    private val mixingFront = Path()

    init { tag = "atlas-function-pancreatic-duct-buffer-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> orient(c, t)
            1 -> signal(c, t)
            2 -> secrete(c, t)
            3 -> deliver(c, t)
            4 -> buffer(c, t)
        }
    }

    private fun orient(c: Canvas, t: Float) {
        filled(c, lobule, 0xfff7e4d4, 0xffcfa797)
        for (branch in lobuleBranches) tube(c, branch, 15f, 9f)
        tube(c, collecting, 22f, 14f)
        acinus(c, 85f, 107f, .86f)
        acinus(c, 86f, 180f, 1f)
        acinus(c, 93f, 254f, .87f)
        val p = motion.orient(t)
        for (i in 0..3) {
            val f = p - i * .045f
            if (f >= 0f) at(orientationTrack, f) { x, y -> disc(c, x, y, 2.6f, acidInk, cream) }
        }
        callout(c, R.string.health_atlas_duct_buffer_story_acinus, 58f, 46f, 88f, 59f, 54f, 71f, 76f)
        callout(c, R.string.health_atlas_duct_buffer_story_acinar_lumen, 175f, 325f, 132f,
            155f, 310f, 93f, 254f)
        callout(c, R.string.health_atlas_duct_buffer_story_small_duct, 277f, 96f, 135f,
            269f, 103f, 223f, 125f)
    }

    private fun acinus(c: Canvas, x: Float, y: Float, scale: Float) {
        c.save()
        c.translate(x, y)
        c.scale(scale, scale)
        for (i in 1..5) {
            c.save()
            c.rotate(i * 60f)
            filled(c, acinarWedge, acinarFill, tissueEdge)
            oval(c, 25f, -5f, 34f, 5f, 0xffa67f9c, 0xff855871)
            disc(c, 13f, -1f, 1.5f, acidInk)
            disc(c, 17f, 2f, 1.4f, acidInk)
            c.restore()
        }
        disc(c, 0f, 0f, 6f, ductLumen, ductEdge)
        c.restore()
    }

    private fun signal(c: Canvas, t: Float) {
        filled(c, mucosa, 0xfff2c8bb, tissueEdge)
        for (i in 0..13) {
            val x = 36f + i * 20f
            if (i != 9) {
                rounded(c, x, 148f, x + 18f, 174f, 5f, 0xfff9dcc8)
                oval(c, x + 5f, 162f, x + 13f, 171f, 0xffc18d9d, tissueEdge)
            }
        }
        filled(c, sCell, 0xffdcbbd8, signalInk)
        disc(c, 219f, 171f, 3.8f, signalInk)
        stroke(c, bloodCourse, tissueEdge, 16f)
        stroke(c, bloodCourse, 0xfff1c4bf, 12f)
        rounded(c, 49f, 300f, 175f, 320f, 7f, ductLumen)
        for (i in 0..3) ductCell(c, 49f + i * 32f, 271f, 32f, 31f, i == 2)
        line(c, 51f, 302f, 174f, 302f, ductEdge, 1.5f)

        val arrival = motion.acidArrival(t)
        for (i in 0..3) {
            at(acidTrack, (.27f + arrival * .73f - .085f * i)) { x, y ->
                acidMark(c, x, y - (i % 2) * 6f, 1f)
            }
        }
        val signal = motion.secretin(t)
        for (i in 0..3) {
            val f = signal - i * .12f
            if (f > 0f) at(signalTrack, f) { x, y -> disc(c, x, y, 3.3f, signalInk, cream) }
        }
        callout(c, R.string.health_atlas_duct_buffer_story_acidic_contents, 102f, 79f, 135f,
            105f, 87f, 116f, 111f)
        callout(c, R.string.health_atlas_duct_buffer_story_s_cell, 274f, 103f, 98f,
            267f, 111f, 220f, 154f)
        callout(c, R.string.health_atlas_duct_buffer_story_blood_signal, 252f, 248f, 166f,
            192f, 238f, 172f, 225f)
        callout(c, R.string.health_atlas_duct_buffer_story_duct_cells, 240f, 305f, 130f,
            205f, 297f, 145f, 285f)
    }

    private fun secrete(c: Canvas, t: Float) {
        rounded(c, 45f, 146f, 315f, 213f, 7f, ductLumen)
        for (i in 0..5) {
            val x = 45f + i * 45f
            ductCell(c, x, 115f, 45f, 36f, i == 1 || i == 3)
            ductCell(c, x, 207f, 45f, 36f, i == 2)
        }
        line(c, 45f, 151f, 315f, 151f, ductEdge, 1.6f)
        line(c, 45f, 207f, 315f, 207f, ductEdge, 1.6f)
        for (i in 0..2) {
            val base = 112f + 45f * i
            val top = i != 1
            for (j in 0..2) {
                val p = motion.secretion(t - j * .09f, i)
                if (p > 0f) {
                    val across = (p * 2f).coerceAtMost(1f)
                    val downstream = (p * 2f - 1f).coerceAtLeast(0f)
                    val y = if (top) 142f + across * (26f + j * 4f) else 217f - across * (27f + j * 4f)
                    fluidMark(c, base + j * 7f + downstream * 38f, y)
                }
            }
        }
        arrow(c, 272f, 181f, 300f, 181f, fluidInk)
        callout(c, R.string.health_atlas_duct_buffer_story_duct_cells, 111f, 81f, 124f,
            111f, 90f, 111f, 123f)
        leader(c, 56f, 274f, 33f, 248f)
        leader(c, 33f, 248f, 33f, 177f)
        callout(c, R.string.health_atlas_duct_buffer_story_duct_lumen, 85f, 294f, 126f,
            33f, 177f, 54f, 177f)
        leader(c, 295f, 275f, 327f, 246f)
        leader(c, 327f, 246f, 327f, 181f)
        callout(c, R.string.health_atlas_duct_buffer_story_rich_fluid, 252f, 294f, 176f,
            327f, 181f, 304f, 181f)
    }

    private fun ductCell(c: Canvas, x: Float, y: Float, w: Float, h: Float, active: Boolean) {
        rounded(c, x, y, x + w, y + h, 5f, 0xff85a39a)
        rounded(c, x + 1f, y + 1f, x + w - 1f, y + h - 1f, 4f,
            if (active) 0xffb5d8c8 else 0xffe4ebdc)
        val mid = x + w / 2f
        oval(c, mid - 6f, y + h * .36f, mid + 6f, y + h * .67f, 0xffa5b8a9, ductEdge)
    }

    private fun deliver(c: Canvas, t: Float) {
        bowel(c, duodenum, 48f)
        for (i in 0..3) {
            val y = 129f + 23f * i
            line(c, 316f, y - 3f, 309f - i, y + 2f, tissueEdge, 1.1f)
        }
        filled(c, pancreas, organFill, tissueEdge)
        stroke(c, organDetails, 0xffbf877b, 1.25f)
        tube(c, organBranches, 5f, 2.5f)
        tube(c, mainDuct, 11f, 7f)
        disc(c, 298f, 185f, 3.4f, ductLumen, ductEdge)
        val p = motion.delivery(t)
        for (i in 0..4) {
            val f = .12f + .87f * p - i * .043f
            if (f >= 0f) at(deliveryTrack, f) { x, y ->
                if (i == 2) disc(c, x, y, 2.1f, acidInk, cream)
                else fluidMark(c, x, y, .74f)
            }
        }
        callout(c, R.string.health_atlas_duct_buffer_story_pancreas, 89f, 87f, 132f, 90f, 95f, 99f, 130f)
        callout(c, R.string.health_atlas_duct_buffer_story_main_duct, 103f, 230f, 160f,
            111f, 216f, 140f, 159f)
        callout(c, R.string.health_atlas_duct_buffer_story_duodenum, 266f, 312f, 127f,
            269f, 299f, 266f, 254f)
    }

    private fun Path.traceDuct() {
        moveTo(45f, 142f)
        cubicTo(93f, 154f, 147f, 153f, 191f, 173f)
        cubicTo(222f, 188f, 261f, 189f, 298f, 185f)
    }

    private fun buffer(c: Canvas, t: Float) {
        bowel(c, bufferBowel, 68f)
        for (i in 0..5) {
            val x = 68f + i * 42f
            val y = if (i < 3) 203f else 220f
            line(c, x, y + 4f, x + 4f, y - 3f, 0xffb47c72, 1.3f)
        }
        stroke(c, bufferBowel, 0xfff1cb96, 23f)
        tube(c, bufferInlet, 22f, 14f)
        val mixed = motion.buffering(t)
        if (mixed > 0f) {
            mixingFront.rewind()
            mixingTrack.getSegment(0f, mixed * mixingTrack.length, mixingFront, true)
            stroke(c, mixingFront, 0xffdec99e, 22f)
            stroke(c, mixingFront, 0xffc9d6bb, 14f)
        }
        for (i in 0..6) {
            val p = .05f + i * .129f + motion.delivery(t) * .115f
            at(acidStream, p) { x, y ->
                val reached = x in 196f..(200f + 110f * mixed)
                if (!reached || i % 2 == 0) acidMark(c, x, y + (i % 3 - 1) * 4f, .63f, reached)
            }
        }
        val inlet = motion.bufferInflow(t)
        for (i in 0..3) {
            val f = .17f + .82f * inlet - i * .19f
            if (f >= 0f) at(inflowTrack, f) { x, y -> fluidMark(c, x, y, .84f) }
        }
        if (mixed > 0f) at(mixingTrack, mixed * .77f) { x, y -> fluidMark(c, x, y) }
        callout(c, R.string.health_atlas_duct_buffer_story_acidic_contents, 91f, 111f, 138f,
            91f, 120f, 97f, 174f)
        callout(c, R.string.health_atlas_duct_buffer_story_rich_fluid, 250f, 76f, 174f,
            246f, 86f, 208f, 122f)
        callout(c, R.string.health_atlas_duct_buffer_story_duodenal_lumen, 242f, 281f, 165f,
            242f, 266f, 253f, 200f)
    }

    private fun acidMark(c: Canvas, x: Float, y: Float, s: Float, muted: Boolean = false) {
        oval(c, x - 12f * s, y - 5f * s, x + 12f * s, y + 5f * s,
            if (muted) 0xffddc59d else acidFill, if (muted) 0xffb08f67 else acidInk)
        line(c, x - 4f * s, y, x + 3f * s, y + s, if (muted) 0xffb08f67 else acidInk, 1f)
    }

    private fun fluidMark(c: Canvas, x: Float, y: Float, s: Float = 1f) {
        line(c, x - 5f * s, y + s, x + 2f * s, y - s, fluidInk, 1.8f)
        line(c, x, y + 3f * s, x + 5f * s, y + 1.5f * s, fluidInk, 1.45f)
    }

    private fun tube(c: Canvas, path: Path, outer: Float, inner: Float) {
        stroke(c, path, ductEdge, outer)
        stroke(c, path, ductLumen, inner)
    }

    private fun bowel(c: Canvas, path: Path, width: Float) {
        stroke(c, path, tissueEdge, width)
        stroke(c, path, gutWall, width - 3f)
        stroke(c, path, gutMiddle, width - 10f)
        stroke(c, path, gutLumen, width - 22f)
    }

    private fun filled(c: Canvas, path: Path, color: Long, edge: Long) {
        ink(color); c.drawPath(path, paint)
        stroke(c, path, edge, 1.2f)
    }

    private fun filled(c: Canvas, path: Path, fill: Shader, edge: Long) {
        ink(cream); paint.shader = fill; c.drawPath(path, paint); paint.shader = null
        stroke(c, path, edge, 1.2f)
    }

    private fun leader(c: Canvas, x: Float, y: Float, tx: Float, ty: Float) =
        line(c, x, y, tx, ty, guide, 1.05f)

    private fun callout(
        c: Canvas, @StringRes res: Int, x: Float, y: Float, width: Float,
        lx: Float, ly: Float, tx: Float, ty: Float,
    ) {
        leader(c, lx, ly, tx, ty)
        disc(c, tx, ty, 1.65f, guide)
        label(c, res, x, y, width)
    }

    private fun shape(build: Path.() -> Unit) = Path().apply(build)

    companion object {
        const val SECRETIN_REFERENCE_URL = "https://pubmed.ncbi.nlm.nih.gov/930532/"
        const val DUCT_FLUID_REFERENCE_URL = "https://pubmed.ncbi.nlm.nih.gov/9706019/"
    }
}
