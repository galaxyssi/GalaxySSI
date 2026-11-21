package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader
import androidx.annotation.StringRes

internal object HealthAtlasCholangiocyteMotion {
    fun stream(t: Float, offset: Float) =
        (HealthAtlasFunctionStory.safePhase(t) * .67f + offset).let { it - kotlin.math.floor(it) }

    fun exchange(t: Float, index: Int) = advance(t, .035f + index * .18f, .58f)

    fun osmosis(t: Float, index: Int) = advance(t, .02f + index * .12f, .60f)

    private fun advance(t: Float, start: Float, span: Float): Float {
        val p = ((HealthAtlasFunctionStory.safePhase(t) - start) / span).coerceIn(0f, 1f)
        return p * p * (3f - 2f * p)
    }
}

internal class HealthAtlasCholangiocyteStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val motion = HealthAtlasCholangiocyteMotion
    private val guide = 0xff405c67
    private val edge = 0xff527b79
    private val mint = 0xffa0c2ad
    private val lumenLight = 0xfff0f2d3
    private val bileInk = 0xff916820
    private val ionInk = 0xff2b7569
    private val chlorideInk = 0xff77528b
    private val waterInk = 0xff326c95
    private val cellInk = 0xff826779
    private val tissue = shade(239f, 297f, 0xffcecbdc, 0xfff2e8e6)
    private val liverGradient = shade(78f, 258f, 0xfff3e7ed, 0xffbeadc8)
    private val channelGradient = shade(132f, 208f, 0xffe2ebcc, 0xffb4cfb0)
    private val closeLumen = shade(90f, 155f, 0xfff3f5dc, 0xffccdec4)
    private val cellShade = shade(0f, 95f, 0xfff5e8e6, 0xffd2b8cc)
    private val focusShade = shade(0f, 95f, 0xfff5e8d8, 0xffd5adc4)
    private val nucleus = shade(52f, 81f, 0xffd6bad6, 0xff9f82ad)

    private val hepaticTissue = shape {
        moveTo(44f, 111f)
        cubicTo(72f, 82f, 111f, 76f, 150f, 77f)
        cubicTo(178f, 76f, 192f, 96f, 216f, 94f)
        cubicTo(250f, 88f, 302f, 91f, 315f, 120f)
        cubicTo(330f, 155f, 288f, 178f, 253f, 184f)
        cubicTo(223f, 189f, 209f, 207f, 180f, 217f)
        cubicTo(143f, 225f, 131f, 247f, 87f, 244f)
        cubicTo(49f, 242f, 31f, 223f, 32f, 191f)
        cubicTo(27f, 160f, 28f, 129f, 44f, 111f)
        close()
    }
    private val hepaticVeils = shape {
        moveTo(46f, 129f); cubicTo(73f, 98f, 107f, 95f, 141f, 91f)
        moveTo(44f, 144f); cubicTo(69f, 117f, 104f, 110f, 124f, 111f)
        moveTo(46f, 210f); cubicTo(66f, 228f, 103f, 226f, 127f, 215f)
        moveTo(50f, 221f); cubicTo(74f, 238f, 111f, 235f, 141f, 218f)
        moveTo(149f, 96f); cubicTo(174f, 101f, 185f, 114f, 196f, 107f)
        moveTo(264f, 101f); cubicTo(286f, 101f, 303f, 108f, 306f, 121f)
        moveTo(296f, 149f); cubicTo(278f, 176f, 232f, 171f, 210f, 191f)
        moveTo(272f, 163f); cubicTo(246f, 168f, 233f, 168f, 219f, 179f)
    }
    private val ductTwigs = shape {
        moveTo(63f, 130f); quadTo(79f, 139f, 91f, 145f)
        moveTo(89f, 112f); quadTo(100f, 129f, 105f, 150f)
        moveTo(125f, 116f); quadTo(128f, 138f, 121f, 155f)
        moveTo(64f, 184f); quadTo(91f, 192f, 116f, 180f)
        moveTo(78f, 206f); quadTo(92f, 192f, 105f, 185f)
        moveTo(134f, 201f); quadTo(137f, 182f, 144f, 167f)
        moveTo(225f, 115f); quadTo(222f, 127f, 215f, 140f)
        moveTo(264f, 145f); quadTo(243f, 134f, 229f, 134f)
        moveTo(208f, 167f); quadTo(202f, 156f, 188f, 155f)
    }
    private val smallDucts = shape {
        leftDuct()
        moveTo(107f, 183f); quadTo(126f, 174f, 145f, 168f)
        rightDuct()
    }
    private val trunk = shape { moveTo(157f, 174f); downDuct() }
    private val orientStreams = arrayOf(
        track(shape { leftDuct(); downDuct() }),
        track(shape { rightDuct(); downDuct() }),
    )

    private val openLumen = shape {
        moveTo(55f, 130f)
        cubicTo(112f, 127f, 243f, 128f, 302f, 132f)
        cubicTo(331f, 143f, 333f, 192f, 306f, 210f)
        cubicTo(252f, 221f, 124f, 217f, 55f, 211f)
        cubicTo(28f, 202f, 28f, 147f, 55f, 130f)
        close()
    }
    private val lumenRibbons = arrayOf(
        track(shape { moveTo(41f, 166f); cubicTo(133f, 145f, 218f, 177f, 306f, 153f) }),
        track(shape { moveTo(42f, 183f); cubicTo(121f, 178f, 212f, 192f, 312f, 175f) }),
        track(shape { moveTo(48f, 197f); cubicTo(133f, 192f, 215f, 212f, 315f, 192f) }),
    )
    private val wallFloor = shape {
        moveTo(48f, 243f); cubicTo(127f, 239f, 215f, 248f, 311f, 240f)
        lineTo(314f, 273f); cubicTo(227f, 284f, 148f, 264f, 49f, 278f)
        quadTo(29f, 268f, 48f, 243f); close()
    }
    private val cellShape = shape {
        moveTo(1f, 5f); cubicTo(13f, -1f, 48f, -1f, 59f, 5f)
        cubicTo(62f, 23f, 57f, 31f, 59f, 49f)
        cubicTo(58f, 69f, 63f, 92f, 52f, 93f)
        cubicTo(43f, 95f, 14f, 96f, 7f, 91f)
        cubicTo(-1f, 85f, 1f, 69f, 0f, 52f)
        cubicTo(2f, 33f, -2f, 18f, 1f, 5f); close()
    }
    private val cellRelief = shape {
        moveTo(5f, 19f); cubicTo(13f, 13f, 42f, 13f, 54f, 17f)
        moveTo(7f, 25f); quadTo(16f, 19f, 28f, 21f)
        moveTo(13f, 42f); quadTo(17f, 35f, 29f, 37f)
        moveTo(40f, 35f); quadTo(50f, 35f, 50f, 43f)
        moveTo(9f, 76f); quadTo(17f, 82f, 24f, 82f)
    }

    private val closeField = shape {
        moveTo(44f, 97f); cubicTo(130f, 85f, 224f, 93f, 307f, 99f)
        quadTo(323f, 106f, 313f, 148f)
        cubicTo(218f, 161f, 123f, 147f, 45f, 155f)
        quadTo(33f, 131f, 44f, 97f); close()
    }
    private val tissueField = shape {
        moveTo(44f, 242f); cubicTo(106f, 244f, 222f, 247f, 312f, 238f)
        quadTo(321f, 259f, 308f, 282f)
        cubicTo(233f, 299f, 145f, 272f, 54f, 287f)
        quadTo(34f, 279f, 44f, 242f); close()
    }
    private val fibers = shape {
        moveTo(52f, 270f); cubicTo(106f, 258f, 141f, 269f, 168f, 269f)
        moveTo(59f, 277f); quadTo(100f, 268f, 144f, 274f)
        moveTo(237f, 268f); quadTo(275f, 272f, 309f, 260f)
        moveTo(242f, 275f); quadTo(273f, 284f, 303f, 269f)
    }
    private val bicarbonateCourse = shape {
        moveTo(151f, 197f); cubicTo(156f, 183f, 171f, 172f, 171f, 154f)
        cubicTo(169f, 134f, 145f, 122f, 116f, 108f)
    }
    private val chlorideCourse = shape {
        moveTo(245f, 108f); cubicTo(214f, 119f, 187f, 134f, 187f, 154f)
        cubicTo(186f, 173f, 205f, 182f, 211f, 205f)
    }
    private val bicarbonateTrack = track(bicarbonateCourse)
    private val chlorideTrack = track(chlorideCourse)
    private val exchangerLeft = shape {
        moveTo(161f, 147f); cubicTo(167f, 150f, 165f, 157f, 161f, 161f)
    }
    private val exchangerMiddle = shape {
        moveTo(179f, 146f); cubicTo(175f, 150f, 182f, 156f, 179f, 162f)
    }
    private val exchangerRight = shape {
        moveTo(196f, 147f); cubicTo(191f, 151f, 194f, 158f, 198f, 161f)
    }
    private val waterCourse = shape {
        moveTo(173f, 280f); cubicTo(185f, 264f, 198f, 261f, 199f, 246f)
        cubicTo(199f, 222f, 219f, 212f, 215f, 190f)
        cubicTo(212f, 174f, 214f, 165f, 214f, 153f)
        cubicTo(213f, 127f, 239f, 108f, 278f, 111f)
    }
    private val waterTrack = track(waterCourse)

    private val bowel = shape {
        moveTo(242f, 98f)
        cubicTo(284f, 121f, 299f, 157f, 284f, 209f)
        cubicTo(272f, 250f, 237f, 269f, 192f, 265f)
    }
    private val folds = shape {
        moveTo(269f, 98f); quadTo(266f, 109f, 256f, 113f)
        moveTo(280f, 108f); quadTo(275f, 120f, 266f, 123f)
        moveTo(289f, 120f); quadTo(287f, 131f, 275f, 134f)
        moveTo(298f, 135f); quadTo(294f, 146f, 282f, 147f)
        moveTo(304f, 151f); quadTo(298f, 159f, 287f, 161f)
        moveTo(306f, 169f); quadTo(299f, 177f, 290f, 173f)
        moveTo(304f, 187f); quadTo(298f, 190f, 289f, 187f)
        moveTo(300f, 204f); quadTo(295f, 205f, 284f, 201f)
        moveTo(296f, 219f); quadTo(285f, 220f, 280f, 213f)
        moveTo(287f, 237f); quadTo(276f, 232f, 273f, 225f)
        moveTo(277f, 250f); quadTo(267f, 247f, 264f, 236f)
        moveTo(263f, 262f); quadTo(254f, 256f, 253f, 246f)
        moveTo(245f, 271f); quadTo(237f, 265f, 239f, 254f)
        moveTo(226f, 278f); quadTo(219f, 270f, 223f, 260f)
        moveTo(209f, 282f); quadTo(204f, 274f, 207f, 264f)
    }
    private val outlet = shape { outletDuct() }
    private val downstream = track(shape {
        outletDuct()
        cubicTo(288f, 188f, 283f, 208f, 275f, 226f)
        quadTo(259f, 252f, 232f, 259f)
    })
    private val current = Path()
    private val symbol = Path()

    init { tag = "atlas-function-cholangiocyte-bile-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> enter(c, t)
            1 -> lining(c, t)
            2 -> exchange(c, t)
            3 -> water(c, t)
            4 -> carry(c, t)
        }
    }

    private fun enter(c: Canvas, t: Float) {
        filled(c, hepaticTissue, liverGradient, 0xff937f9d)
        stroke(c, hepaticVeils, 0xffebdae6, 3.2f)
        stroke(c, hepaticVeils, 0xfff9eced, 1.15f)
        tube(c, ductTwigs, 5.5f)
        tube(c, smallDucts, 12f)
        tube(c, trunk, 23f)
        // Restore the light center at the branch junction where strokes meet.
        stroke(c, smallDucts, lumenLight, 5.1f)
        for ((i, course) in orientStreams.withIndex()) {
            for (j in 0..2) {
                val f = motion.stream(t, .05f + i * .08f + j * .28f)
                at(course, f) { x, y -> bileMark(c, x, y, 3.5f) }
            }
        }
        callout(c, R.string.health_atlas_cholangiocyte_story_liver, 81f, 56f, 118f, 81f, 65f, 65f, 104f)
        callout(c, R.string.health_atlas_cholangiocyte_story_small_duct, 264f, 67f, 130f, 262f, 76f, 229f, 134f)
        callout(c, R.string.health_atlas_cholangiocyte_story_larger_duct, 218f, 327f, 139f, 217f, 313f, 198f, 252f)
    }

    private fun lining(c: Canvas, t: Float) {
        filled(c, wallFloor, tissue, 0xffb7a6bc)
        filled(c, openLumen, channelGradient, edge)
        for (i in 0..5) {
            val x = 48f + i * 44f
            epithelialCell(c, x, 138f + i * .7f, 44f, -45f, false)
            epithelialCell(c, x, 208f + i * .7f, 44f, 50f, i == 4)
        }
        for ((i, course) in lumenRibbons.withIndex()) {
            flowRibbon(c, course, motion.stream(t, .18f * i), .23f, 0xffecf3d8, 2.4f)
            for (j in 0..2) {
                val p = motion.stream(t, .08f + .12f * i + .29f * j)
                at(course, .03f + .92f * p) { x, y -> bileMark(c, x, y, 4.2f) }
            }
        }
        line(c, 84f, 72f, 34f, 140f, guide, 1f)
        callout(c, R.string.health_atlas_cholangiocyte_story_lumen, 84f, 65f, 114f, 34f, 140f, 49f, 171f)
        callout(c, R.string.health_atlas_cholangiocyte_story_apical, 101f, 304f, 123f, 97f, 289f, 126f, 210f)
        callout(c, R.string.health_atlas_cholangiocyte_story_cell, 250f, 310f, 126f, 249f, 294f, 238f, 233f)
    }

    private fun exchange(c: Canvas, t: Float) {
        closeWall(c)
        stroke(c, bicarbonateCourse, 0xff93b9a4, 1.6f)
        stroke(c, chlorideCourse, 0xffb798bd, 1.6f)
        chevron(c, 129f, 114f, -1f, -.48f, ionInk)
        chevron(c, 208f, 197f, .26f, 1f, chlorideInk)
        channelStroke(c, exchangerLeft, ionInk)
        channelStroke(c, exchangerMiddle, ionInk)
        channelStroke(c, exchangerRight, ionInk)
        for (i in 0..2) {
            val p = motion.exchange(t, i)
            if (p > 0f) {
                val fan = ((p - .9f) * 10f).coerceAtLeast(0f)
                at(bicarbonateTrack, p) { x, y -> bicarbonateMark(c, x - fan * (10f + i * 13f), y + fan * 13f, 4.6f) }
                at(chlorideTrack, p) { x, y -> chlorideMark(c, x + fan * i * 4f, y + fan * (4f + i * 8f), 4.3f) }
            }
        }
        bicarbonateMark(c, 116f, 108f, 5.2f)
        chlorideMark(c, 245f, 108f, 4.7f)
        callout(c, R.string.health_atlas_cholangiocyte_story_bicarbonate, 80f, 59f, 98f, 83f, 68f, 111f, 103f)
        callout(c, R.string.health_atlas_cholangiocyte_story_chloride, 275f, 59f, 83f, 273f, 69f, 249f, 103f)
        callout(c, R.string.health_atlas_cholangiocyte_story_exchanger, 180f, 80f, 120f, 180f, 90f, 179f, 146f)
    }

    private fun water(c: Canvas, t: Float) {
        closeWall(c)
        stroke(c, waterCourse, 0xffadd0d8, 8f)
        stroke(c, waterCourse, 0xfff0f8ef, 2.5f)
        chevron(c, 216f, 166f, 0f, -1f, waterInk)
        waterPore(c, 214f, 153f)
        waterPore(c, 199f, 246f)
        for (i in 0..3) {
            val p = motion.osmosis(t, i)
            if (p > 0f) {
                val fan = ((p - .9f) * 10f).coerceAtLeast(0f)
                at(waterTrack, p) { x, y -> waterMark(c, x + fan * i * 8f, y + fan * (i % 2 * 11f - 4f), 5.1f) }
            }
        }
        for (i in 0..2) {
            val x = 78f + i * 29f + motion.stream(t, .2f * i) * 18f
            bicarbonateMark(c, x, 130f - i * 4f, 3.8f)
        }
        callout(c, R.string.health_atlas_cholangiocyte_story_lumen, 88f, 67f, 103f, 88f, 76f, 86f, 103f)
        callout(c, R.string.health_atlas_cholangiocyte_story_water_channel, 221f, 64f, 124f,
            220f, 75f, 208f, 148f)
        callout(c, R.string.health_atlas_cholangiocyte_story_tissue_side, 105f, 321f, 107f,
            111f, 307f, 120f, 272f)
    }

    private fun carry(c: Canvas, t: Float) {
        stroke(c, bowel, 0xff947a8e, 48f)
        stroke(c, bowel, 0xffc8aab9, 45f)
        stroke(c, bowel, 0xffe4c9ce, 37f)
        stroke(c, bowel, 0xfff9e8e1, 24f)
        stroke(c, folds, 0xffbd94a6, 1.4f)
        tube(c, outlet, 34f)
        disc(c, 267f, 182f, 6.3f, 0xffdcdfc5, edge)
        flowRibbon(c, downstream, motion.stream(t, .29f), .31f, 0xffa6cbbb, 4.2f)
        for (i in 0..11) {
            val f = motion.stream(t, .08f * i)
            at(downstream, .025f + .95f * f) { x, y ->
                val dy = (i % 3 - 1) * 4.8f
                when (i % 4) {
                    0 -> waterMark(c, x, y + dy, 3.9f)
                    2 -> bicarbonateMark(c, x, y + dy, 3.6f)
                    else -> bileMark(c, x, y + dy, 3.4f)
                }
            }
        }
        callout(c, R.string.health_atlas_cholangiocyte_story_modified_bile, 122f, 73f, 143f,
            129f, 83f, 152f, 140f)
        callout(c, R.string.health_atlas_cholangiocyte_story_duodenum, 261f, 319f, 129f,
            264f, 305f, 253f, 267f)
    }

    private fun closeWall(c: Canvas) {
        filled(c, closeField, closeLumen, 0xffa9c0a6)
        filled(c, tissueField, tissue, 0xffb9acbd)
        stroke(c, fibers, 0xffb8adc6, 1.6f)
        epithelialCell(c, 46f, 152f, 80f, 95f, false)
        epithelialCell(c, 126f, 151f, 109f, 98f, true)
        epithelialCell(c, 235f, 150f, 78f, 97f, false)
    }

    private fun epithelialCell(c: Canvas, x: Float, y: Float, w: Float, h: Float, focus: Boolean) {
        c.save()
        c.translate(x, y)
        c.scale(w / 60f, h / 95f)
        filled(c, cellShape, if (focus) focusShade else cellShade, cellInk)
        stroke(c, cellRelief, 0xfffbf0ec, 1.6f)
        oval(c, 18f, 53f, 40f, 81f, nucleus, 0xff886993)
        disc(c, 31f, 63f, 2.4f, 0xff7b6191)
        line(c, 7f, 3f, 53f, 3f, 0xff648986, 1.8f)
        for (i in 0..6) {
            val xx = 9f + i * 6.7f
            line(c, xx, 3f, xx - .35f, if (i % 3 == 0) -2.5f else -1f, edge, .85f)
        }
        disc(c, 2f, 8f, 2f, 0xff7c6b82)
        disc(c, 58f, 8f, 2f, 0xff7c6b82)
        c.restore()
    }

    private fun Path.leftDuct() {
        moveTo(83f, 141f); cubicTo(114f, 152f, 147f, 159f, 157f, 174f)
    }

    private fun Path.rightDuct() {
        moveTo(278f, 121f)
        cubicTo(257f, 124f, 241f, 129f, 229f, 134f)
        cubicTo(201f, 144f, 173f, 157f, 157f, 174f)
    }

    private fun Path.downDuct() {
        cubicTo(170f, 193f, 172f, 220f, 198f, 252f)
        quadTo(205f, 267f, 220f, 283f)
    }

    private fun Path.outletDuct() {
        moveTo(57f, 129f)
        cubicTo(106f, 117f, 125f, 132f, 152f, 140f)
        cubicTo(197f, 155f, 227f, 158f, 267f, 182f)
    }

    private fun tube(c: Canvas, course: Path, w: Float) {
        stroke(c, course, edge, w)
        stroke(c, course, mint, w * .76f)
        stroke(c, course, lumenLight, w * .47f)
    }

    private fun flowRibbon(c: Canvas, course: PathMeasure, p: Float, span: Float, color: Long, w: Float) {
        current.rewind()
        val len = course.length
        course.getSegment(p * len, (p + span).coerceAtMost(1f) * len, current, true)
        if (p + span > 1f) course.getSegment(0f, (p + span - 1f) * len, current, true)
        stroke(c, current, color, w)
    }

    private fun chevron(c: Canvas, x: Float, y: Float, dx: Float, dy: Float, color: Long) {
        line(c, x - 5f * dx + 3f * dy, y - 5f * dy - 3f * dx, x, y, color, 1.3f)
        line(c, x - 5f * dx - 3f * dy, y - 5f * dy + 3f * dx, x, y, color, 1.3f)
    }

    private fun bileMark(c: Canvas, x: Float, y: Float, r: Float) =
        oval(c, x - r, y - r * .48f, x + r, y + r * .48f, 0xffe2bf73, bileInk)

    private fun bicarbonateMark(c: Canvas, x: Float, y: Float, r: Float) {
        symbol.rewind()
        symbol.moveTo(x, y - r); symbol.lineTo(x + r, y)
        symbol.lineTo(x, y + r); symbol.lineTo(x - r, y); symbol.close()
        ink(0xffd6edca); c.drawPath(symbol, paint)
        stroke(c, symbol, ionInk, 1.1f)
    }

    private fun chlorideMark(c: Canvas, x: Float, y: Float, r: Float) =
        disc(c, x, y, r, 0xfff0deed, chlorideInk)

    private fun waterMark(c: Canvas, x: Float, y: Float, r: Float) {
        symbol.rewind()
        symbol.moveTo(x, y - r)
        symbol.cubicTo(x + r * .4f, y - r * .45f, x + r, y, x + r * .73f, y + r * .55f)
        symbol.cubicTo(x + r * .42f, y + r * 1.08f, x - r * .48f, y + r * 1.08f, x - r * .73f, y + r * .55f)
        symbol.cubicTo(x - r, y, x - r * .4f, y - r * .45f, x, y - r); symbol.close()
        ink(0xffdeeff4); c.drawPath(symbol, paint)
        stroke(c, symbol, waterInk, 1.1f)
    }

    private fun waterPore(c: Canvas, x: Float, y: Float) {
        for (side in -1..1 step 2) {
            val dx = side * 6f
            line(c, x + dx, y - 5f, x + dx * .77f, y, waterInk, 4.1f)
            line(c, x + dx * .77f, y, x + dx, y + 5f, waterInk, 4.1f)
        }
    }

    private fun channelStroke(c: Canvas, path: Path, color: Long) {
        stroke(c, path, color, 6f)
        stroke(c, path, 0xffbdd0b4, 3f)
    }

    private fun filled(c: Canvas, path: Path, fill: Shader, border: Long) {
        ink(cream); paint.shader = fill; c.drawPath(path, paint); paint.shader = null
        stroke(c, path, border, 1.15f)
    }

    private fun callout(
        c: Canvas, @StringRes res: Int, x: Float, baseline: Float, width: Float,
        fromX: Float, fromY: Float, toX: Float, toY: Float,
    ) {
        line(c, fromX, fromY, toX, toY, guide, 1f)
        disc(c, toX, toY, 1.7f, guide)
        label(c, res, x, baseline, width)
    }

    private fun shape(build: Path.() -> Unit) = Path().apply(build)

    companion object {
        const val EXCHANGE_REFERENCE_URL = "https://pubmed.ncbi.nlm.nih.gov/20041402/"
        const val WATER_REFERENCE_URL = "https://pubmed.ncbi.nlm.nih.gov/7528928/"
    }
}
