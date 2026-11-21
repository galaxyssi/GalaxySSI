package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader

/** Cell silhouettes and normalized motion are educational geometry, not measured anatomy. */
internal abstract class HealthAtlasMastAndTCellArt(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val lymphocyteRim = Path().apply {
        moveTo(0f, -43f)
        cubicTo(22f, -45f, 38f, -29f, 42f, -13f)
        cubicTo(46f, 1f, 40f, 13f, 38f, 22f)
        cubicTo(31f, 39f, 14f, 44f, -5f, 43f)
        cubicTo(-24f, 43f, -42f, 30f, -43f, 8f)
        cubicTo(-46f, -12f, -35f, -32f, -23f, -36f)
        quadTo(-12f, -41f, 0f, -43f)
        close()
    }

    protected fun ease(t: Float, start: Float = 0f, end: Float = 1f): Float {
        val f = ((t - start) / (end - start)).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }

    protected fun mix(start: Float, end: Float, fraction: Float) = start + (end - start) * fraction

    protected fun fill(c: Canvas, path: Path, shader: Shader, edge: Long) {
        ink(cream)
        paint.shader = shader
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, edge, 1.6f)
    }

    protected fun lymphocyte(c: Canvas, x: Float, y: Float, size: Float, shell: Shader, edge: Long) {
        c.save()
        c.translate(x, y)
        c.scale(size, size)
        fill(c, lymphocyteRim, shell, edge)
        oval(c, -30f, -32f, 23f, 30f, 0xff94839f, 0xff66556f)
        oval(c, -24f, -26f, 16f, 23f, 0xffa897b4, 0xffa897b4)
        disc(c, -12f, -12f, 4f, 0xffc9b9d3)
        ink(cream, 2f)
        c.drawArc(-37f, -37f, 37f, 37f, 207f, 43f, false, paint)
        c.restore()
    }
}

internal class HealthAtlasHelperTCellStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasMastAndTCellArt(context, story) {
    private val helperEdge = 0xff23736b
    private val signalInk = 0xff236d67
    private val receiverEdge = 0xff8e5e42
    private val helperFill = shade(-43f, 43f, 0xffbfe9d7, 0xff66ab9d)
    private val bFill = shade(-43f, 43f, 0xfff5daaa, 0xffd4a476)
    private val tFill = shade(-43f, 43f, 0xffc9e4f0, 0xff89aecf)
    private val cueFill = shade(-43f, 43f, 0xfff3ded4, 0xffd6a697)
    private val cueRim = Path().apply {
        moveTo(4f, -40f)
        cubicTo(22f, -41f, 26f, -24f, 39f, -20f)
        quadTo(58f, -11f, 40f, 1f)
        cubicTo(31f, 8f, 50f, 23f, 32f, 34f)
        cubicTo(15f, 46f, -12f, 48f, -28f, 32f)
        cubicTo(-44f, 21f, -33f, 11f, -45f, -2f)
        quadTo(-57f, -17f, -41f, -23f)
        cubicTo(-24f, -29f, -17f, -38f, 4f, -40f)
        close()
    }
    private val upperPath = Path().apply { moveTo(138f, 160f); cubicTo(167f, 150f, 169f, 103f, 234f, 104f) }
    private val lowerPath = Path().apply { moveTo(138f, 185f); cubicTo(176f, 196f, 178f, 241f, 234f, 243f) }
    private val upperTrack = track(upperPath)
    private val lowerTrack = track(lowerPath)
    private val signalPoint = FloatArray(2)
    private val spreadAngles = floatArrayOf(-64f, -32f, -1f, 29f, 60f)
    private val mark = Path()

    init { tag = "atlas-function-helper-t-coordination-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> cue(c, t)
            1 -> send(c, t)
            2 -> branch(c, t, false)
            else -> branch(c, t, true)
        }
    }

    private fun cue(c: Canvas, t: Float) {
        val f = ease(t)
        c.save()
        c.translate(98f + 26f * f, 172f)
        c.scale(1.18f, 1.18f)
        fill(c, cueRim, cueFill, receiverEdge)
        oval(c, -25f, -19f, 18f, 21f, 0xffb4829a, violet)
        disc(c, -11f, -7f, 4f, 0xffdfbacb)
        c.restore()

        lymphocyte(c, 224f, 172f, 1.16f, helperFill, helperEdge)
        val response = ease(t, .40f, .90f)
        for (i in 0..2) {
            val y = 150f + i * 22f
            line(c, 183f - i % 2 * 2f, y, 184f + 15f * response, y, signalInk, 1.4f + response)
        }
        label(c, R.string.health_atlas_helper_t_story_label_cue_cell, 110f, 266f, 132f)
        label(c, R.string.health_atlas_helper_t_story_label_helper, 231f, 266f, 109f)
    }

    private fun send(c: Canvas, t: Float) {
        lymphocyte(c, 124f, 171f, 1.45f, helperFill, helperEdge)
        for (i in spreadAngles.indices) {
            val f = ease(t, .065f + .086f * i, .53f + .105f * i)
            if (f <= 0f) continue
            c.save()
            c.translate(124f, 171f)
            c.rotate(spreadAngles[i])
            val r = 64f + 62f * f
            diamond(c, r, i % 2 * 4f, 4.6f - 1.4f * f)
            if (f > .15f) diamond(c, r - 12f * f, -7f, 2.4f)
            c.restore()
        }
        label(c, R.string.health_atlas_helper_t_story_label_cytokines, 249f, 269f, 152f)
        label(c, R.string.health_atlas_helper_t_story_label_helper, 115f, 269f, 112f)
    }

    private fun branch(c: Canvas, t: Float, responding: Boolean) {
        val first = if (responding) 1f else ease(t, .04f, .80f)
        val second = if (responding) 1f else ease(t, .18f, .94f)
        lymphocyte(c, 87f, 172f, 1.16f, helperFill, helperEdge)
        lymphocyte(c, 267f, 104f, .78f, bFill, receiverEdge)
        lymphocyte(c, 267f, 243f, .78f, tFill, blue)
        if (responding) {
            delivery(c, upperTrack, .58f + .42f * t, .90f)
            delivery(c, lowerTrack, .52f + .48f * t, 1f)
            responseFan(c, 267f, 104f, t, receiverEdge, -1f)
            responseFan(c, 267f, 243f, ease(t, .10f, .96f), blue, 1f)
        } else {
            delivery(c, upperTrack, first, .92f)
            delivery(c, lowerTrack, second, .88f)
        }
        label(c, R.string.health_atlas_helper_t_story_label_helper, 87f, 240f, 117f)
        label(c, R.string.health_atlas_helper_t_story_label_b, 266f, 51f, 113f)
        label(c, R.string.health_atlas_helper_t_story_label_other_t, 263f, 314f, 153f)
    }

    private fun delivery(c: Canvas, route: PathMeasure, f: Float, size: Float) {
        for (i in 0..4) {
            val p = f - .125f * i
            if (p > 0f && route.getPosTan(route.length * p, signalPoint, null)) {
                diamond(c, signalPoint[0], signalPoint[1], size * (4.3f - i * .38f))
            }
        }
    }

    private fun responseFan(c: Canvas, x: Float, y: Float, t: Float, color: Long, direction: Float) {
        for (i in 0..2) {
            val r = 36f + 5f * i + 4f * t
            val sweep = 11f + 13f * ease(t, .02f * i, .65f + .06f * i)
            ink(color, 2.2f - .41f * i)
            c.drawArc(x - r, y - r, x + r, y + r, direction * (19f + 3f * i), sweep, false, paint)
        }
    }

    private fun diamond(c: Canvas, x: Float, y: Float, r: Float) {
        mark.rewind()
        mark.moveTo(x, y - r); mark.lineTo(x + r, y); mark.lineTo(x, y + r); mark.lineTo(x - r, y); mark.close()
        ink(signalInk)
        c.drawPath(mark, paint)
    }
}

internal class HealthAtlasCytotoxicTCellStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasMastAndTCellArt(context, story) {
    private val cytotoxicEdge = 0xff366581
    private val targetEdge = 0xff9c5c61
    private val interfaceInk = 0xff385c78
    private val cytotoxicFill = shade(-43f, 43f, 0xffb8dcec, 0xff6399bd)
    private val abnormalFill = shade(-60f, 60f, 0xfff6cfc5, 0xffd58e92)
    private val nearbyFill = shade(-60f, 60f, 0xffe5e7d4, 0xffbec8a8)
    private val bodyRim = Path().apply {
        moveTo(-20f, -50f)
        cubicTo(2f, -60f, 26f, -54f, 44f, -39f)
        cubicTo(62f, -23f, 54f, -10f, 60f, 6f)
        cubicTo(68f, 29f, 41f, 59f, 18f, 55f)
        cubicTo(-10f, 51f, -26f, 62f, -42f, 46f)
        quadTo(-59f, 31f, -59f, 16f)
        lineTo(-59f, -15f)
        quadTo(-54f, -37f, -20f, -50f); close()
    }
    private val contact = Path()
    private val targetX = 255f
    private val bodyY = 170f
    private val contactX = 196f
    private val engagedX = 149f

    init { tag = "atlas-function-cytotoxic-t-contact-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> pair(c, mix(83f, 127f, ease(t)), 0f)
            1 -> {
                val x = mix(127f, engagedX, ease(t, .02f, .44f))
                pair(c, x, 0f)
                contact(c, ease(t, .44f, .93f))
            }
            2 -> {
                val change = ease(t, .10f, .95f)
                pair(c, engagedX, change)
                contact(c, 1f - ease(t, 0f, .24f), false)
                label(c, R.string.health_atlas_cytotoxic_t_story_label_apoptosis, 254f, 83f, 164f)
            }
            else -> separate(c, t)
        }
    }

    private fun pair(c: Canvas, x: Float, change: Float) {
        target(c, change)
        lymphocyte(c, x, bodyY, 1.08f, cytotoxicFill, cytotoxicEdge)
        label(c, R.string.health_atlas_cytotoxic_t_story_label_cell, 113f, 263f, 132f)
        label(c, R.string.health_atlas_cytotoxic_t_story_label_target, 254f, 263f, 174f)
    }

    private fun contact(c: Canvas, activity: Float, showLabel: Boolean = true) {
        if (activity <= 0f) return
        val spread = 3f + 14f * activity
        contact.rewind()
        contact.moveTo(contactX - 1f, bodyY - spread)
        contact.quadTo(contactX + 2f, bodyY, contactX - 3f, bodyY + spread)
        stroke(c, contact, 0xfff8eee1, 6.1f)
        stroke(c, contact, interfaceInk, 2.25f)
        if (showLabel) {
            label(c, R.string.health_atlas_cytotoxic_t_story_label_contact, 172f, 73f, 170f)
            line(c, 176f, 83f, contactX - 4f, 145f, interfaceInk, 1.1f)
        }
    }

    private fun target(c: Canvas, change: Float, fragments: Float = 0f) {
        val size = 1f - .36f * change
        c.save()
        // Hold the near edge at the point of contact as the target contracts.
        c.translate(targetX - (1f - size) * 59f, bodyY + 5f * change)
        c.scale(size, size)
        fill(c, bodyRim, abnormalFill, targetEdge)
        oval(c, -23f + 10f * change, -26f + 9f * change, 31f - 8f * change, 24f - 6f * change,
            0xffa97491, 0xff80516e)
        disc(c, 10f, -6f, 7f - 3f * change, 0xff79506b)
        disc(c, 2f, 7f, 4f - change, 0xff79506b)
        for (i in 0..2) {
            val f = ease(change, .13f + i * .13f, .66f + i * .10f)
            if (f <= 0f) continue
            val x = 40f + i % 2 * 11f + 14f * f + fragments * (18f + i * 6f)
            val y = -40f + i * 35f + (i - 1) * (11f * f + 12f * fragments)
            disc(c, x, y, 3f + f * (7f - i) - 2.4f * fragments, 0xffdf9c9d, targetEdge)
        }
        c.restore()
    }

    private fun separate(c: Canvas, t: Float) {
        val f = ease(t)
        val x = mix(engagedX, 74f, f)
        val y = bodyY - 38f * f
        target(c, 1f, f)
        lymphocyte(c, x, y, 1.08f, cytotoxicFill, cytotoxicEdge)
        c.save()
        c.translate(280f, 262f)
        c.scale(.61f, .61f)
        fill(c, bodyRim, nearbyFill, 0xff748064)
        oval(c, -24f, -22f, 20f, 20f, 0xffa69ab2, 0xff766b84)
        c.restore()
        label(c, R.string.health_atlas_cytotoxic_t_story_label_cell, (x - 3f).coerceAtLeast(75f), y + 72f, 128f)
        label(c, R.string.health_atlas_cytotoxic_t_story_label_apoptosis, 234f, 112f, 151f)
        label(c, R.string.health_atlas_cytotoxic_t_story_label_neighbor, 252f, 323f, 185f)
    }
}

internal class HealthAtlasRegulatoryTCellStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasMastAndTCellArt(context, story) {
    private val responseEdge = 0xff97663e
    private val regulationEdge = 0xff4c6f55
    private val responderFill = shade(-43f, 43f, 0xfff5d5a2, 0xffd7a47e)
    private val regulatorFill = shade(-43f, 43f, 0xffd1e3b7, 0xff87aa7c)
    private val activityTop = Path()
    private val activityBand = Path()

    init { tag = "atlas-function-regulatory-t-moderation-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> response(c, t, 0f, false)
            1 -> response(c, t + 1f, 0f, true, ease(t))
            2 -> response(c, t + 2f, ease(t, .05f, .95f), true, 1f)
            else -> response(c, t + 3f, 1f, true, 1f)
        }
    }

    private fun response(c: Canvas, phase: Float, settling: Float, showRegulator: Boolean, entering: Float = 0f) {
        ribbon(c, phase, settling)
        for (i in 0..2) {
            val motion = (5.5f - 3.5f * settling) * wave(phase + i * .21f)
            lymphocyte(c, 80f + 100f * i + motion, 117f - 14f * (i % 2) - motion * .6f,
                .75f, responderFill, responseEdge)
        }
        label(c, R.string.health_atlas_regulatory_t_story_label_responders, 180f, 53f, 238f)
        label(c, if (settling < .5f) R.string.health_atlas_regulatory_t_story_label_active
            else R.string.health_atlas_regulatory_t_story_label_moderated, 180f, 223f, 246f)
        if (showRegulator) {
            val x = mix(274f, 182f, entering)
            val y = mix(296f, 277f, entering)
            lymphocyte(c, x, y, .72f + .17f * entering, regulatorFill, regulationEdge)
            label(c, R.string.health_atlas_regulatory_t_story_label_regulator, x, 340f, 140f)
        }
    }

    private fun ribbon(c: Canvas, phase: Float, settling: Float) {
        // A moving thread of activity, not a chart or a measured signal.
        val spread = mix(23f, 5f, settling)
        val halfWidth = mix(9f, 3f, settling)
        activityTop.rewind()
        activityBand.rewind()
        for (i in 0..40) {
            val f = i / 40f
            val x = 42f + 276f * f
            val y = ribbonY(f, phase, spread)
            if (i == 0) {
                activityTop.moveTo(x, y)
                activityBand.moveTo(x, y - halfWidth)
            } else {
                activityTop.lineTo(x, y)
                activityBand.lineTo(x, y - halfWidth)
            }
        }
        for (i in 40 downTo 0) {
            val f = i / 40f
            activityBand.lineTo(42f + 276f * f, ribbonY(f, phase, spread) + halfWidth)
        }
        activityBand.close()
        ink(0xffefceaa)
        c.drawPath(activityBand, paint)
        stroke(c, activityTop, responseEdge, 2.1f)
    }

    private fun ribbonY(f: Float, phase: Float, spread: Float) =
        179f + spread * wave(f * 2.25f - .48f * phase) * (1f - kotlin.math.abs(2f * f - 1f) * .48f)
}

internal class HealthAtlasMastCellStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasMastAndTCellArt(context, story) {
    private val rim = 0xff6e476b
    private val granuleInk = 0xff8c4171
    private val productInk = 0xffb05a48
    private val skinEdge = 0xffab6875
    private val airwayEdge = 0xff598c91
    private val gutEdge = 0xffbb8560
    private val cellFill = shade(-60f, 60f, 0xffedc9e0, 0xffbd84ad)
    private val shell = Path().apply {
        moveTo(-16f, -59f)
        cubicTo(12f, -68f, 39f, -55f, 50f, -37f)
        cubicTo(62f, -27f, 65f, -6f, 62f, 15f)
        cubicTo(60f, 45f, 29f, 65f, 4f, 63f)
        cubicTo(-29f, 66f, -61f, 48f, -61f, 11f)
        cubicTo(-67f, -21f, -47f, -52f, -16f, -59f)
        close()
    }
    private val skinTop = Path().apply {
        moveTo(0f, -22f); lineTo(178f, -22f); lineTo(178f, -12f)
        cubicTo(156f, -1f, 146f, -23f, 126f, -10f)
        cubicTo(100f, 6f, 89f, -22f, 67f, -10f)
        cubicTo(39f, 3f, 31f, -21f, 0f, -9f); close()
    }
    private val gutTop = Path().apply {
        moveTo(0f, 3f); lineTo(20f, 3f)
        for (i in 0..2) {
            val x = 20f + i * 48f
            cubicTo(x + 8f, 3f, x + 5f, -21f, x + 19f, -21f)
            cubicTo(x + 33f, -21f, x + 30f, 3f, x + 40f, 3f)
            lineTo(x + 48f, 3f)
        }
        lineTo(178f, 3f); lineTo(178f, 12f); lineTo(0f, 12f); close()
    }
    private val residentColors = longArrayOf(skinEdge, airwayEdge, gutEdge)
    private val siteNames = intArrayOf(
        R.string.health_atlas_mast_story_label_skin,
        R.string.health_atlas_mast_story_label_airway,
        R.string.health_atlas_mast_story_label_gut,
    )
    private val granules = floatArrayOf(
        -42f, -17f, -31f, -37f, -14f, -46f, 7f, -44f, 29f, -39f, 42f, -23f, 48f, -6f,
        43f, 16f, 36f, 34f, 21f, 47f, 1f, 51f, -21f, 45f, -41f, 32f, -47f, 9f,
        21f, -23f, 28f, -4f, 22f, 18f, 18f, 34f, -9f, 38f, -27f, 28f, -14f, -27f, 3f, -25f,
    )
    private val spokesX = floatArrayOf(.72f, .88f, 1f, .98f, .90f, .75f)
    private val spokesY = floatArrayOf(-.69f, -.47f, -.10f, .20f, .43f, .66f)
    private val releaseRim = floatArrayOf(50f, 59f, 63f, 61f, 55f, 46f)

    init { tag = "atlas-function-mast-cell-granule-release-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> sites(c, t)
            1 -> storage(c, t)
            2 -> release(c, t)
            else -> spread(c, t)
        }
    }

    private fun sites(c: Canvas, t: Float) {
        label(c, R.string.health_atlas_mast_story_label_resident, 180f, 37f, 280f)
        for (i in siteNames.indices) {
            val y = 91f + i * 97f
            val focus = (1f - kotlin.math.abs(t * 2f - i)).coerceIn(0f, 1f)
            val edge = residentColors[i]
            c.save()
            c.translate(28f, y)
            rounded(c, 0f, -22f, 178f, 35f, 4f, 0xfff2dfd5)
            when (i) {
                0 -> { ink(0xffe4a7a5); c.drawPath(skinTop, paint); stroke(c, skinTop, edge, 1.2f) }
                1 -> {
                    oval(c, 4f, -22f, 112f, 19f, 0xff94bcbd, edge)
                    oval(c, 11f, -17f, 105f, 14f, 0xffe2f2ee, edge)
                    for (j in 0..6) line(c, 25f + j * 11f, -12f, 27f + j * 11f, -7f, edge, 1f)
                }
                else -> { ink(0xffedc3a5); c.drawPath(gutTop, paint); stroke(c, gutTop, edge, 1.2f) }
            }
            oval(c, 34f, 22f, 113f, 31f, 0xffd9a1a5, skinEdge)
            val mastX = if (i == 0) 122f else 139f
            val mastY = if (i == 0) 12f else 22f
            ring(c, mastX, mastY, 12f + 6f * focus, rim, 1f + 1.6f * focus)
            mast(c, mastX, mastY, .19f, 0f)
            c.restore()

            line(c, 215f, y + 4f, 230f + 12f * focus, y + 4f, edge, 1.6f + focus)
            label(c, siteNames[i], 286f, y + 8f, 96f)
        }
    }

    private fun storage(c: Canvas, t: Float) {
        mast(c, 180f, 172f, 1.46f, 0f)
        ink(cream, 2.4f)
        c.drawArc(109f, 101f, 251f, 243f, -161f + 165f * ease(t), 54f, false, paint)
        line(c, 141f, 187f, 100f, 274f, rim, 1.5f)
        line(c, 211f, 241f, 265f, 274f, rim, 1.5f)
        disc(c, 141f, 187f, 2.5f, cream, rim)
        disc(c, 211f, 241f, 2.5f, cream, rim)
        label(c, R.string.health_atlas_mast_story_label_cell, 180f, 52f, 230f)
        label(c, R.string.health_atlas_mast_story_label_nucleus, 88f, 297f, 130f)
        label(c, R.string.health_atlas_mast_story_label_granules, 270f, 297f, 132f)
    }

    private fun release(c: Canvas, t: Float) {
        mast(c, 111f, 171f, 1.16f, t)
        releasedContents(c, t)
        label(c, R.string.health_atlas_mast_story_label_cell, 111f, 282f, 128f)
        label(c, R.string.health_atlas_mast_story_label_contents, 254f, 282f, 153f)
    }

    private fun spread(c: Canvas, t: Float) {
        oval(c, 33f, 262f, 327f, 308f, 0xffefc6c7, skinEdge)
        oval(c, 45f, 269f, 315f, 301f, 0xfffbe5de, skinEdge)
        for (i in 0..5) {
            val x = 77f + i * 40f
            val y = 267f - 4.5f * wave((i + .5f) / 12f)
            oval(c, x - 7f, y, x + 7f, y + 5f, 0xffbe8e9c, skinEdge)
        }
        mast(c, 111f, 171f, 1.16f, 1f)
        releasedContents(c, 1f, t)
        label(c, R.string.health_atlas_mast_story_label_tissue, 249f, 49f, 174f)
        label(c, R.string.health_atlas_mast_story_label_vessel, 180f, 332f, 220f)
    }

    private fun releasedContents(c: Canvas, release: Float, spread: Float = 0f) {
        for (i in spokesX.indices) {
            val out = ease(release, fusionPhase(i), .62f + .073f * i)
            if (out <= 0f) continue
            val f = ease(spread, .02f + .034f * i, .74f + .042f * i)
            val x = 111f + 1.16f * releaseRim[i] + (50f * out + 72f * f) * spokesX[i]
            val y = 171f + 1.16f * granules[2 * (i + 4) + 1] + (20f * out + 22f * f) * spokesY[i]
            val r = mix(2f, 3.8f, out) - 1.65f * f
            disc(c, x, y, r, productInk)
            if (out > .18f) disc(c, x + 8f * out + 6f * f, y - 4f * out + 7f * f, r * .63f, productInk)
        }
    }

    private fun fusionPhase(index: Int) = .31f + .074f * index

    private fun mast(c: Canvas, x: Float, y: Float, size: Float, release: Float) {
        c.save()
        c.translate(x, y)
        c.scale(size, size)
        fill(c, shell, cellFill, rim)
        oval(c, -38f, -24f, 8f, 25f, 0xff88658f, rim)
        oval(c, -33f, -20f, 2f, 21f, 0xffa387ad, 0xffa387ad)
        for (i in 0 until granules.size / 2) {
            val gx = granules[2 * i]
            val gy = granules[2 * i + 1]
            val releasing = i in 4..9
            val f = if (releasing) ease(release, .04f + .071f * (i - 4), fusionPhase(i - 4)) else 0f
            if (f < 1f) {
                val x = if (releasing) mix(gx, releaseRim[i - 4], f) else gx
                disc(c, x, gy, (4.9f + i % 3) * (1f - .75f * f), granuleInk, cream)
            }
        }
        c.restore()
    }

    private fun ring(c: Canvas, x: Float, y: Float, radius: Float, color: Long, width: Float) {
        ink(color, width)
        c.drawCircle(x, y, radius, paint)
    }
}
