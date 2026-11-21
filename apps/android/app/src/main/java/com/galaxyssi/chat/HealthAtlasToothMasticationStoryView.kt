package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import androidx.annotation.StringRes
import kotlin.math.abs

internal class HealthAtlasToothMasticationStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.TOOTH_MASTICATION) {
    private val gumEdge = 0xff986a70
    private val gumLight = 0xffefbdb3
    private val gum = 0xffdc9b97
    private val mouth = 0xff9b646b
    private val bone = 0xffefd2aa
    private val boneEdge = 0xffa77c67
    private val enamel = 0xfffffcf4
    private val enamelEdge = 0xff8e8073
    private val enamelShade = 0xffe8decd
    private val food = 0xffc98547
    private val foodEdge = 0xff854c2e
    private val fiber = 0xfff2bf78
    private val saliva = 0xff527e8f
    private val guide = 0xff52676a

    private enum class Tooth { INCISOR, CANINE, PREMOLAR, MOLAR }

    private data class ArchTooth(
        val kind: Tooth, val x: Float, val y: Float, val w: Float, val h: Float, val angle: Float,
    )

    private val halfArch = listOf(
        ArchTooth(Tooth.INCISOR, 165f, 84f, 28f, 25f, -6f),
        ArchTooth(Tooth.INCISOR, 137f, 93f, 25f, 25f, -30f),
        ArchTooth(Tooth.CANINE, 117f, 116f, 28f, 26f, -52f),
        ArchTooth(Tooth.PREMOLAR, 106f, 146f, 27f, 27f, -73f),
        ArchTooth(Tooth.PREMOLAR, 102f, 176f, 28f, 29f, -88f),
        ArchTooth(Tooth.MOLAR, 102f, 210f, 33f, 36f, -90f),
        ArchTooth(Tooth.MOLAR, 105f, 247f, 34f, 36f, -97f),
    )
    private val palate = shape {
        moveTo(87f, 252f)
        cubicTo(79f, 224f, 82f, 156f, 97f, 117f)
        cubicTo(113f, 77f, 141f, 62f, 180f, 62f)
        cubicTo(219f, 62f, 247f, 77f, 263f, 117f)
        cubicTo(278f, 156f, 281f, 224f, 273f, 252f)
        cubicTo(268f, 290f, 92f, 290f, 87f, 252f)
        close()
    }
    private val palateWash = shade(62f, 278f, gum, 0xffeab0a9)
    private val palatalVault = shape {
        moveTo(125f, 250f)
        cubicTo(119f, 215f, 122f, 162f, 141f, 129f)
        cubicTo(158f, 99f, 202f, 99f, 219f, 129f)
        cubicTo(238f, 162f, 241f, 215f, 235f, 250f)
        cubicTo(219f, 269f, 141f, 269f, 125f, 250f)
        close()
    }
    private val archIncisor = shape {
        moveTo(-.9f, -.71f); quadTo(0f, -.94f, .91f, -.71f)
        cubicTo(1.05f, -.17f, .84f, .62f, .55f, .76f)
        quadTo(0f, 1.04f, -.63f, .76f); quadTo(-.97f, .34f, -.9f, -.71f)
        close()
    }
    private val archCanine = shape {
        moveTo(-.9f, -.05f); quadTo(-.63f, -.57f, -.05f, -.99f)
        quadTo(.51f, -.82f, .94f, -.11f); quadTo(.85f, .68f, .21f, .9f)
        quadTo(-.67f, 1.07f, -.9f, -.05f); close()
    }
    private val archPremolar = shape {
        moveTo(-.8f, -.54f)
        cubicTo(-.4f, -1.13f, .49f, -1.15f, .87f, -.5f)
        cubicTo(1.16f, .19f, .64f, .99f, .02f, .98f)
        cubicTo(-.61f, 1f, -1.15f, .27f, -.8f, -.54f)
        close()
    }
    private val archMolar = shape {
        moveTo(-.92f, -.51f)
        quadTo(-.88f, -1.05f, -.31f, -.93f); quadTo(.1f, -.78f, .39f, -.96f)
        quadTo(.96f, -.98f, .95f, -.44f); quadTo(.79f, -.05f, .95f, .37f)
        quadTo(.91f, .98f, .4f, .94f); quadTo(.03f, .81f, -.31f, .98f)
        quadTo(-.92f, 1f, -.92f, .49f); quadTo(-.79f, .09f, -.92f, -.51f)
        close()
    }
    private val archFissure = shape {
        moveTo(-.58f, -.08f); quadTo(-.21f, .12f, 0f, -.09f)
        quadTo(.29f, -.24f, .63f, -.05f)
    }

    private data class ProfileTooth(val kind: Tooth, val x: Float, val y: Float, val w: Float, val h: Float)

    private val profile = listOf(
        ProfileTooth(Tooth.INCISOR, 75f, 147f, 19f, 32f),
        ProfileTooth(Tooth.INCISOR, 96f, 150f, 19f, 29f),
        ProfileTooth(Tooth.CANINE, 124f, 151f, 28f, 34f),
        ProfileTooth(Tooth.PREMOLAR, 156f, 152f, 29f, 29f),
        ProfileTooth(Tooth.PREMOLAR, 188f, 152f, 30f, 29f),
        ProfileTooth(Tooth.MOLAR, 227f, 151f, 42f, 29f),
        ProfileTooth(Tooth.MOLAR, 273f, 149f, 44f, 29f),
    )
    private val cuttingEdge = shape {
        moveTo(-.89f, .07f); quadTo(-.23f, -.15f, .62f, .02f)
        cubicTo(.96f, .28f, .68f, .76f, .15f, .96f)
        lineTo(-.82f, 1f); quadTo(-1.09f, .58f, -.89f, .07f); close()
    }
    private val pointedCusp = shape {
        moveTo(-.92f, .04f); quadTo(-.13f, -.18f, .8f, .06f)
        quadTo(1.04f, .45f, .65f, .69f); lineTo(.05f, .99f)
        quadTo(-.15f, 1.04f, -.27f, .9f)
        quadTo(-1.08f, .55f, -.92f, .04f); close()
    }
    private val grindingCusps = shape {
        moveTo(-.92f, .07f); quadTo(-.46f, -.15f, 0f, .02f)
        quadTo(.58f, -.14f, .94f, .09f); quadTo(1.03f, .45f, .93f, .74f)
        quadTo(.69f, 1.05f, .42f, .94f); quadTo(.16f, .8f, -.06f, .91f)
        quadTo(-.52f, 1.07f, -.77f, .92f); quadTo(-1.06f, .73f, -.92f, .07f); close()
    }
    private val profileVault = shape {
        moveTo(45f, 130f)
        cubicTo(74f, 113f, 92f, 97f, 131f, 99f)
        cubicTo(176f, 104f, 213f, 91f, 256f, 98f)
        quadTo(289f, 103f, 306f, 122f)
        lineTo(293f, 149f); quadTo(181f, 139f, 68f, 151f)
        quadTo(48f, 152f, 45f, 130f); close()
    }
    private val profileUpperGum = shape {
        moveTo(56f, 141f); cubicTo(101f, 126f, 236f, 131f, 294f, 138f)
        quadTo(303f, 144f, 293f, 154f)
        cubicTo(258f, 161f, 109f, 158f, 67f, 154f)
        quadTo(55f, 153f, 56f, 141f); close()
    }
    private val profileJaw = shape {
        moveTo(295f, 135f); quadTo(295f, 126f, 307f, 130f)
        quadTo(316f, 133f, 313f, 145f); lineTo(305f, 222f)
        quadTo(301f, 247f, 270f, 252f); cubicTo(215f, 261f, 140f, 261f, 79f, 246f)
        quadTo(57f, 239f, 60f, 217f); lineTo(74f, 205f)
        quadTo(184f, 219f, 268f, 209f); quadTo(284f, 201f, 285f, 179f)
        close()
    }
    private val profileLowerGum = shape {
        moveTo(61f, 213f); cubicTo(73f, 199f, 109f, 202f, 137f, 205f)
        cubicTo(192f, 206f, 261f, 200f, 287f, 198f); lineTo(284f, 214f)
        cubicTo(243f, 228f, 122f, 229f, 67f, 220f); quadTo(60f, 218f, 61f, 213f); close()
    }
    private val profileJawContour = shape {
        moveTo(75f, 232f); cubicTo(123f, 249f, 236f, 252f, 280f, 235f)
        quadTo(295f, 225f, 296f, 201f)
    }

    private val frontVault = shape {
        moveTo(51f, 130f)
        cubicTo(78f, 107f, 132f, 108f, 180f, 109f)
        cubicTo(228f, 108f, 282f, 107f, 309f, 130f)
        lineTo(307f, 157f); quadTo(280f, 169f, 251f, 157f)
        cubicTo(227f, 147f, 221f, 131f, 180f, 130f)
        cubicTo(139f, 131f, 133f, 147f, 109f, 157f)
        quadTo(80f, 169f, 53f, 157f); close()
    }
    private val palateEdge = shape {
        moveTo(56f, 156f); quadTo(83f, 167f, 110f, 155f)
        cubicTo(133f, 147f, 140f, 130f, 180f, 130f)
        cubicTo(220f, 130f, 227f, 147f, 250f, 155f)
        quadTo(277f, 167f, 304f, 156f)
    }
    private val frontJaw = shape {
        moveTo(51f, 210f); quadTo(74f, 201f, 110f, 213f)
        cubicTo(129f, 220f, 126f, 242f, 180f, 243f)
        cubicTo(234f, 242f, 231f, 220f, 250f, 213f)
        quadTo(286f, 201f, 309f, 210f); lineTo(303f, 230f)
        cubicTo(282f, 277f, 229f, 285f, 180f, 285f)
        cubicTo(131f, 285f, 78f, 277f, 57f, 230f)
        close()
    }
    private val frontGum = shape {
        moveTo(53f, 211f); quadTo(80f, 200f, 111f, 212f)
        cubicTo(133f, 222f, 126f, 240f, 180f, 242f)
        cubicTo(234f, 240f, 227f, 222f, 249f, 212f)
        quadTo(280f, 200f, 307f, 211f)
    }
    private val frontTongue = Path()
    private val tongueMidline = Path()
    private val frontMolarCenters = floatArrayOf(84f, 276f)

    private val bite = shape {
        moveTo(-33f, -4f); quadTo(-22f, -10f, -5f, -8f)
        quadTo(17f, -11f, 35f, -3f); lineTo(31f, 6f)
        quadTo(9f, 10f, -9f, 7f); quadTo(-23f, 10f, -35f, 3f); close()
    }
    private val outerBite = shape {
        moveTo(-33f, -4f); quadTo(-22f, -10f, -2f, -8f)
        lineTo(1f, 6f); quadTo(-18f, 10f, -35f, 3f); close()
    }
    private val innerBite = shape {
        moveTo(0f, -8f); quadTo(17f, -11f, 35f, -3f); lineTo(31f, 6f)
        quadTo(13f, 10f, 3f, 7f); close()
    }
    private val crumb = shape {
        moveTo(-.96f, -.09f); lineTo(-.58f, -.79f); quadTo(-.03f, -1.12f, .52f, -.69f)
        lineTo(.96f, -.24f); lineTo(.74f, .56f); quadTo(.21f, .98f, -.49f, .71f)
        lineTo(-.88f, .48f); close()
    }
    private val crumbs = listOf(
        -19f to 1f, -10f to -5f, -3f to 4f, 6f to -6f, 13f to 3f, 21f to -1f,
    )

    init { tag = "atlas-function-tooth-mastication-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> dentalArch(c, t)
            1 -> incisorBite(c, t)
            2 -> canineTear(c, t)
            3 -> grindingStroke(c, t)
            4 -> gatherBolus(c, t)
        }
    }

    private fun dentalArch(c: Canvas, t: Float) {
        ink(gum); paint.shader = palateWash; c.drawPath(palate, paint); paint.shader = null
        stroke(c, palate, gumEdge, 1.4f)
        area(c, palatalVault, gumLight, 0xffc99491, 1f)
        line(c, 180f, 118f, 180f, 255f, 0xffbe8a88, 1f)
        for (side in -1..1 step 2) {
            for (i in 0..2) {
                val y = 135f + 11f * i
                line(c, 176f + 2f * (1 + side), y, 180f + side * (24f + 6f * i), y - 4f, 0xffc99491, 1.6f)
            }
            for (tooth in halfArch) {
                c.save()
                c.translate(180f + side * (180f - tooth.x), tooth.y)
                c.rotate(-side * tooth.angle)
                c.scale(tooth.w / 2f, tooth.h / 2f)
                val crown = when (tooth.kind) {
                    Tooth.INCISOR -> archIncisor
                    Tooth.CANINE -> archCanine
                    Tooth.PREMOLAR -> archPremolar
                    Tooth.MOLAR -> archMolar
                }
                area(c, crown, enamel, enamelEdge, .085f)
                val strength = (1f - abs(3f * t - tooth.kind.ordinal)).coerceIn(0f, 1f)
                if (strength > 0f) {
                    val alpha = (160f * strength).toLong()
                    ink((alpha shl 24) or 0x0088c8bb); c.drawPath(crown, paint)
                    stroke(c, crown, ((alpha + 64L) shl 24) or 0x003b8175, .105f)
                }
                if (tooth.kind == Tooth.MOLAR || tooth.kind == Tooth.PREMOLAR) {
                    stroke(c, archFissure, enamelEdge, .075f)
                    if (tooth.kind == Tooth.MOLAR) {
                        line(c, .02f, -.67f, 0f, -.09f, enamelEdge, .075f)
                        line(c, 0f, -.09f, .2f, .6f, enamelEdge, .075f)
                    }
                } else {
                    line(c, -.36f, .35f, .36f, .35f, enamelShade, .11f)
                }
                c.restore()
            }
        }
        callout(c, R.string.health_atlas_tooth_mastication_story_incisors, 54f, 60f, 84f, 84f, 61f, 162f, 79f)
        callout(c, R.string.health_atlas_tooth_mastication_story_canines, 47f, 118f, 74f, 85f, 121f, 111f, 118f)
        callout(c, R.string.health_atlas_tooth_mastication_story_premolars, 315f, 159f, 81f, 310f, 166f, 257f, 176f)
        callout(c, R.string.health_atlas_tooth_mastication_story_molars, 312f, 242f, 76f, 301f, 249f, 256f, 247f)
    }

    private fun incisorBite(c: Canvas, t: Float) {
        val close = ease(t, .18f, .52f)
        val release = ease(t, .60f, .93f)
        val angle = -9f + 8.4f * close - 5f * release
        val separation = ease(t, .52f, .92f)
        profileBones(c, angle)
        c.save()
        c.translate(69f, 183f)
        if (t <= .52f) {
            c.scale(1f, 1f - .55f * close)
            area(c, bite, food, foodEdge, 1.3f)
            line(c, -25f, -2f, 22f, -3f, fiber, 1.2f)
        } else {
            bitePiece(c, outerBite, -11f * separation, 7f * separation, -24f, -7f)
            bitePiece(c, innerBite, 17f * separation, 3f * separation, 8f, 24f)
        }
        c.restore()
        profileCrowns(c, angle, Tooth.INCISOR)
        callout(c, R.string.health_atlas_tooth_mastication_story_incisors, 60f, 73f, 94f, 58f, 83f, 73f, 163f)
    }

    private fun bitePiece(c: Canvas, piece: Path, dx: Float, dy: Float, from: Float, to: Float) {
        c.save()
        c.translate(dx, dy)
        area(c, piece, food, foodEdge, 1.3f)
        line(c, from, -2f, to, -2f, fiber, 1.2f)
        c.restore()
    }

    private fun canineTear(c: Canvas, t: Float) {
        val close = ease(t, .08f, .31f)
        val pull = ease(t, .31f, .87f)
        val angle = -6.8f + 6.1f * close - 3.3f * ease(t, .66f, .96f)
        profileBones(c, angle)
        c.save()
        c.translate(122f, 186f)
        bitePiece(c, innerBite, 0f, 0f, 8f, 26f)
        val dx = -22f * pull
        val dy = 7f * pull
        bitePiece(c, outerBite, dx, dy, -24f, -5f)
        for (i in -1..1) {
            val y = 3f * i
            if (t < .53f + .05f * (i + 1)) {
                line(c, dx - 3f, dy + y, 7f, y, fiber, 1.45f)
            }
        }
        c.restore()
        profileCrowns(c, angle, Tooth.CANINE)
        callout(c, R.string.health_atlas_tooth_mastication_story_canines, 123f, 72f, 90f, 123f, 82f, 124f, 163f)
    }

    private fun profileBones(c: Canvas, angle: Float) {
        area(c, profileVault, bone, boneEdge, 1.5f)
        area(c, profileUpperGum, gum, gumEdge, 1.2f)
        c.save()
        c.rotate(angle, 307f, 136f)
        area(c, profileJaw, bone, boneEdge, 1.55f)
        stroke(c, profileJawContour, 0xffcea687, 1.6f)
        area(c, profileLowerGum, gumLight, gumEdge, 1.2f)
        c.restore()
    }

    private fun profileCrowns(c: Canvas, angle: Float, focus: Tooth) {
        for (tooth in profile) {
            crown(c, tooth.kind, tooth.x, tooth.y, tooth.w, tooth.h, tooth.kind == focus)
        }
        c.save()
        c.rotate(angle, 307f, 136f)
        for (tooth in profile) {
            crown(c, tooth.kind, tooth.x + 4f, 211f, tooth.w - 2f, -tooth.h + 3f, tooth.kind == focus)
        }
        c.restore()
        callout(c, R.string.health_atlas_tooth_mastication_story_jaw, 254f, 322f, 103f, 254f, 304f, 254f, 245f)
    }

    private fun grindingStroke(c: Canvas, t: Float) {
        val cycle = (1.65f * t) % 1f
        val close = ease(cycle, .11f, .46f) - ease(cycle, .70f, 1f)
        val shear = ease(cycle, .28f, .69f) - ease(cycle, .75f, 1f)
        val jawX = 10f * shear
        val jawY = 17f - 16f * close
        val breakUp = ease(t, .24f, .68f)
        frontSection(c, jawX, jawY, 0f)
        c.save()
        c.translate(274f + jawX * .52f, 176f + jawY * .48f)
        if (t < .30f) {
            foodCrumb(c, 0f, 0f, 23f, 9f - 5f * close, 0f)
        } else {
            for ((i, offset) in crumbs.withIndex()) {
                val x = offset.first * (.57f + .48f * breakUp) + if (i % 2 == 0) shear * 4f else 0f
                val y = offset.second * (1f - .74f * close)
                foodCrumb(c, x, y, 5.8f - 2.1f * breakUp, 5f - 3f * close, 15f * (i - 2))
            }
        }
        c.restore()
        frontCrowns(c, jawX, jawY)
        callout(c, R.string.health_atlas_tooth_mastication_story_molars, 276f, 82f, 98f, 276f, 91f, 276f, 162f)
        callout(c, R.string.health_atlas_tooth_mastication_story_jaw, 180f, 332f, 103f, 180f, 315f, 180f, 274f + jawY)
    }

    private fun gatherBolus(c: Canvas, t: Float) {
        val open = ease(t, .03f, .48f) - .46f * ease(t, .79f, 1f)
        val place = ease(t, .19f, .87f)
        val wet = ease(t, .30f, .80f)
        val jawX = 5f * open
        val jawY = 12f + 17f * open
        frontSection(c, jawX, jawY, place)
        val x = 198f + 65f * place
        val y = 202f - 12f * place + jawY * .38f
        for ((i, offset) in crumbs.withIndex()) {
            val dx = offset.first * (1f - .55f * wet)
            val dy = offset.second * (1f - .15f * wet)
            foodCrumb(c, x + dx, y + dy, 5.8f, 4.3f, 15f * (i - 2))
        }
        if (wet > 0f) {
            val alpha = (wet * 255f).toLong()
            val film = (alpha shl 24) or (saliva and 0x00ffffff)
            val edge = 24f - 8f * wet
            ink(film, 1.8f); c.drawArc(x - edge, y - 11f, x + edge, y + 10f, 197f, 146f * wet, false, paint)
        }
        disc(c, x + 2f, y - 19f + 9f * wet, 2.8f, 0xffacd3db, saliva)
        frontCrowns(c, jawX, jawY)
        callout(c, R.string.health_atlas_tooth_mastication_story_saliva, 238f, 78f, 88f, 233f, 88f, x + 2f, y - 19f + 9f * wet)
        callout(c, R.string.health_atlas_tooth_mastication_story_tongue, 141f, 181f, 80f, 142f, 188f, 154f + jawX, 216f + jawY * .58f)
    }

    private fun frontSection(c: Canvas, dx: Float, dy: Float, reach: Float) {
        area(c, frontVault, bone, boneEdge, 1.4f)
        stroke(c, palateEdge, gumLight, 9f)
        stroke(c, palateEdge, gumEdge, 1.2f)
        c.save()
        c.translate(dx, dy)
        area(c, frontJaw, bone, boneEdge, 1.5f)
        stroke(c, frontGum, gum, 10f)
        stroke(c, frontGum, gumEdge, 1.2f)
        c.translate(0f, -.42f * dy)
        val tip = 227f + 34f * reach
        val lift = 8f * reach
        frontTongue.rewind()
        frontTongue.moveTo(119f, 237f)
        frontTongue.cubicTo(108f, 217f, 126f, 208f, 151f, 208f)
        frontTongue.cubicTo(181f, 205f, tip - 24f, 212f - lift, tip, 208f - lift)
        frontTongue.cubicTo(tip + 4f, 229f - lift, 210f, 248f, 171f, 248f)
        frontTongue.quadTo(136f, 249f, 119f, 237f)
        frontTongue.close()
        area(c, frontTongue, 0xffdc979b, mouth, 1.3f)
        tongueMidline.rewind()
        tongueMidline.moveTo(151f, 224f)
        tongueMidline.quadTo(182f, 215f, tip - 16f, 218f - lift)
        stroke(c, tongueMidline, 0xffb6777c, 1.15f)
        c.restore()
    }

    private fun frontCrowns(c: Canvas, dx: Float, dy: Float) {
        for (x in frontMolarCenters) {
            crown(c, Tooth.MOLAR, x, 150f, 54f, 24f, x > 180f)
            crown(c, Tooth.MOLAR, x + dx, 210f + dy, 52f, -34f, x > 180f)
        }
    }

    private fun crown(c: Canvas, kind: Tooth, x: Float, y: Float, w: Float, h: Float, focus: Boolean) {
        c.save()
        c.translate(x, y)
        c.scale(w / 2f, h)
        val outline = when (kind) {
            Tooth.INCISOR -> cuttingEdge
            Tooth.CANINE -> pointedCusp
            Tooth.PREMOLAR, Tooth.MOLAR -> grindingCusps
        }
        area(c, outline, if (focus) 0xfff4faf1 else enamel, if (focus) guide else enamelEdge, .052f)
        line(c, -.48f, .23f, -.5f, .64f, enamelShade, .055f)
        if (kind == Tooth.MOLAR || kind == Tooth.PREMOLAR) {
            line(c, -.06f, .90f, .01f, .45f, enamelShade, .065f)
        }
        c.restore()
    }

    private fun foodCrumb(c: Canvas, x: Float, y: Float, w: Float, h: Float, angle: Float) {
        c.save()
        c.translate(x, y); c.rotate(angle); c.scale(w, h)
        area(c, crumb, food, foodEdge, .13f)
        line(c, -.4f, -.27f, .38f, -.28f, fiber, .15f)
        c.restore()
    }

    private fun callout(c: Canvas, @StringRes res: Int, x: Float, y: Float, w: Float,
        elbowX: Float, elbowY: Float, targetX: Float, targetY: Float,
    ) {
        line(c, elbowX, elbowY, targetX, targetY, guide, 1f)
        disc(c, targetX, targetY, 1.6f, guide)
        label(c, res, x, y, w)
    }

    private fun ease(t: Float, start: Float, end: Float): Float {
        val x = ((t - start) / (end - start)).coerceIn(0f, 1f)
        return x * x * (3f - 2f * x)
    }

    private fun shape(build: Path.() -> Unit) = Path().apply(build)

    private fun area(c: Canvas, path: Path, fill: Long, edge: Long, weight: Float) {
        ink(fill); c.drawPath(path, paint)
        stroke(c, path, edge, weight)
    }
}
