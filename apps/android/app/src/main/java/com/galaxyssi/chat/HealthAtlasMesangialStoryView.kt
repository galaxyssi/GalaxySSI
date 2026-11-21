package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader

internal enum class HealthAtlasMesangialStage(val title: Int, val caption: Int) {
    LOCATE(R.string.health_atlas_mesangial_story_locate, R.string.health_atlas_mesangial_story_locate_caption),
    BOUNDARY(R.string.health_atlas_mesangial_story_boundary, R.string.health_atlas_mesangial_story_boundary_caption),
    SUPPORT(R.string.health_atlas_mesangial_story_support, R.string.health_atlas_mesangial_story_support_caption),
    UPTAKE(R.string.health_atlas_mesangial_story_uptake, R.string.health_atlas_mesangial_story_uptake_caption),
    TENSION(R.string.health_atlas_mesangial_story_tension, R.string.health_atlas_mesangial_story_tension_caption);

    fun progress(t: Float): Float {
        val f = t.coerceIn(0f, 1f)
        return when (this) {
            LOCATE -> smooth(f)
            BOUNDARY -> 1f - (1f - f) * (1f - f)
            SUPPORT -> f * f
            UPTAKE -> f
            TENSION -> if (f < .7f) smooth(f / .7f) else smooth((1f - f) / .3f)
        }
    }

    private fun smooth(f: Float) = f * f * (3f - 2f * f)
}

internal class HealthAtlasMesangialStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.MESANGIAL_SUPPORT) {
    private val vesselInk = 0xff995e66
    private val matrixInk = 0xff927344
    private val cellInk = 0xff396d65
    private val podocyteInk = 0xff785e85
    private val leaderInk = 0xff576d70
    private val matrixFill = shade(150f, 277f, 0xfff4e5bb, 0xffdec29a)
    private val bloodFill = shade(140f, 278f, 0xffffede2, 0xffefbdb3)
    private val mesangialFill = shade(174f, 251f, 0xffc7dfca, 0xff78aa96)
    private val podocyteFill = shade(103f, 148f, 0xffe6d9ed, 0xffae94bd)
    private val segment = Path()
    private val movingOutline = Path()

    private val capsule = Path().apply {
        moveTo(35f, 34f)
        cubicTo(52f, 9f, 102f, 9f, 126f, 27f)
        cubicTo(145f, 41f, 149f, 67f, 137f, 80f)
        quadTo(135f, 84f, 152f, 91f)
        lineTo(146f, 101f)
        quadTo(128f, 91f, 121f, 96f)
        cubicTo(89f, 112f, 44f, 101f, 35f, 76f)
        cubicTo(30f, 64f, 30f, 48f, 35f, 34f)
        close()
    }
    private val tuft = Path().apply {
        moveTo(18f, 49f)
        cubicTo(41f, 55f, 48f, 50f, 54f, 34f)
        cubicTo(61f, 17f, 89f, 23f, 84f, 40f)
        cubicTo(80f, 54f, 53f, 52f, 62f, 68f)
        cubicTo(70f, 82f, 88f, 57f, 97f, 48f)
        cubicTo(116f, 26f, 138f, 55f, 122f, 72f)
        cubicTo(106f, 88f, 91f, 73f, 81f, 84f)
        cubicTo(65f, 96f, 56f, 77f, 48f, 71f)
        quadTo(36f, 65f, 18f, 69f)
    }
    private val tuftBranches = Path().apply {
        moveTo(50f, 43f)
        cubicTo(39f, 72f, 61f, 88f, 74f, 87f)
        moveTo(81f, 33f)
        cubicTo(100f, 20f, 119f, 31f, 120f, 48f)
        moveTo(87f, 59f)
        cubicTo(98f, 69f, 105f, 58f, 120f, 56f)
    }
    private val tuftTrack = track(tuft)

    private val outline = Path().apply { sectionOutline(0f) }
    private val leftLumen = Path().apply {
        moveTo(82f, 140f)
        cubicTo(49f, 139f, 33f, 175f, 34f, 208f)
        cubicTo(34f, 241f, 56f, 276f, 87f, 277f)
        cubicTo(113f, 278f, 122f, 259f, 112f, 238f)
        cubicTo(102f, 218f, 105f, 205f, 112f, 184f)
        cubicTo(121f, 160f, 106f, 141f, 82f, 140f)
        close()
    }
    private val rightLumen = Path().apply {
        moveTo(192f, 140f)
        cubicTo(220f, 139f, 239f, 171f, 238f, 207f)
        cubicTo(239f, 240f, 226f, 269f, 196f, 273f)
        cubicTo(169f, 278f, 155f, 257f, 163f, 239f)
        cubicTo(171f, 218f, 170f, 198f, 162f, 180f)
        cubicTo(153f, 159f, 168f, 140f, 192f, 140f)
        close()
    }
    private val wallTrack = track(Path().apply {
        moveTo(245f, 209f)
        cubicTo(249f, 168f, 231f, 134f, 192f, 133f)
        cubicTo(155f, 132f, 158f, 153f, 137f, 153f)
    })
    private val relaxedEdge = Path().apply {
        moveTo(27f, 207f)
        cubicTo(26f, 247f, 51f, 283f, 89f, 284f)
    }

    private val cell = Path().apply {
        moveTo(118f, 174f)
        cubicTo(129f, 180f, 126f, 201f, 138f, 203f)
        cubicTo(149f, 202f, 150f, 182f, 163f, 178f)
        cubicTo(157f, 188f, 158f, 206f, 153f, 214f)
        cubicTo(158f, 225f, 153f, 234f, 149f, 239f)
        cubicTo(148f, 246f, 158f, 250f, 160f, 257f)
        cubicTo(148f, 255f, 142f, 247f, 136f, 244f)
        cubicTo(129f, 243f, 124f, 253f, 115f, 254f)
        cubicTo(120f, 246f, 125f, 238f, 123f, 230f)
        cubicTo(119f, 219f, 130f, 212f, 126f, 201f)
        quadTo(122f, 181f, 118f, 174f)
        close()
    }
    private val podocyte = Path().apply {
        moveTo(149f, 147f)
        cubicTo(159f, 137f, 170f, 126f, 178f, 118f)
        cubicTo(178f, 96f, 212f, 94f, 220f, 110f)
        cubicTo(224f, 118f, 220f, 121f, 221f, 127f)
        quadTo(224f, 136f, 232f, 147f)
        quadTo(223f, 148f, 219f, 139f)
        quadTo(213f, 129f, 208f, 124f)
        quadTo(202f, 126f, 198f, 132f)
        quadTo(193f, 135f, 193f, 131f)
        lineTo(195f, 122f)
        quadTo(188f, 125f, 185f, 129f)
        quadTo(179f, 137f, 175f, 138f)
        lineTo(177f, 128f)
        quadTo(164f, 136f, 159f, 145f)
        quadTo(155f, 151f, 149f, 147f)
        close()
    }

    private val fibers = listOf(
        curve(124f, 193f, 120f, 170f, 107f, 145f),
        curve(154f, 192f, 158f, 165f, 171f, 139f),
        curve(126f, 238f, 119f, 254f, 110f, 278f),
        curve(147f, 241f, 153f, 258f, 166f, 276f),
    )
    private val fiberTracks = fibers.map { track(it) }
    private val uptakeTrack = track(curve(138f, 170f, 151f, 186f, 146f, 218f))

    init { tag = "atlas-function-mesangial-support-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val stage = HealthAtlasMesangialStage.entries[step]
        val f = stage.progress(t)
        val tension = if (stage == HealthAtlasMesangialStage.TENSION) f else 0f

        drawOverview(c, if (stage == HealthAtlasMesangialStage.LOCATE) f else null)
        drawSection(c, tension)
        if (stage == HealthAtlasMesangialStage.SUPPORT) {
            for ((i, fiber) in fiberTracks.withIndex()) {
                val reach = .4f + .6f * ((f - i * .055f) / .835f).coerceIn(0f, 1f)
                sweep(c, fiber, reach - .25f, reach, 0xffa37435, 3.4f)
            }
        }
        drawCell(c, tension)
        when (stage) {
            HealthAtlasMesangialStage.LOCATE, HealthAtlasMesangialStage.SUPPORT,
            HealthAtlasMesangialStage.TENSION -> Unit
            HealthAtlasMesangialStage.BOUNDARY -> {
                sweep(c, wallTrack, f - .30f, f + .05f, 0xff9e712f, 4.2f)
                if (f > .35f) {
                    val light = ((f - .35f) / .65f).coerceIn(0f, 1f)
                    stroke(c, podocyte, (0xff79528b and 0xffffffL) or ((light * 255).toLong() shl 24), 2.5f)
                }
            }
            HealthAtlasMesangialStage.UPTAKE -> drawUptake(c, f)
        }
        drawLabels(c)
    }

    private fun drawOverview(c: Canvas, f: Float?) {
        line(c, 86f, 69f, 49f, 151f, 0xffaab7ae, 1f)
        line(c, 112f, 69f, 139f, 153f, 0xffaab7ae, 1f)
        ink(0xffedf1e5); c.drawPath(capsule, paint)
        stroke(c, capsule, 0xff879b92, 1.5f)
        stroke(c, tuftBranches, vesselInk, 8.5f)
        stroke(c, tuftBranches, 0xffe1a7a8, 5.8f)
        stroke(c, tuft, vesselInk, 10.5f)
        stroke(c, tuft, 0xffefb9b0, 7.5f)
        if (f != null) {
            sweep(c, tuftTrack, .72f * f, .17f + .72f * f, 0xffae5360, 3.8f)
            ink(0xff936d42, 1.8f)
            c.drawOval(86f - 3f * f, 52f - 3f * f, 112f + 3f * f, 76f + 3f * f, paint)
        } else {
            ink(0xff936d42, 1.2f)
            c.drawOval(85f, 51f, 113f, 77f, paint)
        }
    }

    private fun drawSection(c: Canvas, tension: Float) {
        val edge = if (tension == 0f) outline else movingOutline.apply {
            rewind()
            sectionOutline(tension)
        }
        fill(c, edge, matrixFill)
        stroke(c, edge, matrixInk, 3.3f)
        c.save()
        c.scale(loopScale(tension), 1f, LOOP_HINGE, 208f)
        drawLumen(c, leftLumen, 69f, 184f)
        c.restore()
        drawLumen(c, rightLumen, 195f, 180f)
        for (fiber in fibers) stroke(c, fiber, 0xffb39a70, 1.7f)
        if (tension > 0f) stroke(c, relaxedEdge, 0xffaeaaa1, 1.3f)
    }

    private fun drawLumen(c: Canvas, path: Path, x: Float, y: Float) {
        fill(c, path, bloodFill)
        stroke(c, path, 0xffce8c90, 4.2f)
        stroke(c, path, vesselInk, 1.1f)
        redCell(c, x, y, -26f)
        redCell(c, x + 14f, y + 25f, 32f)
        redCell(c, x - 5f, y + 49f, -9f)
    }

    private fun drawCell(c: Canvas, tension: Float) {
        c.save()
        c.scale(1f, 1f - .12f * tension, 138f, 227f)
        fill(c, cell, mesangialFill)
        stroke(c, cell, cellInk, 1.6f)
        oval(c, 126f, 217f, 140f, 237f, 0xff75a592, cellInk)
        disc(c, 133f, 227f, 2.1f, cellInk)
        c.restore()
        fill(c, podocyte, podocyteFill)
        stroke(c, podocyte, podocyteInk, 1.5f)
        oval(c, 189f, 105f, 210f, 117f, 0xffb39bc2, podocyteInk)
    }

    private fun drawUptake(c: Canvas, f: Float) {
        // Start on the matrix side and end in a vesicle, not across the filtration wall.
        val travel = (f / .72f).coerceIn(0f, 1f)
        val radius = 4f + 1.5f * ((f - .48f) / .24f).coerceIn(0f, 1f)
        disc(c, 146f, 218f, radius, 0xffcce2ce, cellInk)
        at(uptakeTrack, travel) { x, y ->
            val size = 1f - .52f * ((f - .72f) / .28f).coerceIn(0f, 1f)
            debris(c, x, y, size)
        }
        debris(c, 251f, 253f, 1f)
        label(c, R.string.health_atlas_mesangial_story_label_debris, 307f, 257f, 93f)
    }

    private fun drawLabels(c: Canvas) {
        leader(c, 155f, 36f, 120f, 39f)
        label(c, R.string.health_atlas_mesangial_story_label_glomerulus, 205f, 40f, 94f)
        leader(c, 255f, 111f, 215f, 110f)
        label(c, R.string.health_atlas_mesangial_story_label_podocyte, 300f, 115f, 84f)
        leader(c, 253f, 164f, 215f, 164f)
        label(c, R.string.health_atlas_mesangial_story_label_loop, 302f, 168f, 91f)
        leader(c, 252f, 198f, 245f, 201f)
        label(c, R.string.health_atlas_mesangial_story_label_basement, 302f, 197f, 93f)
        label(c, R.string.health_atlas_mesangial_story_label_membrane, 302f, 211f, 93f)
        line(c, 104f, 309f, 127f, 269f, leaderInk, 1f)
        leader(c, 127f, 269f, 133f, 228f)
        label(c, R.string.health_atlas_mesangial_story_label_cell, 86f, 328f, 146f)
        line(c, 180f, 309f, 153f, 270f, leaderInk, 1f)
        leader(c, 153f, 270f, 146f, 258f)
        label(c, R.string.health_atlas_mesangial_story_label_matrix, 203f, 328f, 143f)
    }

    private fun leader(c: Canvas, x: Float, y: Float, targetX: Float, targetY: Float) {
        line(c, x, y, targetX, targetY, leaderInk, 1f)
        disc(c, targetX, targetY, 1.8f, leaderInk, cream)
    }

    private fun redCell(c: Canvas, x: Float, y: Float, tilt: Float) {
        c.save()
        c.rotate(tilt, x, y)
        oval(c, x - 10f, y - 5f, x + 10f, y + 5f, 0xffcb7b82, vesselInk)
        oval(c, x - 5.5f, y - 2f, x + 5.5f, y + 2f, 0xffe6a29e, 0xffb96d77)
        c.restore()
    }

    private fun debris(c: Canvas, x: Float, y: Float, size: Float) {
        disc(c, x - 2f * size, y, 2.2f * size, 0xffb17c42, matrixInk)
        disc(c, x + 1.8f * size, y + 1.3f * size, 1.9f * size, 0xffd6a361, matrixInk)
        disc(c, x + .4f * size, y - 2.4f * size, 1.8f * size, 0xffebc58b, matrixInk)
    }

    private fun fill(c: Canvas, path: Path, fill: Shader) {
        ink(cream); paint.shader = fill; c.drawPath(path, paint); paint.shader = null
    }

    private fun sweep(c: Canvas, track: PathMeasure, start: Float, end: Float, color: Long, weight: Float) {
        segment.rewind()
        if (track.getSegment(start.coerceAtLeast(0f) * track.length, end.coerceAtMost(1f) * track.length, segment, true)) {
            stroke(c, segment, color, weight)
        }
    }

    private fun curve(x: Float, y: Float, cx: Float, cy: Float, endX: Float, endY: Float) =
        Path().apply { moveTo(x, y); quadTo(cx, cy, endX, endY) }

    private fun loopScale(tension: Float) = 1f - .13f * tension

    private fun Path.sectionOutline(tension: Float) {
        // Move only the free edge of the left loop; the mesangial hinge stays put.
        fun x(value: Float) = LOOP_HINGE + (value - LOOP_HINGE) * loopScale(tension)
        moveTo(137f, 153f)
        cubicTo(158f, 153f, 155f, 132f, 192f, 133f)
        cubicTo(231f, 134f, 249f, 168f, 245f, 209f)
        cubicTo(247f, 250f, 233f, 277f, 194f, 280f)
        cubicTo(169f, 283f, 159f, 270f, 142f, 270f)
        cubicTo(x(123f), 270f, x(117f), 284f, x(89f), 284f)
        cubicTo(x(51f), 283f, x(26f), 247f, x(27f), 207f)
        cubicTo(x(26f), 169f, x(42f), 133f, x(81f), 133f)
        cubicTo(x(119f), 133f, x(114f), 155f, 137f, 153f)
        close()
    }

    companion object {
        const val DURATION_MS = 20_000L
        const val STRUCTURE_SOURCE = "https://pubmed.ncbi.nlm.nih.gov/3631536/"
        const val UPTAKE_SOURCE = "https://pubmed.ncbi.nlm.nih.gov/33837218/"
        private const val LOOP_HINGE = 137f
    }
}
