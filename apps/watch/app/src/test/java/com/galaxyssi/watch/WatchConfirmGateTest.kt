package com.galaxyssi.watch

import org.junit.Assert.*
import org.junit.Test

class WatchConfirmGateTest {
    @Test fun requiresArmedSessionAndThreeStableSeconds() {
        val gate = WatchConfirmGate()
        assertFalse(gate.ready("result", 0))
        gate.arm(10)
        assertFalse(gate.ready("result", 100))
        assertFalse(gate.ready("result", 3099))
        assertTrue(gate.ready("result", 3100))
        gate.cancel()
        assertFalse(gate.ready("result", 10000))
    }
    @Test fun textOrWindowChangesRestartCountdownAndMissingControlsResetIt() {
        val gate = WatchConfirmGate()
        gate.arm(0)
        assertFalse(gate.ready("window1:hello", 0))
        assertFalse(gate.ready("window1:hello world", 2000))
        assertFalse(gate.ready("window1:hello world", 3000))
        assertFalse(gate.ready(null, 4000))
        assertFalse(gate.ready("window1:hello world", 5000))
        assertFalse(gate.ready("window2:hello world", 7000))
        assertTrue(gate.ready("window2:hello world", 10000))
    }
    @Test fun cancellationAndExpirationPreventLateClicks() {
        val gate = WatchConfirmGate()
        gate.arm(0); gate.ready("result", 0); gate.cancel()
        assertFalse(gate.ready("result", 3000))
        gate.arm(5000)
        assertFalse(gate.ready("result", 124000))
        assertFalse(gate.ready("result", 127000))
        assertFalse(gate.active(127000))
    }
}
