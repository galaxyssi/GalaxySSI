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
    private val sodiumInk = 0xff97602c
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
    private val villusOutline = track(surface)
    private val villusTrace = Path()
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
    private val glucosePath = Path().apply {
        moveTo(240f, 89f)
        quadTo(251f, 102f, 251f, 123f)
        lineTo(251f, 260f)
    }
    private val sodiumPath = Path().apply {
        moveTo(271f, 89f)
        quadTo(261f, 102f, 261f, 123f)
        quadTo(261f, 167f, 282f, 175f)
        quadTo(307f, 187f, 307f, 212f)
        lineTo(307f, 252f)
    }
    private val glucoseTrack = track(glucosePath)
    private val sodiumTrack = track(sodiumPath)

    init {
        tag = "atlas-function-intestinal-absorption-art"
        val point = FloatArray(2)
        val tangent = FloatArray(2)
        // Normal to the villus silhouette: cell bodies on the inside, microvilli on the lumen side.
        for (index in 8..128) {
            if (!villusOutline.getPosTan(villusOutline.length * index / 136f, point, tangent)) continue
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
        drawVillus(c, step == 1, t.takeIf { step == 0 })
        if (step == 2) {
            flow(c, bloodRoute, t)
            drawGlucoseTransport(c, t)
            return
        }
        drawInset(c, t.takeIf { step == 1 })
        if (step == 4) {
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

    private fun drawGlucoseTransport(c: Canvas, t: Float) {
        oval(c, 162f, 114f, 179f, 132f, 0x22fff8eb, leaderInk)
        line(c, 180f, 122f, 206f, 117f, leaderInk, 1f)
        rounded(c, 204f, 73f, 348f, 270f, 8f, 0xffdceeed)
        rounded(c, 204f, 118f, 348f, 230f, 5f, 0xfff4d0b8)
        line(c, 205f, 230f, 347f, 230f, coral, 3f)
        for (x in 209..345 step 5) {
            line(c, x.toFloat(), 117f, x.toFloat(), 111f, brushInk, 1.5f)
        }
        oval(c, 291f, 147f, 326f, 165f, 0xffe0b5bd, coral)
        rounded(c, 240f, 109f, 272f, 129f, 6f, teal)
        rounded(c, 239f, 224f, 263f, 236f, 4f, teal)
        rounded(c, 299f, 222f, 330f, 238f, 5f, teal)
        stroke(c, glucosePath, blue, 1.8f)
        stroke(c, sodiumPath, sodiumInk, 1.8f)
        arrow(c, 251f, 245f, 251f, 260f, blue)
        arrow(c, 307f, 241f, 307f, 252f, sodiumInk)
        arrow(c, 323f, 251f, 323f, 206f, violet)
        for (i in 0..1) {
            val f = (t + i * .5f) % 1f
            at(glucoseTrack, f) { x, y -> disc(c, x, y, 3.8f, blue, cream) }
            at(sodiumTrack, f) { x, y ->
                rounded(c, x - 3.3f, y - 3.3f, x + 3.3f, y + 3.3f, .7f, sodiumInk)
            }
            disc(c, 323f, 250f - 40f * f, 2.6f, violet, cream)
        }
        label(c, R.string.health_atlas_absorption_story_label_lumen, 275f, 62f, 132f)
        label(c, R.string.health_atlas_absorption_story_sglt1, 309f, 121f, 62f)
        label(c, R.string.health_atlas_absorption_story_glut2, 226f, 221f, 41f)
        label(c, R.string.health_atlas_absorption_story_pump, 314f, 196f, 65f)
        label(c, R.string.health_atlas_absorption_story_tissue_side, 276f, 288f, 143f)
        disc(c, 212f, 312f, 3.8f, blue, cream)
        label(c, R.string.health_atlas_absorption_story_glucose, 247f, 316f, 60f)
        rounded(c, 280f, 309f, 286f, 315f, .7f, sodiumInk)
        label(c, R.string.health_atlas_absorption_story_sodium, 300f, 316f, 24f)
        disc(c, 321f, 312f, 3f, violet, cream)
        label(c, R.string.health_atlas_absorption_story_potassium, 336f, 316f, 19f)
    }

    private fun drawVillus(c: Canvas, highlightBrush: Boolean, outlineProgress: Float?) {
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
        outlineProgress?.let { progress ->
            villusTrace.rewind()
            villusOutline.getSegment(0f, villusOutline.length * progress, villusTrace, true)
            stroke(c, villusTrace, teal, 2.2f)
        }
        line(c, 29f, 294f, 198f, 294f, coral, 1.2f)

        label(c, R.string.health_atlas_absorption_story_label_lumen, 118f, 38f, 112f)
        label(c, R.string.health_atlas_absorption_story_label_villus, 44f, 77f, 67f)
        line(c, 57f, 82f, 70f, 88f, leaderInk, 1f)
        label(c, R.string.health_atlas_absorption_story_label_capillaries, 68f, 319f, 116f)
        line(c, 68f, 305f, 69f, 287f, 0xffad5264, 1f)
        label(c, R.string.health_atlas_absorption_story_label_lacteal, 162f, 319f, 64f)
        line(c, 152f, 305f, 137f, 288f, teal, 1f)
    }

    private fun drawInset(c: Canvas, brushProgress: Float?) {
        // The selected epithelium is enlarged with its lumen-facing edge turned upward.
        val highlightBrush = brushProgress != null
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
        stroke(c, insetBrush, brushInk, 1.8f)
        brushProgress?.let { progress ->
            c.save()
            c.clipRect(218f, 94f, 218f + 128f * progress, 110f)
            stroke(c, insetBrush, teal, 2.35f)
            c.restore()
        }
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
