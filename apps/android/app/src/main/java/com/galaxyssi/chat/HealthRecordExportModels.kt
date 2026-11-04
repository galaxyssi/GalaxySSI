package com.galaxyssi.chat

import java.time.LocalDate
import java.time.ZoneId
import org.json.JSONArray
import org.json.JSONObject

internal enum class HealthRecordExportFormat(val extension: String, val mime: String) {
    CSV("csv", "text/csv"), JSON("json", "application/json"), XLSX("xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
}
internal data class HealthRecordExportScope(val metrics: Set<HealthMetric> = HealthMetric.entries.toSet(), val from: Long = 0,
    val until: Long = Long.MAX_VALUE, val zone: String = ZoneId.systemDefault().id, val originalId: String = "",
    val annotations: Boolean = false, val format: HealthRecordExportFormat = HealthRecordExportFormat.CSV,
    val cameraOriginals: Boolean = false, val uploadedOriginals: Boolean = false) {
    val bundlesOriginals get() = cameraOriginals || uploadedOriginals
    val extension get() = if (bundlesOriginals) "zip" else format.extension
    val mime get() = if (bundlesOriginals) "application/zip" else format.mime
    fun selects(original: HealthOriginal) = if (original.source == "camera") cameraOriginals else uploadedOriginals
    init {
        require(metrics.isNotEmpty() && from >= 0 && until > from); ZoneId.of(zone)
        require(originalId.isEmpty() || java.util.UUID.fromString(originalId).toString() == originalId)
    }
    fun matches(record: HealthObservation) = record.profileId == "self" && record.draft.metric in metrics &&
        record.draft.measuredAt >= from && record.draft.measuredAt < until && (originalId.isEmpty() || record.draft.evidence?.originalId == originalId)
    fun snapshot(record: HealthObservation): HealthObservation {
        check(matches(record))
        return if (annotations) record else record.copy(draft = record.draft.copy(note = "", reference = "",
            evidence = record.draft.evidence?.copy(rawText = "", boxes = emptyList(), tableSheet = "")))
    }
    fun json() = JSONObject().put("metrics", JSONArray(metrics.sortedBy { it.ordinal }.map { it.name })).put("from", from).put("until", until)
        .put("zone", zone).put("original", originalId).put("annotations", annotations).put("format", format.name).put("profile", "self")
        .put("camera_originals", cameraOriginals).put("uploaded_originals", uploadedOriginals)
    companion object {
        fun from(j: JSONObject): HealthRecordExportScope {
            require(j.getString("profile") == "self")
            val metrics = j.getJSONArray("metrics").let { a -> (0 until a.length()).map { HealthMetric.valueOf(a.getString(it)) }.toSet() }
            return HealthRecordExportScope(metrics, j.getLong("from"), j.getLong("until"), j.getString("zone"), j.getString("original"), j.getBoolean("annotations"),
                HealthRecordExportFormat.valueOf(j.getString("format")), j.optBoolean("camera_originals"), j.optBoolean("uploaded_originals"))
        }
        fun dates(first: LocalDate, last: LocalDate, zone: ZoneId): Pair<Long, Long> {
            require(!first.isBefore(LocalDate.of(1970, 1, 1)) && !last.isBefore(first))
            return first.atStartOfDay(zone).toInstant().toEpochMilli().coerceAtLeast(0) to last.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        }
    }
}
internal enum class HealthRecordExportState { PREPARING, REVIEW, QUEUED, GENERATING, GENERATED, SAVED, FAILED, CANCELLED }
internal enum class HealthExportSourceStatus { NONE, AVAILABLE, MISSING, UNREADABLE, HASH_MISMATCH, NOT_SELECTED;
    val warning get() = this == MISSING || this == UNREADABLE || this == HASH_MISMATCH
}
internal data class HealthRecordExportItem(val sequence: Long, val record: HealthObservation, val sourceStatus: HealthExportSourceStatus)
internal data class HealthRecordExportAttachment(val originalId: String, val sha256: String, val status: HealthExportSourceStatus,
    val original: HealthOriginal? = null, val sequence: Long = 0) {
    init {
        require(status != HealthExportSourceStatus.NONE && (status == HealthExportSourceStatus.AVAILABLE) == (original != null))
        require(original == null || original.id == originalId && original.sha256 == sha256 && !original.reviewOnly)
    }
    fun json() = JSONObject().put("original_id", originalId).put("sha256", sha256).put("status", status.name)
        .apply { original?.let { put("original", it.json()) } }
    companion object {
        fun from(sequence: Long, j: JSONObject) = HealthRecordExportAttachment(j.getString("original_id"), j.getString("sha256"),
            HealthExportSourceStatus.valueOf(j.getString("status")), j.optJSONObject("original")?.let(HealthOriginal::from), sequence)
        fun token(id: String, sha256: String) = AgentMemoryIndexKey.token("health-export-attachment|$id|$sha256")
    }
}
internal data class HealthRecordExportSession(val id: String, val scope: HealthRecordExportScope, val createdAt: Long,
    val state: HealthRecordExportState = HealthRecordExportState.PREPARING, val phase: String = "prepare",
    val dispatch: String = java.util.UUID.randomUUID().toString(), val attempt: String = "", val count: Long = 0, val rows: Long = 0,
    val sourceWarnings: Long = 0, val estimatedBytes: Long = 0, val completed: Long = 0, val artifactBytes: Long = 0,
    val sha256: String = "", val error: String = "", val confirmedAt: Long = 0, val preparedAt: Long = 0, val scanned: Long = 0,
    val attachmentCount: Long = 0, val attachmentAvailable: Long = 0, val attachmentBytes: Long = 0, val attachmentWarnings: Long = 0) {
    fun json() = JSONObject().put("id", id).put("scope", scope.json()).put("created", createdAt).put("state", state.name).put("phase", phase)
        .put("dispatch", dispatch).put("attempt", attempt).put("count", count).put("rows", rows).put("warnings", sourceWarnings).put("estimate", estimatedBytes)
        .put("completed", completed).put("bytes", artifactBytes).put("sha256", sha256).put("error", error).put("confirmed", confirmedAt).put("prepared", preparedAt).put("scanned", scanned)
        .put("attachment_count", attachmentCount).put("attachment_available", attachmentAvailable)
        .put("attachment_bytes", attachmentBytes).put("attachment_warnings", attachmentWarnings)
    companion object {
        fun from(j: JSONObject) = HealthRecordExportSession(j.getString("id"), HealthRecordExportScope.from(j.getJSONObject("scope")), j.getLong("created"),
            HealthRecordExportState.valueOf(j.getString("state")), j.getString("phase"), j.getString("dispatch"), j.getString("attempt"), j.getLong("count"),
            j.getLong("rows"), j.getLong("warnings"), j.getLong("estimate"), j.getLong("completed"), j.getLong("bytes"), j.getString("sha256"), j.getString("error"), j.getLong("confirmed"), j.getLong("prepared"), j.getLong("scanned"),
            j.optLong("attachment_count"), j.optLong("attachment_available"), j.optLong("attachment_bytes"), j.optLong("attachment_warnings"))
    }
}
internal class HealthRecordExportFailure(val code: String) : java.io.IOException(code)
internal object HealthCsvCellSafety {
    fun encoded(value: String): Pair<String, Boolean> {
        val first = value.dropWhile { it.isWhitespace() || it == '\uFEFF' }.firstOrNull()
        val escape = first != null && first in "=+-@'\uFF1D\uFF0B\uFF0D\uFF20" || value.firstOrNull() in listOf('\t', '\r', '\n')
        // Spreadsheet-facing CSV uses a reversible tab prefix; JSON and XLSX retain exact text.
        return (if (escape) "\t$value" else value) to escape
    }
}
