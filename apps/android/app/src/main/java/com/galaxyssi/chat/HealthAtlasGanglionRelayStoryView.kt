package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader
import com.galaxyssi.chat.R.string
import kotlin.math.abs

internal object HealthAtlasGanglionRelayMotion {
    fun sensory(t: Float) = window(t, .05f, .94f)
    fun preganglionic(t: Float) = window(t, .05f, .43f)
    fun contact(t: Float) = (1f - abs(HealthAtlasFunctionStory.safePhase(t) - .51f) / .08f).coerceIn(0f, 1f)
    fun postganglionic(t: Float) = window(t, .59f, .95f)
    fun satellite(t: Float) = 1f - abs(2f * HealthAtlasFunctionStory.safePhase(t) - 1f)

    private fun window(t: Float, start: Float, end: Float): Float {
        val f = ((HealthAtlasFunctionStory.safePhase(t) - start) / (end - start)).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }
}

internal class HealthAtlasGanglionRelayStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.GANGLION_RELAY) {
    private val nerveEdge = 0xff996a64
    private val softNerve = 0xffc49a83
    private val gliaEdge = 0xff4f8178
    private val nucleusEdge = 0xff956277
    private val sensoryInk = 0xff326c78
    private val preInk = 0xff96602c
    private val postInk = 0xff91566d
    private val guide = 0xff617473
    private val capsuleFill = shade(90f, 257f, 0xfffcf4e7, 0xffe8cfb6)
    private val cordFill = shade(116f, 229f, 0xfff6dfcd, 0xffd5aaad)
    private val somaFill = shade(91f, 214f, 0xffffecd6, 0xffdfa295)
    private val postFill = shade(126f, 226f, 0xfff4d5c9, 0xffcd929a)
    private val gliaFill = shade(94f, 245f, 0xffd7eadd, 0xff91beb0)
    private val localSomaFill = shade(111f, 228f, 0xffffedda, 0xffe2ac9d)

    private val sensoryCapsule = shape {
        moveTo(66f, 162f)
        cubicTo(103f, 168f, 101f, 118f, 133f, 94f)
        cubicTo(167f, 70f, 224f, 82f, 242f, 120f)
        cubicTo(253f, 141f, 259f, 162f, 291f, 172f)
        lineTo(291f, 197f)
        cubicTo(263f, 199f, 259f, 223f, 220f, 240f)
        cubicTo(178f, 258f, 125f, 238f, 108f, 210f)
        quadTo(96f, 189f, 66f, 191f)
        close()
    }
    private val cord = shape {
        moveTo(31f, 110f)
        cubicTo(14f, 119f, 16f, 150f, 20f, 168f)
        cubicTo(24f, 182f, 13f, 205f, 22f, 222f)
        cubicTo(37f, 250f, 71f, 238f, 78f, 215f)
        cubicTo(82f, 200f, 79f, 187f, 78f, 174f)
        cubicTo(74f, 157f, 82f, 135f, 67f, 118f)
        quadTo(50f, 101f, 31f, 110f)
        close()
    }
    private val dorsalHorn = shape {
        moveTo(36f, 133f)
        cubicTo(44f, 145f, 46f, 166f, 49f, 173f)
        cubicTo(54f, 169f, 54f, 150f, 62f, 145f)
        cubicTo(65f, 158f, 60f, 175f, 61f, 185f)
        cubicTo(61f, 195f, 69f, 204f, 65f, 215f)
        cubicTo(59f, 221f, 56f, 211f, 50f, 196f)
        cubicTo(45f, 191f, 45f, 208f, 36f, 217f)
        cubicTo(29f, 216f, 30f, 203f, 36f, 191f)
        cubicTo(40f, 180f, 30f, 151f, 36f, 133f)
        close()
    }
    private val sensoryFibers = shape {
        moveTo(70f, 172f); cubicTo(127f, 177f, 131f, 153f, 164f, 156f)
        cubicTo(210f, 159f, 231f, 181f, 286f, 179f)
        moveTo(70f, 186f); cubicTo(114f, 185f, 132f, 211f, 180f, 211f)
        cubicTo(227f, 211f, 243f, 190f, 286f, 191f)
        moveTo(94f, 186f); cubicTo(147f, 181f, 125f, 204f, 191f, 204f)
        quadTo(221f, 203f, 241f, 195f)
    }
    private val sensoryAxon = shape {
        moveTo(334f, 187f)
        cubicTo(279f, 187f, 239f, 185f, 192f, 183f)
        cubicTo(152f, 181f, 107f, 182f, 76f, 176f)
        quadTo(65f, 174f, 60f, 162f)
    }
    private val sensoryStem = shape {
        moveTo(192f, 183f)
        cubicTo(180f, 182f, 179f, 170f, 179f, 162f)
        quadTo(180f, 151f, 176f, 143f)
    }

    private val autonomicCapsule = shape {
        moveTo(72f, 144f)
        cubicTo(112f, 133f, 118f, 98f, 162f, 96f)
        cubicTo(214f, 87f, 244f, 104f, 267f, 144f)
        quadTo(283f, 167f, 302f, 172f)
        lineTo(302f, 197f)
        quadTo(282f, 195f, 259f, 220f)
        cubicTo(220f, 264f, 140f, 269f, 107f, 211f)
        quadTo(93f, 173f, 72f, 172f)
        close()
    }
    private val dendrites = shape {
        moveTo(214f, 184f); cubicTo(195f, 172f, 189f, 147f, 179f, 132f)
        quadTo(174f, 124f, 165f, 120f)
        moveTo(190f, 152f); quadTo(196f, 135f, 188f, 124f)
        moveTo(209f, 198f); cubicTo(188f, 198f, 180f, 216f, 157f, 222f)
        moveTo(186f, 209f); quadTo(178f, 203f, 168f, 204f)
        moveTo(220f, 165f); cubicTo(215f, 151f, 227f, 139f, 225f, 127f)
        moveTo(225f, 137f); quadTo(235f, 132f, 238f, 124f)
        moveTo(226f, 207f); quadTo(229f, 223f, 245f, 227f)
    }
    private val input = shape {
        moveTo(26f, 153f)
        cubicTo(67f, 153f, 89f, 144f, 112f, 148f)
        cubicTo(128f, 151f, 134f, 155f, 143f, 160f)
    }
    private val terminal = shape {
        moveTo(135f, 153f)
        cubicTo(143f, 146f, 154f, 151f, 154f, 160f)
        cubicTo(154f, 168f, 151f, 171f, 147f, 171f)
        quadTo(138f, 172f, 135f, 164f)
        close()
    }
    private val receivingDendrite = shape {
        moveTo(166f, 163f)
        cubicTo(189f, 164f, 187f, 181f, 207f, 189f)
    }
    private val output = shape {
        moveTo(231f, 187f)
        cubicTo(255f, 177f, 279f, 179f, 302f, 187f)
        quadTo(319f, 192f, 334f, 190f)
    }

    private val sheathContour = shape {
        moveTo(166f, 91f)
        cubicTo(205f, 91f, 235f, 122f, 236f, 163f)
        cubicTo(238f, 208f, 207f, 244f, 165f, 245f)
        cubicTo(123f, 245f, 92f, 214f, 92f, 172f)
        cubicTo(90f, 128f, 122f, 93f, 166f, 91f)
        close()
    }
    private val gliaBorders = shape {
        moveTo(135f, 97f); quadTo(135f, 106f, 141f, 111f)
        moveTo(214f, 112f); quadTo(211f, 121f, 206f, 125f)
        moveTo(235f, 183f); quadTo(228f, 181f, 222f, 183f)
        moveTo(189f, 241f); quadTo(188f, 232f, 183f, 227f)
        moveTo(111f, 223f); quadTo(119f, 221f, 124f, 213f)
        moveTo(94f, 153f); quadTo(103f, 153f, 108f, 155f)
    }
    private val matrix = shape {
        moveTo(218f, 114f); quadTo(237f, 124f, 249f, 152f)
        moveTo(229f, 218f); quadTo(253f, 208f, 262f, 215f)
        moveTo(239f, 227f); quadTo(258f, 221f, 273f, 225f)
        moveTo(245f, 155f); quadTo(259f, 143f, 278f, 142f)
    }

    private val sensoryTrack = track(sensoryAxon)
    private val inputTrack = track(input)
    private val outputTrack = track(output)

    init { tag = "atlas-function-ganglion-relay-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            HealthAtlasGanglionRelayAssignment.SENSORY -> sensory(c, t)
            HealthAtlasGanglionRelayAssignment.AUTONOMIC -> autonomic(c, t)
            HealthAtlasGanglionRelayAssignment.SATELLITE -> satellite(c, t)
        }
    }

    private fun sensory(c: Canvas, t: Float) {
        tissue(c, sensoryCapsule, capsuleFill, softNerve)
        stroke(c, sensoryFibers, softNerve, 1.5f)
        quietSoma(c, 129f, 139f, 12f, 14f)
        quietSoma(c, 222f, 137f, 13f, 16f)
        quietSoma(c, 152f, 220f, 15f, 11f)
        quietSoma(c, 204f, 227f, 14f, 13f)
        tissue(c, cord, cordFill, nerveEdge)
        ink(0xffbc929f)
        c.drawPath(dorsalHorn, paint)
        fiber(c, sensoryStem, sensoryInk, 4.5f)
        fiber(c, sensoryAxon, sensoryInk, 4.5f)
        arrow(c, 324f, 205f, 296f, 205f, sensoryInk)
        arrow(c, 111f, 200f, 83f, 196f, sensoryInk)
        oval(c, 147f, 98f, 201f, 151f, 0xffb6d5c5, gliaEdge)
        oval(c, 151f, 102f, 197f, 147f, somaFill, nerveEdge)
        nucleus(c, 173f, 123f, 9f)
        val f = motion.sensory(t)
        if (f > 0f && f < 1f) at(sensoryTrack, f) { x, y -> disc(c, x, y, 4.7f, sensoryInk, cream) }

        callout(c, string.health_atlas_ganglion_relay_art_drg, 83f, 62f, 142f, 131f, 96f)
        callout(c, string.health_atlas_ganglion_relay_art_soma, 269f, 91f, 151f, 194f, 111f)
        callout(c, string.health_atlas_ganglion_relay_art_junction, 193f, 272f, 110f, 192f, 183f)
        callout(c, string.health_atlas_ganglion_relay_art_central, 78f, 315f, 142f, 47f, 224f)
        callout(c, string.health_atlas_ganglion_relay_art_peripheral, 284f, 315f, 140f, 322f, 187f)
    }

    private fun autonomic(c: Canvas, t: Float) {
        tissue(c, autonomicCapsule, capsuleFill, softNerve)
        quietSoma(c, 138f, 123f, 10f, 12f)
        quietSoma(c, 128f, 201f, 12f, 16f)
        quietSoma(c, 191f, 238f, 14f, 11f)
        quietSoma(c, 254f, 149f, 11f, 14f)
        stroke(c, dendrites, 0xffa56a7d, 3.7f)
        fiber(c, receivingDendrite, postInk, 5.6f)
        fiber(c, output, postInk, 4.2f)
        oval(c, 192f, 161f, 242f, 214f, postFill, postInk)
        nucleus(c, 215f, 185f, 9.5f)
        fiber(c, input, preInk, 4.2f)
        tissue(c, terminal, capsuleFill, preInk)
        disc(c, 146f, 158f, 1.6f, preInk)
        disc(c, 149f, 164f, 1.5f, preInk)
        val incoming = motion.preganglionic(t)
        val outgoing = motion.postganglionic(t)
        val contact = motion.contact(t)
        if (incoming > 0f && incoming < 1f) at(inputTrack, incoming) { x, y -> disc(c, x, y, 4.7f, preInk, cream) }
        if (contact > 0f) {
            disc(c, 158f, 159f, 1.55f * contact, preInk)
            disc(c, 161f, 164f, 1.45f * contact, preInk)
        }
        if (outgoing > 0f && outgoing < 1f) at(outputTrack, outgoing) { x, y -> disc(c, x, y, 4.7f, postInk, cream) }
        arrow(c, 37f, 172f, 65f, 169f, preInk)
        arrow(c, 299f, 207f, 327f, 210f, postInk)

        callout(c, string.health_atlas_ganglion_relay_art_pre, 88f, 60f, 149f, 68f, 150f)
        callout(c, string.health_atlas_ganglion_relay_art_synapse, 189f, 83f, 120f, 159f, 160f)
        callout(c, string.health_atlas_ganglion_relay_art_dendrite, 85f, 277f, 130f, 177f, 165f)
        callout(c, string.health_atlas_ganglion_relay_art_post_soma, 229f, 281f, 152f, 227f, 198f)
        callout(c, string.health_atlas_ganglion_relay_art_post, 277f, 315f, 152f, 322f, 191f)
    }

    private fun satellite(c: Canvas, t: Float) {
        stroke(c, matrix, 0xffb5a995, 1.3f)
        oval(c, 246f, 151f, 317f, 214f, gliaFill, gliaEdge)
        oval(c, 252f, 156f, 311f, 208f, postFill, nerveEdge)
        nucleus(c, 284f, 182f, 8.5f)
        tissue(c, sheathContour, gliaFill, gliaEdge)
        stroke(c, gliaBorders, gliaEdge, 1.1f)
        val contrast = (215 - 32 * motion.satellite(t)).toLong()
        val space = 0xffffe700L or contrast
        oval(c, 106f, 105f, 223f, 230f, space, gliaEdge)
        oval(c, 112f, 111f, 217f, 224f, localSomaFill, nerveEdge)
        nucleus(c, 161f, 162f, 18.5f)
        oval(c, 162f, 94f, 178f, 102f, gliaEdge, 0xff577a72)
        oval(c, 224f, 153f, 233f, 168f, gliaEdge, 0xff577a72)
        oval(c, 148f, 232f, 166f, 241f, gliaEdge, 0xff577a72)
        oval(c, 95f, 176f, 103f, 189f, gliaEdge, 0xff577a72)

        callout(c, string.health_atlas_ganglion_relay_art_sheath, 91f, 57f, 150f, 122f, 111f)
        callout(c, string.health_atlas_ganglion_relay_art_soma, 266f, 66f, 151f, 203f, 144f)
        callout(c, string.health_atlas_ganglion_relay_art_glial_nucleus, 79f, 277f, 133f, 99f, 182f)
        callout(c, string.health_atlas_ganglion_relay_art_perisomatic, 226f, 309f, 180f, 198f, 216f)
        callout(c, string.health_atlas_ganglion_relay_art_matrix, 281f, 258f, 145f, 249f, 220f)
    }

    private fun quietSoma(c: Canvas, x: Float, y: Float, rx: Float, ry: Float) {
        oval(c, x - rx, y - ry, x + rx, y + ry, 0xffefd4bd, 0xffbf9b85)
        disc(c, x - 1f, y - 1f, ry * .27f, 0xffc299a0)
    }

    private fun nucleus(c: Canvas, x: Float, y: Float, radius: Float) {
        disc(c, x, y, radius, 0xffcf9ead, nucleusEdge)
        disc(c, x - radius * .2f, y - radius * .2f, radius * .27f, nucleusEdge)
    }

    private fun fiber(c: Canvas, p: Path, color: Long, width: Float) {
        stroke(c, p, cream, width + 3.1f)
        stroke(c, p, color, width)
    }

    private fun tissue(c: Canvas, p: Path, fill: Shader, edge: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(p, paint)
        paint.shader = null
        stroke(c, p, edge, 1.45f)
    }

    private fun callout(c: Canvas, id: Int, x: Float, y: Float, width: Float, tx: Float, ty: Float) {
        line(c, x, y + if (ty > y) 5f else -14f, tx, ty, guide, 1f)
        disc(c, tx, ty, 1.65f, guide, cream)
        label(c, id, x, y, width)
    }

    private fun shape(block: Path.() -> Unit) = Path().apply(block)

    private companion object {
        val motion = HealthAtlasGanglionRelayMotion
    }
}
