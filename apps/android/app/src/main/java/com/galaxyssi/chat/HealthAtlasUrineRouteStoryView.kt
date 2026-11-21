package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import kotlin.math.abs
import kotlin.math.roundToInt

internal class HealthAtlasUrineRouteStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.URINE_ROUTE) {
    private val shape = Path()
    private val lumen = Path()
    private val trace = Path()
    private val kidneyTone = shade(54f, 163f, 0xfff8d2cb, 0xffd58c9e)
    private val wallTone = shade(70f, 265f, 0xfff8ddd4, 0xffdea1a9)
    private val urineTone = shade(105f, 262f, 0xffffe7a7, 0xffe7b568)

    private val kidney = Path().apply {
        moveTo(139f, 81f)
        cubicTo(130f, 46f, 91f, 44f, 77f, 73f)
        cubicTo(61f, 102f, 61f, 144f, 84f, 160f)
        cubicTo(106f, 176f, 141f, 151f, 139f, 129f)
        cubicTo(138f, 118f, 121f, 122f, 126f, 108f)
        cubicTo(129f, 99f, 144f, 101f, 139f, 81f)
        close()
    }
    private val medulla = Path().apply {
        moveTo(121f, 80f)
        cubicTo(103f, 56f, 78f, 80f, 78f, 113f)
        cubicTo(71f, 152f, 99f, 160f, 119f, 138f)
        cubicTo(130f, 128f, 109f, 125f, 115f, 108f)
        cubicTo(119f, 98f, 132f, 93f, 121f, 80f)
        close()
    }
    private val calyces = Path().apply {
        moveTo(101f, 90f); quadTo(111f, 103f, 128f, 110f)
        moveTo(95f, 113f); quadTo(110f, 109f, 128f, 110f)
        moveTo(101f, 137f); quadTo(114f, 132f, 128f, 110f)
    }
    private val overviewUreter = Path().apply {
        moveTo(127f, 110f)
        arcFromPelvis()
    }
    private val pelvisRoute = track(Path().apply {
        moveTo(101f, 90f); quadTo(111f, 103f, 127f, 110f)
        arcFromPelvis()
    })
    private val ureter = Channel(Path().apply {
        moveTo(42f, 100f); cubicTo(145f, 94f, 152f, 234f, 316f, 256f)
    })
    private val tunnel = Channel(Path().apply {
        moveTo(42f, 74f); cubicTo(107f, 93f, 120f, 151f, 260f, 231f)
    })
    private val junctionWall = Path().apply {
        moveTo(20f, 104f); cubicTo(126f, 110f, 211f, 126f, 340f, 145f)
        lineTo(340f, 245f); cubicTo(211f, 225f, 121f, 197f, 20f, 196f)
        close()
    }
    private val junctionExit = track(Path().apply {
        moveTo(260f, 231f); quadTo(268f, 242f, 287f, 257f)
    })
    private val inlet = Path().apply {
        moveTo(49f, 169f); cubicTo(52f, 199f, 94f, 199f, 118f, 215f)
    }
    private val inletTrack = track(inlet)
    private val outlet = Channel(Path().apply { moveTo(180f, 252f); lineTo(180f, 324f) })

    init { tag = "atlas-function-urine-route-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> overview(c, t)
            1 -> peristalsis(c, t)
            2 -> junction(c, t)
            3, 4 -> reservoir(c, t, emptying = step == 4)
        }
    }

    private fun overview(c: Canvas, t: Float) {
        line(c, 180f, 281f, 180f, 321f, coral, 12f)
        line(c, 180f, 281f, 180f, 321f, peach, 9f)
        line(c, 180f, 285f, 180f, 321f, cream, 3f)
        bladderShape(shape, 52f, 219f, 291f, 6f)
        ink(peach); c.drawPath(shape, paint); stroke(c, shape, coral, 1.4f)
        bladderShape(shape, 45f, 226f, 287f, 2f)
        ink(0xffffe7b3); c.drawPath(shape, paint)
        for (side in 0..1) {
            c.save()
            if (side == 1) c.scale(-1f, 1f, 180f, 0f)
            ink(cream); paint.shader = kidneyTone; c.drawPath(kidney, paint); paint.shader = null
            stroke(c, kidney, coral, 1.5f)
            ink(0xfff2bab3); c.drawPath(medulla, paint); stroke(c, medulla, 0xffcb8992, 1f)
            stroke(c, overviewUreter, coral, 9f)
            stroke(c, overviewUreter, 0xfff6d3bf, 6.5f)
            stroke(c, calyces, 0xffb8847a, 6f)
            stroke(c, calyces, 0xffffedc4, 4f)
            oval(c, 121f, 103f, 141f, 119f, 0xffffe4aa, 0xffb8847a)
            pulse(c, pelvisRoute, (t * 1.25f + side * .38f) % 1.15f, .12f, 3.7f)
            c.restore()
        }
        callout(c, R.string.health_atlas_urine_route_story_renal_pelvis, 180f, 33f, 130f, 138f, 108f)
        callout(c, R.string.health_atlas_urine_route_story_ureters, 76f, 195f, 95f, 139f, 203f)
        callout(c, R.string.health_atlas_urine_route_story_bladder, 278f, 236f, 95f, 224f, 248f)
        callout(c, R.string.health_atlas_urine_route_story_urethra, 257f, 299f, 95f, 184f, 311f)
    }

    private fun peristalsis(c: Canvas, t: Float) {
        val front = .23f + .73f * t
        val pinch = front - .16f
        passage(c, ureter) { f -> 11f + 5f * bump(f - front, .13f) - 8f * bump(f - pinch, .12f) }
        pulse(c, ureter.route, front + .05f, .10f, 13f)
        val i = (pinch * SAMPLES).roundToInt()
        val x = ureter.x[i]; val y = ureter.y[i]
        val nx = ureter.nx[i]; val ny = ureter.ny[i]
        for (side in -1..1 step 2) {
            arrow(c, x + side * nx * 34f, y + side * ny * 34f,
                x + side * nx * 16f, y + side * ny * 16f, violet)
        }
        callout(c, R.string.health_atlas_urine_route_story_ureter, 56f, 42f, 96f, 43f, 94f)
        label(c, R.string.health_atlas_urine_route_story_contraction, 239f, 55f, 168f)
        line(c, 151f, 50f, 164f, 50f, violet, 2.4f)
        arrow(c, 126f, 299f, 233f, 299f, teal)
        label(c, R.string.health_atlas_urine_route_story_to_bladder, 180f, 322f, 180f)
    }

    private fun junction(c: Canvas, t: Float) {
        rounded(c, 20f, 189f, 340f, 280f, 9f, 0xffdfece8)
        ink(peach); c.drawPath(junctionWall, paint); stroke(c, junctionWall, coral, 1.4f)
        for (y in 122..181 step 12) {
            trace.rewind(); trace.moveTo(24f, y.toFloat())
            trace.cubicTo(131f, y + 4f, 223f, y + 33f, 336f, y + 47f)
            stroke(c, trace, 0xffd99897, 1.2f)
        }
        val front = .10f + 1.06f * ease(t)
        passage(c, tunnel) { f ->
            8f - 6f * ease((f - .4f) / .55f) * (1f - bump(f - front + .06f, .19f))
        }
        pulse(c, tunnel.route, front, .11f, 7f)
        pulse(c, junctionExit, (front - 1f) * 5.4f, .35f, 5f)
        callout(c, R.string.health_atlas_urine_route_story_oblique_tunnel, 154f, 51f, 150f, 158f, 151f)
        callout(c, R.string.health_atlas_urine_route_story_bladder_wall, 279f, 101f, 139f, 300f, 182f)
        label(c, R.string.health_atlas_urine_route_story_bladder_interior, 180f, 306f, 195f)
    }

    private fun reservoir(c: Canvas, t: Float, emptying: Boolean) {
        val open = if (emptying) ease(t / .22f) * (1f - ease((t - .89f) / .11f)) else 0f
        val drain = if (emptying) ease((t - .14f) / .80f) else 0f
        val size = if (emptying) 1f - drain else ease(t)
        val half = 79f + 34f * size
        val dome = 134f - 62f * size
        val level = if (emptying) 111f + 149f * drain else 196f - 85f * size

        passage(c, outlet) { f ->
            val relaxed = 5f + 2f * open
            relaxed - (relaxed - .35f) * (1f - open) * bump(f - .43f, .32f)
        }
        bladderShape(shape, half, dome, 260f, 13f)
        ink(cream); paint.shader = wallTone; c.drawPath(shape, paint); paint.shader = null
        stroke(c, shape, coral, 1.6f)
        bladderShape(lumen, half - 11f, dome + 11f, 258f, 5f + 2f * open)
        ink(cream); c.drawPath(lumen, paint)
        c.save()
        c.clipPath(lumen)
        ink(cream); paint.shader = urineTone; c.drawRect(45f, level, 315f, 262f, paint); paint.shader = null
        line(c, 45f, level, 315f, level, 0xffca974b, 1.5f)
        c.restore()
        stroke(c, lumen, 0xffbd8186, 1.35f)
        // The paired inlets end at the lower sides; neither feeds the bladder dome.
        for (side in 0..1) {
            c.save()
            if (side == 1) c.scale(-1f, 1f, 180f, 0f)
            stroke(c, inlet, coral, 13f)
            stroke(c, inlet, 0xfff7d9c4, 10f)
            stroke(c, inlet, cream, 4f)
            if (!emptying) pulse(c, inletTrack, (t * 2.1f + side * .48f) % 1.2f, .2f, 4.2f)
            c.restore()
        }
        if (emptying && open > .8f && drain < 1f) {
            pulse(c, outlet.route, ((t - .14f) * 4f) % 1.23f, .28f, 6f * open, from = .13f)
        }
        callout(c, R.string.health_atlas_urine_route_story_bladder, 180f, 43f, 120f, 180f, dome + 5f)
        callout(c, R.string.health_atlas_urine_route_story_ureters, 37f, 144f, 60f, 50f, 169f)
        callout(c, R.string.health_atlas_urine_route_story_urethra, 271f, 306f, 99f, 187f, 320f)
        callout(c, R.string.health_atlas_urine_route_story_outlet, 75f, 269f, 136f, 169f, 283f)
    }

    private fun bladderShape(path: Path, half: Float, top: Float, base: Float, neck: Float) = with(path) {
        rewind()
        moveTo(180f - neck, base)
        cubicTo(164f, base - 21f, 180f - half, base - 16f, 180f - half, (top + base) / 2f)
        cubicTo(180f - half, top + 12f, 144f, top, 180f, top)
        cubicTo(216f, top, 180f + half, top + 12f, 180f + half, (top + base) / 2f)
        cubicTo(180f + half, base - 16f, 196f, base - 21f, 180f + neck, base)
    }

    private fun passage(c: Canvas, channel: Channel, radius: (Float) -> Float) {
        for (i in 0..SAMPLES) channel.radii[i] = radius(i.toFloat() / SAMPLES)
        ribbon(c, channel, 9f, 0xffe9b0ab, coral)
        ribbon(c, channel, 3.5f, 0xfff7d7c2, 0xffc68b87)
        ribbon(c, channel, 0f, cream, 0xffbc8680)
    }

    // Sample both walls along the same centerline so a moving pinch changes the actual lumen.
    private fun ribbon(c: Canvas, channel: Channel, margin: Float, color: Long, edge: Long) {
        shape.rewind()
        for (side in -1..1 step 2) {
            for (j in 0..SAMPLES) {
                val i = if (side < 0) j else SAMPLES - j
                val r = side * (channel.radii[i] + margin)
                val x = channel.x[i] + r * channel.nx[i]
                val y = channel.y[i] + r * channel.ny[i]
                if (side < 0 && j == 0) shape.moveTo(x, y) else shape.lineTo(x, y)
            }
        }
        shape.close()
        ink(color); c.drawPath(shape, paint); stroke(c, shape, edge, 1.2f)
    }

    private fun pulse(c: Canvas, route: PathMeasure, front: Float, length: Float, width: Float, from: Float = 0f) {
        trace.rewind()
        if (!route.getSegment(maxOf(from, front - length) * route.length,
                minOf(1f, front) * route.length, trace, true)) return
        stroke(c, trace, 0xffb37532, width)
        stroke(c, trace, 0xfff3c56c, width * .61f)
    }

    private fun callout(c: Canvas, res: Int, x: Float, y: Float, max: Float, toX: Float, toY: Float) {
        line(c, x, y + 5f, toX, toY, 0xff776c72, 1.15f)
        disc(c, toX, toY, 2f, violet, cream)
        label(c, res, x, y, max)
    }

    private class Channel(path: Path) {
        val route = PathMeasure(path, false)
        val x = FloatArray(SAMPLES + 1)
        val y = FloatArray(SAMPLES + 1)
        val nx = FloatArray(SAMPLES + 1)
        val ny = FloatArray(SAMPLES + 1)
        val radii = FloatArray(SAMPLES + 1)

        init {
            val point = FloatArray(2)
            val tangent = FloatArray(2)
            for (i in 0..SAMPLES) {
                route.getPosTan(route.length * i / SAMPLES, point, tangent)
                x[i] = point[0]; y[i] = point[1]
                nx[i] = -tangent[1]; ny[i] = tangent[0]
            }
        }
    }

    private companion object {
        const val SAMPLES = 64

        fun Path.arcFromPelvis() {
            cubicTo(156f, 113f, 139f, 142f, 137f, 169f)
            cubicTo(135f, 206f, 143f, 229f, 156f, 258f)
        }

        fun ease(t: Float): Float = t.coerceIn(0f, 1f).let { it * it * (3f - 2f * it) }
        fun bump(d: Float, span: Float) = ease(1f - abs(d) / span)
    }
}
