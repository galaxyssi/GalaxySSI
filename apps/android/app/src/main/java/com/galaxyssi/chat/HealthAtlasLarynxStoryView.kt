package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos

internal class HealthAtlasLarynxStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.LARYNGEAL_VOICE) {
    private val rimFill = shade(48f, 199f, 0xfff7d9c7, 0xffdca0a5)
    private val lumenFill = shade(65f, 192f, 0xff74898e, 0xff4b666f)
    private val foldFill = shade(84f, 176f, 0xfffff8e8, 0xffecd2bf)
    private val wallFill = shade(245f, 340f, 0xfff1c7c4, 0xffe8d0b7)
    private val foldSection = shade(263f, 289f, 0xfffff8e8, 0xffe9cbb7)
    private val wallEdge = 0xff916872
    private val guide = 0xff537178
    private val flowColor = 0xff246e76
    private val pulseColor = 0xffa26032
    private val detail = Path()
    private val fold = Path()

    private val outline = Path().apply {
        moveTo(180f, 49f)
        cubicTo(143f, 44f, 112f, 62f, 103f, 94f)
        cubicTo(86f, 132f, 100f, 171f, 129f, 189f)
        cubicTo(149f, 203f, 170f, 196f, 180f, 191f)
        cubicTo(190f, 196f, 211f, 203f, 231f, 189f)
        cubicTo(260f, 171f, 274f, 132f, 257f, 94f)
        cubicTo(248f, 62f, 217f, 44f, 180f, 49f)
        close()
    }
    private val vestibule = Path().apply {
        moveTo(180f, 72f)
        cubicTo(148f, 66f, 122f, 83f, 115f, 115f)
        cubicTo(105f, 142f, 121f, 169f, 145f, 179f)
        cubicTo(159f, 186f, 172f, 182f, 180f, 180f)
        cubicTo(188f, 182f, 201f, 186f, 215f, 179f)
        cubicTo(239f, 169f, 255f, 142f, 245f, 115f)
        cubicTo(238f, 83f, 212f, 66f, 180f, 72f)
        close()
    }
    private val anteriorRim = Path().apply {
        moveTo(134f, 69f)
        cubicTo(154f, 48f, 206f, 48f, 226f, 69f)
        cubicTo(213f, 66f, 196f, 73f, 180f, 86f)
        cubicTo(164f, 73f, 147f, 66f, 134f, 69f)
        close()
    }
    private val airwayWall = Path().apply {
        moveTo(124f, 246f)
        cubicTo(122f, 261f, 131f, 279f, 141f, 294f)
        quadTo(148f, 306f, 146f, 339f)
        lineTo(158f, 339f)
        cubicTo(160f, 311f, 157f, 296f, 152f, 286f)
        cubicTo(146f, 271f, 139f, 262f, 141f, 246f)
        close()
    }

    init { tag = "atlas-function-laryngeal-voice-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val cycle = 3f * t
        val opening = .5f - .5f * cos(2.0 * PI * cycle).toFloat()
        val vibration = when (step) {
            2 -> ease(t)
            3 -> 1f
            4 -> 1f - ease(t * 2.5f)
            else -> 0f
        }
        val release = ease((t - .15f) / .75f)
        val posture = when (step) {
            0 -> 36f + 7f * wave(t)
            1 -> 36f - 32f * ease(t)
            4 -> 4f + 32f * release
            else -> 4f
        }
        val gap = posture + vibration * (11f * opening - 3f)
        superior(c, gap)
        frontal(c, gap)

        val outgoing = when (step) {
            2 -> ease(t * 3f)
            3 -> 1f
            4 -> vibration
            else -> 0f
        }
        if (outgoing > 0f) {
            airwayFlow(c, 2f * t, up = true, below = outgoing,
                above = outgoing * (.15f + .85f * opening) * (gap / 8f).coerceAtMost(1f))
        }
        if (step == 0 || step == 4) {
            val breath = if (step == 0) wave(t) else {
                ease((t - .4f) / .32f) * (1f - ease((t - .75f) / .25f)) * .75f
            }
            airwayFlow(c, 3f * t, up = breath < 0f, below = abs(breath), above = abs(breath))
        }
        val sound = when (step) {
            3 -> ease(t * 6f)
            4 -> vibration
            else -> 0f
        }
        if (sound > 0f) acousticPulses(c, cycle, sound)
    }

    private fun superior(c: Canvas, gap: Float) {
        label(c, R.string.health_atlas_larynx_story_superior, 180f, 28f, 154f)
        shape(c, outline, rimFill, wallEdge)
        shape(c, vestibule, lumenFill, 0xffa1747c)
        ink(0xfff9d8c4)
        c.drawPath(anteriorRim, paint)
        stroke(c, anteriorRim, 0xffbd8790, 1.2f)

        // The folds share a fixed anterior attachment; their posterior edges move apart.
        fold.rewind()
        fold.moveTo(180f, 86f)
        fold.cubicTo(177f - .15f * gap, 112f, 178f - .55f * gap, 146f, 180f - gap, 173f)
        fold.cubicTo(153f - .68f * gap, 175f, 123f, 158f, 119f, 132f)
        fold.cubicTo(116f, 113f, 144f, 93f, 180f, 86f)
        fold.close()
        detail.rewind()
        detail.moveTo(128f, 133f)
        detail.quadTo(131f, 115f, 156f - .10f * gap, 101f)
        for (side in 0..1) {
            c.save()
            if (side == 1) c.scale(-1f, 1f, 180f, 0f)
            shape(c, fold, foldFill, 0xff997580)
            stroke(c, detail, 0xfffff9ee, 2f)
            c.restore()
        }

        leader(c, 67f, 75f, 92f, 75f, 115f, 78f)
        label(c, R.string.health_atlas_larynx_story_larynx, 42f, 79f, 48f)
        leader(c, 72f, 133f, 95f, 133f, 134f, 124f)
        label(c, R.string.health_atlas_larynx_story_folds, 43f, 137f, 57f)
        line(c, 180f, 199f, 180f, 158f, guide, 1.05f)
        disc(c, 180f, 158f, 2f, 0xffedf5ed, guide)
        label(c, R.string.health_atlas_larynx_story_glottis, 180f, 214f, 112f)
    }

    private fun frontal(c: Canvas, gap: Float) {
        line(c, 24f, 225f, 336f, 225f, 0xffc1ceca, 1f)
        label(c, R.string.health_atlas_larynx_story_cutaway, 180f, 241f, 153f)
        detail.rewind()
        detail.moveTo(141f, 246f)
        detail.cubicTo(139f, 262f, 146f, 271f, 152f, 286f)
        detail.cubicTo(157f, 296f, 160f, 311f, 158f, 339f)
        detail.lineTo(202f, 339f)
        detail.cubicTo(200f, 311f, 203f, 296f, 208f, 286f)
        detail.cubicTo(214f, 271f, 221f, 262f, 219f, 246f)
        detail.close()
        ink(0xffdbeeea)
        c.drawPath(detail, paint)

        val lip = 180f - gap * .55f
        fold.rewind()
        fold.moveTo(142f, 263f)
        fold.cubicTo(155f, 263f, lip - 2f, 270f, lip, 278f)
        fold.cubicTo(lip - 2f, 286f, 160f, 288f, 150f, 289f)
        fold.close()
        for (side in 0..1) {
            c.save()
            if (side == 1) c.scale(-1f, 1f, 180f, 0f)
            shape(c, airwayWall, wallFill, wallEdge)
            shape(c, fold, foldSection, wallEdge)
            for (y in 305..333 step 7) {
                line(c, 146.5f, y.toFloat(), 157f, y + 1f, 0xffb78979, 1.15f)
            }
            c.restore()
        }

        line(c, 47f, 270f, 65f, 270f, flowColor, 2f)
        label(c, R.string.health_atlas_larynx_story_airflow, 56f, 287f, 96f)
        line(c, 283f, 270f, 301f, 270f, pulseColor, 2f)
        label(c, R.string.health_atlas_larynx_story_sound, 292f, 287f, 118f)
        leader(c, 86f, 326f, 112f, 326f, 150f, 319f)
        label(c, R.string.health_atlas_larynx_story_trachea, 55f, 330f, 61f)
    }

    private fun airwayFlow(c: Canvas, travel: Float, up: Boolean, below: Float, above: Float) {
        val direction = if (up) -1f else 1f
        for (i in 0..4) {
            val p = unit(travel + i / 5f)
            val y = if (up) 337f - 88f * p else 249f + 88f * p
            val strength = if (y > 278f) below else above
            val fade = minOf(p * 9f, (1f - p) * 9f, abs(y - 278f) / 9f, 1f)
            val opacity = strength * fade
            if (opacity <= 0f) continue
            val x = 180f + (i % 3 - 1) * minOf(5f, abs(y - 278f) * .24f)
            val color = faded(flowColor, opacity)
            line(c, x, y - direction * 4f, x, y + direction * 3f, color, 1.7f)
            line(c, x - 2.8f, y, x, y + direction * 3f, color, 1.4f)
            line(c, x + 2.8f, y, x, y + direction * 3f, color, 1.4f)
        }
    }

    private fun acousticPulses(c: Canvas, cycle: Float, strength: Float) {
        // One new front per illustrated fold cycle, launched during the opening phase.
        for (i in 0..1) {
            val age = (unit(cycle - .25f) + i) / 2f
            val y = 270f - 21f * age
            val halfWidth = 4f + 24f * age
            detail.rewind()
            detail.moveTo(180f - halfWidth, y + 2f)
            detail.quadTo(180f, y - 4f, 180f + halfWidth, y + 2f)
            val fade = minOf(age * 8f, (1f - age) * 5f, 1f)
            stroke(c, detail, faded(pulseColor, strength * fade), 1.8f)
        }
    }

    private fun shape(c: Canvas, path: Path, fill: Shader, edge: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, edge, 1.35f)
    }

    private fun leader(c: Canvas, x: Float, y: Float, bendX: Float, bendY: Float, toX: Float, toY: Float) {
        line(c, x, y, bendX, bendY, guide, 1.05f)
        line(c, bendX, bendY, toX, toY, guide, 1.05f)
        disc(c, toX, toY, 1.6f, guide)
    }

    private fun ease(t: Float): Float {
        val p = t.coerceIn(0f, 1f)
        return p * p * (3f - 2f * p)
    }

    private fun unit(t: Float) = (t % 1f + 1f) % 1f

    private fun faded(color: Long, opacity: Float) =
        (color and 0x00ffffffL) or ((255f * opacity.coerceIn(0f, 1f)).toLong() shl 24)
}
