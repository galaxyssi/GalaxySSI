package com.galaxyssi.chat

import com.google.crypto.tink.subtle.AesGcmHkdfStreaming
import java.io.File
import java.io.FilterOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.nio.file.Files
import java.nio.channels.SeekableByteChannel
import java.security.DigestOutputStream
import java.security.MessageDigest
import java.util.UUID

internal data class HealthExportDigest(val bytes: Long, val sha256: String)
/** Shared private artifact boundary; public saving remains a separate explicit operation. */
internal class HealthPrivateExportFile(private val directory: File) {
    fun file(id: String, attempt: String, partial: Boolean = false): File {
        require(UUID.fromString(id).toString() == id && UUID.fromString(attempt).toString() == attempt)
        val root = directory.canonicalFile
        return File(root, "$id-$attempt.${if (partial) "partial" else "enc"}").canonicalFile.also { check(it.parentFile == root) }
    }
    fun cleanup(id: String, attempt: String) {
        val keep = file(id, attempt); val partial = file(id, attempt, true)
        directory.listFiles().orEmpty().filter { it.name.startsWith("$id-") && it != keep && it != partial && it.extension in listOf("enc", "partial") }
            .forEach { check(it.canonicalFile.parentFile == directory.canonicalFile); check(it.delete()) }
    }
    fun write(id: String, attempt: String, key: ByteArray, aad: ByteArray, cancelled: () -> Unit, emit: (OutputStream) -> Unit): HealthExportDigest {
        val partial = file(id, attempt, true); val destination = file(id, attempt)
        check(!destination.exists()); check(partial.parentFile!!.isDirectory || partial.parentFile!!.mkdirs())
        val digest = MessageDigest.getInstance("SHA-256"); var bytes = 0L
        try {
            java.io.FileOutputStream(partial).use { raw ->
                primitive(key).newEncryptingStream(borrowed(raw), aad).use { encrypted ->
                    val counted = object : FilterOutputStream(DigestOutputStream(encrypted, digest)) {
                        override fun write(value: Int) { out.write(value); bytes++ }
                        override fun write(buffer: ByteArray, offset: Int, length: Int) { out.write(buffer, offset, length); bytes += length }
                    }
                    emit(borrowed(counted))
                }
                raw.fd.sync()
            }
            cancelled(); Files.move(partial.toPath(), destination.toPath())
            return HealthExportDigest(bytes, digest.digest().joinToString("") { "%02x".format(it) })
        } finally { partial.delete() }
    }
    fun input(id: String, attempt: String, key: ByteArray, aad: ByteArray): InputStream {
        val aead = primitive(key); val raw = file(id, attempt).inputStream()
        return try { aead.newDecryptingStream(raw, aad) } catch (failure: Throwable) { raw.close(); throw failure }
    }
    fun readChannel(id: String, attempt: String, key: ByteArray, aad: ByteArray): SeekableByteChannel {
        val aead = primitive(key)
        val raw = Files.newByteChannel(file(id, attempt).toPath())
        return try { aead.newSeekableDecryptingChannel(raw, aad) }
        catch (failure: Throwable) { raw.close(); throw failure }
    }
    companion object {
        fun primitive(key: ByteArray) = AesGcmHkdfStreaming(key, "HmacSha256", 32, 64 * 1024, 0)
        fun borrowed(output: OutputStream) = object : FilterOutputStream(output) {
            override fun write(bytes: ByteArray, offset: Int, length: Int) = out.write(bytes, offset, length)
            override fun close() = flush()
        }
        fun copyVerified(input: InputStream, output: OutputStream, expected: HealthExportDigest, cancelled: () -> Unit = {}): Long {
            val digest = MessageDigest.getInstance("SHA-256"); var bytes = 0L
            val buffer = ByteArray(64 * 1024)
            try { input.use { while (true) {
                cancelled(); val n = it.read(buffer); if (n < 0) break
                output.write(buffer, 0, n); digest.update(buffer, 0, n); bytes += n
            } } } finally { buffer.fill(0) }
            check(bytes == expected.bytes && digest.digest().joinToString("") { "%02x".format(it) } == expected.sha256) { "Export integrity check failed" }
            output.flush(); return bytes
        }
    }
}
