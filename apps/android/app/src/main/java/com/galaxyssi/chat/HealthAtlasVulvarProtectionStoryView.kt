package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader
import com.galaxyssi.chat.HealthAtlasVulvarProtectionAssignment as Lesson
import com.galaxyssi.chat.HealthAtlasVulvarProtectionMotion.reveal
import com.galaxyssi.chat.HealthAtlasVulvarProtectionPlates as Plates
import com.galaxyssi.chat.R.string

internal object HealthAtlasVulvarProtectionMotion {
    // Only the reading emphasis advances; the tissue contours stay fixed.
    fun reveal(t: Float, start: Float, end: Float): Float {
        val p = ((t - start) / (end - start)).coerceIn(0f, 1f)
        return .10f + .90f * p * p * (3f - 2f * p)
    }
}

internal class HealthAtlasVulvarProtectionStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val outerInk = 0xff914f48
    private val innerInk = 0xff644671
    private val vestibuleInk = 0xff346c60
    private val boundaryInk = 0xff6d564d
    private val fatInk = 0xff845928
    private val segment = Path()
    private val region = art(Plates.region)
    private val outer = art(Plates.outer)
    private val inner = art(Plates.inner)

    private val regionalOutline = track(Path().apply {
        moveTo(180f, 26f)
        cubicTo(145f, 26f, 120f, 45f, 105f, 76f)
        cubicTo(89f, 108f, 91f, 150f, 105f, 181f)
        cubicTo(121f, 217f, 151f, 246f, 180f, 252f)
        cubicTo(209f, 246f, 239f, 217f, 255f, 181f)
        cubicTo(269f, 150f, 271f, 108f, 255f, 76f)
        cubicTo(240f, 45f, 215f, 26f, 180f, 26f)
    })
    private val regionOuter = track(Path().apply {
        moveTo(165f, 52f)
        cubicTo(142f, 53f, 121f, 78f, 116f, 113f)
        cubicTo(108f, 153f, 128f, 208f, 166f, 229f)
    })
    private val regionInnerMargin = track(Path().apply {
        moveTo(176f, 73f)
        cubicTo(169f, 99f, 162f, 120f, 162f, 149f)
        cubicTo(162f, 169f, 167f, 190f, 174f, 211f)
    })
    private val sectionSkin = track(Path().apply {
        moveTo(27f, 183f)
        cubicTo(53f, 171f, 58f, 154f, 67f, 121f)
        cubicTo(76f, 89f, 92f, 75f, 113f, 80f)
        cubicTo(135f, 85f, 144f, 114f, 144f, 144f)
    })
    private val sectionFat = track(Path().apply {
        moveTo(80f, 126f)
        cubicTo(86f, 104f, 96f, 92f, 110f, 96f)
        cubicTo(124f, 100f, 130f, 121f, 129f, 145f)
        cubicTo(130f, 163f, 142f, 186f, 158f, 197f)
    })
    private val innerLeft = track(Path().apply {
        moveTo(174f, 52f)
        cubicTo(172f, 62f, 168f, 72f, 161f, 83f)
        cubicTo(152f, 98f, 145f, 116f, 149f, 132f)
        cubicTo(153f, 144f, 150f, 161f, 154f, 173f)
        cubicTo(160f, 190f, 163f, 201f, 174f, 224f)
    })
    private val innerRight = track(Path().apply {
        moveTo(185f, 57f)
        cubicTo(187f, 70f, 192f, 82f, 200f, 96f)
        cubicTo(207f, 107f, 211f, 119f, 209f, 132f)
        cubicTo(208f, 144f, 213f, 159f, 207f, 174f)
        cubicTo(201f, 187f, 203f, 201f, 187f, 226f)
    })

    private val profileBase = Path().apply {
        moveTo(0f, 196f)
        cubicTo(11f, 190f, 14f, 152f, 29f, 148f)
        cubicTo(48f, 143f, 47f, 198f, 74f, 198f)
        cubicTo(101f, 198f, 100f, 143f, 119f, 148f)
        cubicTo(134f, 152f, 137f, 190f, 148f, 196f)
        lineTo(148f, 219f)
        quadTo(74f, 235f, 0f, 219f)
        close()
    }
    private val shortFold = Path().apply {
        moveTo(37f, 191f)
        cubicTo(40f, 174f, 43f, 158f, 50f, 157f)
        cubicTo(62f, 155f, 53f, 181f, 70f, 197f)
        quadTo(53f, 204f, 37f, 191f)
        close()
    }
    private val longFold = Path().apply {
        moveTo(37f, 191f)
        cubicTo(35f, 174f, 36f, 151f, 43f, 134f)
        cubicTo(52f, 111f, 64f, 121f, 58f, 149f)
        cubicTo(53f, 175f, 60f, 189f, 70f, 197f)
        quadTo(53f, 204f, 37f, 191f)
        close()
    }
    private val shortEdge = track(shortFold)
    private val longEdge = track(longFold)
    private val baseShade = shade(145f, 231f, 0xfff4d4bc, 0xffcb9383)
    private val foldShade = shade(119f, 202f, 0xffe8d5e7, 0xffb18eae)

    init { tag = "atlas-function-vulvar-protective-folds-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            Lesson.OVERVIEW -> overview(c, t)
            Lesson.OUTER -> outerCover(c, t)
            Lesson.INNER -> innerBorder(c, t)
            Lesson.VARIATION -> variation(c, t)
            Lesson.BOUNDARY -> boundaries(c, t)
        }
    }

    private fun art(plate: HealthAtlasPlate) = requireNotNull(context.getDrawable(plate.drawable)).apply {
        setBounds(0, TOP, Plates.WIDTH, TOP + Plates.HEIGHT)
    }

    private fun overview(c: Canvas, t: Float) {
        region.draw(c)
        onPlate(c) {
            pairedTrace(c, regionOuter, outerInk, reveal(t, 0f, .56f))
            pairedTrace(c, regionInnerMargin, innerInk, reveal(t, .32f, .95f))
        }
        callout(c, Plates.region.features[1], 55f, 144f, 87f, 149f, outerInk)
        callout(c, Plates.region.features[2], 305f, 136f, 272f, 141f, innerInk)
    }

    private fun outerCover(c: Canvas, t: Float) {
        outer.draw(c)
        onPlate(c) {
            pairedTrace(c, sectionSkin, outerInk, reveal(t, 0f, .67f))
            pairedTrace(c, sectionFat, fatInk, reveal(t, .28f, .96f))
        }
        callout(c, Plates.outer.features[0], 105f, 85f, 105f, 94f, outerInk)
        callout(c, Plates.outer.features[1], 75f, 308f, 75f, 290f, fatInk)
    }

    private fun innerBorder(c: Canvas, t: Float) {
        inner.draw(c)
        onPlate(c) {
            val progress = reveal(t, 0f, .91f)
            trace(c, innerLeft, innerInk, progress)
            trace(c, innerRight, innerInk, progress)
        }
        callout(c, Plates.inner.features[1], 263f, 82f, 263f, 92f, innerInk)
        callout(c, Plates.inner.features[2], 181f, 317f, 181f, 300f, vestibuleInk)
    }

    private fun boundaries(c: Canvas, t: Float) {
        region.draw(c)
        onPlate(c) {
            trace(c, regionalOutline, boundaryInk, reveal(t, 0f, .72f))
            pairedTrace(c, regionInnerMargin, vestibuleInk, reveal(t, .28f, .98f))
        }
        callout(c, Plates.region.features[0], 58f, 86f, 78f, 94f, boundaryInk)
        callout(c, Plates.region.features[3], 180f, 321f, 180f, 303f, vestibuleInk)
    }

    private fun variation(c: Canvas, t: Float) {
        line(c, 180f, 100f, 180f, 250f, 0xffabbdb6, 1f)
        val progress = reveal(t, 0f, .92f)
        profile(c, 18f, false, progress)
        profile(c, 194f, true, progress)
        label(c, string.health_atlas_vulvar_protection_profile_one, 92f, 263f, 130f)
        label(c, string.health_atlas_vulvar_protection_profile_two, 268f, 263f, 130f)
        label(c, string.health_atlas_vulvar_protection_inner_folds, 180f, 303f, 150f)
        line(c, 121f, 299f, 138f, 299f, innerInk, 2.1f)
    }

    private fun profile(c: Canvas, x: Float, longerLeft: Boolean, progress: Float) {
        c.save()
        c.translate(x, 0f)
        surface(c, profileBase, baseShade, outerInk)
        oval(c, 54f, 189f, 94f, 204f, 0xffb9d4c3, vestibuleInk)
        profileFold(c, longerLeft, progress)
        c.translate(148f, 0f)
        c.scale(-1f, 1f)
        profileFold(c, false, progress)
        c.restore()
    }

    private fun profileFold(c: Canvas, longer: Boolean, progress: Float) {
        surface(c, if (longer) longFold else shortFold, foldShade, innerInk)
        trace(c, if (longer) longEdge else shortEdge, innerInk, progress)
    }

    private fun surface(c: Canvas, path: Path, shader: Shader, color: Long) {
        ink(cream)
        paint.shader = shader
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, color, 1.3f)
    }

    private fun callout(c: Canvas, feature: HealthAtlasFeature,
        textX: Float, baseline: Float, startX: Float, startY: Float, color: Long) {
        val x = feature.marker.x * Plates.WIDTH
        val y = feature.marker.y * Plates.HEIGHT + TOP
        line(c, startX, startY, x, y, color, 1.05f)
        disc(c, x, y, 2.6f, color, cream)
        label(c, feature.title, textX, baseline, 104f)
    }

    private inline fun onPlate(c: Canvas, draw: () -> Unit) {
        c.save()
        c.translate(0f, TOP.toFloat())
        draw()
        c.restore()
    }

    private fun pairedTrace(c: Canvas, path: PathMeasure, color: Long, progress: Float) {
        trace(c, path, color, progress)
        c.save()
        c.translate(Plates.WIDTH.toFloat(), 0f)
        c.scale(-1f, 1f)
        trace(c, path, color, progress)
        c.restore()
    }

    private fun trace(c: Canvas, path: PathMeasure, color: Long, progress: Float) {
        segment.rewind()
        if (path.getSegment(0f, path.length * progress, segment, true)) {
            stroke(c, segment, cream, 4f)
            stroke(c, segment, color, 2.05f)
        }
    }

    private companion object {
        const val TOP = 40
    }
}
