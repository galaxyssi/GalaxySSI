package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader

internal class HealthAtlasAstrocyteStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.ASTROCYTE_SUPPORT) {
    private val senderFill = shade(44f, 134f, 0xffffeada, 0xffedbb9c)
    private val receiverFill = shade(165f, 221f, 0xffffead9, 0xffe8ba9f)
    private val astrocyteFill = shade(65f, 285f, 0xffdfefda, 0xff8fcbba)
    private val vesselFill = shade(282f, 321f, 0xffffe2dd, 0xffeab6bb)
    private val sender = Path().apply {
        moveTo(34f, 54f)
        cubicTo(55f, 63f, 64f, 63f, 82f, 64f)
        cubicTo(96f, 63f, 108f, 57f, 124f, 63f)
        cubicTo(151f, 68f, 166f, 90f, 163f, 110f)
        quadTo(160f, 133f, 138f, 134f)
        cubicTo(107f, 134f, 74f, 140f, 64f, 114f)
        cubicTo(55f, 93f, 54f, 80f, 31f, 77f)
        quadTo(24f, 64f, 34f, 54f)
        close()
    }
    private val receiver = Path().apply {
        moveTo(32f, 210f)
        quadTo(55f, 204f, 59f, 186f)
        cubicTo(64f, 168f, 80f, 164f, 107f, 164f)
        lineTo(138f, 164f)
        cubicTo(157f, 163f, 164f, 176f, 155f, 193f)
        cubicTo(146f, 212f, 125f, 214f, 102f, 213f)
        cubicTo(73f, 211f, 60f, 228f, 36f, 225f)
        quadTo(29f, 220f, 32f, 210f)
        close()
    }
    private val astrocyte = Path().apply {
        moveTo(210f, 160f)
        cubicTo(219f, 145f, 234f, 133f, 232f, 115f)
        cubicTo(230f, 104f, 220f, 103f, 210f, 92f)
        quadTo(205f, 86f, 204f, 77f)
        quadTo(211f, 89f, 230f, 94f)
        quadTo(241f, 96f, 244f, 108f)
        cubicTo(251f, 91f, 245f, 81f, 263f, 71f)
        quadTo(271f, 68f, 274f, 61f)
        quadTo(276f, 72f, 263f, 79f)
        quadTo(255f, 87f, 256f, 101f)
        cubicTo(257f, 122f, 241f, 139f, 250f, 155f)
        quadTo(264f, 166f, 278f, 158f)
        cubicTo(296f, 146f, 293f, 130f, 313f, 136f)
        quadTo(323f, 139f, 330f, 133f)
        quadTo(325f, 146f, 307f, 143f)
        cubicTo(301f, 143f, 301f, 161f, 283f, 171f)
        quadTo(272f, 177f, 277f, 181f)
        quadTo(289f, 186f, 302f, 175f)
        quadTo(309f, 169f, 322f, 172f)
        quadTo(310f, 173f, 303f, 183f)
        quadTo(287f, 197f, 268f, 191f)
        cubicTo(258f, 202f, 263f, 217f, 274f, 227f)
        quadTo(283f, 235f, 285f, 246f)
        quadTo(274f, 234f, 264f, 232f)
        quadTo(252f, 229f, 246f, 214f)
        cubicTo(235f, 225f, 238f, 245f, 235f, 262f)
        quadTo(234f, 273f, 248f, 276f)
        quadTo(256f, 279f, 250f, 284f)
        quadTo(229f, 289f, 205f, 284f)
        quadTo(200f, 279f, 209f, 276f)
        quadTo(220f, 273f, 221f, 263f)
        cubicTo(224f, 245f, 215f, 233f, 221f, 213f)
        quadTo(214f, 206f, 211f, 197f)
        cubicTo(202f, 205f, 193f, 206f, 189f, 215f)
        quadTo(185f, 225f, 174f, 229f)
        quadTo(182f, 222f, 182f, 213f)
        cubicTo(185f, 199f, 204f, 194f, 203f, 182f)
        cubicTo(194f, 171f, 183f, 169f, 174f, 166f)
        quadTo(166f, 164f, 169f, 157f)
        quadTo(171f, 152f, 170f, 145f)
        quadTo(168f, 138f, 173f, 135f)
        quadTo(180f, 137f, 179f, 149f)
        cubicTo(180f, 157f, 198f, 155f, 210f, 160f)
        close()
    }
    private val vessel = Path().apply { addRoundRect(25f, 283f, 335f, 320f, 13f, 13f, Path.Direction.CW) }
    private val vesicles = arrayOf(87f to 92f, 115f to 91f, 134f to 113f)
    private val signalRoutes = List(3) { i ->
        val x = 129f + 6f * i
        val y = 149f + 3f * i
        track(Path().apply {
            moveTo(134f, 113f)
            quadTo(x, 133f, x, y)
        })
    }
    private val uptakeRoutes = List(3) { i ->
        val offset = i * 3f
        track(Path().apply {
            moveTo(129f + 6f * i, 149f + offset)
            cubicTo(152f, 144f + offset, 163f, 147f + offset, 175f, 151f + offset)
            cubicTo(185f, 163f + offset, 205f, 159f + offset, 218f, 168f + offset)
        })
    }
    private val conversionRoutes = List(3) { i ->
        val offset = i * 3f
        track(Path().apply {
            moveTo(218f, 168f + offset)
            quadTo(229f, 164f + offset, 238f + offset, 170f + offset)
        })
    }
    private val returnRoutes = List(3) { i ->
        val offset = i * 3f
        track(Path().apply {
            moveTo(238f + offset, 170f + offset)
            cubicTo(220f, 148f + offset, 216f, 117f + offset, 183f, 100f + offset)
            quadTo(159f, 88f + offset, 125f, 91f)
        })
    }
    private val bufferRoutes = listOf(
        track(Path().apply { moveTo(308f, 212f); quadTo(284f, 206f, 266f, 189f) }),
        track(Path().apply { moveTo(290f, 251f); quadTo(268f, 248f, 253f, 220f) }),
        track(Path().apply { moveTo(159f, 206f); quadTo(174f, 185f, 191f, 172f) }),
    )
    private val diamond = Path().apply {
        moveTo(0f, -5f)
        lineTo(5f, 0f)
        lineTo(0f, 5f)
        lineTo(-5f, 0f)
        close()
    }

    init { tag = "atlas-function-astrocyte-support-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        outline(c, sender, senderFill, sienna)
        outline(c, receiver, receiverFill, sienna)
        capillary(c, (step + t) / story.chapters.size)
        outline(c, astrocyte, astrocyteFill, teal)
        oval(c, 222f, 181f, 247f, 204f, 0xffa2c7b9, teal)
        oval(c, 230f, 187f, 241f, 198f, 0xff86b1a3, 0xff79a697)
        for ((x, y) in vesicles) {
            disc(c, x, y, 8f, 0xffffe8d3, sienna)
            if ((step == 0 && (x != 134f || t < .25f)) || x == 87f) {
                disc(c, x - 2f, y + 2f, 1.65f, sienna)
                disc(c, x + 2f, y - 1f, 1.65f, sienna)
            }
        }
        for (i in 0..2) {
            val x = 117f + i * 12f
            line(c, x, 163f, x - 2f, 159f, sienna, 1.4f)
            line(c, x, 163f, x + 2f, 159f, sienna, 1.4f)
        }
        when (step) {
            0 -> neuronSignal(c, t)
            1 -> for (i in uptakeRoutes.indices) {
                at(uptakeRoutes[i], travel(t, .05f + .09f * i, .62f)) { x, y -> glutamate(c, x, y) }
            }
            2 -> conversion(c, t)
            3 -> recycle(c, t)
            4 -> localBuffer(c, t)
        }
        callouts(c)
        legend(c)
    }

    private fun neuronSignal(c: Canvas, t: Float) {
        for (i in signalRoutes.indices) {
            val f = travel(t, .22f + .09f * i, .38f)
            if (f > 0f) at(signalRoutes[i], f) { x, y -> glutamate(c, x, y) }
        }
        val response = travel(t, .58f, .19f)
        if (response > 0f) {
            val x = 134f - response * 16f
            val y = 171f + response * 17f
            val r = 5f + 9f * response
            oval(c, x - r, y - r * .63f, x + r, y + r * .63f, 0xfffae0ab, 0xffc0874e)
        }
    }

    private fun conversion(c: Canvas, t: Float) {
        for (i in conversionRoutes.indices) {
            val f = travel(t, .10f + .10f * i, .51f)
            at(conversionRoutes[i], f) { x, y ->
                if (f < .58f) glutamate(c, x, y) else glutamine(c, x, y)
            }
        }
    }

    private fun recycle(c: Canvas, t: Float) {
        // The return path ends inside the sender; this is not another synaptic message.
        for (i in returnRoutes.indices) {
            val f = travel(t, .02f + .10f * i, .54f)
            if (f < 1f) at(returnRoutes[i], f) { x, y -> glutamine(c, x, y) }
            else disc(c, 112f + i * 3f, 91f + (i % 2) * 3f, 1.9f, sienna)
        }
    }

    private fun localBuffer(c: Canvas, t: Float) {
        for (i in bufferRoutes.indices) {
            val f = travel(t, .09f + .16f * i, .54f)
            if (f < 1f) at(bufferRoutes[i], f) { x, y -> potassium(c, x, y) }
        }
        potassium(c, 308f, 229f + 2f * wave(t))
        potassium(c, 168f, 184f - 2f * wave(t))
    }

    private fun capillary(c: Canvas, t: Float) {
        outline(c, vessel, vesselFill, coral)
        c.save()
        c.clipPath(vessel)
        for (i in 0..4) {
            val x = -62f + 96f * (i + t)
            val drift = wave(x / 192f)
            val y = 301f + 2.5f * drift
            c.save()
            c.rotate(14f * drift, x, y)
            oval(c, x - 12f, y - 5.5f, x + 12f, y + 5.5f, 0xffde9ca7, coral)
            oval(c, x - 5f, y - 2f, x + 5f, y + 2f, 0xffefb8bd, 0xffcd929e)
            c.restore()
        }
        c.restore()
    }

    private fun callouts(c: Canvas) {
        leader(c, 83f, 39f, 86f, 66f, sienna)
        label(c, R.string.health_atlas_astrocyte_story_sending_neuron, 83f, 34f, 151f)
        leader(c, 85f, 151f, 116f, 150f, sienna)
        label(c, R.string.health_atlas_astrocyte_story_synaptic_cleft, 46f, 155f, 70f)
        leader(c, 87f, 231f, 93f, 212f, sienna)
        label(c, R.string.health_atlas_astrocyte_story_receiving_neuron, 87f, 248f, 151f)
        leader(c, 302f, 111f, 252f, 128f, teal)
        label(c, R.string.health_atlas_astrocyte_story_astrocyte, 302f, 105f, 100f)
        leader(c, 82f, 275f, 82f, 286f, coral)
        label(c, R.string.health_atlas_astrocyte_story_capillary, 82f, 270f, 137f)
        leader(c, 284f, 271f, 241f, 280f, teal)
        label(c, R.string.health_atlas_astrocyte_story_endfoot, 294f, 266f, 112f)
    }

    private fun legend(c: Canvas) {
        glutamate(c, 33f, 339f)
        label(c, R.string.health_atlas_astrocyte_story_glutamate, 83f, 344f, 85f)
        glutamine(c, 148f, 339f)
        label(c, R.string.health_atlas_astrocyte_story_glutamine, 198f, 344f, 85f)
        potassium(c, 266f, 339f)
        label(c, R.string.health_atlas_astrocyte_story_potassium, 308f, 344f, 69f)
    }

    private fun glutamate(c: Canvas, x: Float, y: Float) = disc(c, x, y, 3.7f, sienna, cream)

    private fun glutamine(c: Canvas, x: Float, y: Float) {
        c.save()
        c.translate(x, y)
        ink(violet)
        c.drawPath(diamond, paint)
        stroke(c, diamond, cream, 1.1f)
        c.restore()
    }

    private fun potassium(c: Canvas, x: Float, y: Float) {
        disc(c, x, y, 4.9f, blue, cream)
        line(c, x - 2f, y, x + 2f, y, cream, 1f)
        line(c, x, y - 2f, x, y + 2f, cream, 1f)
    }

    private fun leader(c: Canvas, x: Float, y: Float, tx: Float, ty: Float, color: Long) {
        line(c, x, y, tx, ty, color, 1.05f)
        disc(c, tx, ty, 1.8f, color)
    }

    private fun outline(c: Canvas, path: Path, fill: Shader, border: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, border, 1.35f)
    }

    private fun travel(t: Float, start: Float, duration: Float): Float {
        val f = ((t - start) / duration).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }
}
