package com.galaxyssi.chat

import java.time.LocalDate
import java.time.ZoneId

internal enum class HealthOriginalKind {
    IMAGE, PDF, TABLE, OTHER;
    companion object {
        fun of(original: HealthOriginal): HealthOriginalKind = when {
            original.mime.startsWith("image/") -> IMAGE
            original.mime == "application/pdf" -> PDF
            HealthTableParser.format(original.name, original.mime) != null -> TABLE
            else -> OTHER
        }
    }
}
internal data class HealthLibraryFilter(
    val kind: HealthOriginalKind? = null, val from: Long = 0, val until: Long = Long.MAX_VALUE, val filesOnly: Boolean = false,
) {
    init { require(from >= 0 && until > from && !(filesOnly && kind == HealthOriginalKind.IMAGE)) }
    companion object {
        fun dates(first: LocalDate, last: LocalDate, zone: ZoneId, kind: HealthOriginalKind? = null): HealthLibraryFilter {
            require(!first.isBefore(LocalDate.of(1970, 1, 1)) && !last.isBefore(first))
            return HealthLibraryFilter(kind, first.atStartOfDay(zone).toInstant().toEpochMilli().coerceAtLeast(0), last.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli())
        }
    }
}
internal data class HealthLibraryPage(val originals: List<HealthOriginal>, val next: Pair<Long, String>?)
internal enum class HealthOriginalExportState { SELECTING, REVIEW, QUEUED, GENERATING, GENERATED, SAVED, FAILED, CANCELLED }
internal data class HealthOriginalExportSession(val id: String, val state: HealthOriginalExportState, val createdAt: Long,
    val count: Long = 0, val sourceBytes: Long = 0, val missing: Long = 0, val completed: Long = 0,
    val attempt: String = "", val archiveBytes: Long = 0, val sha256: String = "", val error: String = "", val dispatch: String = "",
    val pendingSave: String = "", val verifiedSaveAt: Long = 0, val saveFailed: Boolean = false) {
    fun json() = org.json.JSONObject().put("id", id).put("state", state.name).put("created", createdAt).put("count", count)
        .put("source_bytes", sourceBytes).put("missing", missing).put("completed", completed).put("attempt", attempt)
        .put("archive_bytes", archiveBytes).put("sha256", sha256).put("error", error).put("dispatch", dispatch)
        .put("pending_save", pendingSave).put("verified_save_at", verifiedSaveAt).put("save_failed", saveFailed)
    companion object {
        fun from(j: org.json.JSONObject) = HealthOriginalExportSession(j.getString("id"), HealthOriginalExportState.valueOf(j.getString("state")),
            j.getLong("created"), j.getLong("count"), j.getLong("source_bytes"), j.getLong("missing"), j.getLong("completed"),
            j.getString("attempt"), j.getLong("archive_bytes"), j.getString("sha256"), j.getString("error"), j.optString("dispatch"),
            j.optString("pending_save"), j.optLong("verified_save_at"), j.optBoolean("save_failed"))
    }
}

internal fun HealthOriginalExportSession.title() = when (state) {
    HealthOriginalExportState.REVIEW -> R.string.health_library_confirm
    HealthOriginalExportState.QUEUED, HealthOriginalExportState.GENERATING -> R.string.health_library_generating
    HealthOriginalExportState.GENERATED -> R.string.health_library_generated
    HealthOriginalExportState.SAVED -> if (verifiedSaveAt > 0) R.string.health_library_saved else R.string.health_library_legacy_save
    HealthOriginalExportState.CANCELLED -> R.string.health_import_cancelled
    else -> R.string.health_library_failed
}
internal object HealthOriginalArchiveNames {
    fun entry(original: HealthOriginal): String {
        require(java.util.UUID.fromString(original.id).toString() == original.id)
        val value = original.name.map { if (it.isISOControl() || it in "/\\:<>\"|?*") '_' else it }.joinToString("").trim().trimEnd('.')
        val extension = value.substringAfterLast('.', "").takeIf { it.length in 1..16 && value.contains('.') }?.let { ".$it" }.orEmpty()
        val stem = if (extension.isEmpty()) value else value.dropLast(extension.length)
        val bounded = stem.take(180 - extension.length).trimEnd { Character.isHighSurrogate(it) }.trimEnd(' ', '.')
        val named = (bounded.ifBlank { "document" } + extension).takeUnless { it == "." || it == ".." } ?: "document"
        val reserved = named.substringBefore('.').uppercase(java.util.Locale.ROOT)
        val clean = if (reserved in setOf("CON", "PRN", "AUX", "NUL") || reserved.matches(Regex("(?:COM|LPT)[1-9]"))) "_$named" else named
        return "originals/${original.id}/$clean"
    }
}
