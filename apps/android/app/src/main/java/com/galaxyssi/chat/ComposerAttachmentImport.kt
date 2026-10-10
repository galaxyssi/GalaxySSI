package com.galaxyssi.chat

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.time.LocalDate
import java.util.UUID

internal object ComposerAttachmentImport {
    fun retain(context: Context, source: AgentInputAttachment, maxBytes: Long = Long.MAX_VALUE): AgentInputAttachment {
        LocalAttachmentUris.resolve(context, source.uri)?.let { file ->
            require(file.length() <= maxBytes) { "Attachment is too large" }
            return source.copy(sizeBytes = file.length())
        }
        require(source.sizeBytes <= maxBytes) { "Attachment is too large" }
        val extension = source.displayName.substringAfterLast('.', "bin")
            .lowercase().takeIf { it.matches(Regex("[a-z0-9]{1,12}")) } ?: "bin"
        val file = context.contentResolver.openInputStream(source.uri)?.use {
            copyToPrivate(it, context.filesDir, maxBytes, extension)
        } ?: error("Attachment source is unavailable")
        return try {
            source.copy(uri = LocalAttachmentUris.forFile(context, file, source.displayName, source.mimeType),
                sizeBytes = file.length())
        } catch (error: Exception) {
            file.delete()
            throw error
        }
    }

    internal fun copyToPrivate(input: InputStream, filesDir: File, maxBytes: Long,
        extension: String = "bin", date: LocalDate = LocalDate.now()): File {
        require(maxBytes >= 0L)
        require(extension.matches(Regex("[a-z0-9]{1,12}")))
        val directory = File(filesDir,
            "composer-attachments-v1/imported/${date.year}/${date.monthValue.toString().padStart(2, '0')}")
        check(directory.mkdirs() || directory.isDirectory)
        val staged = File.createTempFile(".import-", ".part", directory)
        val target = File(directory, "${UUID.randomUUID()}.$extension")
        val buffer = ByteArray(64 * 1024)
        try {
            FileOutputStream(staged).use { output ->
                var copied = 0L
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    require(count.toLong() <= maxBytes - copied) { "Attachment is too large" }
                    output.write(buffer, 0, count)
                    copied += count
                }
                output.fd.sync()
            }
            java.nio.file.Files.move(staged.toPath(), target.toPath(), java.nio.file.StandardCopyOption.ATOMIC_MOVE)
            return target
        } finally {
            buffer.fill(0)
            staged.delete()
        }
    }
}
