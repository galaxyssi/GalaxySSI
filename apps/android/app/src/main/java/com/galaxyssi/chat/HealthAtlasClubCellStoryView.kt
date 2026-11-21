package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import androidx.annotation.StringRes

internal object HealthAtlasClubCellMotion {
    fun locate(t: Float) = ease(t, .06f, .88f)
    fun cilia(t: Float) = ease(t, .08f, .87f)
    fun dock(t: Float) = ease(t, .04f, .50f)
    fun release(t: Float, index: Int) = ease(t, .49f + .055f * index, .80f + .060f * index)
    fun spread(t: Float, index: Int) = ease(t, .08f + .021f * index, .75f + .028f * index)
    fun expand(t: Float) = ease(t, .04f, .65f)
    fun divide(t: Float) = ease(t, .24f, .68f)
    fun differentiate(t: Float) = ease(t, .52f, .94f)

    private fun ease(t: Float, start: Float, end: Float): Float {
        val phase = if (t.isFinite()) t.coerceIn(0f, 1f) else 0f
        val f = ((phase - start) / (end - start)).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }
}

internal class HealthAtlasClubCellStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.CLUB_CELL_AIRWAY) {
    private val wallEdge = 0xff945e63
    private val muscle = 0xffc68585
    private val tissue = 0xfff2d5bd
    private val air = 0xffe9f4f1
    private val fluid = 0xffc4e4e5
    private val fluidEdge = 0xff649493
    private val clubEdge = 0xff815b35
    private val clubGold = 0xffecc47c
    private val granuleInk = 0xff996030
    private val proteinInk = 0xff726047
    private val ciliaInk = 0xff4d7d76
    private val cellEdge = 0xff727477
    private val nucleus = 0xffa480aa
    private val guide = 0xff506469
    private val branchFill = shade(55f, 217f, 0xfff1c9b0, 0xffba787e)
    private val clubFill = shade(150f, 255f, 0xfff7dfa1, 0xffdfaa6a)
    private val ciliatedFill = shade(186f, 256f, 0xffd6e9e1, 0xffa7c9c3)
    private val clubPositions = setOf(0, 3, 7, 10, 14)

    private val branch = Path().apply {
        moveTo(103f, 105f)
        cubicTo(158f, 90f, 201f, 64f, 241f, 58f)
        cubicTo(288f, 49f, 325f, 78f, 331f, 116f)
        cubicTo(337f, 154f, 319f, 180f, 287f, 196f)
        quadTo(258f, 212f, 231f, 243f)
        lineTo(103f, 105f); close()
    }
    private val branchFibers = Path().apply {
        moveTo(175f, 94f); cubicTo(226f, 77f, 250f, 61f, 279f, 68f)
        moveTo(206f, 106f); cubicTo(253f, 86f, 282f, 76f, 306f, 92f)
        moveTo(229f, 127f); cubicTo(262f, 109f, 302f, 100f, 326f, 113f)
        moveTo(242f, 154f); cubicTo(267f, 135f, 307f, 127f, 328f, 134f)
        moveTo(249f, 179f); cubicTo(274f, 161f, 306f, 156f, 323f, 156f)
        moveTo(241f, 209f); quadTo(277f, 180f, 307f, 181f)
    }
    private val rimClub = Path().apply {
        moveTo(-14f, 72f)
        quadTo(-12f, 61f, -10f, 55f)
        cubicTo(-7f, 44f, 7f, 44f, 10f, 55f)
        quadTo(12f, 61f, 14f, 72f)
        quadTo(0f, 76f, -14f, 72f); close()
    }
    private val rimCiliated = Path().apply {
        moveTo(-14f, 72f); lineTo(-11f, 55f)
        quadTo(0f, 54f, 11f, 55f); lineTo(14f, 72f)
        quadTo(0f, 76f, -14f, 72f); close()
    }
    private val bed = Path().apply {
        moveTo(24f, 244f); lineTo(335f, 244f); lineTo(335f, 276f)
        cubicTo(275f, 285f, 235f, 269f, 173f, 281f)
        cubicTo(117f, 291f, 68f, 277f, 24f, 282f); close()
    }
    private val bedFibers = Path().apply {
        moveTo(35f, 270f); quadTo(71f, 260f, 107f, 268f)
        moveTo(86f, 274f); quadTo(140f, 280f, 174f, 270f)
        moveTo(191f, 266f); quadTo(224f, 259f, 260f, 267f)
        moveTo(251f, 271f); quadTo(293f, 278f, 323f, 267f)
    }
    private val ciliatedCell = Path().apply {
        moveTo(-47f, 191f); quadTo(0f, 188f, 47f, 191f)
        cubicTo(45f, 209f, 49f, 234f, 47f, 253f)
        lineTo(-47f, 253f); cubicTo(-49f, 235f, -45f, 209f, -47f, 191f); close()
    }
    private val ciliaStroke = Path()
    private val clubCell = Path().apply {
        moveTo(118f, 191f)
        cubicTo(137f, 190f, 138f, 151f, 176f, 151f)
        cubicTo(213f, 151f, 216f, 188f, 234f, 191f)
        cubicTo(233f, 219f, 240f, 241f, 234f, 253f)
        quadTo(171f, 257f, 118f, 253f)
        cubicTo(113f, 234f, 121f, 211f, 118f, 191f); close()
    }
    private val apicalLight = Path().apply {
        moveTo(147f, 174f); cubicTo(155f, 160f, 164f, 157f, 176f, 157f)
        quadTo(190f, 156f, 200f, 169f)
    }
    private val film = Path().apply {
        filmEdge(this)
        lineTo(335f, 191f); lineTo(234f, 191f)
        cubicTo(216f, 188f, 213f, 151f, 176f, 151f)
        cubicTo(138f, 151f, 137f, 190f, 118f, 191f)
        lineTo(24f, 191f); close()
    }
    private val filmSurface = Path().apply { filmEdge(this) }
    private val releasePore = Path().apply {
        moveTo(170f, 151f)
        cubicTo(173f, 153f, 169f, 157f, 172f, 161f)
        quadTo(176f, 166f, 180f, 161f)
        cubicTo(183f, 157f, 179f, 153f, 182f, 151f)
    }
    private val releaseTracks = listOf(
        track(Path().apply { moveTo(176f, 158f); quadTo(173f, 143f, 160f, 143f) }),
        track(Path().apply { moveTo(176f, 158f); quadTo(176f, 142f, 188f, 141f) }),
        track(Path().apply { moveTo(176f, 158f); quadTo(187f, 146f, 201f, 152f) }),
    )
    private val spreadLeft = track(Path().apply {
        moveTo(177f, 141f)
        cubicTo(144f, 141f, 144f, 170f, 117f, 180f)
        quadTo(95f, 182f, 41f, 180f)
    })
    private val spreadRight = track(Path().apply {
        moveTo(177f, 142f)
        cubicTo(207f, 142f, 217f, 177f, 238f, 180f)
        lineTo(312f, 180f)
    })
    private val renewal = Path()

    init { tag = "atlas-function-club-cell-airway-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> locate(c, t)
            1 -> dome(c, t)
            2 -> release(c, t)
            3 -> spread(c, t)
            4 -> renew(c, t)
        }
    }

    private fun locate(c: Canvas, t: Float) {
        ink(cream); paint.shader = branchFill; c.drawPath(branch, paint); paint.shader = null
        stroke(c, branch, wallEdge, 1.7f)
        stroke(c, branchFibers, 0xffab7572, 1.5f)
        c.save()
        c.translate(150f, 184f)
        c.scale(1f, .92f)
        disc(c, 0f, 0f, 101f, tissue, wallEdge)
        disc(c, 0f, 0f, 93f, muscle, wallEdge)
        ink(0xffe2a399, 1.4f); c.drawCircle(0f, 0f, 87f, paint)
        disc(c, 0f, 0f, 80f, tissue, wallEdge)
        disc(c, 0f, 0f, 74f, 0xffd1e4db, fluidEdge)
        disc(c, 0f, 0f, 54f, air)
        for (i in 0..15) {
            c.save()
            c.rotate(i * 22.5f)
            rimCell(c, i in clubPositions)
            c.restore()
        }
        val scan = HealthAtlasClubCellMotion.locate(t)
        ink(clubEdge, 2.2f)
        c.drawArc(-41f, -41f, 41f, 41f, 166f - 91f * scan, 30f, false, paint)
        c.restore()
        leader(c, R.string.health_atlas_club_cell_story_lumen, 70f, 66f, 111f, 91f, 122f, 166f, true)
        leader(c, R.string.health_atlas_club_cell_story_bronchiole, 260f, 34f, 153f, 57f, 264f, 77f, true)
        leader(c, R.string.health_atlas_club_cell_story_club, 130f, 323f, 99f, 289f, 150f, 236f)
        leader(c, R.string.health_atlas_club_cell_story_muscle, 275f, 299f, 133f, 276f, 230f, 223f)
    }

    private fun rimCell(c: Canvas, club: Boolean) {
        val edge = if (club) clubEdge else ciliaInk
        val cell = if (club) rimClub else rimCiliated
        fill(c, cell, if (club) clubGold else 0xffb3d1c8)
        stroke(c, cell, edge, .85f)
        oval(c, -4f, 63f, 4f, 70f, nucleus, edge)
        if (club) {
            disc(c, -3f, 54f, 1.5f, granuleInk)
            disc(c, 4f, 56f, 1.5f, granuleInk)
        } else {
            for (i in -2..2) line(c, i * 3.5f, 55f, i * 3f + 1.5f, 50f, edge, .9f)
        }
    }

    private fun dome(c: Canvas, t: Float) {
        humanWall(c, HealthAtlasClubCellMotion.cilia(t))
        granule(c, 176f, 176f, 5.1f)
        leader(c, R.string.health_atlas_club_cell_story_dome, 176f, 75f, 121f, 104f, 176f, 149f, true)
        leader(c, R.string.health_atlas_club_cell_story_cilia, 64f, 130f, 86f, 155f, 77f, 178f, true)
        leader(c, R.string.health_atlas_club_cell_story_granule, 277f, 111f, 135f, 138f, 199f, 184f, true)
        leader(c, R.string.health_atlas_club_cell_story_club, 176f, 317f, 117f, 287f, 176f, 222f)
        leader(c, R.string.health_atlas_club_cell_story_ciliated, 277f, 317f, 113f, 287f, 279f, 219f)
    }

    private fun release(c: Canvas, t: Float) {
        humanWall(c, .3f)
        val dock = HealthAtlasClubCellMotion.dock(t)
        val exported = HealthAtlasClubCellMotion.release(t, 0)
        if (dock < .98f) {
            granule(c, 182f - 6f * dock, 193f - 35f * dock, 6.5f)
        }
        if (dock >= .98f && exported < .94f) {
            fill(c, releasePore, fluid)
            line(c, 171f, 151f, 181f, 151f, fluid, 2.5f)
            stroke(c, releasePore, clubEdge, 1.1f)
        }
        for ((i, path) in releaseTracks.withIndex()) {
            val progress = HealthAtlasClubCellMotion.release(t, i)
            if (progress > 0f) at(path, progress) { x, y -> protein(c, x, y) }
        }
        leader(c, R.string.health_atlas_club_cell_story_surface, 86f, 90f, 151f, 117f, 154f, 159f, true)
        leader(c, R.string.health_atlas_club_cell_story_fluid, 266f, 90f, 131f, 119f, 226f, 168f, true)
        leader(c, R.string.health_atlas_club_cell_story_club, 176f, 317f, 117f, 287f, 176f, 222f)
    }

    private fun spread(c: Canvas, t: Float) {
        humanWall(c, .44f)
        protein(c, 176f, 141f)
        for (i in 0..5) {
            val travel = HealthAtlasClubCellMotion.spread(t, i)
            val path = if (i % 2 == 0) spreadLeft else spreadRight
            at(path, .04f + .10f * (i / 2) + (.45f + .06f * i) * travel) { x, y ->
                protein(c, x, y + (i / 2 - 1) * 3f)
            }
        }
        leader(c, R.string.health_atlas_club_cell_story_protein, 153f, 72f, 163f, 103f, 176f, 141f, true)
        leader(c, R.string.health_atlas_club_cell_story_fluid, 276f, 126f, 123f, 151f, 282f, 176f, true)
        leader(c, R.string.health_atlas_club_cell_story_epithelium, 177f, 317f, 159f, 295f, 213f, 237f)
    }

    private fun renew(c: Canvas, t: Float) {
        val expansion = HealthAtlasClubCellMotion.expand(t)
        val division = HealthAtlasClubCellMotion.divide(t)
        val mature = HealthAtlasClubCellMotion.differentiate(t)
        wallBed(c)
        drawCiliatedCell(c, 57f, .70f, .3f)
        drawCiliatedCell(c, 287f, 1.02f, .3f)

        // Show one local lineage in the mouse: a retained club cell and a ciliated daughter.
        val right = 187f + 52f * expansion
        val joinY = 171f + 20f * mature
        val shoulderY = 159f + 32f * mature
        renewal.rewind()
        renewal.moveTo(90f, 191f)
        renewal.cubicTo(104f, 190f, 103f, 153f, 126f, 153f)
        renewal.cubicTo(150f, 153f, 147f, joinY, 163f, joinY)
        renewal.cubicTo(173f, shoulderY, right - 10f, shoulderY, right, 191f)
        renewal.quadTo(right + 2f, 219f, right, 253f)
        renewal.lineTo(90f, 253f); renewal.close()
        ink(cream); paint.shader = clubFill; c.drawPath(renewal, paint); paint.shader = null
        if (division > 0f) {
            val boundary = joinY + (253f - joinY) * division
            line(c, 163f, 253f, 163f, boundary, clubEdge, 1.3f)
        }
        if (mature > 0f) {
            c.save()
            c.clipPath(renewal)
            ink(cream); paint.shader = ciliatedFill
            paint.alpha = (255f * mature).toInt()
            c.drawRect(163f, minOf(joinY, shoulderY), right + 2f, 254f, paint)
            paint.shader = null
            c.restore()
            line(c, 163f, 253f, 163f, joinY, cellEdge, 1.15f)
            // Short emerging cilia project only from the new lumen-facing surface.
            for (i in 0..9) {
                val x = 171f + i * 6.4f
                val y = 191f - (191f - shoulderY) * .64f
                cilium(c, x, y, 16f * mature, 3f + 3f * mature)
            }
        }
        stroke(c, renewal, clubEdge, 1.4f)
        val nucleusX = 142f - 17f * division
        oval(c, nucleusX - 12f, 213f, nucleusX + 12f, 239f, nucleus, violet)
        if (division > 0f) {
            val childX = 143f + (right - 162f) * .75f * division
            val r = 12f * division
            oval(c, childX - r, 226f - r, childX + r, 226f + r, nucleus, violet)
        }
        granule(c, 125f, 178f, 4f)
        granule(c, 133f, 191f, 3.5f)
        label(c, R.string.health_atlas_club_cell_story_mouse, 180f, 93f, 206f)
        leader(c, R.string.health_atlas_club_cell_story_club, 107f, 317f, 113f, 287f, 125f, 211f)
        leader(c, R.string.health_atlas_club_cell_story_new_ciliated, 252f, 317f, 170f, 287f, 203f, 224f)
    }

    private fun humanWall(c: Canvas, cilia: Float) {
        wallBed(c)
        fill(c, film, fluid)
        stroke(c, filmSurface, fluidEdge, 1.4f)
        drawCiliatedCell(c, 71f, 1f, cilia)
        drawCiliatedCell(c, 284f, 1.08f, cilia)
        ink(cream); paint.shader = clubFill; c.drawPath(clubCell, paint); paint.shader = null
        stroke(c, clubCell, clubEdge, 1.6f)
        stroke(c, apicalLight, 0xfffceac1, 1.7f)
        oval(c, 159f, 209f, 193f, 242f, nucleus, violet)
        disc(c, 175f, 225f, 4.3f, violet)
        granule(c, 156f, 183f, 4.3f)
        granule(c, 199f, 184f, 4.8f)
        granule(c, 165f, 199f, 3.3f)
        granule(c, 209f, 199f, 3.9f)
    }

    private fun wallBed(c: Canvas) {
        fill(c, bed, tissue)
        stroke(c, bed, wallEdge, 1.05f)
        stroke(c, bedFibers, 0xffc38d7b, 1.1f)
    }

    private fun drawCiliatedCell(c: Canvas, x: Float, width: Float, phase: Float) {
        c.save()
        c.translate(x, 0f); c.scale(width, 1f)
        ink(cream); paint.shader = ciliatedFill; c.drawPath(ciliatedCell, paint); paint.shader = null
        stroke(c, ciliatedCell, cellEdge, 1.3f)
        oval(c, -13f, 208f, 12f, 238f, nucleus, violet)
        disc(c, -2f, 222f, 3.3f, violet)
        for (i in 0..12) {
            val offset = i - 6
            val bend = 10f * wave(phase + offset * .025f) + 2f
            cilium(c, offset * 6.3f, 189f + offset * offset * .045f, 16f - i % 3, bend)
        }
        c.restore()
    }

    private fun cilium(c: Canvas, x: Float, y: Float, length: Float, bend: Float) {
        ciliaStroke.rewind()
        ciliaStroke.moveTo(x, y)
        ciliaStroke.quadTo(x + bend * .14f, y - length * .68f, x + bend, y - length)
        stroke(c, ciliaStroke, ciliaInk, 1.35f)
    }

    private fun filmEdge(p: Path) = with(p) {
        moveTo(24f, 170f); quadTo(71f, 168f, 112f, 171f)
        cubicTo(130f, 169f, 132f, 129f, 176f, 129f)
        cubicTo(220f, 129f, 225f, 168f, 241f, 170f)
        quadTo(284f, 168f, 335f, 170f)
    }

    private fun granule(c: Canvas, x: Float, y: Float, r: Float) {
        disc(c, x, y, r, 0xffe3ad62, granuleInk)
        disc(c, x - r * .15f, y - r * .12f, r * .38f, granuleInk)
    }

    private fun protein(c: Canvas, x: Float, y: Float) {
        oval(c, x - 3.2f, y - 2.2f, x + 3.2f, y + 2.2f, 0xffe9bf72, proteinInk)
    }

    private fun fill(c: Canvas, p: Path, color: Long) {
        ink(color); c.drawPath(p, paint)
    }

    private fun leader(
        c: Canvas, @StringRes res: Int, x: Float, baseline: Float, width: Float,
        elbowY: Float, targetX: Float, targetY: Float, belowText: Boolean = false,
    ) {
        pointer(c, x, baseline + if (belowText) 5f else -11f, elbowY, targetX, targetY)
        label(c, res, x, baseline, width)
    }

    private fun pointer(c: Canvas, x: Float, startY: Float, elbowY: Float, targetX: Float, targetY: Float) {
        line(c, x, startY, x, elbowY, guide, 1.05f)
        line(c, x, elbowY, targetX, targetY, guide, 1.05f)
        disc(c, targetX, targetY, 2f, guide)
    }
}
