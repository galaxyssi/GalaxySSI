package com.galaxyssi.watch
import org.junit.Assert.*
import org.junit.Test
class WatchBackgroundWakePolicyTest {
    @Test fun backgroundDoesNotRequireHome() {
        assertTrue(WatchBackgroundWakePolicy.allowed(false, false, false, false))
    }
    @Test fun visibleOtherPagesAndTypingDoNotListen() {
        assertFalse(WatchBackgroundWakePolicy.allowed(true, false, false, false))
        assertTrue(WatchBackgroundWakePolicy.allowed(true, true, false, false))
    }
    @Test fun microphoneHandoffAndPlaybackBlockBothModes() {
        for (visible in listOf(false, true)) {
            assertFalse(WatchBackgroundWakePolicy.allowed(visible, true, true, false))
            assertFalse(WatchBackgroundWakePolicy.allowed(visible, true, false, true))
        }
    }
}
