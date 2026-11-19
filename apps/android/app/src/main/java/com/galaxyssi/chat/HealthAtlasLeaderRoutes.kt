package com.galaxyssi.chat

import kotlin.math.hypot

internal data class HealthAtlasLeaderPoint(val x: Float, val y: Float) {
    init { require(x.isFinite() && y.isFinite()) }
}

/** Small visibility graph for label leaders. Recomputed on layout, never on animation frames. */
internal object HealthAtlasLeaderRoutes {
    fun route(start: HealthAtlasLeaderPoint, end: HealthAtlasLeaderPoint,
        obstacles: List<HealthAtlasLeaderPoint>, clearance: Float): List<HealthAtlasLeaderPoint> {
        require(clearance.isFinite() && clearance > 0f)
        fun distance(a: HealthAtlasLeaderPoint, b: HealthAtlasLeaderPoint) = hypot(a.x - b.x, a.y - b.y)
        fun visible(a: HealthAtlasLeaderPoint, b: HealthAtlasLeaderPoint) = obstacles.all {
            segmentDistance(it, a, b) >= clearance
        }
        if (visible(start, end)) return listOf(start, end)
        // Coincident/overlapping targets cannot have an unambiguous leader; keep their markers only.
        if (obstacles.any { distance(it, start) < clearance || distance(it, end) < clearance }) return emptyList()
        val offset = clearance * 1.5f
        val candidates = obstacles.flatMap { p -> listOf(
            HealthAtlasLeaderPoint(p.x - offset, p.y - offset), HealthAtlasLeaderPoint(p.x + offset, p.y - offset),
            HealthAtlasLeaderPoint(p.x + offset, p.y + offset), HealthAtlasLeaderPoint(p.x - offset, p.y + offset)) }
        val points = listOf(start, end) + candidates.distinct().filter { point -> obstacles.all { distance(point, it) >= clearance } }
        val costs = Array(points.size) { FloatArray(points.size) { Float.POSITIVE_INFINITY } }
        for (i in points.indices) for (j in 0 until i) if (visible(points[i], points[j])) {
            val cost = distance(points[i], points[j]); costs[i][j] = cost; costs[j][i] = cost
        }
        val best = FloatArray(points.size) { Float.POSITIVE_INFINITY }.apply { this[0] = 0f }
        val previous = IntArray(points.size) { -1 }
        val visited = BooleanArray(points.size)
        repeat(points.size) {
            val current = points.indices.filter { !visited[it] }.minByOrNull { best[it] } ?: return emptyList()
            if (!best[current].isFinite()) return emptyList()
            if (current == 1) {
                val path = mutableListOf<HealthAtlasLeaderPoint>()
                var index = 1
                while (index >= 0) { path += points[index]; index = previous[index] }
                return path.asReversed()
            }
            visited[current] = true
            for (next in points.indices) if (!visited[next]) {
                val cost = best[current] + costs[current][next]
                if (cost < best[next]) { best[next] = cost; previous[next] = current }
            }
        }
        return emptyList()
    }

    fun segmentDistance(point: HealthAtlasLeaderPoint, start: HealthAtlasLeaderPoint, end: HealthAtlasLeaderPoint): Float {
        val dx = end.x - start.x; val dy = end.y - start.y
        val lengthSquared = dx * dx + dy * dy
        if (lengthSquared == 0f) return hypot(point.x - start.x, point.y - start.y)
        val t = (((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared).coerceIn(0f, 1f)
        return hypot(point.x - start.x - t * dx, point.y - start.y - t * dy)
    }
}
