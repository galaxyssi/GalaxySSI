package com.galaxyssi.chat

import android.graphics.pdf.PdfDocument
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class ScreenAssistantPdfDownloadsDeviceTest {
    @Test fun savesExactPdfReusesCopyAndRestoresDeletedCopy() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val id = UUID.randomUUID().toString()
        val pdf = File(context.cacheDir, "download-test-$id.pdf")
        val preferences = context.getSharedPreferences("screen_content_downloads", 0)
        val resolver = context.contentResolver
        fun saved() = Uri.parse(requireNotNull(preferences.getString(id, null)))
        try {
            val document = PdfDocument()
            try {
                val page = document.startPage(PdfDocument.PageInfo.Builder(100, 100, 1).create())
                document.finishPage(page)
                pdf.outputStream().use(document::writeTo)
            } finally { document.close() }
            val path = ScreenAssistantPdfDownloads.save(context, id, pdf)
            assertTrue(path.startsWith("Download/GalaxySSI/"))
            val first = saved()
            assertArrayEquals(pdf.readBytes(), resolver.openInputStream(first)!!.use { it.readBytes() })
            assertEquals(path, ScreenAssistantPdfDownloads.save(context, id, pdf))
            assertEquals(first, saved())
            assertEquals(1, resolver.delete(first, null, null))
            ScreenAssistantPdfDownloads.save(context, id, pdf)
            assertNotEquals(first, saved())
            assertArrayEquals(pdf.readBytes(), resolver.openInputStream(saved())!!.use { it.readBytes() })
        } finally {
            preferences.getString(id, null)?.let { resolver.delete(Uri.parse(it), null, null) }
            preferences.edit().remove(id).commit()
            pdf.delete()
        }
    }
}
