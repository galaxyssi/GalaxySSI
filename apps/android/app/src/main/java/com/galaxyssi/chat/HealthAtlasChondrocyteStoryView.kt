package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader
import androidx.annotation.StringRes

internal class HealthAtlasChondrocyteStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.CHONDROCYTE_MATRIX) {
    private val matrixFill = shade(84f, 263f, 0xffe5f2e8, 0xffbad9d3)
    private val territoryFill = shade(113f, 244f, 0xffcde8de, 0xff9fc7be)
    private val rimFill = shade(131f, 225f, 0xffaed6c9, 0xff81b5ac)
    private val cellFill = shade(141f, 208f, 0xffffeee1, 0xffdcacc2)
    private val tissueEdge = 0xff6d9e92
    private val rimEdge = 0xff488779
    private val cellEdge = 0xff9a627f
    private val fibrilInk = 0xffa77784
    private val newCollagen = 0xff974e69
    private val aggrecanInk = 0xff976733
    private val waterInk = 0xff397f9c
    private val leader = 0xff52656a
    private val detail = Path()
    private val segment = Path()
    private val position = FloatArray(2)
    private val tangent = FloatArray(2)

    private val patch = Path().apply {
        moveTo(25f, 105f)
        cubicTo(67f, 84f, 116f, 103f, 167f, 94f)
        cubicTo(216f, 86f, 285f, 88f, 334f, 103f)
        cubicTo(340f, 136f, 328f, 173f, 336f, 211f)
        quadTo(339f, 233f, 333f, 251f)
        cubicTo(294f, 267f, 240f, 252f, 189f, 259f)
        cubicTo(135f, 266f, 68f, 267f, 26f, 252f)
        cubicTo(17f, 214f, 29f, 159f, 25f, 105f)
        close()
    }
    private val territory = profile(175f, 177f, 70f, 60f)
    private val rim = profile(173f, 177f, 50f, 46f)
    private val lacuna = profile(173f, 176f, 41f, 37f)
    private val cell = profile(172f, 176f, 36f, 32f)
    private val golgi = Path().apply {
        for (i in 0..2) {
            val x = 184f + 4.5f * i
            moveTo(x, 169f + i * 2f)
            cubicTo(x + 9f, 176f, x + 9f, 188f, x - 1f, 195f - i * 2f)
        }
    }
    private val reticulum = Path().apply {
        moveTo(148f, 181f)
        cubicTo(144f, 163f, 154f, 151f, 175f, 154f)
        moveTo(150f, 187f)
        cubicTo(154f, 199f, 169f, 202f, 180f, 192f)
        moveTo(154f, 192f)
        quadTo(166f, 200f, 175f, 193f)
    }
    private val neighbors = listOf(
        neighbor(51f, 117f, 18f, 11f),
        neighbor(311f, 125f, 17f, 13f),
        neighbor(295f, 241f, 19f, 12f),
        neighbor(53f, 235f, 19f, 13f),
    )
    private val fibrils = listOf(
        curve(26f, 126f, 77f, 148f, 100f, 107f, 148f, 102f),
        curve(55f, 97f, 82f, 107f, 99f, 132f, 126f, 123f),
        curve(30f, 166f, 81f, 135f, 109f, 163f, 132f, 144f),
        curve(26f, 186f, 63f, 169f, 99f, 180f, 122f, 158f),
        curve(22f, 205f, 66f, 215f, 86f, 171f, 122f, 183f),
        curve(44f, 248f, 94f, 240f, 81f, 215f, 127f, 209f),
        curve(76f, 255f, 115f, 244f, 123f, 229f, 151f, 218f),
        curve(103f, 261f, 132f, 249f, 147f, 258f, 168f, 232f),
        curve(138f, 101f, 157f, 125f, 183f, 111f, 203f, 135f),
        curve(201f, 101f, 219f, 121f, 234f, 125f, 253f, 128f),
        curve(227f, 93f, 247f, 111f, 273f, 132f, 300f, 107f),
        curve(216f, 150f, 250f, 127f, 273f, 154f, 331f, 142f),
        curve(227f, 160f, 252f, 158f, 300f, 171f, 332f, 154f),
        curve(228f, 188f, 269f, 177f, 294f, 203f, 333f, 179f),
        curve(227f, 205f, 245f, 224f, 289f, 208f, 335f, 214f),
        curve(211f, 221f, 242f, 222f, 255f, 254f, 279f, 254f),
        curve(177f, 231f, 195f, 249f, 235f, 231f, 258f, 247f),
        curve(176f, 259f, 199f, 250f, 217f, 263f, 244f, 254f),
        curve(291f, 227f, 302f, 210f, 316f, 236f, 334f, 228f),
    )
    private val collagenRoutes = listOf(
        track(curve(151f, 169f, 135f, 161f, 125f, 169f, 109f, 172f)),
        track(curve(150f, 187f, 135f, 192f, 126f, 201f, 107f, 213f)),
    )
    private val collagenJoins = listOf(
        track(curve(109f, 172f, 96f, 178f, 79f, 173f, 59f, 178f)),
        track(curve(107f, 213f, 89f, 222f, 100f, 239f, 78f, 237f)),
    )
    private val focusContours = listOf(track(lacuna), track(rim), track(territory), track(fibrils[8]))
    private val carrier = curve(233f, 209f, 254f, 217f, 285f, 178f, 309f, 193f)
    private val deposits = listOf(
        Deposit(246f, 208f, -19f, track(curve(192f, 183f, 208f, 182f, 226f, 195f, 246f, 208f))),
        Deposit(269f, 198f, -34f, track(curve(194f, 181f, 219f, 174f, 245f, 185f, 269f, 198f))),
        Deposit(292f, 190f, -5f, track(curve(193f, 177f, 218f, 161f, 266f, 168f, 292f, 190f))),
    )

    init { tag = "atlas-function-chondrocyte-matrix-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val hydration = when {
            step < 3 -> .18f
            step == 3 -> .18f + .82f * ease(t, .03f, .95f)
            else -> 1f
        }
        val squeeze = if (step == 4) ease(t, 0f, .36f) * (1f - ease(t, .38f, .96f)) else 0f
        val scaleY = 1f - .19f * squeeze
        c.save()
        c.scale(1f, scaleY, 180f, MID_Y)
        drawMatrix(c, hydration, squeeze, step, t)
        drawCell(c)
        when (step) {
            0 -> traceZones(c, t)
            1 -> depositCollagen(c, t)
            2 -> releaseAggrecan(c, t)
        }
        if (step > 1) depositCollagen(c, 1f)
        if (step > 2) releaseAggrecan(c, 1f)
        c.restore()
        if (step == 4) drawCompression(c, t, squeeze, scaleY)
        drawLabels(c, scaleY)
    }

    private fun drawMatrix(c: Canvas, hydration: Float, squeeze: Float, step: Int, t: Float) {
        c.save()
        c.translate(0f, 4f)
        ink(0x1a386e65)
        c.drawPath(patch, paint)
        c.restore()
        filled(c, patch, matrixFill, tissueEdge, 1.5f)
        c.save()
        c.clipPath(patch)
        filled(c, territory, territoryFill, 0xff93bdb1, 1.2f)
        hydrationMarks(c, hydration, squeeze, step, t)
        fibrils.forEachIndexed { index, fiber ->
            stroke(c, fiber, 0xb1f9f2e7, 3.1f)
            stroke(c, fiber, fibrilInk, if (index % 3 == 0) 1.45f else 1f)
        }
        brush(c, 77f, 151f, -32f, .72f, 0xff997f58)
        brush(c, 98f, 224f, 36f, .61f, 0xff997f58)
        brush(c, 267f, 144f, 48f, .75f, 0xff997f58)
        brush(c, 193f, 242f, -31f, .68f, 0xff997f58)
        for (neighbor in neighbors) {
            ink(0xffb3d3c9)
            c.drawPath(neighbor.rim, paint)
            stroke(c, neighbor.rim, 0xff8db1aa, 1.05f)
            ink(0xffd6b8c9)
            c.drawPath(neighbor.cell, paint)
            oval(c, neighbor.x - 6f, neighbor.y - 3f, neighbor.x + 3f, neighbor.y + 4f,
                0xff9b7d9a, 0xff8f708c)
        }
        c.restore()
        filled(c, rim, rimFill, rimEdge, 1.4f)
        ink(0xffe7eee3)
        c.drawPath(lacuna, paint)
        stroke(c, lacuna, 0xff739c91, 1.15f)
    }

    private fun drawCell(c: Canvas) {
        filled(c, cell, cellFill, cellEdge, 1.65f)
        oval(c, 147f, 158f, 179f, 190f, 0xffb08bad, 0xff825c85)
        oval(c, 153f, 161f, 174f, 184f, 0xffbd9ab8, 0xffb08bad)
        disc(c, 166f, 175f, 4f, 0xff8e668d)
        stroke(c, reticulum, 0xfffaf1ee, 3.3f)
        stroke(c, reticulum, 0xffbd8da8, 1.45f)
        stroke(c, golgi, 0xffa16b83, 1.8f)
    }

    private fun traceZones(c: Canvas, t: Float) {
        focusContours.forEachIndexed { index, contour ->
            val f = ((t - .13f * index) / .56f).coerceIn(0f, 1f)
            val head = f * 1.34f
            val color = if (index == 3) newCollagen else 0xff286e63
            drawRun(c, contour, head - .34f, head, 0xeafff8e8, 5.8f)
            drawRun(c, contour, head - .34f, head, color, 3.2f)
        }
    }

    private fun depositCollagen(c: Canvas, t: Float) {
        for (i in collagenRoutes.indices) {
            val ride = ease(t, .04f + i * .21f, .57f + i * .19f)
            if (ride > 0f && ride < 1f && sample(collagenRoutes[i], ride)) {
                val x = position[0]
                val y = position[1]
                val dx = tangent[0] * 4.5f
                val dy = tangent[1] * 4.5f
                line(c, x - dx, y - dy, x + dx, y + dy, cream, 5.8f)
                line(c, x - dx, y - dy, x + dx, y + dy, newCollagen, 2.8f)
            }
            val growth = ease(t, .53f + i * .19f, .83f + i * .17f)
            drawRun(c, collagenJoins[i], 0f, growth, cream, 4.5f)
            drawRun(c, collagenJoins[i], 0f, growth, newCollagen, 2.3f)
        }
    }

    private fun releaseAggrecan(c: Canvas, t: Float) {
        stroke(c, carrier, 0xffa28864, 1.5f)
        deposits.forEachIndexed { index, deposit ->
            val f = ease(t, index * .16f, .56f + index * .20f)
            if (f == 0f) return@forEachIndexed
            if (f == 1f) {
                brush(c, deposit.x, deposit.y, deposit.angle, 1f, aggrecanInk)
            } else if (sample(deposit.route, f)) {
                brush(c, position[0], position[1], -62f + (deposit.angle + 62f) * f, .55f + .45f * f, aggrecanInk)
            }
        }
    }

    private fun hydrationMarks(c: Canvas, hydration: Float, squeeze: Float, step: Int, t: Float) {
        // Local wash and stream marks indicate extracellular water, not granules secreted by the cell.
        ink(0xff79c8da)
        paint.alpha = (111f * hydration * (1f - .56f * squeeze)).toInt()
        val extent = 10f + 15f * hydration
        c.drawOval(77f - extent, 132f, 93f + extent, 171f, paint)
        c.drawOval(245f - extent, 162f, 295f + extent, 223f, paint)

        for (side in -1..1 step 2) {
            for (i in 0..4) {
                val advance = if (step == 3) ease(t, .04f + .063f * i, .72f + .066f * i) else 0f
                val x = 180f + side * (if (step < 4) 139f - 40f * advance else 99f + 40f * squeeze) +
                    (i % 3 - 1) * 12f
                val y = 155f + 15f * i + side * 4f
                val alpha = if (step < 4) 60f + 132f * advance else 192f - 75f * squeeze
                waterMark(c, x, y, 7f + 5f * hydration, alpha.toInt())
            }
        }
    }

    private fun waterMark(c: Canvas, x: Float, y: Float, length: Float, alpha: Int) {
        detail.rewind()
        detail.moveTo(x - length * .5f, y + 1f)
        detail.quadTo(x - length * .19f, y - 3f, x + length * .12f, y)
        detail.quadTo(x + length * .28f, y + 1.5f, x + length * .5f, y - 1f)
        ink(waterInk, 1.65f)
        paint.alpha = alpha
        c.drawPath(detail, paint)
    }

    private fun brush(c: Canvas, x: Float, y: Float, angle: Float, scale: Float, color: Long) {
        c.save()
        c.translate(x, y)
        c.rotate(angle)
        c.scale(scale, scale)
        detail.rewind()
        detail.moveTo(0f, 0f)
        detail.quadTo(2f, -11f, 0f, -24f)
        for (i in 0..4) {
            val yy = -5f - i * 4f
            val width = if (i == 4) 4f else 7f
            detail.moveTo(1f, yy)
            detail.quadTo(-3f, yy, -width, yy - 4f)
            detail.moveTo(1f, yy - 1f)
            detail.quadTo(5f, yy - 1f, width + 1f, yy - 5f)
        }
        stroke(c, detail, 0xfff9ecd2, 3.2f)
        stroke(c, detail, color, 1.45f)
        c.restore()
    }

    private fun drawCompression(c: Canvas, t: Float, squeeze: Float, scaleY: Float) {
        val alpha = (215f * ease(t, 0f, .15f) * (1f - ease(t, .35f, .65f))).toInt()
        if (alpha == 0) return
        val color = (alpha.toLong() shl 24) or 0x87532e
        for (x in listOf(46f, 313f)) {
            val top = mappedY(94f, scaleY) - 3f
            val base = mappedY(260f, scaleY) + 3f
            val length = 13f + 5f * squeeze
            arrow(c, x, top - length, x, top, color)
            arrow(c, x, base + length, x, base, color)
        }
    }

    private fun drawLabels(c: Canvas, scaleY: Float) {
        callout(c, R.string.health_atlas_chondrocyte_story_label_lacuna, 74f, 58f, 112f,
            99f, 104f, 146f, mappedY(148f, scaleY), true)
        callout(c, R.string.health_atlas_chondrocyte_story_label_chondrocyte, 276f, 58f, 132f,
            256f, 96f, 198f, mappedY(158f, scaleY), true)
        callout(c, R.string.health_atlas_chondrocyte_story_label_interterritorial, 180f, 29f, 159f,
            180f, 82f, 172f, mappedY(108f, scaleY), true)
        callout(c, R.string.health_atlas_chondrocyte_story_label_pericellular, 89f, 306f, 151f,
            105f, 267f, 133f, mappedY(201f, scaleY), false)
        callout(c, R.string.health_atlas_chondrocyte_story_label_territorial, 268f, 306f, 151f,
            249f, 269f, 224f, mappedY(215f, scaleY), false)

        line(c, 22f, 321f, 338f, 321f, 0xffadc4ba, 1f)
        line(c, 19f, 339f, 32f, 336f, newCollagen, 2.5f)
        label(c, R.string.health_atlas_chondrocyte_story_label_collagen, 84f, 344f, 98f)
        brush(c, 142f, 344f, 16f, .54f, aggrecanInk)
        label(c, R.string.health_atlas_chondrocyte_story_label_aggrecan, 197f, 344f, 80f)
        waterMark(c, 268f, 340f, 16f, 255)
        label(c, R.string.health_atlas_chondrocyte_story_label_water, 306f, 344f, 51f)
    }

    private fun callout(
        c: Canvas, @StringRes id: Int, x: Float, baseline: Float, width: Float, elbowX: Float,
        elbowY: Float, anchorX: Float, anchorY: Float, down: Boolean,
    ) {
        label(c, id, x, baseline, width)
        val start = baseline + if (down) 6f else -16f
        line(c, x, start, elbowX, elbowY, leader, 1.05f)
        line(c, elbowX, elbowY, anchorX, anchorY, leader, 1.05f)
        disc(c, anchorX, anchorY, 2.2f, leader, cream)
    }

    private fun filled(c: Canvas, path: Path, shader: Shader, edge: Long, weight: Float) {
        ink(cream)
        paint.shader = shader
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, edge, weight)
    }

    private fun drawRun(c: Canvas, path: PathMeasure, from: Float, to: Float, color: Long, width: Float) {
        if (to <= 0f || from >= 1f || from >= to) return
        segment.rewind()
        val start = path.length * from.coerceIn(0f, 1f)
        val end = path.length * to.coerceIn(0f, 1f)
        if (path.getSegment(start, end, segment, true)) stroke(c, segment, color, width)
    }

    private fun sample(path: PathMeasure, f: Float) = path.getPosTan(path.length * f, position, tangent)

    private fun ease(t: Float, from: Float, to: Float): Float {
        val f = ((t - from) / (to - from)).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }

    private fun mappedY(y: Float, scale: Float) = MID_Y + (y - MID_Y) * scale

    private fun curve(
        x0: Float, y0: Float, x1: Float, y1: Float, x2: Float, y2: Float, x3: Float, y3: Float,
    ) = Path().apply {
        moveTo(x0, y0)
        cubicTo(x1, y1, x2, y2, x3, y3)
    }

    private fun profile(x: Float, y: Float, rx: Float, ry: Float) = Path().apply {
        moveTo(x - rx, y - .06f * ry)
        cubicTo(x - rx, y - .66f * ry, x - .48f * rx, y - ry, x + .08f * rx, y - ry)
        cubicTo(x + .67f * rx, y - ry, x + rx, y - .61f * ry, x + rx, y - .03f * ry)
        cubicTo(x + rx, y + .61f * ry, x + .47f * rx, y + ry, x - .12f * rx, y + ry)
        cubicTo(x - .71f * rx, y + ry, x - rx, y + .52f * ry, x - rx, y - .06f * ry)
        close()
    }

    private fun neighbor(x: Float, y: Float, rx: Float, ry: Float) =
        Neighbor(x, y, profile(x, y, rx, ry), profile(x, y, rx - 4f, ry - 3f))

    private data class Neighbor(val x: Float, val y: Float, val rim: Path, val cell: Path)
    private data class Deposit(val x: Float, val y: Float, val angle: Float, val route: PathMeasure)

    private companion object {
        const val MID_Y = 177f
    }
}
