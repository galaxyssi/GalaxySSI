package com.galaxyssi.chat

import com.google.crypto.tink.StreamingAead
import com.google.crypto.tink.subtle.AesGcmHkdfStreaming
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.nio.file.Files
import java.security.SecureRandom
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/** Password-portable, segmented AEAD. Callers stage imports until read() validates final EOF. */
internal object StreamingBackupArchive {
    private val MAGIC = byteArrayOf(0x47, 0x53, 0x53, 0x49, 0x42, 0x41, 0x4b, 2)
    private const val SALT_BYTES = 32
    private const val ITERATIONS = 600_000
    private const val SEGMENT_BYTES = 1024 * 1024

    fun isStreaming(file: File): Boolean = file.inputStream().use { input ->
        val header = ByteArray(MAGIC.size)
        var size = 0
        while (size < header.size) {
            val n = input.read(header, size, header.size - size)
            if (n < 0) return@use false
            size += n
        }
        header.contentEquals(MAGIC)
    }

    fun write(file: File, password: CharArray, emit: (BackupRecordStream.Writer) -> Unit): Long {
        require(password.size >= 8) { "Backup password must be at least 8 characters" }
        require(!file.exists()) { "Backup destination already exists" }
        val directory = file.absoluteFile.parentFile!!
        check(directory.isDirectory || directory.mkdirs()) { "Cannot create backup directory" }
        val temporary = File.createTempFile(".backup-", ".partial", directory)
        try {
            val count = FileOutputStream(temporary).use { output ->
                val result = write(output, password, emit)
                output.fd.sync()
                result
            }
            // Android may deny hard links. Default move also rejects an existing destination.
            Files.move(temporary.toPath(), file.toPath())
            return count
        } finally { temporary.delete() }
    }

    internal fun write(output: OutputStream, password: CharArray, emit: (BackupRecordStream.Writer) -> Unit): Long {
        require(password.size >= 8) { "Backup password must be at least 8 characters" }
        val salt = ByteArray(SALT_BYTES).also(SecureRandom()::nextBytes)
        val header = MAGIC + salt
        val aead = primitive(password, salt)
        output.write(header)
        // Finalize authentication without closing the caller's file descriptor before fsync.
        val destination = object : OutputStream() {
            override fun write(value: Int) = output.write(value)
            override fun write(bytes: ByteArray, offset: Int, length: Int) = output.write(bytes, offset, length)
            override fun flush() = output.flush()
            override fun close() = flush()
        }
        return aead.newEncryptingStream(destination, header).use { encrypted ->
            val records = BackupRecordStream.Writer(encrypted)
            emit(records)
            records.finish()
        }
    }

    fun read(file: File, password: CharArray, visit: (String, String, InputStream) -> Unit): Long =
        file.inputStream().use { read(it, password, visit) }

    internal fun read(input: InputStream, password: CharArray, visit: (String, String, InputStream) -> Unit): Long {
        val header = ByteArray(MAGIC.size + SALT_BYTES)
        java.io.DataInputStream(input).readFully(header)
        require(header.copyOfRange(0, MAGIC.size).contentEquals(MAGIC)) { "Unsupported backup format" }
        val aead = primitive(password, header.copyOfRange(MAGIC.size, header.size))
        return aead.newDecryptingStream(input, header).use { BackupRecordStream.read(it, visit) }
    }

    private fun primitive(password: CharArray, salt: ByteArray): StreamingAead {
        val spec = PBEKeySpec(password, salt, ITERATIONS, 256)
        val material = try { SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded }
            finally { spec.clearPassword() }
        return try { AesGcmHkdfStreaming(material, "HmacSha256", 32, SEGMENT_BYTES, 0) }
            finally { material.fill(0) }
    }
}
