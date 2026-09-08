package com.galaxyssi.chat.voice.tts

import org.junit.Assert.*
import org.junit.Test

class ProgressiveTtsTimeoutPolicyTest {
    @Test fun shortUtterancesKeepABoundedStartupAllowance() {
        assertEquals(20_000L, ProgressiveTtsTimeoutPolicy.forText("hello"))
    }

    @Test fun longChineseUtterancesAreNotTruncatedAtTwentySeconds() {
        assertEquals(63_000L, ProgressiveTtsTimeoutPolicy.forText("语".repeat(96)))
        assertEquals(600_000L, ProgressiveTtsTimeoutPolicy.forText("语".repeat(1_200)))
    }

    @Test fun invalidlyLargeInputStillHasABoundedWatchdog() {
        assertEquals(600_000L, ProgressiveTtsTimeoutPolicy.forText("x".repeat(100_000)))
    }
}
