package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader
import androidx.annotation.StringRes
import kotlin.math.PI
import kotlin.math.sin

internal class HealthAtlasBrainstemRhythmStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.BRAINSTEM_RHYTHM) {
    private val guide = 0xff657482
    private val neural = 0xff69518e
    private val quietNeural = 0xffad98bb
    private val movingAir = 0xff356e8e
    private val muscle = 0xffab5661
    private val bodyFill = shade(26f, 313f, 0xfff9e9d9, 0xfff2d8d0)
    private val brainFill = shade(41f, 99f, 0xfff8cadb, 0xffe5aabf)
    private val lungFill = shade(168f, 290f, 0xffffe1d8, 0xffe9b0b2)
    private val body = Path().apply {
        moveTo(151f, 35f)
        cubicTo(172f, 17f, 219f, 22f, 230f, 56f)
        cubicTo(242f, 89f, 218f, 108f, 224f, 128f)
        quadTo(226f, 142f, 245f, 151f)
        cubicTo(268f, 161f, 269f, 208f, 260f, 248f)
        quadTo(250f, 277f, 249f, 307f)
        quadTo(182f, 324f, 113f, 307f)
        quadTo(112f, 278f, 103f, 248f)
        cubicTo(93f, 205f, 97f, 165f, 127f, 152f)
        quadTo(151f, 141f, 153f, 120f)
        quadTo(154f, 116f, 147f, 115f)
        quadTo(137f, 113f, 138f, 103f)
        lineTo(135f, 94f)
        quadTo(125f, 94f, 128f, 86f)
        lineTo(137f, 73f)
        quadTo(138f, 47f, 151f, 35f)
        close()
    }
    private val brain = Path().apply {
        moveTo(149f, 63f)
        cubicTo(151f, 44f, 172f, 34f, 188f, 37f)
        cubicTo(207f, 35f, 223f, 48f, 222f, 68f)
        cubicTo(223f, 82f, 210f, 88f, 196f, 86f)
        cubicTo(179f, 92f, 158f, 86f, 150f, 77f)
        quadTo(145f, 72f, 149f, 63f)
        close()
    }
    private val folds = Path().apply {
        moveTo(157f, 59f); cubicTo(165f, 62f, 173f, 49f, 183f, 51f)
        moveTo(154f, 72f); cubicTo(166f, 75f, 170f, 61f, 182f, 66f)
        moveTo(174f, 79f); cubicTo(181f, 73f, 195f, 79f, 201f, 69f)
        moveTo(190f, 45f); cubicTo(187f, 54f, 207f, 52f, 213f, 60f)
        moveTo(190f, 62f); quadTo(197f, 57f, 201f, 62f)
        moveTo(204f, 77f); quadTo(212f, 75f, 215f, 69f)
    }
    private val stem = Path().apply {
        moveTo(175f, 80f)
        quadTo(182f, 79f, 196f, 81f)
        quadTo(200f, 87f, 198f, 95f)
        lineTo(200f, 119f)
        quadTo(197f, 122f, 191f, 119f)
        quadTo(191f, 104f, 182f, 98f)
        quadTo(175f, 94f, 178f, 88f)
        close()
    }
    private val cord = Path().apply {
        moveTo(196f, 116f); cubicTo(196f, 131f, 198f, 150f, 198f, 174f)
    }
    private val descending = Path().apply {
        moveTo(191f, 101f); cubicTo(196f, 111f, 196f, 131f, 197f, 145f)
    }
    private val leftNerve = Path().apply {
        moveTo(197f, 145f)
        cubicTo(181f, 145f, 157f, 150f, 151f, 173f)
        cubicTo(144f, 202f, 138f, 253f, 129f, 285f)
    }
    private val rightNerve = Path().apply {
        moveTo(197f, 145f)
        cubicTo(208f, 144f, 214f, 154f, 217f, 175f)
        cubicTo(221f, 202f, 224f, 255f, 233f, 285f)
    }
    private val airway = Path().apply {
        moveTo(138f, 95f); traceAirway()
    }
    private val airRoute = Path().apply {
        moveTo(112f, 95f); lineTo(138f, 95f); traceAirway()
    }
    private val bronchi = Path().apply {
        moveTo(151f, 213f); quadTo(157f, 200f, 175f, 190f)
        quadTo(192f, 196f, 210f, 211f)
    }
    private val cordTrack = track(descending)
    private val leftTrack = track(leftNerve)
    private val rightTrack = track(rightNerve)
    private val airTrack = track(airRoute)
    private val trail = Path()
    private val lung = Path()
    private val diaphragm = Path()
    private val ribs = Path()
    private val network = floatArrayOf(272f, 73f, 294f, 69f, 306f, 87f, 287f, 98f, 267f, 93f)
    private val connections = intArrayOf(0, 1, 1, 2, 2, 3, 3, 4, 4, 0, 0, 3, 1, 3)

    init { tag = "atlas-function-brainstem-rhythm-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val expiration = t / .79f
        val expansion = when (step) {
            3 -> ease(t)
            4 -> 1f - ease(expiration)
            else -> 0f
        }
        shaded(c, body, bodyFill, 0xffc69b94)
        drawHead(c)
        drawChest(c, expansion, contracting = step == 3)
        drawAirway(c)
        drawMotorPath(c, step, t)
        if (step == 3) airflow(c, t, inward = true)
        if (step == 4 && expiration < 1f) airflow(c, expiration, inward = false)
        if (step == 0) {
            val pulse = envelope(t)
            ink(0xff8b70a3, 1.5f)
            paint.alpha = (220f * pulse).toInt()
            c.drawCircle(191f, 101f, 9f + 7f * t, paint)
        }
        val burst = when (step) {
            1 -> envelope(t * 2f % 1f)
            2 -> envelope(t / .26f)
            4 -> envelope((t - .81f) / .19f)
            else -> 0f
        }
        drawNetwork(c, burst)
        drawLabels(c, expansion)
    }

    private fun Path.traceAirway() {
        cubicTo(156f, 94f, 170f, 99f, 172f, 115f)
        quadTo(175f, 139f, 175f, 191f)
    }

    private fun drawHead(c: Canvas) {
        oval(c, 195f, 77f, 220f, 100f, 0xffe4afbd, 0xffb47c93)
        for (y in 84..96 step 4) line(c, 202f, y.toFloat(), 215f, y - 2f, 0xffba8197, 1f)
        shaded(c, brain, brainFill, 0xffb47c93)
        stroke(c, folds, 0xffc187a1, 1.2f)
        solid(c, stem, 0xffcdb7df, neural)
        line(c, 138f, 99f, 146f, 99f, 0xffaf817c, 1.1f)
    }

    private fun drawChest(c: Canvas, expansion: Float, contracting: Boolean) {
        for (side in 0..1) {
            c.save()
            c.translate(181f, 0f)
            c.scale(if (side == 0) -1f else 1f, 1f)
            ribs.rewind()
            for (i in 0..4) {
                val y = 175f + i * 21f
                ribs.moveTo(6f, y)
                ribs.cubicTo(31f, y - 12f, 63f, y - 7f, 68f, y + 13f)
            }
            stroke(c, ribs, 0xffe2b6a9, 2f)
            val outer = 56f + 5f * expansion
            val base = (if (side == 0) 265f else 271f) + 16f * expansion
            val notch = if (side == 0) 0f else 9f
            lung.rewind()
            lung.moveTo(25f, 166f)
            lung.cubicTo(40f, 171f, outer, 199f, outer, 232f)
            lung.quadTo(outer + 2f, 261f, 53f, 284f)
            lung.cubicTo(39f, base, 24f, base - 7f, 10f, base + 7f)
            lung.cubicTo(3f, base - 2f, 7f + notch, 235f, 9f + notch, 218f)
            lung.cubicTo(7f, 197f, 10f, 170f, 25f, 166f)
            lung.close()
            shaded(c, lung, lungFill, 0xffb77887)
            c.clipPath(lung)
            ribs.rewind()
            ribs.moveTo(5f, 214f); ribs.quadTo(35f, 222f, 63f, 241f)
            if (side == 0) {
                ribs.moveTo(22f, 226f); ribs.quadTo(45f, 220f, 61f, 213f)
            }
            stroke(c, ribs, 0xffce939d, 1.2f)
            c.restore()
        }
        // The costal edges stay put as the two domes descend and flatten.
        diaphragm.rewind()
        diaphragm.moveTo(128f, 288f)
        diaphragm.cubicTo(146f, 256f + 22f * expansion, 162f, 252f + 27f * expansion,
            181f, diaphragmCenter(expansion))
        diaphragm.cubicTo(201f, 258f + 21f * expansion, 218f, 260f + 20f * expansion, 234f, 288f)
        stroke(c, diaphragm, muscle, if (contracting) 8f else 7f)
        stroke(c, diaphragm, if (contracting) 0xffefac9a else 0xffedc0ae, 4.3f)
    }

    private fun drawAirway(c: Canvas) {
        stroke(c, bronchi, 0xffb48676, 8f)
        stroke(c, bronchi, 0xfff1d3b3, 5.5f)
        stroke(c, airway, 0xffb48676, 9f)
        stroke(c, airway, 0xfff5dcc0, 6.6f)
        for (y in 144..184 step 7) line(c, 172f, y.toFloat(), 178f, y.toFloat(), 0xffc39783, 1f)
    }

    private fun drawMotorPath(c: Canvas, step: Int, t: Float) {
        stroke(c, cord, 0xffa78db5, 8.5f)
        stroke(c, cord, 0xffe0c7e4, 6f)
        stroke(c, leftNerve, quietNeural, 2.2f)
        stroke(c, rightNerve, quietNeural, 2.2f)
        disc(c, 197f, 145f, 3.1f, cream, quietNeural)
        if (step == 2) {
            val travel = t / .91f
            if (travel <= .29f) {
                signal(c, cordTrack, travel / .29f)
            } else {
                val branch = (travel - .29f) / .71f
                signal(c, leftTrack, branch)
                signal(c, rightTrack, branch)
            }
        }
    }

    private fun signal(c: Canvas, track: PathMeasure, progress: Float) {
        trail.rewind()
        val end = progress.coerceIn(0f, 1f)
        if (track.getSegment((end - .23f).coerceAtLeast(0f) * track.length, end * track.length, trail, true)) {
            stroke(c, trail, neural, 3.3f)
        }
        at(track, end) { x, y -> disc(c, x, y, 4f, cream, neural) }
    }

    private fun airflow(c: Canvas, t: Float, inward: Boolean) {
        val direction = if (inward) 1f else -1f
        for (i in 0..2) {
            val travel = 1.44f * t - .19f * i
            if (travel !in .08f..1f) continue
            val head = if (inward) travel else 1f - travel
            at(airTrack, head - .077f * direction) { x1, y1 ->
                at(airTrack, head) { x2, y2 -> arrow(c, x1, y1, x2, y2, movingAir) }
            }
        }
    }

    private fun drawNetwork(c: Canvas, burst: Float) {
        line(c, 194f, 103f, 251f, 89f, guide, 1f)
        disc(c, 191f, 101f, 3.5f, 0xffe9d8f1, neural)
        oval(c, 250f, 52f, 323f, 114f, 0xffeee4f2, 0xffb7a2c5)
        for (i in connections.indices step 2) {
            val a = connections[i] * 2
            val b = connections[i + 1] * 2
            line(c, network[a], network[a + 1], network[b], network[b + 1], quietNeural, 1f + burst)
        }
        for (i in network.indices step 2) {
            disc(c, network[i], network[i + 1], 3.4f + 2.8f * burst, 0xffd2bae0, neural)
            if (burst > .25f) disc(c, network[i], network[i + 1], 1.7f + burst, neural)
        }
    }

    private fun drawLabels(c: Canvas, expansion: Float) {
        callout(c, R.string.health_atlas_brainstem_story_stem, 61f, 58f, 111f, 103f, 184f, 91f)
        label(c, R.string.health_atlas_brainstem_story_network, 286f, 41f, 130f)
        callout(c, R.string.health_atlas_brainstem_story_cord, 282f, 143f, 141f, 220f, 196f, 128f)
        callout(c, R.string.health_atlas_brainstem_story_phrenic, 61f, 199f, 111f, 111f, 145f, 196f)
        callout(c, R.string.health_atlas_brainstem_story_lungs, 299f, 218f, 79f, 269f, 230f, 224f)
        val dome = diaphragmCenter(expansion)
        line(c, 181f, 315f, 181f, dome + 4f, guide, 1f)
        disc(c, 181f, dome + 4f, 1.6f, guide)
        label(c, R.string.health_atlas_brainstem_story_diaphragm, 181f, 332f, 133f)
    }

    private fun callout(c: Canvas, @StringRes id: Int, x: Float, y: Float, width: Float,
        railX: Float, targetX: Float, targetY: Float) {
        line(c, railX, y + 5f, targetX, targetY, guide, 1f)
        disc(c, targetX, targetY, 1.6f, guide)
        label(c, id, x, y, width)
    }

    private fun shaded(c: Canvas, path: Path, fill: Shader, border: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, border, 1.3f)
    }

    private fun solid(c: Canvas, path: Path, fill: Long, border: Long) {
        ink(fill)
        c.drawPath(path, paint)
        stroke(c, path, border, 1.3f)
    }

    private fun diaphragmCenter(expansion: Float) = 276f + 10f * expansion

    private fun ease(progress: Float): Float {
        val t = progress.coerceIn(0f, 1f)
        return t * t * (3f - 2f * t)
    }

    private fun envelope(progress: Float) = if (progress in 0f..1f) sin(PI * progress).toFloat() else 0f
}
