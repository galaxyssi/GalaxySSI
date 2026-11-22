package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader

internal class HealthAtlasThymusStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.THYMIC_SELECTION) {
    private val capsuleEdge = 0xffa26476
    private val medullaEdge = 0xffb48171
    private val early = 0xff805e9a
    private val selected = 0xff287c70
    private val reactive = 0xff986329
    private val vesselBlue = 0xff527f9b
    private val guide = 0xff687177
    private val cortexShade = shade(80f, 296f, 0xfff5d8df, 0xffdfa8bb)
    private val medullaShade = shade(139f, 266f, 0xffffecd6, 0xfff3ccaf)
    private val tissue = shape {
        moveTo(99f, 145f)
        cubicTo(105f, 107f, 136f, 84f, 170f, 83f)
        cubicTo(190f, 74f, 207f, 89f, 225f, 83f)
        cubicTo(263f, 73f, 290f, 98f, 302f, 129f)
        cubicTo(309f, 146f, 299f, 167f, 308f, 186f)
        cubicTo(326f, 235f, 285f, 271f, 252f, 282f)
        cubicTo(224f, 296f, 208f, 278f, 183f, 288f)
        cubicTo(146f, 302f, 113f, 277f, 99f, 251f)
        cubicTo(78f, 217f, 88f, 181f, 99f, 145f)
        close()
    }
    private val medulla = shape {
        moveTo(144f, 175f)
        cubicTo(153f, 149f, 179f, 142f, 200f, 149f)
        cubicTo(223f, 159f, 247f, 142f, 258f, 167f)
        cubicTo(269f, 187f, 251f, 195f, 260f, 211f)
        cubicTo(269f, 231f, 247f, 254f, 226f, 255f)
        cubicTo(207f, 257f, 197f, 246f, 180f, 258f)
        cubicTo(161f, 268f, 149f, 244f, 151f, 228f)
        cubicTo(153f, 205f, 132f, 199f, 144f, 175f)
        close()
    }
    private val shoulders = shape {
        moveTo(42f, 39f)
        cubicTo(44f, 50f, 34f, 50f, 25f, 54f)
        quadTo(15f, 58f, 17f, 83f)
        lineTo(17f, 102f); quadTo(52f, 108f, 86f, 102f)
        lineTo(86f, 83f); quadTo(88f, 58f, 78f, 54f)
        cubicTo(69f, 50f, 59f, 50f, 61f, 39f)
    }
    private val lung = shape {
        moveTo(43f, 58f)
        cubicTo(35f, 55f, 25f, 70f, 25f, 87f)
        cubicTo(25f, 95f, 35f, 97f, 41f, 92f)
        quadTo(46f, 87f, 43f, 58f)
        close()
    }
    private val thymicLobe = shape {
        moveTo(50f, 54f)
        cubicTo(46f, 52f, 46f, 63f, 44f, 69f)
        cubicTo(39f, 80f, 44f, 88f, 49f, 87f)
        cubicTo(53f, 84f, 54f, 61f, 50f, 54f)
        close()
    }
    private val entryVessel = shape {
        moveTo(62f, 285f)
        cubicTo(104f, 284f, 107f, 258f, 136f, 248f)
        quadTo(150f, 244f, 156f, 226f)
    }
    private val exitVessel = shape {
        moveTo(228f, 241f)
        cubicTo(224f, 266f, 248f, 273f, 260f, 283f)
        quadTo(279f, 293f, 302f, 291f)
    }
    private val enter = shape {
        moveTo(68f, 285f)
        cubicTo(104f, 282f, 107f, 258f, 136f, 248f)
        quadTo(150f, 244f, 156f, 226f)
        cubicTo(162f, 207f, 122f, 203f, 119f, 167f)
    }
    private val migrate = shape {
        moveTo(141f, 121f)
        cubicTo(125f, 153f, 128f, 174f, 149f, 183f)
        cubicTo(167f, 193f, 181f, 174f, 200f, 186f)
    }
    private val leave = shape {
        moveTo(196f, 218f)
        quadTo(214f, 214f, 228f, 241f)
        cubicTo(224f, 266f, 248f, 273f, 260f, 283f)
        quadTo(279f, 293f, 296f, 291f)
    }
    private val enterTrack = track(enter)
    private val migrateTrack = track(migrate)
    private val leaveTrack = track(leave)
    private val dashes = DashPathEffect(floatArrayOf(2.5f, 4f), 0f)
    private val head = FloatArray(2)
    private val tangent = FloatArray(2)

    init { tag = "atlas-function-thymic-selection-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        anatomy(c)
        when (step) {
            0 -> {
                travel(c, enter, enterTrack, t, early, 8f)
                cellLabel(c, 180f, early, R.string.health_atlas_thymus_story_precursor, 115f)
            }
            1 -> positiveSelection(c, t)
            2 -> {
                travel(c, migrate, migrateTrack, t, selected, 8f)
                cellLabel(c, 180f, selected, R.string.health_atlas_thymus_story_selected_cell, 115f)
            }
            3 -> negativeSelection(c, t)
            else -> {
                travel(c, leave, leaveTrack, t, selected, 9.5f)
                cellLabel(c, 180f, selected, R.string.health_atlas_thymus_story_naive_cell, 135f)
            }
        }
        anatomyLabels(c)
    }

    private fun anatomy(c: Canvas) {
        fill(c, shoulders, 0xfff5eae4)
        stroke(c, shoulders, 0xffbca7a0, 1.15f)
        fill(c, lung, 0xffc6e1df)
        c.save()
        c.scale(-1f, 1f, 51.5f, 0f)
        fill(c, lung, 0xffc6e1df)
        c.restore()
        fill(c, thymicLobe, 0xffd995aa)
        stroke(c, thymicLobe, capsuleEdge, 1.1f)
        c.save()
        c.scale(-1f, 1.04f, 51.5f, 67f)
        fill(c, thymicLobe, 0xffe5a9b8)
        stroke(c, thymicLobe, capsuleEdge, 1.1f)
        c.restore()
        line(c, 61f, 78f, 115f, 115f, 0xffa38591, 1.15f)

        pane(c, tissue, cortexShade, capsuleEdge)
        c.save()
        c.clipPath(tissue)
        for (row in 0..13) for (col in 0..15) {
            val seed = (row * 17 + col * 13) % 7
            val x = 88f + 15f * col + (row % 2) * 5f - seed
            val y = 88f + 15f * row + seed
            disc(c, x, y, 1.2f + seed * .13f, 0xffc98da6)
        }
        c.restore()
        pane(c, medulla, medullaShade, medullaEdge)
        c.save()
        c.clipPath(medulla)
        for (row in 0..5) for (col in 0..5) {
            val x = 146f + 22f * col - row % 2 * 6f
            val y = 151f + 21f * row + (col * 11 % 7)
            disc(c, x, y, 1.4f, 0xffdaab9b)
        }
        c.restore()
        vessel(c, entryVessel, capsuleEdge, 0xfff5d5d7)
        vessel(c, exitVessel, vesselBlue, 0xffd1e7ee)
    }

    private fun anatomyLabels(c: Canvas) {
        label(c, R.string.health_atlas_thymus_story_thymus, 51f, 29f, 94f)
        label(c, R.string.health_atlas_thymus_story_lobule, 157f, 51f, 111f)
        leader(c, 157f, 58f, 157f, 72f, 157f, 84f)
        label(c, R.string.health_atlas_thymus_story_cortex, 285f, 53f, 95f)
        leader(c, 285f, 60f, 285f, 82f, 272f, 113f)
        label(c, R.string.health_atlas_thymus_story_medulla, 327f, 242f, 60f)
        leader(c, 327f, 229f, 287f, 215f, 251f, 205f)
        label(c, R.string.health_atlas_thymus_story_blood_vessel, 286f, 316f, 123f)
        leader(c, 286f, 303f, 286f, 298f, 279f, 290f)
    }

    private fun positiveSelection(c: Canvas, t: Float) {
        presenter(c, 180f, 117f, capsuleEdge, 0xffedbdcb)
        val contact = ramp(t, 0f, .55f)
        val x = 119f + 27f * contact
        val y = 126f - 9f * contact
        val signal = ramp(t, .47f, .8f)
        if (signal > 0f) {
            ink(0xfff9f0c7, 2f)
            paint.alpha = (200 * (1f - signal)).toInt()
            c.drawCircle(158f, 117f, 4f + 8f * signal, paint)
        }
        ink(sienna)
        c.drawRoundRect(155f, 114f, 162f, 120f, 2f, 2f, paint)
        cell(c, x, y, 8.5f, if (t >= .72f) selected else early)
        label(c, R.string.health_atlas_thymus_story_self_mhc, 223f, 126f, 84f)
        leader(c, 208f, 111f, 184f, 96f, 160f, 113f)
        label(c, R.string.health_atlas_thymus_story_cortical_epithelium, 233f, 146f, 144f)
        leader(c, 196f, 134f, 188f, 129f, 183f, 123f)
    }

    private fun negativeSelection(c: Canvas, t: Float) {
        presenter(c, 221f, 197f, medullaEdge, 0xfff4bd9d)
        val approach = ramp(t, 0f, .46f)
        val removal = ramp(t, .46f, .89f)
        val x = 170f + 24f * approach
        val y = 186f + 6f * approach
        if (removal < 1f) {
            cell(c, x, y, 8.5f - 3f * removal, reactive, (255 * (1f - removal)).toInt())
            if (removal > 0f) {
                ink(reactive)
                paint.alpha = (185 * (1f - removal)).toInt()
                c.drawCircle(x - 4f - 5f * removal, y - 4f, 1.65f, paint)
                c.drawCircle(x + 3f, y + 4f + 6f * removal, 1.25f, paint)
            }
        }
        cell(c, 166f + 44f * t, 220f + 8f * wave(t * .5f), 8f, selected)
        cellLabel(c, 82f, reactive, R.string.health_atlas_thymus_story_self_reactive_cell, 125f)
        cellLabel(c, 255f, selected, R.string.health_atlas_thymus_story_maturing_cell, 137f)
    }

    private fun travel(c: Canvas, path: Path, measure: PathMeasure, t: Float, color: Long, radius: Float) {
        ink(color, 1.25f)
        paint.alpha = 160
        paint.pathEffect = dashes
        c.drawPath(path, paint)
        paint.pathEffect = null
        if (measure.getPosTan(measure.length, head, tangent)) {
            arrow(c, head[0] - 7f * tangent[0], head[1] - 7f * tangent[1], head[0], head[1], color)
        }
        at(measure, .025f + .90f * t) { x, y -> cell(c, x, y, radius, color) }
    }

    private fun presenter(c: Canvas, x: Float, y: Float, edge: Long, fill: Long) {
        line(c, x - 17f, y + 1f, x + 13f, y - 6f, edge, 3f)
        line(c, x - 6f, y - 15f, x + 7f, y + 12f, edge, 3f)
        line(c, x - 12f, y + 12f, x + 7f, y - 12f, edge, 3f)
        oval(c, x - 13f, y - 9f, x + 11f, y + 9f, fill, edge)
        oval(c, x - 4f, y - 3f, x + 4f, y + 4f, 0xfff4dfde, edge)
    }

    private fun cell(c: Canvas, x: Float, y: Float, r: Float, color: Long, alpha: Int = 255) {
        ink(0xfff9faf4); paint.alpha = alpha; c.drawCircle(x, y, r + 2f, paint)
        ink(color); paint.alpha = alpha; c.drawCircle(x, y, r, paint)
        ink(0xfff0f4e9); paint.alpha = alpha * 5 / 8
        c.drawOval(x - r * .62f, y - r * .52f, x + r * .29f, y + r * .42f, paint)
        ink(0xfff9faf4); paint.alpha = alpha; c.drawCircle(x + r * .43f, y - r * .35f, 1.35f, paint)
    }

    private fun cellLabel(c: Canvas, x: Float, color: Long, res: Int, width: Float) {
        val value = context.getString(res)
        paint.textSize = 13f
        val textWidth = minOf(width, paint.measureText(value))
        disc(c, x - textWidth / 2f - 9f, 338f, 3.4f, color)
        label(c, res, x, 343f, width)
    }

    private fun leader(c: Canvas, x: Float, y: Float, elbowX: Float, elbowY: Float, tx: Float, ty: Float) {
        line(c, x, y, elbowX, elbowY, guide, 1f)
        line(c, elbowX, elbowY, tx, ty, guide, 1f)
        disc(c, tx, ty, 1.6f, guide)
    }

    private fun vessel(c: Canvas, path: Path, edge: Long, lumen: Long) {
        stroke(c, path, edge, 13.5f)
        stroke(c, path, lumen, 10.5f)
    }

    private fun pane(c: Canvas, path: Path, fill: Shader, edge: Long) {
        ink(cream); paint.shader = fill; c.drawPath(path, paint); paint.shader = null
        stroke(c, path, edge, 1.8f)
    }

    private fun fill(c: Canvas, path: Path, color: Long) {
        ink(color); c.drawPath(path, paint)
    }

    private fun ramp(t: Float, start: Float, end: Float): Float {
        val p = ((t - start) / (end - start)).coerceIn(0f, 1f)
        return p * p * (3f - 2f * p)
    }

    private fun shape(build: Path.() -> Unit) = Path().apply(build)
}
