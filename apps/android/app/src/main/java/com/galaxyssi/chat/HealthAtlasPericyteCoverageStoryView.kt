package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import com.galaxyssi.chat.HealthAtlasPericyteCoverageAssignment.COOPERATION
import com.galaxyssi.chat.HealthAtlasPericyteCoverageAssignment.INTERFACE
import com.galaxyssi.chat.HealthAtlasPericyteCoverageAssignment.WRAP
import com.galaxyssi.chat.R.string

internal class HealthAtlasPericyteCoverageStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val muralFill = 0xff80bbb0
    private val muralEdge = 0xff286b66
    private val liningFill = 0xffe2a7a6
    private val liningEdge = 0xff905765
    private val matrixFill = 0xffeddbad
    private val matrixEdge = 0xffad8650
    private val lumenFill = 0xffffe8df
    private val focus = 0xfffff3a1
    private val guide = 0xff50686a
    private val slide = 0xfffbf6e9
    private val sleeve = Path().apply { addRoundRect(27f, 127f, 333f, 247f, 16f, 16f, Path.Direction.CW) }
    private val window = Path().apply { addRoundRect(28f, 158f, 332f, 216f, 9f, 9f, Path.Direction.CW) }
    private val profile = Path().apply {
        moveTo(44f, 130f)
        cubicTo(83f, 125f, 106f, 127f, 125f, 117f)
        cubicTo(135f, 111f, 135f, 95f, 159f, 94f)
        cubicTo(181f, 92f, 184f, 109f, 204f, 118f)
        cubicTo(227f, 126f, 271f, 122f, 308f, 133f)
        cubicTo(274f, 130f, 249f, 131f, 228f, 136f)
        cubicTo(214f, 140f, 208f, 149f, 204f, 154f)
        cubicTo(203f, 145f, 206f, 140f, 208f, 135f)
        cubicTo(192f, 132f, 183f, 124f, 169f, 127f)
        cubicTo(152f, 132f, 140f, 129f, 127f, 134f)
        cubicTo(104f, 136f, 81f, 129f, 44f, 130f)
        close()
    }
    private val wrap = Path().apply {
        moveTo(219f, 91f)
        cubicTo(247f, 107f, 263f, 135f, 264f, 166f)
        cubicTo(266f, 196f, 252f, 220f, 238f, 234f)
        cubicTo(226f, 243f, 214f, 246f, 205f, 246f)
        cubicTo(241f, 230f, 253f, 197f, 251f, 169f)
        cubicTo(250f, 141f, 232f, 123f, 213f, 111f)
        cubicTo(195f, 101f, 173f, 91f, 145f, 99f)
        cubicTo(164f, 83f, 199f, 80f, 219f, 91f)
        close()
    }
    private val wrapTrace = track(Path().apply {
        moveTo(214f, 99f)
        cubicTo(241f, 117f, 257f, 141f, 257f, 170f)
        cubicTo(259f, 201f, 243f, 229f, 212f, 244f)
    })
    private val matrix = Path().apply {
        moveTo(29f, 155f)
        cubicTo(83f, 156f, 104f, 156f, 127f, 128f)
        cubicTo(150f, 96f, 183f, 96f, 218f, 116f)
        cubicTo(244f, 131f, 269f, 144f, 331f, 148f)
        lineTo(331f, 193f)
        lineTo(29f, 194f)
        close()
    }
    private val liningDetail = Path().apply {
        moveTo(29f, 189f)
        cubicTo(80f, 175f, 149f, 174f, 174f, 186f)
        quadTo(189f, 205f, 207f, 185f)
        cubicTo(248f, 171f, 281f, 184f, 331f, 189f)
        lineTo(331f, 238f)
        cubicTo(232f, 228f, 109f, 244f, 29f, 233f)
        close()
    }
    private val muralDetail = Path().apply {
        moveTo(48f, 161f)
        cubicTo(98f, 161f, 115f, 149f, 135f, 126f)
        cubicTo(150f, 110f, 185f, 110f, 211f, 125f)
        cubicTo(244f, 143f, 272f, 150f, 304f, 155f)
        cubicTo(257f, 164f, 227f, 150f, 207f, 169f)
        quadTo(198f, 177f, 200f, 191f)
        quadTo(190f, 203f, 182f, 192f)
        quadTo(185f, 175f, 175f, 168f)
        cubicTo(144f, 149f, 108f, 177f, 48f, 161f)
        close()
    }

    init { tag = "atlas-function-pericyte-coverage-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        rounded(c, 16f, 20f, 344f, 340f, 10f, slide)
        when (step) {
            WRAP -> crossSection(c, t)
            INTERFACE -> wallDetail(c, t)
            COOPERATION -> lengthwise(c, t, true)
            else -> lengthwise(c, t, false)
        }
    }

    private fun lengthwise(c: Canvas, t: Float, cooperation: Boolean) {
        label(c, string.health_atlas_pericyte_coverage_art_lengthwise, 180f, 46f, 280f)
        ink(matrixFill); c.drawPath(sleeve, paint)
        rounded(c, 28f, 138f, 332f, 237f, 13f, liningFill)
        for (i in 0..4) {
            val x = 54f + 62f * i
            oval(c, x - 12f, 144f, x + 12f, 152f, liningEdge, liningEdge)
            oval(c, x - 12f, 221f, x + 12f, 230f, liningEdge, liningEdge)
            if (i < 4) {
                line(c, x + 32f, 139f, x + 34f, 157f, liningEdge, 1.2f)
                line(c, x + 29f, 216f, x + 35f, 236f, liningEdge, 1.2f)
            }
        }
        c.save()
        c.clipPath(window)
        ink(lumenFill); c.drawPath(window, paint)
        for (i in 0..3) {
            val x = 28f + 304f * ((t + .25f * i) % 1f)
            val y = if (i % 2 == 0) 172f else 203f
            oval(c, x - 13f, y - 6f, x + 13f, y + 6f, 0xffd98983, liningEdge)
            oval(c, x - 6f, y - 2f, x + 6f, y + 2f, liningFill, liningFill)
        }
        c.restore()
        stroke(c, window, liningEdge, 1.2f)
        stroke(c, sleeve, matrixEdge, 1.3f)
        ink(muralFill); c.drawPath(profile, paint)
        stroke(c, profile, muralEdge, 1.35f)
        oval(c, 148f, 101f, 173f, 118f, muralEdge, muralEdge)
        label(c, string.health_atlas_pericyte_coverage_art_lumen, 180f, 192f, 110f)
        callout(c, string.health_atlas_pericyte_coverage_art_cell, 158f, 77f, 155f, 157f, 97f)
        callout(c, string.health_atlas_pericyte_coverage_art_lining, 87f, 282f, 123f, 105f, 226f)
        if (cooperation) {
            val mark = 2.5f + 1.1f * (1f + wave(t))
            line(c, 91f, 241f, 269f, 241f, focus, mark)
            callout(c, string.health_atlas_pericyte_coverage_art_matrix, 234f, 319f, 190f, 244f, 242f)
        }
    }

    private fun crossSection(c: Canvas, t: Float) {
        label(c, string.health_atlas_pericyte_coverage_art_cross_section, 180f, 46f, 280f)
        disc(c, 170f, 173f, 81f, matrixFill, matrixEdge)
        disc(c, 170f, 173f, 70f, liningFill, liningEdge)
        for (i in 0..3) {
            c.save()
            c.rotate(16f + i * 90f, 170f, 173f)
            oval(c, 156f, 107f, 184f, 118f, liningEdge, liningEdge)
            c.rotate(43f, 170f, 173f)
            line(c, 170f, 103f, 170f, 120f, liningEdge, 1.2f)
            c.restore()
        }
        disc(c, 170f, 173f, 55f, lumenFill, liningEdge)
        ink(muralFill); c.drawPath(wrap, paint)
        stroke(c, wrap, muralEdge, 1.45f)
        oval(c, 178f, 78f, 226f, 109f, muralFill, muralEdge)
        oval(c, 188f, 84f, 211f, 101f, muralEdge, muralEdge)
        at(wrapTrace, .08f + .83f * t) { x, y -> disc(c, x, y, 4.1f, focus, muralEdge) }
        label(c, string.health_atlas_pericyte_coverage_art_lumen, 170f, 177f, 97f)
        callout(c, string.health_atlas_pericyte_coverage_art_cell, 257f, 73f, 140f, 215f, 88f)
        callout(c, string.health_atlas_pericyte_coverage_art_extension, 269f, 285f, 130f, 244f, 228f)
        callout(c, string.health_atlas_pericyte_coverage_art_matrix, 104f, 313f, 160f, 127f, 239f)
    }

    private fun wallDetail(c: Canvas, t: Float) {
        label(c, string.health_atlas_pericyte_coverage_art_detail, 180f, 46f, 280f)
        rounded(c, 29f, 214f, 331f, 279f, 8f, lumenFill)
        ink(matrixFill); c.drawPath(matrix, paint)
        stroke(c, matrix, matrixEdge, 1.2f)
        ink(liningFill); c.drawPath(liningDetail, paint)
        stroke(c, liningDetail, liningEdge, 1.4f)
        ink(muralFill); c.drawPath(muralDetail, paint)
        stroke(c, muralDetail, muralEdge, 1.4f)
        oval(c, 151f, 122f, 194f, 141f, muralEdge, muralEdge)
        oval(c, 83f, 199f, 130f, 219f, liningEdge, liningEdge)
        val pulse = 1f + wave(t - .25f)
        ink(focus, 2.3f); c.drawCircle(191f, 192f, 13f + 5f * pulse, paint)
        label(c, string.health_atlas_pericyte_coverage_art_lumen, 167f, 259f, 110f)
        callout(c, string.health_atlas_pericyte_coverage_art_cell, 100f, 83f, 145f, 155f, 124f)
        callout(c, string.health_atlas_pericyte_coverage_art_matrix, 258f, 104f, 152f, 273f, 146f)
        callout(c, string.health_atlas_pericyte_coverage_art_contact, 262f, 312f, 142f, 191f, 198f)
        callout(c, string.health_atlas_pericyte_coverage_art_lining, 75f, 296f, 109f, 61f, 229f)
    }

    private fun callout(c: Canvas, res: Int, x: Float, y: Float, width: Float, tipX: Float, tipY: Float) {
        val tail = if (y > tipY) y - 15f else y + 5f
        line(c, x, tail, tipX, tipY, guide, 1.1f)
        disc(c, tipX, tipY, 2.3f, cream, guide)
        label(c, res, x, y, width)
    }
}
