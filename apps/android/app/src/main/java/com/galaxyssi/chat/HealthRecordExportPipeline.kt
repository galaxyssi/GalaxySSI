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
            fun source(record: HealthObservation): HealthExportSourceStatus {
                val evidence = record.draft.evidence ?: return HealthExportSourceStatus.NONE
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
                val values = page.records.filter(session.scope::matches).map { record -> checkActive(); record to source(record) }
                checkActive(); exports.append(session, values, page.records.size); cursor = page.next
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
    fun generate(exports: HealthRecordExportStore, id: String, dispatch: String, stopped: () -> Boolean = { false }, sheetRows: Int = 1_048_576): HealthOriginalArchiveOutcome {
        val (session, key) = exports.claimGenerate(id, dispatch) ?: return HealthOriginalArchiveOutcome.COMPLETE
        var complete = false
        try {
            fun checkActive() { if (stopped() || !exports.current(session)) throw CancellationException() }
            exports.artifacts.cleanup(id, session.attempt)
            val digest = exports.artifacts.write(id, session.attempt, key, exports.artifactAad(session), ::checkActive) { output ->
                HealthRecordExportFormats.open(session, output, sheetRows).use { sink ->
                    var after = 0L; var count = 0L; var rows = 0L
                    do {
                        checkActive(); val page = exports.items(id, after)
                        page.take(30).forEach { item ->
                            checkActive(); check(item.sequence == count + 1 && session.scope.matches(item.record)) { "Export snapshot sequence mismatch" }
                            sink.append(item); count++; rows += HealthRecordExportRows.count(item.record)
                        }
                        exports.advance(session, count); after = if (page.size > 30) page[29].sequence else 0
                    } while (after > 0)
                    check(count == session.count && rows == session.rows) { "Export snapshot count changed" }
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
    fun save(exports: HealthRecordExportStore, session: HealthRecordExportSession, output: OutputStream, cancelled: () -> Unit = {}) =
        HealthPrivateExportFile.copyVerified(exports.input(session), output, HealthExportDigest(session.artifactBytes, session.sha256), cancelled)
}
