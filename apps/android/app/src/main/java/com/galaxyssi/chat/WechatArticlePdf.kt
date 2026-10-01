package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import android.net.Uri
import android.provider.MediaStore
import android.text.Html
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.Base64
import java.io.File

internal data class WechatSavedArticle(val uri: Uri, val name: String, val pages: Int)

/** Local PDF rendering; no model, remote renderer, or screen capture is involved. */
internal object WechatArticlePdf {
    fun render(html: String, destination: File, checkpoint: () -> Unit = {}): Int {
        val document = PdfDocument()
        var page: PdfDocument.Page? = null
        var pageNumber = 0
        var y = 32f
        val width = 531
        val bottom = 806f
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 12f; color = Color.BLACK }
        fun nextPage() {
            checkpoint()
            page?.let(document::finishPage)
            require(pageNumber < 500) { "article_page_limit" }
            page = document.startPage(PdfDocument.PageInfo.Builder(595, 842, ++pageNumber).create())
            y = 32f
        }
        try {
            nextPage()
            WechatArticleDocuments.blocks(html).forEach { block ->
                checkpoint()
                when (block) {
                    is WechatArticleBlock.Text -> {
                        val text = Html.fromHtml(block.html, Html.FROM_HTML_MODE_COMPACT).trim()
                        if (text.isNotEmpty()) {
                            val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, width)
                                .setAlignment(Layout.Alignment.ALIGN_NORMAL).setIncludePad(false)
                                .setLineSpacing(4f, 1f).build()
                            var first = 0
                            while (first < layout.lineCount) {
                                checkpoint()
                                val top = layout.getLineTop(first)
                                var last = first
                                while (last < layout.lineCount && layout.getLineBottom(last) - top <= bottom - y) last++
                                if (last == first) {
                                    require(y > 32f) { "article_line_exceeds_page" }
                                    nextPage(); continue
                                }
                                val height = layout.getLineBottom(last - 1) - top
                                val canvas = page!!.canvas
                                canvas.save()
                                canvas.clipRect(32f, y, 563f, y + height)
                                canvas.translate(32f, y - top)
                                layout.draw(canvas)
                                canvas.restore()
                                y += height + 8
                                first = last
                                if (first < layout.lineCount) nextPage()
                            }
                        }
                    }
                    is WechatArticleBlock.Image -> {
                        require(block.source.startsWith("data:image/")) { "article_image_missing" }
                        val bytes = Base64.decode(block.source.substringAfter("base64,", ""), Base64.DEFAULT)
                        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "article_image_invalid" }
                        var sample = 1
                        while (bounds.outWidth / sample > 1600 || bounds.outHeight / sample > 2400) sample *= 2
                        val bitmap = requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size,
                            BitmapFactory.Options().apply { inSampleSize = sample }))
                        try {
                            val scale = minOf(width.toFloat() / bitmap.width, 750f / bitmap.height, 1f)
                            val w = bitmap.width * scale
                            val h = bitmap.height * scale
                            if (y + h > bottom) nextPage()
                            val x = (595f - w) / 2
                            page!!.canvas.drawBitmap(bitmap, null, RectF(x, y, x + w, y + h),
                                Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
                            y += h + 10
                        } finally { bitmap.recycle() }
                    }
                }
            }
            page?.let(document::finishPage)
            page = null
            checkpoint()
            destination.outputStream().use(document::writeTo)
            return pageNumber
        } finally {
            page?.let { runCatching { document.finishPage(it) } }
            document.close()
        }
    }

    fun save(context: Context, pdf: File, name: String, pages: Int, checkpoint: () -> Unit = {}): WechatSavedArticle {
        require(name.endsWith(".pdf") && '/' !in name && '\\' !in name && pdf.length() > 0 && pages > 0)
        val resolver = context.contentResolver
        checkpoint()
        val uri = checkNotNull(resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, "application/pdf")
            put(MediaStore.Downloads.RELATIVE_PATH, WechatArticleDocuments.DIRECTORY)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }))
        try {
            pdf.inputStream().use { input -> checkNotNull(resolver.openOutputStream(uri, "w")).use { output ->
                val buffer = ByteArray(64 * 1024)
                var length = input.read(buffer)
                while (length >= 0) { checkpoint(); output.write(buffer, 0, length); length = input.read(buffer) }
            } }
            checkpoint()
            check(resolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null) == 1)
            return WechatSavedArticle(uri, name, pages)
        } catch (error: Exception) {
            runCatching { resolver.delete(uri, null, null) }
            throw error
        }
    }
}
