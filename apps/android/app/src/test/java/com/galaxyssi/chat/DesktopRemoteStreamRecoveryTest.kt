package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class DesktopRemoteStreamRecoveryTest {
    private val recovery = DesktopRemoteStreamRecovery()
    private fun next(now: Long = 1000, session: String = "a", active: Boolean = false,
                     error: String = "", failureSession: String = session, failureAt: Long = 0,
                     connected: Boolean = true, authorized: Boolean = true, expires: Long = 100000) =
        recovery.next(now, connected, authorized, session, expires, active, error, failureSession, failureAt)

    @Test fun startsAgainWhenStreamStoppedWithoutDisconnectingBroker() {
        assertEquals(DesktopRemoteStreamRecovery.Action.START, next())
        assertEquals(DesktopRemoteStreamRecovery.Action.NONE, next(now = 2000, active = true))
        assertEquals(DesktopRemoteStreamRecovery.Action.START, next(now = 6000))
    }

    @Test fun backendRestartRenewsMissingHandleAndStartsNewSession() {
        next()
        assertEquals(DesktopRemoteStreamRecovery.Action.RENEW,
            next(now = 2000, error = "tool_handle_not_found", failureAt = 2000))
        assertEquals(DesktopRemoteStreamRecovery.Action.NONE,
            next(now = 3000, error = "tool_handle_not_found", failureAt = 2000))
        assertEquals(DesktopRemoteStreamRecovery.Action.START,
            next(now = 4000, session = "b", error = "tool_handle_not_found", failureSession = "a", failureAt = 2000))
        assertEquals(DesktopRemoteStreamRecovery.Action.NONE,
            next(now = 5000, session = "b", active = true, error = "tool_handle_not_found", failureSession = "a", failureAt = 4500))
    }

    @Test fun expiredSessionRenewsWithoutReplayingInput() {
        assertEquals(DesktopRemoteStreamRecovery.Action.RENEW, next(expires = 900))
        assertEquals(DesktopRemoteStreamRecovery.Action.NONE, next(now = 1500, expires = 900))
        assertEquals(DesktopRemoteStreamRecovery.Action.RENEW, next(now = 6000, expires = 900))
    }

    @Test fun temporaryFailureRetriesSameSessionAfterBackoff() {
        next()
        assertEquals(DesktopRemoteStreamRecovery.Action.NONE,
            next(now = 2000, error = "message_expired", failureAt = 2000))
        assertEquals(DesktopRemoteStreamRecovery.Action.START,
            next(now = 7000, error = "message_expired", failureAt = 2000))
    }

    @Test fun unverifiedOrOversizedFrameDoesNotCauseAutomaticRetryLoop() {
        for (code in listOf("desktop_action_receipt_unverified", "screenshot_too_large", "authorization_required")) {
            recovery.reset()
            assertEquals(DesktopRemoteStreamRecovery.Action.NONE, next(error = code, failureAt = 1000))
            assertEquals(DesktopRemoteStreamRecovery.Action.NONE, next(now = 20000, error = code, failureAt = 1000))
            assertEquals(DesktopRemoteStreamRecovery.Action.START, next(now = 21000))
        }
    }

    @Test fun disconnectedOrUnauthorizedNeverStarts() {
        assertEquals(DesktopRemoteStreamRecovery.Action.NONE, next(connected = false))
        assertEquals(DesktopRemoteStreamRecovery.Action.NONE, next(authorized = false))
    }
}
