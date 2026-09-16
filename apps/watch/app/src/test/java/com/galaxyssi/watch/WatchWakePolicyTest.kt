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
        assertFalse(WatchWakePolicy.confidentResult(result(end = 8.0)))
        assertFalse(WatchWakePolicy.confidentResult("""{"partial":"hello hello"}"""))
        assertFalse(WatchWakePolicy.confidentResult("invalid"))
    }
}
