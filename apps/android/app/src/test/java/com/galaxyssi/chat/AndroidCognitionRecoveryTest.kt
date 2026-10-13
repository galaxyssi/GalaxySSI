package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.withLock

class AndroidCognitionRecoveryTest {
    private val rows = mutableMapOf<String, String>()
    private var now = 1_000L
    private fun policy() = AndroidCognitionRecovery(rows::get, { key, value -> rows[key] = value }, { now })
    private val scheduled = AndroidCognitionWorkMode.SCHEDULED

    @Test fun tenthConsecutiveFailureRemainsStoppedAfterReconstructionAndClockAdvance() {
        repeat(10) { attempt ->
            val recovery = policy()
            assertTrue(recovery.mayAttempt(scheduled))
            val failure = recovery.failed(scheduled, IllegalStateException("private input"))
            assertEquals(attempt + 1, failure.failures)
            assertFalse(policy().mayAttempt(scheduled))
            now = failure.retryAtMillis
        }
        now += 365L * 24 * 60 * 60 * 1_000
        assertTrue(policy().state(scheduled).stopped)
        assertFalse(policy().mayAttempt(scheduled))
        assertEquals(10, policy().failed(scheduled, Exception()).failures)
        assertFalse(rows.values.any { "private input" in it })
    }

    @Test fun successfulAttemptsHaveNoLifetimeBudgetAndResetOnlyTheirMode() {
        val recovery = policy()
        recovery.failed(scheduled, Exception())
        repeat(1_000) {
            assertTrue(recovery.mayAttempt(AndroidCognitionWorkMode.EVENT))
            recovery.succeeded(AndroidCognitionWorkMode.EVENT)
        }
        assertEquals(1, recovery.state(scheduled).failures)
        recovery.succeeded(scheduled)
        assertEquals(0, policy().state(scheduled).failures)
        assertTrue(policy().mayAttempt(scheduled))
    }

    @Test fun explicitResumeTokenResetsOnceButCannotResetItsOwnRetries() {
        repeat(10) { policy().failed(scheduled, Exception()) }
        policy().resumeOnce("manual-1")
        assertTrue(policy().mayAttempt(scheduled))
        repeat(10) {
            policy().resumeOnce("manual-1")
            policy().failed(AndroidCognitionWorkMode.EXPLICIT, Exception())
        }
        assertTrue(policy().state(AndroidCognitionWorkMode.EXPLICIT).stopped)
        policy().resumeOnce("manual-2")
        AndroidCognitionWorkMode.entries.forEach { assertTrue(policy().mayAttempt(it)) }
    }

    @Test fun backoffIsDurableAndCappedWithoutTreatingClockTicksAsProgress() {
        val expected = listOf(30_000L, 60_000L, 120_000L, 240_000L, 480_000L, 960_000L, 1_800_000L)
        expected.forEach { delay ->
            val failed = policy().failed(scheduled, Exception())
            assertEquals(delay, failed.retryAtMillis - now)
            now = failed.retryAtMillis - 1
            assertFalse(policy().mayAttempt(scheduled))
            now++
            assertTrue(policy().mayAttempt(scheduled))
        }
    }

    @Test fun memoryIntegrityCauseIsStoredWithoutMemoryContentsOrIdentifiers() {
        val failure = policy().failed(scheduled, GlobalMemorySupersessionException(listOf("missing_forward:private-id")))
        assertEquals("memory_integrity", failure.reason)
        assertFalse(rows.values.any { "private-id" in it })
    }

    @Test fun cancellationDoesNotConsumeBudgetOrScheduleRecovery() {
        assertThrows(kotlinx.coroutines.CancellationException::class.java) {
            policy().failed(scheduled, kotlinx.coroutines.CancellationException("replaced"))
        }
        assertTrue(rows.isEmpty())
        assertTrue(policy().mayAttempt(scheduled))
    }

    @Test fun sharedExecutionLeaseSerializesModesAndReleasesAfterFailure() = runBlocking {
        var active = 0
        var peak = 0
        (1..8).map {
            async {
                runCatching {
                    AndroidCognitionRecovery.execution.withLock {
                        active++
                        peak = maxOf(peak, active)
                        try { delay(2); if (it == 3) error("test") } finally { active-- }
                    }
                }
            }
        }.awaitAll()
        assertEquals(1, peak)
        assertEquals(0, active)
        assertFalse(AndroidCognitionRecovery.execution.isLocked)
    }
}
