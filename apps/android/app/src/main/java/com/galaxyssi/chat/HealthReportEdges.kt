package com.galaxyssi.chat

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor

/** Thousandths of the upright image. Bounds contain all four fitted paper corners. */
internal data class HealthReportCrop(val left: Int, val top: Int, val right: Int, val bottom: Int) {
    fun encode() = intArrayOf(left, top, right, bottom)
    fun pixels(width: Int, height: Int) = intArrayOf(left * width / 1000, top * height / 1000,
        (right * width + 999) / 1000, (bottom * height + 999) / 1000)
    companion object {
        fun from(bounds: IntArray?): HealthReportCrop? {
            if (bounds == null || bounds.size != 4 || bounds.any { it !in 0..1000 } ||
                bounds[2] - bounds[0] < 300 || bounds[3] - bounds[1] < 300) return null
            return HealthReportCrop(bounds[0], bounds[1], bounds[2], bounds[3])
        }
    }
}

/** Conservative four-edge suggestion for light paper against a darker surround. */
internal object HealthReportEdges {
    private const val MAX_EDGE = 320
    private const val SCANS = 21
    private data class Point(val x: Double, val y: Double)
    private data class Line(val offset: Double, val slope: Double) {
        fun at(position: Double) = offset + slope * position
    }

    fun detect(gray: IntArray, width: Int, height: Int): HealthReportCrop? {
        require(width > 0 && height > 0 && width.toLong() * height == gray.size.toLong())
        val stride = (maxOf(width, height) + MAX_EDGE - 1) / MAX_EDGE
        val w = width / stride
        val h = height / stride
        if (minOf(w, h) < 44) return null
        if (stride == 1) return fit(gray, w, h)
        val small = IntArray(w * h)
        try {
            val low = stride / 4
            val high = stride - 1 - low
            for (y in 0 until h) for (x in 0 until w) {
                val col = x * stride
                val top = (y * stride + low) * width
                val bottom = (y * stride + high) * width
                small[y * w + x] = (gray[top + col + low] + gray[top + col + high] +
                    gray[bottom + col + low] + gray[bottom + col + high]) / 4
            }
            val crop = fit(small, w, h) ?: return null
            return HealthReportCrop(crop.left * (w * stride) / width, crop.top * (h * stride) / height,
                ((crop.right * (w * stride) + width - 1) / width).coerceAtMost(1000),
                ((crop.bottom * (h * stride) + height - 1) / height).coerceAtMost(1000))
        } finally { small.fill(0) }
    }

    private fun fit(gray: IntArray, w: Int, h: Int): HealthReportCrop? {
        val left = edge(gray, w, h, horizontal = true, reverse = false) ?: return null
        val right = edge(gray, w, h, horizontal = true, reverse = true) ?: return null
        val top = edge(gray, w, h, horizontal = false, reverse = false) ?: return null
        val bottom = edge(gray, w, h, horizontal = false, reverse = true) ?: return null
        fun intersection(vertical: Line, across: Line): Point {
            val x = (vertical.offset + vertical.slope * across.offset) / (1 - vertical.slope * across.slope)
            return Point(x, across.at(x))
        }
        val tl = intersection(left, top); val tr = intersection(right, top)
        val bl = intersection(left, bottom); val br = intersection(right, bottom)
        val points = listOf(tl, tr, br, bl)
        if (points.any { it.x !in 2.0..(w - 3.0) || it.y !in 2.0..(h - 3.0) } ||
            minOf(tr.x - tl.x, br.x - bl.x) < w * .31 || minOf(bl.y - tl.y, br.y - tr.y) < h * .31) return null
        val area = points.indices.sumOf { i -> points[i].x * points[(i + 1) % 4].y - points[i].y * points[(i + 1) % 4].x } / 2
        if (area !in (w * h * .23)..(w * h * .93)) return null
        val padX = maxOf(2.0, w * .019); val padY = maxOf(2.0, h * .019)
        val bounds = intArrayOf(
            floor((points.minOf { it.x } - padX) * 1000 / w).toInt().coerceAtLeast(0),
            floor((points.minOf { it.y } - padY) * 1000 / h).toInt().coerceAtLeast(0),
            ceil((points.maxOf { it.x } + padX) * 1000 / w).toInt().coerceAtMost(1000),
            ceil((points.maxOf { it.y } + padY) * 1000 / h).toInt().coerceAtMost(1000))
        if (bounds[0] + bounds[1] + (1000 - bounds[2]) + (1000 - bounds[3]) < 90) return null
        return HealthReportCrop.from(bounds)
    }

    private fun edge(gray: IntArray, w: Int, h: Int, horizontal: Boolean, reverse: Boolean): Line? {
        val span = if (horizontal) w else h
        val length = if (horizontal) h else w
        val strip = (span / 55).coerceIn(2, 5)
        val prefix = IntArray(span + 1)
        val candidates = ArrayList<Point>(SCANS)
        try {
            for (scan in 0 until SCANS) {
                val at = (length * (.23 + .54 * scan / (SCANS - 1))).toInt()
                for (i in 0 until span) {
                    val coordinate = if (reverse) span - 1 - i else i
                    val pixel = if (horizontal) at * w + coordinate else coordinate * w + at
                    prefix[i + 1] = prefix[i] + gray[pixel]
                }
                var score = 0.0
                var best = -1
                for (i in strip + 1 until (span * .43).toInt()) {
                    val inside = (prefix[i + strip] - prefix[i]) / strip
                    val outside = (prefix[i] - prefix[i - strip]) / strip
                    val plateau = (prefix[i + 4 * strip] - prefix[i + 2 * strip]) / (2 * strip)
                    val strength = minOf(inside, plateau) - outside
                    if (minOf(inside, plateau) < 110 || strength < 23) continue
                    val rank = strength - i * .10
                    if (rank > score) { score = rank; best = i }
                }
                if (best >= 0) candidates += Point(at.toDouble(), if (reverse) span - best.toDouble() else best.toDouble())
            }
        } finally { prefix.fill(0) }
        if (candidates.size < 15) return null
        val tolerance = maxOf(1.6, span * .014)
        var consensus = emptyList<Point>()
        var error = Double.MAX_VALUE
        for ((i, a) in candidates.withIndex()) for (j in i + 1 until candidates.size) {
            val b = candidates[j]
            if (b.x - a.x < length * .23) continue
            val slope = (b.y - a.y) / (b.x - a.x)
            if (abs(slope) > .46) continue
            val line = Line(a.y - slope * a.x, slope)
            val inliers = candidates.filter { abs(it.y - line.at(it.x)) <= tolerance }
            if (inliers.size < 15 || inliers.last().x - inliers.first().x < length * .40) continue
            val residual = inliers.sumOf { abs(it.y - line.at(it.x)) }
            if (inliers.size > consensus.size || inliers.size == consensus.size && residual < error) {
                consensus = inliers
                error = residual
            }
        }
        if (consensus.isEmpty()) return null
        val centerX = consensus.map { it.x }.average(); val centerY = consensus.map { it.y }.average()
        val slope = consensus.sumOf { (it.x - centerX) * (it.y - centerY) } / consensus.sumOf { (it.x - centerX) * (it.x - centerX) }
        return Line(centerY - slope * centerX, slope).takeIf { abs(slope) <= .46 }
    }
}
