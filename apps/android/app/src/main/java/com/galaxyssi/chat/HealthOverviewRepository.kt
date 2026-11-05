package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import java.io.File
import java.time.ZoneId

internal data class HealthOverviewDatabases(val fixture: String? = null) {
    val records get() = fixture?.let { "health-overview-records-$it.db" } ?: "health_records_v1.db"
    val originals get() = fixture?.let { "health-overview-originals-$it.db" } ?: "health_originals_v1.db"
    val reminders get() = fixture?.let { "health-reminder-test-$it.db" } ?: HealthReminderStore.DEFAULT_DB
    val privacy get() = fixture?.let { "health-privacy-test-$it.db" } ?: HealthPrivacyStore.DEFAULT_DB
    val profile get() = fixture?.let { "health-profile-test-$it.db" } ?: HealthProfileStore.DEFAULT_DB
    val prefs get() = fixture?.let { "health-overview-test-$it" } ?: "health-overview"
    val backups get() = fixture?.let { "health-backup-history-test-$it.db" } ?: "health_backup_history_v1.db"
    fun originalRoot(context: Context) = File(context.filesDir, fixture?.let { "health-overview-test-$it" } ?: "health-originals-v1")
}

internal fun Intent.healthNavigationDatabases() = HealthOverviewDatabases(
    getStringExtra("health_overview_test_id").orEmpty().takeIf { BuildConfig.DEBUG && HealthProfilePolicy.uuid(it) })

internal fun Intent.putHealthNavigationFixture(names: HealthOverviewDatabases) = apply {
    if (BuildConfig.DEBUG && names.fixture != null) putExtra("health_overview_test_id", names.fixture)
}

internal data class HealthOverviewMetric(val metric: HealthMetric, val record: HealthObservation?, val freshness: HealthOverviewFreshness)
internal data class HealthOverviewDerived(val sleep: HealthWeeklyStat? = null, val alert: HealthSleepAlert? = null,
    val permitted: Boolean = true, val unavailable: Boolean = false)
internal data class HealthOverviewSnapshot(val time: Long, val zone: ZoneId, val hasRecords: Boolean, val metrics: List<HealthOverviewMetric>,
    val derived: HealthOverviewDerived, val attention: List<HealthOverviewAttention>, val reviewUnavailable: Boolean,
    val connectionsUnavailable: Boolean = false)

internal object HealthOverviewRepository {
    fun load(context: Context, records: HealthRecordStore, names: HealthOverviewDatabases, now: Long, zone: ZoneId): HealthOverviewSnapshot {
        val selected = HealthOverviewPolicy.metrics.toSet()
        val versions = records.metricVersions(selected)
        val metrics = HealthOverviewPolicy.metrics.map { metric ->
            val observation = records.overviewLatestSelf(metric, now)
            HealthOverviewMetric(metric, observation, HealthOverviewPolicy.freshness(metric, observation?.draft?.measuredAt, now, zone))
        }
        val hasRecords = metrics.any { it.record != null } || records.overviewLatestSelf(null, now) != null
        val reviews = runCatching { pendingReviews(context, records, names, limit = 2, onePerKind = true) }
        val connections = runCatching {
            val scopes = if (names.fixture == null) HealthConnectSettings.selection(context) else HealthConnectScope.entries.toSet()
            HealthOverviewPolicy.activeConnections(scopes.mapNotNull(records::healthSyncIncident), scopes)
        }
        val derived = runCatching { derive(context, records, names, now, zone, versions.getValue(HealthMetric.SLEEP_DURATION),
            metrics.any { it.metric == HealthMetric.SLEEP_DURATION && it.record != null }) }.getOrElse {
            if (it is HealthAccessBlocked) HealthOverviewDerived(permitted = false) else HealthOverviewDerived(unavailable = true)
        }
        if (records.metricVersions(selected) != versions) throw HealthWeeklyChanged()
        return HealthOverviewSnapshot(now, zone, hasRecords, metrics, derived,
            listOfNotNull(derived.alert?.let { HealthOverviewAttention.Change(it) }) + reviews.getOrDefault(emptyList()) +
                connections.getOrDefault(emptyList()), reviews.isFailure, connections.isFailure)
    }

    fun pendingReviews(context: Context, records: HealthRecordStore, names: HealthOverviewDatabases, limit: Int,
                       onePerKind: Boolean = false): List<HealthOverviewAttention.Review> {
        if (!context.getDatabasePath(names.originals).exists() &&
            (names.fixture != null || !context.getDatabasePath(names.records).exists())) return emptyList()
        return HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            val candidates = originals.overviewReviewJobs()
            if (candidates.isEmpty()) return@use emptyList()
            HealthTableStore(context, names.records).use { tables ->
                val eligible = candidates.asSequence().mapNotNull { job ->
                    val kind = when (job.state) {
                        HealthImportState.TABLE_REVIEW -> tables.batch(job.id)?.takeIf { it.originalId == job.originalId && it.state in setOf(
                            HealthTableState.SHEET_SELECTION, HealthTableState.MAPPING, HealthTableState.READY) }?.let { HealthOverviewReviewKind.TABLE }
                        HealthImportState.REVIEW -> if (job.nextPage > 0 && job.originalId.isNotBlank() &&
                            (records.overviewHasOcrDraft(job.id) || !records.overviewHasOriginalHistory(job.originalId))) HealthOverviewReviewKind.OCR else null
                        else -> null
                    }
                    kind?.let { job to it }
                }
                (if (onePerKind) eligible.distinctBy { it.second } else eligible).take(limit).map { (job, kind) ->
                    val name = originals.originalForJob(job.id)?.takeIf { it.id == job.originalId }?.name.orEmpty()
                    HealthOverviewAttention.Review(job.id, kind, job.createdAt, name)
                }.toList()
            }
        }
    }

    private fun derive(context: Context, records: HealthRecordStore, names: HealthOverviewDatabases, now: Long, zone: ZoneId,
        version: String, hasSleep: Boolean): HealthOverviewDerived {
        val hasPrivacy = context.getDatabasePath(names.privacy).exists()
        if (!hasSleep && !hasPrivacy) return HealthOverviewDerived()
        val scope = HealthWeeklyScope(HealthOverviewPolicy.localDay(now, zone).minusDays(1), zone,
            setOf(HealthMetric.SLEEP_DURATION), comparison = false)
        HealthPrivacyStore(context, names.privacy).use { privacy ->
            if (!privacy.policy().metrics) return HealthOverviewDerived(permitted = false)
            if (!hasSleep) return HealthOverviewDerived()
            return privacy.track(HealthAccessScope.overview(scope)) {
                val stamp = HealthWeeklyStamp(scope, mapOf(HealthMetric.SLEEP_DURATION to version), now)
                val sleep = HealthWeeklyRepository.calculate(records, scope, stamp).stats.single()
                val alert = if (context.getDatabasePath(names.reminders).exists()) HealthReminderStore(context, names.reminders).use {
                    HealthOverviewPolicy.activeChange(it.activeSleep(), it.settings(), scope, version)
                } else null
                HealthOverviewDerived(sleep, alert)
            }
        }
    }
}
