package com.galaxyssi.chat

/** Recover observation sessions only; uncertain input actions are never replayed. */
internal class DesktopRemoteStreamRecovery {
    enum class Action { NONE, RENEW, START }
    private var startedSession = ""
    private var rejectedSession = ""
    private var rejectedCode = ""
    private var observedFailureAt = 0L
    private var lastRenewAt: Long? = null
    private var lastStartAt: Long? = null
    private var retryAfter = 0L

    fun reset() {
        startedSession = ""
        rejectedSession = ""
        rejectedCode = ""
        observedFailureAt = 0L
        lastRenewAt = null
        lastStartAt = null
        retryAfter = 0L
    }

    fun next(now: Long, connected: Boolean, authorized: Boolean, session: String,
             expiresAt: Long, streamActive: Boolean, errorCode: String,
             failureSession: String, failureAt: Long): Action {
        if (!connected || !authorized) return Action.NONE
        if (errorCode.isBlank()) { rejectedSession = ""; rejectedCode = "" }
        if (errorCode.isNotBlank() && failureAt > observedFailureAt) {
            observedFailureAt = failureAt
            if (failureSession == session) {
                rejectedSession = session
                rejectedCode = errorCode
                retryAfter = now + 5_000
            }
        }
        var rejected = session.isNotBlank() && session == rejectedSession
        if (rejected && rejectedCode in retryableErrors) {
            if (now < retryAfter) return Action.NONE
            rejectedSession = ""; rejectedCode = ""; rejected = false
        }
        if (rejected && rejectedCode !in renewableErrors) return Action.NONE
        if (session.isBlank() || expiresAt <= now || rejected) {
            if (lastRenewAt?.let { now - it < 5_000 } == true) return Action.NONE
            lastRenewAt = now
            return Action.RENEW
        }
        if (streamActive && startedSession == session) return Action.NONE
        if (startedSession == session && lastStartAt?.let { now - it < 1_000 } == true) return Action.NONE
        startedSession = session
        lastStartAt = now
        return Action.START
    }

    companion object {
        private val renewableErrors = setOf("tool_handle_not_found", "tool_handle_expired", "desktop_session_required")
        private val retryableErrors = setOf("message_expired", "desktop_control_busy")
    }
}
