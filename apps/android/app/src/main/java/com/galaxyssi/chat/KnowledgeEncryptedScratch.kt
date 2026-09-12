package com.galaxyssi.chat

import com.google.crypto.tink.StreamingAead
import com.google.crypto.tink.subtle.AesGcmHkdfStreaming
import java.io.Closeable
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.io.RandomAccessFile
import java.nio.channels.OverlappingFileLockException
import java.security.SecureRandom
import java.util.UUID

/** Ephemeral encrypted spill files. The random key is never persisted. */
internal class KnowledgeEncryptedScratch(private val parent: File) : Closeable {
    internal val directory: File
    private val lockFile: RandomAccessFile
    private val lock: java.nio.channels.FileLock
    private var primitive: StreamingAead?
    private var closed = false

    init {
        check(parent.isDirectory || parent.mkdirs()) { "Cannot create encrypted scratch directory" }
        val owned = withParentLock(parent) {
            sweep(parent)
            val folder = File(parent, "job-${UUID.randomUUID()}").apply { check(mkdir()) }
            val handle = RandomAccessFile(File(folder, "lock"), "rw")
            try { Triple(folder, handle, handle.channel.lock()).also { OWNED.add(folder.canonicalPath) } }
            catch (failure: Throwable) { handle.close(); deleteFiles(folder); throw failure }
        }
        directory = owned.first
        lockFile = owned.second
        lock = owned.third
        val key = ByteArray(32).also(SecureRandom()::nextBytes)
        primitive = try { AesGcmHkdfStreaming(key, "HmacSha256", 32, 64 * 1024, 0) }
            catch (failure: Throwable) { releaseFiles(); throw failure }
            finally { key.fill(0) }
    }

    fun create(): File { checkActive(); return File.createTempFile("part-", ".aead", directory) }
    fun output(file: File): OutputStream {
        validate(file)
        val raw = file.outputStream()
        return try { requireNotNull(primitive).newEncryptingStream(raw, aad(file)) }
            catch (failure: Throwable) { raw.close(); throw failure }
    }
    fun input(file: File): InputStream {
        validate(file)
        val raw = file.inputStream()
        return try { requireNotNull(primitive).newDecryptingStream(raw, aad(file)) }
            catch (failure: Throwable) { raw.close(); throw failure }
    }
    fun remove(file: File) { validate(file); check(file.delete()) { "Cannot remove encrypted scratch file" } }
    private fun aad(file: File) = (directory.name + "/" + file.name).toByteArray(Charsets.UTF_8)
    private fun validate(file: File) {
        checkActive()
        require(file.canonicalFile.parentFile == directory.canonicalFile && file.name.startsWith("part-"))
    }
    private fun checkActive() { check(!closed) { "Encrypted scratch is closed" }; check(!Thread.currentThread().isInterrupted) }
    override fun close() {
        if (closed) return
        closed = true
        primitive = null
        val interrupted = Thread.interrupted()
        try { releaseFiles() } finally { if (interrupted) Thread.currentThread().interrupt() }
    }

    private fun releaseFiles() = withParentLock(parent) {
        try { lock.release() } finally {
            lockFile.close()
            OWNED.remove(directory.canonicalPath)
            deleteFiles(directory)
        }
    }

    companion object {
        private val MONITOR = Any()
        private val OWNED = HashSet<String>()
        private val JOB = Regex("job-[0-9a-f-]{36}")
        private fun <T> withParentLock(parent: File, block: () -> T): T = synchronized(MONITOR) {
            RandomAccessFile(File(parent, ".lock"), "rw").use { handle -> handle.channel.lock().use { block() } }
        }
        private fun sweep(parent: File) {
            // A live owner keeps its lock even across processes. Crashed jobs have no usable key.
            java.nio.file.Files.newDirectoryStream(parent.toPath()).use { entries ->
                for (path in entries) {
                    val directory = path.toFile()
                    if (!JOB.matches(directory.name) || !directory.isDirectory || java.nio.file.Files.isSymbolicLink(path)) continue
                    // Opening/closing another descriptor can release this process's POSIX locks.
                    if (directory.canonicalPath in OWNED) continue
                    RandomAccessFile(File(directory, "lock"), "rw").use { handle ->
                        val lease = try { handle.channel.tryLock() } catch (_: OverlappingFileLockException) { null }
                        if (lease != null) {
                            lease.use {
                                java.nio.file.Files.newDirectoryStream(path).use { files ->
                                    for (file in files) if (file.fileName.toString() != "lock") java.nio.file.Files.deleteIfExists(file)
                                }
                            }
                            handle.close()
                            deleteFiles(directory)
                        }
                    }
                }
            }
        }
        private fun deleteFiles(directory: File) {
            java.nio.file.Files.newDirectoryStream(directory.toPath()).use { entries ->
                for (path in entries) java.nio.file.Files.deleteIfExists(path)
            }
            check(directory.delete()) { "Cannot remove encrypted scratch directory" }
        }
    }
}
