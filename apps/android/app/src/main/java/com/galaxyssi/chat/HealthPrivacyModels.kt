package com.galaxyssi.chat

import java.time.ZoneId
import org.json.JSONArray
import org.json.JSONObject

internal enum class HealthPrivacyOption { CONFIRMED_METRICS, PROFILE_CONTEXT, ONLINE_ANALYSIS, ORIGINAL_IMAGES, RETAIN_IMPORT_ORIGINALS }
internal data class HealthPrivacyPolicy(
    val metrics: Boolean = true, val profile: Boolean = true, val online: Boolean = false,
    val images: Boolean = false, val version: String = "", val retainImportOriginals: Boolean = true
) {
    init { require(!images || online) }
    fun enabled(option: HealthPrivacyOption) = when (option) {
        HealthPrivacyOption.CONFIRMED_METRICS -> metrics
        HealthPrivacyOption.PROFILE_CONTEXT -> profile
        HealthPrivacyOption.ONLINE_ANALYSIS -> online
        HealthPrivacyOption.ORIGINAL_IMAGES -> images
        HealthPrivacyOption.RETAIN_IMPORT_ORIGINALS -> retainImportOriginals
    }
    fun change(option: HealthPrivacyOption, value: Boolean) = when (option) {
        HealthPrivacyOption.CONFIRMED_METRICS -> copy(metrics = value)
        HealthPrivacyOption.PROFILE_CONTEXT -> copy(profile = value)
        HealthPrivacyOption.ONLINE_ANALYSIS -> copy(online = value, images = value && images)
        HealthPrivacyOption.ORIGINAL_IMAGES -> copy(images = value)
        HealthPrivacyOption.RETAIN_IMPORT_ORIGINALS -> copy(retainImportOriginals = value)
    }
    fun json() = JSONObject().put("metrics", metrics).put("profile", profile).put("online", online).put("images", images)
        .put("version", version).put("retain_import_originals", retainImportOriginals)
    companion object {
        fun from(j: JSONObject) = HealthPrivacyPolicy(j.getBoolean("metrics"), j.getBoolean("profile"), j.getBoolean("online"),
            j.getBoolean("images"), j.getString("version"),
            if (j.has("retain_import_originals")) j.getBoolean("retain_import_originals") else true)
    }
}

internal enum class HealthAccessPurpose(val permission: HealthPrivacyOption? = null) {
    TREND(HealthPrivacyOption.CONFIRMED_METRICS),
    TREND_RECORDS(HealthPrivacyOption.CONFIRMED_METRICS),
    TREND_SOURCES(HealthPrivacyOption.CONFIRMED_METRICS),
    PROFILE_CONTEXT(HealthPrivacyOption.PROFILE_CONTEXT),
    SLEEP_CHANGE(HealthPrivacyOption.CONFIRMED_METRICS),
    OVERVIEW(HealthPrivacyOption.CONFIRMED_METRICS),
    WEEKLY_REPORT(HealthPrivacyOption.CONFIRMED_METRICS),
    SAVE_WEEKLY_REPORT(HealthPrivacyOption.CONFIRMED_METRICS),
    HEALTH_ANALYSIS(HealthPrivacyOption.CONFIRMED_METRICS),
    HEALTH_ANALYSIS_ONLINE(HealthPrivacyOption.ONLINE_ANALYSIS),
    SAVE_RECORDS, SAVE_ORIGINALS, GENERATE_BACKUP, DELETE_PROFILE, DELETE_BLUETOOTH_HISTORY, DELETE_HEALTH_CONNECT_HISTORY
}
internal enum class HealthAccessOutcome { STARTED, COMPLETE, FAILED, CANCELLED, BLOCKED }
internal enum class HealthAccessSource { ALL, MANUAL, ORIGINAL, BLUETOOTH, HEALTH_CONNECT }
internal enum class HealthAccessFormat { CSV, JSON, XLSX, ZIP, ORIGINAL, PDF, GHBACKUP }
internal data class HealthAccessScope(
    val purpose: HealthAccessPurpose, val metrics: Set<HealthMetric> = emptySet(),
    val from: Long = 0, val until: Long = Long.MAX_VALUE, val zone: String = "UTC",
    val fields: Set<HealthProfileField> = emptySet(), val count: Long? = null,
    val source: HealthAccessSource = HealthAccessSource.ALL, val format: HealthAccessFormat? = null,
    val annotations: Boolean = false, val drafts: Long? = null, val basicCount: Int? = null,
    val reportRecords: Boolean = false, val baselineFrom: Long? = null, val destination: String = ""
) {
    init {
        require(until > from && (count == null || count >= 0) && (drafts == null || drafts >= 0))
        require(basicCount == null || basicCount in 0..HealthProfileField.entries.size)
        require(baselineFrom == null || baselineFrom in 0 until from)
        require(destination.length <= 384 && destination.none(Char::isISOControl))
        require((purpose == HealthAccessPurpose.HEALTH_ANALYSIS_ONLINE) == destination.isNotEmpty())
        ZoneId.of(zone)
        when (purpose) {
            HealthAccessPurpose.TREND, HealthAccessPurpose.TREND_RECORDS, HealthAccessPurpose.TREND_SOURCES ->
                require(metrics.size == 1 && fields.isEmpty() && count == null && format == null)
            HealthAccessPurpose.PROFILE_CONTEXT -> require(metrics.isEmpty() && count != null && format == null)
            HealthAccessPurpose.SLEEP_CHANGE -> require(metrics == setOf(HealthMetric.SLEEP_DURATION) && baselineFrom != null && format == null)
            HealthAccessPurpose.OVERVIEW -> require(metrics == setOf(HealthMetric.SLEEP_DURATION) && baselineFrom == null && format == null)
            HealthAccessPurpose.WEEKLY_REPORT, HealthAccessPurpose.SAVE_WEEKLY_REPORT ->
                require(metrics.isNotEmpty() && fields.isEmpty() && !annotations && format == if (purpose == HealthAccessPurpose.SAVE_WEEKLY_REPORT) HealthAccessFormat.PDF else null)
            HealthAccessPurpose.HEALTH_ANALYSIS, HealthAccessPurpose.HEALTH_ANALYSIS_ONLINE ->
                require(metrics.isNotEmpty() && fields.isEmpty() && !annotations && !reportRecords && format == null)
            HealthAccessPurpose.SAVE_RECORDS -> require(metrics.isNotEmpty() && count != null && format in listOf(HealthAccessFormat.CSV, HealthAccessFormat.JSON, HealthAccessFormat.XLSX, HealthAccessFormat.ZIP))
            HealthAccessPurpose.SAVE_ORIGINALS -> require(count != null && format in listOf(HealthAccessFormat.ZIP, HealthAccessFormat.ORIGINAL))
            HealthAccessPurpose.GENERATE_BACKUP -> require(count != null && format == HealthAccessFormat.GHBACKUP && fields.isEmpty())
            HealthAccessPurpose.DELETE_PROFILE -> require(count != null && drafts != null && basicCount != null && format == null)
            HealthAccessPurpose.DELETE_BLUETOOTH_HISTORY -> require(metrics == setOf(HealthMetric.BLOOD_PRESSURE) &&
                source == HealthAccessSource.BLUETOOTH && count != null && count > 0 && format == null)
            HealthAccessPurpose.DELETE_HEALTH_CONNECT_HISTORY -> require(metrics.size == 1 && HealthConnectScope.entries.any { it.metric in metrics } &&
                source == HealthAccessSource.HEALTH_CONNECT && count != null && count > 0 && format == null)
        }
    }
    fun json() = JSONObject().put("purpose", purpose.name).put("metrics", JSONArray(metrics.map { it.name })).put("from", from)
        .put("until", until).put("zone", zone).put("fields", JSONArray(fields.map { it.name })).put("count", count ?: JSONObject.NULL)
        .put("source", source.name).put("format", format?.name ?: JSONObject.NULL).put("annotations", annotations)
        .put("drafts", drafts ?: JSONObject.NULL).put("basics", basicCount ?: JSONObject.NULL)
        .put("reportRecords", reportRecords).put("baselineFrom", baselineFrom ?: JSONObject.NULL)
        .apply { if (destination.isNotEmpty()) put("destination", destination) }
    companion object {
        fun from(j: JSONObject): HealthAccessScope {
            fun values(key: String) = j.getJSONArray(key).let { a -> (0 until a.length()).map(a::getString) }
            return HealthAccessScope(HealthAccessPurpose.valueOf(j.getString("purpose")), values("metrics").map(HealthMetric::valueOf).toSet(),
                j.getLong("from"), j.getLong("until"), j.getString("zone"), values("fields").map(HealthProfileField::valueOf).toSet(),
                j.takeUnless { it.isNull("count") }?.getLong("count"), HealthAccessSource.valueOf(j.getString("source")),
                j.takeUnless { it.isNull("format") }?.getString("format")?.let(HealthAccessFormat::valueOf), j.getBoolean("annotations"),
                j.takeUnless { it.isNull("drafts") }?.getLong("drafts"), j.takeUnless { it.isNull("basics") }?.getInt("basics"),
                j.optBoolean("reportRecords"), j.takeUnless { it.isNull("baselineFrom") }?.getLong("baselineFrom"), j.optString("destination"))
        }
        fun trend(purpose: HealthAccessPurpose, spec: HealthTrendSpec) = HealthAccessScope(purpose, setOf(spec.metric), spec.from, spec.until, spec.zone.id,
            source = when {
                spec.source.manualOnly -> HealthAccessSource.MANUAL
                spec.source.originalId.isNotEmpty() -> HealthAccessSource.ORIGINAL
                spec.source.bluetoothGroup.isNotEmpty() -> HealthAccessSource.BLUETOOTH
                spec.source.platformOrigin.isNotEmpty() -> HealthAccessSource.HEALTH_CONNECT
                else -> HealthAccessSource.ALL
            })
        fun records(session: HealthRecordExportSession) = with(session.scope) {
            HealthAccessScope(HealthAccessPurpose.SAVE_RECORDS, metrics, from, until, zone, count = session.count,
                source = if (originalId.isEmpty()) HealthAccessSource.ALL else HealthAccessSource.ORIGINAL,
                format = if (bundlesOriginals) HealthAccessFormat.ZIP else HealthAccessFormat.valueOf(format.name), annotations = annotations)
        }
        fun originals(count: Long, zip: Boolean = false) = HealthAccessScope(HealthAccessPurpose.SAVE_ORIGINALS, count = count,
            format = if (zip) HealthAccessFormat.ZIP else HealthAccessFormat.ORIGINAL)
        fun weekly(scope: HealthWeeklyScope, save: Boolean = false) = HealthAccessScope(
            if (save) HealthAccessPurpose.SAVE_WEEKLY_REPORT else HealthAccessPurpose.WEEKLY_REPORT,
            scope.metrics, scope.from, scope.until, scope.zone.id, format = if (save) HealthAccessFormat.PDF else null,
            reportRecords = scope.records, baselineFrom = if (scope.hasBaseline) scope.baselineScope().from else null)
        fun sleepChange(scope: HealthWeeklyScope) = HealthAccessScope(HealthAccessPurpose.SLEEP_CHANGE, scope.metrics,
            scope.from, scope.until, scope.zone.id, baselineFrom = scope.baselineScope().from)
        fun overview(scope: HealthWeeklyScope) = HealthAccessScope(HealthAccessPurpose.OVERVIEW, scope.metrics, scope.from, scope.until, scope.zone.id)
        fun analysis(scope: HealthWeeklyScope, destination: String = "") = HealthAccessScope(
            if (destination.isBlank()) HealthAccessPurpose.HEALTH_ANALYSIS else HealthAccessPurpose.HEALTH_ANALYSIS_ONLINE,
            scope.metrics, scope.from, scope.until, scope.zone.id,
            baselineFrom = if (scope.hasBaseline) scope.baselineScope().from else null, destination = destination)
        fun deleteProfile(preview: HealthProfileDeletePreview) = HealthAccessScope(HealthAccessPurpose.DELETE_PROFILE,
            count = preview.entries, drafts = preview.drafts, basicCount = preview.fields)
    }
}
internal data class HealthAccessEvent(val id: String, val time: Long, val scope: HealthAccessScope,
    val outcome: HealthAccessOutcome, val policyVersion: String) {
    fun json() = JSONObject().put("id", id).put("time", time).put("scope", scope.json()).put("outcome", outcome.name).put("policy_version", policyVersion)
    companion object {
        fun from(j: JSONObject) = HealthAccessEvent(j.getString("id"), j.getLong("time"), HealthAccessScope.from(j.getJSONObject("scope")),
            HealthAccessOutcome.valueOf(j.getString("outcome")), j.getString("policy_version"))
    }
}
internal data class HealthAccessCursor(val time: Long, val id: String)
internal data class HealthAccessPage(val entries: List<HealthAccessEvent>, val next: HealthAccessCursor?)
internal class HealthAccessBlocked : IllegalStateException("Health use is not authorized")
internal class HealthPrivacyConflict : IllegalStateException("Health privacy policy changed")
