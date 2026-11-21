package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader

internal class HealthAtlasFibroblastStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.FIBROBLAST_MATRIX) {
    private val dermalFill = shade(108f, 274f, 0xffffeee7, 0xffecd0d8)
    private val surfaceFill = shade(79f, 134f, 0xffffecdb, 0xfff0bcb0)
    private val cellFill = shade(192f, 226f, 0xffe0d8f2, 0xffaf93c7)
    private val collagenInk = 0xffaa757e
    private val newFiberInk = 0xff397f76
    private val cueInk = 0xff547f9e
    private val leaderInk = 0xff665969
    private val fiberPath = Path()
    private val segment = Path()
    private val measure = PathMeasure()

    private val dermis = Path().apply {
        moveTo(33f, 105f)
        lineTo(305f, 105f)
        quadTo(310f, 106f, 310f, 113f)
        lineTo(310f, 259f)
        quadTo(310f, 273f, 297f, 273f)
        lineTo(47f, 273f)
        quadTo(33f, 273f, 33f, 259f)
        close()
    }
    private val side = Path().apply {
        moveTo(310f, 105f)
        lineTo(329f, 88f)
        lineTo(329f, 244f)
        quadTo(329f, 251f, 323f, 256f)
        lineTo(306f, 269f)
        quadTo(310f, 264f, 310f, 258f)
        close()
    }
    private val epidermalBand = Path().apply {
        moveTo(33f, 105f)
        quadTo(87f, 100f, 134f, 105f)
        quadTo(184f, 110f, 218f, 104f)
        quadTo(263f, 99f, 310f, 105f)
        lineTo(310f, 133f)
        cubicTo(288f, 138f, 276f, 125f, 250f, 132f)
        cubicTo(230f, 139f, 217f, 127f, 194f, 134f)
        cubicTo(170f, 141f, 154f, 126f, 133f, 133f)
        cubicTo(112f, 140f, 96f, 127f, 76f, 132f)
        quadTo(49f, 140f, 33f, 133f)
        close()
    }
    private val epidermalTop = Path().apply {
        moveTo(33f, 105f)
        lineTo(53f, 88f)
        quadTo(101f, 82f, 154f, 88f)
        quadTo(201f, 93f, 239f, 87f)
        quadTo(279f, 82f, 329f, 88f)
        lineTo(310f, 105f)
        quadTo(263f, 99f, 218f, 104f)
        quadTo(184f, 110f, 134f, 105f)
        quadTo(87f, 100f, 33f, 105f)
        close()
    }
    private val epidermalEdge = Path().apply {
        moveTo(310f, 105f)
        lineTo(329f, 88f)
        lineTo(329f, 115f)
        lineTo(310f, 133f)
        close()
    }
    private val surfaceDetail = Path().apply {
        moveTo(47f, 102f)
        quadTo(92f, 96f, 132f, 101f)
        moveTo(218f, 100f)
        quadTo(267f, 94f, 304f, 100f)
        moveTo(38f, 120f)
        cubicTo(108f, 113f, 158f, 126f, 225f, 119f)
        quadTo(270f, 113f, 305f, 120f)
    }
    private val cell = Path().apply {
        moveTo(129f, 229f)
        cubicTo(149f, 214f, 150f, 200f, 173f, 197f)
        cubicTo(195f, 194f, 210f, 201f, 232f, 186f)
        cubicTo(218f, 208f, 199f, 211f, 187f, 217f)
        cubicTo(165f, 226f, 151f, 217f, 129f, 229f)
        close()
    }
    private val cellDetail = Path().apply {
        moveTo(146f, 221f)
        quadTo(158f, 210f, 161f, 209f)
        moveTo(195f, 204f)
        quadTo(213f, 202f, 222f, 195f)
    }

    private val scaffold = listOf(
        Fiber(54f, 162f, 92f, 143f, 111f, 164f, 143f, 150f),
        Fiber(150f, 154f, 191f, 166f, 214f, 135f, 248f, 150f),
        Fiber(248f, 150f, 267f, 155f, 283f, 164f, 298f, 154f),
        Fiber(47f, 208f, 75f, 207f, 97f, 179f, 147f, 188f),
        Fiber(57f, 225f, 73f, 201f, 103f, 207f, 118f, 190f),
        Fiber(156f, 174f, 189f, 169f, 201f, 190f, 227f, 168f),
        Fiber(62f, 238f, 95f, 226f, 122f, 247f, 151f, 233f),
        Fiber(57f, 257f, 84f, 244f, 101f, 261f, 127f, 253f),
        Fiber(112f, 262f, 143f, 254f, 156f, 225f, 195f, 234f),
        Fiber(179f, 257f, 215f, 239f, 241f, 257f, 270f, 239f),
        Fiber(249f, 247f, 270f, 228f, 285f, 243f, 299f, 225f),
    )
    private val outgoing = listOf(
        Fiber(216f, 182f, 238f, 166f, 263f, 192f, 288f, 171f) to
            Fiber(216f, 181f, 239f, 168f, 260f, 174f, 294f, 169f),
        Fiber(231f, 194f, 261f, 181f, 276f, 213f, 299f, 185f) to
            Fiber(230f, 195f, 253f, 186f, 275f, 196f, 298f, 187f),
        Fiber(214f, 215f, 236f, 200f, 242f, 238f, 270f, 217f) to
            Fiber(213f, 213f, 232f, 218f, 246f, 239f, 279f, 226f),
        Fiber(202f, 226f, 221f, 221f, 224f, 246f, 243f, 244f) to
            Fiber(202f, 225f, 220f, 229f, 220f, 249f, 243f, 253f),
    )
    private val olderFiber = Fiber(62f, 181f, 86f, 160f, 109f, 186f, 134f, 171f)
    private val renewedFiber = Fiber(62f, 183f, 92f, 178f, 105f, 158f, 133f, 170f)

    init { tag = "atlas-function-fibroblast-matrix-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        drawPatch(c)
        val turnover = if (step == 4) eased(t, .06f, .92f) else 0f
        for (fiber in scaffold) {
            fiber.trace(fiberPath)
            drawFiber(c, fiberPath, collagenInk, 2.7f)
        }
        olderFiber.trace(fiberPath)
        drawFiber(c, fiberPath, collagenInk, 2.7f, 1f - turnover)
        if (turnover > 0f) {
            renewedFiber.trace(fiberPath)
            drawSegment(c, 0f, turnover, collagenInk, 2.7f, turnover)
        }

        if (step == 0) {
            traceBundle(c, scaffold[1], t)
            traceBundle(c, scaffold[6], t)
        }
        if (step == 1) drawRepairCue(c, t)
        if (step >= 2) drawNewMatrix(c, step, t)
        tissue(c, cell, cellFill, violet)
        oval(c, 166f, 200f, 190f, 213f, 0xff795489, 0xff634372)
        stroke(c, cellDetail, 0xfff6ecfc, 1.45f)
        drawCallouts(c)
    }

    private fun drawPatch(c: Canvas) {
        rounded(c, 39f, 107f, 326f, 281f, 17f, 0x186b514a)
        ink(0xffdfb4be)
        c.drawPath(side, paint)
        stroke(c, side, coral, 1.25f)
        for (row in 0..3) {
            val y = 160f + row * 24f
            line(c, 314f, y, 325f, y - 10f, 0xffc28a99, 1.4f)
        }
        tissue(c, dermis, dermalFill, coral)
        ink(0xffd99a92)
        c.drawPath(epidermalEdge, paint)
        stroke(c, epidermalEdge, coral, 1.25f)
        tissue(c, epidermalBand, surfaceFill, coral)
        tissue(c, epidermalTop, surfaceFill, coral)
        stroke(c, surfaceDetail, 0xfffff3e4, 1.5f)
    }

    private fun drawRepairCue(c: Canvas, t: Float) {
        // A local pulse is a symbol for repair cues, not a moving cell or a visible wound.
        for (i in 0..1) {
            val pulse = ((t - .19f * i) / .78f).coerceIn(0f, 1f)
            val alpha = 4f * pulse * (1f - pulse)
            if (alpha == 0f) continue
            ink(cueInk, 2f)
            paint.alpha = (185f * alpha).toInt()
            c.drawCircle(112f, 174f, 7f + 40f * pulse, paint)
        }
        val focus = eased(t, .45f, .75f) * (1f - eased(t, .82f, 1f))
        if (focus > 0f) {
            ink(violet, 4f)
            paint.alpha = (125f * focus).toInt()
            c.drawPath(cell, paint)
        }
    }

    private fun drawNewMatrix(c: Canvas, step: Int, t: Float) {
        val arrangement = when (step) {
            2 -> 0f
            3 -> eased(t, .08f, .92f)
            else -> 1f
        }
        for ((i, shapes) in outgoing.withIndex()) {
            val growth = if (step == 2) eased(t, .05f + .11f * i, .54f + .13f * i) else 1f
            if (growth == 0f) continue
            shapes.first.trace(fiberPath, shapes.second, arrangement)
            if (growth == 1f) drawFiber(c, fiberPath, newFiberInk, 2.7f)
            else drawSegment(c, 0f, growth, newFiberInk, 2.7f, 1f)
        }
    }

    private fun drawCallouts(c: Canvas) {
        label(c, R.string.health_atlas_fibroblast_story_epidermis, 91f, 51f, 116f)
        line(c, 91f, 59f, 91f, 113f, leaderInk, 1.15f)
        disc(c, 91f, 113f, 2.6f, coral, cream)

        label(c, R.string.health_atlas_fibroblast_story_dermis, 278f, 51f, 126f)
        line(c, 300f, 57f, 340f, 73f, leaderInk, 1.15f)
        line(c, 340f, 73f, 340f, 157f, leaderInk, 1.15f)
        line(c, 340f, 157f, 321f, 174f, leaderInk, 1.15f)
        disc(c, 321f, 174f, 2.6f, coral, cream)

        label(c, R.string.health_atlas_fibroblast_story_collagen, 88f, 323f, 138f)
        line(c, 88f, 308f, 88f, 235f, leaderInk, 1.15f)
        disc(c, 88f, 235f, 2.6f, collagenInk, cream)

        label(c, R.string.health_atlas_fibroblast_story_fibroblast, 244f, 323f, 134f)
        line(c, 244f, 308f, 244f, 287f, leaderInk, 1.15f)
        line(c, 244f, 287f, 184f, 216f, leaderInk, 1.15f)
        disc(c, 184f, 216f, 2.6f, violet, cream)
    }

    private fun tissue(c: Canvas, path: Path, fill: Shader, border: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, border, 1.35f)
    }

    private fun drawFiber(c: Canvas, path: Path, color: Long, width: Float, alpha: Float = 1f) {
        if (alpha <= 0f) return
        val opacity = (255f * alpha).toInt()
        ink(0xfffff4e9, width + 2.3f)
        paint.alpha = opacity
        c.drawPath(path, paint)
        ink(color, width)
        paint.alpha = opacity
        c.drawPath(path, paint)
    }

    private fun traceBundle(c: Canvas, fiber: Fiber, t: Float) {
        fiber.trace(fiberPath)
        val head = t * 1.25f
        drawSegment(c, head - .25f, head, 0xffffe0a9, 3.2f, 1f)
    }

    private fun drawSegment(c: Canvas, start: Float, end: Float, color: Long, width: Float, alpha: Float) {
        measure.setPath(fiberPath, false)
        segment.rewind()
        val length = measure.length
        if (measure.getSegment(start.coerceIn(0f, 1f) * length, end.coerceIn(0f, 1f) * length, segment, true)) {
            drawFiber(c, segment, color, width, alpha)
        }
    }

    private fun eased(t: Float, from: Float, to: Float): Float {
        val f = ((t - from) / (to - from)).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }

    private data class Fiber(
        val x0: Float, val y0: Float, val x1: Float, val y1: Float,
        val x2: Float, val y2: Float, val x3: Float, val y3: Float,
    ) {
        fun trace(path: Path, target: Fiber = this, fraction: Float = 0f) {
            fun mix(a: Float, b: Float) = a + (b - a) * fraction
            path.rewind()
            path.moveTo(mix(x0, target.x0), mix(y0, target.y0))
            path.cubicTo(
                mix(x1, target.x1), mix(y1, target.y1),
                mix(x2, target.x2), mix(y2, target.y2),
                mix(x3, target.x3), mix(y3, target.y3),
            )
        }
    }
}
