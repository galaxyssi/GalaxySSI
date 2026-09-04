package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GalaxySSIIdenticonTest {
    @Test
    fun sameIdentityProducesStablePatternAndColor() {
        val first = GalaxySSIIdenticon.fromIdentityFingerprint("ab".repeat(32))
        val second = GalaxySSIIdenticon.fromIdentityFingerprint("AB".repeat(32))

        assertEquals(first, second)
    }

    @Test
    fun differentIdentitiesProduceDifferentIdenticons() {
        val first = GalaxySSIIdenticon.fromIdentityFingerprint("ab".repeat(32))
        val second = GalaxySSIIdenticon.fromIdentityFingerprint("cd".repeat(32))

        assertNotEquals(first, second)
    }

    @Test
    fun generatedPatternIsHorizontallySymmetric() {
        val pattern = GalaxySSIIdenticon.fromIdentityFingerprint("12".repeat(32))

        for (row in 0 until GalaxySSIIdenticonPattern.GRID_SIZE) {
            for (column in 0 until GalaxySSIIdenticonPattern.GRID_SIZE) {
                assertEquals(
                    pattern.isFilled(row, column),
                    pattern.isFilled(row, GalaxySSIIdenticonPattern.GRID_SIZE - column - 1)
                )
            }
        }
        assertTrue(pattern.cells.any { it })
    }
}
