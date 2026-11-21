package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader
import com.galaxyssi.chat.R.string

internal class HealthAtlasAdrenalMedullaStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.ADRENAL_MEDULLA_SIGNAL) {
    private val guide = 0xff5a6c72
    private val rim = 0xff96623d
    private val medullaInk = 0xff8b5969
    private val cellInk = 0xff986568
    private val cargo = 0xff6d4a80
    private val vesselInk = 0xffa36571
    private val nerveInk = 0xff8c682d
    private val kidneyShade = shade(134f, 271f, 0xffdfa2a3, 0xffbd7780)
    private val cortexShade = shade(97f, 254f, 0xfff6dba3, 0xffdfa26c)
    private val medullaShade = shade(130f, 223f, 0xffe8b9b7, 0xffc78e9d)
    private val cellShade = shade(96f, 260f, 0xffffe7d3, 0xffe9b4aa)

    private val kidney = Path().apply {
        moveTo(104f, 139f)
        cubicTo(124f, 140f, 134f, 158f, 129f, 174f)
        cubicTo(125f, 189f, 109f, 190f, 108f, 204f)
        cubicTo(106f, 216f, 125f, 220f, 122f, 238f)
        cubicTo(118f, 263f, 91f, 279f, 66f, 268f)
        cubicTo(35f, 255f, 34f, 221f, 42f, 187f)
        cubicTo(49f, 155f, 75f, 133f, 104f, 139f)
        close()
    }
    private val gland = Path().apply {
        moveTo(60f, 151f)
        cubicTo(56f, 145f, 66f, 135f, 74f, 125f)
        cubicTo(84f, 114f, 89f, 95f, 98f, 101f)
        cubicTo(107f, 108f, 110f, 121f, 119f, 133f)
        cubicTo(122f, 140f, 117f, 145f, 109f, 144f)
        cubicTo(91f, 138f, 73f, 144f, 60f, 151f)
        close()
    }
    private val cortex = Path().apply {
        moveTo(227f, 104f)
        cubicTo(241f, 88f, 263f, 101f, 280f, 125f)
        cubicTo(294f, 145f, 302f, 173f, 317f, 198f)
        cubicTo(334f, 226f, 312f, 251f, 285f, 239f)
        cubicTo(255f, 225f, 229f, 227f, 198f, 244f)
        cubicTo(169f, 259f, 155f, 235f, 166f, 211f)
        cubicTo(181f, 179f, 198f, 136f, 227f, 104f)
        close()
    }
    private val medulla = Path().apply {
        moveTo(226f, 151f)
        cubicTo(235f, 130f, 255f, 134f, 267f, 152f)
        cubicTo(278f, 169f, 283f, 188f, 292f, 203f)
        cubicTo(299f, 216f, 290f, 222f, 276f, 216f)
        cubicTo(255f, 207f, 233f, 208f, 207f, 222f)
        cubicTo(197f, 225f, 188f, 222f, 194f, 210f)
        cubicTo(201f, 189f, 214f, 173f, 226f, 151f)
        close()
    }
    private val cortexEdge = track(cortex)
    private val medullaEdge = track(medulla)
    private val highlight = Path()
    private val nerve = Path().apply {
        moveTo(32f, 118f)
        cubicTo(71f, 115f, 77f, 84f, 110f, 86f)
        cubicTo(145f, 84f, 159f, 113f, 179f, 113f)
    }
    private val nerveBranch = Path().apply {
        moveTo(126f, 89f)
        quadTo(136f, 100f, 142f, 116f)
    }
    private val nerveTrack = track(nerve)
    private val receivingCell = Path().apply {
        moveTo(105f, 205f)
        cubicTo(101f, 166f, 124f, 139f, 159f, 134f)
        cubicTo(198f, 128f, 230f, 128f, 266f, 147f)
        cubicTo(304f, 166f, 323f, 206f, 301f, 234f)
        cubicTo(274f, 272f, 216f, 273f, 166f, 259f)
        cubicTo(134f, 249f, 111f, 237f, 105f, 205f)
        close()
    }
    private val secretingCell = Path()
    private val capillary = Path().apply {
        moveTo(28f, 235f)
        cubicTo(96f, 223f, 138f, 251f, 199f, 238f)
        cubicTo(248f, 227f, 285f, 202f, 332f, 211f)
    }
    private val capillaryTrack = track(capillary)
    private val entryTrack = track(Path().apply {
        moveTo(178f, 177f)
        cubicTo(183f, 200f, 159f, 218f, 175f, 238f)
        cubicTo(203f, 252f, 275f, 200f, 327f, 211f)
    })
    private val restingVessel = Path().apply {
        moveTo(29f, 117f)
        cubicTo(113f, 88f, 220f, 142f, 331f, 115f)
    }
    private val restingTrack = track(restingVessel)
    private val recoveryCurve = Path().apply {
        moveTo(61f, 202f)
        cubicTo(112f, 211f, 126f, 246f, 176f, 263f)
        cubicTo(219f, 279f, 264f, 279f, 313f, 280f)
    }
    private val recoveryTrack = track(recoveryCurve)

    init { tag = "atlas-function-adrenal-medulla-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> locate(c, t)
            1 -> signal(c, t)
            2 -> release(c, t)
            3 -> circulate(c, t)
            else -> settle(c, t)
        }
    }

    private fun locate(c: Canvas, t: Float) {
        tissue(c, kidney, kidneyShade, medullaInk)
        oval(c, 53f, 162f, 92f, 248f, 0xffd9989e, 0xffcc8791)
        line(c, 107f, 203f, 138f, 213f, 0xffc08286, 4f)
        tissue(c, gland, cortexShade, rim)
        line(c, 121f, 123f, 197f, 138f, guide, 1f)
        line(c, 121f, 143f, 167f, 201f, guide, 1f)
        tissue(c, cortex, cortexShade, rim)
        c.save()
        c.clipPath(cortex)
        // Faint radial striations belong to the outer rind; the medulla overlays them.
        for (i in 0..17) {
            at(cortexEdge, i / 18f) { x, y -> line(c, x, y, 244f, 186f, 0xffc48961, 1f) }
        }
        c.restore()
        tissue(c, medulla, medullaShade, medullaInk)
        for (i in 0..8) {
            val x = 215f + i * 7.5f
            val y = 182f + 12f * wave(.11f * i)
            oval(c, x - 3f, y - 2f, x + 3f, y + 2f, 0xffd4a4ad, 0xffb57d8c)
        }
        val outer = t < .47f
        val fraction = if (outer) t / .47f else (t - .47f) / .53f
        val edge = if (outer) cortexEdge else medullaEdge
        highlight.rewind()
        if (edge.getSegment(0f, edge.length * ease(fraction), highlight, true)) {
            val alpha = if (outer) ease((1f - fraction) * 4f) else 1f
            stroke(c, highlight, opacity(if (outer) 0xff985528 else cargo, alpha), 3.2f)
        }
        leader(c, string.health_atlas_adrenal_medulla_story_art_gland, 80f, 77f, 119f, 96f, 111f)
        leader(c, string.health_atlas_adrenal_medulla_story_art_kidney, 76f, 302f, 100f, 72f, 256f)
        leader(c, string.health_atlas_adrenal_medulla_story_art_cortex, 264f, 67f, 112f, 268f, 115f)
        leader(c, string.health_atlas_adrenal_medulla_story_art_medulla, 249f, 292f, 116f, 248f, 201f)
    }

    private fun signal(c: Canvas, t: Float) {
        tissue(c, receivingCell, cellShade, cellInk)
        nucleus(c, 213f, 199f, 29f, 21f)
        for (i in 0..6) vesicle(c, 131f + i * 22f, 220f + 18f * wave(i * .09f), 5.5f)
        stroke(c, nerveBranch, nerveInk, 8f)
        stroke(c, nerveBranch, sand, 5f)
        stroke(c, nerve, nerveInk, 10f)
        stroke(c, nerve, sand, 7f)
        oval(c, 132f, 108f, 152f, 123f, sand, nerveInk)
        oval(c, 167f, 105f, 190f, 121f, sand, nerveInk)
        for (i in 0..2) {
            val x = 166f + 10f * i
            val y = 133f - i * .7f
            line(c, x, y - 2f, x, y + 3f, teal, 2.6f)
        }
        for (i in 0..1) {
            val pulse = (t - .14f * i) / .68f
            if (pulse in 0f..1f) at(nerveTrack, pulse) { x, y ->
                disc(c, x, y, 3.5f, 0xff805626, 0xffffedd0)
            }
            val crossing = (t - .54f - .14f * i) / .25f
            if (crossing in 0f..1f) {
                for (j in 0..3) {
                    val x = 173f + 4f * j + 3f * crossing * wave(j * .4f)
                    disc(c, x, 120f + 10f * crossing - j % 2 * 2f, 1.8f, teal)
                }
            }
        }
        leader(c, string.health_atlas_adrenal_medulla_story_art_nerve, 94f, 60f, 150f, 86f, 92f)
        leader(c, string.health_atlas_adrenal_medulla_story_art_transmitter, 262f, 104f, 144f, 191f, 125f)
        leader(c, string.health_atlas_adrenal_medulla_story_art_cell, 246f, 300f, 155f, 249f, 251f)
    }

    private fun release(c: Canvas, t: Float) {
        val approach = ease(t / .46f)
        val pore = ease((t - .46f) / .12f)
        val center = 184f
        val mouth = 2f + 4f * pore
        // The opened vesicle is an outward-facing pocket in the cell membrane.
        secretingCell.rewind()
        with(secretingCell) {
            moveTo(54f, 172f)
            cubicTo(50f, 121f, 97f, 94f, 160f, 94f)
            cubicTo(222f, 92f, 282f, 112f, 303f, 157f)
            cubicTo(321f, 195f, 291f, 220f, 254f, 220f)
            if (pore > 0f) {
                lineTo(center + mouth, 220f)
                cubicTo(206f, 204f, 198f, 195f, center, 195f)
                cubicTo(170f, 195f, 162f, 204f, center - mouth, 220f)
            }
            lineTo(113f, 220f)
            cubicTo(79f, 220f, 59f, 204f, 54f, 172f)
            close()
        }
        tissue(c, secretingCell, cellShade, cellInk)
        nucleus(c, 241f, 151f, 31f, 22f)
        vesicle(c, 113f, 141f, 10f)
        vesicle(c, 92f, 172f, 7f)
        vesicle(c, 136f, 189f, 8f)
        vesicle(c, 151f, 127f, 6f)
        vesicle(c, 266f, 192f, 7f)
        if (pore == 0f) {
            vesicle(c, center - 15f * (1f - approach), 155f + 51f * approach, 11f)
        } else {
            for (i in 0..5) {
                val f = ease((t - .47f - i * .043f) / .31f)
                val x = center + (i - 2.5f) * (1.3f + 5f * f)
                val y = 206f + (55f + 5f * (i % 3)) * f
                hormone(c, x, y, 3.4f, 1f - .42f * f)
            }
        }
        leader(c, string.health_atlas_adrenal_medulla_story_art_vesicle, 91f, 66f, 147f, 105f, 136f)
        leader(c, string.health_atlas_adrenal_medulla_story_art_fusion, 263f, 250f, 126f, 197f, 221f)
        leader(c, string.health_atlas_adrenal_medulla_story_art_catecholamines, 147f, 311f, 174f, 173f, 271f)
    }

    private fun circulate(c: Canvas, t: Float) {
        c.save()
        c.translate(70f, 77f)
        c.scale(.38f, .38f)
        c.translate(-105f, -134f)
        tissue(c, receivingCell, cellShade, cellInk)
        nucleus(c, 183f, 199f, 25f, 19f)
        vesicle(c, 248f, 222f, 8f)
        c.restore()
        oval(c, 217f, 89f, 303f, 165f, cellShade, cellInk)
        nucleus(c, 264f, 122f, 14f, 10f)
        vesicle(c, 247f, 142f, 4.5f)
        oval(c, 135f, 94f, 216f, 179f, cellShade, cellInk)
        nucleus(c, 168f, 132f, 14f, 11f)
        vesicle(c, 188f, 151f, 6f)
        vesicle(c, 175f, 166f, 5f)
        vesicle(c, 193f, 136f, 4f)
        vessel(c, capillary, 42f)
        bloodCells(c, capillaryTrack, .74f * t)
        for (i in 0..7) {
            val phase = t * 1.08f - i * .11f + .15f
            if (phase !in 0f..1f) continue
            at(entryTrack, phase) { x, y ->
                val alpha = minOf(1f, 14f * phase, 12f * (1f - phase))
                hormone(c, x + (i % 3 - 1) * 4f, y + (i % 4 - 1.5f) * 6f * phase, 3.5f, alpha)
            }
        }
        leader(c, string.health_atlas_adrenal_medulla_story_art_cell, 152f, 66f, 147f, 161f, 105f)
        leader(c, string.health_atlas_adrenal_medulla_story_art_capillary, 75f, 293f, 112f, 86f, 243f)
        leader(c, string.health_atlas_adrenal_medulla_story_art_catecholamines, 252f, 293f, 158f, 235f, 226f)
    }

    private fun settle(c: Canvas, t: Float) {
        vessel(c, restingVessel, 42f)
        bloodCells(c, restingTrack, .52f * t)
        val remaining = 1f - ease(t)
        for (i in 0..9) {
            val strength = (2f + 8f * remaining - i).coerceIn(0f, 1f)
            val f = (.64f * t + i * .113f) % 1f
            at(restingTrack, f) { x, y ->
                hormone(c, x, y + 11f * wave(i * .39f), 3.4f, minOf(1f, 10f * f, 10f * (1f - f)) * strength)
            }
        }
        line(c, 56f, 196f, 56f, 304f, guide, 1.1f)
        arrow(c, 56f, 304f, 323f, 304f, guide)
        for (x in 60..311 step 11) line(c, x.toFloat(), 282f, x + 6f, 282f, guide, 1f)
        stroke(c, recoveryCurve, 0xffba9dbf, 2f)
        highlight.rewind()
        if (recoveryTrack.getSegment(0f, recoveryTrack.length * t, highlight, true)) {
            stroke(c, highlight, cargo, 3f)
        }
        at(recoveryTrack, t) { x, y -> disc(c, x, y, 4.1f, cargo, cream) }

        label(c, string.health_atlas_adrenal_medulla_story_art_blood, 234f, 68f, 123f)
        arrow(c, 273f, 65f, 313f, 65f, guide)
        label(c, string.health_atlas_adrenal_medulla_story_art_level, 156f, 182f, 224f)
        label(c, string.health_atlas_adrenal_medulla_story_art_baseline, 110f, 331f, 116f)
        line(c, 110f, 317f, 110f, 305f, guide, 1f)
        line(c, 110f, 303f, 110f, 282f, guide, 1f)
        label(c, string.health_atlas_adrenal_medulla_story_art_time, 296f, 331f, 86f)
    }

    private fun tissue(c: Canvas, path: Path, fill: Shader, outline: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, outline, 1.7f)
    }

    private fun nucleus(c: Canvas, x: Float, y: Float, rx: Float, ry: Float) {
        oval(c, x - rx, y - ry, x + rx, y + ry, 0xffd6b3c9, 0xffa37999)
        disc(c, x - rx * .23f, y + ry * .12f, ry * .24f, 0xffaa7f9d)
    }

    private fun vesicle(c: Canvas, x: Float, y: Float, size: Float) {
        disc(c, x, y, size, 0xfff1d7dd, 0xffa57492)
        hormone(c, x, y, size * .45f)
    }

    private fun hormone(c: Canvas, x: Float, y: Float, size: Float, alpha: Float = 1f) {
        if (alpha <= 0f) return
        c.save()
        c.rotate(45f, x, y)
        ink(opacity(cargo, alpha))
        c.drawRect(x - size * .7f, y - size * .7f, x + size * .7f, y + size * .7f, paint)
        c.restore()
    }

    private fun vessel(c: Canvas, path: Path, width: Float) {
        stroke(c, path, vesselInk, width)
        stroke(c, path, 0xffd99aa2, width - 2.6f)
        stroke(c, path, 0xfff4c4c4, width - 9f)
    }

    private fun bloodCells(c: Canvas, path: android.graphics.PathMeasure, phase: Float) {
        for (i in 0..4) {
            val f = (phase + i * .21f) % 1f
            at(path, f) { x, center ->
                val y = center + 8f * wave(i * .37f)
                val alpha = minOf(1f, f * 16f, (1f - f) * 16f)
                oval(c, x - 9f, y - 4f, x + 9f, y + 4f, opacity(0xffce7f88, alpha), opacity(vesselInk, alpha))
                line(c, x - 3f, y, x + 3f, y, opacity(0xffebb1b4, alpha), 1.3f)
            }
        }
    }

    private fun leader(c: Canvas, res: Int, x: Float, y: Float, width: Float, tx: Float, ty: Float) {
        val anchor = if (ty > y) y + 5f else y - 15f
        line(c, x, anchor, tx, ty, guide, 1f)
        disc(c, tx, ty, 2f, guide)
        label(c, res, x, y, width)
    }

    private fun ease(value: Float): Float {
        val f = value.coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }

    private fun opacity(color: Long, alpha: Float) =
        (color and 0xffffff) or ((alpha.coerceIn(0f, 1f) * 255f).toLong() shl 24)
}
