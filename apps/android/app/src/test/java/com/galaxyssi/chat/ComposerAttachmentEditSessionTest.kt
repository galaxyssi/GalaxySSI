package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ComposerAttachmentEditSessionTest {
    private val photo = ComposerAttachmentItem("photo-1", "content://camera/one", "one.jpg", "image/jpeg", 1200)

    @Test fun cropPreservesIdentityAndOriginal() {
        val edited = photo.cropped("content://local/cropped", "one-cropped.jpg", 600, "image/jpeg")
        assertEquals(photo.id, edited.id)
        assertEquals(photo.uri, edited.source)
        assertEquals(photo.uri, edited.originalUri)
        assertTrue(edited.isCropped)
        assertEquals("content://camera/one", photo.uri)
    }

    @Test fun repeatedCropAlwaysReferencesOriginalNotPreviousDerivative() {
        val first = photo.cropped("content://local/first", "one-cropped.jpg", 600, "image/jpeg")
        val second = first.cropped("content://local/second", "one-cropped.jpg", 700, "image/jpeg")
        assertEquals(photo.uri, second.source)
        assertEquals(photo.id, second.id)
        assertEquals("content://local/second", second.uri)
    }

    @Test fun mixedImagesAndDocumentsRoundTripWithoutChangingOrderOrMetadata() {
        val files = listOf(photo, ComposerAttachmentItem("pdf", "content://docs/pdf", "资料.pdf", "application/pdf", 20_000),
            ComposerAttachmentItem("png", "content://docs/png", "透明.png", "image/png", 0))
        assertEquals(files, ComposerAttachmentItem.decode(ComposerAttachmentItem.encode(files)))
        assertFalse(files[1].isImage)
        assertTrue(files[2].isImage)
    }

    @Test fun cropStateSurvivesRestoration() {
        val edited = photo.cropped("content://local/crop", "one-cropped.jpg", 600, "image/jpeg")
        val restored = ComposerAttachmentItem.decode(ComposerAttachmentItem.encode(listOf(edited))).single()
        assertEquals(edited, restored)
        assertTrue(restored.isCropped)
        assertEquals(photo.uri, restored.source)
    }

    @Test fun legacyDescriptorsUseCurrentImageAsOriginal() {
        val descriptor = photo.descriptor().apply { remove("original_uri") }
        val restored = ComposerAttachmentItem.from(descriptor)
        assertEquals(photo.uri, restored.source)
        assertFalse(restored.isCropped)
    }

    @Test(expected = IllegalArgumentException::class) fun documentCannotBeCropped() {
        photo.copy(mime = "application/pdf").cropped("content://new", "new.jpg", 100, "image/jpeg")
    }

    @Test(expected = IllegalArgumentException::class) fun emptyCropCannotReplaceOriginal() {
        photo.cropped("content://new", "new.jpg", 0, "image/jpeg")
    }

    @Test(expected = IllegalArgumentException::class) fun missingCropUriCannotReplaceOriginal() {
        photo.cropped("", "new.jpg", 10, "image/jpeg")
    }

    @Test fun imageMimeIsCaseInsensitive() { assertTrue(photo.copy(mime = "IMAGE/HEIF").isImage) }
    @Test fun emptyDraftRestoresAsEmptyList() { assertTrue(ComposerAttachmentItem.decode("[]").isEmpty()) }
    @Test fun unknownSizeRemainsUnknownWithoutTruncatingFile() {
        val file = photo.copy(size = -1)
        assertEquals(-1L, ComposerAttachmentItem.from(file.descriptor()).size)
    }
}
