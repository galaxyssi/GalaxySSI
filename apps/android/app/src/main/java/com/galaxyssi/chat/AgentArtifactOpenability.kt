package com.galaxyssi.chat

import android.content.Context
import android.graphics.BitmapFactory
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.pdmodel.PDDocument
import java.io.File
import java.io.InputStreamReader
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.util.Locale
import java.util.zip.CRC32
import java.util.zip.ZipFile

/** Host-owned openability evidence, not a guarantee about a document's semantic content. */
internal class AgentArtifactOpenability(private val context: Context? = null) {
    fun inspect(file: File, expectedSha256: String, maximumExpandedBytes: Long = 96L * 1024 * 1024): AgentNativeJsonObject {
        var scope = "byte_stream"
        return try {
            require(file.isFile && file.canRead()) { "File is not readable" }
            val extension = file.extension.lowercase(Locale.ROOT)
            val details: Map<String, Any?> = when {
                extension == "pdf" -> {
                    scope = "pdf_document_open"
                    val app = requireNotNull(context) { "PDF inspection requires the Android runtime" }
                    PDFBoxResourceLoader.init(app.applicationContext)
                    PDDocument.load(file, MemoryUsageSetting.setupMixed(4L * 1024 * 1024).setTempDir(app.cacheDir)).use { document ->
                        require(document.numberOfPages > 0) { "PDF contains no pages" }
                        val page = document.getPage(0)
                        require(page.mediaBox.width > 0 && page.mediaBox.height > 0) { "PDF page dimensions are invalid" }
                        mapOf("page_count" to document.numberOfPages, "all_pages_rendered" to false)
                    }
                }
                extension in IMAGE_EXTENSIONS -> {
                    scope = "image_first_frame_decode"
                    requireNotNull(context) { "Image inspection requires the Android runtime" }
                    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(file.path, options)
                    require(options.outWidth > 0 && options.outHeight > 0) { "Image dimensions could not be decoded" }
                    val width = options.outWidth
                    val height = options.outHeight
                    options.inJustDecodeBounds = false
                    options.inSampleSize = 1
                    while (maxOf(width, height) / options.inSampleSize > 1024) options.inSampleSize *= 2
                    val bitmap = requireNotNull(BitmapFactory.decodeFile(file.path, options)) { "Image pixels could not be decoded" }
                    try { mapOf("width" to width, "height" to height, "mime_type" to options.outMimeType) }
                    finally { bitmap.recycle() }
                }
                extension in OFFICE_EXTENSIONS -> {
                    scope = "office_package_open"
                    val archive = verifyArchive(file, maximumExpandedBytes)
                    require(file.length() <= MAX_XML_PACKAGE_BYTES) { "Office inspection exceeds the in-memory budget" }
                    AgentOfficeDocumentExtractor.verifyOpenability(file.readBytes(), extension)
                    archive
                }
                extension in ARCHIVE_EXTENSIONS -> {
                    scope = "archive_entries_read"
                    verifyArchive(file, maximumExpandedBytes)
                }
                extension in TEXT_EXTENSIONS -> {
                    scope = "utf8_text_read"
                    val decoder = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT)
                    var count = 0L
                    InputStreamReader(file.inputStream(), decoder).use { reader ->
                        val buffer = CharArray(8192)
                        while (true) {
                            val read = reader.read(buffer)
                            if (read < 0) break
                            count += read
                        }
                    }
                    mapOf("characters_read" to count)
                }
                else -> emptyMap()
            }
            // UI delivery independently checks this digest again before opening/saving the artifact.
            val actual = digest(file)
            require(actual.equals(expectedSha256, ignoreCase = true)) { "File changed during inspection" }
            mapOf("status" to "verified", "scope" to scope, "sha256" to actual,
                "checked_at_millis" to System.currentTimeMillis(), "details" to details)
        } catch (error: Exception) {
            mapOf("status" to "unverified", "scope" to scope,
                "reason" to error.javaClass.simpleName, "detail" to error.message.orEmpty().take(240))
        }
    }

    private fun verifyArchive(file: File, maximumExpandedBytes: Long): Map<String, Any?> = ZipFile(file).use { zip ->
        require(zip.size() in 1..MAX_ARCHIVE_ENTRIES) { "Archive entry count is outside the inspection budget" }
        var total = 0L
        val names = hashSetOf<String>()
        val buffer = ByteArray(64 * 1024)
        for (entry in zip.entries().asSequence()) {
            val name = entry.name.replace('\\', '/')
            require(!name.startsWith('/') && ':' !in name && name.split('/').none { it == ".." } && names.add(name)) {
                "Archive contains an unsafe or duplicate entry"
            }
            if (entry.isDirectory) continue
            val crc = CRC32()
            var bytes = 0L
            zip.getInputStream(entry).use { input ->
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    total += read
                    bytes += read
                    require(total <= maximumExpandedBytes) { "Archive exceeds the expanded inspection budget" }
                    crc.update(buffer, 0, read)
                }
            }
            require(bytes == entry.size && crc.value == entry.crc) { "Archive entry integrity check failed" }
        }
        mapOf("entry_count" to zip.size(), "expanded_bytes" to total)
    }

    private fun digest(file: File): String {
        val hash = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                hash.update(buffer, 0, count)
            }
        }
        return hash.digest().joinToString("") { "%02x".format(it) }
    }

    companion object {
        private val IMAGE_EXTENSIONS = setOf("png", "jpg", "jpeg", "webp", "gif", "bmp")
        private val OFFICE_EXTENSIONS = setOf("docx", "xlsx", "pptx")
        private val ARCHIVE_EXTENSIONS = setOf("zip", "jar", "apk", "aab")
        private val TEXT_EXTENSIONS = setOf("txt", "md", "csv", "tsv", "html", "htm", "json", "xml", "svg",
            "py", "js", "ts", "kt", "java", "c", "cpp", "h", "css", "yaml", "yml", "toml", "log", "sh")
        private const val MAX_XML_PACKAGE_BYTES = 24L * 1024 * 1024
        private const val MAX_ARCHIVE_ENTRIES = 50_000
    }
}
