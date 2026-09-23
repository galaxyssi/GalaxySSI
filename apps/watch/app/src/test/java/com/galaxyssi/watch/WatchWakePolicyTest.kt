package com.galaxyssi.watch

import org.junit.Assert.*
import org.junit.Test

class WatchWakePolicyTest {
    @Test fun requiresTwoCompleteWords() {
        assertTrue(WatchWakePolicy.matches("Hello, HELLO!"))
        assertFalse(WatchWakePolicy.matches("hello"))
        assertFalse(WatchWakePolicy.matches("hello world"))
        assertFalse(WatchWakePolicy.matches("they said hello hello"))
        assertFalse(WatchWakePolicy.matches("hellohello"))
        assertFalse(WatchWakePolicy.matches("hello hello hello"))
    }
    @Test fun rejectsUncertainIncompleteOrWidelySeparatedDetections() {
        fun result(confidence: Double = 0.95, end: Double = 1.5) =
            """{"text":"hello hello","result":[{"word":"hello","conf":$confidence,"start":0.1,"end":0.6},{"word":"hello","conf":$confidence,"start":0.8,"end":$end}]}"""
        assertTrue(WatchWakePolicy.confidentResult(result()))
        assertFalse(WatchWakePolicy.confidentResult(result(0.5)))
        assertTrue(WatchWakePolicy.confidentResult(result(0.72)))
        assertFalse(WatchWakePolicy.confidentResult(result(end = 8.0)))
        assertFalse(WatchWakePolicy.confidentResult("""{"partial":"hello hello"}"""))
        assertFalse(WatchWakePolicy.confidentResult("invalid"))
    }
    @Test fun stablePartialNeedsExactTwoWordsForAtLeast650ms() {
        val c = WatchWakeCandidate()
        assertFalse(c.observe("""{"partial":"hello hello"}""", 1000))
        assertFalse(c.observe("""{"partial":"hello hello"}""", 1600))
        assertTrue(c.observe("""{"partial":"hello hello"}""", 1650))
        assertFalse(c.observe("""{"partial":"hello world"}""", 1700))
        assertFalse(c.observe("""{"partial":"hello hello"}""", 1800))
        assertFalse(c.observe("""{"partial":"hello hello"}""", 5400))
    }
}
