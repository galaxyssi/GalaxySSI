package com.signalasi.chat

import com.signalasi.chat.voice.modelstream.ModelStreamError
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
}
