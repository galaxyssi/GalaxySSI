package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader
import com.galaxyssi.chat.R.string

internal object HealthAtlasAutonomicRelayMotion {
    fun output(t: Float, vagal: Boolean) =
        if (vagal) segment(t, .08f, .95f) * .64f else segment(t, .18f, .9f) * .86f

    fun sympatheticApproach(t: Float) = segment(t, .04f, .52f)
    fun sympatheticHandoff(t: Float) = bump(t, .46f, .89f)
    fun sympatheticExit(t: Float) = segment(t, .64f, .98f) * .33f
    fun cardiacArrival(t: Float) = segment(t, .06f, .68f)
    fun beatSpacing(t: Float) = 49f - 17f * segment(t, .38f, .96f)
    fun vagalDescent(t: Float) = segment(t, .03f, .62f)
    fun vagalHandoff(t: Float) = bump(t, .55f, .89f)
    fun vagalExit(t: Float) = segment(t, .68f, .98f)

    // Separate streams stay present together; these phases are not physiological timings.
    fun ongoing(t: Float, vagal: Boolean) = HealthAtlasFunctionStory.safePhase(t).let {
        if (vagal) (.83f * it + .38f) % 1f else (1.10f * it + .12f) % 1f
    }

    private fun segment(t: Float, start: Float, end: Float): Float {
        val f = ((HealthAtlasFunctionStory.safePhase(t) - start) / (end - start)).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }

    private fun bump(t: Float, start: Float, end: Float): Float {
        val f = ((HealthAtlasFunctionStory.safePhase(t) - start) / (end - start)).coerceIn(0f, 1f)
        return 4f * f * (1f - f)
    }
}

internal class HealthAtlasAutonomicRelayStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.AUTONOMIC_RELAY) {
    private val guide = 0xff596f73
    private val sympathetic = 0xff98602f
    private val vagal = 0xff367b73
    private val neuralEdge = 0xff9b778b
    private val heartEdge = 0xff925e6e
    private val node = 0xff795777
    private val centralWash = shade(38f, 150f, 0xffecd1bf, 0xffd9b1ae)
    private val chestWash = shade(88f, 320f, 0xfff5e8dc, 0xffefe3d7)
    private val heartWash = shade(212f, 302f, 0xffefb8ac, 0xffcb8391)
    private val vesselBlue = 0xffa2b7c6
    private val vesselRed = 0xffdba09e
    private val trace = Path()

    private val torso = path {
        moveTo(146f, 81f)
        cubicTo(149f, 110f, 117f, 104f, 89f, 119f)
        cubicTo(65f, 132f, 59f, 161f, 64f, 188f)
        cubicTo(72f, 237f, 70f, 277f, 77f, 309f)
        quadTo(175f, 337f, 282f, 309f)
        cubicTo(290f, 272f, 286f, 229f, 294f, 188f)
        cubicTo(300f, 160f, 296f, 135f, 273f, 121f)
        cubicTo(247f, 108f, 210f, 110f, 210f, 81f)
        close()
    }
    private val lung = path {
        moveTo(151f, 124f)
        cubicTo(132f, 111f, 104f, 134f, 95f, 169f)
        cubicTo(85f, 196f, 86f, 233f, 91f, 249f)
        cubicTo(100f, 271f, 139f, 270f, 153f, 246f)
        cubicTo(160f, 221f, 147f, 202f, 154f, 183f)
        cubicTo(160f, 165f, 165f, 136f, 151f, 124f)
        close()
    }
    private val brain = path {
        moveTo(145f, 75f)
        cubicTo(131f, 68f, 130f, 55f, 142f, 49f)
        cubicTo(143f, 40f, 158f, 36f, 167f, 40f)
        cubicTo(176f, 33f, 188f, 38f, 191f, 43f)
        cubicTo(207f, 41f, 216f, 50f, 214f, 62f)
        cubicTo(225f, 76f, 208f, 83f, 195f, 79f)
        cubicTo(179f, 86f, 167f, 83f, 159f, 77f)
        quadTo(151f, 80f, 145f, 75f)
        close()
    }
    private val folds = path {
        moveTo(142f, 59f)
        quadTo(151f, 51f, 161f, 56f)
        quadTo(169f, 61f, 175f, 49f)
        moveTo(151f, 69f)
        cubicTo(158f, 63f, 165f, 71f, 174f, 68f)
        quadTo(186f, 66f, 185f, 55f)
        moveTo(187f, 74f)
        quadTo(196f, 62f, 208f, 64f)
        moveTo(194f, 54f)
        quadTo(202f, 51f, 208f, 55f)
    }
    private val cord = path {
        moveTo(178f, 71f)
        cubicTo(173f, 90f, 175f, 111f, 174f, 132f)
        cubicTo(173f, 158f, 171f, 193f, 170f, 224f)
    }
    private val sympatheticTrunk = path {
        moveTo(128f, 116f)
        cubicTo(122f, 130f, 119f, 145f, 120f, 151f)
        quadTo(115f, 174f, 115f, 203f)
    }
    private val heart = path {
        moveTo(176f, 218f)
        cubicTo(162f, 208f, 143f, 214f, 142f, 233f)
        cubicTo(139f, 255f, 164f, 266f, 181f, 276f)
        cubicTo(198f, 286f, 213f, 301f, 225f, 302f)
        cubicTo(239f, 296f, 247f, 264f, 243f, 242f)
        cubicTo(241f, 217f, 224f, 211f, 211f, 213f)
        cubicTo(196f, 209f, 191f, 222f, 176f, 218f)
        close()
    }
    private val venaCava = path {
        moveTo(150f, 188f)
        cubicTo(150f, 204f, 155f, 216f, 160f, 224f)
    }
    private val aorta = path {
        moveTo(188f, 226f)
        cubicTo(185f, 210f, 176f, 194f, 185f, 184f)
        cubicTo(194f, 173f, 209f, 175f, 216f, 182f)
    }
    private val pulmonaryTrunk = path {
        moveTo(188f, 227f)
        cubicTo(195f, 218f, 204f, 206f, 224f, 202f)
    }
    private val heartDetail = path {
        moveTo(145f, 238f)
        cubicTo(161f, 240f, 173f, 229f, 187f, 230f)
        cubicTo(201f, 229f, 212f, 222f, 225f, 220f)
        moveTo(188f, 232f)
        cubicTo(192f, 252f, 203f, 275f, 225f, 295f)
        moveTo(196f, 251f)
        quadTo(206f, 253f, 213f, 260f)
        moveTo(205f, 270f)
        quadTo(214f, 271f, 218f, 277f)
    }
    private val symFirst = route {
        moveTo(SPINAL_X, SPINAL_Y)
        cubicTo(157f, 138f, 133f, 144f, THORACIC_X, THORACIC_Y)
    }
    private val symSecond = route {
        moveTo(THORACIC_X, THORACIC_Y)
        cubicTo(105f, 161f, 103f, 192f, 121f, 207f)
        quadTo(135f, 222f, SA_X, SA_Y)
    }
    private val vagFirst = route {
        moveTo(MEDULLA_X, MEDULLA_Y)
        cubicTo(207f, 92f, 226f, 110f, 227f, 135f)
        cubicTo(230f, 160f, 228f, 186f, CARDIAC_X, CARDIAC_Y)
    }
    private val vagSecond = route {
        moveTo(CARDIAC_X, CARDIAC_Y)
        quadTo(179f, 209f, SA_X, SA_Y)
    }
    private val compareSymFirst = route {
        moveTo(40f, 112f)
        lineTo(107f, 112f)
    }
    private val compareSymSecond = route {
        moveTo(107f, 112f)
        cubicTo(191f, 112f, 228f, 111f, 271f, 177f)
    }
    private val compareVagFirst = route {
        moveTo(40f, 237f)
        lineTo(216f, 237f)
    }
    private val compareVagSecond = route {
        moveTo(216f, 237f)
        quadTo(247f, 233f, 271f, 177f)
    }

    init { tag = "atlas-function-autonomic-relay-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> output(c, t)
            1 -> sympatheticRelay(c, t)
            2 -> cardiacTarget(c, t)
            3 -> vagalRelay(c, t)
            4 -> compare(c, t)
        }
    }

    private fun output(c: Canvas, t: Float) {
        anatomy(c, showSympathetic = true)
        fiber(c, symFirst, sympathetic, first = true)
        fiber(c, vagFirst, vagal, first = true)
        segment(c, symFirst, motion.output(t, false), sympathetic)
        segment(c, vagFirst, motion.output(t, true), vagal)
        disc(c, SPINAL_X, SPINAL_Y, 4.3f, sympathetic, cream)
        disc(c, MEDULLA_X, MEDULLA_Y, 4.3f, vagal, cream)
        target(c, 0f)
        callout(c, string.health_atlas_autonomic_relay_story_art_brainstem, 271f, 69f, 99f, MEDULLA_X, MEDULLA_Y)
        leader(c, string.health_atlas_autonomic_relay_story_art_cord, 48f, 116f, 90f, 88f, 119f, SPINAL_X, SPINAL_Y)
        callout(c, string.health_atlas_autonomic_relay_story_art_heart, 257f, 326f, 78f, 232f, 277f)
    }

    private fun sympatheticRelay(c: Canvas, t: Float) {
        anatomy(c, showSympathetic = true)
        fiber(c, symFirst, sympathetic, first = true)
        fiber(c, symSecond, sympathetic, first = false)
        val arrival = motion.sympatheticApproach(t)
        val exit = motion.sympatheticExit(t)
        segment(c, symFirst, arrival, sympathetic)
        segment(c, symSecond, exit, sympathetic)
        disc(c, SPINAL_X, SPINAL_Y, 3.9f, sympathetic, cream)
        ganglion(c, THORACIC_X, THORACIC_Y, sympathetic, motion.sympatheticHandoff(t))
        target(c, 0f)
        callout(c, string.health_atlas_autonomic_relay_story_art_thoracic_ganglion, 75f, 91f, 141f, THORACIC_X, THORACIC_Y)
        callout(c, string.health_atlas_autonomic_relay_story_art_cord, 278f, 124f, 106f, SPINAL_X, SPINAL_Y)
        callout(c, string.health_atlas_autonomic_relay_story_art_cardiac_fiber, 87f, 285f, 146f, 129f, 214f)
    }

    private fun cardiacTarget(c: Canvas, t: Float) {
        val arrival = motion.cardiacArrival(t)
        c.save()
        c.translate(139f, 140f)
        c.scale(1.37f, 1.37f)
        c.translate(-SA_X, -SA_Y)
        drawHeart(c)
        fiber(c, symSecond, sympathetic, first = false)
        segment(c, symSecond, arrival, sympathetic)
        ganglion(c, THORACIC_X, THORACIC_Y, sympathetic, 0f)
        target(c, ((arrival - .83f) / .17f).coerceIn(0f, 1f))
        c.restore()
        callout(c, string.health_atlas_autonomic_relay_story_art_thoracic_ganglion, 174f, 25f, 146f, 83f, 39f)
        leader(c, string.health_atlas_autonomic_relay_story_art_sa_node, 50f, 171f, 85f, 82f, 165f, 139f, 140f)
        callout(c, string.health_atlas_autonomic_relay_story_art_heart, 285f, 148f, 92f, 245f, 176f)
        label(c, string.health_atlas_autonomic_relay_story_art_beat_spacing, 180f, 273f, 162f)
        beatMarks(c, t, motion.beatSpacing(t))
    }

    private fun vagalRelay(c: Canvas, t: Float) {
        anatomy(c, showSympathetic = false)
        fiber(c, vagFirst, vagal, first = true)
        fiber(c, vagSecond, vagal, first = false)
        segment(c, vagFirst, motion.vagalDescent(t), vagal)
        val exit = motion.vagalExit(t)
        segment(c, vagSecond, exit, vagal)
        disc(c, MEDULLA_X, MEDULLA_Y, 3.9f, vagal, cream)
        ganglion(c, CARDIAC_X, CARDIAC_Y, vagal, motion.vagalHandoff(t))
        target(c, ((exit - .76f) / .24f).coerceIn(0f, 1f))
        callout(c, string.health_atlas_autonomic_relay_story_art_brainstem, 76f, 97f, 108f, MEDULLA_X, MEDULLA_Y)
        leader(c, string.health_atlas_autonomic_relay_story_art_vagus, 295f, 140f, 116f, 252f, 135f, 227f, 135f)
        callout(c, string.health_atlas_autonomic_relay_story_art_cardiac_ganglion, 280f, 171f, 142f, CARDIAC_X, CARDIAC_Y)
        callout(c, string.health_atlas_autonomic_relay_story_art_sa_node, 83f, 267f, 115f, SA_X, SA_Y)
    }

    private fun compare(c: Canvas, t: Float) {
        c.save()
        c.translate(271f, 177f)
        c.scale(.73f, .73f)
        c.translate(-SA_X, -SA_Y)
        drawHeart(c)
        c.restore()
        compareRoute(c, compareSymFirst, compareSymSecond, 107f, 112f, sympathetic, .29f, motion.ongoing(t, false))
        compareRoute(c, compareVagFirst, compareVagSecond, 216f, 237f, vagal, .64f, motion.ongoing(t, true))
        disc(c, 271f, 177f, 4.5f, node, cream)
        label(c, string.health_atlas_autonomic_relay_story_art_sympathetic, 101f, 52f, 170f)
        label(c, string.health_atlas_autonomic_relay_story_art_parasympathetic, 112f, 304f, 185f)
        callout(c, string.health_atlas_autonomic_relay_story_art_thoracic_ganglion, 106f, 157f, 174f, 107f, 112f)
        callout(c, string.health_atlas_autonomic_relay_story_art_cardiac_ganglion, 186f, 196f, 143f, 216f, 237f)
        callout(c, string.health_atlas_autonomic_relay_story_art_sa_node, 299f, 100f, 106f, 271f, 177f)
    }

    private fun anatomy(c: Canvas, showSympathetic: Boolean) {
        tissue(c, torso, chestWash, 0xffc9b7a7)
        ink(0xffecd4cb)
        c.drawPath(lung, paint)
        c.save()
        c.scale(-1f, 1f, 180f, 0f)
        c.drawPath(lung, paint)
        c.restore()
        for (i in 0..5) {
            val y = 122f + i * 16f
            rounded(c, 166f, y, 183f, y + 12f, 3f, 0xffe1c9b8)
        }
        stroke(c, cord, neuralEdge, 9f)
        stroke(c, cord, 0xffe7bfb7, 6.4f)
        oval(c, 182f, 66f, 212f, 87f, 0xffd8aeac, neuralEdge)
        for (i in 0..2) line(c, 192f, 76f + 3f * i, 206f, 75f + 3f * i, neuralEdge, .9f)
        tissue(c, brain, centralWash, neuralEdge)
        stroke(c, folds, neuralEdge, 1.2f)
        if (showSympathetic) {
            stroke(c, sympatheticTrunk, 0xffbe9470, 2.2f)
            oval(c, 119f, 124f, 128f, 134f, sand, sympathetic)
            oval(c, 112f, 168f, 122f, 179f, sand, sympathetic)
            oval(c, 111f, 192f, 120f, 202f, sand, sympathetic)
            oval(c, 115f, 145f, 125f, 157f, sand, sympathetic)
        }
        drawHeart(c)
    }

    private fun drawHeart(c: Canvas) {
        vessel(c, venaCava, vesselBlue, 13f)
        vessel(c, aorta, vesselRed, 15f)
        line(c, 194f, 178f, 191f, 167f, heartEdge, 5.6f)
        line(c, 194f, 178f, 191f, 167f, vesselRed, 3.9f)
        line(c, 204f, 177f, 205f, 166f, heartEdge, 5.2f)
        line(c, 204f, 177f, 205f, 166f, vesselRed, 3.5f)
        vessel(c, pulmonaryTrunk, vesselBlue, 10f)
        tissue(c, heart, heartWash, heartEdge)
        stroke(c, heartDetail, heartEdge, 1.35f)
    }

    private fun beatMarks(c: Canvas, t: Float, spacing: Float) {
        val left = 52f
        val right = 308f
        val y = 299f
        arrow(c, left, y, right, y, guide)
        val travel = (t * 2.4f % 1f) * spacing
        for (i in 0..8) {
            val x = left + travel + spacing * i
            if (x < left + 7f || x > right - 13f) continue
            line(c, x, y - 11f, x, y + 5f, node, 2f)
            disc(c, x, y - 11f, 2.4f, node)
        }
    }

    private fun compareRoute(
        c: Canvas, first: Fiber, second: Fiber, x: Float, y: Float,
        color: Long, split: Float, phase: Float,
    ) {
        fiber(c, first, color, first = true)
        fiber(c, second, color, first = false)
        at(first.track, 0f) { sx, sy -> disc(c, sx, sy, 4.8f, color, cream) }
        val handoff = (1f - kotlin.math.abs(phase - split) / .08f).coerceIn(0f, 1f)
        ganglion(c, x, y, color, handoff)
        val f = if (phase < split) phase / split else (phase - split) / (1f - split)
        at(if (phase < split) first.track else second.track, f) { px, py ->
            disc(c, px, py, 4.2f, color, cream)
        }
    }

    private fun fiber(c: Canvas, fiber: Fiber, color: Long, first: Boolean) {
        val width = if (first) 3.5f else 2.15f
        stroke(c, fiber.path, cream, width + 2.7f)
        stroke(c, fiber.path, color, width)
    }

    private fun segment(c: Canvas, fiber: Fiber, fraction: Float, color: Long) {
        if (fraction <= 0f) return
        val length = fiber.track.length
        trace.rewind()
        if (fiber.track.getSegment(length * (fraction - .18f).coerceAtLeast(0f), length * fraction, trace, true)) {
            stroke(c, trace, color, 5.1f)
        }
        if (fraction < 1f) at(fiber.track, fraction) { x, y -> disc(c, x, y, 3.9f, color, cream) }
    }

    private fun ganglion(c: Canvas, x: Float, y: Float, color: Long, activity: Float) {
        if (activity > 0f) {
            ink(color, 1.25f)
            c.drawCircle(x, y, 8f + 5f * activity, paint)
        }
        oval(c, x - 7f, y - 8f, x + 7f, y + 8f, cream, color)
        disc(c, x - 2.1f, y - 2.2f, 1.75f, color)
        disc(c, x + 1.9f, y + 2.1f, 2.25f + activity, color)
    }

    private fun target(c: Canvas, activity: Float) {
        disc(c, SA_X, SA_Y, 4f, node, cream)
        if (activity > 0f) {
            ink(node, 1.15f)
            c.drawCircle(SA_X, SA_Y, 5.8f + 2.8f * activity, paint)
        }
    }

    private fun tissue(c: Canvas, shape: Path, fill: Shader, edge: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(shape, paint)
        paint.shader = null
        stroke(c, shape, edge, 1.45f)
    }

    private fun vessel(c: Canvas, shape: Path, color: Long, width: Float) {
        stroke(c, shape, heartEdge, width)
        stroke(c, shape, color, width - 2.5f)
    }

    private fun callout(c: Canvas, res: Int, x: Float, y: Float, width: Float, tx: Float, ty: Float) {
        leader(c, res, x, y, width, x, if (ty > y) y + 5f else y - 14f, tx, ty)
    }

    private fun leader(c: Canvas, res: Int, x: Float, y: Float, width: Float, ax: Float, ay: Float, tx: Float, ty: Float) {
        line(c, ax, ay, tx, ty, guide, 1f)
        disc(c, tx, ty, 1.65f, guide, cream)
        label(c, res, x, y, width)
    }

    private fun path(block: Path.() -> Unit) = Path().apply(block)
    private fun route(block: Path.() -> Unit) = path(block).let { Fiber(it, track(it)) }
    private class Fiber(val path: Path, val track: PathMeasure)

    private companion object {
        val motion = HealthAtlasAutonomicRelayMotion
        const val MEDULLA_X = 181f
        const val MEDULLA_Y = 90f
        const val SPINAL_X = 174f
        const val SPINAL_Y = 147f
        const val THORACIC_X = 120f
        const val THORACIC_Y = 151f
        const val CARDIAC_X = 202f
        const val CARDIAC_Y = 204f
        const val SA_X = 161f
        const val SA_Y = 225f
    }
}
