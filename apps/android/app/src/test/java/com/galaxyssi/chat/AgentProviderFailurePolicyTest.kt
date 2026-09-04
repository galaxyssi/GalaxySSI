package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.ModelStreamError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentProviderFailurePolicyTest {
    @Test
    fun insufficientBalanceIsPermanentAndNotRetryable() {
        val failure = AgentProviderFailurePolicy.classify(
            ModelStreamError("invalid_request_error", "Insufficient Balance", httpStatus = 402)
        )

        assertEquals(AgentProviderFailureClass.PERMANENT_BILLING, failure.failureClass)
        assertTrue(failure.permanent)
        assertFalse(failure.retryable)
    }

    @Test
    fun serverFailureRemainsRetryable() {
        val failure = AgentProviderFailurePolicy.classify(
            ModelStreamError("upstream_error", "Provider unavailable", httpStatus = 503, retryable = true)
        )

        assertEquals(AgentProviderFailureClass.TRANSIENT, failure.failureClass)
        assertFalse(failure.permanent)
        assertTrue(failure.retryable)
    }

    @Test
    fun invalidKeyIsPermanentEvenWithoutHttpStatus() {
        val failure = AgentProviderFailurePolicy.classify("Cloud request failed: invalid API key")

        assertEquals(AgentProviderFailureClass.PERMANENT_CREDENTIAL, failure.failureClass)
        assertTrue(failure.permanent)
    }

    @Test
    fun transientFailureRetriesFiveTimesBeforeFailover() {
        val failure = AgentProviderFailurePolicy.classify(
            ModelStreamError("upstream_error", "Temporary outage", httpStatus = 503, retryable = true)
        )

        assertTrue(AgentProviderFailurePolicy.shouldRetrySameResource(failure, 1))
        assertTrue(AgentProviderFailurePolicy.shouldRetrySameResource(failure, 4))
        assertFalse(AgentProviderFailurePolicy.shouldRetrySameResource(failure, 5))
    }

    @Test
    fun permanentFailureSwitchesWithoutRetry() {
        val failure = AgentProviderFailurePolicy.classify("Insufficient Balance")

        assertFalse(AgentProviderFailurePolicy.shouldRetrySameResource(failure, 1))
    }

    @Test
    fun automaticInteractiveRoutingFailsOverQuicklyWhenAnAlternativeExists() {
        val profile = AgentProviderFailurePolicy.attemptProfile(
            manuallyLocked = false,
            hasAlternativeResource = true,
            supervisedProject = false
        )

        assertEquals(2, profile.maxAttempts)
        assertEquals(10_000L, profile.connectTimeoutMillis)
        assertEquals(15_000L, profile.readTimeoutMillis)
    }

    @Test
    fun supervisedProjectAllowsLongerObservationBeforeFailover() {
        val profile = AgentProviderFailurePolicy.attemptProfile(
            manuallyLocked = false,
            hasAlternativeResource = true,
            supervisedProject = true
        )

        assertEquals(2, profile.maxAttempts)
        assertEquals(15_000L, profile.connectTimeoutMillis)
        assertEquals(60_000L, profile.readTimeoutMillis)
    }

    @Test
    fun manualOrUniqueResourceKeepsPatientTimeouts() {
        val locked = AgentProviderFailurePolicy.attemptProfile(
            manuallyLocked = true,
            hasAlternativeResource = true,
            supervisedProject = false
        )
        val unique = AgentProviderFailurePolicy.attemptProfile(
            manuallyLocked = false,
            hasAlternativeResource = false,
            supervisedProject = false
        )

        assertEquals(locked, unique)
        assertEquals(5, locked.maxAttempts)
        assertEquals(20_000L, locked.connectTimeoutMillis)
        assertEquals(300_000L, locked.readTimeoutMillis)
    }

    @Test
    fun automaticInteractiveRoutingStopsRetryingAfterSecondFailure() {
        val failure = AgentProviderFailurePolicy.classify(
            ModelStreamError("upstream_error", "Temporary outage", httpStatus = 503, retryable = true)
        )
        val profile = AgentProviderFailurePolicy.attemptProfile(
            manuallyLocked = false,
            hasAlternativeResource = true,
            supervisedProject = false
        )

        assertTrue(AgentProviderFailurePolicy.shouldRetrySameResource(failure, 1, profile))
        assertFalse(AgentProviderFailurePolicy.shouldRetrySameResource(failure, 2, profile))
    }
}
