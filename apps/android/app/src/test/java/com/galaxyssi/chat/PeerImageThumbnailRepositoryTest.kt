package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

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

    @Test
    fun imagesInTheSameMonthHaveSeparatePersistentThumbnails() {
        val first = File("imported/2026/10/first.jpg")
        val second = File(first.parentFile, "second.jpg")
        val attachment = image()
        assertNotEquals(
            PeerImageThumbnailPolicy.storedFile(first, attachment),
            PeerImageThumbnailPolicy.storedFile(second, attachment)
        )
        assertEquals(first.parentFile, PeerImageThumbnailPolicy.storedFile(first, attachment).parentFile)
    }

    @Test
    fun renamedDisplayLabelsAndTransferProgressDoNotRegenerateThumbnails() {
        val original = File("imported/photo.jpg")
        val attachment = image()
        val updated = attachment.copy(name = "renamed.jpg", transferId = "completed",
            transferState = "complete", transferProgress = 100)
        assertEquals(PeerImageThumbnailPolicy.cacheIdentity(attachment), PeerImageThumbnailPolicy.cacheIdentity(updated))
        assertEquals(PeerImageThumbnailPolicy.storedFile(original, attachment),
            PeerImageThumbnailPolicy.storedFile(original, updated))
    }

    @Test
    fun changedContentInvalidatesBothCacheLayers() {
        val original = File("imported/photo.jpg")
        val attachment = image().copy(sha256 = "a".repeat(64))
        val changed = attachment.copy(sha256 = "b".repeat(64))
        assertNotEquals(PeerImageThumbnailPolicy.cacheIdentity(attachment), PeerImageThumbnailPolicy.cacheIdentity(changed))
        assertNotEquals(PeerImageThumbnailPolicy.storedFile(original, attachment),
            PeerImageThumbnailPolicy.storedFile(original, changed))
    }

    @Test
    fun legacyDirectoryWideThumbnailCannotBeSelected() {
        val original = File("imported/photo.jpg")
        val result = PeerImageThumbnailPolicy.storedFile(original, image())
        assertNotEquals(File(original.parentFile, PeerImageThumbnailPolicy.LEGACY_FILE_NAME), result)
        assertTrue(result.name.matches(Regex("\\.peer-image-thumbnail-v2-[a-f0-9]{64}\\.sasie")))
    }

    @Test
    fun incomingTransfersWithTheSameFileNameRemainIsolated() {
        assertNotEquals(
            PeerImageThumbnailPolicy.storedFile(File("incoming/first/data.sasie"), image()),
            PeerImageThumbnailPolicy.storedFile(File("incoming/second/data.sasie"), image())
        )
    }

    @Test
    fun similarNamesAndExtensionsDoNotCollide() {
        val files = listOf("photo.jpg", "photo.png", "PHOTO.jpg", "photo-1.jpg", "photo_1.jpg")
        val names = files.map { PeerImageThumbnailPolicy.storedFile(File("imported", it), image()).name }
        assertEquals(files.size, names.toSet().size)
    }

    private fun image() = PeerChatAttachment("photo.jpg", "image/jpeg", 2_000_000,
        uri = "content://galaxyssi/photo/1")
}
