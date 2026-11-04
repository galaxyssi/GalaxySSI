package com.galaxyssi.chat

import java.io.OutputStream
import java.util.concurrent.CancellationException
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

internal enum class HealthOriginalArchiveOutcome { COMPLETE, FAILED, RETRY }
internal object HealthOriginalArchive {
    fun generate(originals: HealthOriginalStore, library: HealthOriginalLibraryStore, id: String, dispatch: String? = null, stopped: () -> Boolean = { false }): HealthOriginalArchiveOutcome {
        val (session, key) = library.claim(id, dispatch) ?: return HealthOriginalArchiveOutcome.COMPLETE
        var completed = false
        try {
            library.cleanupAbandoned(session)
            fun checkActive() { if (stopped() || !library.current(id, session.attempt)) throw CancellationException() }
            val digest = library.artifacts.write(id, session.attempt, key, library.aad(session), ::checkActive) { output ->
                    ZipOutputStream(output, Charsets.UTF_8).use { zip ->
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
            }
            library.generated(session, digest.bytes, digest.sha256); completed = true
            return HealthOriginalArchiveOutcome.COMPLETE
        } catch (failure: CancellationException) {
            if (stopped()) { library.interrupted(session); return HealthOriginalArchiveOutcome.RETRY }
            return HealthOriginalArchiveOutcome.COMPLETE
        } catch (failure: Exception) {
            library.failed(session, (failure as? HealthImportFailure)?.code ?: "archive_failed")
            return HealthOriginalArchiveOutcome.FAILED
        } finally { key.fill(0); if (!completed) library.file(session).delete() }
    }
    fun save(library: HealthOriginalLibraryStore, session: HealthOriginalExportSession, output: OutputStream, cancelled: () -> Unit = {}): Long {
        return HealthPrivateExportFile.copyVerified(library.input(session), output, HealthExportDigest(session.archiveBytes, session.sha256), cancelled)
    }
}
