package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader

internal class HealthAtlasVenousReturnStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.VENOUS_RETURN) {
    private val legFill = shade(73f, 296f, 0xfffae4cd, 0xffedc4ad)
    private val soleusFill = shade(133f, 245f, 0xffefd1bb, 0xffcc8f8f)
    private val gastroFill = shade(85f, 202f, 0xfff3c2b6, 0xffd6909c)
    private val lumenFill = shade(78f, 315f, 0xffe3f4f6, 0xffacd8e2)
    private val wallInk = 0xff487588
    private val flowInk = 0xff226780
    private val leaderInk = 0xff71818a
    private val detail = Path()
    private val lumen = Path()

    private val leg = Path().apply {
        moveTo(46f, 75f)
        cubicTo(57f, 70f, 87f, 70f, 98f, 75f)
        cubicTo(94f, 105f, 119f, 123f, 113f, 162f)
        cubicTo(109f, 198f, 91f, 221f, 86f, 255f)
        cubicTo(84f, 268f, 97f, 278f, 94f, 289f)
        cubicTo(90f, 299f, 60f, 299f, 57f, 287f)
        cubicTo(54f, 276f, 64f, 267f, 60f, 252f)
        cubicTo(55f, 214f, 43f, 191f, 37f, 162f)
        cubicTo(29f, 122f, 50f, 104f, 46f, 75f)
        close()
    }
    private val soleus = Path().apply {
        moveTo(47f, 120f)
        cubicTo(34f, 155f, 49f, 195f, 63f, 226f)
        quadTo(70f, 243f, 72f, 257f)
        cubicTo(78f, 244f, 79f, 232f, 89f, 213f)
        cubicTo(104f, 186f, 113f, 146f, 98f, 120f)
        close()
    }
    private val gastro = Path().apply {
        moveTo(72f, 101f)
        cubicTo(64f, 80f, 48f, 89f, 44f, 115f)
        cubicTo(33f, 152f, 49f, 181f, 71f, 206f)
        cubicTo(89f, 184f, 108f, 152f, 102f, 119f)
        cubicTo(98f, 92f, 82f, 84f, 72f, 101f)
        close()
    }
    private val vein = Path().apply {
        moveTo(80f, 82f)
        cubicTo(78f, 113f, 90f, 140f, 85f, 170f)
        cubicTo(83f, 205f, 72f, 221f, 75f, 254f)
    }

    init { tag = "atlas-function-venous-return-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        // Unitless poses for one representative segment, not a model of the gait cycle.
        val squeeze = when (step) {
            1 -> .82f * ease(t)
            2 -> .82f + .18f * ease(t)
            3 -> 1f
            4 -> 1f - ease(t)
            else -> 0f
        }
        val proximalOpen = when (step) {
            1 -> ease(t, .32f, .86f)
            2, 3 -> 1f
            4 -> 1f - ease(t, 0f, .29f)
            else -> 0f
        }
        val distalOpen = when (step) {
            1 -> 1f - ease(t, 0f, .32f)
            2, 3 -> 0f
            4 -> ease(t, .29f, .62f)
            else -> 1f
        }

        line(c, 141f, 20f, 141f, 340f, 0xffcadbd4, 1f)
        label(c, R.string.health_atlas_venous_return_story_calf, 75f, 31f, 121f)
        label(c, R.string.health_atlas_venous_return_story_cutaway, 244f, 31f, 172f)
        drawCalf(c, squeeze, if (step == 0) t else 0f)
        label(c, R.string.health_atlas_venous_return_story_heartward, X, 57f, 120f)
        arrow(c, 270f, 84f, 270f, 66f, flowInk)
        drawMuscle(c, squeeze)
        drawVein(c, squeeze)
        c.save()
        c.clipPath(lumen)
        drawValve(c, PROXIMAL, proximalOpen)
        drawValve(c, DISTAL, distalOpen)
        c.restore()
        valveLabel(c, PROXIMAL, R.string.health_atlas_venous_return_story_proximal_valve)
        valveLabel(c, DISTAL, R.string.health_atlas_venous_return_story_distal_valve)
        when (step) {
            0 -> {
                stationRing(c, X, PROXIMAL, (t * 2f).coerceAtMost(1f))
                stationRing(c, X, DISTAL, (t * 2f - 1f).coerceAtLeast(0f))
            }
            1 -> if (squeeze > .06f) {
                arrow(c, 164f, MID, 191f + 10f * squeeze, MID, coral)
                arrow(c, 296f, MID, 269f - 10f * squeeze, MID, coral)
            }
            2, 3 -> {
                flow(c, t, PROXIMAL + 94f, 82f)
                if (step == 3) stationRing(c, X, DISTAL - 8f, t)
            }
            4 -> if (distalOpen > .86f) flow(c, t, 310f, MID - 16f, ease(t, .56f, .68f))
        }
    }

    private fun drawCalf(c: Canvas, squeeze: Float, focus: Float) {
        tissue(c, leg, legFill, 0xffb88c79)
        tissue(c, soleus, soleusFill, 0xffad7472)
        c.save()
        c.scale(1f + .075f * squeeze, 1f - .075f * squeeze, 72f, 101f)
        tissue(c, gastro, gastroFill, coral)
        for (i in -2..2) {
            val offset = i * 8f
            detail.rewind()
            detail.moveTo(72f + offset, 104f + 2f * kotlin.math.abs(i))
            detail.quadTo(72f + 1.45f * offset, 151f, 72f + .45f * offset, 190f)
            stroke(c, detail, if (i == 0) coral else 0xfff8d9ce, if (i == 0) 1.4f else 1.1f)
        }
        c.restore()
        stroke(c, vein, 0xffe1eef0, 7f)
        stroke(c, vein, wallInk, 3.2f)
        label(c, R.string.health_atlas_venous_return_story_gastrocnemius, 75f, 58f, 116f)
        line(c, 63f, 63f, 63f, 108f, leaderInk, 1f)
        disc(c, 63f, 108f, 2.1f, coral, cream)
        label(c, R.string.health_atlas_venous_return_story_soleus, 75f, 326f, 116f)
        detail.rewind()
        detail.moveTo(56f, 313f)
        detail.lineTo(27f, 284f)
        detail.lineTo(27f, 190f)
        detail.lineTo(49f, 183f)
        stroke(c, detail, leaderInk, 1f)
        disc(c, 49f, 183f, 2.1f, coral, cream)
        line(c, 96f, 169f, 151f, 169f, wallInk, 1.1f)
        ink(wallInk, 1.4f)
        c.drawCircle(85f, 169f, 11f, paint)
        stationRing(c, 85f, 169f, focus, 12f)
    }

    private fun drawMuscle(c: Canvas, squeeze: Float) {
        for (side in -1..1 step 2) {
            fun x(offset: Float) = X + side * offset
            val edge = 27f - 9f * squeeze
            detail.rewind()
            detail.moveTo(x(68f), 142f)
            detail.cubicTo(x(43f), 143f, x(edge), 154f, x(edge), MID)
            detail.cubicTo(x(edge), 209f, x(43f), 221f, x(68f), 224f)
            detail.quadTo(x(83f), MID, x(68f), 142f)
            detail.close()
            tissue(c, detail, gastroFill, 0xffbf8590)
            for (i in -1..1) {
                val y = MID + i * 13f
                line(c, x(68f), y + i * 7f, x(edge + 8f + kotlin.math.abs(i) * 5f), y, 0xfff7d9d1, 1.4f)
            }
        }
    }

    private fun drawVein(c: Canvas, squeeze: Float) {
        lumen.rewind()
        lumen.moveTo(X + 19f, 78f)
        traceWall(1f, 1f, PROXIMAL, DISTAL, 315f, squeeze)
        lumen.lineTo(X - 19f, 315f)
        traceWall(-1f, -1f, DISTAL, PROXIMAL, 78f, squeeze)
        lumen.close()
        tissue(c, lumen, lumenFill, wallInk, 2.2f)
        line(c, X - 15f, 82f, X + 15f, 82f, 0xfff4fcfd, 1.4f)
        line(c, X - 15f, 311f, X + 15f, 311f, 0xffe1f3f6, 1.4f)
    }

    private fun traceWall(side: Float, direction: Float, first: Float, last: Float, end: Float, squeeze: Float) {
        val rim = X + side * 19f
        val sinus = X + side * 27f
        val waist = X + side * (19f - 8f * squeeze)
        lumen.lineTo(rim, first - 28f * direction)
        lumen.cubicTo(rim, first - 17f * direction, sinus, first - 13f * direction, sinus, first)
        lumen.cubicTo(sinus, first + 17f * direction, waist, MID - 24f * direction, waist, MID)
        lumen.cubicTo(waist, MID + 24f * direction, sinus, last - 17f * direction, sinus, last)
        lumen.cubicTo(sinus, last + 13f * direction, rim, last + 17f * direction, rim, last + 28f * direction)
        lumen.lineTo(rim, end)
    }

    private fun drawValve(c: Canvas, y: Float, open: Float) {
        for (side in -1..1 step 2) {
            val tip = X + side * (16f * open)
            val root = X + side * 27f
            detail.rewind()
            detail.moveTo(root, y + 10f)
            detail.quadTo(X + side * (11f + 12f * open), y + 6f, tip, y - 8f)
            detail.quadTo(X + side * (9f + 10f * open), y + 14f, root, y + 10f)
            detail.close()
            ink(0xffe8f6f6)
            c.drawPath(detail, paint)
            stroke(c, detail, flowInk, 1.5f)
        }
    }

    private fun valveLabel(c: Canvas, y: Float, text: Int) {
        label(c, text, 305f, y - 13f, 87f)
        line(c, 258f, y, 297f, y, leaderInk, 1f)
        line(c, 297f, y, 305f, y - 8f, leaderInk, 1f)
    }

    private fun flow(c: Canvas, t: Float, from: Float, to: Float, strength: Float = 1f) {
        for (i in 0..2) {
            val p = (2f * t + i / 3f) % 1f
            val y = from + (to - from) * p
            ink(flowInk, 2f)
            paint.alpha = (255f * strength * minOf(1f, 6f * p, 6f * (1f - p))).toInt()
            c.drawLine(X - 4f, y + 4f, X, y, paint)
            c.drawLine(X + 4f, y + 4f, X, y, paint)
        }
    }

    private fun stationRing(c: Canvas, x: Float, y: Float, t: Float, radius: Float = 7f) {
        if (t <= 0f || t >= 1f) return
        ink(0xffac6a40, 1.7f)
        paint.alpha = (213f * 4f * t * (1f - t)).toInt()
        c.drawCircle(x, y, radius + 17f * t, paint)
    }

    private fun tissue(c: Canvas, path: Path, fill: Shader, border: Long, weight: Float = 1.45f) {
        ink(cream)
        paint.shader = fill
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, border, weight)
    }

    private fun ease(t: Float, from: Float = 0f, to: Float = 1f): Float {
        val u = ((t - from) / (to - from)).coerceIn(0f, 1f)
        return u * u * (3f - 2f * u)
    }

    private companion object {
        const val X = 230f
        const val PROXIMAL = 116f
        const val DISTAL = 246f
        const val MID = 181f
    }
}
