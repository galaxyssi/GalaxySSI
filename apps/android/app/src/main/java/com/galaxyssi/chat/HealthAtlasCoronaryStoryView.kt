package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader
import kotlin.math.abs

internal class HealthAtlasCoronaryStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.CORONARY_PERFUSION) {
    private val wallInk = 0xff995f62
    private val artery = 0xffa1414f
    private val arteryFill = 0xffe69b86
    private val vein = 0xff3e7188
    private val veinFill = 0xff95bdc9
    private val leader = 0xff786969
    private val oxygen = 0xffb67822
    private val muscle = shade(84f, 215f, 0xfff7cbb3, 0xffcc777e)
    private val leftMuscle = shade(106f, 215f, 0xffecb09b, 0xffb86675)
    private val aorta = shade(20f, 111f, 0xfff7b5a0, 0xffc76b70)
    private val rootWash = shade(246f, 322f, 0xffffd9bd, 0xffe09082)
    private val pulmonary = shade(52f, 110f, 0xffdfebec, 0xff96b8c1)
    private val wallDetail = shade(250f, 326f, 0xffffe4cd, 0xffe6a39b)
    private val backMuscle = shade(249f, 331f, 0xfff7d1bb, 0xffd58e90)
    private val detail = Path()
    private val position = FloatArray(2)
    private val tangent = FloatArray(2)

    private val arch = shape {
        moveTo(142f, 108f)
        cubicTo(137f, 94f, 147f, 78f, 146f, 59f)
        cubicTo(145f, 31f, 162f, 18f, 186f, 18f)
        cubicTo(207f, 17f, 223f, 27f, 231f, 44f)
        quadTo(225f, 52f, 212f, 55f)
        cubicTo(207f, 45f, 199f, 43f, 189f, 45f)
        cubicTo(173f, 46f, 176f, 67f, 177f, 76f)
        quadTo(185f, 94f, 180f, 109f)
        close()
    }
    private val venaCava = shape {
        moveTo(113f, 42f)
        quadTo(123f, 36f, 133f, 43f)
        cubicTo(128f, 56f, 132f, 73f, 136f, 91f)
        lineTo(111f, 95f)
        quadTo(114f, 68f, 113f, 42f)
        close()
    }
    private val pulmonaryTrunk = shape {
        moveTo(163f, 121f)
        cubicTo(174f, 99f, 180f, 78f, 195f, 67f)
        cubicTo(205f, 59f, 216f, 56f, 235f, 57f)
        quadTo(240f, 64f, 237f, 77f)
        cubicTo(222f, 76f, 211f, 81f, 207f, 96f)
        lineTo(201f, 121f)
        close()
    }
    private val heart = shape {
        moveTo(154f, 101f)
        cubicTo(141f, 80f, 112f, 83f, 100f, 104f)
        cubicTo(82f, 134f, 105f, 158f, 128f, 176f)
        cubicTo(150f, 195f, 181f, 207f, 207f, 213f)
        cubicTo(230f, 218f, 249f, 185f, 253f, 156f)
        cubicTo(260f, 125f, 248f, 99f, 226f, 96f)
        cubicTo(209f, 91f, 195f, 105f, 183f, 111f)
        quadTo(168f, 117f, 154f, 101f)
        close()
    }
    private val lvSurface = shape {
        moveTo(191f, 121f)
        cubicTo(200f, 105f, 215f, 96f, 229f, 99f)
        cubicTo(253f, 104f, 258f, 130f, 252f, 157f)
        cubicTo(246f, 186f, 230f, 216f, 207f, 213f)
        cubicTo(190f, 194f, 181f, 148f, 191f, 121f)
        close()
    }
    private val atrialGroove = shape {
        moveTo(99f, 123f)
        cubicTo(124f, 116f, 145f, 132f, 153f, 146f)
        quadTo(171f, 173f, 196f, 190f)
    }
    private val rootCusp = shape {
        moveTo(144f, 101f)
        quadTo(152f, 111f, 163f, 105f)
        quadTo(173f, 111f, 181f, 102f)
    }
    private val rightCoronary = route {
        moveTo(145f, 95f)
        cubicTo(126f, 96f, 128f, 112f, 115f, 120f)
        cubicTo(104f, 127f, 102f, 137f, 110f, 150f)
        quadTo(118f, 163f, 134f, 171f)
    }
    private val rightBranch = route {
        moveTo(113f, 121f)
        cubicTo(130f, 124f, 135f, 146f, 155f, 156f)
    }
    private val leftMain = route {
        moveTo(178f, 94f)
        quadTo(189f, 96f, 195f, 116f)
    }
    private val descending = route {
        moveTo(195f, 116f)
        cubicTo(182f, 143f, 180f, 171f, 208f, 203f)
    }
    private val circumflex = route {
        moveTo(195f, 116f)
        cubicTo(210f, 113f, 235f, 113f, 251f, 137f)
    }
    private val diagonal = route {
        moveTo(186f, 143f)
        cubicTo(204f, 147f, 204f, 168f, 231f, 178f)
    }
    private val anteriorVein = route {
        moveTo(198f, 205f)
        cubicTo(170f, 177f, 171f, 151f, 180f, 132f)
        cubicTo(188f, 111f, 222f, 102f, 245f, 117f)
    }
    private val rootSection = shape {
        moveTo(144f, 248f)
        quadTo(180f, 237f, 216f, 248f)
        cubicTo(210f, 269f, 233f, 277f, 232f, 295f)
        quadTo(233f, 315f, 205f, 326f)
        quadTo(180f, 335f, 155f, 326f)
        quadTo(127f, 315f, 128f, 295f)
        cubicTo(127f, 277f, 150f, 269f, 144f, 248f)
        close()
    }
    private val rootValve = shape {
        moveTo(132f, 310f)
        cubicTo(152f, 303f, 160f, 326f, 180f, 316f)
        cubicTo(199f, 326f, 207f, 303f, 228f, 310f)
    }
    private val ostialFlows = listOf(-1f, 1f).map { side ->
        route {
            moveTo(180f + side * 4f, 251f)
            cubicTo(180f + side * 7f, 276f, 180f + side * 24f, 299f, 180f + side * 48f, 291f)
            cubicTo(180f + side * 71f, 281f, 180f + side * 89f, 288f, 180f + side * 107f, 302f)
        }
    }
    private val posteriorHeart = shape {
        moveTo(175f, 265f)
        cubicTo(156f, 245f, 114f, 243f, 99f, 267f)
        cubicTo(84f, 290f, 116f, 321f, 141f, 329f)
        cubicTo(164f, 335f, 196f, 322f, 220f, 311f)
        cubicTo(247f, 299f, 269f, 270f, 250f, 251f)
        cubicTo(234f, 238f, 202f, 246f, 192f, 261f)
        quadTo(184f, 271f, 175f, 265f)
        close()
    }
    private val posteriorAtrium = shape {
        moveTo(208f, 263f)
        cubicTo(215f, 250f, 228f, 249f, 229f, 236f)
        quadTo(242f, 233f, 250f, 238f)
        quadTo(244f, 250f, 254f, 258f)
        cubicTo(271f, 277f, 250f, 295f, 231f, 298f)
        quadTo(205f, 289f, 208f, 263f)
        close()
    }
    private val cardiacVein = route {
        moveTo(99f, 285f)
        cubicTo(110f, 267f, 132f, 267f, 155f, 277f)
    }
    private val tributary = route {
        moveTo(161f, 323f)
        cubicTo(182f, 308f, 170f, 296f, 188f, 286f)
    }
    private val coronarySinus = route {
        moveTo(155f, 277f)
        cubicTo(178f, 282f, 199f, 297f, 222f, 282f)
        quadTo(231f, 276f, 239f, 273f)
    }

    init { tag = "atlas-function-coronary-perfusion-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val ease = t * t * (3f - 2f * t)
        val squeeze = when (step) {
            2 -> ease
            3 -> 1f - ease
            else -> 0f
        }
        drawHeart(c, step, t, squeeze)
        line(c, 24f, 222f, 336f, 222f, 0xffd1c5b8, 1f)
        when (step) {
            0 -> drawRoot(c, t)
            4 -> drawReturn(c, t)
            else -> drawWall(c, step, t, squeeze)
        }
    }

    private fun drawHeart(c: Canvas, step: Int, t: Float, squeeze: Float) {
        tissue(c, venaCava, pulmonary, 0xff789aa6)
        tissue(c, arch, aorta, wallInk)
        line(c, 218f, 47f, 227f, 42f, 0xffffc5ac, 2.3f)
        tissue(c, pulmonaryTrunk, pulmonary, 0xff789aa6)
        tissue(c, heart, muscle, wallInk)
        tissue(c, lvSurface, leftMuscle, 0xffb67577)
        stroke(c, atrialGroove, 0xffb9797a, 1.35f)

        // The widened root is exposed schematically so both openings can be seen.
        detail.rewind()
        detail.moveTo(146f, 76f)
        detail.cubicTo(150f, 85f, 140f, 88f, 142f, 99f)
        detail.quadTo(162f, 118f, 182f, 101f)
        detail.cubicTo(186f, 91f, 176f, 83f, 177f, 76f)
        detail.quadTo(160f, 80f, 146f, 76f)
        detail.close()
        tissue(c, detail, aorta, wallInk)
        stroke(c, rootCusp, 0xfffbe0c2, 1.9f)

        val prominent = step != 4
        vessel(c, rightCoronary, 8f, prominent)
        vessel(c, rightBranch, 4.2f, prominent)
        vessel(c, leftMain, 8.5f, prominent)
        vessel(c, descending, 7.5f, prominent)
        vessel(c, circumflex, 6.4f, prominent)
        vessel(c, diagonal, 4.8f, prominent)
        disc(c, 145f, 95f, 3.9f, artery, cream)
        disc(c, 178f, 94f, 3.9f, artery, cream)
        when (step) {
            0 -> {
                stream(c, rightCoronary, t, .36f, 1, cream, .45f, .55f)
                stream(c, leftMain, t, .75f, 1, cream)
            }
            4 -> {
                stroke(c, anteriorVein.path, vein, 6.4f)
                stroke(c, anteriorVein.path, veinFill, 3.9f)
                stream(c, anteriorVein, t, 1.38f, 3, cream)
            }
            else -> {
                val cycle = step - 1 + t
                stream(c, rightCoronary, cycle, 1.43f, 2, cream)
                stream(c, rightBranch, cycle + .12f, 1.55f, 1, cream)
                stream(c, leftMain, cycle, 1.5f, 1, cream)
                val leftFlow = 1f - .58f * squeeze
                val leftT = wallTime(step, t)
                stream(c, descending, leftT, 1.52f, 3, cream, leftFlow)
                stream(c, circumflex, leftT, 1.3f, 2, cream, leftFlow)
                stream(c, diagonal, leftT, 1.48f, 1, cream, leftFlow)
                ink(0xff8b5b60, 1.35f)
                c.drawOval(206f, 158f, 231f, 183f, paint)
                line(c, 224f, 182f, 250f, 222f, leader, 1f)
            }
        }
        label(c, R.string.health_atlas_coronary_story_aortic_root, 77f, 54f, 112f)
        line(c, 104f, 59f, 144f, 82f, leader, 1f)
        label(c, R.string.health_atlas_coronary_story_right_ostium, 67f, 86f, 118f)
        line(c, 108f, 89f, 140f, 95f, leader, 1f)
        label(c, R.string.health_atlas_coronary_story_left_ostium, 290f, 86f, 116f)
        line(c, 249f, 90f, 184f, 94f, leader, 1f)
        label(c, R.string.health_atlas_coronary_story_rca, 55f, 163f, 100f)
        line(c, 99f, 157f, 105f, 146f, leader, 1f)
        label(c, R.string.health_atlas_coronary_story_lad, 115f, 202f, 88f)
        line(c, 148f, 197f, 194f, 190f, leader, 1f)
        label(c, R.string.health_atlas_coronary_story_circumflex, 301f, 139f, 107f)
        line(c, 269f, 134f, 243f, 128f, leader, 1f)
    }

    private fun drawRoot(c: Canvas, t: Float) {
        tissue(c, rootSection, rootWash, wallInk)
        oval(c, 145f, 243f, 215f, 254f, 0xfff9bca8, wallInk)
        stroke(c, rootValve, wallInk, 2.1f)
        for ((index, branch) in ostialFlows.withIndex()) {
            detail.rewind()
            branch.measure.getSegment(branch.measure.length * .53f, branch.measure.length, detail, true)
            stroke(c, detail, artery, 10f)
            stroke(c, detail, arteryFill, 6.4f)
            val x = if (index == 0) 132f else 228f
            disc(c, x, 291f, 5f, artery, cream)
            stream(c, branch, t, 1.12f, 2, 0xff763345)
        }
        label(c, R.string.health_atlas_coronary_story_root_section, 180f, 239f, 179f)
        label(c, R.string.health_atlas_coronary_story_rca, 71f, 321f, 119f)
        label(c, R.string.health_atlas_coronary_story_lca, 289f, 321f, 119f)
        line(c, 73f, 306f, 73f, 309f, leader, 1f)
        line(c, 287f, 306f, 287f, 309f, leader, 1f)
        line(c, 181f, 320f, 181f, 339f, leader, 1f)
        label(c, R.string.health_atlas_coronary_story_aortic_valve, 180f, 352f, 138f)
    }

    private fun drawWall(c: Canvas, step: Int, t: Float, squeeze: Float) {
        label(c, R.string.health_atlas_coronary_story_lv_wall, 180f, 241f, 212f)
        val crowding = 1f - .57f * squeeze
        val time = wallTime(step, t)
        val mid = 290f
        detail.rewind()
        detail.moveTo(39f, 273f)
        detail.cubicTo(104f, 244f, 228f, 242f, 313f, 270f)
        detail.quadTo(331f, 286f, 320f, 306f)
        detail.cubicTo(255f, 334f, 108f, 334f, 42f, 308f)
        detail.quadTo(23f, 292f, 39f, 273f)
        detail.close()
        tissue(c, detail, wallDetail, 0xffbb827a)
        for (side in -1..1 step 2) {
            for (row in 0..1) {
                val edge = mid + side * (15f + row * 6f)
                val inside = mid + side * (21f - 11f * squeeze + row * 9f)
                detail.rewind()
                detail.moveTo(54f, edge)
                detail.cubicTo(101f, edge + 4f, 122f, inside, 161f, inside)
                detail.cubicTo(207f, inside, 232f, edge - 3f, 300f, edge)
                stroke(c, detail, if (row == 0) 0xffcd8c82 else 0xfffbe0c9, 2.5f)
            }
        }
        stroke(c, arteriole.path, artery, 5f + 5f * crowding)
        stroke(c, arteriole.path, arteryFill, 2f + 4f * crowding)
        stroke(c, venule.path, vein, 6.8f)
        stroke(c, venule.path, veinFill, 3.8f)
        c.save()
        c.scale(1f, crowding, 180f, mid)
        for ((i, branch) in capillaries.withIndex()) {
            stroke(c, branch.path, if (i == 1) 0xffa15d73 else 0xffb76b79, 3.4f)
            stream(c, branch, time + i * .16f, 1.32f, 2, cream, .38f + .62f * crowding)
        }
        c.restore()
        stream(c, arteriole, time, 1.65f, 2, cream, .45f + .55f * crowding)
        stream(c, venule, step - 1 + t, 1.05f, 2, cream)
        for (i in 0..3) {
            val u = (time * 1.35f + i * .26f) % 1f
            val side = if (i % 2 == 0) -1f else 1f
            val x = 149f + i * 20f + 5f * u
            val y = mid + side * (8f * crowding + 19f * u)
            ink(oxygen)
            paint.alpha = (255f * (1f - abs(2f * u - 1f)) * crowding).toInt()
            c.drawOval(x - 2.6f, y - 1.6f, x + 2.6f, y + 1.6f, paint)
        }
        if (step == 2) {
            for (side in -1..1 step 2) {
                val tip = mid + side * (13f - 5f * squeeze)
                arrow(c, 177f, tip + side * 13f, 177f, tip, 0xff905864)
            }
        }
        line(c, 65f, 296f, 65f, 333f, leader, 1f)
        line(c, 191f, 307f, 191f, 333f, leader, 1f)
        line(c, 288f, 295f, 288f, 333f, leader, 1f)
        label(c, R.string.health_atlas_coronary_story_arteriole, 65f, 349f, 100f)
        label(c, R.string.health_atlas_coronary_story_capillaries, 191f, 349f, 125f)
        label(c, R.string.health_atlas_coronary_story_venule, 288f, 349f, 100f)
    }

    private val arteriole = route {
        moveTo(42f, 291f)
        cubicTo(74f, 282f, 96f, 290f, 121f, 290f)
    }
    private val capillaries = listOf(-1f, 0f, 1f).map { side ->
        route {
            moveTo(121f, 290f)
            cubicTo(145f, 290f + 24f * side, 153f, 282f + 12f * side, 174f, 289f + 13f * side)
            cubicTo(198f, 297f + 15f * side, 224f, 290f + 19f * side, 248f, 290f)
        }
    }
    private val venule = route {
        moveTo(248f, 290f)
        quadTo(280f, 294f, 318f, 286f)
    }

    private fun drawReturn(c: Canvas, t: Float) {
        tissue(c, posteriorHeart, backMuscle, wallInk)
        tissue(c, posteriorAtrium, pulmonary, vein)
        stroke(c, tributary.path, vein, 4f)
        stroke(c, tributary.path, veinFill, 2.1f)
        stroke(c, cardiacVein.path, vein, 6.4f)
        stroke(c, cardiacVein.path, veinFill, 3.8f)
        stroke(c, coronarySinus.path, vein, 11f)
        stroke(c, coronarySinus.path, veinFill, 7.2f)
        stream(c, cardiacVein, t, 1.12f, 2, cream)
        stream(c, tributary, t + .34f, 1.1f, 1, cream)
        stream(c, coronarySinus, t - .15f, 1.38f, 3, cream)
        label(c, R.string.health_atlas_coronary_story_posterior, 109f, 240f, 161f)
        line(c, 239f, 272f, 270f, 276f, leader, 1f)
        label(c, R.string.health_atlas_coronary_story_right_atrium, 308f, 287f, 92f)
        line(c, 111f, 276f, 81f, 302f, leader, 1f)
        line(c, 81f, 302f, 81f, 333f, leader, 1f)
        line(c, 188f, 286f, 211f, 332f, leader, 1f)
        label(c, R.string.health_atlas_coronary_story_cardiac_vein, 89f, 348f, 141f)
        label(c, R.string.health_atlas_coronary_story_sinus, 237f, 348f, 140f)
    }

    // Integrated qualitative speed: the left-sided arrows decelerate, then accelerate.
    private fun wallTime(step: Int, t: Float): Float {
        val delta = .64f * t * t * t * (1f - .5f * t)
        return when (step) {
            2 -> 1f + t - delta
            3 -> 1.68f + .36f * t + delta
            else -> t
        }
    }

    private fun vessel(c: Canvas, route: Route, width: Float, prominent: Boolean) {
        stroke(c, route.path, if (prominent) artery else 0xffac7073, width)
        stroke(c, route.path, if (prominent) arteryFill else 0xffdca29a, width * .58f)
    }

    private fun stream(
        c: Canvas, route: Route, t: Float, speed: Float, count: Int, color: Long,
        strength: Float = 1f, span: Float = 1f,
    ) {
        val length = route.measure.length
        for (i in 0 until count) {
            val travel = t * speed + i.toFloat() / count
            val u = travel - kotlin.math.floor(travel)
            val p = u * span
            if (!route.measure.getPosTan(length * p, position, tangent)) continue
            val x = position[0]
            val y = position[1]
            val dx = tangent[0]
            val dy = tangent[1]
            val size = minOf(5.8f, length * .19f)
            ink(color, 1.65f)
            paint.alpha = (255f * strength * minOf(1f, 8f * u, 8f * (1f - u))).toInt()
            c.drawLine(x - size * dx, y - size * dy, x, y, paint)
            c.drawLine(x, y, x - .55f * size * dx + .36f * size * dy, y - .55f * size * dy - .36f * size * dx, paint)
            c.drawLine(x, y, x - .55f * size * dx - .36f * size * dy, y - .55f * size * dy + .36f * size * dx, paint)
        }
    }

    private fun tissue(c: Canvas, path: Path, fill: Shader, border: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, border, 1.5f)
    }

    private class Route(val path: Path, val measure: PathMeasure)
    private fun shape(build: Path.() -> Unit) = Path().apply(build)
    private fun route(build: Path.() -> Unit) = shape(build).let { Route(it, track(it)) }
}
