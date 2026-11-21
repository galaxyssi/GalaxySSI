package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader
import kotlin.math.abs

internal enum class HealthAtlasPodocyteStage(val title: Int, val caption: Int) {
    GLOMERULUS(R.string.health_atlas_podocyte_story_glomerulus, R.string.health_atlas_podocyte_story_glomerulus_caption),
    FENESTRAE(R.string.health_atlas_podocyte_story_fenestrae, R.string.health_atlas_podocyte_story_fenestrae_caption),
    BASEMENT(R.string.health_atlas_podocyte_story_basement, R.string.health_atlas_podocyte_story_basement_caption),
    FOOT_PROCESSES(R.string.health_atlas_podocyte_story_feet, R.string.health_atlas_podocyte_story_feet_caption),
    FILTRATION(R.string.health_atlas_podocyte_story_filtration, R.string.health_atlas_podocyte_story_filtration_caption);

    fun progress(t: Float): Float {
        val f = t.coerceIn(0f, 1f)
        return when (this) {
            GLOMERULUS -> ease(f)
            FENESTRAE -> f * f
            BASEMENT -> 1f - (1f - f) * (1f - f)
            FOOT_PROCESSES -> ease(((f - .08f) / .84f).coerceIn(0f, 1f))
            FILTRATION -> f
        }
    }

    private fun ease(f: Float) = f * f * (3f - 2f * f)
}

internal class HealthAtlasPodocyteStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.PODOCYTE_BARRIER) {
    private val leaderInk = 0xff52666b
    private val vesselInk = 0xff9d5863
    private val endoInk = 0xffa26169
    private val matrixInk = 0xff8a7051
    private val footInk = 0xff705580
    private val neighborInk = 0xff537a73
    private val slitInk = 0xff514f64
    private val waterInk = 0xff30759d
    private val soluteInk = 0xff327c6a
    private val proteinInk = 0xff886521

    private val bloodFill = shade(111f, 176f, 0x00f0bbb5, 0xfff4cbc2)
    private val filtrateFill = shade(176f, 302f, 0xffccdfe2, 0x00ddebed)
    private val endoFill = shade(136f, 173f, 0xfffbddd1, 0xffd38f94)
    private val matrixFill = shade(157f, 188f, 0xfff6e7c3, 0xffdbc096)
    private val podocyteFill = shade(185f, 257f, 0xffc6b2d6, 0xffe5d7ed)
    private val brush = Path()

    private val capsule = Path().apply {
        moveTo(104f, 83f)
        cubicTo(78f, 107f, 35f, 92f, 32f, 60f)
        cubicTo(28f, 35f, 50f, 18f, 78f, 20f)
        cubicTo(106f, 20f, 123f, 42f, 118f, 64f)
        quadTo(116f, 72f, 128f, 81f)
        lineTo(121f, 90f)
        quadTo(109f, 81f, 104f, 83f)
        close()
    }
    private val tuft = Path().apply {
        moveTo(20f, 40f)
        cubicTo(44f, 44f, 47f, 46f, 54f, 34f)
        cubicTo(62f, 21f, 84f, 27f, 79f, 40f)
        cubicTo(75f, 50f, 55f, 48f, 58f, 61f)
        cubicTo(60f, 70f, 71f, 67f, 80f, 57f)
        cubicTo(91f, 43f, 103f, 44f, 108f, 55f)
        cubicTo(114f, 73f, 89f, 82f, 74f, 79f)
        cubicTo(56f, 77f, 56f, 88f, 45f, 73f)
        quadTo(42f, 64f, 20f, 61f)
    }
    private val tuftBranch = Path().apply {
        moveTo(56f, 36f)
        cubicTo(49f, 55f, 45f, 66f, 58f, 80f)
        moveTo(76f, 45f)
        cubicTo(98f, 28f, 109f, 41f, 108f, 55f)
        moveTo(70f, 66f)
        cubicTo(82f, 69f, 92f, 56f, 103f, 61f)
    }
    private val tuftFlow = track(tuft)
    private val blood = strip({ 111f }, ::wallY)
    private val filtrateSpace = strip({ wallY(it) + MATRIX_DEPTH }, { 302f })
    private val basement = strip(::wallY, { wallY(it) + MATRIX_DEPTH })

    private val fenestrae = List(8) { 43f + 25.5f * it }
    private val endothelium = (0..fenestrae.size).map { i ->
        val left = if (i == 0) LEFT else fenestrae[i - 1] + 3.5f
        val right = if (i == fenestrae.size) RIGHT else fenestrae[i] - 3.5f
        strip(::endoY, ::wallY, left, right)
    }
    private val feet = List(8) { 39.5f + 27f * it }
    private val slits = List(feet.lastIndex) { feet[it] + 13.5f }
    private val foot = Path().apply {
        moveTo(-10f, 0f)
        lineTo(10f, 0f)
        cubicTo(10f, 5f, 7f, 7f, 5f, 10f)
        quadTo(3f, 14f, 4f, 18f)
        quadTo(-1f, 21f, -5f, 17f)
        cubicTo(-4f, 11f, -10f, 8f, -10f, 0f)
        close()
    }
    private val podocyte = Path().apply {
        moveTo(67f, footY(67f) + 13f)
        cubicTo(72f, 217f, 91f, 213f, 111f, 230f)
        cubicTo(117f, 229f, 119f, 214f, 119f, footY(120f) + 13f)
        lineTo(124f, footY(120f) + 13f)
        cubicTo(124f, 216f, 128f, 225f, 134f, 228f)
        cubicTo(153f, 229f, 164f, 214f, 174f, footY(174f) + 13f)
        lineTo(178f, footY(174f) + 15f)
        cubicTo(176f, 222f, 161f, 229f, 155f, 238f)
        cubicTo(153f, 259f, 109f, 266f, 101f, 244f)
        cubicTo(91f, 228f, 70f, 230f, 63f, footY(67f) + 14f)
        close()
    }
    private val leftFlow = track(filtrationRoute(fenestrae.first(), slits.first(), 33f))
    private val rightFlow = track(filtrationRoute(fenestrae.last(), slits.last(), 234f))

    init { tag = "atlas-function-podocyte-barrier-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val stage = HealthAtlasPodocyteStage.entries[step]
        val f = stage.progress(t)
        drawGlomerulus(c, if (stage == HealthAtlasPodocyteStage.GLOMERULUS) f else null)
        fill(c, blood, bloodFill)
        fill(c, filtrateSpace, filtrateFill)
        drawWall(c)
        drawBlood(c, if (stage == HealthAtlasPodocyteStage.FILTRATION) f else 0f)

        when (stage) {
            HealthAtlasPodocyteStage.GLOMERULUS -> Unit
            HealthAtlasPodocyteStage.FENESTRAE -> drawFenestraFocus(c, f)
            HealthAtlasPodocyteStage.BASEMENT -> drawBasementFocus(c, f)
            HealthAtlasPodocyteStage.FOOT_PROCESSES -> drawSlitFocus(c, f)
            HealthAtlasPodocyteStage.FILTRATION -> drawFiltrate(c, f)
        }
        drawLabels(c)
    }

    private fun drawGlomerulus(c: Canvas, f: Float?) {
        line(c, 94f, 75f, LEFT, 111f, 0xffa2aba1, 1f)
        line(c, 107f, 72f, RIGHT, 111f, 0xffa2aba1, 1f)
        ink(0xfff5f5e9); c.drawPath(capsule, paint)
        stroke(c, capsule, 0xff93a49b, 1.5f)
        stroke(c, tuftBranch, vesselInk, 7f)
        stroke(c, tuftBranch, 0xffe6acac, 4.4f)
        stroke(c, tuft, vesselInk, 8.5f)
        stroke(c, tuft, 0xffeab5b4, 5.7f)
        ink(0xff875267, if (f == null) 1.2f else 1.7f)
        val radius = if (f == null) 11f else 11f + 2f * wave(f - .25f)
        c.drawCircle(102f, 67f, radius, paint)
        if (f != null) {
            for (i in 0..2) {
                at(tuftFlow, (f * .72f + i * .33f) % 1f) { x, y -> disc(c, x, y, 2.4f, 0xff9c3f51) }
            }
        }
        line(c, 135f, 49f, 110f, 61f, leaderInk, 1f)
        label(c, R.string.health_atlas_podocyte_story_label_glomerulus, 177f, 45f, 99f)
    }

    private fun drawWall(c: Canvas) {
        fill(c, basement, matrixFill)
        for (i in 0..25) {
            val x = LEFT + 4f + i * 8f
            val y = wallY(x)
            val offset = if (i % 2 == 0) 0f else 2f
            line(c, x, y + 4f + offset, x + 4f, y + 7f + offset, 0xffbfa681, 1f)
            line(c, x + 3f, y + 10f, x + 7f, y + 8f, 0xffbfa681, .9f)
        }
        stroke(c, basement, matrixInk, 1.25f)
        for (segment in endothelium) {
            fill(c, segment, endoFill)
            stroke(c, segment, endoInk, 1f)
        }
        val y = endoY(81f)
        oval(c, 73f, y + 3f, 89f, y + 10f, 0xffb16d80, 0xff874e62)

        fill(c, podocyte, podocyteFill)
        stroke(c, podocyte, footInk, 1.45f)
        oval(c, 110f, 235f, 140f, 251f, 0xffac8abd, footInk)
        oval(c, 119f, 240f, 126f, 245f, 0xff856397, footInk)
        for ((i, x) in feet.withIndex()) {
            c.save()
            c.translate(x, footY(x))
            val attached = i % 2 == 1
            ink(if (attached) 0xffcdb8dc else 0xffadc9bf)
            c.drawPath(foot, paint)
            stroke(c, foot, if (attached) footInk else neighborInk, 1.15f)
            c.restore()
        }
        for (x in slits) diaphragm(c, x, slitInk, 1.35f)
    }

    private fun drawFenestraFocus(c: Canvas, f: Float) {
        val focus = fenestrae.first() + (fenestrae.last() - fenestrae.first()) * f
        for (x in fenestrae) {
            val alpha = (1f - abs(x - focus) / 34f).coerceAtLeast(0f)
            if (alpha == 0f) continue
            val y = wallY(x) - 6f
            ink(withAlpha(0xff9f4960, alpha), 2f)
            c.drawOval(x - 6f, y - 9f, x + 6f, y + 8f, paint)
        }
    }

    private fun drawBasementFocus(c: Canvas, f: Float) {
        // Follow the shared matrix without depicting a pore or a moving wall.
        val center = LEFT + (RIGHT - LEFT) * f
        for (i in 0..53) {
            val x = LEFT + 2f + i * 4f
            val alpha = (1f - abs(x - center) / 34f).coerceAtLeast(0f)
            if (alpha > 0f) {
                line(c, x, wallY(x) + 6.5f, x + 4f, wallY(x + 4f) + 6.5f, withAlpha(0xffa1732e, alpha), 2.8f)
            }
        }
    }

    private fun drawSlitFocus(c: Canvas, f: Float) {
        val focus = slits.last() - (slits.last() - slits.first()) * f
        for (x in slits) {
            val alpha = (1f - abs(x - focus) / 37f).coerceAtLeast(0f)
            if (alpha > 0f) diaphragm(c, x, withAlpha(0xff69458c, alpha), 3.3f)
        }
    }

    private fun diaphragm(c: Canvas, x: Float, color: Long, weight: Float) {
        line(c, x - 4.6f, footY(x - 4.6f) + 3.5f, x + 4.6f, footY(x + 4.6f) + 3.5f, color, weight)
    }

    private fun drawBlood(c: Canvas, f: Float) {
        c.save()
        c.clipRect(LEFT, 109f, RIGHT, 155f)
        for (i in 0..2) {
            val x = LEFT - 13f + (45f + i * 76f + f * 190f) % (RIGHT - LEFT + 26f)
            redCell(c, x, 126f + 4f * (i % 2), if (i % 2 == 0) -13f else 19f)
        }
        for (i in 0..3) {
            val x = LEFT - 7f + (23f + i * 57f + f * 157f) % (RIGHT - LEFT + 14f)
            protein(c, x, 140f + 3f * (i % 2))
        }
        c.restore()
    }

    private fun drawFiltrate(c: Canvas, f: Float) {
        // Tangential blood flow and outward filtrate flow are simultaneous.
        arrow(c, 112f, 111f, 169f, 111f, vesselInk)
        arrow(c, 136f, 268f, 136f, 289f, waterInk)
        for (i in 0..2) {
            val p = (f * 1.27f + i / 3f) % 1f
            at(leftFlow, p) { x, y -> water(c, x, y) }
            at(rightFlow, p) { x, y -> solute(c, x, y) }
            val q = (p + .16f) % 1f
            at(leftFlow, q) { x, y -> solute(c, x, y) }
            at(rightFlow, q) { x, y -> water(c, x, y) }
        }
    }

    private fun drawLabels(c: Canvas) {
        label(c, R.string.health_atlas_podocyte_story_label_blood, 300f, 113f, 105f)
        leader(c, 250f, 120f, 230f, 120f)
        label(c, R.string.health_atlas_podocyte_story_label_fenestrated, 300f, 140f, 105f)
        label(c, R.string.health_atlas_podocyte_story_label_endothelium, 300f, 154f, 105f)
        leader(c, 250f, 151f, 238f, wallY(238f) - 7f)
        label(c, R.string.health_atlas_podocyte_story_label_basement, 300f, 173f, 105f)
        label(c, R.string.health_atlas_podocyte_story_label_membrane, 300f, 187f, 105f)
        leader(c, 250f, 175f, 238f, wallY(238f) + 7f)
        label(c, R.string.health_atlas_podocyte_story_label_feet, 300f, 209f, 105f)
        leader(c, 250f, 205f, feet.last(), footY(feet.last()) + 5f)
        label(c, R.string.health_atlas_podocyte_story_label_slit, 300f, 232f, 105f)
        line(c, 250f, 228f, 238f, 218f, leaderInk, 1f)
        leader(c, 238f, 218f, slits.last(), footY(slits.last()) + 3.5f)
        label(c, R.string.health_atlas_podocyte_story_label_urinary, 300f, 281f, 105f)
        leader(c, 250f, 277f, 240f, 277f)

        line(c, 22f, 306f, 338f, 306f, 0xffb8c9c4, 1f)
        water(c, 35f, 322f)
        label(c, R.string.health_atlas_podocyte_story_label_water, 98f, 327f, 106f)
        solute(c, 198f, 322f)
        label(c, R.string.health_atlas_podocyte_story_label_solutes, 274f, 327f, 126f)
        redCell(c, 35f, 344f, -13f)
        label(c, R.string.health_atlas_podocyte_story_label_cells, 98f, 349f, 106f)
        protein(c, 198f, 344f)
        label(c, R.string.health_atlas_podocyte_story_label_proteins, 274f, 349f, 126f)
    }

    private fun leader(c: Canvas, fromX: Float, fromY: Float, x: Float, y: Float) {
        line(c, fromX, fromY, x, y, leaderInk, 1f)
        disc(c, x, y, 1.8f, leaderInk, cream)
    }

    private fun redCell(c: Canvas, x: Float, y: Float, tilt: Float) {
        c.save()
        c.rotate(tilt, x, y)
        oval(c, x - 11f, y - 5.7f, x + 11f, y + 5.7f, 0xffd1838b, vesselInk)
        oval(c, x - 5.8f, y - 2.2f, x + 5.8f, y + 2.2f, 0xffe9aaa6, 0xffba707d)
        c.restore()
    }

    private fun protein(c: Canvas, x: Float, y: Float) {
        disc(c, x - 2.2f, y + .8f, 2.9f, 0xffc7a05d, proteinInk)
        disc(c, x + 2.3f, y + 1.4f, 2.6f, 0xffd4b071, proteinInk)
        disc(c, x + .4f, y - 2f, 2.7f, 0xffe4c487, proteinInk)
    }

    private fun water(c: Canvas, x: Float, y: Float) {
        brush.rewind()
        brush.moveTo(x, y - 4.3f)
        brush.cubicTo(x + 1f, y - 2f, x + 3.4f, y, x + 3.4f, y + 1.3f)
        brush.cubicTo(x + 3.4f, y + 5f, x - 3.4f, y + 5f, x - 3.4f, y + 1.3f)
        brush.cubicTo(x - 3.4f, y, x - 1f, y - 2f, x, y - 4.3f)
        brush.close()
        ink(0xff88bed5); c.drawPath(brush, paint)
        stroke(c, brush, waterInk, 1.1f)
    }

    private fun solute(c: Canvas, x: Float, y: Float) {
        brush.rewind()
        brush.moveTo(x, y - 2.7f)
        brush.lineTo(x + 2.7f, y)
        brush.lineTo(x, y + 2.7f)
        brush.lineTo(x - 2.7f, y)
        brush.close()
        ink(soluteInk); c.drawPath(brush, paint)
    }

    private fun fill(c: Canvas, path: Path, fill: Shader) {
        ink(cream); paint.shader = fill; c.drawPath(path, paint); paint.shader = null
    }

    private fun strip(top: (Float) -> Float, bottom: (Float) -> Float, left: Float = LEFT, right: Float = RIGHT) =
        Path().apply {
            val samples = ((right - left) / 2f).toInt().coerceAtLeast(1)
            fun x(i: Int) = left + (right - left) * i / samples
            moveTo(left, top(left))
            for (i in 1..samples) lineTo(x(i), top(x(i)))
            for (i in samples downTo 0) lineTo(x(i), bottom(x(i)))
            close()
        }

    private fun filtrationRoute(pore: Float, slit: Float, exit: Float) = Path().apply {
        moveTo(pore, wallY(pore) - 29f)
        lineTo(pore, wallY(pore) - 1f)
        quadTo(pore, wallY(pore) + 5f, slit, footY(slit) - 1f)
        lineTo(slit, footY(slit) + 9f)
        cubicTo(slit, footY(slit) + 27f, exit, 261f, exit, 293f)
    }

    private fun wallY(x: Float): Float {
        val dx = x - 134f
        return 173f - .0008f * dx * dx
    }

    private fun endoY(x: Float): Float {
        val bulge = (1f - abs(x - 81f) / 15f).coerceAtLeast(0f)
        return wallY(x) - 12f - 12f * bulge * bulge
    }

    private fun footY(x: Float) = wallY(x) + MATRIX_DEPTH

    private fun withAlpha(color: Long, opacity: Float) =
        (color and 0x00ffffff) or ((opacity * 255f).toLong() shl 24)

    companion object {
        const val DURATION_MS = 20_000L
        const val STRUCTURE_SOURCE = "https://pubmed.ncbi.nlm.nih.gov/25759085/"
        const val ALBUMIN_SOURCE = "https://pubmed.ncbi.nlm.nih.gov/940256/"
        private const val LEFT = 24f
        private const val RIGHT = 244f
        private const val MATRIX_DEPTH = 13f
    }
}
