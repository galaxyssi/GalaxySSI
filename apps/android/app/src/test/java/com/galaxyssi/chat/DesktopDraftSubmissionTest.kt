package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class DesktopDraftSubmissionTest {
    @Test fun matchingSuccessClearsOnlyTheSubmittedRevision() {
        val state = DesktopDraftSubmission()
        state.edited()
        assertTrue(state.begin("a"))
        assertTrue(state.complete("a", true))
        assertNull(state.pendingId)
    }

    @Test fun editsWhileWaitingSurviveTheReceipt() {
        val state = DesktopDraftSubmission()
        state.begin("a")
        state.edited()
        assertFalse(state.complete("a", true))
        assertNull(state.pendingId)
    }

    @Test fun repeatedTapDoesNotEnqueueAnotherSend() {
        val state = DesktopDraftSubmission()
        assertTrue(state.begin("a"))
        assertFalse(state.begin("b"))
        assertEquals("a", state.pendingId)
    }

    @Test fun unrelatedAndDuplicateReceiptsDoNotClearDrafts() {
        val state = DesktopDraftSubmission()
        state.begin("a")
        assertFalse(state.complete("b", true))
        assertEquals("a", state.pendingId)
        assertTrue(state.complete("a", true))
        assertFalse(state.complete("a", true))
    }

    @Test fun failureKeepsDraftAndAllowsExplicitRetry() {
        val state = DesktopDraftSubmission()
        state.begin("a")
        assertFalse(state.complete("a", false))
        assertTrue(state.begin("b"))
        assertTrue(state.complete("b", true))
    }

    @Test fun timeoutOrBackgroundDoesNotAcceptLateAcknowledgments() {
        val state = DesktopDraftSubmission()
        state.begin("a")
        state.cancel()
        assertFalse(state.complete("a", true))
        assertTrue(state.begin("b"))
        assertFalse(state.complete("a", true))
        assertEquals("b", state.pendingId)
    }
}
