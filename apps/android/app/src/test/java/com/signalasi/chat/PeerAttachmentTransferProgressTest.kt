package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class PeerAttachmentTransferProgressTest {
    @Test
    fun progressUsesVerifiedBytesAndNeverCompletesEarly() {
        assertEquals(0, PeerAttachmentTransferProgress.percent(0, 100))
        assertEquals(49, PeerAttachmentTransferProgress.percent(49, 100))
        assertEquals(99, PeerAttachmentTransferProgress.percent(99, 100))
        assertEquals(100, PeerAttachmentTransferProgress.percent(100, 100))
    }

    @Test
    fun transferRequestsAStableBoundedWindow() {
        val missing = (0 until 100).toList()

        assertEquals(
            (0 until PeerAttachmentTransferProgress.REQUEST_WINDOW_CHUNKS).toList(),
            PeerAttachmentTransferProgress.requestWindow(missing)
        )
    }
}
