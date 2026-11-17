package com.galaxyssi.chat

import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class PeerAttachmentOpenDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun grantsOnlyReadAccessAndLeavesTheChoiceOfViewerToAndroid() = withAttachment { _, uri ->
        val result = PeerAttachmentOpen.open(context, uri, "report.pdf", PeerAttachmentOpen.PDF_MIME) { intent ->
            assertEquals(Intent.ACTION_VIEW, intent.action)
            assertEquals("application/pdf", intent.type)
            assertEquals(uri, intent.data)
            assertEquals(uri, intent.clipData?.getItemAt(0)?.uri)
            assertEquals(Intent.FLAG_GRANT_READ_URI_PERMISSION, intent.flags)
            assertNull(intent.component)
            assertNull(intent.`package`)
        }
        assertEquals(PeerAttachmentOpenResult.OPENED, result)
    }

    @Test fun distinguishesMissingViewerFromUnreadableSource() = withAttachment { _, uri ->
        val missing = PeerAttachmentOpen.open(context, uri, "report.pdf", PeerAttachmentOpen.PDF_MIME) {
            throw ActivityNotFoundException()
        }
        val denied = PeerAttachmentOpen.open(context, uri, "report.pdf", PeerAttachmentOpen.PDF_MIME) {
            throw SecurityException()
        }
        assertEquals(PeerAttachmentOpenResult.NO_READER, missing)
        assertEquals(PeerAttachmentOpenResult.UNREADABLE, denied)
    }

    @Test fun legacyFileIsSharedThroughTheReadOnlyAttachmentProvider() = withAttachment { file, _ ->
        val result = PeerAttachmentOpen.open(context, Uri.fromFile(file), "report.pdf", PeerAttachmentOpen.PDF_MIME) { intent ->
            assertEquals("content", intent.data?.scheme)
            assertEquals(file.canonicalFile, LocalAttachmentUris.resolve(context, requireNotNull(intent.data)))
            assertArrayEquals(file.readBytes(), context.contentResolver.openInputStream(requireNotNull(intent.data))?.use { it.readBytes() })
        }
        assertEquals(PeerAttachmentOpenResult.OPENED, result)
    }

    @Test fun downloadsUsesOnlyThePublicFileManagerIntentWithoutSharingTheAttachment() {
        val attempts = mutableListOf<Intent>()
        assertTrue(PeerAttachmentOpen.openDownloads {
            attempts += it
            if (attempts.size == 1) throw ActivityNotFoundException()
        })
        assertEquals("com.sec.android.app.myfiles", attempts.first().`package`)
        assertNull(attempts.last().`package`)
        for (intent in attempts) {
            assertEquals(DownloadManager.ACTION_VIEW_DOWNLOADS, intent.action)
            assertNull(intent.data)
            assertNull(intent.clipData)
            assertEquals(0, intent.flags)
        }
    }

    private fun withAttachment(test: (File, Uri) -> Unit) {
        val file = File(context.filesDir, "composer-attachments-v1/pdf-test-${UUID.randomUUID()}.pdf")
        file.parentFile?.mkdirs()
        try {
            file.writeText("%PDF-1.4\n")
            test(file, LocalAttachmentUris.forFile(context, file, "report.pdf", PeerAttachmentOpen.PDF_MIME))
        } finally {
            file.delete()
        }
    }
}
