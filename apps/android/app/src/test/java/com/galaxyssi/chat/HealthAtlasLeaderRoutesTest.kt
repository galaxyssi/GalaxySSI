package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasLeaderRoutesTest {
    private fun p(x: Float, y: Float) = HealthAtlasLeaderPoint(x, y)
    private fun verify(start: HealthAtlasLeaderPoint, end: HealthAtlasLeaderPoint, obstacles: List<HealthAtlasLeaderPoint>, radius: Float) {
        val path = HealthAtlasLeaderRoutes.route(start, end, obstacles, radius)
        assertEquals(start, path.first()); assertEquals(end, path.last())
        for ((a, b) in path.zipWithNext()) for (obstacle in obstacles)
            assertTrue(HealthAtlasLeaderRoutes.segmentDistance(obstacle, a, b) >= radius - .001f)
        assertEquals(path, HealthAtlasLeaderRoutes.route(start, end, obstacles, radius))
    }
    @Test fun clearLeadersRemainStraight() {
        val start = p(10f, 20f); val end = p(300f, 20f)
        assertEquals(listOf(start, end), HealthAtlasLeaderRoutes.route(start, end, listOf(p(100f, 80f)), 10f))
    }
    @Test fun collinearAndClusteredTargetsAreAvoidedAtMultipleScales() {
        for (scale in listOf(.5f, 1f, 2f, 3f)) {
            val obstacles = listOf(p(80f * scale, 0f), p(110f * scale, 8f * scale), p(180f * scale, 0f))
            verify(p(0f, 0f), p(300f * scale, 0f), obstacles, 12f * scale)
        }
    }
    @Test fun steepAndReversedLeadersRetainTheirEndpoints() {
        verify(p(20f, 200f), p(50f, 0f), listOf(p(35f, 100f)), 10f)
        verify(p(300f, 40f), p(0f, 0f), listOf(p(150f, 20f)), 10f)
    }
    @Test fun overlappingEndpointsDoNotDrawAnAmbiguousConnection() {
        assertTrue(HealthAtlasLeaderRoutes.route(p(0f, 0f), p(100f, 0f), listOf(p(0f, 1f)), 10f).isEmpty())
    }
    @Test fun degenerateSegmentsAndInvalidInputsAreHandled() {
        assertEquals(5f, HealthAtlasLeaderRoutes.segmentDistance(p(3f, 4f), p(0f, 0f), p(0f, 0f)), .001f)
        assertThrows(IllegalArgumentException::class.java) { HealthAtlasLeaderRoutes.route(p(0f, 0f), p(1f, 1f), emptyList(), 0f) }
        assertThrows(IllegalArgumentException::class.java) { p(Float.NaN, 0f) }
    }
}
