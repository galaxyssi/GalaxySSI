package com.galaxyssi.chat

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Path
import android.view.View
import kotlin.math.abs
import kotlin.math.sin

internal class HealthAtlasSubcutaneousStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.SUBCUTANEOUS_CUSHION) {
    private val plate by lazy {
        Bitmap.createBitmap(720, 560, Bitmap.Config.ARGB_8888).also { bitmap ->
            requireNotNull(context.getDrawable(R.drawable.health_atlas_subcutaneous_section)).apply {
                setBounds(0, 0, bitmap.width, bitmap.height)
                draw(Canvas(bitmap))
            }
        }
    }
    private val mesh = FloatArray((COLUMNS + 1) * (ROWS + 1) * 2)
    private val pressure = 0xff477f8d
    private val lighter = 0xffc3e2e1
    private val boundary = 0xff668983
    private val left = Path().apply {
        moveTo(180f, 148f); cubicTo(156f, 176f, 141f, 204f, 94f, 222f)
    }
    private val right = Path().apply {
        moveTo(180f, 148f); cubicTo(204f, 176f, 219f, 204f, 266f, 222f)
    }
    private val leftMeasure = track(left)
    private val rightMeasure = track(right)

    init {
        paint.isFilterBitmap = true
        tag = "atlas-function-subcutaneous-cushion-art"
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
    }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val compress = when (step) {
            0 -> 0f
            1 -> smooth(t)
            2 -> 1f
            else -> 1f - smooth(t)
        }
        section(c, compress)
        when (step) {
            0 -> layers(c, t)
            1 -> contact(c, compress)
            2 -> {
                contact(c, compress)
                spread(c, t)
            }
            else -> {
                contact(c, compress)
                val rest = 91f
                repeat(11) { index ->
                    val x = 119f + index * 11f
                    line(c, x, rest, x + 5f, rest, 0xff9a9685, 1.3f)
                }
                label(c, R.string.health_atlas_subcutaneous_reference_surface, 180f, 334f, 265f)
            }
        }
    }

    private fun section(c: Canvas, compression: Float) {
        var i = 0
        for (row in 0..ROWS) {
            val y = row * (280f / ROWS)
            for (column in 0..COLUMNS) {
                val x = column * (360f / COLUMNS)
                val relative = (x - 180f) / 100f
                val across = (1f - relative * relative).coerceAtLeast(0f)
                val depth = ((223f - y) / 172f).coerceIn(0f, 1f)
                val bulge = (1f - abs(y - 153f) / 75f).coerceAtLeast(0f)
                mesh[i++] = x + 15f * compression * relative * across * bulge
                mesh[i++] = 42f + y + 28f * compression * across * depth
            }
        }
        ink(0xffffffff)
        c.drawBitmapMesh(plate, COLUMNS, ROWS, mesh, 0, null, 0, paint)
    }

    private fun layers(c: Canvas, t: Float) {
        val halo = (2f + 5f * sin(t * Math.PI)).toFloat()
        callout(c, R.string.health_atlas_subcutaneous_epidermis, 72f, 84f, 103f, halo)
        callout(c, R.string.health_atlas_subcutaneous_lobule, 180f, 160f, 191f, halo)
        callout(c, R.string.health_atlas_subcutaneous_fascia, 293f, 294f, 268f, halo)
        label(c, R.string.health_atlas_subcutaneous_deep_muscle, 180f, 329f, 160f)
    }

    private fun callout(c: Canvas, title: Int, x: Float, targetX: Float, targetY: Float, halo: Float) {
        line(c, x, 46f, targetX, targetY, 0xff71938e, 1.2f)
        disc(c, targetX, targetY, halo + 3f, 0x8079b6ad)
        disc(c, targetX, targetY, 3.2f, boundary, cream)
        label(c, title, x, 35f, 110f)
    }

    private fun contact(c: Canvas, f: Float) {
        val y = 91f + 28f * f
        val radius = 31f + 13f * f
        rounded(c, 180f - radius, y - 12f, 180f + radius, y + 2f, 5f, lighter)
        line(c, 182f - radius, y + 1.7f, 178f + radius, y + 1.7f, pressure, 1.7f)
        for (x in listOf(160f, 180f, 200f)) arrow(c, x, y - 36f, x, y - 15f, pressure)
        label(c, R.string.health_atlas_subcutaneous_load, 180f, 29f, 234f)
    }

    private fun spread(c: Canvas, t: Float) {
        stroke(c, left, lighter, 7.2f)
        stroke(c, right, lighter, 7.2f)
        stroke(c, left, pressure, 1.9f)
        stroke(c, right, pressure, 1.9f)
        arrow(c, 110f, 216f, 94f, 222f, pressure)
        arrow(c, 250f, 216f, 266f, 222f, pressure)
        for (measure in listOf(leftMeasure, rightMeasure)) at(measure, t) { x, y ->
            disc(c, x, y, 5.2f, cream, pressure)
        }
        label(c, R.string.health_atlas_subcutaneous_force_spread, 180f, 334f, 260f)
    }

    private fun smooth(t: Float) = t * t * (3f - 2f * t)

    private companion object {
        const val COLUMNS = 24
        const val ROWS = 20
    }
}
