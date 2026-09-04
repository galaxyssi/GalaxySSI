package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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
    fun smallTransferRequestsAStableBoundedWindow() {
        val missing = (0 until 100).toList()

        assertEquals(
            (0 until PeerAttachmentTransferProgress.DEFAULT_REQUEST_WINDOW_CHUNKS).toList(),
            PeerAttachmentTransferProgress.requestWindow(
                missing,
                PeerAttachmentTransferProgress.LARGE_ATTACHMENT_THRESHOLD_BYTES,
                AgentOutboundAttachmentTransferStore.CHUNK_BYTES
            )
        )
    }

    @Test
    fun largeTransferRequestsOneMegabyteWindow() {
        val missing = (0 until 100).toList()

        assertEquals(
            (0 until 4).toList(),
            PeerAttachmentTransferProgress.requestWindow(
                missing,
                PeerAttachmentTransferProgress.LARGE_ATTACHMENT_THRESHOLD_BYTES + 1,
                AgentOutboundAttachmentTransferStore.CHUNK_BYTES
            )
        )
    }

    @Test
    fun imagesAndVoiceAutoReceiveButOrdinaryFilesWaitForUser() {
        assertTrue(PeerAttachmentTransferProgress.shouldAutoReceive("image/jpeg"))
        assertTrue(PeerAttachmentTransferProgress.shouldAutoReceive("audio/ogg"))
        assertFalse(PeerAttachmentTransferProgress.shouldAutoReceive("application/zip"))
        assertFalse(PeerAttachmentTransferProgress.shouldAutoReceive("video/mp4"))
    }

    @Test
    fun progressOverlayOnlyAppearsWhileTransferIsActive() {
        assertTrue(PeerAttachmentTransferProgress.isActive(0, "downloading"))
        assertTrue(PeerAttachmentTransferProgress.isActive(63, "uploading"))
        assertFalse(PeerAttachmentTransferProgress.isActive(100, "complete"))
        assertFalse(PeerAttachmentTransferProgress.isActive(42, "failed"))
        assertFalse(PeerAttachmentTransferProgress.isActive(-1, "downloading"))
    }
}
