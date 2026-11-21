package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader
import androidx.annotation.StringRes

internal object HealthAtlasGastricChiefMotion {
    fun locate(t: Float) = ease(t, .06f, .86f)
    fun pack(t: Float, index: Int) = ease(t, .09f + .09f * index, .64f + .10f * index)
    fun dock(t: Float) = ease(t, .03f, .53f)
    fun release(t: Float, index: Int) = ease(t, .46f + .055f * index, .80f + .06f * index)
    fun acidFlow(t: Float) = ease(t, .02f, .60f)
    fun activate(t: Float, index: Int) = ease(t, .32f + .19f * index, .72f + .22f * index)
    fun approach(t: Float, index: Int) = ease(t, .02f + .23f * index, .40f + .23f * index)
    fun split(t: Float, index: Int) = ease(t, .40f + .23f * index, .71f + .26f * index)

    private fun ease(t: Float, start: Float, end: Float): Float {
        val phase = if (t.isFinite()) t.coerceIn(0f, 1f) else 0f
        val f = ((phase - start) / (end - start)).coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }
}

internal class HealthAtlasGastricChiefStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.GASTRIC_CHIEF_SECRETION) {
    private val stroma = 0xfff4d8c9
    private val glandEdge = 0xff9a6470
    private val chiefEdge = 0xff6d6088
    private val chiefPale = 0xffdcd3ed
    private val nucleus = 0xffa18bb9
    private val lumenEdge = 0xff568184
    private val pitColor = 0xffd6e9e5
    private val guide = 0xff56696e
    private val amber = 0xff9b622f
    private val acid = 0xffa54539
    private val enzyme = 0xff426d94
    private val peptide = 0xff397164
    private val gastricFill = shade(84f, 250f, 0xfff6c9b6, 0xffd78c91)
    private val chiefFill = shade(94f, 263f, 0xfff0e4ef, 0xffb5a5d0)
    private val fluidFill = shade(67f, 289f, 0xffe5f2ec, 0xffc2e0dd)
    private val wallFill = shade(82f, 274f, 0xfffbe8da, 0xffe5b3ad)

    private val stomach = shape {
        moveTo(54f, 92f); quadTo(62f, 87f, 72f, 91f)
        cubicTo(71f, 111f, 75f, 127f, 81f, 126f)
        cubicTo(96f, 108f, 120f, 110f, 134f, 125f)
        cubicTo(159f, 154f, 145f, 209f, 120f, 232f)
        cubicTo(89f, 259f, 58f, 243f, 43f, 227f)
        quadTo(29f, 211f, 16f, 222f)
        lineTo(17f, 204f); quadTo(29f, 207f, 37f, 196f)
        cubicTo(46f, 181f, 46f, 166f, 54f, 148f)
        cubicTo(61f, 132f, 57f, 111f, 54f, 92f); close()
    }
    private val stomachFolds = shape {
        moveTo(93f, 138f); cubicTo(117f, 123f, 136f, 148f, 132f, 170f)
        moveTo(74f, 153f); cubicTo(104f, 123f, 134f, 174f, 113f, 205f)
        moveTo(65f, 173f); cubicTo(94f, 153f, 117f, 194f, 91f, 221f)
        moveTo(54f, 193f); cubicTo(76f, 178f, 92f, 207f, 73f, 223f)
    }
    private val glandWall = shape {
        moveTo(169f, 90f); quadTo(199f, 77f, 223f, 86f)
        cubicTo(235f, 89f, 231f, 110f, 251f, 110f)
        cubicTo(268f, 110f, 261f, 86f, 278f, 83f)
        quadTo(305f, 78f, 335f, 89f)
        lineTo(335f, 243f)
        cubicTo(328f, 284f, 289f, 307f, 249f, 301f)
        cubicTo(193f, 300f, 169f, 257f, 169f, 215f); close()
    }
    private val glandLumen = shape {
        moveTo(221f, 85f)
        cubicTo(232f, 84f, 232f, 113f, 245f, 123f)
        cubicTo(252f, 135f, 241f, 148f, 243f, 169f)
        cubicTo(245f, 192f, 234f, 218f, 235f, 245f)
        cubicTo(233f, 264f, 240f, 280f, 249f, 279f)
        cubicTo(261f, 278f, 263f, 262f, 255f, 240f)
        cubicTo(251f, 213f, 261f, 193f, 259f, 169f)
        cubicTo(257f, 150f, 259f, 140f, 263f, 126f)
        cubicTo(274f, 113f, 263f, 89f, 280f, 83f)
    }
    private val locateTrack = track(shape {
        moveTo(252f, 112f); cubicTo(256f, 176f, 234f, 215f, 246f, 270f)
    })
    private val glandEpithelialCell = shape {
        moveTo(-23f, -10f); quadTo(-8f, -17f, 20f, -10f)
        quadTo(25f, 0f, 18f, 11f); quadTo(-8f, 16f, -24f, 9f)
        quadTo(-28f, 0f, -23f, -10f); close()
    }
    private val closeLumen = shape {
        moveTo(216f, 69f); quadTo(258f, 77f, 301f, 68f)
        cubicTo(325f, 102f, 327f, 243f, 297f, 279f)
        quadTo(256f, 290f, 215f, 279f); close()
    }
    private val chief = shape {
        moveTo(43f, 136f); cubicTo(51f, 105f, 94f, 100f, 139f, 100f)
        quadTo(192f, 101f, 214f, 117f)
        cubicTo(228f, 128f, 227f, 150f, 226f, 177f)
        lineTo(226f, 210f); quadTo(229f, 239f, 211f, 250f)
        cubicTo(175f, 272f, 81f, 266f, 55f, 241f)
        cubicTo(34f, 222f, 34f, 163f, 43f, 136f); close()
    }
    private val lumenWall = shape {
        moveTo(301f, 70f); cubicTo(285f, 96f, 296f, 118f, 289f, 146f)
        cubicTo(282f, 179f, 300f, 218f, 290f, 253f)
        quadTo(286f, 270f, 297f, 279f)
        cubicTo(330f, 265f, 344f, 232f, 337f, 189f)
        cubicTo(331f, 143f, 345f, 103f, 326f, 79f); close()
    }
    private val rER = shape {
        moveTo(80f, 143f); cubicTo(94f, 129f, 127f, 130f, 141f, 146f)
        moveTo(88f, 154f); cubicTo(107f, 140f, 133f, 144f, 147f, 159f)
        moveTo(121f, 159f); cubicTo(138f, 162f, 155f, 177f, 147f, 199f)
        moveTo(137f, 162f); cubicTo(165f, 172f, 163f, 196f, 155f, 210f)
        moveTo(139f, 210f); cubicTo(133f, 228f, 100f, 241f, 79f, 228f)
        moveTo(144f, 224f); cubicTo(125f, 244f, 96f, 250f, 82f, 241f)
    }
    private val packTracks = listOf(
        track(shape { moveTo(150f, 151f); quadTo(168f, 128f, 207f, 148f) }),
        track(shape { moveTo(158f, 171f); quadTo(169f, 157f, 204f, 178f) }),
        track(shape { moveTo(155f, 220f); quadTo(180f, 243f, 209f, 221f) }),
    )
    private val secretionTracks = listOf(
        track(shape { moveTo(219f, 195f); cubicTo(237f, 197f, 253f, 178f, 254f, 134f) }),
        track(shape { moveTo(221f, 195f); cubicTo(237f, 195f, 274f, 189f, 270f, 153f) }),
        track(shape { moveTo(223f, 195f); cubicTo(240f, 196f, 261f, 209f, 276f, 190f) }),
    )
    private val fusionPore = shape {
        moveTo(226f, 184f); cubicTo(225f, 189f, 215f, 186f, 215f, 195f)
        cubicTo(215f, 204f, 225f, 201f, 226f, 206f)
    }

    private val glandSection = shape {
        moveTo(35f, 78f); quadTo(104f, 66f, 125f, 81f)
        quadTo(174f, 94f, 233f, 81f); quadTo(284f, 66f, 325f, 80f)
        cubicTo(340f, 120f, 319f, 171f, 328f, 220f)
        quadTo(338f, 270f, 295f, 281f)
        quadTo(253f, 288f, 229f, 276f)
        quadTo(174f, 265f, 127f, 279f)
        quadTo(69f, 292f, 37f, 275f)
        cubicTo(22f, 240f, 37f, 198f, 27f, 157f)
        quadTo(18f, 99f, 35f, 78f); close()
    }
    private val sharedLumen = shape {
        moveTo(120f, 80f); quadTo(174f, 94f, 233f, 81f)
        cubicTo(247f, 112f, 222f, 151f, 241f, 185f)
        cubicTo(248f, 210f, 220f, 250f, 231f, 277f)
        quadTo(174f, 265f, 126f, 279f)
        cubicTo(113f, 246f, 135f, 219f, 121f, 188f)
        cubicTo(109f, 164f, 131f, 110f, 120f, 80f); close()
    }
    private val parietal = shape {
        moveTo(43f, 131f); cubicTo(49f, 104f, 78f, 98f, 96f, 111f)
        quadTo(127f, 128f, 123f, 152f)
        cubicTo(123f, 178f, 133f, 199f, 110f, 214f)
        cubicTo(67f, 236f, 30f, 185f, 43f, 131f); close()
    }
    private val canaliculus = shape {
        moveTo(121f, 144f); quadTo(114f, 149f, 108f, 141f)
        quadTo(99f, 129f, 92f, 132f)
        quadTo(85f, 135f, 97f, 144f)
        quadTo(106f, 151f, 99f, 157f)
        quadTo(87f, 161f, 94f, 166f)
        quadTo(105f, 170f, 112f, 159f); quadTo(117f, 155f, 121f, 159f)
    }
    private val sectionChief = shape {
        moveTo(233f, 155f); cubicTo(253f, 136f, 286f, 140f, 310f, 153f)
        quadTo(328f, 191f, 314f, 231f)
        cubicTo(308f, 254f, 259f, 268f, 235f, 251f)
        quadTo(227f, 245f, 231f, 228f)
        cubicTo(242f, 193f, 232f, 186f, 233f, 155f); close()
    }
    private val acidTrack = track(shape {
        moveTo(106f, 152f); cubicTo(139f, 144f, 159f, 139f, 175f, 176f)
    })
    private val acidTint = shade(105f, 246f, 0xffe8aa92, 0xffedcfac)

    private val stomachCavity = shape {
        moveTo(28f, 130f); cubicTo(69f, 65f, 279f, 61f, 323f, 118f)
        cubicTo(352f, 152f, 319f, 247f, 278f, 268f)
        cubicTo(211f, 306f, 104f, 286f, 53f, 251f)
        cubicTo(22f, 230f, 10f, 171f, 28f, 130f); close()
    }
    private val cavityFolds = shape {
        moveTo(35f, 142f); cubicTo(59f, 140f, 58f, 111f, 94f, 107f)
        moveTo(82f, 98f); cubicTo(114f, 113f, 131f, 94f, 156f, 89f)
        moveTo(173f, 95f); cubicTo(216f, 109f, 239f, 80f, 281f, 103f)
        moveTo(303f, 115f); cubicTo(295f, 139f, 318f, 154f, 314f, 180f)
        moveTo(42f, 221f); cubicTo(74f, 225f, 59f, 241f, 105f, 254f)
        moveTo(123f, 266f); cubicTo(153f, 266f, 180f, 274f, 208f, 267f)
        moveTo(235f, 265f); cubicTo(261f, 250f, 285f, 256f, 300f, 224f)
    }
    private val proteinY = floatArrayOf(188f, 172f, 166f, 175f, 192f, 199f, 187f, 169f, 163f, 172f, 188f, 193f)
    private val pepsinGlyph = shape {
        moveTo(-.94f, .15f); cubicTo(-1f, -.43f, -.48f, -1f, .04f, -.91f)
        quadTo(.56f, -1f, .92f, -.55f); quadTo(1.08f, -.20f, .55f, -.13f)
        quadTo(.20f, .02f, .59f, .19f); quadTo(1.03f, .25f, .83f, .58f)
        cubicTo(.51f, 1f, -.81f, 1.14f, -.94f, .15f); close()
    }

    init { tag = "atlas-function-gastric-chief-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> locate(c, t)
            1 -> pack(c, t)
            2 -> release(c, t)
            3 -> activate(c, t)
            4 -> digest(c, t)
        }
    }

    private fun locate(c: Canvas, t: Float) {
        tinted(c, stomach, gastricFill)
        stroke(c, stomach, glandEdge, 1.8f)
        stroke(c, stomachFolds, 0xfff9d0c0, 5f)
        stroke(c, stomachFolds, coral, 1.2f)
        ink(amber, 1.7f); c.drawCircle(111f, 145f, 12f, paint)
        line(c, 123f, 141f, 169f, 103f, guide, 1f)
        line(c, 121f, 151f, 169f, 231f, guide, 1f)

        tinted(c, glandWall, wallFill)
        stroke(c, glandWall, glandEdge, 1.45f)
        for (i in 0..5) {
            glandCell(c, 215f - 2f * i, 115f + 28f * i, i >= 4, i == 2)
            glandCell(c, 283f - 1f * i, 117f + 28f * i, i >= 4, i == 1 || i == 3)
        }
        glandCell(c, 221f, 268f, true, false)
        glandCell(c, 250f, 284f, true, false)
        glandCell(c, 280f, 267f, true, false)
        ink(pitColor); c.drawPath(glandLumen, paint)
        stroke(c, glandLumen, lumenEdge, 1.4f)
        val p = HealthAtlasGastricChiefMotion.locate(t)
        at(locateTrack, p) { x, y -> disc(c, x, y, 4.8f, amber, cream) }
        ink(amber, 1f + 1.2f * p)
        c.drawOval(191f, 228f, 303f, 297f, paint)

        callout(c, R.string.health_atlas_gastric_chief_story_stomach, 67f, 62f, 106f, 67f, 70f, 76f, 119f)
        callout(c, R.string.health_atlas_gastric_chief_story_pit, 243f, 50f, 130f, 243f, 58f, 252f, 116f)
        callout(c, R.string.health_atlas_gastric_chief_story_chief_cells, 161f, 318f, 122f, 173f, 302f, 204f, 255f)
        callout(c, R.string.health_atlas_gastric_chief_story_gland_base, 303f, 318f, 104f, 294f, 302f, 264f, 291f)
    }

    private fun glandCell(c: Canvas, x: Float, y: Float, isChief: Boolean, isParietal: Boolean) {
        c.save()
        c.translate(x, y)
        if (x > 250f) c.scale(-1f, 1f)
        val border = if (isChief) chiefEdge else glandEdge
        if (isParietal) {
            oval(c, -24f, -15f, 24f, 15f, 0xffedb7a5, border)
            disc(c, 0f, 1f, 4.6f, 0xffb88097, border)
        } else {
            ink(if (isChief) chiefPale else stroma); c.drawPath(glandEpithelialCell, paint)
            stroke(c, glandEpithelialCell, border, 1f)
            oval(c, -19f, -4f, -8f, 5f, nucleus, border)
            if (isChief) {
                disc(c, 7f, -4f, 2.6f, violet)
                disc(c, 13f, 3f, 2.1f, violet)
            }
        }
        c.restore()
    }

    private fun closeUp(c: Canvas) {
        tinted(c, closeLumen, fluidFill)
        tinted(c, lumenWall, wallFill)
        stroke(c, lumenWall, glandEdge, 1.4f)
        for (i in 0..5) {
            val y = 105f + 27f * i
            oval(c, 307f, y - 5f, 321f, y + 5f, 0xffc790a6, glandEdge)
            if (i < 5) line(c, 295f, y + 13f, 331f, y + 15f, glandEdge, .9f)
        }
        tinted(c, chief, chiefFill)
        stroke(c, chief, chiefEdge, 1.9f)
        stroke(c, rER, 0xff9984ae, 2.4f)
        for (i in 0..5) {
            disc(c, 91f + 7f * i, 134f + .45f * (i - 2) * (i - 2), 1.2f, chiefEdge)
            disc(c, 92f + 7f * i, 243f - .45f * i * i, 1.2f, chiefEdge)
        }
        oval(c, 65f, 162f, 127f, 222f, nucleus, chiefEdge)
        oval(c, 75f, 171f, 114f, 210f, 0xffbcaad0, nucleus)
        disc(c, 96f, 192f, 6f, chiefEdge, nucleus)
        granule(c, 186f, 130f, 8.5f)
        granule(c, 187f, 157f, 7.8f)
        granule(c, 174f, 205f, 7f)
        granule(c, 186f, 245f, 8.4f)
    }

    private fun pack(c: Canvas, t: Float) {
        closeUp(c)
        packTracks.forEachIndexed { i, path ->
            val p = HealthAtlasGastricChiefMotion.pack(t, i)
            at(path, p) { x, y -> granule(c, x, y, 4.4f + 4.6f * p) }
        }
        callout(c, R.string.health_atlas_gastric_chief_story_granule, 147f, 63f, 139f, 153f, 71f, 183f, 125f)
        callout(c, R.string.health_atlas_gastric_chief_story_gland_lumen, 281f, 49f, 120f, 281f, 57f, 260f, 99f)
        callout(c, R.string.health_atlas_gastric_chief_story_nucleus, 86f, 307f, 140f, 84f, 290f, 91f, 213f)
    }

    private fun release(c: Canvas, t: Float) {
        closeUp(c)
        val p = HealthAtlasGastricChiefMotion.dock(t)
        if (p < .90f) {
            granule(c, 181f + 36f * p, 183f + 12f * p, 9f)
        } else {
            // The pocket is open to the lumen; its membrane does not travel with the cargo.
            line(c, 226f, 184f, 226f, 206f, 0xffcfe5e0, 3.4f)
            ink(0xffcfe5e0); c.drawPath(fusionPore, paint)
            stroke(c, fusionPore, chiefEdge, 1.4f)
            if (HealthAtlasGastricChiefMotion.release(t, 0) == 0f) molecule(c, 219f, 195f, 4f, 0f)
        }
        secretionTracks.forEachIndexed { i, path ->
            val f = HealthAtlasGastricChiefMotion.release(t, i)
            if (f > 0f) at(path, f) { x, y -> molecule(c, x, y, 5.6f, 0f) }
        }
        molecule(c, 270f, 103f, 6.4f, 0f)
        callout(c, R.string.health_atlas_gastric_chief_story_chief_cell, 86f, 56f, 124f, 86f, 64f, 95f, 110f)
        callout(c, R.string.health_atlas_gastric_chief_story_pepsinogen, 282f, 50f, 124f, 282f, 58f, 271f, 94f)
        callout(c, R.string.health_atlas_gastric_chief_story_membrane, 150f, 310f, 159f, 159f, 293f, 221f, 231f)
        callout(c, R.string.health_atlas_gastric_chief_story_gland_lumen, 286f, 310f, 111f, 286f, 293f, 268f, 247f)
    }

    private fun activate(c: Canvas, t: Float) {
        val flow = HealthAtlasGastricChiefMotion.acidFlow(t)
        tinted(c, glandSection, wallFill)
        stroke(c, glandSection, glandEdge, 1.45f)
        tinted(c, sharedLumen, fluidFill)
        ink(cream); paint.shader = acidTint; paint.alpha = (143f * flow).toInt()
        c.drawPath(sharedLumen, paint); paint.shader = null
        stroke(c, sharedLumen, lumenEdge, 1.35f)
        oval(c, 43f, 229f, 118f, 267f, stroma, glandEdge)
        oval(c, 246f, 91f, 315f, 133f, stroma, glandEdge)
        ink(0xffedb4a1); c.drawPath(parietal, paint)
        stroke(c, parietal, glandEdge, 1.7f)
        oval(c, 57f, 155f, 89f, 187f, 0xffca8eaa, glandEdge)
        for (i in 0..2) oval(c, 57f + 11f * i, 127f - 4f * i, 65f + 11f * i, 139f - 4f * i, peach, glandEdge)
        ink(pitColor); c.drawPath(canaliculus, paint)
        line(c, 122f, 145f, 122f, 158f, pitColor, 5f)
        stroke(c, canaliculus, lumenEdge, 1.4f)
        tinted(c, sectionChief, chiefFill)
        stroke(c, sectionChief, chiefEdge, 1.7f)
        oval(c, 278f, 181f, 309f, 218f, nucleus, chiefEdge)
        granule(c, 248f, 173f, 7.2f)
        granule(c, 252f, 200f, 6.7f)
        granule(c, 248f, 225f, 7.2f)

        for (i in 0..3) {
            val f = (flow * 1.18f - .19f * i).coerceIn(0f, 1f)
            if (f > 0f) at(acidTrack, f) { x, y -> disc(c, x, y + (i % 2) * 5f, 2.7f, acid, cream) }
        }
        val first = HealthAtlasGastricChiefMotion.activate(t, 0)
        val second = HealthAtlasGastricChiefMotion.activate(t, 1)
        molecule(c, 174f, 191f - 7f * first, 11f, first)
        molecule(c, 195f, 238f - 12f * second, 9f, second)
        callout(c, R.string.health_atlas_gastric_chief_story_parietal_cell, 76f, 53f, 126f, 77f, 61f, 78f, 111f)
        callout(c, R.string.health_atlas_gastric_chief_story_chief_cell, 287f, 53f, 120f, 298f, 61f, 295f, 147f)
        callout(c, R.string.health_atlas_gastric_chief_story_acidic_lumen, 97f, 317f, 126f, 107f, 300f, 143f, 240f)
        callout(c, R.string.health_atlas_gastric_chief_story_activation_site, 246f, 317f, 145f, 237f, 300f, 202f, 251f)
    }

    private fun digest(c: Canvas, t: Float) {
        tinted(c, stomachCavity, fluidFill)
        stroke(c, stomachCavity, 0xffe5aa9e, 13f)
        stroke(c, stomachCavity, glandEdge, 1.65f)
        stroke(c, cavityFolds, 0xffefd9ca, 7f)
        stroke(c, cavityFolds, coral, 1.1f)

        val left = HealthAtlasGastricChiefMotion.split(t, 0)
        val right = HealthAtlasGastricChiefMotion.split(t, 1)
        val middleX = 5f * left - 4f * right
        val middleY = 20f * left
        if (left == 0f) bond(c, 3, 0f, 0f)
        if (right == 0f) bond(c, 7, middleX, middleY)
        chain(c, 0, 3, -11f * left, -8f * left)
        chain(c, 4, 7, middleX, middleY)
        chain(c, 8, 11, middleX + 17f * right, middleY - 29f * right)
        for (i in 0..1) {
            val p = HealthAtlasGastricChiefMotion.approach(t, i)
            val split = if (i == 0) left else right
            val target = if (i == 0) 136f else 216f
            val side = if (i == 0) -1f else 1f
            val x = target + side * (46f * (1f - p) + 26f * split) + i * middleX * p
            val y = 157f - 35f * (1f - p) + (15f + i * middleY) * wave(p * .25f) - 39f * split
            molecule(c, x, y, 9f)
        }
        molecule(c, 288f, 145f, 7.4f)
        callout(c, R.string.health_atlas_gastric_chief_story_protein, 77f, 54f, 131f, 72f, 63f, 100f, 156f)
        callout(c, R.string.health_atlas_gastric_chief_story_pepsin, 282f, 55f, 113f, 283f, 63f, 288f, 136f)
        line(c, 180f, 309f, 180f, 254f, guide, 1.1f)
        line(c, 180f, 254f, 137f, 202f, guide, 1.1f)
        line(c, 180f, 254f, 221f, 197f, guide, 1.1f)
        disc(c, 137f, 202f, 1.7f, guide)
        disc(c, 221f, 197f, 1.7f, guide)
        label(c, R.string.health_atlas_gastric_chief_story_cut_sites, 180f, 328f, 144f)
    }

    private fun chain(c: Canvas, first: Int, last: Int, dx: Float, dy: Float) {
        for (i in first until last) bond(c, i, dx, dy)
        for (i in first..last) {
            val fill = if (i % 2 == 0) 0xffa8c7a8 else 0xffc6d49c
            disc(c, 66f + 20f * i + dx, proteinY[i] + dy, 5.4f, fill, peptide)
        }
    }

    private fun bond(c: Canvas, i: Int, dx: Float, dy: Float) {
        val x = 66f + 20f * i + dx
        line(c, x, proteinY[i] + dy, x + 20f, proteinY[i + 1] + dy, peptide, 2.7f)
    }

    private fun granule(c: Canvas, x: Float, y: Float, radius: Float) {
        disc(c, x, y, radius, 0xffffe3b5, amber)
        molecule(c, x - radius * .12f, y, radius * .47f, 0f)
    }

    // A gold cap distinguishes inactive precursor from the same enzyme after cleavage.
    private fun molecule(c: Canvas, x: Float, y: Float, size: Float, cleavage: Float? = null) {
        c.save()
        c.translate(x, y)
        c.scale(size, size)
        ink(enzyme); c.drawPath(pepsinGlyph, paint)
        if (cleavage != null) {
            val dx = 1.20f * cleavage
            val dy = .62f * cleavage
            line(c, .72f + dx, -.42f + dy, .89f + dx, .16f + dy, amber, .36f)
        }
        c.restore()
    }

    private fun callout(
        c: Canvas, @StringRes res: Int, x: Float, baseline: Float, width: Float,
        fromX: Float, fromY: Float, toX: Float, toY: Float,
    ) {
        line(c, fromX, fromY, toX, toY, guide, 1.1f)
        disc(c, toX, toY, 1.7f, guide)
        label(c, res, x, baseline, width)
    }

    private fun tinted(c: Canvas, path: Path, fill: Shader) {
        ink(cream); paint.shader = fill; c.drawPath(path, paint); paint.shader = null
    }

    private fun shape(build: Path.() -> Unit) = Path().apply(build)
}
