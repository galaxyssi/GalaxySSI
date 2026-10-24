package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ChatImageSaveStateTest {
    @Test fun saveStartsReady() = assertEquals(ChatImageSaveState.Status.READY, ChatImageSaveState().status)
    @Test fun saveIsNotCompletedBeforeIoFinishes() {
        val state = ChatImageSaveState()
        assertTrue(state.begin())
        assertEquals(ChatImageSaveState.Status.SAVING, state.status)
    }
    @Test fun repeatedTapsDoNotStartAnotherCopy() {
        val state = ChatImageSaveState()
        state.begin()
        repeat(10) { assertFalse(state.begin()) }
    }
    @Test fun successfulSaveCannotBeRepeatedInTheSamePreview() {
        val state = ChatImageSaveState()
        state.begin(); state.finish(true)
        assertEquals(ChatImageSaveState.Status.SAVED, state.status)
        assertFalse(state.begin())
    }
    @Test fun failedSaveCanBeRetried() {
        val state = ChatImageSaveState()
        state.begin(); state.finish(false)
        assertEquals(ChatImageSaveState.Status.READY, state.status)
        assertTrue(state.begin())
        state.finish(true)
        assertEquals(ChatImageSaveState.Status.SAVED, state.status)
    }
    @Test fun completionWithoutRequestDoesNotChangeState() {
        val state = ChatImageSaveState()
        state.finish(true)
        assertEquals(ChatImageSaveState.Status.READY, state.status)
    }
    @Test fun duplicateCompletionDoesNotUndoSuccess() {
        val state = ChatImageSaveState()
        state.begin(); state.finish(true); state.finish(false)
        assertEquals(ChatImageSaveState.Status.SAVED, state.status)
    }
    @Test fun formatLabelsPreserveActualFormat() {
        assertEquals("JPEG", ChatImagePreviewSource.formatLabel("image/jpeg"))
        assertEquals("HEIC", ChatImagePreviewSource.formatLabel("image/heic"))
        assertEquals("PNG", ChatImagePreviewSource.formatLabel("image/png"))
        assertEquals("SVG", ChatImagePreviewSource.formatLabel("image/svg+xml"))
        assertEquals("", ChatImagePreviewSource.formatLabel(""))
        assertEquals("", ChatImagePreviewSource.formatLabel("image/*"))
    }
}
