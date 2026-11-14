package com.galaxyssi.chat

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class HealthReportDeliveryTest {
    @Test fun lostPublishIsRetriedOnceWithoutProbing() = runBlocking {
        val reply = CompletableDeferred<String>()
        var attempts = 0
        val result = HealthReportDelivery.receive(reply, {
            if (++attempts == 2) { reply.complete("result"); true } else false
        }, { error("No probe needed") }, retryDelay = 0)
        assertEquals("result", result)
        assertEquals(2, attempts)
    }

    @Test fun retryRequiresAuthenticatedAbsenceNotAnUnansweredProbe() = runBlocking {
        for (admission in HealthReportAdmission.entries) {
            val reply = CompletableDeferred<String>()
            var attempts = 0
            val result = runCatching {
                HealthReportDelivery.receive(reply, {
                    if (++attempts == 2) reply.complete("recovered")
                    true
                }, { admission }, earlyWait = 1, responseWait = 1, retryDelay = 0)
            }
            if (admission == HealthReportAdmission.MISSING) {
                assertEquals("recovered", result.getOrThrow())
                assertEquals(2, attempts)
            } else {
                assertEquals(1, attempts)
                val expected = if (admission == HealthReportAdmission.TERMINAL_FAILURE)
                    HealthReportDeliveryProblem.REMOTE_FAILURE else HealthReportDeliveryProblem.REPLY_TIMEOUT
                assertEquals(expected, (result.exceptionOrNull() as HealthReportCodexUnavailable).problem)
            }
        }
    }

    @Test fun lateResultWinsWhileCheckingAdmission() = runBlocking {
        val reply = CompletableDeferred<String>()
        var attempts = 0
        assertEquals("late result", HealthReportDelivery.receive(reply, { attempts++; true }, {
            reply.complete("late result")
            HealthReportAdmission.MISSING
        }, earlyWait = 1))
        assertEquals(1, attempts)
    }
}
