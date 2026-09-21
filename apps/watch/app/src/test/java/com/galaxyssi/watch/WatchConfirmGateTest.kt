package com.galaxyssi.watch

import org.junit.Assert.*
import org.junit.Test

class WatchConfirmGateTest {
    @Test fun requiresArmedSessionAndOnePointFiveStableSeconds() {
        val gate = WatchConfirmGate()
        assertFalse(gate.ready("result", 0))
        gate.arm(10)
        assertFalse(gate.ready("result", 100))
        assertFalse(gate.ready("result", 1599))
        assertTrue(gate.ready("result", 1600))
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
    @Test fun touchBeforeFirstRecognitionResultCancelsTheWholeSession() {
        val gate = WatchConfirmGate()
        gate.arm(0)
        assertFalse(gate.hasCandidate)
        gate.cancel()
        assertFalse(gate.ready("later recognition", 1000))
        assertFalse(gate.ready("later recognition", 2500))
        assertFalse(gate.active(2500))
    }
    @Test fun touchJustBeforeCountdownEndsCannotBeUndoneByTextUpdates() {
        val gate = WatchConfirmGate()
        gate.arm(0)
        gate.ready("result", 100)
        assertFalse(gate.ready("result", 1599))
        gate.cancel()
        assertFalse(gate.ready("result", 1600))
        gate.reset()
        assertFalse(gate.ready("updated result", 4000))
        gate.arm(5000)
        assertFalse(gate.ready("new session", 5000))
        assertTrue(gate.ready("new session", 6500))
    }
}
