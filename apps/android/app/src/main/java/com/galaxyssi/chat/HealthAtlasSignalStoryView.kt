package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

internal object HealthAtlasSignalMotion {
    fun axonTravel(t: Float, myelinated: Boolean) =
        HealthAtlasFunctionStory.safePhase(t) * (if (myelinated) .98f else .63f)

    fun upstreamDrive(t: Float) = 1f - .70f * HealthAtlasFunctionStory.safePhase(t)

    fun synapticRelease(t: Float, index: Int): Float =
        ((t - .38f - index * .085f) / .39f).coerceIn(0f, 1f)

    fun gradedInput(time: Float): Float {
        val t = HealthAtlasFunctionStory.safePhase(time)
        fun input(at: Float, width: Float) = (1f - abs(t - at) / width).coerceAtLeast(0f)
        return .18f + .30f * input(.24f, .25f) - .24f * input(.47f, .17f) +
            .24f * input(.70f, .25f) + .35f * input(.81f, .27f)
    }

    fun gateProgress(time: Float, openAt: Float, duration: Float) =
        ((HealthAtlasFunctionStory.safePhase(time) - openAt) / duration).coerceIn(0f, 1f)
}

internal class HealthAtlasSignalStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasFunctionArt(context, story) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val field = RectF(0f, 0f, 360f, 360f)
    private val shape = Path()
    private val xy = FloatArray(2)
    private val artwork = mutableMapOf<Int, Drawable>()
    private val paper = shade(0f, 360f, 0xffe9f4f5, 0xfffbf0df)
    private val terminalShade = shade(73f, 185f, 0xfff8e0cf, 0xffd49087)
    private val receivingShade = shade(246f, 317f, 0xffe0ede6, 0xffadd0c1)
    private val wrapShade = shade(115f, 220f, 0xfff4e4b9, 0xffc89170)
    private val cream = 0xfffbf8ed
    private val text = 0xff24444e
    private val gold = 0xffa76e29
    private val violet = 0xff765789
    private val teal = 0xff367970
    private val blue = 0xff3d7593
    private val coral = 0xffa5636e
    private val feedbackInk = 0xffa24d5d
    private val dendrites by lazy { listOf(
        track { moveTo(113f, 59f); cubicTo(119f, 77f, 131f, 84f, 150f, 103f) },
        track { moveTo(193f, 58f); cubicTo(181f, 79f, 173f, 89f, 150f, 103f) },
    ) }
    private val axon by lazy { track {
        moveTo(150f, 103f); cubicTo(153f, 121f, 150f, 133f, 158f, 145f)
        cubicTo(176f, 172f, 198f, 203f, 212f, 229f)
        cubicTo(223f, 253f, 227f, 264f, 247f, 270f); quadTo(258f, 275f, 263f, 281f)
    } }
    private val portal by lazy { track {
        moveTo(189f, 54f); quadTo(175f, 65f, 177f, 79f)
        quadTo(182f, 113f, 174f, 148f); quadTo(154f, 170f, 130f, 188f)
    } }
    private val tshRoute by lazy { track {
        moveTo(77f, 138f); quadTo(85f, 207f, 148f, 212f); quadTo(187f, 216f, 225f, 202f)
    } }
    private val thyroidOut by lazy { track {
        moveTo(137f, 177f); quadTo(138f, 210f, 155f, 229f)
        quadTo(199f, 231f, 255f, 238f); lineTo(305f, 244f)
    } }
    private val nodes = intArrayOf(94, 160, 226, 292)
    private val potential = FloatArray(65) { HealthAtlasSignalMotion.gradedInput(it / 64f) }

    init {
        tag = when (story) {
            HealthAtlasFunctionStory.SYNAPTIC_SIGNAL -> "atlas-function-synaptic-signal-art"
            HealthAtlasFunctionStory.MYELIN_SIGNAL -> "atlas-function-myelin-signal-art"
            else -> "atlas-function-thyroid-feedback-art"
        }
    }

    override fun onDraw(c: Canvas) {
        val scale = minOf(width, height) / 360f
        if (scale <= 0f) return
        val chapter = story.chapter(phase)
        val t = story.fraction(phase)
        c.save()
        c.translate((width - 360f * scale) / 2f, (height - 360f * scale) / 2f)
        c.scale(scale, scale)
        ink(cream); paint.shader = paper; c.drawRoundRect(field, 8f, 8f, paint); paint.shader = null
        when (story) {
            HealthAtlasFunctionStory.SYNAPTIC_SIGNAL -> when (chapter) {
                0, 1 -> neuron(c, chapter == 0, t)
                else -> synapse(c, chapter, t)
            }
            HealthAtlasFunctionStory.MYELIN_SIGNAL -> when (chapter) {
                0 -> glialBranches(c, t)
                1 -> wrapping(c, t)
                2, 3 -> myelinRelay(c, chapter == 3, t)
                else -> compare(c, t)
            }
            else -> when (chapter) {
                0 -> trh(c, t)
                1 -> tsh(c, t)
                2 -> secretion(c, t)
                3 -> conversion(c, t)
                else -> feedback(c, t)
            }
        }
        c.restore()
    }

    private fun neuron(c: Canvas, receiving: Boolean, t: Float) {
        c.save()
        c.translate(37f, 2f)
        c.scale(.79f, .79f)
        plate(c, R.drawable.health_atlas_neuron, 75, 12, 275, 312)
        if (receiving) {
            for (i in dendrites.indices) {
                val f = loop(t * 1.22f + i * .28f)
                trail(c, dendrites[i], f, blue)
            }
            val input = HealthAtlasSignalMotion.gradedInput(t)
            ring(c, 154f, 138f, 6f + 9f * input, if (input >= .58f) gold else blue)
            leader(c, 52f, 48f, 117f, 61f, R.string.health_atlas_signal_neuro_dendrites, blue)
            leader(c, 63f, 211f, 154f, 138f, R.string.health_atlas_signal_neuro_initial, gold)
        } else {
            trail(c, axon, t, gold)
            leader(c, 70f, 223f, 190f, 191f, R.string.health_atlas_signal_neuro_axon, gold)
            leader(c, 253f, 331f, 240f, 281f, R.string.health_atlas_signal_neuro_terminal, coral)
        }
        c.restore()
        if (receiving) gradedPotential(c, t) else membraneRelay(c, t)
    }

    private fun gradedPotential(c: Canvas, t: Float) {
        rounded(c, 19f, 262f, 341f, 343f, 8f, cream)
        label(c, 114f, 282f, R.string.health_atlas_signal_neuro_voltage)
        label(c, 275f, 283f, R.string.health_atlas_signal_neuro_threshold)
        val left = 32f; val bottom = 332f; val length = 292f; val height = 63f
        val thresholdY = bottom - .58f * height
        for (i in 0..19) {
            val x = left + i * 15f
            line(c, x, thresholdY, x + 7f, thresholdY, gold, 1f)
        }
        val samples = (t * potential.lastIndex).toInt().coerceAtLeast(1)
        path {
            moveTo(left, bottom - height * potential.first())
            for (i in 1..samples) {
                lineTo(left + length * i / potential.lastIndex, bottom - height * potential[i])
            }
        }
        ink(blue, 2.5f); c.drawPath(shape, paint)
        val reading = HealthAtlasSignalMotion.gradedInput(t)
        dot(c, left + length * t, bottom - height * reading, 4f, if (reading >= .58f) gold else blue)
    }

    private fun membraneRelay(c: Canvas, t: Float) {
        rounded(c, 19f, 274f, 341f, 343f, 8f, cream)
        line(c, 34f, 303f, 326f, 303f, coral, 3f)
        line(c, 34f, 314f, 326f, 314f, coral, 3f)
        for (segment in 0..2) {
            val x = 77f + segment * 103f
            val local = t * 1.55f - segment * .29f
            val activation = local in .04f.. .69f
            val sodium = local < .32f
            val color = if (!activation) 0xff8fa4a6 else if (sodium) blue else violet
            gate(c, x, 309f, color, activation)
            if (activation) {
                if (sodium) arrow(c, x, 289f, x, 327f, blue) else arrow(c, x, 327f, x, 289f, violet)
                val f = if (sodium) (local - .04f) / .28f else (local - .32f) / .37f
                dot(c, x, if (sodium) 289f + 38f * f else 327f - 38f * f, 3.1f, color)
            }
        }
        dot(c, 40f, 333f, 2.9f, blue)
        label(c, 98f, 337f, R.string.health_atlas_signal_neuro_sodium_in)
        dot(c, 216f, 333f, 2.9f, violet)
        label(c, 274f, 337f, R.string.health_atlas_signal_neuro_potassium_out)
    }

    private fun gate(c: Canvas, x: Float, y: Float, color: Long, open: Boolean) {
        rounded(c, x - 14f, y - 11f, x + 14f, y + 11f, 4f, cream)
        rounded(c, x - 13f, y - 9f, x - 4f, y + 9f, 4f, color)
        rounded(c, x + 4f, y - 9f, x + 13f, y + 9f, 4f, color)
        if (!open) line(c, x - 5f, y, x + 5f, y, color, 3f)
    }

    private fun synapse(c: Canvas, chapter: Int, t: Float) {
        val fusion = chapter == 3 && t > .35f
        path {
            moveTo(138f, 74f); cubicTo(88f, 77f, 79f, 108f, 89f, 145f)
            quadTo(95f, 179f, 132f, 183f)
            lineTo(160f, 183f)
            if (fusion) quadTo(180f, 141f, 200f, 183f)
            lineTo(226f, 183f); quadTo(262f, 180f, 270f, 146f)
            cubicTo(280f, 102f, 256f, 76f, 222f, 74f); close()
        }
        paintPath(c, terminalShade, coral)
        shadedBox(c, 70f, 245f, 290f, 312f, 22f, receivingShade)
        line(c, 90f, 246f, 271f, 246f, teal, 2.8f)
        for (x in listOf(139f, 180f, 221f)) {
            path { moveTo(x - 10f, 232f); quadTo(x, 246f, x + 10f, 232f) }
            ink(teal, 4f); c.drawPath(shape, paint)
        }
        vesicle(c, 124f, 124f)
        vesicle(c, 213f, 116f)
        when (chapter) {
            2 -> {
                vesicle(c, 178f, 138f)
                val open = t > .22f
                c.save()
                c.rotate(90f, 267f, 147f)
                gate(c, 267f, 147f, blue, open)
                c.restore()
                for (i in 0..4) {
                    val f = HealthAtlasSignalMotion.gateProgress(t, .22f + i * .085f, .43f)
                    val x = 318f - 99f * f
                    val y = 147f + (i - 2) * 5.5f * abs(1f - f * 2f)
                    dot(c, x, y, 3.6f, blue)
                }
                label(c, 291f, 116f, R.string.health_atlas_signal_neuro_calcium_ions)
                if (open) arrow(c, 307f, 169f, 229f, 169f, blue)
            }
            3 -> {
                if (!fusion) vesicle(c, 180f, 140f + 21f * (t / .35f).coerceIn(0f, 1f))
                else for (i in 0..4) {
                    val f = HealthAtlasSignalMotion.synapticRelease(t, i)
                    dot(c, 180f + (i - 2) * 18f * f, 174f + 61f * f, 3.8f, violet)
                }
                if (fusion) arrow(c, 112f, 194f, 112f, 227f, violet)
                leader(c, 277f, 201f, 208f, 219f, R.string.health_atlas_signal_neuro_transmitter, violet)
            }
            else -> {
                val receptorOpen = t in .24f.. .79f
                gate(c, 180f, 246f, teal, receptorOpen)
                val binding = HealthAtlasSignalMotion.gateProgress(t, .03f, .21f)
                val clearing = HealthAtlasSignalMotion.gateProgress(t, .70f, .26f)
                dot(c, 168f + 12f * binding - 50f * clearing, 202f + 29f * binding - 38f * clearing, 4f, violet)
                if (receptorOpen) {
                    arrow(c, 180f, 250f, 180f, 281f, blue)
                    for (i in 0..2) {
                        val f = HealthAtlasSignalMotion.gateProgress(t, .25f + i * .11f, .27f)
                        dot(c, 180f + (i - 1) * 11f * f, 248f + 41f * f, 3.3f, blue)
                    }
                }
                if (clearing > 0f) arrow(c, 122f, 223f, 122f, 189f, violet)
                label(c, 99f, 280f, R.string.health_atlas_signal_neuro_sodium_in)
                leader(c, 303f, 193f, 230f, 234f, R.string.health_atlas_signal_neuro_receptor, teal)
            }
        }
        leader(c, 134f, 48f, 137f, 86f, R.string.health_atlas_signal_neuro_terminal, coral)
        label(c, 180f, 336f, R.string.health_atlas_signal_neuro_next)
    }

    private fun vesicle(c: Canvas, x: Float, y: Float) {
        oval(c, x, y, 12.5f, 12.5f, 0xffeee2eb)
        ring(c, x, y, 12.5f, violet)
        dot(c, x - 4f, y + 3f, 2.5f, violet)
        dot(c, x + 4f, y - 2f, 2.5f, violet)
    }

    private fun glialBranches(c: Canvas, t: Float) {
        val x = 180f
        val branches = listOf(89f to 181f, 241f to 222f, 147f to 263f)
        for ((tx, ty) in branches) {
            path { moveTo(x, 110f); quadTo(tx + 10f, 125f, tx, ty) }
            ink(0xff8ebeb1, 8f); c.drawPath(shape, paint)
            ink(teal, 1.5f); c.drawPath(shape, paint)
        }
        oval(c, x, 91f, 28f, 25f, 0xff93c3b8)
        oval(c, x - 2f, 91f, 13f, 12f, violet)
        for ((_, y) in branches) line(c, 33f, y, 327f, y, coral, 10f)
        for ((tx, ty) in branches) {
            val width = 18f + 19f * t
            sheath(c, tx - width, ty, tx + width, 15f)
            ring(c, tx, ty, 8f + 4f * sin(PI.toFloat() * t), cream)
        }
        leader(c, 182f, 42f, 181f, 78f, R.string.health_atlas_signal_myelin_oligo, teal)
        leader(c, 271f, 309f, 155f, 263f, R.string.health_atlas_signal_myelin_cover, gold)
    }

    private fun wrapping(c: Canvas, t: Float) {
        val x = 160f
        val y = 186f
        oval(c, x, y, 72f, 72f, 0xffefe1bc)
        oval(c, x, y, 23f, 23f, 0xffdd9b91)
        ring(c, x, y, 23f, coral)
        for (i in 0..3) {
            val r = 27f + 10f * i
            val turn = (t * 1.4f - i * .15f).coerceIn(.05f, 1f) * 345f
            ink(if (i % 2 == 0) 0xff9a6d55 else gold, 4.5f)
            c.drawArc(x - r, y - r, x + r, y + r, -93f, turn, false, paint)
        }
        oval(c, 219f, 145f, 21f, 15f, 0xffd4ae98)
        oval(c, 221f, 145f, 10f, 6.5f, violet)
        leader(c, 255f, 87f, 222f, 140f, R.string.health_atlas_signal_myelin_schwann, violet)
        leader(c, 81f, 298f, 107f, 209f, R.string.health_atlas_signal_myelin_cover, gold)
        leader(c, 243f, 298f, 170f, 192f, R.string.health_atlas_signal_neuro_axon, coral)
    }

    private fun myelinRelay(c: Canvas, active: Boolean, t: Float) {
        axonSection(c, 176f, true)
        if (active) {
            val head = 37f + 287f * t
            line(c, maxOf(34f, head - 38f), 176f, head, 176f, blue, 2f)
            dot(c, head, 176f, 4.3f, blue)
            for (node in nodes) {
                val closeness = (1f - abs(head - node) / 17f).coerceIn(0f, 1f)
                if (closeness > 0f) ring(c, node.toFloat(), 176f, 7f + 10f * closeness, gold)
            }
            leader(c, 212f, 272f, 176f, 177f, R.string.health_atlas_signal_myelin_current, blue)
        } else {
            val activeNode = nodes[(t * nodes.size).toInt().coerceAtMost(nodes.lastIndex)]
            ring(c, activeNode.toFloat(), 176f, 9f + 4f * sin(t * 15f), blue)
            leader(c, 214f, 96f, activeNode.toFloat(), 176f, R.string.health_atlas_signal_myelin_node, blue)
            leader(c, 111f, 262f, 124f, 186f, R.string.health_atlas_signal_myelin_cover, gold)
        }
    }

    private fun compare(c: Canvas, t: Float) {
        for (myelinated in listOf(true, false)) {
            val y = if (myelinated) 131f else 244f
            axonSection(c, y, myelinated)
            val x = 34f + 292f * HealthAtlasSignalMotion.axonTravel(t, myelinated)
            dot(c, x, y, 4.8f, blue)
            if (!myelinated || nodes.any { abs(it - x) < 14f })
                ring(c, x, y, 8f + 3f * sin(t * 13f), gold)
            label(c, 180f, y + 49f, if (myelinated) R.string.health_atlas_signal_myelin_yes
                else R.string.health_atlas_signal_myelin_no)
        }
    }

    private fun axonSection(c: Canvas, y: Float, wrapped: Boolean) {
        line(c, 33f, y, 327f, y, coral, 11f)
        if (wrapped) {
            var previous = 36f
            for (node in nodes) {
                sheath(c, previous, y, node - 6f, 14f)
                previous = node + 6f
            }
            sheath(c, previous, y, 326f, 14f)
        }
        line(c, 34f, y, 326f, y, 0xffefb4a9, 2.1f)
    }

    private fun sheath(c: Canvas, start: Float, y: Float, end: Float, thick: Float) {
        ink(cream); paint.shader = wrapShade
        c.drawRoundRect(start, y - thick, end, y + thick, 9f, 9f, paint); paint.shader = null
        ink(gold, 1.1f); c.drawRoundRect(start, y - thick, end, y + thick, 9f, 9f, paint)
        line(c, start + 5f, y - thick + 5f, end - 5f, y - thick + 5f, cream, 1f)
    }

    private fun trh(c: Canvas, t: Float) {
        c.save()
        c.translate(0f, 41f)
        plate(c, R.drawable.health_atlas_endocrine_pituitary_section, 0, 0, 360, 280)
        for (i in 0..5) marker(c, portal, loop(t * 1.14f + i / 6f)) { cv, x, y -> dot(cv, x, y, 3.7f, teal) }
        c.restore()
        leader(c, 247f, 54f, 189f, 90f, R.string.health_atlas_signal_thyroid_hypo, teal)
        leader(c, 115f, 317f, 132f, 228f, R.string.health_atlas_signal_thyroid_anterior, coral)
        legend(c, 264f, 317f, "TRH", teal)
    }

    private fun tsh(c: Canvas, t: Float) {
        plate(c, R.drawable.health_atlas_endocrine_pituitary_section, 22, 55, 171, 171)
        plate(c, R.drawable.health_atlas_endocrine_thyroid_section, 185, 145, 338, 264)
        shape.rewind()
        tshRoute.getSegment(0f, tshRoute.length, shape, true)
        ink(0xffe1a3a6, 21f); c.drawPath(shape, paint)
        ink(0xfff2c9c1, 12f); c.drawPath(shape, paint)
        for (i in 0..4) {
            val f = loop(t * 1.25f + i / 5f)
            marker(c, tshRoute, f) { cv, x, y ->
                rounded(cv, x - 3.5f, y - 3.5f, x + 3.5f, y + 3.5f, 1.5f, gold)
            }
        }
        label(c, 99f, 46f, R.string.health_atlas_signal_thyroid_anterior)
        label(c, 259f, 282f, R.string.health_atlas_signal_thyroid_gland)
        legend(c, 165f, 294f, "TSH", gold)
    }

    private fun secretion(c: Canvas, t: Float) {
        c.save()
        c.translate(0f, 37f)
        plate(c, R.drawable.health_atlas_endocrine_thyroid_section, 0, 0, 360, 280)
        for (i in 0..5) marker(c, thyroidOut, loop(t * 1.11f + i / 6f)) { cv, x, y ->
            dot(cv, x, y, if (i % 5 == 0) 3.0f else 4.6f, if (i % 5 == 0) teal else violet)
        }
        c.restore()
        leader(c, 93f, 56f, 124f, 107f, R.string.health_atlas_signal_thyroid_follicle, coral)
        leader(c, 263f, 313f, 236f, 272f, R.string.health_atlas_signal_thyroid_blood, coral)
        legend(c, 105f, 316f, "T4", violet)
        legend(c, 168f, 316f, "T3", teal)
    }

    private fun conversion(c: Canvas, t: Float) {
        shadedBox(c, 30f, 101f, 330f, 255f, 24f, receivingShade)
        val fraction = (t * 1.2f).coerceAtMost(1f)
        val x = 113f + fraction * 133f
        val y = 179f + 10f * sin(fraction * PI.toFloat())
        arrow(c, 108f, 215f, 252f, 215f, teal)
        for (i in 0..3) {
            if (i == 3 && fraction > .53f) {
                dot(c, x + 21f * fraction, y - 17f - fraction * 18f, 4f, violet)
            } else {
                val angle = i * 1.57f
                dot(c, x + 10f * cos(angle), y + 10f * sin(angle), 6f, if (fraction < .53f) violet else teal)
            }
        }
        label(c, 180f, 65f, R.string.health_atlas_signal_thyroid_tissue)
        legend(c, 109f, 298f, "T4", violet)
        legend(c, 255f, 298f, "T3", teal)
    }

    private fun feedback(c: Canvas, t: Float) {
        val drive = HealthAtlasSignalMotion.upstreamDrive(t)
        val positions = listOf(74f, 161f, 250f)
        val center = 151f
        val captions = listOf(R.string.health_atlas_signal_thyroid_hypo, R.string.health_atlas_signal_thyroid_anterior,
            R.string.health_atlas_signal_thyroid_gland)
        val tones = longArrayOf(teal, gold, violet)
        for (i in positions.indices) {
            val y = positions[i]
            oval(c, center, y, 21f, 14f, 0xffeed7c9)
            dot(c, center, y, if (i == 2) 5f + 5f * t else 4f + 3f * drive, tones[i])
            label(c, 66f, y + 5f, captions[i])
        }
        val bars = (4f * drive).toInt().coerceAtLeast(1)
        for (i in 0..1) {
            val start = positions[i] + 18f
            val end = positions[i + 1] - 18f
            arrow(c, center, start, center, end, tones[i])
            for (j in 0 until bars) {
                val f = loop(t * 1.5f + j / 4f)
                dot(c, center, start + (end - start) * f, 2.7f, tones[i])
            }
        }
        legend(c, 208f, 121f, "TRH", teal)
        legend(c, 208f, 209f, "TSH", gold)
        line(c, 178f, 250f, 272f, 250f, feedbackInk, 2.1f)
        line(c, 272f, 250f, 272f, 74f, feedbackInk, 2.1f)
        for (y in positions.take(2)) {
            line(c, 272f, y, 183f, y, feedbackInk, 2f)
            line(c, 183f, y - 6f, 183f, y + 6f, feedbackInk, 2.6f)
        }
        val f = loop(t * 1.3f)
        dot(c, 272f, 248f - f * 172f, 3.8f, feedbackInk)
        legend(c, 245f, 287f, "T4 / T3", violet)
        label(c, 223f, 326f, R.string.health_atlas_signal_thyroid_inhibition)
    }

    private fun legend(c: Canvas, x: Float, y: Float, text: String, color: Long) {
        dot(c, x - 26f, y - 4f, 3.7f, color)
        ink(this.text); paint.textSize = 12f
        c.drawText(text, x + 3f, y, paint)
    }
    private fun trail(c: Canvas, track: PathMeasure, f: Float, color: Long) {
        val end = f * track.length
        shape.rewind()
        if (track.getSegment(maxOf(0f, end - 27f), end, shape, true)) {
            ink(cream, 6f); c.drawPath(shape, paint)
            ink(color, 2.7f); c.drawPath(shape, paint)
        }
        if (track.getPosTan(end, xy, null)) dot(c, xy[0], xy[1], 3.3f, color)
    }
    private fun marker(c: Canvas, path: PathMeasure, f: Float, draw: (Canvas, Float, Float) -> Unit) {
        if (path.getPosTan(path.length * f, xy, null)) draw(c, xy[0], xy[1])
    }
    private fun leader(c: Canvas, x: Float, y: Float, tx: Float, ty: Float, res: Int, color: Long) {
        line(c, x, if (ty < y) y - 16f else y + 5f, tx, ty, color, 1.1f)
        dot(c, tx, ty, 2.1f, color)
        label(c, x, y, res)
    }
    private fun label(c: Canvas, x: Float, y: Float, res: Int) {
        ink(text); paint.textSize = 13f
        val label = context.getString(res)
        val available = 2f * minOf(x - 8f, 352f - x)
        val width = paint.measureText(label)
        if (width > available) paint.textSize *= available / width
        c.drawText(label, x, y, paint)
    }
    private fun paintPath(c: Canvas, shader: Shader, color: Long) {
        ink(cream); paint.shader = shader; c.drawPath(shape, paint); paint.shader = null
        ink(color, 1.5f); c.drawPath(shape, paint)
    }
    private fun rounded(c: Canvas, l: Float, t: Float, r: Float, b: Float, radius: Float, color: Long) {
        ink(color); c.drawRoundRect(l, t, r, b, radius, radius, paint)
    }
    private fun shadedBox(c: Canvas, l: Float, t: Float, r: Float, b: Float, radius: Float, shade: Shader) {
        ink(cream); paint.shader = shade
        c.drawRoundRect(l, t, r, b, radius, radius, paint); paint.shader = null
    }
    private fun arrow(c: Canvas, x: Float, y: Float, tx: Float, ty: Float, color: Long) {
        val distance = sqrt((tx - x) * (tx - x) + (ty - y) * (ty - y))
        val ux = (tx - x) / distance
        val uy = (ty - y) / distance
        line(c, x, y, tx, ty, color, 1.7f)
        line(c, tx, ty, tx - 6f * ux + 3.2f * uy, ty - 6f * uy - 3.2f * ux, color, 1.7f)
        line(c, tx, ty, tx - 6f * ux - 3.2f * uy, ty - 6f * uy + 3.2f * ux, color, 1.7f)
    }
    private fun dot(c: Canvas, x: Float, y: Float, r: Float, color: Long) {
        oval(c, x, y, r + .7f, r + .7f, cream); oval(c, x, y, r, r, color)
    }
    private fun ring(c: Canvas, x: Float, y: Float, r: Float, color: Long) {
        ink(color, 1.6f); c.drawCircle(x, y, r, paint)
    }
    private fun oval(c: Canvas, x: Float, y: Float, rx: Float, ry: Float, color: Long) {
        ink(color); c.drawOval(x - rx, y - ry, x + rx, y + ry, paint)
    }
    private fun line(c: Canvas, x: Float, y: Float, tx: Float, ty: Float, color: Long, width: Float) {
        ink(color, width); c.drawLine(x, y, tx, ty, paint)
    }
    private fun plate(c: Canvas, id: Int, l: Int, top: Int, r: Int, b: Int) {
        artwork.getOrPut(id) { requireNotNull(context.getDrawable(id)).mutate() }.apply {
            setBounds(l, top, r, b); draw(c)
        }
    }
    private fun ink(color: Long, width: Float = 0f) {
        paint.color = color.toInt()
        paint.style = if (width == 0f) Paint.Style.FILL else Paint.Style.STROKE
        paint.strokeWidth = width
    }
    private inline fun path(build: Path.() -> Unit) { shape.rewind(); shape.build() }
    private inline fun track(build: Path.() -> Unit) = PathMeasure(Path().apply(build), false)
    private fun loop(t: Float) = t % 1f
    private fun shade(top: Float, bottom: Float, a: Long, b: Long) =
        LinearGradient(0f, top, 0f, bottom, a.toInt(), b.toInt(), Shader.TileMode.CLAMP)
}
