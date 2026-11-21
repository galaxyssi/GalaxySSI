package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import androidx.annotation.StringRes

internal class HealthAtlasSurfactantStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.ALVEOLAR_SURFACTANT) {
    private val lining = 0xffc5e4ea
    private val air = 0xffedf7f7
    private val tissue = 0xfff5ddd2
    private val rose = 0xff995769
    private val guide = 0xff547079
    private val surfaceY = 246f
    private val domeX = 125f
    private val apexY = surfaceY - 34f
    private val filmY = surfaceY - 16f
    private val pore = Path()
    private val sac = Path().apply {
        moveTo(82f, 28f)
        cubicTo(86f, 49f, 67f, 51f, 55f, 69f)
        cubicTo(33f, 99f, 53f, 132f, 91f, 136f)
        cubicTo(133f, 141f, 155f, 107f, 140f, 79f)
        cubicTo(130f, 57f, 107f, 51f, 111f, 28f)
    }
    private val filmEdge = surface(filmY)
    private val filmTrack = track(filmEdge)
    private val liquid = section(filmY)
    private val epitheliumEdge = surface(surfaceY)
    private val epithelium = section(surfaceY)
    private val cellBed = section(surfaceY + 8f)
    private val typeTwo = Path().apply {
        moveTo(87f, surfaceY)
        dome(this, surfaceY)
        cubicTo(170f, 264f, 154f, 284f, 129f, 288f)
        cubicTo(104f, 292f, 85f, 269f, 87f, surfaceY)
        close()
    }

    init { tag = "atlas-function-alveolar-surfactant-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val breath = when (step) {
            3 -> t
            4 -> 1f - t
            else -> 0f
        }
        val width = .89f + .18f * breath
        overview(c, step, width)
        wallCutaway(c, step, t, width)
    }

    private fun overview(c: Canvas, step: Int, width: Float) {
        val sampleX = stretch(116f, 96f, width)
        line(c, sampleX - 5f, 139f, 31f, 169f, guide, 1f)
        line(c, sampleX + 6f, 139f, 329f, 169f, guide, 1f)
        c.save()
        c.scale(width, 1f, 96f, 0f)
        fill(c, sac, air)
        stroke(c, sac, rose, 14f)
        stroke(c, sac, peach, 11.5f)
        stroke(c, sac, lining, 4.5f)
        stroke(c, sac, teal, 1.6f)
        c.restore()
        ink(guide, 1.5f)
        c.drawCircle(sampleX, 132f, 8.5f, paint)

        line(c, 100f, 82f, 190f, 60f, guide, 1f)
        disc(c, 100f, 82f, 2f, guide)
        label(c, R.string.health_atlas_surfactant_air, 264f, 64f, 138f)
        if (step in 3..4) {
            val inhale = step == 3
            for (side in -1..1 step 2) {
                val inner = 96f + side * 53f
                val outer = 96f + side * 74f
                arrow(c, if (inhale) inner else outer, 110f, if (inhale) outer else inner, 110f, teal)
            }
            label(c, if (inhale) R.string.health_atlas_surfactant_inhale else R.string.health_atlas_surfactant_exhale,
                264f, 108f, 154f)
        }
    }

    private fun wallCutaway(c: Canvas, step: Int, t: Float, width: Float) {
        rounded(c, 15f, 169f, 345f, 309f, 8f, air)
        c.save()
        c.scale(width, 1f, 180f, 0f)
        fill(c, liquid, lining)
        fill(c, epithelium, peach)
        fill(c, cellBed, tissue)
        stroke(c, epitheliumEdge, rose, 1.15f)
        fill(c, typeTwo, 0xffebadab)
        stroke(c, typeTwo, rose, 1.4f)
        oval(c, 111f, 258f, 137f, 277f, 0xffc9abd1, violet)
        oval(c, 231f, 247f, 252f, 254f, 0xffc9abd1, violet)
        capillary(c)
        lamellarBody(c, 110f, 244f, 6f)
        lamellarBody(c, 147f, 252f, 5f)
        when (step) {
            0 -> {
                lamellarBody(c, domeX, 233f, 7f)
                // Animate the cutaway highlight, not the size or location of the stored packet.
                ink(guide, 1.25f)
                c.drawArc(domeX - 11f, 222f, domeX + 11f, 244f, -90f, 45f + 290f * t, false, paint)
            }
            1 -> release(c, t)
            2 -> if (t < .2f) releasedMaterial(c, 1f + t)
        }
        stroke(c, filmEdge, teal, 2.1f)
        for (i in 1..19) {
            at(filmTrack, i / 20f) { x, y -> disc(c, x, y, 1.55f, 0xff91c8ae) }
        }
        if (step == 2 && t >= .2f) {
            val spread = (t - .2f) / .8f
            for (side in -1..1 step 2) {
                val span = if (side < 0) .32f else .60f
                at(filmTrack, .35f + side * span * spread) { x, y -> disc(c, x, y, 2.8f, teal, cream) }
            }
        }
        c.restore()

        at(filmTrack, .77f) { x, y ->
            callout(c, R.string.health_atlas_surfactant_film, 258f, 190f, 145f,
                stretch(x, 180f, width), y, true)
        }
        if (step == 0) {
            val targetX = stretch(107f, 180f, width)
            line(c, 66f, 196f, 66f, 229f, guide, 1f)
            line(c, 66f, 229f, targetX, 240f, guide, 1f)
            disc(c, targetX, 240f, 2f, guide)
            label(c, R.string.health_atlas_surfactant_lamellar_bodies, 66f, 190f, 106f)
        } else {
            callout(c, R.string.health_atlas_surfactant_liquid, 66f, 190f, 106f,
                stretch(57f, 180f, width), 244f, true)
        }
        callout(c, R.string.health_atlas_surfactant_type_ii, 78f, 330f, 102f,
            stretch(119f, 180f, width), 283f)
        callout(c, R.string.health_atlas_surfactant_capillary, 192f, 330f, 97f,
            stretch(212f, 180f, width), 287f)
        callout(c, R.string.health_atlas_surfactant_type_i, 293f, 330f, 99f,
            stretch(302f, 180f, width), 252f)
    }

    private fun capillary(c: Canvas) {
        oval(c, 163f, 268f, 278f, 297f, 0xfff8cbd1, rose)
        for (i in 0..2) {
            val x = 176f + i * 36f
            oval(c, x, 277f, x + 17f, 288f, 0xffce838c, rose)
        }
    }

    private fun lamellarBody(c: Canvas, x: Float, y: Float, radius: Float) {
        disc(c, x, y, radius, 0xffe1eee0, teal)
        disc(c, x, y, radius * .58f, 0xff9ec8b4, teal)
    }

    private fun release(c: Canvas, t: Float) {
        val approach = (t / .48f).coerceAtMost(1f)
        if (approach < 1f) {
            lamellarBody(c, domeX, 233f - 14f * approach, 7f)
            return
        }
        // The open neck joins the lamellar body lumen to the liquid, not the air.
        pore.rewind()
        pore.moveTo(domeX - 5f, apexY)
        pore.cubicTo(domeX - 8f, apexY + 13f, domeX + 8f, apexY + 13f, domeX + 5f, apexY)
        fill(c, pore, lining)
        line(c, domeX - 4f, apexY, domeX + 4f, apexY, lining, 2f)
        stroke(c, pore, teal, 1.3f)
        releasedMaterial(c, ((t - .48f) / .52f).coerceIn(0f, 1f))
    }

    private fun releasedMaterial(c: Canvas, travel: Float) {
        for (i in -1..1) {
            val x = domeX + i * (1.8f + travel * 2f)
            val y = apexY + 4f - 16f * travel + i * 1.4f
            disc(c, x, y, 1.55f, teal)
        }
    }

    private fun callout(c: Canvas, @StringRes resource: Int, x: Float, baseline: Float, width: Float,
        targetX: Float, targetY: Float, above: Boolean = false) {
        line(c, x, baseline + if (above) 6f else -16f, targetX, targetY, guide, 1f)
        disc(c, targetX, targetY, 2f, guide)
        label(c, resource, x, baseline, width)
    }

    private fun stretch(x: Float, center: Float, width: Float) = center + (x - center) * width

    private fun fill(c: Canvas, path: Path, color: Long) {
        ink(color)
        c.drawPath(path, paint)
    }

    private fun dome(path: Path, y: Float) {
        path.cubicTo(99f, y - 7f, 96f, y - 34f, domeX, y - 34f)
        path.cubicTo(150f, y - 34f, 150f, y - 11f, 170f, y - 4f)
    }

    private fun surface(y: Float) = Path().apply {
        moveTo(28f, y + 3f)
        cubicTo(53f, y + 8f, 74f, y + 6f, 87f, y)
        dome(this, y)
        cubicTo(216f, y + 13f, 274f, y - 4f, 332f, y + 4f)
    }

    private fun section(y: Float) = surface(y).apply {
        lineTo(332f, 303f)
        lineTo(28f, 303f)
        close()
    }
}
