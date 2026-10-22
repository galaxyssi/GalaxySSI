package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MainPageBackPressGateTest {
    @Test fun firstPressNeverBackgrounds() {
        assertFalse(MainPageBackPressGate().shouldBackground(0))
        assertFalse(MainPageBackPressGate().shouldBackground(100_000))
    }

    @Test fun secondPressWithinOneSecondBackgrounds() {
        for (gap in listOf(1L, 300L, 999L, 1000L)) {
            val gate = MainPageBackPressGate()
            assertFalse(gate.shouldBackground(1000))
            assertTrue(gate.shouldBackground(1000 + gap))
        }
    }

    @Test fun expiredPressStartsANewPair() {
        val gate = MainPageBackPressGate()
        assertFalse(gate.shouldBackground(1000))
        assertFalse(gate.shouldBackground(2001))
        assertTrue(gate.shouldBackground(2300))
    }

    @Test fun repeatedSlowPressesDoNotBackground() {
        val gate = MainPageBackPressGate()
        repeat(20) { assertFalse(gate.shouldBackground(it * 1001L)) }
    }

    @Test fun navigationOrInteractionResetsThePair() {
        val gate = MainPageBackPressGate()
        assertFalse(gate.shouldBackground(1000))
        gate.reset()
        assertFalse(gate.shouldBackground(1100))
        assertTrue(gate.shouldBackground(1200))
    }

    @Test fun backgroundingConsumesBothPresses() {
        val gate = MainPageBackPressGate()
        assertFalse(gate.shouldBackground(1000))
        assertTrue(gate.shouldBackground(1100))
        assertFalse(gate.shouldBackground(1200))
    }

    @Test fun anEarlierClockValueCannotCompleteThePair() {
        val gate = MainPageBackPressGate()
        assertFalse(gate.shouldBackground(1000))
        assertFalse(gate.shouldBackground(900))
        assertTrue(gate.shouldBackground(1100))
    }
}
