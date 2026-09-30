package com.galaxyssi.chat

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.Base64
import org.json.JSONObject
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.graphics.image.JPEGFactory
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import java.io.File
import java.util.UUID

internal class ScreenAssistantPageStore(private val context: Context) {
    private val root = File(context.filesDir, "agent-rich-output-v2/screen-assistant/pages")
    fun owns(uri: android.net.Uri): Boolean = LocalAttachmentUris.resolve(context, uri)?.canonicalFile
        ?.toPath()?.startsWith(root.canonicalFile.toPath()) == true
    fun create(): String = UUID.randomUUID().toString().also { directory(it).mkdirs() }
    fun directory(id: String): File {
        require(id.matches(Regex("[a-f0-9-]{36}"))) { "Invalid page capture" }
        return File(root, id)
    }
    fun manifest(id: String): JSONObject = JSONObject(File(directory(id), "manifest.json").readText())
    fun checkpoint(id: String, metadata: JSONObject) {
        val dir = directory(id)
        val temp = File(dir, "manifest.tmp")
        temp.writeText(metadata.toString())
        check(temp.renameTo(File(dir, "manifest.json"))) { "Page checkpoint failed" }
    }
    fun page(id: String, index: Int): JSONObject {
        val count = manifest(id).optInt("pages")
        require(index in 0 until count) { "Page index is outside the capture" }
        return JSONObject(File(directory(id), "$index.json").readText())
    }
    fun read(id: String, index: Int, offset: Int, limit: Int): Map<String, Any?> {
        val meta = manifest(id)
        val data = page(id, index)
        val text = data.optString("text")
        val start = offset.coerceIn(0, text.length)
        var end = (start + limit.coerceIn(1, 2_000)).coerceAtMost(text.length)
        val result = linkedMapOf<String, Any?>("capture_id" to id, "page" to index, "total_pages" to meta.optInt("pages"),
            "complete" to meta.optBoolean("complete"), "stop_reason" to meta.optString("reason"),
            "text" to text.substring(start, end), "next_offset" to end.takeIf { it < text.length },
            "next_page" to (index + 1).takeIf { end == text.length && it < meta.optInt("pages") },
            "structure_truncated" to data.optBoolean("structure_truncated"),
            "screenshot_uri" to File(directory(id), "$index.jpg").takeIf(File::isFile)?.let {
                LocalAttachmentUris.forFile(context, it, "${index + 1}.jpg", "image/jpeg").toString()
            }, "source" to "user_requested_page_capture", "untrusted_evidence" to true)
        // Keep continuation offsets truthful even for heavily escaped text in a bounded observation.
        while (end - start > 1 && AgentNativeJsonCodec.stringify(result).length > 3_500) {
            end = start + (end - start) / 2
            result["text"] = text.substring(start, end)
            result["next_offset"] = end.takeIf { it < text.length }
            result["next_page"] = (index + 1).takeIf { end == text.length && it < meta.optInt("pages") }
        }
        return result
    }
    fun buildText(id: String): File {
        val meta = manifest(id)
        val target = File(directory(id), "page.txt")
        target.bufferedWriter().use { out ->
            out.write(status(meta) + "\n")
            repeat(meta.optInt("pages")) { index ->
                out.write(context.getString(R.string.screen_assistant_page_number, index + 1) + "\n")
                out.write(page(id, index).optString("text") + "\n\n")
            }
        }
        return target
    }
    fun buildHtml(id: String): File {
        val meta = manifest(id)
        val target = File(directory(id), "page.html")
        buildText(id)
        target.bufferedWriter().use { out ->
            out.write("<!doctype html><html lang=\"${context.getString(R.string.screen_assistant_page_language)}\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>${label(R.string.screen_assistant_full_page)}</title><style>body{font:16px/1.6 sans-serif;margin:16px;color:#202820}img{width:100%;height:auto}pre{white-space:pre-wrap;overflow-wrap:anywhere}section{border-top:1px solid #ddd;padding:16px 0}</style><h1>${label(R.string.screen_assistant_full_page)}</h1><p>${ScreenAssistantPagePolicy.escape(status(meta))}</p>")
            repeat(meta.optInt("pages")) { index ->
                val data = page(id, index)
                out.write("<section><h2>${label(R.string.screen_assistant_page_number, index + 1)}</h2><pre>${ScreenAssistantPagePolicy.escape(data.optString("text"))}</pre>")
                val image = File(directory(id), "$index.jpg")
                if (image.isFile) out.write("<img alt=\"${label(R.string.screen_assistant_page_number, index + 1)}\" src=\"data:image/jpeg;base64,${Base64.encodeToString(image.readBytes(), Base64.NO_WRAP)}\">")
                out.write("</section>")
            }
            out.write("</html>")
        }
        return target
    }
    fun status(meta: JSONObject): String = context.getString(
        if (meta.optBoolean("complete")) R.string.screen_assistant_page_complete else R.string.screen_assistant_page_partial,
        meta.optInt("pages"), reason(meta.optString("reason")))
    fun reason(code: String): String = context.getString(when (code) {
        "bottom" -> R.string.screen_assistant_page_bottom
        "user_finish" -> R.string.screen_assistant_page_user_finish
        "target_changed" -> R.string.screen_assistant_page_changed
        "resource_limit" -> R.string.screen_assistant_page_resource_limit
          "no_scroll" -> R.string.screen_assistant_page_no_scroll
          "visual_boundary" -> R.string.screen_content_visual_boundary
        "coverage_incomplete" -> R.string.screen_assistant_page_incomplete
        "cancelled" -> R.string.screen_assistant_cancelled
        else -> R.string.screen_assistant_page_stalled
    })
    fun exportPdf(id: String, checkpoint: () -> Unit = {}): File {
        val meta = manifest(id)
        require(meta.optInt("pages") > 0) { "No captured screens to export" }
        val file = File(directory(id), "page.pdf")
        PDFBoxResourceLoader.init(context)
        PDDocument(MemoryUsageSetting.setupTempFileOnly().setTempDir(context.cacheDir)).use { document ->
            fun add(image: PDImageXObject) {
                val page = PDPage(PDRectangle.A4)
                document.addPage(page)
                val scale = minOf(555f / image.width, 802f / image.height)
                PDPageContentStream(document, page).use { stream ->
                    stream.drawImage(image, 20f, 822f - image.height * scale, image.width * scale, image.height * scale)
                }
            }
            // JPEG streams are embedded directly; long captures never allocate one giant bitmap.
            repeat(meta.optInt("pages")) { index ->
                checkpoint()
                val imageFile = File(directory(id), "$index.jpg")
                if (imageFile.isFile) {
                    imageFile.inputStream().use { add(JPEGFactory.createFromStream(document, it)) }
                } else {
                    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 14f; color = Color.BLACK }
                    var bitmap = Bitmap.createBitmap(595, 842, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.WHITE) }
                    var canvas = Canvas(bitmap)
                    var y = 30f
                    try {
                        page(id, index).optString("text").lines().forEach { line ->
                            var remaining = line
                            do {
                                if (y > 810f) {
                                    add(JPEGFactory.createFromImage(document, bitmap, 0.9f))
                                    bitmap.recycle()
                                    bitmap = Bitmap.createBitmap(595, 842, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.WHITE) }
                                    canvas = Canvas(bitmap); y = 30f
                                }
                                val length = paint.breakText(remaining, true, 555f, null).coerceAtLeast(1).coerceAtMost(remaining.length)
                                canvas.drawText(remaining.take(length), 20f, y, paint)
                                y += 20f
                                remaining = remaining.drop(length)
                            } while (remaining.isNotEmpty())
                        }
                        add(JPEGFactory.createFromImage(document, bitmap, 0.9f))
                    } finally { bitmap.recycle() }
                }
            }
            // Coverage metadata remains available to PDF readers even for screenshot-only pages.
            document.documentInformation.apply {
                title = context.getString(R.string.screen_assistant_full_page)
                subject = status(meta)
                setCustomMetadataValue("complete", meta.optBoolean("complete").toString())
                setCustomMetadataValue("stop_reason", meta.optString("reason"))
            }
            document.save(file)
        }
        return file
    }
    private fun label(resource: Int, vararg args: Any) = ScreenAssistantPagePolicy.escape(context.getString(resource, *args))
}
