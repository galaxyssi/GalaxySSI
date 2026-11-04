package com.galaxyssi.chat

import java.io.FilterOutputStream
import java.io.OutputStream
import java.nio.file.Files
import java.security.DigestOutputStream
import java.security.MessageDigest
import java.util.concurrent.CancellationException
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

internal enum class HealthOriginalArchiveOutcome { COMPLETE, FAILED, RETRY }
internal object HealthOriginalArchive {
    private class Borrowed(output: OutputStream) : FilterOutputStream(output) {
        override fun write(bytes: ByteArray, offset: Int, length: Int) = out.write(bytes, offset, length)
        override fun close() = flush()
    }
    private class Counted(output: OutputStream) : FilterOutputStream(output) {
        var bytes = 0L
        override fun write(value: Int) { out.write(value); bytes++ }
        override fun write(buffer: ByteArray, offset: Int, length: Int) { out.write(buffer, offset, length); bytes += length }
    }
    fun generate(originals: HealthOriginalStore, library: HealthOriginalLibraryStore, id: String, dispatch: String? = null, stopped: () -> Boolean = { false }): HealthOriginalArchiveOutcome {
        val (session, key) = library.claim(id, dispatch) ?: return HealthOriginalArchiveOutcome.COMPLETE
        val partial = library.file(session, true); val destination = library.file(session)
        var completed = false
        try {
            check(partial.parentFile!!.isDirectory || partial.parentFile!!.mkdirs())
            library.cleanupAbandoned(session)
            val digest = MessageDigest.getInstance("SHA-256"); var size = 0L
            fun checkActive() { if (stopped() || !library.current(id, session.attempt)) throw CancellationException() }
            java.io.FileOutputStream(partial).use { raw ->
                library.primitive(key).newEncryptingStream(Borrowed(raw), library.aad(session)).use { encrypted ->
                    val counted = Counted(DigestOutputStream(encrypted, digest))
                    ZipOutputStream(Borrowed(counted), Charsets.UTF_8).use { zip ->
                        var after = ""; var count = 0L
                        do {
                            checkActive(); val page = library.items(id, after)
                            page.take(30).forEach { original ->
                                checkActive()
                                if (originals.original(original.id) != original) throw HealthImportFailure("original_changed")
                                if (!originals.present(original)) throw HealthImportFailure("original_missing")
                                zip.putNextEntry(ZipEntry(HealthOriginalArchiveNames.entry(original)).apply { time = original.importedAt })
                                originals.copyVerified(original, zip, ::checkActive); zip.closeEntry()
                                count++; library.advance(session, count)
                            }
                            after = if (page.size > 30) page[29].id else ""
                        } while (after.isNotEmpty())
                        check(count == session.count) { "Export manifest count changed" }
                        zip.putNextEntry(ZipEntry("manifest.ndjson").apply { time = session.createdAt })
                        fun line(value: org.json.JSONObject) {
                            val bytes = (value.toString() + "\n").toByteArray(Charsets.UTF_8)
                            try { zip.write(bytes) } finally { bytes.fill(0) }
                        }
                        line(org.json.JSONObject().put("format", "galaxyssi-originals").put("version", 1).put("created", session.createdAt)
                            .put("original_count", session.count).put("contains_measurements", false))
                        do {
                            checkActive(); val page = library.items(id, after)
                            page.take(30).forEach { original -> line(org.json.JSONObject().put("id", original.id).put("name", original.name).put("mime", original.mime)
                                .put("bytes", original.size).put("sha256", original.sha256).put("imported_at", original.importedAt).put("source", original.source)
                                .put("entry", HealthOriginalArchiveNames.entry(original))) }
                            after = if (page.size > 30) page[29].id else ""
                        } while (after.isNotEmpty())
                        zip.closeEntry()
                    }
                    size = counted.bytes
                }
                raw.fd.sync()
            }
            checkActive(); Files.move(partial.toPath(), destination.toPath())
            library.generated(session, size, digest.digest().joinToString("") { "%02x".format(it) }); completed = true
            return HealthOriginalArchiveOutcome.COMPLETE
        } catch (failure: CancellationException) {
            if (stopped()) { library.interrupted(session); return HealthOriginalArchiveOutcome.RETRY }
            return HealthOriginalArchiveOutcome.COMPLETE
        } catch (failure: Exception) {
            library.failed(session, (failure as? HealthImportFailure)?.code ?: "archive_failed")
            return HealthOriginalArchiveOutcome.FAILED
        } finally { key.fill(0); partial.delete(); if (!completed) destination.delete() }
    }
    fun save(library: HealthOriginalLibraryStore, session: HealthOriginalExportSession, output: OutputStream, cancelled: () -> Unit = {}): Long {
        val digest = MessageDigest.getInstance("SHA-256"); var count = 0L
        library.input(session).use { input ->
            val buffer = ByteArray(64 * 1024)
            try { while (true) {
                cancelled(); val size = input.read(buffer); if (size < 0) break
                output.write(buffer, 0, size); digest.update(buffer, 0, size); count += size
            } } finally { buffer.fill(0) }
        }
        check(count == session.archiveBytes && digest.digest().joinToString("") { "%02x".format(it) } == session.sha256) { "Export archive integrity check failed" }
        output.flush(); return count
    }
}
