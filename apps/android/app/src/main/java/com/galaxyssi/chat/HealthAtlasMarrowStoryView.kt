package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader

internal class HealthAtlasMarrowStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.MARROW_HEMATOPOIESIS) {
    private val tissueFill = shade(74f, 287f, 0xfffff0e5, 0xffebc8c3)
    private val boneFill = shade(74f, 170f, 0xffffedc9, 0xffddb994)
    private val lumenFill = shade(190f, 271f, 0xfff7ddd9, 0xffdca0a5)
    private val stemFill = shade(-27f, 30f, 0xffe4def0, 0xffb498c3)
    private val erythroblastFill = shade(-31f, 30f, 0xfff5d1df, 0xffcd8ea5)
    private val megakaryocyteFill = shade(-30f, 33f, 0xffe7deed, 0xffbd99b6)
    private val wall = 0xffad6973
    private val vesselNucleus = 0xff9e637b
    private val boneEdge = 0xffae8468
    private val leaderInk = 0xff746477
    private val redInk = 0xffa95060
    private val stemInk = 0xff775583
    private val detail = Path()

    private val trabecula = Path().apply {
        moveTo(18f, 70f)
        lineTo(160f, 70f)
        cubicTo(146f, 85f, 134f, 87f, 118f, 89f)
        cubicTo(94f, 91f, 94f, 116f, 76f, 124f)
        cubicTo(56f, 132f, 46f, 122f, 42f, 153f)
        quadTo(39f, 170f, 18f, 180f)
        close()
        moveTo(287f, 70f)
        lineTo(342f, 70f)
        lineTo(342f, 157f)
        quadTo(325f, 152f, 320f, 132f)
        cubicTo(316f, 111f, 292f, 107f, 287f, 70f)
        close()
    }
    private val stroma = Path().apply {
        moveTo(72f, 171f)
        cubicTo(88f, 161f, 96f, 148f, 115f, 145f)
        quadTo(130f, 143f, 146f, 131f)
        quadTo(139f, 143f, 124f, 151f)
        quadTo(120f, 156f, 140f, 173f)
        quadTo(125f, 168f, 115f, 159f)
        cubicTo(99f, 159f, 88f, 169f, 72f, 171f)
        close()
    }
    private val lumen = Path().apply {
        moveTo(18f, vesselY(18f) - 26f)
        for (x in 22..342 step 4) lineTo(x.toFloat(), vesselY(x.toFloat()) - 26f)
        for (x in 342 downTo 18 step 4) lineTo(x.toFloat(), vesselY(x.toFloat()) + 26f)
        close()
    }
    private val erythroidRoute = route(110f, 174f, 164f, 115f, 226f, 106f)
    private val megakaryocyteRoute = route(110f, 190f, 164f, 234f, 225f, 245f)
    private val erythroidMeasure = track(erythroidRoute)
    private val megakaryocyteMeasure = track(megakaryocyteRoute)

    init { tag = "atlas-function-marrow-hematopoiesis-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> drawNiche(c, t)
            1 -> drawSelfRenewal(c, t)
            2 -> drawCommitment(c, t)
            3 -> drawMaturation(c, t)
            4 -> drawRelease(c, t)
        }
    }

    private fun drawNiche(c: Canvas, t: Float) {
        drawMarrow(c, t * .54f, release = false)
        val focus = progress(t, .06f, .84f)
        ink(0xfff9eaf4)
        paint.alpha = (62f + 135f * focus).toInt()
        c.drawOval(145f, 115f, 231f, 192f, paint)
        stem(c, 187f, 156f, 22f)
        callout(c, R.string.health_atlas_marrow_story_label_bone, 72f, 43f, 99f, 61f, 97f)
        callout(c, R.string.health_atlas_marrow_story_label_stroma, 173f, 43f, 85f, 119f, 145f)
        callout(c, R.string.health_atlas_marrow_story_label_stem, 280f, 43f, 117f, 201f, 139f)
        labelSinusoid(c)
    }

    private fun drawSelfRenewal(c: Canvas, t: Float) {
        val separation = progress(t, .14f, .86f)
        val x = 108f
        val y = 170f
        val distance = 132f * separation
        val radius = 34f - 6f * separation
        val right = x + distance
        if (distance < 2f * radius) {
            // The shared membrane narrows as the two daughter cells separate.
            val mid = (x + right) * .5f
            val neck = maxOf(2f, radius - distance * .5f)
            val bend = minOf(radius * .55f, distance * .38f)
            val arc = radius * .55f
            detail.rewind()
            detail.moveTo(x, -radius)
            detail.cubicTo(x + bend, -radius, mid - bend, -neck, mid, -neck)
            detail.cubicTo(mid + bend, -neck, right - bend, -radius, right, -radius)
            detail.cubicTo(right + arc, -radius, right + radius, -arc, right + radius, 0f)
            detail.cubicTo(right + radius, arc, right + arc, radius, right, radius)
            detail.cubicTo(right - bend, radius, mid + bend, neck, mid, neck)
            detail.cubicTo(mid - bend, neck, x + bend, radius, x, radius)
            detail.cubicTo(x - arc, radius, x - radius, arc, x - radius, 0f)
            detail.cubicTo(x - radius, -arc, x - arc, -radius, x, -radius)
            detail.close()
            c.save()
            c.translate(0f, y)
            filled(c, detail, stemFill, stemInk)
            c.restore()
            val splitting = progress(t, .13f, .52f)
            stemNucleus(c, x, y, 19f - 5f * splitting)
            if (splitting > 0f) stemNucleus(c, right, y, radius * .48f * splitting)
        } else {
            stem(c, x, y, radius)
            stem(c, right, y, radius)
        }
        callout(c, R.string.health_atlas_marrow_story_label_stem, 108f, 105f, 132f, 108f, 146f)
        line(c, 79f, 231f, 79f, 239f, leaderInk, 1.15f)
        line(c, 79f, 239f, 272f, 239f, leaderInk, 1.15f)
        line(c, 272f, 239f, 272f, 231f, leaderInk, 1.15f)
        callout(c, R.string.health_atlas_marrow_story_label_pool, 175f, 267f, 155f, 175f, 239f)
    }

    private fun drawCommitment(c: Canvas, t: Float) {
        drawRoute(c, erythroidRoute, erythroidMeasure, progress(t, .04f, .70f), redInk)
        drawRoute(c, megakaryocyteRoute, megakaryocyteMeasure, progress(t, .25f, .92f), stemInk)
        stem(c, 74f, 181f, 27f)
        erythroblast(c, 268f, 104f, 23f, 11f)
        megakaryocyte(c, 268f, 248f)
        callout(c, R.string.health_atlas_marrow_story_label_stem, 75f, 126f, 120f, 75f, 154f)
        callout(c, R.string.health_atlas_marrow_story_label_red_lineage, 261f, 46f, 172f, 268f, 81f)
        callout(c, R.string.health_atlas_marrow_story_label_mega_lineage, 249f, 306f, 197f, 268f, 279f)
        label(c, R.string.health_atlas_marrow_story_label_illustrative, 180f, 340f, 260f)
    }

    private fun drawMaturation(c: Canvas, t: Float) {
        arrow(c, 111f, 169f, 140f, 169f, leaderInk)
        arrow(c, 222f, 169f, 258f, 169f, leaderInk)
        erythroblast(c, 71f, 169f, 30f, 19f)
        val condense = progress(t, .03f, .44f)
        val extrude = progress(t, .29f, .87f)
        val r = 24f - 4f * condense
        val x = 176f - 3f * extrude
        val nx = 176f + 29f * extrude
        val ny = 169f + 13f * extrude
        oval(c, x - r, 169f - r, x + r, 169f + r, 0xffe7a7b2, redInk)
        val nr = 12f - 5f * condense
        if (extrude > .55f) disc(c, nx, ny, nr + 2.4f, 0xffe5a5ad, redInk)
        stemNucleus(c, nx, ny, nr)
        reticulocyte(c, 289f, 169f, 19f)
        callout(c, R.string.health_atlas_marrow_story_label_early, 72f, 102f, 108f, 71f, 139f)
        callout(c, R.string.health_atlas_marrow_story_label_late, 180f, 102f, 106f, 176f, 147f)
        callout(c, R.string.health_atlas_marrow_story_label_reticulocyte, 289f, 102f, 108f, 289f, 154f)
    }

    private fun drawRelease(c: Canvas, t: Float) {
        drawMarrow(c, t * 1.15f, release = true)
        reticulocyte(c, 110f, 127f, 10f)
        releaseCell(c, t, 156f, 165f, 179f, 330f)
        releaseCell(c, (t - .28f) / .72f, 137f, 175f, 157f, 265f)
        callout(c, R.string.health_atlas_marrow_story_label_reticulocyte, 103f, 43f, 130f, 108f, 120f)
        callout(c, R.string.health_atlas_marrow_story_label_lining, 257f, 43f, 132f, 235f, vesselY(235f) - 26f)
        labelSinusoid(c)
    }

    private fun releaseCell(c: Canvas, t: Float, fromX: Float, fromY: Float, entryX: Float, endX: Float) {
        val approach = progress(t, 0f, .25f)
        val cross = progress(t, .18f, .51f)
        val flow = ((t - .44f) / .56f).coerceIn(0f, 1f)
        val x = fromX + (entryX - fromX) * approach + (endX - entryX) * flow
        val y = fromY + (vesselY(x) - 4f - fromY) * cross
        val squeeze = 4f * cross * (1f - cross)
        c.save()
        c.translate(x, y)
        c.scale(1f - .28f * squeeze, 1f + .16f * squeeze)
        reticulocyte(c, 0f, 0f, 11f)
        c.restore()
    }

    private fun drawMarrow(c: Canvas, flow: Float, release: Boolean) {
        c.save()
        c.clipRect(22f, 74f, 338f, 284f)
        ink(cream); paint.shader = tissueFill
        c.drawRect(22f, 74f, 338f, 284f, paint)
        paint.shader = null

        for (i in 0 until marrowCells.size step 2) {
            val x = marrowCells[i]
            val y = marrowCells[i + 1]
            val radius = 5.5f + (i % 6)
            disc(c, x, y, radius, 0xffeac1c7, 0xffcd9da9)
            disc(c, x - 1f, y, radius * .44f, 0xffb587a0)
        }
        filled(c, trabecula, boneFill, boneEdge)
        for (i in 0..5) {
            val x = 34f + i * 9f
            val y = 124f - i * 7f
            oval(c, x - 4f, y - 1.8f, x + 3f, y + 1.8f, 0xffcfa587, 0xffc4987b)
        }
        ink(0xffd3b8b3); c.drawPath(stroma, paint)
        stroke(c, stroma, 0xff9e7884, 1f)
        oval(c, 104f, 149f, 120f, 155f, 0xffa8839b, leaderInk)

        filled(c, lumen, lumenFill, wall)
        for (x in 40..332 step 29) {
            val fx = x.toFloat()
            val y = vesselY(fx)
            endothelium(c, fx, y - 25f)
            endothelium(c, fx - 9f, vesselY(fx - 9f) + 25f)
        }
        c.save()
        c.clipPath(lumen)
        for (i in 0..6) {
            val x = 8f + 344f * ((flow * .55f + i / 7f) % 1f)
            val y = vesselY(x) + if (i % 2 == 0) 11f else -11f
            redCell(c, x, y, if (release) 7f else 9f, i * 13f - 35f)
        }
        c.restore()
        c.restore()
        ink(boneEdge, 1f); c.drawRect(22f, 74f, 338f, 284f, paint)
    }

    private fun stem(c: Canvas, x: Float, y: Float, r: Float) {
        c.save()
        c.translate(x, y)
        oval(c, -r, -r, r, r, stemFill, stemInk)
        stemNucleus(c, -r * .08f, 0f, r * .52f)
        disc(c, r * .68f, -r * .32f, r * .09f, 0xffa287b6)
        disc(c, r * .05f, r * .77f, r * .065f, 0xffa287b6)
        c.restore()
    }

    private fun stemNucleus(c: Canvas, x: Float, y: Float, r: Float) {
        oval(c, x - r, y - r * 1.02f, x + r, y + r * 1.02f, 0xff956b9b, 0xff744d7d)
        disc(c, x - r * .23f, y - r * .19f, r * .23f, 0xffc9acd2)
    }

    private fun erythroblast(c: Canvas, x: Float, y: Float, r: Float, nucleus: Float) {
        c.save()
        c.translate(x, y)
        oval(c, -r, -r, r, r, erythroblastFill, redInk)
        stemNucleus(c, -3f, 0f, nucleus)
        c.restore()
    }

    private fun megakaryocyte(c: Canvas, x: Float, y: Float) {
        c.save()
        c.translate(x, y)
        oval(c, -34f, -31f, 34f, 31f, megakaryocyteFill, stemInk)
        detail.rewind()
        detail.moveTo(-16f, -3f)
        detail.cubicTo(-24f, -18f, -6f, -23f, -1f, -15f)
        detail.cubicTo(9f, -28f, 22f, -11f, 14f, -3f)
        detail.cubicTo(29f, 7f, 11f, 22f, 4f, 14f)
        detail.cubicTo(-7f, 26f, -26f, 13f, -16f, -3f)
        detail.close()
        ink(0xff93688f); c.drawPath(detail, paint)
        stroke(c, detail, stemInk, 1.15f)
        for (i in 0..8) {
            val angle = i / 9f
            disc(c, 25f * wave(angle + .25f), 24f * wave(angle), 1.6f, 0xffab81a0)
        }
        c.restore()
    }

    private fun redCell(c: Canvas, x: Float, y: Float, r: Float, tilt: Float) {
        c.save()
        c.rotate(tilt, x, y)
        oval(c, x - r, y - .65f * r, x + r, y + .65f * r, 0xffd28185, redInk)
        oval(c, x - .49f * r, y - .23f * r, x + .49f * r, y + .23f * r, 0xffedb1ac, 0xffd38588)
        c.restore()
    }

    private fun reticulocyte(c: Canvas, x: Float, y: Float, r: Float) {
        oval(c, x - r, y - .8f * r, x + r, y + .8f * r, 0xffe49aa5, redInk)
        for (i in 0..4) {
            val dx = (i - 2) * r * .24f
            disc(c, x + dx, y + .36f * r * wave(i * .29f + .08f), r * .074f, stemInk)
        }
    }

    private fun endothelium(c: Canvas, x: Float, y: Float) =
        oval(c, x - 7f, y - 2.35f, x + 7f, y + 2.35f, 0xffc18393, vesselNucleus)

    private fun vesselY(x: Float) = 231f + 11f * wave((x - 20f) / 320f + .13f)

    private fun labelSinusoid(c: Canvas) =
        callout(c, R.string.health_atlas_marrow_story_label_sinusoid, 238f, 320f, 148f, 239f, vesselY(239f) + 15f)

    private fun callout(c: Canvas, res: Int, x: Float, baseline: Float, width: Float, tx: Float, ty: Float) {
        val tail = baseline + if (ty > baseline) 6f else -15f
        line(c, x, tail, tx, ty, leaderInk, 1.05f)
        disc(c, tx, ty, 2f, leaderInk, cream)
        label(c, res, x, baseline, width)
    }

    private fun filled(c: Canvas, path: Path, fill: Shader, edge: Long) {
        ink(cream); paint.shader = fill; c.drawPath(path, paint); paint.shader = null
        stroke(c, path, edge, 1.3f)
    }

    private fun route(hx: Float, hy: Float, cx: Float, cy: Float, tipX: Float, tipY: Float) =
        Path().apply { moveTo(105f, 181f); cubicTo(hx, hy, cx, cy, tipX, tipY) }

    private fun drawRoute(c: Canvas, route: Path, measure: PathMeasure, f: Float, color: Long) {
        stroke(c, route, 0xffb9adb6, 1.45f)
        detail.rewind()
        if (measure.getSegment(0f, measure.length * f, detail, true)) stroke(c, detail, color, 2.7f)
        at(measure, .96f) { x, y ->
            at(measure, 1f) { tipX, tipY -> arrow(c, x, y, tipX, tipY, if (f >= .96f) color else leaderInk) }
        }
    }

    private fun progress(t: Float, start: Float, end: Float): Float {
        val f = ((t - start) / (end - start)).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }

    private companion object {
        val marrowCells = floatArrayOf(
            86f, 105f, 142f, 99f, 165f, 84f, 201f, 105f, 235f, 97f, 272f, 96f, 291f, 115f,
            51f, 141f, 73f, 140f, 150f, 112f, 226f, 130f, 250f, 116f, 278f, 141f, 310f, 148f,
            39f, 187f, 62f, 196f, 87f, 182f, 107f, 197f, 226f, 176f, 252f, 154f, 279f, 177f,
            309f, 184f, 328f, 174f, 297f, 203f, 78f, 279f, 126f, 280f, 267f, 268f, 304f, 279f,
        )
    }
}
