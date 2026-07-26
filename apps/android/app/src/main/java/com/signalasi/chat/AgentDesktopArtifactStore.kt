package com.signalasi.chat

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.Locale

internal data class AgentDesktopArtifactIngestResult(
    val completed: Boolean,
    val artifactId: String,
    val artifactUri: String,
    val sha256: String,
    val taskId: String
)

internal object AgentDesktopArtifactStore {
    private const val ROOT_DIRECTORY = "desktop-artifacts"
    private const val MAX_ARTIFACT_BYTES = 64L * 1024L * 1024L
    private const val MAX_CHUNK_BYTES = 256 * 1024
    private const val MAX_CHUNK_COUNT = 256
    private val HEX_64 = Regex("^[0-9a-f]{64}$")

    @Synchronized
    fun ingest(context: Context, payload: JSONObject): AgentDesktopArtifactIngestResult {
        require(payload.optString("type") == "artifact_chunk") { "Unsupported artifact payload" }
        val artifactId = payload.getString("artifact_id").lowercase(Locale.ROOT)
        val artifactUri = payload.getString("artifact_uri")
        val taskId = payload.optString("task_id")
        val name = safeFileName(payload.optString("name"))
        val mimeType = payload.optString("mime_type").ifBlank { "application/octet-stream" }
        val sizeBytes = payload.getLong("size_bytes")
        val digest = payload.getString("sha256").lowercase(Locale.ROOT)
        val originalSizeBytes = payload.optLong("original_size_bytes", sizeBytes)
        val originalDigest = payload.optString("original_sha256", digest).lowercase(Locale.ROOT)
        val chunkIndex = payload.getInt("chunk_index")
        val chunkCount = payload.getInt("chunk_count")
        val chunkSize = payload.getInt("chunk_size_bytes")
        val chunkDigest = payload.getString("chunk_sha256").lowercase(Locale.ROOT)
        require(artifactId.matches(HEX_64) && digest.matches(HEX_64) && chunkDigest.matches(HEX_64))
        require(originalDigest.matches(HEX_64))
        require(Uri.parse(artifactUri).scheme == "signalasi-artifact")
        require(sizeBytes in 1..MAX_ARTIFACT_BYTES)
        require(originalSizeBytes >= sizeBytes)
        require(chunkCount in 1..MAX_CHUNK_COUNT && chunkIndex in 0 until chunkCount)
        require(chunkSize in 1..MAX_CHUNK_BYTES)
        require((sizeBytes + MAX_CHUNK_BYTES - 1) / MAX_CHUNK_BYTES == chunkCount.toLong())

        val bytes = Base64.decode(payload.getString("data_b64"), Base64.DEFAULT)
        require(bytes.size == chunkSize)
        require(sha256(bytes) == chunkDigest)

        existingRecord(context, artifactUri)?.let { record ->
            if (
                record.optString("artifact_id") == artifactId &&
                record.optString("sha256") == digest &&
                artifactFile(context, record)?.isFile == true
            ) {
                return AgentDesktopArtifactIngestResult(true, artifactId, artifactUri, digest, taskId)
            }
        }

        val incoming = File(root(context), "incoming/$artifactId")
        require(incoming.exists() || incoming.mkdirs())
        val manifest = File(incoming, "manifest.json")
        val expected = JSONObject()
            .put("artifact_id", artifactId)
            .put("artifact_uri", artifactUri)
            .put("task_id", taskId)
            .put("name", name)
            .put("mime_type", mimeType)
            .put("size_bytes", sizeBytes)
            .put("sha256", digest)
            .put("original_size_bytes", originalSizeBytes)
            .put("original_sha256", originalDigest)
            .put("chunk_count", chunkCount)
        if (manifest.isFile) {
            require(manifest.readText(Charsets.UTF_8) == expected.toString()) {
                "Artifact chunk metadata mismatch"
            }
        } else {
            writeAtomic(manifest, expected.toString().toByteArray(Charsets.UTF_8))
        }

        val chunkFile = File(incoming, "$chunkIndex.chunk")
        if (chunkFile.isFile) {
            require(chunkFile.length() == bytes.size.toLong() && sha256(chunkFile) == chunkDigest) {
                "Conflicting artifact chunk duplicate"
            }
        } else {
            writeAtomic(chunkFile, bytes)
        }
        val complete = (0 until chunkCount).all { File(incoming, "$it.chunk").isFile }
        if (!complete) {
            return AgentDesktopArtifactIngestResult(false, artifactId, artifactUri, digest, taskId)
        }

        val filesDirectory = File(root(context), "files").apply { require(exists() || mkdirs()) }
        val target = File(filesDirectory, "$artifactId-$name")
        val temporary = File(filesDirectory, "$artifactId.tmp")
        val calculated = MessageDigest.getInstance("SHA-256")
        var written = 0L
        FileOutputStream(temporary).buffered().use { output ->
            repeat(chunkCount) { index ->
                File(incoming, "$index.chunk").inputStream().buffered().use { input ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        calculated.update(buffer, 0, count)
                        written += count
                    }
                }
            }
        }
        val calculatedDigest = calculated.digest().joinToString("") { "%02x".format(it) }
        require(written == sizeBytes && calculatedDigest == digest) {
            temporary.delete()
            "Artifact integrity check failed"
        }
        if (target.exists()) target.delete()
        require(temporary.renameTo(target) || temporary.copyTo(target, overwrite = true).let { temporary.delete(); true })

        val record = JSONObject(expected.toString())
            .put("relative_file", target.relativeTo(root(context)).invariantSeparatorsPath)
            .put("stored_at", System.currentTimeMillis())
        writeRecord(context, artifactUri, record)
        incoming.deleteRecursively()
        return AgentDesktopArtifactIngestResult(true, artifactId, artifactUri, digest, taskId)
    }

    fun resolveBlock(context: Context, block: AgentRichBlock): AgentRichBlock {
        val sourceUri = block.metadata["artifact_source_uri"].orEmpty().ifBlank { block.uri }
        if (Uri.parse(sourceUri).scheme != "signalasi-artifact") return block
        val record = existingRecord(context, sourceUri) ?: return block
        val file = artifactFile(context, record)?.takeIf(File::isFile) ?: return block
        return block.copy(
            uri = contentUri(context, file).toString(),
            mimeType = record.optString("mime_type").ifBlank { block.mimeType },
            metadata = block.metadata + mapOf(
                "artifact_id" to record.optString("artifact_id"),
                "artifact_source_uri" to sourceUri,
                "size" to humanSize(record.optLong("size_bytes")),
                "size_bytes" to record.optLong("size_bytes").toString(),
                "sha256" to record.optString("sha256"),
                "transport" to "encrypted-fragmented",
                "storage" to "app_private",
                "saved_to_downloads" to record.optBoolean("saved_to_downloads", false).toString()
            )
        )
    }

    fun saveToDownloads(context: Context, block: AgentRichBlock): Result<String> = runCatching {
        require(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "System Downloads requires Android 10 or newer"
        }
        val resolved = resolveBlock(context, block)
        val sourceUri = resolved.metadata["artifact_source_uri"].orEmpty()
        val record = existingRecord(context, sourceUri) ?: error("Artifact is not available")
        val source = artifactFile(context, record)?.takeIf(File::isFile)
            ?: error("Artifact file is missing")
        val displayName = normalizedDownloadName(
            record.optString("name").ifBlank { source.name },
            record.optString("mime_type")
        )
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, displayName)
            put(MediaStore.Downloads.MIME_TYPE, record.optString("mime_type"))
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/SignalASI")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val destination = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: error("Download destination could not be created")
        try {
            resolver.openOutputStream(destination, "w")?.use { output ->
                source.inputStream().buffered().use { it.copyTo(output) }
            } ?: error("Download destination could not be opened")
            resolver.update(
                destination,
                ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
                null,
                null
            )
        } catch (failure: Throwable) {
            resolver.delete(destination, null, null)
            throw failure
        }
        record.put("saved_to_downloads", true)
            .put("saved_uri", destination.toString())
            .put("saved_at", System.currentTimeMillis())
        writeRecord(context, sourceUri, record)
        "${Environment.DIRECTORY_DOWNLOADS}/SignalASI/$displayName"
    }

    fun localFile(context: Context, block: AgentRichBlock): File? {
        val resolved = resolveBlock(context, block)
        val sourceUri = resolved.metadata["artifact_source_uri"].orEmpty()
        val record = existingRecord(context, sourceUri) ?: return null
        return artifactFile(context, record)?.takeIf(File::isFile)
    }

    fun clear(context: Context) {
        root(context).deleteRecursively()
    }

    private fun existingRecord(context: Context, artifactUri: String): JSONObject? {
        if (artifactUri.isBlank()) return null
        val file = recordFile(context, artifactUri)
        return runCatching { JSONObject(file.readText(Charsets.UTF_8)) }.getOrNull()
    }

    private fun writeRecord(context: Context, artifactUri: String, record: JSONObject) {
        writeAtomic(recordFile(context, artifactUri), record.toString().toByteArray(Charsets.UTF_8))
    }

    private fun recordFile(context: Context, artifactUri: String): File {
        val directory = File(root(context), "metadata").apply { require(exists() || mkdirs()) }
        return File(directory, "${sha256(artifactUri.toByteArray(Charsets.UTF_8))}.json")
    }

    private fun artifactFile(context: Context, record: JSONObject): File? {
        val relative = record.optString("relative_file").replace('\\', '/').trim('/')
        if (relative.isBlank() || relative.split('/').any { it in setOf("", ".", "..") }) return null
        val root = root(context).canonicalFile
        val candidate = File(root, relative).canonicalFile
        return candidate.takeIf { it.toPath().startsWith(root.toPath()) }
    }

    private fun contentUri(context: Context, file: File): Uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.files",
        file
    )

    private fun root(context: Context): File =
        File(context.applicationContext.filesDir, ROOT_DIRECTORY)

    private fun writeAtomic(target: File, bytes: ByteArray) {
        require(target.parentFile?.exists() == true || target.parentFile?.mkdirs() == true)
        val temporary = File(target.parentFile, "${target.name}.tmp")
        temporary.outputStream().buffered().use { it.write(bytes) }
        if (target.exists()) target.delete()
        require(temporary.renameTo(target) || temporary.copyTo(target, overwrite = true).let { temporary.delete(); true })
    }

    private fun safeFileName(value: String): String {
        val name = value.substringAfterLast('/').substringAfterLast('\\')
            .replace(Regex("[\\u0000-\\u001f<>:\"/\\\\|?*]"), "_")
            .trim()
            .take(180)
        return name.ifBlank { "SignalASI-artifact" }
    }

    private fun normalizedDownloadName(name: String, mimeType: String): String {
        if (mimeType != "image/jpeg" || name.substringAfterLast('.', "").lowercase() in setOf("jpg", "jpeg")) {
            return safeFileName(name)
        }
        return safeFileName(name.substringBeforeLast('.', name) + ".jpg")
    }

    private fun humanSize(bytes: Long): String = when {
        bytes < 1024L -> "$bytes B"
        bytes < 1024L * 1024L -> String.format(Locale.ROOT, "%.1f KB", bytes / 1024.0)
        else -> String.format(Locale.ROOT, "%.1f MB", bytes / (1024.0 * 1024.0))
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
