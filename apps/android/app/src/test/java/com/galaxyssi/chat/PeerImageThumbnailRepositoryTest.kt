package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class PeerImageThumbnailRepositoryTest {
    @Test
    fun stableSourceUriKeepsThumbnailIdentityAcrossProgressUpdates() {
        val original = PeerChatAttachment(
            name = "photo.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 2_000_000,
            uri = "content://galaxyssi/photo/1",
            transferId = "a".repeat(64),
            transferProgress = 10,
            transferState = "downloading"
        )
        assertEquals(
            PeerImageThumbnailPolicy.cacheIdentity(original),
            PeerImageThumbnailPolicy.cacheIdentity(
                original.copy(transferProgress = 100, transferState = "complete")
            )
        )
        assertNotEquals(
            PeerImageThumbnailPolicy.cacheIdentity(original),
            PeerImageThumbnailPolicy.cacheIdentity(original.copy(uri = "content://galaxyssi/photo/2"))
        )
    }
}
