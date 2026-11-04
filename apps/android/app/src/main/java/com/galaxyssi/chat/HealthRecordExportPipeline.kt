package com.galaxyssi.chat

import java.io.OutputStream
import java.util.concurrent.CancellationException

internal object HealthRecordExportPipeline {
    fun prepare(records: HealthRecordStore, originals: HealthOriginalStore, exports: HealthRecordExportStore, id: String, dispatch: String,
                stopped: () -> Boolean = { false }): HealthOriginalArchiveOutcome {
        val session = exports.claimPrepare(id, dispatch) ?: return HealthOriginalArchiveOutcome.COMPLETE
        fun checkActive() { if (stopped() || !exports.current(session)) throw CancellationException() }
        try {
            val versions = session.scope.metrics.associateWith(records::metricVersion)
            var cursor: HealthPageCursor? = null
            val sourceCache = object : LinkedHashMap<String, Pair<String?, HealthExportSourceStatus>>(128, .75f, true) {
                override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Pair<String?, HealthExportSourceStatus>>?) = size > 128
            }
            val attachmentCache = object : LinkedHashMap<String, HealthExportSourceStatus>(128, .75f, true) {
                override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, HealthExportSourceStatus>?) = size > 128
            }
            fun source(record: HealthObservation, pending: MutableMap<String, HealthRecordExportAttachment>): HealthExportSourceStatus {
                val evidence = record.draft.evidence ?: return HealthExportSourceStatus.NONE
                if (session.scope.bundlesOriginals) {
                    val token = HealthRecordExportAttachment.token(evidence.originalId, evidence.sha256)
                    return attachmentCache.getOrPut(token) {
                        (pending[token] ?: exports.attachmentByToken(id, token) ?: HealthRecordExportBundle.inspect(
                            originals, session.scope, evidence, ::checkActive).also { pending[token] = it }).status
                    }
                }
                val value = sourceCache.getOrPut(evidence.originalId) {
                    try {
                        val original = originals.original(evidence.originalId)
                        original?.sha256 to if (original == null || !originals.present(original)) HealthExportSourceStatus.MISSING else HealthExportSourceStatus.AVAILABLE
                    } catch (failure: CancellationException) { throw failure }
                    catch (_: Exception) { null to HealthExportSourceStatus.UNREADABLE }
                }
                return if (value.second == HealthExportSourceStatus.AVAILABLE && value.first != evidence.sha256) HealthExportSourceStatus.HASH_MISMATCH else value.second
            }
            do {
                checkActive(); val page = records.exportChunk(session.scope, cursor)
                val pending = linkedMapOf<String, HealthRecordExportAttachment>()
                val values = page.records.filter(session.scope::matches).map { record -> checkActive(); record to source(record, pending) }
                checkActive(); exports.append(session, values, page.records.size, pending); cursor = page.next
            } while (cursor != null)
            checkActive()
            if (versions.any { (metric, version) -> records.metricVersion(metric) != version }) throw HealthRecordExportFailure("records_changed")
            exports.review(session); return HealthOriginalArchiveOutcome.COMPLETE
        } catch (_: CancellationException) {
            if (stopped()) { exports.interrupted(session); return HealthOriginalArchiveOutcome.RETRY }
            return HealthOriginalArchiveOutcome.COMPLETE
        } catch (failure: Exception) {
            exports.failed(session, (failure as? HealthRecordExportFailure)?.code ?: "preview_failed"); return HealthOriginalArchiveOutcome.FAILED
        }
    }
    fun generate(exports: HealthRecordExportStore, id: String, dispatch: String, stopped: () -> Boolean = { false },
                 sheetRows: Int = 1_048_576, originals: HealthOriginalStore? = null): HealthOriginalArchiveOutcome {
        val (session, key) = exports.claimGenerate(id, dispatch) ?: return HealthOriginalArchiveOutcome.COMPLETE
        var complete = false
        try {
            fun checkActive() { if (stopped() || !exports.current(session)) throw CancellationException() }
            exports.artifacts.cleanup(id, session.attempt)
            val digest = exports.artifacts.write(id, session.attempt, key, exports.artifactAad(session), ::checkActive) { output ->
                if (session.scope.bundlesOriginals) {
                    HealthRecordExportBundle.write(requireNotNull(originals), exports, session, output, ::checkActive) { records ->
                        writeRecords(exports, session, records, sheetRows, ::checkActive)
                    }
                } else {
                    writeRecords(exports, session, output, sheetRows, ::checkActive)
                }
            }
            exports.generated(session, digest); complete = true; return HealthOriginalArchiveOutcome.COMPLETE
        } catch (_: CancellationException) {
            if (stopped()) { exports.interrupted(session); return HealthOriginalArchiveOutcome.RETRY }
            return HealthOriginalArchiveOutcome.COMPLETE
        } catch (failure: Exception) {
            exports.failed(session, (failure as? HealthRecordExportFailure)?.code ?: "generation_failed"); return HealthOriginalArchiveOutcome.FAILED
        } finally { key.fill(0); if (!complete) exports.artifacts.file(id, session.attempt).delete() }
    }
    private fun writeRecords(exports: HealthRecordExportStore, session: HealthRecordExportSession, output: OutputStream,
                             sheetRows: Int, active: () -> Unit) {
        HealthRecordExportFormats.open(session, output, sheetRows).use { sink ->
            var after = 0L; var count = 0L; var rows = 0L
            do {
                active(); val page = exports.items(session.id, after)
                page.take(30).forEach { item ->
                    active(); check(item.sequence == count + 1 && session.scope.matches(item.record)) { "Export snapshot sequence mismatch" }
                    sink.append(item); count++; rows += HealthRecordExportRows.count(item.record)
                }
                exports.advance(session, count); after = if (page.size > 30) page[29].sequence else 0
            } while (after > 0)
            check(count == session.count && rows == session.rows) { "Export snapshot count changed" }
        }
    }
    fun save(exports: HealthRecordExportStore, session: HealthRecordExportSession, output: OutputStream, cancelled: () -> Unit = {}) =
        HealthPrivateExportFile.copyVerified(exports.input(session), output, HealthExportDigest(session.artifactBytes, session.sha256), cancelled)

    fun saveVerified(exports: HealthRecordExportStore, session: HealthRecordExportSession, open: () -> OutputStream,
                     readBack: () -> java.io.InputStream, removeIncomplete: () -> Unit) {
        var opened = false
        try {
            open().use { opened = true; save(exports, session, it) }
            HealthPrivateExportFile.copyVerified(readBack(), HealthRecordExportBundle.discard,
                HealthExportDigest(session.artifactBytes, session.sha256))
        } catch (failure: Exception) {
            if (opened) runCatching(removeIncomplete)
            throw failure
        }
        exports.saved(session)
    }
}
