package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin

internal object HealthAtlasMotionSenseMotion {
    fun touchLoad(step: Int, time: Float): Float {
        val t = HealthAtlasFunctionStory.safePhase(time)
        return when (step) {
            0 -> ((t - .31f) / .69f).coerceAtLeast(0f)
            1 -> .66f + .20f * t
            2 -> .48f + .46f * t
            3 -> .91f
            else -> .91f * (1f - t / .74f).coerceAtLeast(0f)
        }
    }

    fun headHeading(t: Float) = 31f * HealthAtlasFunctionStory.safePhase(t)
    fun gazeCounterRotation(t: Float) = -headHeading(t)
    fun relativeFluid(t: Float) = -16f * sin(PI.toFloat() * HealthAtlasFunctionStory.safePhase(t))
}

internal class HealthAtlasMotionSenseStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val balance = story == HealthAtlasFunctionStory.VESTIBULAR_BALANCE
    private val shape = Path()
    private val trace = Path()
    private val skinFill = shade(115f, 234f, 0xfff7d7c6, 0xffdeac9f)
    private val dermisFill = shade(176f, 320f, 0xfff5e2c8, 0xffe4c5a8)
    private val padFill = shade(47f, 149f, 0xffffe9ca, 0xffdca78c)
    private val cellFill = shade(137f, 290f, 0xffd8e9df, 0xff8bb7ad)
    private val cupFill = shade(112f, 269f, 0xffd8e8dd, 0xff88b9b0)
    private val canal = Path().apply {
        moveTo(142f, 238f); cubicTo(100f, 206f, 130f, 120f, 178f, 107f)
        cubicTo(238f, 95f, 269f, 154f, 233f, 204f)
        cubicTo(219f, 223f, 204f, 235f, 188f, 247f)
    }
    private val lateralCanal = Path().apply {
        moveTo(164f, 245f); cubicTo(121f, 243f, 56f, 222f, 61f, 191f)
        cubicTo(66f, 162f, 124f, 173f, 158f, 195f)
        cubicTo(196f, 213f, 235f, 218f, 212f, 243f); quadTo(198f, 254f, 181f, 253f)
    }
    private val posteriorCanal = Path().apply {
        moveTo(153f, 242f); cubicTo(105f, 229f, 72f, 149f, 94f, 105f)
        cubicTo(108f, 68f, 145f, 78f, 168f, 120f)
        cubicTo(199f, 175f, 179f, 214f, 173f, 244f)
    }
    private val touchNerve = Path().apply {
        moveTo(179f, 205f); cubicTo(194f, 226f, 178f, 238f, 210f, 253f)
        cubicTo(234f, 265f, 244f, 286f, 307f, 283f)
    }
    private val nerveMeasure by lazy { track(touchNerve) }

    init { tag = if (balance) "atlas-function-vestibular-balance-art" else "atlas-function-touch-signal-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        if (balance) when (step) {
            0 -> labyrinth(c, t)
            1 -> headTurn(c, t)
            2, 3 -> hairMotion(c, step == 3, t)
            else -> gaze(c, t)
        } else when (step) {
            0, 1, 4 -> skin(c, step, t)
            2 -> channel(c, t)
            else -> firing(c, t)
        }
    }

    private fun skin(c: Canvas, step: Int, t: Float) {
        val load = HealthAtlasMotionSenseMotion.touchLoad(step, t)
        val surface = 134f
        fun deflection(x: Float): Float {
            val distance = (x - 179f) / 58f
            return 29f * load * exp(-distance * distance)
        }
        shape.rewind(); shape.moveTo(29f, surface)
        for (x in 29..331 step 2) shape.lineTo(x.toFloat(), surface + deflection(x.toFloat()))
        shape.lineTo(331f, 294f); shape.lineTo(29f, 294f); shape.close()
        paintArea(c, dermisFill, coral)
        shape.rewind(); shape.moveTo(29f, surface)
        for (x in 29..331 step 2) shape.lineTo(x.toFloat(), surface + deflection(x.toFloat()))
        for (x in 331 downTo 29 step 2) shape.lineTo(x.toFloat(), 192f + .47f * deflection(x.toFloat()))
        shape.close()
        paintArea(c, skinFill, coral)
        for (i in 0..10) {
            val x = 43f + i * 27f
            val y = 163f + deflection(x) * .77f
            oval(c, x - 10f, y - 10f, x + 10f, y + 12f, peach, coral)
            disc(c, x, y + 2f, 2.8f, 0xffa8757f)
        }
        val lift = when (step) {
            0 -> 22f * (1f - t / .31f).coerceAtLeast(0f)
            4 -> 28f * ((t - .74f) / .26f).coerceAtLeast(0f)
            else -> 0f
        }
        val objectY = surface + deflection(179f) - lift
        oval(c, 117f, objectY - 54f, 241f, objectY, padFill, sienna)
        stroke(c, touchNerve, 0xff9bbdac, 10f)
        stroke(c, touchNerve, teal, 3f)
        val ry = 17f - 4.5f * load
        oval(c, 165f, 201f - ry, 193f, 201f + ry, cellFill, teal)
        disc(c, 182f, 199f, 5.5f, violet)
        if (step != 0 || load > .35f) {
            val count = if (step == 4) (load * 5).toInt() else 3
            for (i in 0 until count) at(nerveMeasure, (t * 1.4f + .21f * i) % 1f) { x, y ->
                disc(c, x, y, 4.2f, blue, cream)
            }
        }
        label(c, R.string.health_atlas_sense_touch_surface, 73f, 103f, 122f)
        line(c, 73f, 113f, 73f, 134f, coral, 1.25f)
        label(c, R.string.health_atlas_sense_touch_merkel, 102f, 241f, 140f)
        line(c, 132f, 226f, 169f, 208f, teal, 1.25f)
        label(c, R.string.health_atlas_sense_touch_nerve, 258f, 323f, 178f)
    }

    private fun channel(c: Canvas, t: Float) {
        val load = HealthAtlasMotionSenseMotion.touchLoad(2, t)
        val gap = 11f + 20f * load
        rounded(c, 42f, 191f, 318f, 274f, 20f, 0xffdceadf)
        for (i in 0..13) {
            val x = 49f + 20f * i
            if (x in 127f..233f) continue
            for (offset in listOf(-6f, 6f)) disc(c, x, 178f + offset, 5.4f, peach, coral)
        }
        rounded(c, 127f, 153f, 179f - gap / 2, 204f, 8f, 0xff7aaea0)
        rounded(c, 179f + gap / 2, 153f, 233f, 204f, 8f, 0xff7aaea0)
        arrow(c, 138f, 141f, 138f - 15f * t, 141f, coral)
        arrow(c, 222f, 141f, 222f + 15f * t, 141f, coral)
        for (i in 0..3) {
            val dy = HealthAtlasChemicalSenseMotion.transfer(t, i, .24f)
            disc(c, 176f + (i % 2) * 9f, 113f - i * 12f + 132f * dy, 4.2f, blue, cream)
        }
        label(c, R.string.health_atlas_sense_touch_ions, 284f, 97f, 132f)
        line(c, 255f, 106f, 195f, 129f, blue, 1.25f)
        paint.textSize = 14f; ink(teal); c.drawText("PIEZO2", 180f, 301f, paint)
    }

    private fun firing(c: Canvas, t: Float) {
        val x = 52f
        val length = 255f
        val end = (length * t).toInt()
        label(c, R.string.health_atlas_sense_touch_press, 179f, 62f, 216f)
        label(c, R.string.health_atlas_sense_touch_signal, 179f, 200f, 207f)
        line(c, x, 142f, x + length, 142f, 0xffbcbcaf, 1.4f)
        line(c, x, 289f, x + length, 289f, 0xffbcbcaf, 1.4f)
        trace.rewind(); trace.moveTo(x, 142f)
        for (i in 0..end) trace.lineTo(x + i, 142f - minOf(1f, i / 41f) * 42f)
        stroke(c, trace, coral, 2.4f)
        trace.rewind(); trace.moveTo(x, 289f)
        for (i in 0..end) {
            val f = i.toFloat()
            val period = if (i < 75) 11f else 31f
            val active = i > 27 && (f % period < 2f)
            trace.lineTo(x + f, 289f - if (active) 28f else 0f)
        }
        stroke(c, trace, teal, 1.8f)
    }

    private fun labyrinth(c: Canvas, t: Float) {
        for ((curve, color) in listOf(posteriorCanal to 0xffae7892, canal to 0xff5a979d, lateralCanal to 0xff86a883)) {
            stroke(c, curve, blue, 17f); stroke(c, curve, color, 13f)
            stroke(c, curve, 0xffcce4d8, 5f)
        }
        oval(c, 142f, 229f, 210f, 268f, cupFill, blue)
        oval(c, 173f, 254f, 213f, 289f, skinFill, coral)
        val r = 5f + 3f * wave(t)
        disc(c, 186f, 249f, r, teal, cream)
        disc(c, 192f, 270f, r * .8f, sienna, cream)
        label(c, R.string.health_atlas_sense_balance_canals, 230f, 63f, 165f)
        line(c, 220f, 74f, 216f, 106f, blue, 1.25f)
        label(c, R.string.health_atlas_sense_balance_otolith, 268f, 306f, 159f)
        line(c, 241f, 288f, 209f, 272f, coral, 1.25f)
    }

    private fun headTurn(c: Canvas, t: Float) {
        val turn = HealthAtlasMotionSenseMotion.headHeading(t)
        val lag = HealthAtlasMotionSenseMotion.relativeFluid(t)
        c.save(); c.rotate(turn, 181f, 175f)
        oval(c, 83f, 82f, 279f, 269f, cellFill, teal)
        oval(c, 112f, 112f, 250f, 239f, cream, blue)
        disc(c, 260f, 176f, 14f, sand, sienna)
        c.rotate(lag, 181f, 175f)
        for (i in 0..4) {
            val angle = (i * 21f + 111f) * PI.toFloat() / 180f
            disc(c, 181f + 82f * kotlin.math.cos(angle), 175f + 79f * sin(angle), 4.4f, blue, cream)
        }
        c.restore()
        arrow(c, 113f, 65f, 203f + 54f * t, 65f, coral)
        arrow(c, 179f, 293f, 94f, 293f, blue)
        label(c, R.string.health_atlas_sense_balance_head, 181f, 43f, 180f)
        label(c, R.string.health_atlas_sense_balance_fluid, 159f, 320f, 230f)
    }

    private fun hairMotion(c: Canvas, otolith: Boolean, t: Float) {
        val deflect = 21f * t
        rounded(c, 37f, 116f, 323f, 274f, 22f, 0xffe0eee8)
        if (otolith) {
            rounded(c, 65f + deflect, 132f, 265f + deflect, 152f, 8f, sand)
            for (i in 0..7) disc(c, 75f + deflect + 25f * i, 125f - 3f * (i % 2), 5f, sienna, cream)
        } else {
            shape.rewind()
            shape.moveTo(119f, 224f); shape.cubicTo(113f + deflect, 194f, 116f + deflect, 143f, 165f + deflect, 122f)
            shape.cubicTo(196f + deflect, 118f, 226f + deflect, 160f, 224f + deflect, 189f)
            shape.lineTo(218f, 224f); shape.close()
            paintArea(c, cupFill, teal)
        }
        val count = if (otolith) 7 else 5
        val span = if (otolith) 27f else 23f
        val start = if (otolith) 83f else 124f
        for (i in 0 until count) {
            val x = start + i * span
            oval(c, x - 8.5f, 225f, x + 8.5f, 257f, peach, coral)
            disc(c, x, 244f, 3f, violet)
            for (j in -1..1) {
                shape.rewind(); shape.moveTo(x + j * 3f, 225f)
                shape.quadTo(x + j * 3f, 204f, x + j * 4f + deflect, if (otolith) 152f else 187f + j * 5f)
                stroke(c, shape, teal, 1.6f)
            }
        }
        arrow(c, 101f, 88f, 155f + 53f * t, 88f, blue)
        label(c, if (otolith) R.string.health_atlas_sense_balance_membrane else R.string.health_atlas_sense_balance_cupula_label,
            168f, 60f, 175f)
        label(c, R.string.health_atlas_sense_balance_hair, 180f, 311f, 210f)
    }

    private fun gaze(c: Canvas, t: Float) {
        val heading = HealthAtlasMotionSenseMotion.headHeading(t)
        val look = HealthAtlasMotionSenseMotion.gazeCounterRotation(t)
        c.save(); c.rotate(heading, 180f, 199f)
        oval(c, 104f, 131f, 256f, 284f, skinFill, coral)
        oval(c, 91f, 192f, 108f, 226f, peach, coral)
        oval(c, 252f, 192f, 269f, 226f, peach, coral)
        arrow(c, 180f, 190f, 180f, 116f, coral)
        for (x in listOf(151f, 209f)) {
            oval(c, x - 16f, 147f, x + 16f, 172f, cream, teal)
            c.save(); c.rotate(look, x, 162f)
            disc(c, x, 153f, 6f, teal)
            line(c, x, 147f, x, 117f, teal, 1.3f)
            c.restore()
        }
        c.restore()
        disc(c, 180f, 55f, 10f, sienna, cream)
        disc(c, 180f, 55f, 3f, cream)
        label(c, R.string.health_atlas_sense_balance_eye, 181f, 324f, 232f)
    }

    private fun paintArea(c: Canvas, fill: android.graphics.Shader, edge: Long) {
        ink(cream); paint.shader = fill; c.drawPath(shape, paint); paint.shader = null
        stroke(c, shape, edge, 1.35f)
    }
}
