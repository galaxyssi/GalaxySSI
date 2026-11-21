package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import androidx.annotation.StringRes
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

internal class HealthAtlasCranialReflexStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.CRANIAL_REFLEX) {
    private val guide = 0xff65747e
    private val light = 0xffb47c31
    private val sensory = 0xff26746e
    private val sensoryRest = 0xff8cb2a8
    private val relay = 0xff755587
    private val relayRest = 0xffae94b7
    private val motor = 0xffa25264
    private val motorRest = 0xffc79ba1
    private val eyeBorder = 0xff936964
    private val midbrainBorder = 0xffac7d8b
    private val sclera = shade(55f, 96f, 0xfffffbf3, 0xffedd9cf)
    private val iris = shade(51f, 94f, 0xffb1b99a, 0xff688e83)
    private val brain = shade(222f, 313f, 0xfff3d9df, 0xffe3bcc9)

    private val eye = Path().apply {
        moveTo(-47f, 74f)
        cubicTo(-33f, 55f, -15f, 52f, 0f, 53f)
        cubicTo(22f, 54f, 37f, 64f, 47f, 78f)
        cubicTo(32f, 89f, 17f, 98f, -4f, 96f)
        cubicTo(-24f, 94f, -40f, 84f, -47f, 74f)
        close()
    }
    private val lid = Path().apply {
        moveTo(-51f, 72f)
        cubicTo(-28f, 45f, 10f, 40f, 40f, 63f)
        moveTo(-47f, 74f)
        cubicTo(-26f, 49f, 15f, 42f, 47f, 78f)
        moveTo(-35f, 87f); quadTo(-15f, 105f, 15f, 100f)
    }
    private val globeSection = Path().apply {
        moveTo(-35f, 83f)
        cubicTo(-32f, 106f, -20f, 122f, 0f, 124f)
        cubicTo(20f, 122f, 33f, 105f, 35f, 84f)
        quadTo(0f, 93f, -35f, 83f)
        close()
    }
    private val retina = Path().apply {
        moveTo(-24f, 103f)
        quadTo(-14f, 120f, 0f, 120f)
        quadTo(14f, 120f, 24f, 103f)
    }
    private val lightGuide = Path().apply {
        moveTo(56f, 44f); quadTo(71f, 51f, 82f, 64f)
    }
    private val lightIn = Path().apply {
        moveTo(56f, 44f); quadTo(77f, 54f, 90f, 75f)
    }
    private val lightThrough = Path().apply {
        moveTo(90f, 91f); lineTo(90f, 117f)
    }
    private val lightTrack = track(lightIn)
    private val lightThroughTrack = track(lightThrough)
    private val retinaOnLitSide = Path(retina).apply { offset(90f, 0f) }

    private val midbrain = Path().apply {
        moveTo(180f, 222f)
        cubicTo(163f, 211f, 146f, 220f, 140f, 231f)
        cubicTo(120f, 236f, 111f, 250f, 117f, 269f)
        cubicTo(120f, 289f, 136f, 307f, 153f, 312f)
        cubicTo(166f, 317f, 174f, 312f, 180f, 306f)
        cubicTo(186f, 312f, 194f, 317f, 207f, 312f)
        cubicTo(224f, 307f, 240f, 289f, 243f, 269f)
        cubicTo(249f, 250f, 240f, 236f, 220f, 231f)
        cubicTo(214f, 220f, 197f, 211f, 180f, 222f)
        close()
    }
    private val midbrainFolds = Path().apply {
        moveTo(143f, 233f); quadTo(156f, 221f, 172f, 228f)
        moveTo(188f, 228f); quadTo(204f, 221f, 217f, 233f)
        moveTo(123f, 256f); quadTo(136f, 246f, 151f, 252f)
        moveTo(209f, 252f); quadTo(224f, 246f, 237f, 256f)
        moveTo(130f, 271f); cubicTo(132f, 288f, 150f, 301f, 164f, 304f)
        moveTo(230f, 271f); cubicTo(228f, 288f, 210f, 301f, 196f, 304f)
    }
    private val routes = listOf(SideRoutes(1f), SideRoutes(-1f))
    private val trail = Path()
    private val spokes = Path()

    init { tag = "atlas-function-cranial-reflex-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val narrowing = if (step == 4) ease(t, .08f, .84f) else 0f
        val radius = 12.6f - 6.6f * narrowing
        traceIris(radius)
        drawMidbrain(c)
        drawEye(c, 90f, 1f, radius, narrowing)
        drawEye(c, 270f, -1f, radius, narrowing)
        drawRoutes(c, step, t)
        drawLight(c, step, t)
        drawLabels(c, step)
    }

    private fun drawEye(c: Canvas, x: Float, direction: Float, pupilRadius: Float, narrowing: Float) {
        c.save()
        c.translate(x, 0f)
        c.scale(direction, 1f)
        // The pale extension below the frontal iris exposes the posterior retinal lining.
        ink(0xfff5e9df); c.drawPath(globeSection, paint)
        stroke(c, globeSection, 0xffc8a6a0, 1.1f)
        stroke(c, retina, 0xffc48177, 3.6f)
        stroke(c, retina, 0xffebad91, 1.6f)
        ink(cream)
        paint.shader = sclera
        c.drawPath(eye, paint)
        paint.shader = null
        stroke(c, eye, eyeBorder, 1.25f)
        c.save()
        c.clipPath(eye)
        oval(c, -22f, 52f, 22f, 97f, iris, 0xff4b7169)
        stroke(c, spokes, 0xff507b70, .75f)
        ink(0xff718675, 1.6f)
        c.drawCircle(0f, 75f, pupilRadius + 1.2f, paint)
        if (narrowing > 0f) {
            ink(motor, 1.6f)
            paint.alpha = (235f * narrowing).toInt()
            c.drawCircle(0f, 75f, pupilRadius + 1.2f, paint)
        }
        disc(c, 0f, 75f, pupilRadius, 0xff243b42)
        disc(c, -3.5f, 71f, 1.6f, 0xfff4f2e6)
        c.restore()
        stroke(c, lid, eyeBorder, 1.4f)
        oval(c, 37f, 74f, 46f, 81f, 0xffdca7a0, 0xffb68883)
        c.restore()
    }

    private fun traceIris(pupilRadius: Float) {
        spokes.rewind()
        for (i in 0 until 40) {
            val phase = (i * (PI * 2 / 40)).toFloat()
            val cosA = cos(phase)
            val sinA = sin(phase)
            val inner = pupilRadius + if (i % 3 == 0) 3.2f else 2f
            val outer = if (i % 2 == 0) 20.1f else 18.3f
            spokes.moveTo(cosA * inner, 75f + sinA * inner)
            spokes.quadTo(cosA * 17f - sinA, 75f + sinA * 17f + cosA,
                cosA * outer, 75f + sinA * outer)
        }
    }

    private fun drawMidbrain(c: Canvas) {
        ink(cream)
        paint.shader = brain
        c.drawPath(midbrain, paint)
        paint.shader = null
        stroke(c, midbrain, midbrainBorder, 1.4f)
        stroke(c, midbrainFolds, 0xffc595a7, 1.3f)
        oval(c, 137f, 283f, 170f, 308f, 0xffe6b4c4, 0xffcb9aaa)
        oval(c, 190f, 283f, 223f, 308f, 0xffe6b4c4, 0xffcb9aaa)
        disc(c, 180f, 290f, 6.4f, 0xffd6a5b8)
        disc(c, 180f, 290f, 2.7f, cream, midbrainBorder)
    }

    private fun drawRoutes(c: Canvas, step: Int, t: Float) {
        for (side in routes) {
            stroke(c, side.nerve, sensoryRest, 2.8f)
            stroke(c, side.stay, sensoryRest, 2.1f)
            stroke(c, side.cross, sensoryRest, 2.1f)
            stroke(c, side.localRelay, relayRest, 1.8f)
            stroke(c, side.crossRelay, relayRest, 1.8f)
            stroke(c, side.returnNerve, motorRest, 2.8f)
            stroke(c, side.toIris, motorRest, 1.9f)
        }
        for (side in routes) {
            val pretectal = when (step) {
                1 -> ease(t, .66f, .94f)
                2 -> 1f - .48f * ease(t, .12f, .68f)
                else -> 0f
            }
            val pupilDrive = when (step) {
                2 -> ease(t, .44f, .88f)
                3 -> 1f - .65f * ease(t, 0f, .44f)
                else -> 0f
            }
            val ganglionDrive = if (step == 3) {
                ease(t, .46f, .59f) * (1f - .8f * ease(t, .68f, .96f))
            } else 0f
            node(c, side.x(154f), 239f, pretectal, sensory)
            node(c, side.x(148f), 277f, pupilDrive, relay)
            node(c, side.x(49f), 153f, ganglionDrive, motor)
        }
        when (step) {
            1 -> with(routes[0]) {
                signal(c, nerveTrack, t / .49f, sensory)
                val branch = (t - .42f) / .53f
                signal(c, stayTrack, branch, sensory)
                signal(c, crossTrack, branch, sensory)
            }
            2 -> for (side in routes) {
                val travel = (t - .10f) / .77f
                signal(c, side.localRelayTrack, travel, relay)
                signal(c, side.crossRelayTrack, travel, relay)
            }
            3 -> for (side in routes) {
                signal(c, side.returnTrack, (t - .04f) / .54f, motor)
                signal(c, side.irisTrack, (t - .58f) / .36f, motor)
            }
        }
    }

    private fun node(c: Canvas, x: Float, y: Float, activity: Float, color: Long) {
        if (activity > 0f) {
            ink(color, 1.15f)
            paint.alpha = (110f * activity).toInt()
            c.drawCircle(x, y, 6f + 4f * activity, paint)
        }
        disc(c, x, y, 3.6f, if (activity > .3f) color else cream, color)
        if (activity > .3f) disc(c, x, y, 1.35f, cream)
    }

    private fun signal(c: Canvas, path: PathMeasure, t: Float, color: Long) {
        if (t !in 0f..1f) return
        trail.rewind()
        if (path.getSegment((t - .25f).coerceAtLeast(0f) * path.length, t * path.length, trail, true)) {
            stroke(c, trail, color, 3.1f)
        }
        at(path, t) { x, y -> disc(c, x, y, 3.1f, cream, color) }
    }

    private fun drawLight(c: Canvas, step: Int, t: Float) {
        val staticRay = 0xffccaa71
        stroke(c, lightGuide, staticRay, 1.15f)
        line(c, 49f, 52f, 74f, 67f, staticRay, 1.2f)
        line(c, 66f, 40f, 82f, 54f, staticRay, 1.2f)
        if (step != 0) return
        stroke(c, lightThrough, 0xffd7b789, 1.1f)
        signal(c, lightTrack, t / .50f, light)
        signal(c, lightThroughTrack, (t - .48f) / .31f, light)
        val glow = sin(PI * ease(t, .58f, 1f)).toFloat()
        if (glow > 0f) {
            ink(light, 2f)
            paint.alpha = (205f * glow).toInt()
            c.drawPath(retinaOnLitSide, paint)
        }
    }

    private fun drawLabels(c: Canvas, step: Int) {
        callout(c, R.string.health_atlas_cranial_reflex_story_iris, 180f, 89f, 94f, 135f, 84f, 104f, 81f)
        callout(c, R.string.health_atlas_cranial_reflex_story_retina, 157f, 118f, 64f, 133f, 114f, 106f, 114f)
        callout(c, R.string.health_atlas_cranial_reflex_story_optic, 180f, 154f, 112f, 130f, 150f, 114f, 151f)
        callout(c, R.string.health_atlas_cranial_reflex_story_chiasm, 180f, 172f, 87f, 180f, 178f, 180f, 199f)
        callout(c, R.string.health_atlas_cranial_reflex_story_ganglion, 253f, 190f, 107f, 298f, 183f, 311f, 153f)
        callout(c, R.string.health_atlas_cranial_reflex_story_pretectum, 106f, 219f, 93f, 121f, 223f, 148f, 239f)
        callout(c, R.string.health_atlas_cranial_reflex_story_ew, 66f, 291f, 118f, 120f, 283f, 143f, 277f)
        callout(c, R.string.health_atlas_cranial_reflex_story_motor, 298f, 274f, 111f, 281f, 259f, 284f, 234f)
        callout(c, R.string.health_atlas_cranial_reflex_story_midbrain, 180f, 340f, 105f, 180f, 325f, 180f, 307f)
        if (step == 4) {
            callout(c, R.string.health_atlas_cranial_reflex_story_direct, 109f, 34f, 124f, 108f, 39f, 108f, 53f)
            callout(c, R.string.health_atlas_cranial_reflex_story_consensual, 260f, 34f, 144f, 260f, 39f, 260f, 53f)
        }
    }

    private fun callout(c: Canvas, @StringRes id: Int, x: Float, baseline: Float, width: Float,
        startX: Float, startY: Float, targetX: Float, targetY: Float) {
        line(c, startX, startY, targetX, targetY, guide, .95f)
        disc(c, targetX, targetY, 1.45f, guide)
        label(c, id, x, baseline, width)
    }

    private fun ease(t: Float, start: Float, end: Float): Float {
        val p = ((t - start) / (end - start)).coerceIn(0f, 1f)
        return p * p * (3f - 2f * p)
    }

    // Both halves share geometry; crossed routes end on the opposite half of the plate.
    private class SideRoutes(private val direction: Float) {
        fun x(value: Float) = if (direction > 0f) value else 360f - value

        val nerve = Path().apply {
            moveTo(x(90f), 122f)
            cubicTo(x(95f), 147f, x(130f), 159f, x(156f), 184f)
        }
        val stay = Path().apply {
            moveTo(x(156f), 184f)
            cubicTo(x(166f), 195f, x(148f), 215f, x(154f), 239f)
        }
        val cross = Path().apply {
            moveTo(x(156f), 184f)
            cubicTo(x(170f), 194f, x(196f), 206f, x(206f), 239f)
        }
        val localRelay = Path().apply {
            moveTo(x(154f), 239f); quadTo(x(143f), 257f, x(148f), 277f)
        }
        val crossRelay = Path().apply {
            moveTo(x(154f), 239f); cubicTo(x(160f), 253f, x(200f), 261f, x(212f), 277f)
        }
        val returnNerve = Path().apply {
            moveTo(x(148f), 277f)
            cubicTo(x(119f), 273f, x(89f), 260f, x(76f), 234f)
            cubicTo(x(63f), 211f, x(60f), 179f, x(49f), 153f)
        }
        val toIris = Path().apply {
            moveTo(x(49f), 153f)
            cubicTo(x(42f), 127f, x(51f), 103f, x(72f), 87f)
        }
        val nerveTrack = PathMeasure(nerve, false)
        val stayTrack = PathMeasure(stay, false)
        val crossTrack = PathMeasure(cross, false)
        val localRelayTrack = PathMeasure(localRelay, false)
        val crossRelayTrack = PathMeasure(crossRelay, false)
        val returnTrack = PathMeasure(returnNerve, false)
        val irisTrack = PathMeasure(toIris, false)
    }
}
