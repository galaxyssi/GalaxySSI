package com.galaxyssi.watch
import org.junit.Assert.*
import org.junit.Test
class WatchScreenAwakeTest {
    @Test fun workAndSpeechHoldUntilThirtySecondsAfterBothEnd() {
        val policy = WatchScreenAwakePolicy()
        assertEquals(0L, policy.remaining(0, true, false))
        assertEquals(Long.MAX_VALUE, policy.remaining(1, true, true))
        assertEquals(Long.MAX_VALUE, policy.remaining(90_000, true, true))
        assertEquals(30_000L, policy.remaining(100_000, true, false))
        assertEquals(1L, policy.remaining(129_999, true, false))
        assertEquals(0L, policy.remaining(130_000, true, false))
        assertEquals(0L, policy.remaining(140_000, true, false))
    }
    @Test fun newPlaybackResetsGraceAndBackgroundReleasesImmediately() {
        val policy = WatchScreenAwakePolicy()
        policy.remaining(1, true, true)
        policy.remaining(2, true, false)
        assertEquals(Long.MAX_VALUE, policy.remaining(3, true, true))
        assertEquals(30_000L, policy.remaining(4, true, false))
        assertEquals(0L, policy.remaining(5, false, true))
        assertEquals(0L, policy.remaining(6, true, false))
    }
}
