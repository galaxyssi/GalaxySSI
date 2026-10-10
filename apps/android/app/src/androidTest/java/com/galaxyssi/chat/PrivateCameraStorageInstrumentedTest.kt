package com.galaxyssi.chat

import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class PrivateCameraStorageInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun cameraCanWriteAndCompletedPhotoSurvivesCacheCleanup() {
        val output = PrivateCameraStorage.createOutput(context)
        assertEquals("${context.packageName}.files", output.authority)
        assertEquals("composer_camera", output.pathSegments.first())
        val bytes = byteArrayOf(0xff.toByte(), 0xd8.toByte(), 1, 2, 0xff.toByte(), 0xd9.toByte())
        val cacheFixture = File.createTempFile("camera-test-", ".tmp", context.cacheDir)
        var stored: File? = null
        try {
            context.contentResolver.openOutputStream(output, "w")!!.use { it.write(bytes) }
            val attachment = PrivateCameraStorage.finish(context, output, accepted = true)!!
            assertEquals("image/jpeg", context.contentResolver.getType(attachment))
            stored = LocalAttachmentUris.resolve(context, attachment)!!
            assertTrue(stored.canonicalPath.startsWith(context.filesDir.canonicalPath + "/"))
            assertTrue(cacheFixture.delete())
            assertArrayEquals(bytes, context.contentResolver.openInputStream(attachment)!!.use { it.readBytes() })
        } finally {
            stored?.delete()
            cacheFixture.delete()
            PrivateCameraStorage.finish(context, output, accepted = false)
        }
    }

    @Test fun cancellingDeletesOnlyThePendingCapture() {
        val first = PrivateCameraStorage.createOutput(context)
        val second = PrivateCameraStorage.createOutput(context)
        try {
            context.contentResolver.openOutputStream(first, "w")!!.use { it.write(1) }
            context.contentResolver.openOutputStream(second, "w")!!.use { it.write(2) }
            assertNull(PrivateCameraStorage.finish(context, first, accepted = false))
            assertTrue(runCatching { context.contentResolver.openInputStream(first)!!.close() }.isFailure)
            assertEquals(2, context.contentResolver.openInputStream(second)!!.use { it.read() })
        } finally {
            PrivateCameraStorage.finish(context, second, accepted = false)
        }
    }

    @Test fun emptyCaptureIsRejectedAndRemoved() {
        val output = PrivateCameraStorage.createOutput(context)
        assertNull(PrivateCameraStorage.finish(context, output, accepted = true))
        assertTrue(runCatching { context.contentResolver.openInputStream(output)!!.close() }.isFailure)
    }

    @Test fun unrelatedProviderUriIsNotAccepted() {
        val uri = Uri.parse("content://${context.packageName}.files/composer_crops/not-a-photo.jpg")
        assertNull(PrivateCameraStorage.finish(context, uri, accepted = true))
    }
}
