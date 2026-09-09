package com.galaxyssi.chat

import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeUnit

internal class KnowledgeModelDownloadRejected(message: String) : IOException(message)

/** A verified immutable model artifact; interrupted transfers never replace the installed model. */
internal class VerifiedKnowledgeModelFile(private val target: File, private val bytes: Long, private val sha256: String) {
    private val partial = File(target.parentFile, target.name + ".part")
    init { require(bytes > 0 && sha256.matches(Regex("[a-f0-9]{64}"))) }
    fun partialBytes(): Long = partial.length().coerceIn(0, bytes)
    fun installed(): Boolean = target.isFile && target.length() == bytes

    fun importFile(input: InputStream, cancelled: () -> Boolean = { false }, progress: (Long) -> Unit = {}): File {
        target.parentFile?.mkdirs()
        val temporary = File.createTempFile("embedding-import-", ".part", target.parentFile)
        try {
            copy(input, temporary, false, 0, cancelled, progress)
            verify(temporary, cancelled)
            checkCancellation(cancelled)
            install(temporary)
            return target
        } finally { temporary.delete() }
    }

    fun download(urls: List<String>, cancelled: () -> Boolean = { false }, progress: (Long) -> Unit = {}): File {
        require(urls.isNotEmpty())
        target.parentFile?.mkdirs()
        var last: IOException? = null
        for (url in urls) {
            checkCancellation(cancelled)
            try {
                var offset = LocalModelDownloadProtocol.resumeOffset(partial.length(), bytes)
                if (offset != partial.length()) FileOutputStream(partial).close()
                if (offset < bytes) {
                    val request = Request.Builder().url(url).header("Accept-Encoding", "identity").apply {
                        if (offset > 0) header("Range", "bytes=$offset-")
                    }.build()
                    client.newCall(request).execute().use { response ->
                        if (response.code !in listOf(200, 206)) {
                            val message = "Model source HTTP ${response.code}"
                            if (response.code == 408 || response.code == 429 || response.code >= 500) throw IOException(message)
                            throw KnowledgeModelDownloadRejected(message)
                        }
                        val append = try { LocalModelDownloadProtocol.shouldAppend(offset, response.code, response.header("Content-Range")) }
                            catch (error: IllegalArgumentException) { throw IOException("Invalid model Content-Range", error) }
                        if (!append) offset = 0
                        val body = response.body ?: throw IOException("Empty model response")
                        body.byteStream().use { copy(it, partial, append, offset, cancelled, progress) }
                    }
                }
                verify(partial, cancelled)
                checkCancellation(cancelled)
                install(partial)
                return target
            } catch (error: IOException) { last = error }
        }
        throw last ?: IOException("No model source succeeded")
    }

    fun verifyInstalled(cancelled: () -> Boolean = { false }) = verify(target, cancelled)

    private fun copy(input: InputStream, output: File, append: Boolean, offset: Long,
        cancelled: () -> Boolean, progress: (Long) -> Unit) {
        val buffer = ByteArray(64 * 1024)
        var count = offset
        try {
            FileOutputStream(output, append).use { stream ->
                progress(count)
                while (true) {
                    checkCancellation(cancelled)
                    val n = input.read(buffer)
                    if (n < 0) break
                    if (count + n > bytes) throw KnowledgeModelDownloadRejected("Model response exceeds the pinned length")
                    stream.write(buffer, 0, n)
                    count += n
                    progress(count)
                }
                stream.fd.sync()
            }
        } finally { buffer.fill(0) }
    }
    private fun verify(file: File, cancelled: () -> Boolean) {
        checkCancellation(cancelled)
        if (file.length() != bytes) throw IOException("Model download is incomplete")
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            try {
                while (true) {
                    checkCancellation(cancelled)
                    val n = input.read(buffer); if (n < 0) break
                    digest.update(buffer, 0, n)
                }
            } finally { buffer.fill(0) }
        }
        if (digest.digest().joinToString("") { "%02x".format(it) } != sha256) {
            if (file == partial) partial.delete()
            throw KnowledgeModelDownloadRejected("Embedding model checksum mismatch")
        }
    }
    private fun install(file: File) {
        Files.move(file.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    }
    private fun checkCancellation(cancelled: () -> Boolean) {
        if (cancelled() || Thread.currentThread().isInterrupted) throw CancellationException("Model transfer cancelled")
    }
    companion object {
        private val client = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS).followSslRedirects(false).build()
    }
}
