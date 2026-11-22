package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Path
import androidx.annotation.StringRes
import com.galaxyssi.chat.HealthAtlasTenocyteTendonMatrixAssignment.ALIGNMENT
import com.galaxyssi.chat.HealthAtlasTenocyteTendonMatrixAssignment.MATRIX_PULL
import com.galaxyssi.chat.HealthAtlasTenocyteTendonMatrixAssignment.RECOVERY
import com.galaxyssi.chat.HealthAtlasTenocyteTendonMatrixAssignment.STRAIN_TRANSFER
import com.galaxyssi.chat.R.string

internal object HealthAtlasTenocyteTendonMatrixMotion {
    // Unitless drawing poses, not measurements of tissue or cell strain.
    fun deformation(step: Int, fraction: Float): Float {
        val t = fraction.coerceIn(0f, 1f)
        val eased = t * t * (3f - 2f * t)
        return when (step) {
            MATRIX_PULL -> .56f * eased
            STRAIN_TRANSFER -> .56f + .44f * eased
            RECOVERY -> 1f - eased
            else -> 0f
        }
    }
}

internal class HealthAtlasTenocyteTendonMatrixStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val fiberInk = 0xff6b8f87
    private val adjacentInk = 0xff406f67
    private val cellInk = 0xff715163
    private val nucleusInk = 0xff584051
    private val markerInk = 0xff80513b
    private val restInk = 0xff526267
    private val leaderInk = 0xff586f68
    private val fiberYs = floatArrayOf(78f, 89f, 106f, 119f, 167f, 179f, 196f, 208f)
    private val field = Path().apply { addRoundRect(20f, 70f, 340f, 217f, 8f, 8f, Path.Direction.CW) }
    private val path = Path()
    private val resting = Path()
    private val dash = DashPathEffect(floatArrayOf(4f, 3f), 0f)

    init { tag = "atlas-function-tenocyte-tendon-matrix-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val amount = HealthAtlasTenocyteTendonMatrixMotion.deformation(step, t)
        drawAxis(c, step, amount, t)
        drawMatrix(c, amount)
        callout(c, string.health_atlas_tenocyte_tendon_matrix_art_fibers, 94f, 84f, 196f, adjacentInk)
        callout(c, string.health_atlas_tenocyte_tendon_matrix_art_nucleus, 251f, 196f, 143f - 2f * amount, nucleusInk)
        drawProfile(c, amount)
    }

    private fun drawAxis(c: Canvas, step: Int, amount: Float, phase: Float) {
        val text = when (step) {
            ALIGNMENT -> string.health_atlas_tenocyte_tendon_matrix_art_axis
            RECOVERY -> string.health_atlas_tenocyte_tendon_matrix_art_release
            else -> string.health_atlas_tenocyte_tendon_matrix_art_pull
        }
        label(c, text, 180f, 33f, 152f)
        val reach = 18f + 36f * amount
        val color = if (step == ALIGNMENT) leaderInk else markerInk
        arrow(c, 125f, 49f, 125f - reach, 49f, color)
        arrow(c, 235f, 49f, 235f + reach, 49f, color)
        if (step == ALIGNMENT) {
            disc(c, 125f - reach * phase, 49f, 3.1f, cream, fiberInk)
            disc(c, 235f + reach * phase, 49f, 3.1f, cream, fiberInk)
        }
    }

    private fun drawMatrix(c: Canvas, amount: Float) {
        ink(0xffe9f1ec)
        c.drawPath(field, paint)
        c.save()
        c.clipPath(field)
        for (row in fiberYs.indices) {
            val y = fiberYs[row]
            val adjacent = row == 3 || row == 4
            val shift = (3.5f - row) * 5f * amount
            val spread = 1f + .13f * amount
            val x = 180f + shift
            val rise = (if (row % 2 == 0) 3.1f else 4.6f) * (1f - .74f * amount)
            fiberPath(x, y, spread, rise)
            stroke(c, path, if (adjacent) 0xffb7d2c7 else 0xffcfdfd8, if (adjacent) 8f else 6f)
            stroke(c, path, if (adjacent) adjacentInk else fiberInk, if (adjacent) 1.8f else 1.1f)
            if (adjacent) {
                matrixMarks(c, x - 46f * spread, x + 46f * spread, y)
            }
        }
        drawCell(c, 85f - 4f * amount, 97f, 31f, 4.5f, 0f, secondary = true)
        drawCell(c, 274f + 3f * amount, 187f, 37f, 4.8f, 0f, secondary = true)
        drawCell(c, 180f, 143f, 57f, 12f, amount)
        c.restore()
        stroke(c, field, 0xff9cb5ae, 1.1f)
    }

    private fun fiberPath(x: Float, y: Float, spread: Float, rise: Float) {
        // Both tracking marks are at shared curve vertices, so each stays on its fiber.
        path.rewind()
        path.moveTo(x - 190f * spread, y)
        path.cubicTo(x - 148f * spread, y - rise, x - 84f * spread, y + rise, x - 46f * spread, y)
        path.cubicTo(x - 14f * spread, y - rise, x + 15f * spread, y + rise, x + 46f * spread, y)
        path.cubicTo(x + 86f * spread, y - rise, x + 145f * spread, y + rise, x + 190f * spread, y)
    }

    private fun matrixMarks(c: Canvas, left: Float, right: Float, y: Float) {
        path.rewind()
        path.moveTo(left, y - 4.5f)
        path.lineTo(left + 4.5f, y)
        path.lineTo(left, y + 4.5f)
        path.lineTo(left - 4.5f, y)
        path.close()
        ink(cream)
        c.drawPath(path, paint)
        stroke(c, path, markerInk, 1.5f)
        disc(c, right, y, 3.8f, cream, markerInk)
    }

    private fun drawCell(c: Canvas, x: Float, y: Float, length: Float, height: Float, amount: Float, secondary: Boolean = false) {
        cellPath(path, x, y, length, height, amount)
        ink(if (secondary) 0xffc6afb9 else 0xffe2bdc8)
        c.drawPath(path, paint)
        stroke(c, path, cellInk, if (secondary) 1f else 1.55f)

        cellPath(path, x + 2f, y, length * .40f, height * .56f, amount)
        ink(nucleusInk)
        c.drawPath(path, paint)
        if (!secondary) {
            line(c, x - length * .22f, y - 1.4f, x + length * .25f, y - 2.4f * amount, 0xffb68e9d, 1.15f)
        }
    }

    private fun cellPath(p: Path, x: Float, y: Float, length: Float, height: Float, amount: Float) {
        val halfLength = length * (1f + .23f * amount)
        val halfHeight = height * (1f - .12f * amount)
        val skew = halfHeight * .64f * amount
        p.rewind()
        p.moveTo(x - halfLength, y + skew)
        p.cubicTo(x - .44f * halfLength, y - halfHeight + skew, x + .12f * halfLength,
            y - halfHeight - skew, x + halfLength, y - skew)
        p.cubicTo(x + .24f * halfLength, y + halfHeight - skew, x - .40f * halfLength,
            y + halfHeight + skew, x - halfLength, y + skew)
        p.close()
    }

    private fun callout(c: Canvas, @StringRes text: Int, labelX: Float, targetX: Float, targetY: Float, color: Long) {
        line(c, targetX, targetY, labelX, 224f, 0xfff6f6e9, 3.1f)
        line(c, targetX, targetY, labelX, 224f, leaderInk, 1.1f)
        disc(c, targetX, targetY, 2.8f, cream, color)
        label(c, text, labelX, 241f, 139f)
    }

    private fun drawProfile(c: Canvas, amount: Float) {
        line(c, 30f, 254f, 330f, 254f, 0xffb3c2b7, 1f)
        label(c, string.health_atlas_tenocyte_tendon_matrix_art_profile, 180f, 275f, 220f)
        drawCell(c, 180f, 298f, 73f, 16f, amount)
        cellPath(resting, 180f, 298f, 73f, 16f, 0f)
        ink(restInk, 1.2f)
        paint.pathEffect = dash
        c.drawPath(resting, paint)
        c.drawLine(100f, 332f, 124f, 332f, paint)
        paint.pathEffect = null
        label(c, string.health_atlas_tenocyte_tendon_matrix_art_rest, 190f, 337f, 116f)
    }
}
