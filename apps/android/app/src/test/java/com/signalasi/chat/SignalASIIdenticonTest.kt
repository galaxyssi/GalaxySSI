package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SignalASIIdenticonTest {
    @Test
    fun sameIdentityProducesStablePatternAndColor() {
        val first = SignalASIIdenticon.fromIdentityFingerprint("ab".repeat(32))
        val second = SignalASIIdenticon.fromIdentityFingerprint("AB".repeat(32))

        assertEquals(first, second)
    }

    @Test
    fun differentIdentitiesProduceDifferentIdenticons() {
        val first = SignalASIIdenticon.fromIdentityFingerprint("ab".repeat(32))
        val second = SignalASIIdenticon.fromIdentityFingerprint("cd".repeat(32))

        assertNotEquals(first, second)
    }

    @Test
    fun generatedPatternIsHorizontallySymmetric() {
        val pattern = SignalASIIdenticon.fromIdentityFingerprint("12".repeat(32))

        for (row in 0 until SignalASIIdenticonPattern.GRID_SIZE) {
            for (column in 0 until SignalASIIdenticonPattern.GRID_SIZE) {
                assertEquals(
                    pattern.isFilled(row, column),
                    pattern.isFilled(row, SignalASIIdenticonPattern.GRID_SIZE - column - 1)
                )
            }
        }
        assertTrue(pattern.cells.any { it })
    }
}
