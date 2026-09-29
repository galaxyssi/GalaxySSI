package com.galaxyssi.chat

import android.content.ContentUris
import android.content.Context
import android.graphics.BitmapFactory
import android.os.SystemClock
import android.provider.MediaStore
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import java.util.zip.ZipFile

/** Inspect only files returned by a synthetic test turn; never fabricate a model artifact. */
internal object BusinessArtifactEvidence {
    fun collect(context: Context, expected: JSONObject, directory: File,
                latest: () -> AgentTranscriptEntry?): JSONObject {
        val start = SystemClock.elapsedRealtime()
        if (expected.optBoolean("text_only")) {
            val entry = latest()
            val files = entry?.let { AgentRichContentCodec.decode(it.richOutputJson) }.orEmpty()
                .count { it.type in setOf(AgentRichBlockType.FILE, AgentRichBlockType.IMAGE) }
            return JSONObject().put("correct", files == 0 && !entry?.text.isNullOrBlank())
                .put("check_scope", "text_only_delivery_not_content")
                .put("unexpected_file_count", files).put("content_verified", false)
                .put("requires_human_review", true)
        }
        var blocks = emptyList<AgentRichBlock>()
        var allPresent = false
        val deadline = start + 90_000L
        do {
            blocks = latest()?.let { AgentRichContentCodec.decode(it.richOutputJson) }.orEmpty()
                .filter { it.type in setOf(AgentRichBlockType.FILE, AgentRichBlockType.IMAGE) }
            allPresent = blocks.isNotEmpty() && blocks.all { AgentDesktopArtifactStore.localFile(context, it) != null }
            if (allPresent) break
            SystemClock.sleep(500)
        } while (SystemClock.elapsedRealtime() < deadline)
        val presenceWaitMs = SystemClock.elapsedRealtime() - start
        var saveVerificationMs = 0L
        val records = JSONArray()
        val prefix = expected.getString("name_prefix")
        directory.mkdirs()
        blocks.forEachIndexed { index, block ->
            val record = JSONObject().put("title", block.title).put("type", block.type.name)
                .put("mime_type", block.mimeType).put("uri", block.uri)
            val read = AgentDesktopArtifactStore.withDecryptedArtifact(context, block) { source ->
                require(source.length() in 1..64L * 1024 * 1024)
                val extension = source.extension.lowercase()
                val target = File(directory, "artifact-$index.$extension")
                source.copyTo(target, overwrite = true)
                val sha = source.inputStream().use(::digest)
                record.put("evidence_file", target.name).put("extension", extension)
                    .put("size", source.length()).put("sha256", sha)
                    .put("version_name_matches", source.name.contains(prefix))
                    .put("container_valid", validContainer(source, extension))
                if (extension in setOf("png", "jpg", "jpeg")) {
                    val size = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(source.path, size)
                    record.put("image_width", size.outWidth).put("image_height", size.outHeight)
                }
                val saveStart = SystemClock.elapsedRealtime()
                val saved = AgentDesktopArtifactStore.saveToDownloads(context, block)
                record.put("save_api_pass", saved.isSuccess)
                saved.onSuccess { path ->
                    record.put("download_path", path)
                        .put("download_hash_matches", downloadedDigest(context, path.substringAfterLast('/')) == sha)
                }
                saved.onFailure { record.put("save_error_type", it.javaClass.simpleName) }
                saveVerificationMs += SystemClock.elapsedRealtime() - saveStart
            }
            record.put("received", read.isSuccess)
            read.onFailure { record.put("read_error_type", it.javaClass.simpleName) }
            records.put(record)
        }
        val items = (0 until records.length()).map(records::getJSONObject)
        val extensions = expected.getJSONArray("extensions")
        val missing = (0 until extensions.length()).map(extensions::getString).filter { extension ->
            items.none { it.optString("extension") == extension && it.optBoolean("container_valid") &&
                it.optBoolean("version_name_matches") && it.optBoolean("download_hash_matches") }
        }
        val preview = items.any { it.optString("extension") in setOf("png", "jpg", "jpeg") &&
            it.optBoolean("container_valid") &&
            it.optInt("image_width") >= 128 && it.optInt("image_height") >= 128 &&
            it.optBoolean("version_name_matches") && it.optBoolean("download_hash_matches") }
        val imageCount = items.count { it.optString("extension") in setOf("png", "jpg", "jpeg") }
        val imageCountOk = !expected.has("max_image_count") || imageCount <= expected.getInt("max_image_count")
        val imageFormatOk = imageFormatsMatch(expected, items)
        val dimensions = expected.optJSONArray("expected_dimensions")
        val dimensionsOk = dimensions == null || items.filter { it.has("image_width") }.let { images ->
            images.isNotEmpty() && images.all { it.optInt("image_width") == dimensions.getInt(0) &&
                it.optInt("image_height") == dimensions.getInt(1) }
        }
        val allVerified = allArtifactsVerified(items)
        return JSONObject().put("correct", allPresent && allVerified && missing.isEmpty() &&
                (!expected.optBoolean("preview_required", true) || preview) && imageCountOk && imageFormatOk && dimensionsOk)
            .put("check_scope", "containers_delivery_and_save_only")
            .put("artifact_wait_ms", SystemClock.elapsedRealtime() - start)
            .put("artifact_presence_wait_ms", presenceWaitMs)
            .put("all_artifacts_present", allPresent)
            .put("all_artifacts_verified", allVerified)
            .put("save_verification_ms", saveVerificationMs)
            .put("artifacts", records).put("missing_extensions", JSONArray(missing)).put("preview_received", preview)
            .put("image_count", imageCount).put("image_count_ok", imageCountOk)
            .put("image_format_ok", imageFormatOk).put("dimensions_ok", dimensionsOk)
            .put("content_verified", false).put("preview_fidelity_verified", false)
            .put("ui_open_save_verified", false).put("requires_human_review", true)
    }

    internal fun allArtifactsVerified(items: List<JSONObject>): Boolean =
        items.isNotEmpty() && items.all { item ->
            listOf("received", "container_valid", "version_name_matches", "save_api_pass",
                "download_hash_matches").all { item.optBoolean(it) }
        }

    internal fun imageFormatsMatch(expected: JSONObject, items: List<JSONObject>): Boolean {
        val allowed = expected.optJSONArray("image_extensions")?.let { list ->
            (0 until list.length()).map(list::getString).toSet()
        }
        val images = items.filter { it.optString("type") == AgentRichBlockType.IMAGE.name ||
            it.optString("extension") in setOf("png", "jpg", "jpeg") }
        // Frozen Office prompts explicitly request PNG previews, even though the
        // original catalog did not repeat that constraint as image_extensions.
        return images.all { item ->
            item.optBoolean("container_valid") &&
                (!expected.optBoolean("editable_office") || item.optString("extension") == "png") &&
                (allowed == null || item.optString("extension") in allowed)
        } && (allowed == null || images.isNotEmpty())
    }

    internal fun validContainer(file: File, extension: String): Boolean = runCatching {
        when (extension) {
            "docx", "xlsx", "pptx" -> ZipFile(file).use { zip ->
                val main = mapOf("docx" to "word/document.xml", "xlsx" to "xl/workbook.xml", "pptx" to "ppt/presentation.xml")
                zip.size() <= 10_000 && zip.getEntry("[Content_Types].xml") != null && zip.getEntry(main.getValue(extension)) != null
            }
            "pdf" -> file.inputStream().use {
                val header = ByteArray(5)
                it.read(header) == header.size && String(header, Charsets.US_ASCII) == "%PDF-"
            }
            "png", "jpg", "jpeg" -> BitmapFactory.Options().apply { inJustDecodeBounds = true }.let {
                BitmapFactory.decodeFile(file.path, it)
                val expectedMime = if (extension == "png") "image/png" else "image/jpeg"
                it.outWidth > 0 && it.outHeight > 0 && it.outMimeType == expectedMime
            }
            else -> false
        }
    }.getOrDefault(false)

    private fun downloadedDigest(context: Context, name: String): String? {
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        context.contentResolver.query(collection, arrayOf(MediaStore.Downloads._ID),
            "${MediaStore.Downloads.DISPLAY_NAME}=? AND ${MediaStore.Downloads.RELATIVE_PATH}=?",
            arrayOf(name, "Download/GalaxySSI/"), "${MediaStore.Downloads._ID} DESC")?.use { cursor ->
            if (cursor.moveToFirst()) return context.contentResolver.openInputStream(
                ContentUris.withAppendedId(collection, cursor.getLong(0)))?.use(::digest)
        }
        return null
    }

    private fun digest(input: InputStream): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val size = input.read(buffer)
            if (size < 0) break
            digest.update(buffer, 0, size)
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
