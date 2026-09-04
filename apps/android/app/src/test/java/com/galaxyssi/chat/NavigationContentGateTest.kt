package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NavigationContentGateTest {
    @Test
    fun newerNavigationInvalidatesOlderContent() {
        val gate = NavigationContentGate()
        val first = gate.begin()
        val second = gate.begin()

        assertFalse(gate.isCurrent(first))
        assertTrue(gate.isCurrent(second))
    }

    @Test
    fun staleDismissDoesNotInvalidateCurrentNavigation() {
        val gate = NavigationContentGate()
        val first = gate.begin()
        val second = gate.begin()

        gate.invalidateIfCurrent(first)

        assertTrue(gate.isCurrent(second))
    }
}
