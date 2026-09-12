package com.galaxyssi.chat

import java.io.Closeable
import java.io.File
import java.io.OutputStream
import java.security.DigestOutputStream
import java.security.MessageDigest

internal interface ObsidianPreparedContent : Closeable {
    val isBlank: Boolean
    /** The caller owns the destination stream. Returns the digest of the exact written bytes. */
    fun writeTo(output: OutputStream): String
}

internal class ObsidianStringContent(private var text: String) : ObsidianPreparedContent {
    override val isBlank get() = text.isBlank()
    override fun writeTo(output: OutputStream): String = ObsidianContentHash.write(output) {
        val bytes = text.toByteArray(Charsets.UTF_8)
        try { it.write(bytes) } finally { bytes.fill(0) }
    }
    override fun close() { text = "" }
}

internal class ObsidianStagedContent(private val scratch: KnowledgeEncryptedScratch, private val body: File,
    private val header: String) : ObsidianPreparedContent {
    override val isBlank = false
    override fun writeTo(output: OutputStream): String = ObsidianContentHash.write(output) { target ->
        val bytes = header.toByteArray(Charsets.UTF_8)
        val buffer = ByteArray(8192)
        try {
            target.write(bytes)
            scratch.input(body).use { input ->
                while (true) {
                    check(!Thread.currentThread().isInterrupted)
                    val n = input.read(buffer)
                    if (n < 0) break
                    target.write(buffer, 0, n)
                }
            }
            target.write('\n'.code)
        } finally { bytes.fill(0); buffer.fill(0) }
    }
    override fun close() = scratch.close()
}

internal object ObsidianContentHash {
    fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }
    fun write(output: OutputStream, block: (OutputStream) -> Unit): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val target = DigestOutputStream(output, digest)
        block(target)
        target.flush()
        return hex(digest.digest())
    }
}
