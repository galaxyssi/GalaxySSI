package com.galaxyssi.chat.voice.reliability

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceCircuitBreakerTest {
    private var now = 1_000L
    private val config = VoiceCircuitBreakerConfig(
        rollingWindowMs = 10_000L,
        transientFailureThreshold = 4,
        timeoutFailureThreshold = 3,
        protocolFailureThreshold = 3,
        thermalFailureThreshold = 2,
        nativeCrashThreshold = 2,
        defaultOpenMs = 1_000L,
        timeoutOpenMs = 2_000L,
        thermalOpenMs = 3_000L,
        nativeOpenMs = 4_000L,
        outOfMemoryOpenMs = 5_000L
    )
    private val breaker = VoiceCircuitBreaker({ now }, config)
    private val key = VoiceCircuitKey(VoicePipelineFeature.LOCAL_WHISPER_REALTIME, "base")

    @Test
    fun `oom opens profile circuit immediately`() {
        val record = breaker.failure(key, VoiceFailureKind.OUT_OF_MEMORY, "oom")

        assertEquals(VoiceCircuitState.OPEN, record.state)
        assertFalse(breaker.admit(key).allowed)
        assertEquals(5_000L, breaker.admit(key).retryAfterMs)
    }

    @Test
    fun `two native crashes open only the affected profile`() {
        breaker.failure(key, VoiceFailureKind.NATIVE_CRASH)
        assertTrue(breaker.admit(key).allowed)
        breaker.failure(key, VoiceFailureKind.NATIVE_CRASH)

        assertFalse(breaker.admit(key).allowed)
        assertTrue(breaker.admit(key.copy(profileId = "tiny")).allowed)
    }

    @Test
    fun `failure window expires instead of accumulating forever`() {
        repeat(2) { breaker.failure(key, VoiceFailureKind.TIMEOUT) }
        now += 10_001L
        val record = breaker.failure(key, VoiceFailureKind.TIMEOUT)

        assertEquals(VoiceCircuitState.CLOSED, record.state)
        assertEquals(1, record.consecutiveFailures)
    }

    @Test
    fun `only one half open probe is admitted`() {
        breaker.failure(key, VoiceFailureKind.OUT_OF_MEMORY)
        now += 5_001L

        assertTrue(breaker.admit(key).allowed)
        assertFalse(breaker.admit(key).allowed)
    }

    @Test
    fun `half open success closes circuit`() {
        breaker.failure(key, VoiceFailureKind.OUT_OF_MEMORY)
        now += 5_001L
        assertTrue(breaker.admit(key).allowed)

        val record = breaker.success(key)
        assertEquals(VoiceCircuitState.CLOSED, record.state)
        assertEquals(0, record.consecutiveFailures)
        assertTrue(breaker.admit(key).allowed)
    }

    @Test
    fun `half open failure reopens circuit`() {
        breaker.failure(key, VoiceFailureKind.OUT_OF_MEMORY)
        now += 5_001L
        assertTrue(breaker.admit(key).allowed)

        val record = breaker.failure(key, VoiceFailureKind.TRANSIENT_NETWORK)
        assertEquals(VoiceCircuitState.OPEN, record.state)
    }

    @Test
    fun `user cancellation never trips circuit`() {
        repeat(20) { breaker.failure(key, VoiceFailureKind.USER_ABORT) }

        assertEquals(VoiceCircuitState.CLOSED, breaker.snapshot(key).state)
        assertTrue(breaker.admit(key).allowed)
    }

    @Test
    fun `new app or profile generation clears stale circuit`() {
        breaker.failure(key, VoiceFailureKind.OUT_OF_MEMORY, generation = "v1")
        assertFalse(breaker.admit(key, "v1").allowed)

        assertTrue(breaker.admit(key, "v2").allowed)
        assertEquals(VoiceCircuitState.CLOSED, breaker.snapshot(key, "v2").state)
    }
}
