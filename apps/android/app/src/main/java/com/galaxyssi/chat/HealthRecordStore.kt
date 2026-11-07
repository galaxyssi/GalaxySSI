package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.io.Closeable
import org.json.JSONObject

internal data class HealthPageCursor(val measuredAt: Long, val id: String)
internal data class HealthRecordPage(val records: List<HealthObservation>, val next: HealthPageCursor?)
internal sealed class HealthSaveResult {
    data class Saved(val record: HealthObservation) : HealthSaveResult()
    data class Duplicate(val id: String) : HealthSaveResult()
    object Conflict : HealthSaveResult()
}

/** Indexed metadata stays separate from authenticated, individually encrypted measurement payloads. */
internal class HealthRecordStore(context: Context, private val name: String = "health_records_v1.db") : Closeable {
    private val app = context.applicationContext
    private val helper = Database(context.applicationContext, name)
    private val pendingVersions = linkedMapOf<HealthMetric, String>()
    internal val tableDatabase: SQLiteDatabase get() = helper.writableDatabase
    private fun aad(id: String, revision: Int) = "$name|health|$id|$revision".toByteArray(Charsets.UTF_8)
    private fun dedupe(record: HealthObservation) = AgentMemoryIndexKey.token("$name|health-duplicate-v1|${HealthObservationPolicy.duplicateKey(record)}")
    private fun evidenceKey(draft: HealthDraft): String? = draft.evidence?.let { evidenceKey(it, draft.metric) }
    private fun evidenceKey(evidence: HealthEvidence, metric: HealthMetric): String =
        AgentMemoryIndexKey.token("$name|health-evidence-v1|${evidence.originalId}|${evidence.page}|${evidence.candidateId}|${metric.name}")
    private fun ocrLinkKey(evidence: HealthEvidence): String =
        AgentMemoryIndexKey.token("$name|health-ocr-link-v1|${evidence.originalId}|${evidence.page}|${evidence.candidateId}")
    fun recordForEvidence(draft: HealthDraft): HealthObservation? {
        val key = evidenceKey(draft) ?: return null
        return recordForEvidenceKey(key)
    }
    private fun recordForEvidenceKey(key: String): HealthObservation? {
        return helper.readableDatabase.rawQuery("SELECT id,revision,payload,metric,measured_at FROM observations WHERE evidence_key=? AND deleted=0", arrayOf(key))
            .use { if (it.moveToFirst()) decode(it).also { record -> check(evidenceKey(record.draft) == key) { "Health evidence index mismatch" } } else null }
    }
    fun duplicateFor(draft: HealthDraft): String? = recordForEvidence(draft)?.id ?: helper.readableDatabase.rawQuery(
        "SELECT id FROM observations WHERE dedupe=? AND deleted=0", arrayOf(dedupe(HealthObservationPolicy.observation(draft)))
    ).use { if (it.moveToFirst()) it.getString(0) else null }
    private fun encode(record: HealthObservation): ByteArray {
        val bytes = record.json().toString().toByteArray(Charsets.UTF_8)
        return try { AgentStorageCipher.encryptBinary(bytes, aad(record.id, record.revision)) } finally { bytes.fill(0) }
    }
    private fun decode(cursor: Cursor): HealthObservation {
        val id = cursor.getString(0)
        val revision = cursor.getInt(1)
        val bytes = AgentStorageCipher.decryptBinary(cursor.getBlob(2), aad(id, revision))
        return try { HealthObservation.from(JSONObject(String(bytes, Charsets.UTF_8))).also {
            check(it.id == id && it.revision == revision && HealthObservationPolicy.validate(it.draft) == null) { "Invalid health record" }
            if (cursor.getColumnIndex("metric") >= 0) check(it.draft.metric.name == cursor.getString(3) && it.draft.measuredAt == cursor.getLong(4)) {
                "Health index does not match the authenticated record"
            }
        } } finally { bytes.fill(0) }
    }
    fun count(): Long = helper.readableDatabase.rawQuery("SELECT COUNT(*) FROM observations WHERE deleted=0", null)
        .use { it.moveToFirst(); it.getLong(0) }
    fun overviewLatestSelf(metric: HealthMetric?, until: Long): HealthObservation? =
        recentSelf(until, limit = 1, metric = metric).firstOrNull()
    fun latestManualMeasurement(until: Long): Long? =
        recentSelf(until, limit = 1, manual = true).firstOrNull()?.draft?.measuredAt
    fun confirmedImportCount(): Long = helper.readableDatabase.rawQuery(
        "SELECT COUNT(*) FROM observations WHERE original_id IS NOT NULL AND deleted=0", null
    ).use { it.moveToFirst(); it.getLong(0) }
    fun recentSelf(until: Long, limit: Int, metric: HealthMetric? = null, manual: Boolean = false): List<HealthObservation> {
        require(limit in 1..PAGE_SIZE)
        val found = ArrayList<HealthObservation>(limit)
        var after: HealthPageCursor? = null
        while (true) {
            val args = arrayListOf(until.toString())
            val conditions = arrayListOf("deleted=0", "measured_at<=?")
            if (manual) conditions += "original_id IS NULL AND external_key IS NULL"
            metric?.let { conditions += "metric=?"; args += it.name }
            after?.let { conditions += "(measured_at<? OR (measured_at=? AND id<?))"; args += listOf(it.measuredAt.toString(), it.measuredAt.toString(), it.id) }
            val result = helper.readableDatabase.rawQuery("SELECT id,revision,payload,metric,measured_at FROM observations WHERE " +
                conditions.joinToString(" AND ") + " ORDER BY measured_at DESC,id DESC LIMIT 30", args.toTypedArray()).use { cursor ->
                var last: HealthPageCursor? = null
                while (cursor.moveToNext()) {
                    val row = decode(cursor)
                    if (row.profileId == "self" && (!manual || row.source == "manual")) {
                        found += row
                        if (found.size == limit) return found
                    }
                    last = HealthPageCursor(row.draft.measuredAt, row.id)
                }
                last
            }
            if (result == null) return found
            after = result
        }
    }
    fun overviewHasOriginalHistory(id: String): Boolean = helper.readableDatabase.rawQuery(
        "SELECT 1 FROM observations WHERE original_id=? LIMIT 1", arrayOf(id)).use { it.moveToFirst() }
    fun hasSelfOriginalLink(id: String): Boolean {
        val db = helper.readableDatabase
        fun self(query: String) = db.rawQuery(query, arrayOf(id)).use { rows ->
            while (rows.moveToNext()) if (decode(rows).profileId == "self") return@use true
            false
        }
        return self("SELECT id,revision,payload FROM observations WHERE original_id=? AND deleted=0") ||
            self("SELECT o.id,o.revision,o.payload FROM health_source_links l JOIN observations o " +
                "ON o.id=l.record_id AND o.revision=l.revision AND o.measured_at=l.measured_at WHERE l.original_id=? AND o.deleted=0")
    }
    fun overviewHasOcrDraft(job: String): Boolean {
        val prefix = "ocr:$job:"
        return helper.readableDatabase.rawQuery("SELECT 1 FROM drafts WHERE draft_key>=? AND draft_key<? LIMIT 1",
            arrayOf(prefix, prefix + "\uffff")).use { it.moveToFirst() }
    }
    fun metricVersion(metric: HealthMetric): String = helper.readableDatabase.rawQuery("SELECT token FROM health_metric_clocks WHERE metric=?", arrayOf(metric.name))
        .use { if (it.moveToFirst()) it.getString(0) else "" }
    fun metricVersions(metrics: Set<HealthMetric>): Map<HealthMetric, String> {
        require(metrics.isNotEmpty())
        val names = metrics.map { it.name }.toTypedArray()
        val placeholders = names.joinToString(",") { "?" }
        return helper.readableDatabase.rawQuery("SELECT metric,token FROM health_metric_clocks WHERE metric IN ($placeholders)", names).use {
            val result = metrics.associateWith { "" }.toMutableMap()
            while (it.moveToNext()) result[HealthMetric.valueOf(it.getString(0))] = it.getString(1)
            result.toMap()
        }
    }
    private fun changed(metric: HealthMetric) {
        val token = java.util.UUID.randomUUID().toString()
        helper.writableDatabase.insertWithOnConflict("health_metric_clocks", null, ContentValues().apply { put("metric", metric.name); put("token", token) }, SQLiteDatabase.CONFLICT_REPLACE)
        pendingVersions[metric] = token
    }
    @Synchronized internal fun publishCommittedChanges() {
        if (pendingVersions.isEmpty()) return
        runCatching {
            if (helper.writableDatabase.inTransaction()) return
            val versions = pendingVersions.toMap(); pendingVersions.clear()
            if (versions.any { (metric, token) -> metricVersion(metric) == token }) app.contentResolver.notifyChange(changes(app, name), null)
            if (name == "health_records_v1.db" && HealthMetric.SLEEP_DURATION in versions) HealthReminderWork.sleepRecordsChanged(app)
            if (name == "health_records_v1.db") HealthCareWork.changed(app)
        }
    }
    fun revision(id: String, revision: Int): HealthObservation? = helper.readableDatabase.rawQuery(
        "SELECT id,revision,payload FROM revisions WHERE id=? AND revision=? AND deleted=0", arrayOf(id, revision.toString())
    ).use { if (it.moveToFirst()) decode(it) else null }

    fun record(id: String): HealthObservation? = helper.readableDatabase.rawQuery(
        "SELECT id,revision,payload,metric,measured_at FROM observations WHERE id=? AND deleted=0", arrayOf(id)
    ).use { if (it.moveToFirst()) decode(it) else null }

    internal fun backupPage(after: String, signal: android.os.CancellationSignal? = null): List<HealthObservation> =
        helper.readableDatabase.rawQuery(
            "SELECT id,revision,payload,metric,measured_at FROM observations WHERE id>? AND deleted=0 ORDER BY id LIMIT 30",
            arrayOf(after), signal
        ).use { rows -> buildList { while (rows.moveToNext()) add(decode(rows)) } }

    internal fun restoreMatch(candidate: HealthObservation): HealthRestoreMatch {
        val db = helper.readableDatabase
        fun compare(value: HealthObservation): HealthRestoreMatch {
            val equivalent = value.profileId == candidate.profileId && value.source == candidate.source &&
                value.platformOrigin == candidate.platformOrigin && value.deviceReceivedAt == candidate.deviceReceivedAt &&
                value.deviceClock == candidate.deviceClock && value.bluetoothGroup == candidate.bluetoothGroup && value.draft == candidate.draft
            return HealthRestoreMatch(if (equivalent) HealthRestoreKind.DUPLICATE else HealthRestoreKind.CONFLICT, value)
        }
        db.rawQuery("SELECT id,revision,payload,metric,measured_at,deleted FROM observations WHERE id=?",
            arrayOf(candidate.id)).use { row ->
            if (row.moveToFirst()) return if (row.getInt(5) != 0) HealthRestoreMatch(HealthRestoreKind.CONFLICT, deleted = true)
                else compare(decode(row))
        }
        recordForEvidence(candidate.draft)?.let { return compare(it) }
        recordForOcrLink(candidate.draft)?.let { return HealthRestoreMatch(HealthRestoreKind.CONFLICT, record(it.id)) }
        db.rawQuery("SELECT id,revision,payload,metric,measured_at FROM observations WHERE dedupe=? AND deleted=0",
            arrayOf(dedupe(candidate))).use { if (it.moveToFirst()) return compare(decode(it)) }
        if (candidate.source in setOf("health_connect", "bluetooth")) {
            db.rawQuery("SELECT id,revision,payload,metric,measured_at FROM observations WHERE metric=? AND deleted=0 " +
                "AND measured_at=? AND external_key IS NOT NULL", arrayOf(candidate.draft.metric.name, candidate.draft.measuredAt.toString()))
                .use { rows ->
                    while (rows.moveToNext()) {
                        val existing = decode(rows)
                        if (existing.source != candidate.source || existing.bluetoothGroup != candidate.bluetoothGroup) continue
                        if (HealthObservationPolicy.duplicateKey(existing) == HealthObservationPolicy.duplicateKey(candidate))
                            return compare(existing)
                    }
                }
        }
        return HealthRestoreMatch(HealthRestoreKind.NEW)
    }

    internal fun restoreDedupeKey(record: HealthObservation) = dedupe(record)
    internal fun restoreEvidenceKey(record: HealthObservation) = evidenceKey(record.draft)

    internal fun canReplaceRestored(incoming: HealthObservation, existing: HealthObservation): Boolean {
        if (incoming.id != existing.id || incoming.profileId != "self" || existing.profileId != "self" ||
            incoming.draft.metric != existing.draft.metric || existing.source != incoming.source ||
            incoming.source != (incoming.draft.evidence?.kind ?: "manual") ||
            existing.revision !in 1 until Int.MAX_VALUE - 1 || draft(draftKey(existing.editable())) != null) return false
        val evidenceOwner = recordForEvidence(incoming.draft) ?: recordForOcrLink(incoming.draft)
        if (evidenceOwner != null && evidenceOwner.id != existing.id) return false
        return helper.readableDatabase.rawQuery("SELECT 1 FROM observations WHERE dedupe=? AND deleted=0 AND id<>?",
            arrayOf(dedupe(incoming), existing.id)).use { !it.moveToFirst() }
    }

    internal fun replaceRestored(conflict: HealthRestoreConflict) {
        check(helper.writableDatabase.inTransaction())
        val existing = conflict.existing ?: throw HealthRestoreChanged()
        if (!conflict.replaceable || conflict.deleted || record(existing.id) != existing ||
            !canReplaceRestored(conflict.record, existing)) throw HealthRestoreChanged()
        val draft = conflict.record.draft.copy(recordId = existing.id, revision = existing.revision)
        if (saveWithinTransaction(draft) !is HealthSaveResult.Saved) throw HealthRestoreChanged()
    }

    internal fun backupSourceLinks(record: HealthObservation, signal: android.os.CancellationSignal): Sequence<HealthEvidence> = sequence {
        var after = listOf("", "", "")
        while (true) {
            signal.throwIfCanceled()
            val rows = helper.readableDatabase.rawQuery(
                "SELECT original_id,job_id,evidence_key,payload FROM health_source_links WHERE record_id=? AND revision=? AND measured_at=? " +
                    "AND (original_id,job_id,evidence_key)>(?,?,?) ORDER BY original_id,job_id,evidence_key LIMIT 30",
                (listOf(record.id, record.revision.toString(), record.draft.measuredAt.toString()) + after).toTypedArray(), signal
            ).use { cursor -> buildList {
                while (cursor.moveToNext()) {
                    val key = (0..2).map(cursor::getString)
                    add(key to readSourceLink(record, key[0], key[1], key[2], cursor.getBlob(3)))
                }
            } }
            if (rows.isEmpty()) break
            for ((_, evidence) in rows) yield(evidence)
            after = rows.last().first
        }
    }

    internal fun restorePrimarySourceKey(link: HealthRestoreSourceLink): String? =
        link.evidence.takeIf { it.kind == "ocr" }?.let { evidenceKey(it, link.metric) }

    internal fun restoreSourceSlot(link: HealthRestoreSourceLink): String = with(link) {
        if (evidence.kind == "ocr") ocrLinkKey(evidence)
        else AgentMemoryIndexKey.token("$name|health-restore-table-link|$recordId|$revision|${evidence.originalId}|${evidence.jobId}")
    }

    internal fun restoreSourceMatch(link: HealthRestoreSourceLink): HealthRestoreKind = with(link) {
        if (evidence.kind == "ocr") {
            recordForEvidenceKey(requireNotNull(restorePrimarySourceKey(this)))?.let {
                return@with if (it.id == recordId && it.revision == revision) HealthRestoreKind.DUPLICATE else HealthRestoreKind.CONFLICT
            }
            linkedOcrRecord(evidence)?.let {
                return@with if (it.id == recordId && it.revision == revision && it.draft.evidence == evidence)
                    HealthRestoreKind.DUPLICATE else HealthRestoreKind.CONFLICT
            }
        } else {
            helper.readableDatabase.rawQuery(
                "SELECT payload FROM health_source_links WHERE original_id=? AND record_id=? AND revision=? AND job_id=? AND evidence_key=''",
                arrayOf(evidence.originalId, recordId, revision.toString(), evidence.jobId)
            ).use { cursor ->
                if (cursor.moveToFirst()) {
                    val target = requireNotNull(record(recordId))
                    val saved = readSourceLink(target, evidence.originalId, evidence.jobId, "", cursor.getBlob(0))
                    return@with if (saved == evidence) HealthRestoreKind.DUPLICATE else HealthRestoreKind.CONFLICT
                }
            }
        }
        HealthRestoreKind.NEW
    }

    internal fun insertRestoredSource(link: HealthRestoreSourceLink) {
        val record = record(link.recordId) ?: throw HealthRestoreChanged()
        if (record.revision != link.revision || record.draft.metric != link.metric || record.profileId != "self" ||
            record.source != link.evidence.kind || restoreSourceMatch(link) != HealthRestoreKind.NEW ||
            !insertSourceLink(record, link.evidence, if (link.evidence.kind == "ocr") ocrLinkKey(link.evidence) else ""))
            throw HealthRestoreChanged()
    }

    internal fun insertRestored(record: HealthObservation) {
        val db = helper.writableDatabase
        check(db.inTransaction())
        require(record.profileId == "self" && record.revision in 1 until Int.MAX_VALUE && HealthObservationPolicy.validate(record.draft) == null)
        val bytes = encode(record)
        try {
            val external = if (record.source in setOf("health_connect", "bluetooth"))
                AgentMemoryIndexKey.token("$name|health-restore-source-v1|${record.id}") else null
            db.insertOrThrow("observations", null, ContentValues().apply {
                put("id", record.id); put("revision", record.revision); put("metric", record.draft.metric.name)
                put("measured_at", record.draft.measuredAt); put("payload", bytes); put("dedupe", external ?: dedupe(record))
                put("deleted", 0); put("original_id", record.draft.evidence?.originalId)
                put("evidence_key", evidenceKey(record.draft)); put("external_key", external)
                put("bluetooth_group", record.bluetoothGroup.takeIf(String::isNotEmpty))
            })
            db.insertOrThrow("revisions", null, ContentValues().apply {
                put("id", record.id); put("revision", record.revision); put("payload", bytes)
                put("changed_at", record.receivedAt); put("deleted", 0)
            })
            changed(record.draft.metric)
        } finally { bytes.fill(0) }
    }

    fun page(after: HealthPageCursor? = null, metric: HealthMetric? = null, limit: Int = PAGE_SIZE, originalId: String? = null,
             metrics: Set<HealthMetric>? = null): HealthRecordPage {
        require(limit in 1..PAGE_SIZE)
        if (metrics != null && metrics.isEmpty()) return HealthRecordPage(emptyList(), null)
        if (metric != null && metrics != null && metric !in metrics) return HealthRecordPage(emptyList(), null)
        if (metric == null && metrics != null && metrics.size > 1 && metrics.size < HealthMetric.entries.size)
            return catalogPage(after, metrics, limit, originalId)
        val args = mutableListOf<String>()
        val conditions = mutableListOf("deleted=0")
        val selectedMetric = metric ?: metrics?.singleOrNull()
        if (selectedMetric != null) { conditions += "metric=?"; args += selectedMetric.name }
        if (originalId != null) { conditions += "original_id=?"; args += originalId }
        if (after != null) { conditions += "(measured_at<? OR (measured_at=? AND id<?))"; args += listOf(after.measuredAt.toString(), after.measuredAt.toString(), after.id) }
        val records = helper.readableDatabase.rawQuery("SELECT id,revision,payload,metric,measured_at FROM observations WHERE " +
            conditions.joinToString(" AND ") + " ORDER BY measured_at DESC,id DESC LIMIT ${limit + 1}", args.toTypedArray()).use {
            buildList { while (it.moveToNext()) add(decode(it).also { record ->
                if (originalId != null) check(record.draft.evidence?.originalId == originalId) { "Health original index mismatch" }
                if (metrics != null) check(record.draft.metric in metrics) { "Health catalog index mismatch" }
            }) }
        }
        val visible = records.take(limit)
        val next = if (records.size > limit) visible.last().let { HealthPageCursor(it.draft.measuredAt, it.id) } else null
        return HealthRecordPage(visible, next)
    }

    /** Bound each indexed metric stream before merging IDs; decrypt at most one page plus lookahead. */
    private fun catalogPage(after: HealthPageCursor?, metrics: Set<HealthMetric>, limit: Int, originalId: String?): HealthRecordPage {
        val args = arrayListOf<String>()
        val streams = metrics.sortedBy { it.ordinal }.map { metric ->
            val conditions = mutableListOf("metric=?", "deleted=0"); args += metric.name
            if (originalId != null) { conditions += "original_id=?"; args += originalId }
            if (after != null) {
                conditions += "(measured_at<? OR (measured_at=? AND id<?))"
                args += listOf(after.measuredAt.toString(), after.measuredAt.toString(), after.id)
            }
            "SELECT id,measured_at FROM (SELECT id,measured_at FROM observations WHERE ${conditions.joinToString(" AND ")} " +
                "ORDER BY measured_at DESC,id DESC LIMIT ${limit + 1})"
        }
        val candidateIds = "SELECT id FROM (${streams.joinToString(" UNION ALL ")}) ORDER BY measured_at DESC,id DESC LIMIT ${limit + 1}"
        val records = helper.readableDatabase.rawQuery("SELECT id,revision,payload,metric,measured_at FROM observations WHERE id IN ($candidateIds) " +
            "ORDER BY measured_at DESC,id DESC LIMIT ${limit + 1}", args.toTypedArray()).use { cursor -> buildList {
                while (cursor.moveToNext()) add(decode(cursor).also { record ->
                    check(record.draft.metric in metrics) { "Health catalog index mismatch" }
                    if (originalId != null) check(record.draft.evidence?.originalId == originalId) { "Health original index mismatch" }
                })
            } }
        val visible = records.take(limit)
        return HealthRecordPage(visible, if (records.size > limit) visible.last().let { HealthPageCursor(it.draft.measuredAt, it.id) } else null)
    }

    fun trendChunk(spec: HealthTrendSpec, after: HealthPageCursor? = null, signal: android.os.CancellationSignal? = null): HealthRecordPage =
        trendChunk(spec, after, signal, platformCandidates = spec.source.platformOrigin.isNotEmpty())

    private fun trendChunk(spec: HealthTrendSpec, after: HealthPageCursor?, signal: android.os.CancellationSignal?,
                           platformCandidates: Boolean): HealthRecordPage {
        val conditions = arrayListOf("deleted=0", "metric=?", "measured_at>=?", "measured_at<?")
        val args = arrayListOf(spec.metric.name, spec.from.toString(), spec.until.toString())
        if (spec.source.originalId.isNotBlank()) { conditions += "original_id=?"; args += spec.source.originalId }
        if (spec.source.manualOnly) conditions += "original_id IS NULL AND external_key IS NULL"
        if (spec.source.bluetoothGroup.isNotEmpty()) { conditions += "bluetooth_group=?"; args += spec.source.bluetoothGroup }
        if (platformCandidates) conditions += "external_key IS NOT NULL AND bluetooth_group IS NULL"
        if (after != null) { conditions += "(measured_at<? OR (measured_at=? AND id<?))"; args += listOf(after.measuredAt.toString(), after.measuredAt.toString(), after.id) }
        val rows = helper.readableDatabase.rawQuery("SELECT id,revision,payload,metric,measured_at FROM observations WHERE ${conditions.joinToString(" AND ")} " +
            "ORDER BY measured_at DESC,id DESC LIMIT ${PAGE_SIZE + 1}", args.toTypedArray(), signal).use { cursor -> buildList {
                while (cursor.moveToNext()) add(decode(cursor).also { record ->
                    check(record.draft.metric == spec.metric && record.draft.measuredAt >= spec.from && record.draft.measuredAt < spec.until)
                    if (spec.source.originalId.isNotBlank()) check(record.draft.evidence?.originalId == spec.source.originalId) { "Health trend original mismatch" }
                    if (spec.source.bluetoothGroup.isNotEmpty()) check(spec.source.accepts(record)) { "Health trend device mismatch" }
                })
            } }
        val visible = rows.take(PAGE_SIZE)
        return HealthRecordPage(visible, if (rows.size > PAGE_SIZE) visible.last().let { HealthPageCursor(it.draft.measuredAt, it.id) } else null)
    }
    fun exportChunk(scope: HealthRecordExportScope, after: HealthPageCursor? = null, signal: android.os.CancellationSignal? = null): HealthRecordPage {
        if (scope.originalId.isNotEmpty()) return originalPage(scope.originalId, after, scope, signal)
        val args = arrayListOf<String>()
        fun conditions(metric: HealthMetric?): String {
            val terms = arrayListOf("deleted=0", "measured_at>=?", "measured_at<?"); args += listOf(scope.from.toString(), scope.until.toString())
            metric?.let { terms += "metric=?"; args += it.name }
            after?.let { terms += "(measured_at<? OR (measured_at=? AND id<?))"; args += listOf(it.measuredAt.toString(), it.measuredAt.toString(), it.id) }
            return terms.joinToString(" AND ")
        }
        val query = if (scope.metrics.size == HealthMetric.entries.size) {
            "SELECT id,revision,payload,metric,measured_at FROM observations WHERE ${conditions(null)} ORDER BY measured_at DESC,id DESC LIMIT 31"
        } else {
            val parts = scope.metrics.sortedBy { it.ordinal }.map { metric -> "SELECT id,measured_at FROM (SELECT id,measured_at FROM observations WHERE ${conditions(metric)} ORDER BY measured_at DESC,id DESC LIMIT 31)" }
            "SELECT id,revision,payload,metric,measured_at FROM observations WHERE id IN (SELECT id FROM (${parts.joinToString(" UNION ALL ")}) ORDER BY measured_at DESC,id DESC LIMIT 31) ORDER BY measured_at DESC,id DESC LIMIT 31"
        }
        val rows = helper.readableDatabase.rawQuery(query, args.toTypedArray(), signal).use { cursor -> buildList {
            while (cursor.moveToNext()) add(decode(cursor).also {
                check(it.draft.metric in scope.metrics && it.draft.measuredAt >= scope.from && it.draft.measuredAt < scope.until)
            })
        } }
        val visible = rows.take(PAGE_SIZE)
        return HealthRecordPage(visible, if (rows.size > PAGE_SIZE) visible.last().let { HealthPageCursor(it.draft.measuredAt, it.id) } else null)
    }

    /** The original-scoped view projects the selected evidence without changing the stored record. */
    fun originalPage(originalId: String, after: HealthPageCursor? = null, scope: HealthRecordExportScope? = null,
                     signal: android.os.CancellationSignal? = null, pageSize: Int = PAGE_SIZE): HealthRecordPage {
        require(HealthProfilePolicy.uuid(originalId) && (scope == null || scope.originalId == originalId))
        require(pageSize in 1..PAGE_SIZE)
        val args = arrayListOf<String>()
        fun scoped(time: String = "o.measured_at", id: String = "o.id"): String {
            val conditions = arrayListOf("o.deleted=0")
            if (scope != null) {
                conditions += "$time>=? AND $time<?"
                args += listOf(scope.from.toString(), scope.until.toString())
                conditions += "o.metric IN (${scope.metrics.joinToString(",") { "?" }})"
                args += scope.metrics.map { it.name }
            }
            if (after != null) {
                conditions += "($time,$id)<(?,?)"
                args += listOf(after.measuredAt.toString(), after.id)
            }
            return conditions.joinToString(" AND ")
        }
        args += originalId
        val limit = pageSize + 1
        val primary = "SELECT o.id,o.measured_at FROM observations o WHERE o.original_id=? AND ${scoped()} " +
            "ORDER BY o.measured_at DESC,o.id DESC LIMIT $limit"
        args += originalId
        val secondary = "SELECT DISTINCT l.record_id AS id,l.measured_at FROM health_source_links l JOIN observations o " +
            "ON o.id=l.record_id AND o.revision=l.revision AND o.measured_at=l.measured_at " +
            "WHERE l.original_id=? AND ${scoped("l.measured_at", "l.record_id")} " +
            "ORDER BY l.measured_at DESC,l.record_id DESC LIMIT $limit"
        val database = helper.readableDatabase
        val rows = database.rawQuery("SELECT o.id,o.revision,o.payload,o.metric,o.measured_at,e.job_id,e.payload,e.evidence_key FROM observations o JOIN " +
            "(SELECT id FROM (SELECT * FROM ($primary) UNION SELECT * FROM ($secondary)) " +
            "ORDER BY measured_at DESC,id DESC LIMIT $limit) candidates " +
            "ON o.id=candidates.id LEFT JOIN health_source_links e ON e.rowid=(" +
            "SELECT l.rowid FROM health_source_links l WHERE l.original_id=? AND l.record_id=o.id " +
            "AND l.revision=o.revision AND l.measured_at=o.measured_at ORDER BY l.job_id,l.evidence_key LIMIT 1) " +
            "ORDER BY o.measured_at DESC,o.id DESC", (args + originalId).toTypedArray(), signal).use { cursor -> buildList {
            while (cursor.moveToNext()) {
                signal?.throwIfCanceled()
                val record = decode(cursor)
                val view = if (record.draft.evidence?.originalId == originalId) record else {
                    check(!cursor.isNull(5) && !cursor.isNull(6)) { "Health source link missing" }
                    val evidence = readSourceLink(record, originalId, cursor.getString(5), cursor.getString(7), cursor.getBlob(6))
                    record.copy(draft = record.draft.copy(evidence = evidence))
                }
                check(view.draft.evidence?.originalId == originalId)
                check(scope == null || view.draft.metric in scope.metrics && view.draft.measuredAt in scope.from until scope.until)
                add(view)
            }
        } }
        val visible = rows.take(pageSize)
        return HealthRecordPage(visible, if (rows.size > pageSize) visible.last().let { HealthPageCursor(it.draft.measuredAt, it.id) } else null)
    }

    private fun sourceLinkAad(record: HealthObservation, originalId: String, jobId: String, key: String): ByteArray {
        val address = "${record.id}|${record.revision}|$originalId|$jobId"
        return (if (key.isEmpty()) "$name|health-table-source|$address"
            else "$name|health-ocr-source|$address|$key").toByteArray(Charsets.UTF_8)
    }

    private fun readSourceLink(record: HealthObservation, originalId: String, jobId: String, key: String, payload: ByteArray): HealthEvidence {
        val plain = AgentStorageCipher.decryptBinary(payload, sourceLinkAad(record, originalId, jobId, key))
        try {
            return HealthEvidence.from(JSONObject(String(plain, Charsets.UTF_8))).also { evidence ->
                check(evidence.originalId == originalId && evidence.jobId == jobId && evidence.valid() && evidence.confirmed)
                check(if (key.isEmpty()) evidence.kind == "table" else evidence.kind == "ocr" && ocrLinkKey(evidence) == key)
            }
        } finally { plain.fill(0) }
    }

    private fun recordForOcrLink(draft: HealthDraft): HealthObservation? {
        val source = draft.evidence?.takeIf { it.kind == "ocr" } ?: return null
        return linkedOcrRecord(source)
    }

    private fun linkedOcrRecord(source: HealthEvidence): HealthObservation? {
        val originalId = source.originalId
        val key = ocrLinkKey(source)
        return helper.readableDatabase.rawQuery(
            "SELECT o.id,o.revision,o.payload,o.metric,o.measured_at,l.job_id,l.payload FROM health_source_links l JOIN observations o " +
                "ON o.id=l.record_id AND o.revision=l.revision AND o.measured_at=l.measured_at " +
                "WHERE l.evidence_key=? AND l.evidence_key<>'' AND l.original_id=? AND o.deleted=0 LIMIT 1", arrayOf(key, originalId)
        ).use { cursor ->
            if (!cursor.moveToFirst()) null else {
                val record = decode(cursor)
                val evidence = readSourceLink(record, originalId, cursor.getString(5), key, cursor.getBlob(6))
                record.copy(draft = record.draft.copy(evidence = evidence))
            }
        }
    }

    internal fun linkDuplicateTableSource(draft: HealthDraft, existingId: String): Boolean {
        val evidence = draft.evidence?.takeIf { it.confirmed && it.kind == "table" && it.valid() } ?: return false
        val existing = record(existingId) ?: return false
        if (existing.draft.evidence?.originalId == evidence.originalId ||
            HealthObservationPolicy.duplicateKey(existing) != HealthObservationPolicy.duplicateKey(HealthObservationPolicy.observation(draft))) return false
        return insertSourceLink(existing, evidence, "")
    }

    private fun insertSourceLink(existing: HealthObservation, evidence: HealthEvidence, key: String): Boolean {
        val database = helper.writableDatabase
        check(database.inTransaction())
        val plain = evidence.json().toString().toByteArray(Charsets.UTF_8)
        val encrypted = try { AgentStorageCipher.encryptBinary(plain, sourceLinkAad(existing, evidence.originalId, evidence.jobId, key)) }
        finally { plain.fill(0) }
        val inserted = try { database.insertWithOnConflict("health_source_links", null, ContentValues().apply {
            put("original_id", evidence.originalId)
            put("record_id", existing.id)
            put("revision", existing.revision)
            put("job_id", evidence.jobId)
            put("measured_at", existing.draft.measuredAt)
            put("evidence_key", key)
            put("payload", encrypted)
        }, SQLiteDatabase.CONFLICT_IGNORE) != -1L } finally { encrypted.fill(0) }
        if (inserted) changed(existing.draft.metric)
        return inserted
    }

    internal fun removeTableSourceLinks(jobId: String, metric: HealthMetric) {
        val database = helper.writableDatabase
        check(database.inTransaction())
        if (database.delete("health_source_links", "job_id=? AND evidence_key=''", arrayOf(jobId)) > 0) changed(metric)
    }
    fun trendRecords(spec: HealthTrendSpec, after: HealthPageCursor? = null, numericOnly: Boolean = false,
                     cancelled: () -> Unit = {}, signal: android.os.CancellationSignal? = null): HealthRecordPage {
        val rows = arrayListOf<HealthObservation>(); var cursor = after
        do {
            cancelled(); val page = trendChunk(spec, cursor, signal)
            for (record in page.records) { cancelled(); if (spec.matches(record, numericOnly)) rows += record; if (rows.size > PAGE_SIZE) break }
            cursor = page.next
        } while (rows.size <= PAGE_SIZE && cursor != null)
        val visible = rows.take(PAGE_SIZE)
        return HealthRecordPage(visible, if (rows.size > PAGE_SIZE) visible.last().let { HealthPageCursor(it.draft.measuredAt, it.id) } else null)
    }
    fun trendSourceIds(spec: HealthTrendSpec, after: String = "", signal: android.os.CancellationSignal? = null): List<String> = helper.readableDatabase.rawQuery(
        "SELECT DISTINCT original_id FROM observations WHERE deleted=0 AND metric=? AND measured_at>=? AND measured_at<? " +
            "AND original_id IS NOT NULL AND original_id>? ORDER BY original_id LIMIT 31", arrayOf(spec.metric.name, spec.from.toString(), spec.until.toString(), after), signal
    ).use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(0)) } }

    fun trendBluetoothGroups(spec: HealthTrendSpec, after: String = "", signal: android.os.CancellationSignal? = null): List<String> =
        helper.readableDatabase.rawQuery(
            "SELECT DISTINCT bluetooth_group FROM observations WHERE metric=? AND deleted=0 AND bluetooth_group>? " +
                "AND measured_at>=? AND measured_at<? ORDER BY bluetooth_group LIMIT ${PAGE_SIZE + 1}",
            arrayOf(spec.metric.name, after, spec.from.toString(), spec.until.toString()), signal
        ).use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(0).also { check(isHealthBluetoothGroup(it)) }) } }

    fun trendBluetoothLabel(spec: HealthTrendSpec, group: String, signal: android.os.CancellationSignal? = null): String? =
        latestBluetoothRecord(spec, group, signal)?.platformOrigin

    fun latestBluetoothRecord(spec: HealthTrendSpec, group: String, signal: android.os.CancellationSignal? = null): HealthObservation? {
        require(isHealthBluetoothGroup(group))
        return helper.readableDatabase.rawQuery(
            "SELECT id,revision,payload,metric,measured_at FROM observations WHERE metric=? AND deleted=0 AND bluetooth_group=? " +
                "AND measured_at>=? AND measured_at<? ORDER BY measured_at DESC,id DESC LIMIT 1",
            arrayOf(spec.metric.name, group, spec.from.toString(), spec.until.toString()), signal
        ).use { cursor ->
            if (!cursor.moveToFirst()) null else decode(cursor).let {
                check(it.source == "bluetooth" && it.bluetoothGroup == group)
                it
            }
        }
    }

    fun bluetoothHistoryPreview(group: String): HealthBluetoothHistoryPreview {
        require(isHealthBluetoothGroup(group))
        val db = helper.readableDatabase
        db.beginTransactionNonExclusive()
        return try {
            bluetoothHistoryPreview(db, group).also { db.setTransactionSuccessful() }
        } finally { db.endTransaction() }
    }

    private fun bluetoothHistoryPreview(db: SQLiteDatabase, group: String): HealthBluetoothHistoryPreview =
        db.rawQuery("SELECT COUNT(*),MIN(measured_at),MAX(measured_at) FROM observations WHERE $BLUETOOTH_HISTORY_FILTER",
            arrayOf(HealthMetric.BLOOD_PRESSURE.name, group)).use {
            check(it.moveToFirst())
            HealthBluetoothHistoryPreview(group, metricVersion(HealthMetric.BLOOD_PRESSURE), it.getLong(0), it.getLong(1), it.getLong(2))
        }

    @Synchronized fun eraseBluetoothHistory(preview: HealthBluetoothHistoryPreview, ensureActive: () -> Unit = {}): Long {
        require(isHealthBluetoothGroup(preview.group) && preview.count > 0)
        val db = helper.writableDatabase
        val args = arrayOf(HealthMetric.BLOOD_PRESSURE.name, preview.group)
        db.beginTransaction()
        return try {
            if (bluetoothHistoryPreview(db, preview.group) != preview) throw HealthBluetoothHistoryChanged()
            var removed = 0L
            while (removed < preview.count) {
                ensureActive()
                val batch = db.rawQuery("SELECT id,revision,payload,metric,measured_at FROM observations " +
                    "WHERE $BLUETOOTH_HISTORY_FILTER LIMIT $PAGE_SIZE", args).use { rows ->
                    buildList {
                        while (rows.moveToNext()) {
                            val value = decode(rows)
                            check(value.profileId == "self" && value.source == "bluetooth" && value.bluetoothGroup == preview.group)
                            add(value.id)
                        }
                    }
                }
                check(batch.isNotEmpty())
                for (id in batch) eraseStoredMeasurement(db, id)
                removed += batch.size
            }
            ensureActive()
            check(removed == preview.count)
            changed(HealthMetric.BLOOD_PRESSURE)
            db.setTransactionSuccessful()
            removed
        } finally { db.endTransaction(); publishCommittedChanges() }
    }

    private fun eraseStoredMeasurement(db: SQLiteDatabase, id: String) {
        val key = arrayOf(id)
        db.delete("drafts", "draft_key=?", arrayOf("edit:$id"))
        db.delete("health_source_links", "record_id=?", key)
        db.delete("revisions", "id=?", key)
        check(db.delete("observations", "id=?", key) == 1)
    }

    fun measurementHistoryPreview(scope: HealthMeasurementHistoryScope, ensureActive: () -> Unit = {}): HealthMeasurementHistoryPreview {
        val version = metricVersion(scope.metric)
        val preview = scanMeasurementHistory(helper.readableDatabase, scope, version, ensureActive)
        if (metricVersion(scope.metric) != version) throw HealthMeasurementHistoryChanged()
        return preview
    }

    @Synchronized fun eraseMeasurementHistory(preview: HealthMeasurementHistoryPreview, ensureActive: () -> Unit = {}): Long {
        require(preview.count > 0)
        val metric = preview.scope.metric
        val db = helper.writableDatabase
        db.beginTransaction()
        return try {
            if (metricVersion(metric) != preview.version) throw HealthMeasurementHistoryChanged()
            val erased = scanMeasurementHistory(db, preview.scope, preview.version, ensureActive) {
                eraseStoredMeasurement(db, it.id)
            }
            if (erased != preview) throw HealthMeasurementHistoryChanged()
            changed(metric)
            db.setTransactionSuccessful()
            erased.count
        } finally { db.endTransaction(); publishCommittedChanges() }
    }

    private fun scanMeasurementHistory(db: SQLiteDatabase, scope: HealthMeasurementHistoryScope, version: String,
        ensureActive: () -> Unit, consume: (HealthObservation) -> Unit = {}): HealthMeasurementHistoryPreview {
        // Legacy Bluetooth observations can also have external keys without a group. Authenticate before filtering.
        val filter = if (scope.healthConnectOnly) " AND external_key IS NOT NULL AND bluetooth_group IS NULL" else ""
        val counts = mutableMapOf<HealthMeasurementSource, Long>()
        var first = Long.MAX_VALUE
        var last = 0L
        for (deleted in 0..1) {
            var after: HealthPageCursor? = null
            do {
                ensureActive()
                val args = arrayListOf(scope.metric.name, deleted.toString())
                val cursorFilter = after?.let {
                    args += listOf(it.measuredAt.toString(), it.measuredAt.toString(), it.id)
                    " AND (measured_at<? OR (measured_at=? AND id<?))"
                }.orEmpty()
                val page = db.rawQuery("SELECT id,revision,payload,metric,measured_at FROM observations WHERE metric=? AND deleted=? " +
                    "$filter$cursorFilter ORDER BY measured_at DESC,id DESC LIMIT $PAGE_SIZE",
                    args.toTypedArray()).use { rows -> buildList {
                        while (rows.moveToNext()) { ensureActive(); add(decode(rows)) }
                    } }
                after = page.lastOrNull()?.let { HealthPageCursor(it.draft.measuredAt, it.id) }
                for (row in page) {
                    if (row.profileId != "self" || scope.healthConnectOnly && row.source != "health_connect") continue
                    val source = HealthMeasurementSource.from(row.source)
                    counts[source] = (counts[source] ?: 0L) + 1
                    first = minOf(first, row.draft.measuredAt)
                    last = maxOf(last, row.draft.measuredAt)
                    consume(row)
                }
            } while (page.size == PAGE_SIZE)
        }
        ensureActive()
        return HealthMeasurementHistoryPreview(scope, version, counts.toMap(), if (counts.isEmpty()) 0L else first, last)
    }

    fun trendPlatformOrigins(spec: HealthTrendSpec, after: String = "", signal: android.os.CancellationSignal? = null): List<String> {
        val scope = spec.copy(source = HealthTrendSource())
        val origins = java.util.TreeSet<String>()
        var cursor: HealthPageCursor? = null
        do {
            signal?.throwIfCanceled()
            val page = trendChunk(scope, cursor, signal, platformCandidates = true)
            for (record in page.records) {
                if (record.source != "health_connect" || record.platformOrigin <= after ||
                    !validHealthTrendPlatformOrigin(record.platformOrigin)) continue
                origins.add(record.platformOrigin)
                if (origins.size > PAGE_SIZE + 1) origins.pollLast()
            }
            cursor = page.next
        } while (cursor != null)
        return origins.toList()
    }

    @Synchronized fun save(draft: HealthDraft): HealthSaveResult {
        val database = helper.writableDatabase
        database.beginTransaction()
        return try { saveWithinTransaction(draft).also { database.setTransactionSuccessful() } }
        finally { database.endTransaction(); publishCommittedChanges() }
    }
    @Synchronized fun prepareOcrReviewPage(suggestions: List<HealthDraft>): List<HealthOcrReviewRow> {
        require(suggestions.size <= HEALTH_OCR_REVIEW_PAGE_SIZE)
        if (suggestions.isEmpty()) return emptyList()
        val db = helper.writableDatabase
        db.beginTransaction()
        return try {
            suggestions.map { suggestion ->
                require(suggestion.evidence?.kind == "ocr" && suggestion.recordId.isBlank() && suggestion.revision == 0)
                val primary = recordForEvidence(suggestion)
                val linked = if (primary == null) recordForOcrLink(suggestion) else null
                val saved = primary ?: linked
                if (saved != null) HealthOcrReviewRow(saved.draft, "", saved, linked = linked != null)
                else {
                    val key = draftKey(suggestion)
                    val row = reviewDraft(key) ?: run {
                        saveDraft(suggestion)
                        requireNotNull(reviewDraft(key))
                    }
                    val target = if (row.selection == null) null else duplicateFor(row.draft)?.let(::record)
                    row.copy(link = target?.let { HealthOcrLinkTarget(it.id, it.revision) })
                }
            }.also { db.setTransactionSuccessful() }
        } finally { db.endTransaction() }
    }

    @Synchronized fun saveOcrReviewBatch(jobId: String, originalId: String, items: List<HealthOcrReviewSelection>): HealthOcrBatchResult {
        require(items.isNotEmpty() && items.size <= HEALTH_OCR_REVIEW_SELECTION_LIMIT && items.distinctBy { it.key }.size == items.size)
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            val validated = items.map { item ->
                val draft = reviewDraft(item.key)?.takeIf { it.selection == item.copy(link = null) }?.draft
                    ?: return HealthOcrBatchResult.Stale(item.key)
                val evidence = draft.evidence
                if (evidence?.kind != "ocr" || evidence.jobId != jobId || evidence.originalId != originalId ||
                    draft.recordId.isNotBlank() || draft.revision != 0) return HealthOcrBatchResult.Stale(item.key)
                draft
            }
            var linked = 0
            validated.forEachIndexed { index, draft ->
                val item = items[index]
                val target = item.link
                if (target == null) {
                    when (saveWithinTransaction(draft)) {
                        is HealthSaveResult.Duplicate -> return HealthOcrBatchResult.Duplicate(item.key)
                        HealthSaveResult.Conflict -> return HealthOcrBatchResult.Stale(item.key)
                        is HealthSaveResult.Saved -> Unit
                    }
                } else {
                    val existing = record(target.id)
                    if (existing == null || existing.revision != target.revision ||
                        dedupe(existing) != dedupe(HealthObservationPolicy.observation(draft))) return HealthOcrBatchResult.Stale(item.key)
                    val evidence = requireNotNull(draft.evidence)
                    if (recordForEvidence(draft) != null || recordForOcrLink(draft) != null ||
                        !insertSourceLink(existing, evidence, ocrLinkKey(evidence)))
                        return HealthOcrBatchResult.Duplicate(item.key)
                    clearDraft(item.key)
                    linked++
                }
            }
            db.setTransactionSuccessful()
            return HealthOcrBatchResult.Saved(items.size - linked, linked)
        } finally { db.endTransaction(); publishCommittedChanges() }
    }
    @Synchronized fun importHealthConnect(rows: List<HealthConnectMeasurement>, ensureActive: () -> Unit): Int {
        require(rows.size <= HealthConnectImport.MAX_ROWS)
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            val inserted = insertHealthConnectRows(rows, ensureActive)
            ensureActive()
            db.setTransactionSuccessful()
            return inserted
        } finally { db.endTransaction(); publishCommittedChanges() }
    }

    private fun insertHealthConnectRows(rows: List<HealthConnectMeasurement>, ensureActive: () -> Unit): Int {
        val db = helper.writableDatabase
        var inserted = 0
        for (row in rows) {
            ensureActive()
            val key = AgentMemoryIndexKey.token("$name|health-connect-v1|${row.draft.metric.name}|${row.origin}|${row.id}")
            if (db.rawQuery("SELECT 1 FROM observations WHERE external_key=?", arrayOf(key)).use { it.moveToFirst() }) continue
            if (saveWithinTransaction(row.draft, key, HealthLinkedSource("health_connect", row.origin)) is HealthSaveResult.Saved) inserted++
        }
        return inserted
    }

    fun healthSyncCheckpoint(scope: HealthConnectScope): HealthSyncCheckpoint = readHealthSync("connect:${scope.name}")?.let {
        HealthSyncCheckpoint.from(it).also { mark -> check(mark.scope == scope) }
    } ?: HealthSyncCheckpoint(scope)

    private fun incidentKey(scope: HealthConnectScope) = "connect-incident:${scope.name}"

    internal fun storedSyncIncident(scope: HealthConnectScope): HealthSyncIncident? =
        readHealthSync(incidentKey(scope))?.let { HealthSyncIncident.from(it).also { incident -> check(incident.scope == scope) } }

    fun healthSyncIncident(scope: HealthConnectScope): HealthSyncIncident? =
        storedSyncIncident(scope) ?: HealthSyncIncident.fromCheckpoint(healthSyncCheckpoint(scope))

    fun startHealthSyncAttempt(mark: HealthSyncCheckpoint) {
        require(mark.outcome == HealthSyncOutcome.RUNNING)
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            val key = incidentKey(mark.scope)
            if (readHealthSync(key) == null) HealthSyncIncident.fromCheckpoint(healthSyncCheckpoint(mark.scope))?.let {
                writeHealthSync(key, it.json())
            }
            writeHealthSync("connect:${mark.scope.name}", mark.json())
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }

    fun saveHealthSyncCheckpoint(mark: HealthSyncCheckpoint, systemDelivery: Boolean? = null) {
        val key = "connect:${mark.scope.name}"
        val succeeded = mark.outcome == HealthSyncOutcome.UPDATED || mark.outcome == HealthSyncOutcome.NO_NEW
        if (!succeeded && !mark.outcome.isSyncFailure) {
            writeHealthSync(key, mark.json())
            return
        }
        val delivery = if (mark.outcome.isSyncFailure &&
            (systemDelivery ?: (name == DEFAULT_DB && HealthReminderWork.syncDeliveryEnabled(app)))) HealthReminderDelivery.WAITING
        else HealthReminderDelivery.IN_APP_ONLY
        val db = helper.writableDatabase
        var changed = false
        var reconcileNotices = false
        db.beginTransaction()
        try {
            val prior = healthSyncIncident(mark.scope)
            val next = if (succeeded) prior?.let {
                if (it.resolvedAt == 0L && mark.lastSuccess > 0) it.copy(resolvedAt = mark.lastSuccess, delivery = it.handledDelivery) else it
            } else HealthSyncIncident.fromCheckpoint(mark)?.let {
                if (prior != null && prior.resolvedAt == 0L) prior.copy(outcome = it.outcome, failedAt = it.failedAt,
                    lastSuccess = it.lastSuccess) else it.copy(id = java.util.UUID.randomUUID().toString(), delivery = delivery)
            } ?: prior
            writeHealthSync(key, mark.json())
            if (next != null && next != prior) {
                writeHealthSync(incidentKey(mark.scope), next.json())
                changed = true
                reconcileNotices = (next.id != prior?.id && next.delivery == HealthReminderDelivery.WAITING) ||
                    (next.handled && prior != null && !prior.handled && prior.delivery != HealthReminderDelivery.IN_APP_ONLY)
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        if (changed) notifySyncIncidents()
        if (reconcileNotices && name == DEFAULT_DB) HealthReminderWork.sourceRemindersChanged(app)
    }

    fun acknowledgeHealthSyncIncident(expected: HealthSyncIncident, now: Long) {
        require(now > 0)
        val db = helper.writableDatabase
        val reconcileNotices: Boolean
        db.beginTransaction()
        try {
            val current = healthSyncIncident(expected.scope)
            if (current == null || current.copy(delivery = expected.delivery) != expected || current.handled) throw HealthReminderConflict()
            writeHealthSync(incidentKey(expected.scope), current.copy(acknowledgedAt = now, delivery = current.handledDelivery).json())
            reconcileNotices = current.delivery != HealthReminderDelivery.IN_APP_ONLY
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        notifySyncIncidents()
        if (reconcileNotices && name == DEFAULT_DB) HealthReminderWork.sourceRemindersChanged(app)
    }

    fun finishSyncNotice(expected: HealthSyncIncident, delivery: HealthReminderDelivery): Boolean {
        require(delivery != HealthReminderDelivery.WAITING)
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            val current = healthSyncIncident(expected.scope)
            if (current == null || current.id != expected.id || current.handled || current.delivery != HealthReminderDelivery.WAITING) return false
            writeHealthSync(incidentKey(current.scope), current.copy(delivery = delivery).json())
            db.setTransactionSuccessful()
            return true
        } finally { db.endTransaction() }
    }

    private fun notifySyncIncidents() = app.contentResolver.notifyChange(syncIncidentChanges(app, name), null)

    @Synchronized fun saveHealthSyncChunk(mark: HealthSyncCheckpoint, rows: List<HealthConnectMeasurement>, ensureActive: () -> Unit): HealthSyncCheckpoint {
        require(rows.isNotEmpty() && rows.size <= HealthConnectImport.MAX_ROWS)
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            val inserted = insertHealthConnectRows(rows, ensureActive)
            val next = mark.copy(pendingInserts = Math.addExact(mark.pendingInserts, inserted),
                latestMeasurement = maxOf(mark.latestMeasurement, rows.maxOf { it.draft.measuredAt }))
            saveHealthSyncCheckpoint(next)
            ensureActive()
            db.setTransactionSuccessful()
            return next
        } finally { db.endTransaction(); publishCommittedChanges() }
    }

    fun lastBluetoothReceipt(): Long = readHealthSync("bluetooth")?.getLong("received") ?: 0L

    private fun readHealthSync(key: String): JSONObject? = helper.readableDatabase.rawQuery(
        "SELECT payload FROM health_sync_checkpoints WHERE source=?", arrayOf(key)
    ).use {
        if (!it.moveToFirst()) null else {
            val bytes = AgentStorageCipher.decryptBinary(it.getBlob(0), aad("sync:$key", 1))
            try { JSONObject(String(bytes, Charsets.UTF_8)) } finally { bytes.fill(0) }
        }
    }

    private fun writeHealthSync(key: String, json: JSONObject) {
        val bytes = json.toString().toByteArray(Charsets.UTF_8)
        val encrypted = try { AgentStorageCipher.encryptBinary(bytes, aad("sync:$key", 1)) } finally { bytes.fill(0) }
        try {
            check(helper.writableDatabase.insertWithOnConflict("health_sync_checkpoints", null, ContentValues().apply {
                put("source", key); put("payload", encrypted)
            }, SQLiteDatabase.CONFLICT_REPLACE) != -1L)
        } finally { encrypted.fill(0) }
    }

    @Synchronized fun saveBluetooth(receipt: HealthBluetoothReceipt, condition: String, active: () -> Unit): HealthSaveResult {
        val db = helper.writableDatabase
        val key = AgentMemoryIndexKey.token("$name|health-bluetooth-v1|${receipt.deviceToken}|${receipt.eventKey}")
        db.beginTransaction()
        try {
            active()
            val previous = db.rawQuery("SELECT id FROM observations WHERE external_key=?", arrayOf(key))
                .use { if (it.moveToFirst()) it.getString(0) else null }
            val result = if (previous != null) HealthSaveResult.Duplicate(previous)
                else saveWithinTransaction(receipt.draft(condition), key, HealthLinkedSource("bluetooth", receipt.label, receipt.receivedAt,
                    receipt.clockText, AgentMemoryIndexKey.token("health-bluetooth-trend-v1|${receipt.deviceToken}")))
            if (result is HealthSaveResult.Saved && receipt.receivedAt > lastBluetoothReceipt())
                writeHealthSync("bluetooth", JSONObject().put("received", receipt.receivedAt))
            active()
            db.setTransactionSuccessful()
            return result
        } finally { db.endTransaction(); publishCommittedChanges() }
    }

    private data class HealthLinkedSource(val source: String, val origin: String, val receivedAt: Long? = null,
        val clock: String = "", val bluetoothGroup: String = "")

    private fun saveWithinTransaction(draft: HealthDraft, externalKey: String? = null, source: HealthLinkedSource? = null): HealthSaveResult {
        val database = helper.writableDatabase
        val existingPlatform = if (draft.recordId.isBlank()) null else database.rawQuery(
            "SELECT id,revision,payload,external_key FROM observations WHERE id=? AND deleted=0 AND external_key IS NOT NULL",
            arrayOf(draft.recordId)
        ).use { if (it.moveToFirst()) decode(it) to it.getString(3) else null }
        val sourceKey = externalKey ?: existingPlatform?.second
        val normalized = HealthObservationPolicy.observation(draft)
        val record = if (sourceKey != null) {
            if (existingPlatform != null && (draft.metric != existingPlatform.first.draft.metric || draft.evidence != null))
                return HealthSaveResult.Conflict
            val linked = existingPlatform?.first?.let { HealthLinkedSource(it.source, it.platformOrigin, it.deviceReceivedAt, it.deviceClock, it.bluetoothGroup) }
                ?: requireNotNull(source)
            normalized.copy(source = linked.source, platformOrigin = linked.origin, deviceReceivedAt = linked.receivedAt, deviceClock = linked.clock,
                bluetoothGroup = linked.bluetoothGroup)
        } else normalized
        val encrypted = encode(record)
        val duplicateKey = sourceKey ?: dedupe(record)
        return try {
            val previous = database.rawQuery("SELECT revision,metric FROM observations WHERE id=? AND deleted=0", arrayOf(record.id))
                .use { if (it.moveToFirst()) it.getInt(0) to HealthMetric.valueOf(it.getString(1)) else null }
            val existing = previous?.first ?: 0
            if (existing != draft.revision) return HealthSaveResult.Conflict
            val priorEvidence = recordForEvidence(draft) ?: recordForOcrLink(draft)
            if (priorEvidence != null && priorEvidence.id != record.id) return HealthSaveResult.Duplicate(priorEvidence.id)
            val duplicate = database.rawQuery("SELECT id FROM observations WHERE dedupe=? AND deleted=0 AND id<>?",
                arrayOf(duplicateKey, record.id)).use { if (it.moveToFirst()) it.getString(0) else null }
            if (duplicate != null) return HealthSaveResult.Duplicate(duplicate)
            val values = ContentValues().apply {
                put("id", record.id); put("revision", record.revision); put("metric", draft.metric.name)
                put("measured_at", draft.measuredAt); put("payload", encrypted); put("dedupe", duplicateKey)
                put("deleted", 0)
                put("original_id", draft.evidence?.originalId)
                put("evidence_key", evidenceKey(draft))
                put("external_key", sourceKey)
                put("bluetooth_group", record.bluetoothGroup.takeIf(String::isNotEmpty))
            }
            if (existing == 0) database.insertOrThrow("observations", null, values)
            else check(database.update("observations", values, "id=? AND revision=? AND deleted=0", arrayOf(record.id, existing.toString())) == 1)
            database.insertOrThrow("revisions", null, ContentValues().apply {
                put("id", record.id); put("revision", record.revision); put("payload", encrypted)
                put("changed_at", record.receivedAt); put("deleted", 0)
            })
            changed(record.draft.metric); previous?.second?.takeIf { it != record.draft.metric }?.let(::changed)
            if (externalKey == null) database.delete("drafts", "draft_key=?", arrayOf(draftKey(draft)))
            HealthSaveResult.Saved(record)
        } finally { encrypted.fill(0) }
    }

    @Synchronized fun delete(id: String, revision: Int): Boolean {
        val database = helper.writableDatabase
        database.beginTransaction()
        return try {
            val value = record(id) ?: return false
            if (value.revision != revision) return false
            val removed = value.copy(revision = revision + 1, receivedAt = System.currentTimeMillis())
            val encrypted = encode(removed)
            try {
                check(database.update("observations", ContentValues().apply {
                    put("deleted", 1); put("revision", removed.revision); put("payload", encrypted)
                }, "id=? AND revision=?", arrayOf(id, revision.toString())) == 1)
                database.insertOrThrow("revisions", null, ContentValues().apply {
                    put("id", id); put("revision", removed.revision); put("payload", encrypted)
                    put("changed_at", System.currentTimeMillis()); put("deleted", 1)
                })
                changed(value.draft.metric)
                database.delete("drafts", "draft_key=?", arrayOf("edit:$id"))
                database.setTransactionSuccessful()
                true
            } finally { encrypted.fill(0) }
        } finally { database.endTransaction(); publishCommittedChanges() }
    }

    fun canUndoDelete(id: String, revision: Int): Boolean = revision in 2 until Int.MAX_VALUE &&
        helper.readableDatabase.rawQuery("SELECT 1 FROM observations WHERE id=? AND revision=? AND deleted=1",
            arrayOf(id, revision.toString())).use { it.moveToFirst() }

    @Synchronized fun undoDelete(id: String, deletionRevision: Int): Boolean {
        if (deletionRevision !in 2 until Int.MAX_VALUE) return false
        val database = helper.writableDatabase
        database.beginTransaction()
        return try {
            val removed = database.rawQuery("SELECT id,revision,payload,metric,measured_at,dedupe FROM observations " +
                "WHERE id=? AND revision=? AND deleted=1", arrayOf(id, deletionRevision.toString())).use { rows ->
                if (rows.moveToFirst()) decode(rows) to rows.getString(5) else null
            } ?: return false
            val (tombstone, key) = removed
            val previous = revision(id, deletionRevision - 1) ?: return false
            if (tombstone.profileId != "self" || previous != tombstone.copy(revision = previous.revision, receivedAt = previous.receivedAt))
                return false
            if (database.rawQuery("SELECT 1 FROM observations WHERE dedupe=? AND deleted=0 LIMIT 1",
                    arrayOf(key)).use { it.moveToFirst() } ||
                recordForEvidence(tombstone.draft) != null || recordForOcrLink(tombstone.draft) != null) return false
            val restored = tombstone.copy(revision = deletionRevision + 1, receivedAt = System.currentTimeMillis())
            val encrypted = encode(restored)
            try {
                check(database.update("observations", ContentValues().apply {
                    put("deleted", 0); put("revision", restored.revision); put("payload", encrypted)
                }, "id=? AND revision=? AND deleted=1", arrayOf(id, deletionRevision.toString())) == 1)
                database.insertOrThrow("revisions", null, ContentValues().apply {
                    put("id", id); put("revision", restored.revision); put("payload", encrypted)
                    put("changed_at", restored.receivedAt); put("deleted", 0)
                })
                // Links are authenticated against their revision and must be re-encrypted for the restored one.
                for (evidence in backupSourceLinks(previous, android.os.CancellationSignal())) {
                    val ocr = evidence.kind == "ocr"
                    if (ocr && (recordForEvidenceKey(evidenceKey(evidence, restored.draft.metric)) != null ||
                            linkedOcrRecord(evidence) != null)) return false
                    check(insertSourceLink(restored, evidence, if (ocr) ocrLinkKey(evidence) else ""))
                }
                changed(restored.draft.metric)
                database.setTransactionSuccessful()
                true
            } finally { encrypted.fill(0) }
        } finally { database.endTransaction(); publishCommittedChanges() }
    }

    fun history(id: String, beforeRevision: Int = Int.MAX_VALUE): List<HealthObservation> = helper.readableDatabase.rawQuery(
        "SELECT id,revision,payload FROM revisions WHERE id=? AND revision<? ORDER BY revision DESC LIMIT 50", arrayOf(id, beforeRevision.toString())
    ).use { buildList { while (it.moveToNext()) add(decode(it)) } }

    fun saveDraft(draft: HealthDraft) {
        val key = draftKey(draft)
        if (!draft.hasInput()) { clearDraft(key); return }
        val bytes = draft.json().toString().toByteArray(Charsets.UTF_8)
        val encrypted = try { AgentStorageCipher.encryptBinary(bytes, aad(key, 1)) } finally { bytes.fill(0) }
        try {
            val db = helper.writableDatabase
            if (draft.recordId.isNotBlank()) {
                db.execSQL("INSERT OR REPLACE INTO drafts(draft_key,payload) SELECT ?,? " +
                    "WHERE EXISTS(SELECT 1 FROM observations WHERE id=? AND deleted=0)", arrayOf(key, encrypted, draft.recordId))
            } else check(db.insertWithOnConflict("drafts", null, ContentValues().apply {
                put("draft_key", key); put("payload", encrypted)
            }, SQLiteDatabase.CONFLICT_REPLACE) != -1L) { "Health draft was not saved" }
        }
        finally { encrypted.fill(0) }
    }
    fun draft(key: String): HealthDraft? = helper.readableDatabase.rawQuery("SELECT payload FROM drafts WHERE draft_key=?", arrayOf(key)).use {
        if (it.moveToFirst()) decodeDraft(key, it.getBlob(0)) else null
    }
    private fun decodeDraft(key: String, payload: ByteArray): HealthDraft {
        val bytes = AgentStorageCipher.decryptBinary(payload, aad(key, 1))
        return try { HealthDraft.from(JSONObject(String(bytes, Charsets.UTF_8))) } finally { bytes.fill(0); payload.fill(0) }
    }
    private fun reviewDraft(key: String): HealthOcrReviewRow? =
        helper.readableDatabase.rawQuery("SELECT payload FROM drafts WHERE draft_key=?", arrayOf(key)).use {
            if (!it.moveToFirst()) return@use null
            val payload = it.getBlob(0)
            val version = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(java.security.MessageDigest.getInstance("SHA-256").digest(payload))
            HealthOcrReviewRow(decodeDraft(key, payload), version)
        }
    fun clearDraft(key: String) { helper.writableDatabase.delete("drafts", "draft_key=?", arrayOf(key)) }
    override fun close() = helper.close()

    private class Database(context: Context, name: String) : SQLiteOpenHelper(context, name, null, SCHEMA_VERSION) {
        init { setWriteAheadLoggingEnabled(true) }
        override fun onConfigure(db: SQLiteDatabase) { db.setForeignKeyConstraintsEnabled(true) }
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE observations(id TEXT PRIMARY KEY,revision INTEGER NOT NULL,metric TEXT NOT NULL," +
                "measured_at INTEGER NOT NULL,payload BLOB NOT NULL,dedupe TEXT NOT NULL,deleted INTEGER NOT NULL DEFAULT 0,original_id TEXT,evidence_key TEXT,external_key TEXT,bluetooth_group TEXT)")
            db.execSQL("CREATE UNIQUE INDEX observation_dedupe ON observations(dedupe) WHERE deleted=0")
            db.execSQL("CREATE INDEX observation_page ON observations(deleted,measured_at DESC,id DESC)")
            db.execSQL("CREATE INDEX observation_metric_page ON observations(metric,deleted,measured_at DESC,id DESC)")
            db.execSQL("CREATE INDEX observation_original_page ON observations(original_id,deleted,measured_at DESC,id DESC)")
            db.execSQL("CREATE UNIQUE INDEX observation_evidence ON observations(evidence_key) WHERE deleted=0 AND evidence_key IS NOT NULL")
            db.execSQL("CREATE TABLE revisions(id TEXT NOT NULL REFERENCES observations(id),revision INTEGER NOT NULL," +
                "payload BLOB NOT NULL,changed_at INTEGER NOT NULL,deleted INTEGER NOT NULL,PRIMARY KEY(id,revision))")
            db.execSQL("CREATE TABLE drafts(draft_key TEXT PRIMARY KEY,payload BLOB NOT NULL)")
            HealthTableStore.createSchema(db)
            createClocks(db)
            indexPlatformRecords(db)
            indexBluetoothGroups(db)
            createSyncCheckpoints(db)
            HealthOriginalStore.createSharedSchema(db)
            HealthRestoreReceipts.createSchema(db)
            createSourceLinks(db)
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            check(oldVersion in 1 until SCHEMA_VERSION && newVersion == SCHEMA_VERSION) { "Unsupported health schema upgrade" }
            if (oldVersion < 2) {
                db.execSQL("ALTER TABLE observations ADD COLUMN original_id TEXT")
                db.execSQL("ALTER TABLE observations ADD COLUMN evidence_key TEXT")
                db.execSQL("CREATE INDEX observation_original_page ON observations(original_id,deleted,measured_at DESC,id DESC)")
                db.execSQL("CREATE UNIQUE INDEX observation_evidence ON observations(evidence_key) WHERE deleted=0 AND evidence_key IS NOT NULL")
            }
            if (oldVersion < 3) HealthTableStore.createSchema(db)
            createClocks(db)
            if (oldVersion < 5) {
                db.execSQL("ALTER TABLE observations ADD COLUMN external_key TEXT")
                indexPlatformRecords(db)
            }
            if (oldVersion < 6) createSyncCheckpoints(db)
            if (oldVersion < 7) HealthOriginalStore.createSharedSchema(db)
            if (oldVersion < 8) HealthRestoreReceipts.createSchema(db)
            if (oldVersion < 13) {
                val present = db.rawQuery("PRAGMA table_info(observations)", null).use { rows ->
                    generateSequence { if (rows.moveToNext()) rows.getString(1) else null }.any { it == "bluetooth_group" }
                }
                if (!present) db.execSQL("ALTER TABLE observations ADD COLUMN bluetooth_group TEXT")
                indexBluetoothGroups(db)
            }
            if (oldVersion >= 7 && oldVersion < 9) HealthOriginalLibraryStore.createHistoryIndex(db)
            createSourceLinks(db)
            if (oldVersion == 10) {
                db.execSQL("INSERT INTO health_source_links(original_id,record_id,revision,job_id,measured_at,payload) " +
                    "SELECT original_id,record_id,revision,job_id,measured_at,payload FROM health_table_source_links")
                db.execSQL("DROP TABLE health_table_source_links")
            }
        }
        private fun indexBluetoothGroups(db: SQLiteDatabase) = db.execSQL(
            "CREATE INDEX IF NOT EXISTS observation_bluetooth_page ON observations(metric,deleted,bluetooth_group,measured_at DESC,id DESC) WHERE bluetooth_group IS NOT NULL")
        private fun createSourceLinks(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE IF NOT EXISTS health_source_links(original_id TEXT NOT NULL,record_id TEXT NOT NULL REFERENCES observations(id)," +
                "revision INTEGER NOT NULL,job_id TEXT NOT NULL,measured_at INTEGER NOT NULL,payload BLOB NOT NULL," +
                "evidence_key TEXT NOT NULL DEFAULT '',PRIMARY KEY(original_id,record_id,revision,job_id,evidence_key))")
            db.execSQL("CREATE INDEX IF NOT EXISTS health_source_job ON health_source_links(job_id)")
            db.execSQL("CREATE INDEX IF NOT EXISTS health_source_page ON health_source_links(original_id,measured_at DESC,record_id DESC)")
            db.execSQL("CREATE INDEX IF NOT EXISTS health_source_evidence ON health_source_links(evidence_key) WHERE evidence_key<>''")
            db.execSQL("CREATE INDEX IF NOT EXISTS health_source_record ON health_source_links(record_id,revision,original_id,job_id,evidence_key)")
        }
        private fun indexPlatformRecords(db: SQLiteDatabase) =
            db.execSQL("CREATE UNIQUE INDEX observation_external ON observations(external_key) WHERE external_key IS NOT NULL")
        private fun createSyncCheckpoints(db: SQLiteDatabase) =
            db.execSQL("CREATE TABLE health_sync_checkpoints(source TEXT PRIMARY KEY,payload BLOB NOT NULL)")
        private fun createClocks(db: SQLiteDatabase) { db.execSQL("CREATE TABLE IF NOT EXISTS health_metric_clocks(metric TEXT PRIMARY KEY,token TEXT NOT NULL)") }
    }
    companion object {
        private const val BLUETOOTH_HISTORY_FILTER = "metric=? AND bluetooth_group=? AND deleted IN (0,1)"
        const val DEFAULT_DB = "health_records_v1.db"
        const val SCHEMA_VERSION = 13
        const val PAGE_SIZE = 30
        fun changes(context: Context, name: String = "health_records_v1.db") = android.net.Uri.parse("content://${context.packageName}.health-originals/changes/observations/" + android.net.Uri.encode(name))
        fun syncIncidentChanges(context: Context, name: String) = android.net.Uri.parse(
            "content://${context.packageName}.health-originals/changes/sync-incidents/" + android.net.Uri.encode(name))
        fun draftKey(draft: HealthDraft) = when {
            draft.recordId.isNotBlank() -> "edit:${draft.recordId}"
            draft.evidence != null -> "ocr:${draft.evidence.jobId}:${draft.evidence.page}:${draft.evidence.candidateId}"
            else -> "new:${draft.metric.name}"
        }
    }
}
