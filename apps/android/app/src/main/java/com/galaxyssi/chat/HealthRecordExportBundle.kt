package com.galaxyssi.chat

import java.io.OutputStream
import java.util.concurrent.CancellationException
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.json.JSONArray
import org.json.JSONObject

/** The archive is a scoped export, not a restorable or password-protected backup. */
internal object HealthRecordExportBundle {
    val discard = object : OutputStream() {
        override fun write(value: Int) = Unit
        override fun write(bytes: ByteArray, offset: Int, length: Int) = Unit
    }

    fun inspect(originals: HealthOriginalStore, scope: HealthRecordExportScope, evidence: HealthEvidence,
                active: () -> Unit): HealthRecordExportAttachment {
        fun result(status: HealthExportSourceStatus, original: HealthOriginal? = null) =
            HealthRecordExportAttachment(evidence.originalId, evidence.sha256, status, original)
        return try {
            val original = originals.original(evidence.originalId) ?: return result(HealthExportSourceStatus.MISSING)
            when {
                !scope.selects(original) -> result(HealthExportSourceStatus.NOT_SELECTED)
                original.reviewOnly || !originals.present(original) -> result(HealthExportSourceStatus.MISSING)
                original.sha256 != evidence.sha256 -> result(HealthExportSourceStatus.HASH_MISMATCH)
                else -> {
                    originals.copyVerified(original, discard, active)
                    result(HealthExportSourceStatus.AVAILABLE, original)
                }
            }
        } catch (failure: CancellationException) { throw failure }
        catch (_: Exception) { result(HealthExportSourceStatus.UNREADABLE) }
    }

    fun write(originals: HealthOriginalStore, exports: HealthRecordExportStore, session: HealthRecordExportSession,
              output: OutputStream, active: () -> Unit, writeRecords: (OutputStream) -> Unit) {
        val recordEntry = "records.${session.scope.format.extension}"
        ZipOutputStream(output, Charsets.UTF_8).use { zip ->
            zip.putNextEntry(ZipEntry(recordEntry).apply { time = session.createdAt })
            writeRecords(zip)
            zip.closeEntry()
            var copied = 0L
            var bytes = 0L
            forEachAttachment(exports, session, active) { item ->
                val original = item.original ?: return@forEachAttachment
                if (!session.scope.selects(original) || originals.original(original.id) != original || !originals.present(original))
                    throw HealthRecordExportFailure("originals_changed")
                zip.putNextEntry(ZipEntry(HealthOriginalArchiveNames.entry(original)).apply { time = original.importedAt })
                bytes = Math.addExact(bytes, originals.copyVerified(original, zip, active))
                zip.closeEntry()
                copied++
            }
            check(copied == session.attachmentAvailable && bytes == session.attachmentBytes)
            zip.putNextEntry(ZipEntry("manifest.ndjson").apply { time = session.createdAt })
            fun line(j: JSONObject) {
                val buffer = (j.toString() + "\n").toByteArray(Charsets.UTF_8)
                try { zip.write(buffer) } finally { buffer.fill(0) }
            }
            line(JSONObject().put("format", "galaxyssi-health-records-and-originals").put("version", 1)
                .put("record_entry", recordEntry).put("scope", session.scope.json()).put("observation_count", session.count)
                .put("attachment_reference_count", session.attachmentCount).put("included_originals", copied)
                .put("unavailable_originals", session.attachmentWarnings).put("original_bytes", bytes)
                .put("prepared_at", session.preparedAt).put("confirmed_at", session.confirmedAt)
                .put("manifest_link_fields", JSONArray(listOf("original_id", "sha256")))
                .put("record_link_fields", JSONArray(if (session.scope.format == HealthRecordExportFormat.JSON)
                    listOf("draft.evidence.original", "draft.evidence.sha256") else listOf("original_id", "original_sha256"))))
            forEachAttachment(exports, session, active) { item ->
                line(JSONObject().put("original_id", item.originalId).put("sha256", item.sha256).put("status", item.status.name).apply {
                    item.original?.let { original ->
                        put("entry", HealthOriginalArchiveNames.entry(original)).put("name", original.name)
                            .put("mime", original.mime).put("bytes", original.size).put("source", original.source)
                            .put("imported_at", original.importedAt)
                    }
                })
            }
            zip.closeEntry()
        }
    }

    private inline fun forEachAttachment(exports: HealthRecordExportStore, session: HealthRecordExportSession,
                                         active: () -> Unit, visit: (HealthRecordExportAttachment) -> Unit) {
        var after = 0L
        var count = 0L
        var warnings = 0L
        do {
            active()
            val page = exports.attachments(session.id, after)
            page.take(30).forEach { item ->
                active()
                check(item.sequence == ++count)
                if (item.status.warning) warnings++
                visit(item)
            }
            after = if (page.size > 30) page[29].sequence else 0
        } while (after > 0)
        check(count == session.attachmentCount && warnings == session.attachmentWarnings)
    }
}
