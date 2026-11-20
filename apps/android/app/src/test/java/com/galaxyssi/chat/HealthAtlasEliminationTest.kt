package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasEliminationTest {
    @Test fun normalizedEliminationHalvesAtEachHalfLife() {
        val model = HealthAtlasElimination(4, 8)
        assertEquals(100.0, model.percentAt(0.0), 0.000001)
        assertEquals(50.0, model.percentAt(4.0), 0.000001)
        assertEquals(25.0, model.percent, 0.000001)
        assertEquals(3.125, model.percentAt(20.0), 0.000001)
    }
    @Test fun supportedInputsRemainBoundedAndMonotonic() {
        for (halfLife in 1..24) {
            val model = HealthAtlasElimination(halfLife, 0)
            var previous = 100.0
            for (quarter in 0..192) {
                val current = model.percentAt(quarter / 4.0)
                assertTrue(current.isFinite() && current in 0.0..100.0 && current <= previous)
                previous = current
            }
        }
    }
    @Test fun invalidAndNonfiniteParametersAreRejected() {
        for (halfLife in listOf(-1, 0, 25)) assertTrue(runCatching { HealthAtlasElimination(halfLife, 0) }.isFailure)
        for (elapsed in listOf(-1, 49)) assertTrue(runCatching { HealthAtlasElimination(4, elapsed) }.isFailure)
        for (time in listOf(Double.NaN, Double.POSITIVE_INFINITY, -0.1, 48.1))
            assertTrue(runCatching { HealthAtlasElimination().percentAt(time) }.isFailure)
    }
}
