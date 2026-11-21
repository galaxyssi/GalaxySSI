package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader
import androidx.annotation.StringRes

internal object HealthAtlasAcinarEnzymeMotion {
    fun locate(t: Float) = eased(t, .07f, .79f)
    fun synthesize(t: Float) = eased(t, .02f, .51f)
    fun store(t: Float) = eased(t, .42f, .92f)
    fun dock(t: Float) = eased(t, .12f, .48f)
    fun release(t: Float) = eased(t, .48f, .97f)
    fun enrich(t: Float) = eased(t, .08f, .72f)
    fun transit(t: Float) = HealthAtlasFunctionStory.safePhase(t)
    fun arrive(t: Float) = eased(t, .16f, .95f)

    private fun eased(t: Float, start: Float, end: Float): Float {
        val p = ((HealthAtlasFunctionStory.safePhase(t) - start) / (end - start)).coerceIn(0f, 1f)
        return p * p * (3f - 2f * p)
    }
}

internal class HealthAtlasAcinarEnzymeStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.ACINAR_ENZYME_SECRETION) {
    private val tissueEdge = 0xff995e66
    private val tissueTint = 0xffedb9a7
    private val guide = 0xff5a686d
    private val nucleus = 0xffb886a6
    private val erInk = 0xff765780
    private val golgiInk = 0xffab7054
    private val lumen = 0xffd7efea
    private val ductWall = 0xff8ba6a1
    private val ductEdge = 0xff517c7a
    private val fluidInk = 0xff276f75
    private val enzymeInk = 0xff9d4839
    private val precursorInk = 0xff644474
    private val granuleFill = 0xffeeb17e
    private val highlight = 0xff9c693d
    private val acinusFill = shade(-23f, 27f, 0xfff9d6c4, 0xffdb9c9d)
    private val acinusShade = shade(-23f, 27f, 0xfff3c4b0, 0xffd59197)
    private val cellFill = shade(88f, 256f, 0xfffde4ce, 0xffdf9fa4)
    private val organFill = shade(115f, 238f, 0xfff7d4ab, 0xffd9967c)

    private val acinarWedge = shape {
        moveTo(9f, -4f)
        quadTo(33f, -12f, 51f, -21f)
        cubicTo(63f, -27f, 67f, -15f, 67f, -1f)
        cubicTo(67f, 16f, 63f, 27f, 51f, 22f)
        quadTo(33f, 14f, 9f, 4f)
        close()
    }
    private val acinarOutlet = shape {
        moveTo(0f, 0f); cubicTo(24f, -3f, 57f, -2f, 85f, 0f)
    }
    private val septum = shape {
        moveTo(20f, 122f)
        cubicTo(23f, 99f, 51f, 93f, 73f, 100f)
        cubicTo(99f, 85f, 133f, 98f, 146f, 123f)
        cubicTo(171f, 138f, 167f, 168f, 163f, 190f)
        cubicTo(179f, 211f, 166f, 247f, 146f, 267f)
        cubicTo(121f, 289f, 102f, 266f, 75f, 277f)
        cubicTo(41f, 283f, 20f, 257f, 25f, 229f)
        cubicTo(12f, 209f, 15f, 187f, 28f, 166f)
        quadTo(15f, 145f, 20f, 122f)
        close()
    }
    private val lobuleDucts = shape {
        moveTo(151f, 127f); cubicTo(149f, 178f, 152f, 222f, 137f, 268f)
        moveTo(83f, 131f); quadTo(114f, 127f, 149f, 144f)
        moveTo(91f, 183f); quadTo(122f, 181f, 150f, 195f)
        moveTo(82f, 237f); quadTo(117f, 237f, 146f, 226f)
        moveTo(127f, 250f); quadTo(136f, 249f, 141f, 251f)
    }

    private val cell = shape {
        moveTo(240f, 136f)
        cubicTo(190f, 132f, 133f, 84f, 75f, 94f)
        cubicTo(34f, 101f, 32f, 153f, 42f, 211f)
        cubicTo(51f, 258f, 91f, 260f, 133f, 240f)
        cubicTo(176f, 220f, 206f, 208f, 240f, 204f)
        close()
    }
    private val cellOuterMembrane = shape {
        moveTo(240f, 136f)
        cubicTo(190f, 132f, 133f, 84f, 75f, 94f)
        cubicTo(34f, 101f, 32f, 153f, 42f, 211f)
        cubicTo(51f, 258f, 91f, 260f, 133f, 240f)
        cubicTo(176f, 220f, 206f, 208f, 240f, 204f)
    }
    private val facingCell = shape {
        moveTo(272f, 143f)
        cubicTo(281f, 139f, 293f, 128f, 301f, 116f)
        cubicTo(329f, 120f, 341f, 151f, 332f, 177f)
        cubicTo(323f, 204f, 294f, 220f, 274f, 209f)
        quadTo(269f, 182f, 272f, 143f)
        close()
    }
    private val acinarSpace = shape {
        moveTo(240f, 136f)
        cubicTo(263f, 135f, 279f, 116f, 299f, 100f)
        quadTo(307f, 93f, 324f, 85f)
        lineTo(332f, 100f)
        cubicTo(316f, 107f, 300f, 117f, 290f, 129f)
        quadTo(282f, 138f, 272f, 143f)
        quadTo(270f, 183f, 274f, 209f)
        quadTo(257f, 216f, 240f, 204f)
        close()
    }
    private val fusionMouth = shape {
        moveTo(240f, 169f)
        cubicTo(231f, 169f, 230f, 164f, 224f, 167f)
        cubicTo(215f, 171f, 216f, 183f, 225f, 186f)
        cubicTo(232f, 188f, 234f, 181f, 240f, 181f)
    }
    private val erFolds = List(5) { row ->
        val y = 120f + row * 8f
        shape {
            moveTo(61f - row * 1.2f, y + 1f)
            cubicTo(78f, y - 10f, 89f, y + 7f, 111f + row * 1.4f, y + 1f)
        }
    }
    private val golgiStacks = List(5) { row ->
        val x = 127f + row * 6f
        shape {
            moveTo(x + 5f, 159f + row)
            quadTo(x - 10f, 179f, x + 10f, 196f - row * .8f)
        }
    }
    private val toGolgi = track(shape {
        moveTo(96f, 145f); quadTo(116f, 143f, 127f, 171f)
    })
    private val toStorage = track(shape {
        moveTo(161f, 174f); cubicTo(177f, 171f, 187f, 159f, 210f, 170f)
    })
    private val outOfCell = track(shape {
        moveTo(230f, 175f)
        cubicTo(265f, 177f, 246f, 145f, 281f, 128f)
        quadTo(301f, 105f, 324f, 95f)
    })

    private val collectingBranches = shape {
        moveTo(102f, 105f); cubicTo(127f, 107f, 101f, 153f, 126f, 182f)
        moveTo(97f, 252f); cubicTo(127f, 247f, 107f, 211f, 135f, 182f)
    }
    private val collectingDuct = shape {
        moveTo(94f, 181f); quadTo(108f, 182f, 130f, 182f); lineTo(330f, 182f)
    }
    private val collectingTrack = track(shape {
        moveTo(62f, 181f); quadTo(107f, 180f, 134f, 182f); lineTo(327f, 182f)
    })

    private val pancreas = shape {
        moveTo(28f, 146f)
        cubicTo(35f, 131f, 57f, 138f, 69f, 131f)
        cubicTo(87f, 120f, 104f, 134f, 121f, 129f)
        cubicTo(140f, 121f, 149f, 137f, 165f, 135f)
        cubicTo(182f, 128f, 193f, 143f, 204f, 139f)
        cubicTo(218f, 139f, 221f, 129f, 237f, 134f)
        cubicTo(256f, 132f, 273f, 151f, 273f, 170f)
        cubicTo(283f, 190f, 265f, 224f, 248f, 230f)
        cubicTo(231f, 242f, 211f, 232f, 211f, 216f)
        cubicTo(209f, 204f, 196f, 212f, 187f, 199f)
        cubicTo(174f, 201f, 165f, 184f, 151f, 187f)
        cubicTo(138f, 190f, 131f, 176f, 114f, 178f)
        cubicTo(93f, 180f, 87f, 168f, 68f, 170f)
        cubicTo(53f, 171f, 20f, 162f, 28f, 146f)
        close()
    }
    private val lobularScallops = shape {
        moveTo(62f, 136f); quadTo(54f, 141f, 59f, 148f)
        moveTo(94f, 132f); quadTo(85f, 139f, 91f, 148f)
        moveTo(128f, 134f); quadTo(118f, 141f, 124f, 151f)
        moveTo(164f, 139f); quadTo(148f, 147f, 156f, 159f)
        moveTo(194f, 140f); quadTo(181f, 151f, 191f, 170f)
        moveTo(239f, 137f); quadTo(219f, 145f, 224f, 165f)
        moveTo(82f, 170f); quadTo(83f, 159f, 72f, 157f)
        moveTo(121f, 177f); quadTo(116f, 166f, 103f, 169f)
        moveTo(153f, 185f); quadTo(156f, 175f, 141f, 173f)
        moveTo(182f, 196f); quadTo(182f, 181f, 169f, 182f)
        moveTo(202f, 206f); quadTo(206f, 195f, 195f, 191f)
        moveTo(234f, 232f); quadTo(246f, 216f, 233f, 197f)
        moveTo(261f, 216f); quadTo(248f, 206f, 259f, 194f)
    }
    private val duodenum = shape {
        moveTo(227f, 101f)
        cubicTo(272f, 93f, 299f, 111f, 298f, 162f)
        cubicTo(297f, 202f, 296f, 226f, 269f, 247f)
        cubicTo(238f, 271f, 197f, 258f, 157f, 264f)
    }
    private val pancreaticDuct = shape { tracePancreaticDuct() }
    private val deliveryTrack = track(shape {
        tracePancreaticDuct()
        cubicTo(298f, 218f, 286f, 233f, 269f, 247f)
        cubicTo(238f, 271f, 197f, 258f, 157f, 264f)
    })
    private val duodenalFolds = shape {
        moveTo(252f, 90f); quadTo(249f, 96f, 251f, 104f)
        moveTo(277f, 98f); quadTo(270f, 102f, 273f, 111f)
        moveTo(303f, 125f); quadTo(296f, 127f, 290f, 135f)
        moveTo(308f, 150f); quadTo(301f, 149f, 296f, 156f)
        moveTo(308f, 171f); quadTo(302f, 168f, 298f, 175f)
        moveTo(305f, 203f); quadTo(298f, 199f, 292f, 204f)
        moveTo(298f, 224f); quadTo(289f, 218f, 284f, 225f)
        moveTo(281f, 247f); quadTo(278f, 239f, 270f, 239f)
        moveTo(251f, 267f); quadTo(253f, 260f, 247f, 253f)
        moveTo(225f, 271f); quadTo(228f, 262f, 223f, 255f)
        moveTo(190f, 250f); quadTo(186f, 256f, 190f, 264f)
        moveTo(170f, 252f); quadTo(166f, 259f, 171f, 264f)
    }
    private val cargoDiamond = Path()
    private val cargoKeyWidths = mutableMapOf<Int, Float>()

    init { tag = "atlas-function-acinar-enzymes-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> locate(c, t)
            1 -> packageCargo(c, t)
            2 -> releaseCargo(c, t)
            3 -> ductTransit(c, t)
            4 -> arrive(c, t)
        }
    }

    private fun locate(c: Canvas, t: Float) {
        val p = HealthAtlasAcinarEnzymeMotion.locate(t)
        filled(c, septum, 0xfff5dccb, 0xffc6a095)
        tube(c, lobuleDucts, 8f, 5f)
        acinus(c, 53f, 132f, .37f)
        acinus(c, 120f, 122f, .34f)
        acinus(c, 65f, 183f, .37f)
        acinus(c, 119f, 176f, .40f)
        acinus(c, 53f, 237f, .36f)
        acinus(c, 100f, 248f, .34f)
        ink(highlight, 1.4f)
        c.drawCircle(119f, 176f, 31f + 4f * (1f - p), paint)
        zoomGuide(c, 143f, 153f, 213f, 129f, p)
        zoomGuide(c, 144f, 198f, 213f, 236f, p)
        acinus(c, 263f, 183f, .93f)
        callout(c, R.string.health_atlas_acinar_enzyme_story_lobule, 89f, 65f, 141f, 89f, 74f, 72f, 100f)
        callout(c, R.string.health_atlas_acinar_enzyme_story_acinus, 254f, 65f, 112f, 254f, 74f, 263f, 122f)
        callout(c, R.string.health_atlas_acinar_enzyme_story_lumen, 220f, 301f, 113f, 223f, 288f, 260f, 188f)
        callout(c, R.string.health_atlas_acinar_enzyme_story_small_duct, 303f, 274f, 104f, 318f, 261f, 327f, 183f)
    }

    private fun acinus(c: Canvas, x: Float, y: Float, scale: Float) {
        c.save()
        c.translate(x, y)
        c.scale(scale, scale)
        tube(c, acinarOutlet, 13f, 8f)
        for (i in 1..7) {
            c.save()
            c.rotate(45f * i)
            filled(c, acinarWedge, if (i % 2 == 0) acinusFill else acinusShade, tissueEdge)
            oval(c, 44f, -8f, 57f, 9f, nucleus, erInk)
            line(c, 38f, -9f, 43f, -12f, 0xffb27c8b, 1.2f)
            line(c, 37f, 9f, 44f, 12f, 0xffb27c8b, 1.2f)
            disc(c, 18f, -2.3f, 2.2f, highlight)
            disc(c, 24f, 3.5f, 2.4f, highlight)
            disc(c, 29f, -3f, 2.1f, highlight)
            c.restore()
        }
        disc(c, 0f, 0f, 8.8f, lumen)
        c.restore()
    }

    private fun zoomGuide(c: Canvas, x: Float, y: Float, endX: Float, endY: Float, progress: Float) {
        for (i in 0..9) {
            val from = i / 10f
            val to = minOf(progress, from + .055f)
            if (to > from) line(c, mix(x, endX, from), mix(y, endY, from),
                mix(x, endX, to), mix(y, endY, to), highlight, 1.15f)
        }
    }

    private fun cellPlate(c: Canvas, fused: Boolean = false) {
        filled(c, facingCell, tissueTint, tissueEdge)
        oval(c, 299f, 153f, 321f, 181f, nucleus, erInk)
        for (i in 0..3) disc(c, 282f + (i % 2) * 7f, 152f + i * 13f, 3.2f, granuleFill, highlight)
        filled(c, acinarSpace, lumen, ductEdge)
        ink(cream); paint.shader = cellFill; c.drawPath(cell, paint); paint.shader = null
        stroke(c, cellOuterMembrane, tissueEdge, 1.65f)

        if (fused) {
            ink(lumen); c.drawPath(fusionMouth, paint)
            stroke(c, fusionMouth, tissueEdge, 1.85f)
            line(c, 240f, 136f, 240f, 169f, tissueEdge, 1.85f)
            line(c, 240f, 181f, 240f, 204f, tissueEdge, 1.85f)
        } else {
            line(c, 240f, 136f, 240f, 204f, tissueEdge, 1.85f)
        }

        oval(c, 53f, 177f, 107f, 224f, 0xffc497b3, erInk)
        oval(c, 74f, 191f, 88f, 205f, nucleus, erInk)
        for ((row, fold) in erFolds.withIndex()) {
            stroke(c, fold, 0xffe2bad2, 4.5f)
            stroke(c, fold, erInk, 1.1f)
            for (i in 0..4) {
                disc(c, 65f + i * 9f, 117f + row * 8f + if (i < 2) 0f else 1.6f, .9f, erInk)
            }
        }
        for (stack in golgiStacks) {
            stroke(c, stack, 0xfff1c499, 3.8f)
            stroke(c, stack, golgiInk, 1.15f)
        }
        granule(c, 191f, 144f, 6f)
        granule(c, 208f, 151f, 7f)
        granule(c, 226f, 148f, 5.5f)
        granule(c, 199f, 192f, 6f)
        granule(c, 216f, 195f, 7f)
        granule(c, 228f, 193f, 4.4f)
    }

    private fun packageCargo(c: Canvas, t: Float) {
        cellPlate(c)
        val early = HealthAtlasAcinarEnzymeMotion.synthesize(t)
        val late = HealthAtlasAcinarEnzymeMotion.store(t)
        if (early < 1f) {
            at(toGolgi, early) { x, y -> granule(c, x, y, 3.5f) }
            at(toGolgi, (early - .23f).coerceAtLeast(0f)) { x, y -> disc(c, x, y + 6f, 2.3f, enzymeInk, cream) }
        }
        if (late > 0f) at(toStorage, late) { x, y -> granule(c, x, y, 3.5f + late * 4f) }
        callout(c, R.string.health_atlas_acinar_enzyme_story_rough_er, 74f, 61f, 106f, 74f, 71f, 83f, 121f)
        callout(c, R.string.health_atlas_acinar_enzyme_story_golgi, 102f, 291f, 135f, 122f, 279f, 143f, 192f)
        callout(c, R.string.health_atlas_acinar_enzyme_story_granules, 251f, 291f, 137f, 248f, 279f, 218f, 194f)
    }

    private fun releaseCargo(c: Canvas, t: Float) {
        val dock = HealthAtlasAcinarEnzymeMotion.dock(t)
        val release = HealthAtlasAcinarEnzymeMotion.release(t)
        cellPlate(c, fused = dock >= 1f)
        if (dock < 1f) {
            granule(c, mix(201f, 232f, dock), mix(168f, 175f, dock), 8f)
        } else {
            for (i in 0..3) {
                val p = release * 1.14f - .14f * i
                if (p in 0f..1f) at(outOfCell, p) { x, y ->
                    cargo(c, x, y + (i % 2) * 4f - 2f, i % 2 == 1, 2.8f)
                }
            }
        }
        callout(c, R.string.health_atlas_acinar_enzyme_story_granules, 142f, 59f, 136f, 157f, 68f, 208f, 151f)
        callout(c, R.string.health_atlas_acinar_enzyme_story_lumen, 289f, 60f, 128f, 286f, 70f, 261f, 145f)
        callout(c, R.string.health_atlas_acinar_enzyme_story_membrane, 158f, 277f, 151f, 191f, 264f, 240f, 202f)
        cargoKeys(c)
    }

    private fun ductTransit(c: Canvas, t: Float) {
        tube(c, collectingBranches, 11f, 7f)
        for (i in 0..7) {
            val x = 126f + i * 25.5f
            ductCell(c, x, 145f, i)
            ductCell(c, x, 193f, i + 1)
        }
        tube(c, collectingDuct, 25f, 19f)
        acinus(c, 77f, 105f, .35f)
        acinus(c, 71f, 252f, .34f)
        acinus(c, 62f, 181f, .59f)

        val flow = HealthAtlasAcinarEnzymeMotion.transit(t)
        for (i in 0..4) {
            at(collectingTrack, (flow * .66f + i * .19f) % 1f) { x, y ->
                cargo(c, x, y + if (i % 2 == 0) -2f else 2f, i % 2 != 0, 2.7f)
            }
        }
        val fluid = HealthAtlasAcinarEnzymeMotion.enrich(t)
        for (i in 0..2) {
            val startX = 162f + i * 51f
            val p = (fluid * 1.32f - i * .16f).coerceIn(0f, 1f)
            val y = mix(if (i == 1) 201f else 161f, if (i == 1) 187f else 176f, p)
            fluidMark(c, startX + 16f * p * p, y)
        }
        arrow(c, 310f, 182f, 343f, 182f, ductEdge)
        callout(c, R.string.health_atlas_acinar_enzyme_story_acini, 57f, 51f, 95f, 64f, 59f, 71f, 83f)
        callout(c, R.string.health_atlas_acinar_enzyme_story_ductal_cells, 235f, 93f, 126f, 235f, 102f, 239f, 153f)
        callout(c, R.string.health_atlas_acinar_enzyme_story_duct_fluid, 247f, 275f, 176f, 266f, 262f, 285f, 186f)
        cargoKeys(c)
    }

    private fun ductCell(c: Canvas, x: Float, y: Float, index: Int) {
        rounded(c, x, y, x + 25.5f, y + 28f, 4.5f, ductWall)
        rounded(c, x + .9f, y + 1f, x + 24.6f, y + 27f, 3.5f,
            if (index % 2 == 0) 0xffe4e8d9 else 0xffd3e4d9)
        oval(c, x + 7f, y + 8f, x + 18.5f, y + 18f, 0xff9ab5ad, ductEdge)
    }

    private fun arrive(c: Canvas, t: Float) {
        stroke(c, duodenum, 0xff9f6066, 46f)
        stroke(c, duodenum, 0xffd99b94, 42f)
        stroke(c, duodenum, 0xfff0bcb0, 34f)
        stroke(c, duodenum, 0xfffae4cf, 24f)
        stroke(c, duodenalFolds, 0xffcb9687, 1.4f)
        filled(c, pancreas, organFill, 0xff9e6659)
        stroke(c, lobularScallops, 0xffbf8878, 1.25f)
        tube(c, pancreaticDuct, 11f, 7f)
        disc(c, 297f, 184f, 4.2f, lumen, ductEdge)

        val p = HealthAtlasAcinarEnzymeMotion.arrive(t)
        for (i in 0..4) {
            val f = .30f + .68f * p - .065f * i
            at(deliveryTrack, f) { x, y ->
                if (i % 3 == 2) fluidMark(c, x, y)
                else cargo(c, x, y, i % 3 == 1, 2.65f)
            }
        }
        arrow(c, 214f, 260f, 193f, 261f, 0xff9a6259)
        callout(c, R.string.health_atlas_acinar_enzyme_story_pancreas, 102f, 79f, 126f, 108f, 88f, 131f, 138f)
        callout(c, R.string.health_atlas_acinar_enzyme_story_main_duct, 96f, 222f, 154f, 99f, 209f, 124f, 159f)
        callout(c, R.string.health_atlas_acinar_enzyme_story_duodenum, 265f, 310f, 137f, 266f, 297f, 268f, 248f)
    }

    private fun Path.tracePancreaticDuct() {
        moveTo(47f, 151f)
        cubicTo(94f, 153f, 131f, 158f, 168f, 167f)
        cubicTo(214f, 178f, 251f, 201f, 297f, 184f)
    }

    private fun granule(c: Canvas, x: Float, y: Float, r: Float) {
        disc(c, x, y, r, granuleFill, highlight)
        disc(c, x - r * .17f, y - r * .23f, r * .35f, 0xfff8d6a6)
    }

    private fun cargo(c: Canvas, x: Float, y: Float, precursor: Boolean, r: Float) {
        if (!precursor) {
            disc(c, x, y, r, enzymeInk, cream)
        } else {
            cargoDiamond.apply {
                rewind()
                moveTo(x, y - r - .8f); lineTo(x + r, y)
                lineTo(x, y + r + .8f); lineTo(x - r, y); close()
            }
            filled(c, cargoDiamond, precursorInk, cream)
        }
    }

    private fun cargoKeys(c: Canvas) {
        cargoKey(c, R.string.health_atlas_acinar_enzyme_story_enzymes, 91f, false)
        cargoKey(c, R.string.health_atlas_acinar_enzyme_story_precursors, 259f, true)
    }

    private fun cargoKey(c: Canvas, @StringRes res: Int, center: Float, precursor: Boolean) {
        val width = cargoKeyWidths.getOrPut(res) {
            paint.textSize = 13f
            paint.measureText(context.getString(res)).coerceAtMost(126f)
        }
        cargo(c, center - width / 2f - 3f, 321f, precursor, 4.3f)
        label(c, res, center + 8f, 325f, 126f)
    }

    private fun fluidMark(c: Canvas, x: Float, y: Float) {
        line(c, x - 4f, y + 1f, x + 1f, y - 1f, fluidInk, 1.7f)
        line(c, x, y + 3f, x + 5f, y + 1f, fluidInk, 1.5f)
    }

    private fun callout(
        c: Canvas, @StringRes res: Int, x: Float, y: Float, w: Float,
        lx: Float, ly: Float, tx: Float, ty: Float,
    ) {
        line(c, lx, ly, tx, ty, guide, 1.05f)
        disc(c, tx, ty, 1.55f, guide)
        label(c, res, x, y, w)
    }

    private fun tube(c: Canvas, p: Path, outer: Float, inner: Float) {
        stroke(c, p, ductEdge, outer)
        stroke(c, p, lumen, inner)
    }

    private fun filled(c: Canvas, path: Path, color: Long, edge: Long) {
        ink(color); c.drawPath(path, paint)
        stroke(c, path, edge, 1.2f)
    }

    private fun filled(c: Canvas, path: Path, shader: Shader, edge: Long) {
        ink(cream); paint.shader = shader; c.drawPath(path, paint); paint.shader = null
        stroke(c, path, edge, 1.2f)
    }

    private fun mix(a: Float, b: Float, p: Float) = a + (b - a) * p
    private fun shape(build: Path.() -> Unit) = Path().apply(build)
}
