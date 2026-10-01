package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class WechatArticlePdfDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun savesReadableMultiPageArticleWithOrderedImageAndFinalParagraph() {
        val id = UUID.randomUUID().toString()
        val file = File(context.cacheDir, "wechat-test-$id.pdf")
        val image = Bitmap.createBitmap(400, 200, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.BLUE) }
        val png = ByteArrayOutputStream().also { image.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        image.recycle()
        val html = "<h1>公众号文章保存验证</h1><p>BEGIN-ARTICLE 中文开头</p>" +
            "<img src='data:image/png;base64,${Base64.encodeToString(png, Base64.NO_WRAP)}'>" +
            (1..120).joinToString("") { "<p>Section $it: 中文测试段落，验证全文分页和图文顺序。</p>" } +
            "<p>END-ARTICLE 最后一段，不能遗漏。</p>"
        var saved: WechatSavedArticle? = null
        try {
            val pages = WechatArticlePdf.render(html, file)
            assertTrue(pages >= 3)
            PDFBoxResourceLoader.init(context)
            PDDocument.load(file).use { doc ->
                assertEquals(pages, doc.numberOfPages)
                val text = PDFTextStripper().getText(doc)
                assertTrue(text.contains("BEGIN-ARTICLE"))
                assertTrue(text.contains("END-ARTICLE"))
                assertTrue(text.contains("Section 120"))
            }
            PdfRenderer(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)).use { pdf ->
                val bitmap = Bitmap.createBitmap(595, 842, Bitmap.Config.ARGB_8888)
                bitmap.eraseColor(Color.WHITE)
                pdf.openPage(0).use { it.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY) }
                assertTrue((0 until bitmap.height step 5).any { y ->
                    (0 until bitmap.width step 5).any { x -> bitmap.getPixel(x, y) == Color.BLUE }
                })
                if (InstrumentationRegistry.getArguments().getString("preview") == "true") {
                    listOf(0, pdf.pageCount / 2, pdf.pageCount - 1).distinct().forEach { index ->
                        bitmap.eraseColor(Color.WHITE)
                        pdf.openPage(index).use { it.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY) }
                        File(context.cacheDir, "wechat-pdf-test-$index.png").outputStream().use {
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                        }
                    }
                }
                bitmap.recycle()
            }
            saved = WechatArticlePdf.save(context, file, "wechat-test-$id.pdf", pages)
            context.contentResolver.query(saved.uri, arrayOf(MediaStore.Downloads.RELATIVE_PATH,
                MediaStore.Downloads.IS_PENDING), null, null, null)!!.use {
                assertTrue(it.moveToFirst())
                assertEquals(WechatArticleDocuments.DIRECTORY + "/", it.getString(0))
                assertEquals(0, it.getInt(1))
            }
            assertArrayEquals(file.readBytes(), context.contentResolver.openInputStream(saved.uri)!!.use { it.readBytes() })
        } finally {
            saved?.let { context.contentResolver.delete(it.uri, null, null) }
            file.delete()
        }
    }

    @Test fun cancellationDoesNotPublishADownload() {
        val file = File(context.cacheDir, "wechat-cancel-${UUID.randomUUID()}.pdf")
        try {
            assertTrue(runCatching { WechatArticlePdf.render("<p>content</p>", file) { error("cancelled") } }.isFailure)
            assertFalse(file.exists())
            assertTrue(runCatching { WechatArticlePdf.render("<p>body</p><img src='https://example.com/missing.png'>", file) }.isFailure)
        } finally { file.delete() }
    }
}
