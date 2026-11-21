package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path

internal class HealthAtlasIntestinalAbsorptionStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.INTESTINAL_ABSORPTION) {
    private val tissueFill = shade(60f, 294f, 0xffffeee0, 0xffe9b7a6)
    private val epitheliumFill = shade(60f, 294f, 0xffffd7ba, 0xffd7918c)
    private val enterocyteFill = shade(108f, 225f, 0xffffe3c9, 0xffe9ad9e)
    private val leaderInk = 0xff637e81
    private val brushInk = 0xff8a6052
    private val lipidInk = 0xffa16125
    private val surface = Path().apply {
        moveTo(29f, 294f)
        cubicTo(51f, 278f, 54f, 250f, 54f, 206f)
        cubicTo(54f, 162f, 52f, 123f, 65f, 93f)
        cubicTo(75f, 71f, 92f, 60f, 112f, 60f)
        cubicTo(139f, 60f, 158f, 79f, 169f, 107f)
        cubicTo(179f, 133f, 177f, 168f, 177f, 206f)
        cubicTo(177f, 253f, 182f, 282f, 198f, 294f)
    }
    private val villus = Path(surface).apply { close() }
    private val cellBoundaries = Path()
    private val nuclei = Path()
    private val microvilli = Path()
    private val insetBrush = Path().apply {
        for (x in 222..342 step 4) {
            moveTo(x.toFloat(), 107f)
            lineTo(x.toFloat(), if (x % 8 == 2) 97f else 99f)
        }
    }
    private val enterocyte = Path().apply {
        moveTo(239f, 108f)
        lineTo(323f, 108f)
        cubicTo(320f, 150f, 323f, 198f, 315f, 218f)
        quadTo(282f, 232f, 247f, 218f)
        cubicTo(239f, 198f, 242f, 150f, 239f, 108f)
        close()
    }
    private val capillaries = Path().apply {
        moveTo(69f, 297f)
        cubicTo(73f, 241f, 75f, 197f, 73f, 165f)
        cubicTo(71f, 128f, 78f, 106f, 95f, 104f)
        cubicTo(112f, 102f, 115f, 123f, 111f, 154f)
        cubicTo(105f, 202f, 105f, 249f, 100f, 297f)
        moveTo(74f, 203f)
        cubicTo(85f, 204f, 91f, 186f, 107f, 186f)
        moveTo(74f, 245f)
        cubicTo(87f, 247f, 91f, 229f, 104f, 231f)
    }
    private val lacteal = Path().apply {
        moveTo(133f, 130f)
        cubicTo(131f, 173f, 126f, 194f, 126f, 218f)
        cubicTo(126f, 249f, 135f, 270f, 136f, 297f)
    }
    private val bloodRoute = Route(Path().apply {
        moveTo(28f, 149f)
        cubicTo(48f, 148f, 64f, 147f, 71f, 153f)
        cubicTo(77f, 159f, 72f, 179f, 74f, 196f)
        cubicTo(75f, 228f, 72f, 260f, 70f, 283f)
    }, Cargo.SOLUTE, blue)
    private val lipidIntake = Route(Path().apply {
        moveTo(203f, 182f)
        quadTo(187f, 183f, 168f, 187f)
    }, Cargo.LIPID, lipidInk)
    private val lymphRoute = Route(Path().apply {
        moveTo(164f, 188f)
        cubicTo(150f, 192f, 128f, 196f, 126f, 214f)
        cubicTo(125f, 237f, 133f, 261f, 135f, 283f)
    }, Cargo.CHYLOMICRON, lipidInk)
    private val cellSolutes = Route(Path().apply {
        moveTo(254f, 91f)
        cubicTo(264f, 127f, 250f, 174f, 257f, 211f)
        quadTo(259f, 229f, 259f, 243f)
    }, Cargo.SOLUTE, blue)
    private val cellLipids = Route(Path().apply {
        moveTo(307f, 91f)
        quadTo(302f, 124f, 308f, 148f)
    }, Cargo.LIPID, lipidInk)
    private val cellExport = Route(Path().apply {
        moveTo(309f, 164f)
        cubicTo(300f, 188f, 310f, 215f, 307f, 243f)
    }, Cargo.CHYLOMICRON, lipidInk)

    init {
        tag = "atlas-function-intestinal-absorption-art"
        val outline = track(surface)
        val point = FloatArray(2)
        val tangent = FloatArray(2)
        // Normal to the villus silhouette: cell bodies on the inside, microvilli on the lumen side.
        for (index in 8..128) {
            if (!outline.getPosTan(outline.length * index / 136f, point, tangent)) continue
            val x = point[0]
            val y = point[1]
            val nx = -tangent[1]
            val ny = tangent[0]
            microvilli.moveTo(x, y)
            microvilli.lineTo(x - 3.8f * nx, y - 3.8f * ny)
            if (index % 4 == 0) {
                cellBoundaries.moveTo(x, y)
                cellBoundaries.lineTo(x + 14f * nx, y + 14f * ny)
            } else if (index % 4 == 2) {
                val cx = x + 9f * nx
                val cy = y + 9f * ny
                nuclei.addOval(cx - 2.2f, cy - 3f, cx + 2.2f, cy + 3f, Path.Direction.CW)
            }
        }
    }

    override fun scene(c: Canvas, step: Int, t: Float) {
        drawVillus(c, step == 1)
        drawInset(c, step == 1)
        if (step == 2 || step == 4) {
            flow(c, bloodRoute, t)
            flow(c, cellSolutes, t)
            legend(c, Cargo.SOLUTE, 26f, 107f, 144f, R.string.health_atlas_absorption_story_label_solutes)
        }
        if (step == 3) {
            flow(c, lipidIntake, t, 1)
            flow(c, cellLipids, t, 2)
            cargo(c, Cargo.CHYLOMICRON, 309f, 164f, 3f + 2f * t)
            legend(c, Cargo.LIPID, 26f, 107f, 144f, R.string.health_atlas_absorption_story_label_lipid)
        }
        if (step == 4) {
            flow(c, lymphRoute, t)
            flow(c, cellExport, t, 2)
        }
        if (step >= 3) {
            legend(c, Cargo.CHYLOMICRON, 218f, 283f, 116f, R.string.health_atlas_absorption_story_label_chylomicrons)
        }
    }

    private fun drawVillus(c: Canvas, highlightBrush: Boolean) {
        ink(peach)
        paint.shader = tissueFill
        c.drawPath(villus, paint)
        paint.shader = null
        c.save()
        c.clipPath(villus)
        stroke(c, surface, coral, 29f)
        ink(peach, 27f)
        paint.shader = epitheliumFill
        c.drawPath(surface, paint)
        paint.shader = null
        stroke(c, cellBoundaries, 0xffba7c78, .8f)
        ink(violet)
        c.drawPath(nuclei, paint)
        stroke(c, capillaries, 0xffad5264, 10f)
        stroke(c, capillaries, 0xfff6a1a0, 6.5f)
        stroke(c, lacteal, teal, 18f)
        stroke(c, lacteal, 0xffb8ddd0, 13f)
        c.restore()
        stroke(c, surface, coral, 1.4f)
        stroke(c, microvilli, if (highlightBrush) teal else brushInk, if (highlightBrush) 1.45f else .9f)
        line(c, 29f, 294f, 198f, 294f, coral, 1.2f)

        label(c, R.string.health_atlas_absorption_story_label_lumen, 118f, 38f, 112f)
        label(c, R.string.health_atlas_absorption_story_label_villus, 44f, 77f, 67f)
        line(c, 57f, 82f, 70f, 88f, leaderInk, 1f)
        label(c, R.string.health_atlas_absorption_story_label_capillaries, 68f, 319f, 116f)
        line(c, 68f, 305f, 69f, 287f, 0xffad5264, 1f)
        label(c, R.string.health_atlas_absorption_story_label_lacteal, 162f, 319f, 64f)
        line(c, 152f, 305f, 137f, 288f, teal, 1f)
    }

    private fun drawInset(c: Canvas, highlightBrush: Boolean) {
        // The selected epithelium is enlarged with its lumen-facing edge turned upward.
        val accent = if (highlightBrush) teal else leaderInk
        oval(c, 162f, 114f, 179f, 132f, 0x22fff8eb, accent)
        line(c, 180f, 122f, 208f, 91f, accent, 1f)
        line(c, 208f, 91f, 218f, 91f, accent, 1f)

        rounded(c, 218f, 84f, 346f, 253f, 7f, 0xffdceeed)
        rounded(c, 218f, 108f, 346f, 253f, 7f, 0xfff5d0b9)
        rounded(c, 218f, 108f, 346f, 223f, 4f, 0xffe7b5a5)
        ink(peach)
        paint.shader = enterocyteFill
        c.drawPath(enterocyte, paint)
        paint.shader = null
        stroke(c, enterocyte, if (highlightBrush) teal else coral, 1.4f)
        stroke(c, insetBrush, if (highlightBrush) teal else brushInk, 1.8f)
        oval(c, 270f, 177f, 292f, 199f, 0xffbd90ad, violet)
        oval(c, 223f, 181f, 236f, 199f, 0xffbd90ad, violet)
        oval(c, 326f, 181f, 340f, 199f, 0xffbd90ad, violet)

        label(c, R.string.health_atlas_absorption_story_label_brush_border, 281f, 68f, 128f)
        line(c, 281f, 74f, 281f, 97f, accent, 1f)
        line(c, 281f, 226f, 281f, 265f, leaderInk, 1f)
        label(c, R.string.health_atlas_absorption_story_label_enterocyte, 281f, 280f, 128f)
    }

    private fun flow(c: Canvas, route: Route, t: Float, count: Int = 3) {
        stroke(c, route.path, route.color, 1.2f)
        at(route.measure, .8f) { sx, sy ->
            at(route.measure, 1f) { x, y -> arrow(c, sx, sy, x, y, route.color) }
        }
        for (index in 0 until count) {
            val fraction = ((t + index / count.toFloat()) % 1f) * .86f + .04f
            at(route.measure, fraction) { x, y -> cargo(c, route.cargo, x, y) }
        }
    }

    private fun cargo(c: Canvas, kind: Cargo, x: Float, y: Float, radius: Float = 4.2f) {
        when (kind) {
            Cargo.SOLUTE -> disc(c, x, y, radius * .83f, blue, cream)
            Cargo.LIPID -> {
                c.save()
                c.rotate(45f, x, y)
                rounded(c, x - 2.5f, y - 2.5f, x + 2.5f, y + 2.5f, .7f, lipidInk)
                c.restore()
            }
            Cargo.CHYLOMICRON -> {
                disc(c, x, y, radius, 0xffffdd90, lipidInk)
                disc(c, x, y, radius * .36f, lipidInk)
            }
        }
    }

    private fun legend(c: Canvas, kind: Cargo, marker: Float, x: Float, width: Float, text: Int) {
        cargo(c, kind, marker, 340f)
        label(c, text, x, 344f, width)
    }

    private enum class Cargo { SOLUTE, LIPID, CHYLOMICRON }

    private class Route(val path: Path, val cargo: Cargo, val color: Long) {
        val measure = android.graphics.PathMeasure(path, false)
    }
}
