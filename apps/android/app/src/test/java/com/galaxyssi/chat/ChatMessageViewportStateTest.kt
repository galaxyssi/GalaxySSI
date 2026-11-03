package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ChatMessageViewportStateTest {
    private val anchor = ChatMessageScrollAnchor(451, 870, -37)
    private fun state() = ChatMessageViewportState().apply { select("desktop", false) }

    @Test fun cancellingPickerAtBottomKeepsFollowingLatest() {
        val state = state()
        state.suspend(anchor)
        state.resume()
        assertTrue(state.followLatest)
        assertNull(state.pendingAnchor)
    }

    @Test fun cancellingCameraInHistoryRestoresOnlyIdentifiersAndOffset() {
        val state = state()
        state.userScroll(false, false)
        state.suspend(anchor)
        state.resume()
        assertEquals(anchor, state.pendingAnchor)
        assertFalse(state.followLatest)
    }

    @Test fun sendingDocumentBeforeResumeSupersedesSavedHistoryAnchor() {
        val state = state()
        state.userScroll(false, false)
        state.suspend(anchor)
        assertTrue(state.sent("desktop"))
        state.resume()
        assertTrue(state.followLatest)
        assertNull(state.pendingAnchor)
    }

    @Test fun sendingImageAfterResumeSupersedesInFlightRestore() {
        val state = state()
        state.userScroll(false, false)
        state.suspend(anchor)
        state.resume()
        val loading = state.generation
        state.sent("desktop")
        assertFalse(state.accepts("desktop", loading))
        assertTrue(state.accepts("desktop", state.generation))
    }

    @Test fun backgroundInvalidatesOlderAndNewerPageCallbacks() {
        val state = state()
        val loading = state.generation
        state.suspend(anchor)
        assertFalse(state.accepts("desktop", loading))
        state.resume()
        assertFalse(state.accepts("desktop", loading))
    }

    @Test fun repeatedBackgroundCallbacksDoNotLoseAnchor() {
        val state = state()
        state.userScroll(false, false)
        state.suspend(anchor)
        state.suspend(null)
        assertEquals(anchor, state.pendingAnchor)
    }

    @Test fun switchingContactsInvalidatesPendingScrollAndLoads() {
        val state = state()
        val loading = state.generation
        state.select("phone", false)
        assertFalse(state.accepts("desktop", loading))
        assertFalse(state.sent("desktop"))
        assertEquals("phone", state.contactId)
    }

    @Test fun userDraggingAfterSendStopsFollowingAndCancelsRestore() {
        val state = state()
        state.sent("desktop")
        val loading = state.generation
        state.beginUserScroll()
        state.userScroll(false, false)
        assertFalse(state.followLatest)
        assertFalse(state.accepts("desktop", loading))
    }

    @Test fun reachingLatestEnablesFollowingAgain() {
        val state = state()
        state.beginUserScroll()
        state.userScroll(true, false)
        assertTrue(state.followLatest)
    }

    @Test fun systemNotificationsRemainTopAligned() {
        val state = state()
        state.select("system", true)
        state.userScroll(true, true)
        state.suspend(anchor)
        state.resume()
        assertFalse(state.followLatest)
        assertEquals(anchor, state.pendingAnchor)
    }
}
