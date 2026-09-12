package com.galaxyssi.chat

import java.io.InputStream
import java.io.OutputStream
import java.security.DigestOutputStream
import java.security.MessageDigest

internal data class ObsidianScannedText(val prefix: String, val hash: String)

/** Hash decoded UTF-8 text, matching the old readText/sha256 semantics, without retaining the file. */
internal object ObsidianBoundedTextScan {
    fun read(input: InputStream, maximumCharacters: Int): ObsidianScannedText {
        require(maximumCharacters >= 0)
        val digest = MessageDigest.getInstance("SHA-256")
        val discard = object : OutputStream() {
            override fun write(value: Int) = Unit
            override fun write(bytes: ByteArray, offset: Int, length: Int) = Unit
        }
        val prefix = StringBuilder(minOf(maximumCharacters, 8192))
        val buffer = CharArray(8192)
        try {
            DigestOutputStream(discard, digest).writer(Charsets.UTF_8).use { writer ->
                input.reader(Charsets.UTF_8).use { reader ->
                    while (true) {
                        check(!Thread.currentThread().isInterrupted)
                        val n = reader.read(buffer)
                        if (n < 0) break
                        val retain = minOf(n, maximumCharacters - prefix.length)
                        if (retain > 0) prefix.append(buffer, 0, retain)
                        writer.write(buffer, 0, n)
                    }
                }
            }
            return ObsidianScannedText(prefix.toString(), ObsidianContentHash.hex(digest.digest()))
        } finally { buffer.fill('\u0000') }
    }
}
