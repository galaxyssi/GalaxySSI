package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.view.View
import kotlin.math.sin

internal class HealthAtlasAnkleMortiseStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.ANKLE_MORTISE) {
    private val tibiaLight = 0xfff6dbad
    private val tibiaDark = 0xffd2aa7c
    private val fibulaLight = 0xffd7e6ea
    private val fibulaDark = 0xffa3bdcc
    private val inkBone = 0xff9c7f6c
    private val inkFibula = 0xff627d91
    private val talusLight = 0xffe7a99b
    private val talusDark = 0xffcf858a
    private val inkTalus = 0xff976477
    private val accent = 0xff458e84
    private val tether = 0xffaf9093
    private val inkGuide = 0xff758c91

    init {
        tag = "atlas-function-ankle-mortise-art"
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
    }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val beat = sin(t * Math.PI).toFloat()
        when (step) {
            0 -> overview(c, beat)
            1 -> cradle(c, 0f, beat, showLabels = true)
            2 -> side(c, 16f * ease(t), true)
            3 -> cradle(c, ease(t) * 10f, 1f, showLabels = true)
            else -> side(c, 16f * (1f - ease(t)), false)
        }
    }

    private fun overview(c: Canvas, highlight: Float) {
        c.save()
        c.translate(18f, -8f)
        val tibia = Path().apply {
            moveTo(118f, 41f); cubicTo(144f, 31f, 166f, 34f, 193f, 45f)
            cubicTo(209f, 51f, 199f, 70f, 184f, 79f)
            cubicTo(174f, 95f, 174f, 163f, 178f, 203f)
            cubicTo(180f, 222f, 190f, 235f, 182f, 246f)
            quadTo(165f, 261f, 142f, 248f)
            cubicTo(133f, 239f, 140f, 224f, 140f, 207f)
            cubicTo(145f, 166f, 142f, 112f, 132f, 85f)
            cubicTo(114f, 77f, 100f, 55f, 118f, 41f); close()
        }
        val fibula = Path().apply {
            moveTo(211f, 66f); quadTo(231f, 57f, 235f, 76f); quadTo(233f, 87f, 224f, 95f)
            cubicTo(211f, 121f, 213f, 177f, 213f, 198f)
            cubicTo(213f, 221f, 224f, 231f, 216f, 252f)
            quadTo(209f, 269f, 199f, 252f); cubicTo(201f, 236f, 192f, 219f, 195f, 195f)
            cubicTo(198f, 148f, 200f, 119f, 203f, 94f)
            quadTo(197f, 76f, 211f, 66f); close()
        }
        surface(c, tibia, tibiaLight, tibiaDark, inkBone, 36f, 251f)
        surface(c, fibula, fibulaLight, fibulaDark, inkFibula, 65f, 252f)
        stroke(c, Path().apply {
            moveTo(158f, 88f); cubicTo(164f, 117f, 164f, 169f, 159f, 209f)
        }, 0xfffff1cd, 3.2f)
        line(c, 217f, 111f, 209f, 193f, 0xffe8f4f5, 2.8f)
        val tarsus = Path().apply {
            moveTo(153f, 260f); quadTo(169f, 245f, 194f, 258f); quadTo(202f, 269f, 189f, 279f)
            quadTo(169f, 282f, 155f, 274f); close()
        }
        surface(c, tarsus, talusLight, talusDark, inkTalus, 256f, 281f)
        ink(accent, 2f + 2f * highlight)
        paint.alpha = (95 + highlight * 140).toInt()
        c.drawOval(129f, 219f, 224f, 285f, paint)
        paint.alpha = 255
        c.restore()
        callout(c, R.string.health_atlas_ankle_mortise_tibia, 55f, 107f, 164f, 103f, left = true)
        callout(c, R.string.health_atlas_ankle_mortise_fibula, 306f, 112f, 237f, 114f, left = false)
        callout(c, R.string.health_atlas_ankle_mortise_ankle, 286f, 287f, 229f, 244f, left = false)
    }

    private fun cradle(c: Canvas, shift: Float, emphasis: Float, showLabels: Boolean) {
        val tibia = Path().apply {
            moveTo(93f, 57f); cubicTo(114f, 45f, 144f, 44f, 176f, 55f)
            cubicTo(193f, 62f, 199f, 74f, 194f, 92f)
            cubicTo(187f, 113f, 188f, 143f, 189f, 162f)
            quadTo(190f, 177f, 172f, 179f); quadTo(157f, 174f, 141f, 180f)
            quadTo(124f, 186f, 121f, 204f); quadTo(114f, 214f, 102f, 208f)
            quadTo(92f, 202f, 94f, 188f); cubicTo(99f, 143f, 103f, 122f, 89f, 99f)
            quadTo(72f, 69f, 93f, 57f); close()
        }
        surface(c, tibia, tibiaLight, tibiaDark, inkBone, 52f, 214f)
        stroke(c, Path().apply { moveTo(106f, 78f); quadTo(120f, 115f, 112f, 168f) }, 0xfffff0cd, 4f)
        val fibula = Path().apply {
            moveTo(208f + shift, 53f); quadTo(226f + shift, 48f, 231f + shift, 67f)
            cubicTo(229f + shift, 90f, 221f + shift, 113f, 222f + shift, 145f)
            cubicTo(222f + shift, 168f, 232f + shift, 183f, 225f + shift, 211f)
            quadTo(221f + shift, 230f, 209f + shift, 225f)
            quadTo(198f + shift, 221f, 201f + shift, 209f)
            cubicTo(209f + shift, 186f, 200f + shift, 168f, 198f + shift, 146f)
            cubicTo(193f + shift, 115f, 206f + shift, 94f, 203f + shift, 76f)
            quadTo(197f + shift, 62f, 208f + shift, 53f); close()
        }
        surface(c, fibula, fibulaLight, fibulaDark, inkFibula, 57f, 223f)
        line(c, 215f + shift, 83f, 208f + shift, 134f, 0xffe5f2f4, 3f)
        repeat(3) { index ->
            val y = 115f + index * 10f
            line(c, 190f, y, 202f + shift, y + 9f, tether, 2.4f)
        }
        val talus = Path().apply {
            moveTo(128f, 193f); cubicTo(144f, 181f, 177f, 180f, 194f, 197f)
            quadTo(207f, 211f, 201f, 229f); quadTo(193f, 240f, 172f, 243f)
            quadTo(150f, 242f, 132f, 232f); quadTo(116f, 222f, 128f, 193f); close()
        }
        surface(c, talus, talusLight, talusDark, inkTalus, 186f, 243f)
        stroke(c, Path().apply { moveTo(132f, 196f); quadTo(159f, 183f, 191f, 201f) },
            0xffe6d1aa, 2.5f + emphasis * 1.6f)
        if (shift > .2f) {
            arrow(c, 206f, 254f, 206f + shift * 2.4f + 10, 254f, accent)
            c.save()
            paint.textAlign = android.graphics.Paint.Align.CENTER
            label(c, R.string.health_atlas_ankle_mortise_exaggerated, 181f, 287f, 270f)
            c.restore()
            paint.textAlign = android.graphics.Paint.Align.LEFT
        }
        if (showLabels) {
            callout(c, R.string.health_atlas_ankle_mortise_tibia, 70f, 117f, 121f, 109f, left = true)
            callout(c, R.string.health_atlas_ankle_mortise_fibula, 283f, 95f, 223f + shift, 84f, left = false)
            callout(c, R.string.health_atlas_ankle_mortise_syndesmosis, 294f, 160f, 196f + shift / 2f, 129f, left = false)
            callout(c, R.string.health_atlas_ankle_mortise_talus, 86f, 251f, 151f, 223f, left = true)
        }
    }

    private fun side(c: Canvas, angle: Float, advancing: Boolean) {
        val tibiaSide = Path().apply {
            moveTo(120f, 65f); quadTo(146f, 49f, 170f, 59f)
            quadTo(188f, 67f, 184f, 90f); cubicTo(174f, 119f, 176f, 144f, 179f, 162f)
            quadTo(181f, 174f, 164f, 184f); quadTo(143f, 188f, 127f, 177f)
            quadTo(118f, 171f, 120f, 158f); cubicTo(126f, 121f, 121f, 106f, 114f, 87f)
            quadTo(109f, 70f, 120f, 65f); close()
        }
        surface(c, tibiaSide, tibiaLight, tibiaDark, inkBone, 65f, 185f)
        val foot = Path().apply {
            moveTo(134f, 207f); quadTo(143f, 179f, 167f, 185f)
            quadTo(181f, 191f, 196f, 203f); quadTo(210f, 215f, 240f, 218f)
            quadTo(268f, 220f, 280f, 235f); quadTo(286f, 245f, 270f, 249f)
            cubicTo(239f, 255f, 221f, 240f, 187f, 244f)
            quadTo(153f, 256f, 136f, 236f); quadTo(129f, 223f, 134f, 207f); close()
        }
        val contact = Path().apply {
            moveTo(144f, 201f); quadTo(150f, 184f, 165f, 187f)
            quadTo(179f, 190f, 190f, 203f); quadTo(181f, 215f, 164f, 215f)
            quadTo(150f, 214f, 144f, 201f); close()
        }
        c.save()
        c.rotate(-angle, 157f, 190f)
        surface(c, foot, tibiaLight, tibiaDark, inkBone, 195f, 250f)
        surface(c, contact, talusLight, talusDark, inkTalus, 185f, 214f)
        stroke(c, Path().apply { moveTo(193f, 222f); quadTo(229f, 221f, 254f, 234f) }, 0xffffedcb, 3f)
        c.restore()
        disc(c, 157f, 190f, 4f, accent, cream)
        if (advancing) arrow(c, 293f, 245f, 291f, 211f, accent)
        else arrow(c, 291f, 211f, 293f, 245f, accent)
        callout(c, R.string.health_atlas_ankle_mortise_ankle, 70f, 179f, 153f, 185f, left = true)
        callout(c, R.string.health_atlas_ankle_mortise_tibia, 261f, 107f, 175f, 105f, left = false)
        val caption = if (advancing) R.string.health_atlas_ankle_mortise_dorsiflex else R.string.health_atlas_ankle_mortise_neutral
        paint.textAlign = android.graphics.Paint.Align.CENTER
        label(c, caption, 189f, 297f, 272f)
        paint.textAlign = android.graphics.Paint.Align.LEFT
    }

    private fun surface(c: Canvas, shape: Path, light: Long, dark: Long, border: Long, top: Float, bottom: Float) {
        ink(light); paint.shader = shade(top, bottom, light, dark); c.drawPath(shape, paint); paint.shader = null
        stroke(c, shape, border, 1.8f)
    }

    private fun callout(c: Canvas, title: Int, tx: Float, ty: Float, x: Float, y: Float, left: Boolean) {
        line(c, tx + if (left) 19f else -19f, ty + 4f, x, y, inkGuide, 1f)
        disc(c, x, y, 3f, accent, cream)
        paint.textAlign = android.graphics.Paint.Align.CENTER
        label(c, title, tx, ty, 118f)
        paint.textAlign = android.graphics.Paint.Align.LEFT
    }

    private fun ease(t: Float) = t * t * (3f - 2f * t)
}
