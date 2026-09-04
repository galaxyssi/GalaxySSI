package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.net.URLConnection
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

internal object AgentDesktopArtifactActions {
    private const val MAX_TEXT_PREVIEW_BYTES = 1024 * 1024
    private const val MAX_ARCHIVE_ENTRIES = 500
    private const val MAX_EXTRACTED_BYTES = 128L * 1024L * 1024L

    fun readTextPreview(source: File): Result<String> = runCatching {
        require(source.length() <= MAX_TEXT_PREVIEW_BYTES) { "File is too large to preview" }
        val bytes = source.readBytes()
        require(bytes.none { it == 0.toByte() }) { "Binary file cannot be shown as text" }
        bytes.toString(Charsets.UTF_8)
    }

    fun archivePreview(source: File): Result<List<String>> = runCatching {
        require(source.extension.equals("zip", true)) { "This archive format cannot be previewed" }
        ZipFile(source).use { archive ->
            buildList {
                val entries = archive.entries()
                while (entries.hasMoreElements() && size < MAX_ARCHIVE_ENTRIES) {
                    val entry = entries.nextElement()
                    add(
                        buildString {
                            append(entry.name)
                            if (!entry.isDirectory && entry.size >= 0L) {
                                append("  ")
                                append(humanSize(entry.size))
                            }
                        }
                    )
                }
            }
        }
    }

    fun extractZipToDownloads(context: Context, source: File): Result<String> = runCatching {
        require(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
        require(source.extension.equals("zip", true)) { "Only ZIP extraction is supported" }
        val folder = safeSegment(source.nameWithoutExtension).ifBlank { "Archive" }
        val created = mutableListOf<Uri>()
        var entries = 0
        var extracted = 0L
        try {
            ZipInputStream(source.inputStream().buffered()).use { archive ->
                while (true) {
                    val entry = archive.nextEntry ?: break
                    val parts = safeArchiveParts(entry)
                    if (!entry.isDirectory) {
                        require(++entries <= MAX_ARCHIVE_ENTRIES) { "Archive contains too many files" }
                        val displayName = safeSegment(parts.last())
                        val relativeDirectory = parts.dropLast(1).joinToString("/")
                        val relativePath = buildString {
                            append(Environment.DIRECTORY_DOWNLOADS)
                            append("/GalaxySSI/")
                            append(folder)
                            if (relativeDirectory.isNotBlank()) {
                                append("/")
                                append(relativeDirectory)
                            }
                        }
                        val destination = context.contentResolver.insert(
                            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                            ContentValues().apply {
                                put(MediaStore.Downloads.DISPLAY_NAME, displayName)
                                put(
                                    MediaStore.Downloads.MIME_TYPE,
                                    URLConnection.guessContentTypeFromName(displayName)
                                        ?: "application/octet-stream"
                                )
                                put(MediaStore.Downloads.RELATIVE_PATH, relativePath)
                                put(MediaStore.Downloads.IS_PENDING, 1)
                            }
                        ) ?: error("Could not create extracted file")
                        created += destination
                        context.contentResolver.openOutputStream(destination, "w")?.use { output ->
                            val buffer = ByteArray(64 * 1024)
                            while (true) {
                                val count = archive.read(buffer)
                                if (count < 0) break
                                extracted += count
                                require(extracted <= MAX_EXTRACTED_BYTES) { "Archive expands beyond the safety limit" }
                                output.write(buffer, 0, count)
                            }
                        } ?: error("Could not write extracted file")
                        context.contentResolver.update(
                            destination,
                            ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
                            null,
                            null
                        )
                    }
                    archive.closeEntry()
                }
            }
        } catch (failure: Throwable) {
            created.forEach { context.contentResolver.delete(it, null, null) }
            throw failure
        }
        "${Environment.DIRECTORY_DOWNLOADS}/GalaxySSI/$folder"
    }

    fun compressToDownloads(context: Context, source: File): Result<String> = runCatching {
        require(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
        val zipName = "${source.nameWithoutExtension.ifBlank { source.name }}.zip"
        val destination = context.contentResolver.insert(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, zipName)
                put(MediaStore.Downloads.MIME_TYPE, "application/zip")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/GalaxySSI")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
        ) ?: error("Could not create ZIP file")
        try {
            context.contentResolver.openOutputStream(destination, "w")?.use { output ->
                ZipOutputStream(output.buffered()).use { archive ->
                    archive.putNextEntry(ZipEntry(safeSegment(source.name)))
                    source.inputStream().buffered().use { it.copyTo(archive) }
                    archive.closeEntry()
                }
            } ?: error("Could not write ZIP file")
            context.contentResolver.update(
                destination,
                ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
                null,
                null
            )
        } catch (failure: Throwable) {
            context.contentResolver.delete(destination, null, null)
            throw failure
        }
        "${Environment.DIRECTORY_DOWNLOADS}/GalaxySSI/$zipName"
    }

    private fun safeArchiveParts(entry: ZipEntry): List<String> {
        val normalized = entry.name.replace('\\', '/')
        require(!normalized.startsWith("/") && !Regex("^[A-Za-z]:").containsMatchIn(normalized))
        val parts = normalized.split('/').filter(String::isNotBlank)
        require(parts.isNotEmpty() && parts.none { it in setOf(".", "..") })
        return parts.map(::safeSegment)
    }

    private fun safeSegment(value: String): String =
        value.replace(Regex("[\\u0000-\\u001f<>:\"/\\\\|?*]"), "_")
            .trim()
            .take(120)
            .ifBlank { "file" }

    private fun humanSize(bytes: Long): String = when {
        bytes < 1024L -> "$bytes B"
        bytes < 1024L * 1024L -> String.format(Locale.ROOT, "%.1f KB", bytes / 1024.0)
        else -> String.format(Locale.ROOT, "%.1f MB", bytes / (1024.0 * 1024.0))
    }
}
