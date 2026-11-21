package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader
import androidx.annotation.StringRes
import kotlin.math.abs

internal class HealthAtlasTendonStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.TENDON_FORCE_TRANSFER) {
    private val muscleFill = shade(76f, 162f, 0xfff9d1cc, 0xffd88d99)
    private val tendonFill = shade(106f, 133f, 0xffe4f2e7, 0xffadd2c6)
    private val boneFill = shade(82f, 155f, 0xfffff5df, 0xffead3a8)
    private val boneInk = 0xff96754e
    private val leaderInk = 0xff65817b
    private val muscle = Path()
    private val tendon = Path()
    private val detail = Path()
    private val bone = Path().apply {
        moveTo(264f, 95f)
        cubicTo(278f, 79f, 294f, 81f, 305f, 97f)
        cubicTo(314f, 107f, 325f, 107f, 337f, 108f)
        lineTo(337f, 139f)
        cubicTo(324f, 139f, 317f, 137f, 307f, 142f)
        cubicTo(293f, 152f, 282f, 159f, 268f, 152f)
        cubicTo(250f, 144f, 248f, 112f, 264f, 95f)
        close()
    }
    private val corticalEdge = Path().apply {
        moveTo(275f, 99f)
        cubicTo(286f, 91f, 293f, 97f, 301f, 106f)
        cubicTo(310f, 115f, 323f, 115f, 330f, 115f)
        moveTo(272f, 143f)
        cubicTo(284f, 151f, 295f, 141f, 304f, 137f)
        cubicTo(313f, 131f, 322f, 132f, 330f, 132f)
    }

    init { tag = "atlas-function-tendon-force-transfer-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val eased = t * t * (3f - 2f * t)
        // Unitless drawing poses: loading overlaps force transfer, and unloading reverses the deformation.
        val load = when (step) {
            1 -> .28f * eased
            2 -> .28f + (.82f - .28f) * eased
            3 -> .82f + (1f - .82f) * eased
            4 -> 1f - eased
            else -> 0f
        }
        drawLinkage(c, load)
        val linkProgress = if (step == 0) 3f * t else 0f
        drawCallout(c, R.string.health_atlas_tendon_story_muscle, 80f, 87f, linkProgress, coral)
        drawCallout(c, R.string.health_atlas_tendon_story_tendon, 184f, 112f, linkProgress - 1f, teal)
        drawCallout(c, R.string.health_atlas_tendon_story_bone, 298f, 89f, linkProgress - 2f, boneInk)
        line(c, 184f, 132f, 184f, 189f, leaderInk, 1.25f)
        disc(c, 184f, 132f, 2.3f, teal, cream)
        drawBonePull(c, load, if (step == 3) t else 0f)
        drawCollagen(c, load)
    }

    private fun drawLinkage(c: Canvas, load: Float) {
        tissue(c, bone, boneFill, boneInk)
        stroke(c, corticalEdge, 0xffc7a679, 1.5f)

        // Keep the insertion fixed. As the muscle side pulls left, the tendon spans a longer distance.
        val join = 148f - 15f * load
        val narrow = 2f * load
        tendon.rewind()
        tendon.moveTo(join - 7f, 108f)
        tendon.cubicTo(join + 24f, 115f + narrow, 222f, 111f + narrow, 248f, 112f + narrow)
        tendon.quadTo(259f, 112f, 269f, 108f)
        tendon.quadTo(274f, 119f, 269f, 131f)
        tendon.quadTo(258f, 126f, 248f, 128f - narrow)
        tendon.cubicTo(222f, 129f - narrow, join + 24f, 124f - narrow, join - 7f, 132f)
        tendon.close()
        tissue(c, tendon, tendonFill, teal)
        for (row in -1..1) {
            val offset = row * (4.5f - load)
            detail.rewind()
            detail.moveTo(join - 4f, 120f + offset)
            detail.cubicTo(join + 30f, 121f + offset, 231f, 118f + offset, 268f, 119f + row * 6f)
            stroke(c, detail, 0xff679d90, 1.35f)
        }

        val bulge = 5f * load
        muscle.rewind()
        muscle.moveTo(23f, 119f)
        muscle.cubicTo(36f, 95f, 62f, 80f - bulge, 93f, 86f - bulge)
        muscle.cubicTo(join - 32f, 88f - bulge, join - 22f, 103f, join, 110f)
        muscle.quadTo(join + 4f, 119f, join, 130f)
        muscle.cubicTo(join - 23f, 134f, join - 35f, 153f + bulge, 83f, 154f + bulge)
        muscle.cubicTo(54f, 157f + bulge, 33f, 143f, 23f, 119f)
        muscle.close()
        tissue(c, muscle, muscleFill, coral)
        for (row in -2..2) {
            val spread = row * (8f + load)
            detail.rewind()
            detail.moveTo(32f + abs(row) * 4f, 120f + row * 3f)
            detail.cubicTo(63f, 117f + 1.65f * spread, join - 31f, 120f + spread, join - 4f, 120f + row * 3.5f)
            stroke(c, detail, if (row % 2 == 0) 0xffbb7482 else 0xfffde5df, 1.65f)
        }
    }

    private fun drawCallout(c: Canvas, @StringRes title: Int, x: Float, y: Float, progress: Float, color: Long) {
        label(c, title, x, 54f, 94f)
        line(c, x, 62f, x, y, leaderInk, 1.25f)
        disc(c, x, y, 2.8f, color, cream)
        focusRing(c, x, y, progress, color)
    }

    private fun focusRing(c: Canvas, x: Float, y: Float, progress: Float, color: Long) {
        if (progress <= 0f || progress >= 1f) return
        ink(color, 2.4f)
        paint.alpha = (220f * (1f - abs(2f * progress - 1f))).toInt()
        c.drawCircle(x, y, 5f + 15f * progress, paint)
    }

    private fun drawBonePull(c: Canvas, load: Float, emphasis: Float) {
        focusRing(c, 269f, 119f, emphasis, violet)
        if (load <= .06f) return
        // This arrow is the pull on bone, toward the muscle, not motion of the bone or a signal.
        line(c, 276f, 152f, 276f, 164f, violet, 1.35f)
        loadArrow(c, 276f, 164f, -1f, load)
        label(c, R.string.health_atlas_tendon_story_pull, 277f, 182f, 119f)
    }

    private fun drawCollagen(c: Canvas, load: Float) {
        rounded(c, 18f, 189f, 342f, 334f, 8f, 0xfff3f8ef)
        rounded(c, 31f, 222f, 329f, 304f, 7f, 0xffdcefe5)
        label(c, R.string.health_atlas_tendon_story_collagen, 180f, 211f, 280f)
        val first = 56f - 10f * load
        val halfWave = (304f - first) / 8f
        val crimp = 10f - 8.8f * load
        for (row in 0..2) {
            val y = 239f + 24f * row
            detail.rewind()
            detail.moveTo(first, y)
            for (half in 0..7) {
                val x = first + half * halfWave
                val rise = if (half % 2 == 0) -crimp else crimp
                detail.cubicTo(x + halfWave / 3f, y + rise, x + 2f * halfWave / 3f, y + rise, x + halfWave, y)
            }
            stroke(c, detail, if (row == 1) teal else 0xff51867d, if (row == 1) 3.1f else 2.4f)
        }
        if (load > .06f) {
            loadArrow(c, 96f, 319f, -1f, load)
            loadArrow(c, 264f, 319f, 1f, load)
            label(c, R.string.health_atlas_tendon_story_tension, 180f, 324f, 144f)
        }
    }

    private fun loadArrow(c: Canvas, x: Float, y: Float, direction: Float, load: Float) {
        val tip = x + direction * (7f + 46f * load)
        val base = tip - direction * (4f + 4f * load)
        val wing = 2.5f + 2f * load
        ink(violet, 1.8f + 1.1f * load)
        paint.alpha = (255f * (load * 4f).coerceAtMost(1f)).toInt()
        c.drawLine(x, y, tip, y, paint)
        c.drawLine(base, y - wing, tip, y, paint)
        c.drawLine(base, y + wing, tip, y, paint)
    }

    private fun tissue(c: Canvas, shape: Path, fill: Shader, border: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(shape, paint)
        paint.shader = null
        stroke(c, shape, border, 1.7f)
    }
}
