package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import com.galaxyssi.chat.R.string

internal class HealthAtlasCalciumFeedbackStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.PARATHYROID_FEEDBACK) {
    private val clay = 0xff915d6a
    private val blood = 0xfff3c5c9
    private val guide = 0xff64727a
    private val gold = 0xff9b661f
    private val glandGold = 0xfff1c67d
    private val thyroidShade = shade(28f, 113f, 0xfff7c6b9, 0xffd68d96)
    private val cellShade = shade(175f, 258f, 0xffffe7d3, 0xffeab4b3)
    private val kidneyShade = shade(87f, 250f, 0xfff7c6be, 0xffd9949d)
    private val villusShade = shade(90f, 285f, 0xffffebd4, 0xffefb6ae)
    private val thyroidLobe = Path().apply {
        moveTo(79f, 80f)
        cubicTo(78f, 64f, 73f, 29f, 56f, 29f)
        cubicTo(41f, 29f, 35f, 62f, 42f, 88f)
        cubicTo(49f, 119f, 60f, 119f, 70f, 101f)
        quadTo(77f, 92f, 79f, 80f)
        close()
    }
    private val chiefCell = Path().apply {
        moveTo(43f, 211f)
        cubicTo(51f, 180f, 80f, 177f, 108f, 177f)
        lineTo(250f, 177f)
        cubicTo(281f, 177f, 309f, 183f, 317f, 210f)
        cubicTo(327f, 246f, 270f, 260f, 181f, 258f)
        cubicTo(100f, 263f, 38f, 247f, 43f, 211f)
        close()
    }
    private val neckBlood = Path().apply {
        moveTo(31f, 291f)
        cubicTo(81f, 278f, 128f, 287f, 179f, 295f)
        cubicTo(234f, 303f, 282f, 288f, 329f, 281f)
    }
    private val release = track(Path().apply {
        moveTo(179f, 235f)
        cubicTo(178f, 253f, 187f, 283f, 201f, 295f)
        cubicTo(233f, 302f, 286f, 288f, 325f, 282f)
    })
    private val kidney = Path().apply {
        moveTo(119f, 89f)
        cubicTo(157f, 89f, 160f, 122f, 143f, 140f)
        cubicTo(128f, 155f, 123f, 167f, 138f, 181f)
        cubicTo(158f, 204f, 142f, 244f, 109f, 247f)
        cubicTo(61f, 255f, 29f, 226f, 30f, 177f)
        cubicTo(28f, 127f, 61f, 88f, 119f, 89f)
        close()
    }
    private val renalCortex = Path().apply {
        moveTo(119f, 102f)
        cubicTo(145f, 104f, 143f, 126f, 129f, 138f)
        cubicTo(112f, 154f, 109f, 170f, 126f, 187f)
        cubicTo(143f, 209f, 126f, 230f, 107f, 234f)
        cubicTo(68f, 240f, 43f, 217f, 44f, 177f)
        cubicTo(43f, 135f, 75f, 101f, 119f, 102f)
        close()
    }
    private val tubule = Path().apply {
        moveTo(178f, 143f)
        cubicTo(215f, 132f, 232f, 151f, 268f, 142f)
        quadTo(296f, 136f, 327f, 144f)
    }
    private val renalBlood = Path().apply {
        moveTo(178f, 220f)
        cubicTo(223f, 231f, 279f, 207f, 327f, 216f)
    }
    private val retention = track(Path().apply {
        moveTo(180f, 142f)
        cubicTo(207f, 136f, 224f, 142f, 246f, 143f)
        cubicTo(264f, 144f, 250f, 214f, 274f, 217f)
        quadTo(299f, 212f, 324f, 216f)
    })
    private val activeVitaminD = track(Path().apply {
        moveTo(152f, 296f)
        quadTo(231f, 320f, 324f, 296f)
    })
    private val villus = Path().apply {
        moveTo(107f, 266f)
        cubicTo(140f, 254f, 127f, 199f, 133f, 155f)
        cubicTo(136f, 117f, 147f, 91f, 173f, 89f)
        cubicTo(204f, 85f, 223f, 108f, 224f, 153f)
        cubicTo(226f, 193f, 218f, 252f, 251f, 266f)
    }
    private val villusEdge = track(villus)
    private val intestinalWall = Path(villus).apply {
        lineTo(330f, 266f); lineTo(330f, 291f)
        lineTo(30f, 291f); lineTo(30f, 266f); close()
    }
    private val villusBlood = Path().apply {
        moveTo(82f, 277f)
        cubicTo(178f, 284f, 152f, 237f, 162f, 167f)
        cubicTo(164f, 134f, 170f, 122f, 182f, 122f)
        cubicTo(206f, 123f, 197f, 183f, 201f, 223f)
        quadTo(204f, 283f, 305f, 277f)
    }
    private val uptake = track(Path().apply {
        moveTo(54f, 162f)
        cubicTo(91f, 156f, 128f, 173f, 161f, 181f)
        cubicTo(159f, 236f, 171f, 277f, 87f, 277f)
    })
    private val intestinalSignal = track(Path().apply {
        moveTo(305f, 277f)
        quadTo(204f, 283f, 201f, 223f)
        quadTo(195f, 195f, 216f, 173f)
    })

    init { tag = "atlas-function-parathyroid-feedback-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val ease = t * t * (3f - 2f * t)
        when (step) {
            0 -> parathyroids(c, t, 1f - .66f * ease, 0f)
            1 -> parathyroids(c, t, .34f, .24f + .76f * ease)
            2 -> renalResponse(c, t)
            3 -> intestinalResponse(c, t)
            else -> parathyroids(c, t, .34f + .66f * ease, 1f - .8f * ease)
        }
    }

    private fun parathyroids(c: Canvas, t: Float, calcium: Float, hormone: Float) {
        rounded(c, 77f, 26f, 99f, 121f, 7f, 0xffdfd7c5)
        for (y in 37..113 step 11) line(c, 79f, y.toFloat(), 97f, y.toFloat(), 0xffbaa997, 1.3f)
        rounded(c, 67f, 72f, 109f, 86f, 7f, 0xffe5a3a5)
        for (side in -1..1 step 2) {
            c.save()
            c.scale(-side.toFloat(), 1f, 88f, 0f)
            ink(cream); paint.shader = thyroidShade; c.drawPath(thyroidLobe, paint); paint.shader = null
            stroke(c, thyroidLobe, clay, 1.3f)
            oval(c, 51f, 44f, 63f, 61f, glandGold, gold)
            oval(c, 55f, 83f, 67f, 100f, glandGold, gold)
            c.restore()
        }
        line(c, 119f, 52f, 159f, 52f, gold, 1f)
        line(c, 131f, 82f, 176f, 82f, guide, 1f)
        label(c, string.health_atlas_calcium_feedback_story_art_glands, 240f, 57f, 149f)
        label(c, string.health_atlas_calcium_feedback_story_art_thyroid, 240f, 87f, 122f)

        ink(cream); paint.shader = cellShade; c.drawPath(chiefCell, paint); paint.shader = null
        stroke(c, chiefCell, clay, 1.8f)
        oval(c, 81f, 218f, 131f, 244f, 0xffcfafcb, violet)
        disc(c, 109f, 229f, 4f, 0xffa77da8)
        for (i in 0..3) disc(c, 165f + i * 15f, 234f + (i % 2) * 9f, 4.5f, 0xffe9d4eb, violet)
        for (x in 108..246 step 69) {
            val center = x.toFloat()
            oval(c, center - 6f, 170f, center + 6f, 184f, 0xffd6e7dd, teal)
            disc(c, center, 174f, 3.3f, opacity(teal, calcium))
        }
        for (i in 0..6) {
            val f = wrap(.62f * t + i / 7f)
            val a = (calcium * 7f - i).coerceIn(0f, 1f)
            disc(c, 43f + 272f * f, 153f + 8f * wave(f + i * .3f), 4f, opacity(teal, a))
        }
        vessel(c, neckBlood, 28f)
        flow(c, release, t, violet, 5, hormone)
        label(c, string.health_atlas_calcium_feedback_story_art_calcium, 85f, 136f, 117f)
        label(c, string.health_atlas_calcium_feedback_story_art_receptor, 273f, 136f, 118f)
        line(c, 273f, 141f, 249f, 168f, guide, 1f)
        label(c, string.health_atlas_calcium_feedback_story_art_chief, 104f, 211f, 112f)
        label(c, string.health_atlas_calcium_feedback_story_art_blood, 87f, 332f, 126f)
        if (hormone > 0f) label(c, string.health_atlas_calcium_feedback_story_art_pth, 265f, 332f, 154f)
    }

    private fun renalResponse(c: Canvas, t: Float) {
        ink(cream); paint.shader = kidneyShade; c.drawPath(kidney, paint); paint.shader = null
        stroke(c, kidney, clay, 1.6f)
        ink(0xffe5a4a8); c.drawPath(renalCortex, paint)
        stroke(c, renalCortex, 0xffca878d, 1.1f)
        for (i in 0..3) {
            val y = 126f + 27f * i
            val x = if (i == 0 || i == 3) 79f else 59f
            c.save()
            c.rotate(24f - i * 16f, x + 27f, y)
            oval(c, x, y - 8f, x + 49f, y + 8f, 0xffc7828d, clay)
            c.restore()
            line(c, x + 33f, y, 117f, 170f, 0xfff7d6b5, 5f)
        }
        line(c, 117f, 170f, 139f, 172f, 0xfff7d6b5, 7f)
        line(c, 151f, 117f, 171f, 135f, guide, 1f)
        stroke(c, tubule, gold, 29f)
        stroke(c, tubule, 0xfff8dfb2, 26f)
        stroke(c, tubule, 0xfffff2d4, 15f)
        vessel(c, renalBlood, 23f)
        arrow(c, 234f, 165f, 234f, 200f, teal)
        flow(c, retention, t, teal, 4)
        label(c, string.health_atlas_calcium_feedback_story_art_kidney, 91f, 68f, 125f)
        label(c, string.health_atlas_calcium_feedback_story_art_tubule, 250f, 106f, 156f)
        label(c, string.health_atlas_calcium_feedback_story_art_calcium, 291f, 183f, 104f)
        label(c, string.health_atlas_calcium_feedback_story_art_blood, 252f, 252f, 125f)
        label(c, string.health_atlas_calcium_feedback_story_art_activation, 235f, 283f, 186f)
        flow(c, activeVitaminD, t, gold, 3)
    }

    private fun intestinalResponse(c: Canvas, t: Float) {
        ink(cream); paint.shader = villusShade; c.drawPath(intestinalWall, paint); paint.shader = null
        stroke(c, villus, coral, 15f)
        stroke(c, villus, 0xfff3bcb2, 12.5f)
        for (i in 1..40) {
            at(villusEdge, i / 41f) { x, y -> disc(c, x, y, 2.1f, 0xffba7d8f) }
        }
        vessel(c, villusBlood, 16f)
        line(c, 221f, 130f, 263f, 101f, guide, 1f)
        arrow(c, 83f, 190f, 125f, 190f, teal)
        flow(c, uptake, t, teal, 5)
        flow(c, intestinalSignal, t, gold, 3)
        label(c, string.health_atlas_calcium_feedback_story_art_lumen, 76f, 85f, 124f)
        label(c, string.health_atlas_calcium_feedback_story_art_calcium, 72f, 134f, 106f)
        label(c, string.health_atlas_calcium_feedback_story_art_villus, 278f, 96f, 135f)
        label(c, string.health_atlas_calcium_feedback_story_art_blood, 84f, 320f, 128f)
        label(c, string.health_atlas_calcium_feedback_story_art_vitamin_d, 266f, 320f, 159f)
    }

    private fun vessel(c: Canvas, path: Path, width: Float) {
        stroke(c, path, clay, width)
        stroke(c, path, blood, width - 2.8f)
    }

    // Circles mark calcium, diamonds mark PTH, and paired dots mark active vitamin D.
    private fun flow(c: Canvas, path: PathMeasure, t: Float, color: Long, count: Int, strength: Float = 1f) {
        for (i in 0 until count) {
            val presence = (strength * count - i).coerceIn(0f, 1f)
            if (presence == 0f) continue
            val f = wrap(t + i.toFloat() / count)
            val fill = opacity(color, minOf(1f, 8f * f, 8f * (1f - f)) * presence)
            at(path, f) { x, y ->
                when (color) {
                    violet -> {
                        c.save()
                        c.rotate(45f, x, y)
                        ink(fill); c.drawRect(x - 4f, y - 4f, x + 4f, y + 4f, paint)
                        c.restore()
                    }
                    gold -> {
                        disc(c, x - 2.4f, y + 1.4f, 3.5f, fill)
                        disc(c, x + 2.8f, y - 1.5f, 2.8f, fill)
                    }
                    else -> disc(c, x, y, 4f, fill)
                }
            }
        }
    }

    private fun wrap(t: Float) = t % 1f
    private fun opacity(color: Long, alpha: Float) = (color and 0xffffff) or ((alpha * 255f).toLong() shl 24)
}
