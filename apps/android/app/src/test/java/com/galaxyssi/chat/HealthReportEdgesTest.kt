package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthReportEdgesTest {
    private data class Corner(val x: Double, val y: Double)
    private val upright = listOf(Corner(.19, .12), Corner(.79, .12), Corner(.79, .89), Corner(.19, .89))

    private fun scene(width: Int, height: Int, points: List<Corner>, contrast: Int = 155): IntArray =
        IntArray(width * height) { index ->
            val x = (index % width).toDouble() / width
            val y = (index / width).toDouble() / height
            val inside = points.indices.all { i ->
                val a = points[i]; val b = points[(i + 1) % points.size]
                (b.x - a.x) * (y - a.y) >= (b.y - a.y) * (x - a.x)
            }
            val ink = inside && x in .29.. .67 && y in .24.. .75 && index / width % 19 in 0..2 && index % width % 22 < 12
            val background = 54 + (23 * x + 14 * y).toInt() + (index * 17 % 11)
            if (ink) 40 else (background + if (inside) contrast else 0).coerceAtMost(255)
        }

    private fun containsPaper(crop: HealthReportCrop, points: List<Corner>) {
        assertTrue("Left edge must not clip the paper", crop.left < points.minOf { it.x } * 1000)
        assertTrue("Top edge must not clip the paper", crop.top < points.minOf { it.y } * 1000)
        assertTrue("Right edge must not clip the paper", crop.right > points.maxOf { it.x } * 1000)
        assertTrue("Bottom edge must not clip the paper", crop.bottom > points.maxOf { it.y } * 1000)
        assertTrue("Useful crop should not include the whole scene", crop.left > 45 && crop.top > 40 && crop.right < 965 && crop.bottom < 980)
    }

    @Test fun sharpPaperWithTextAndMildShadowKeepsMarginsAtSeveralResolutions() {
        for ((w, h) in listOf(200 to 280, 481 to 659, 925 to 1217)) {
            val crop = requireNotNull(HealthReportEdges.detect(scene(w, h, upright), w, h))
            containsPaper(crop, upright)
            assertTrue(crop.left in 150..185 && crop.right in 795..835)
        }
    }

    @Test fun mildlySkewedReportUsesAllFourCornersRatherThanCenterEdges() {
        val skewed = listOf(Corner(.24, .13), Corner(.79, .19), Corner(.75, .89), Corner(.15, .82))
        val crop = requireNotNull(HealthReportEdges.detect(scene(260, 320, skewed), 260, 320))
        containsPaper(crop, skewed)
    }

    @Test fun clippedLowContrastAndBorderlessScenesDoNotSuggestACrop() {
        val clipped = upright.map { if (it.x < .5) it.copy(x = -.03) else it }
        assertNull(HealthReportEdges.detect(scene(240, 320, clipped), 240, 320))
        assertNull(HealthReportEdges.detect(scene(240, 320, upright, contrast = 16), 240, 320))
        val flat = IntArray(240 * 320) { 210 }
        assertNull(HealthReportEdges.detect(flat, 240, 320))
        val textOnly = IntArray(240 * 320) { if (it / 240 % 23 < 4 && it % 240 in 40..200) 30 else 218 }
        assertNull(HealthReportEdges.detect(textOnly, 240, 320))
    }

    @Test fun normalizedBoundsRejectInvalidAndRoundOutwardAtCropResolution() {
        assertNull(HealthReportCrop.from(intArrayOf(20, 20, 240, 900)))
        assertNull(HealthReportCrop.from(intArrayOf(20, -1, 800, 900)))
        assertArrayEquals(intArrayOf(13, 46, 99, 156), HealthReportCrop(101, 234, 753, 784).pixels(131, 198))
    }
}
