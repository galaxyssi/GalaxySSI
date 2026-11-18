package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import java.io.File
import java.time.LocalDate
import java.time.ZoneId

internal data class HealthOverviewDatabases(val fixture: String? = null) {
    val records get() = fixture?.let { "health-overview-records-$it.db" } ?: "health_records_v1.db"
    val care get() = fixture?.let { "health-care-test-$it.db" } ?: HealthCareStore.DEFAULT_DB
    val originals get() = fixture?.let { "health-overview-originals-$it.db" } ?: "health_originals_v1.db"
    val reminders get() = fixture?.let { "health-reminder-test-$it.db" } ?: HealthReminderStore.DEFAULT_DB
    val privacy get() = fixture?.let { "health-privacy-test-$it.db" } ?: HealthPrivacyStore.DEFAULT_DB
    val profile get() = fixture?.let { "health-profile-test-$it.db" } ?: HealthProfileStore.DEFAULT_DB
    val prefs get() = fixture?.let { "health-overview-test-$it" } ?: "health-overview"
    val backups get() = fixture?.let { "health-backup-history-test-$it.db" } ?: "health_backup_history_v1.db"
    val activity get() = fixture?.let { "health-activity-test-$it.db" } ?: HealthActivityHistoryStore.DEFAULT_DB
    fun originalRoot(context: Context) = File(context.filesDir, fixture?.let { "health-overview-test-$it" } ?: "health-originals-v1")
}

internal fun Intent.healthNavigationDatabases() = HealthOverviewDatabases(
    getStringExtra("health_overview_test_id").orEmpty().takeIf { BuildConfig.DEBUG && HealthProfilePolicy.uuid(it) })

internal fun Intent.putHealthNavigationFixture(names: HealthOverviewDatabases) = apply {
    if (BuildConfig.DEBUG && names.fixture != null) putExtra("health_overview_test_id", names.fixture)
}

internal data class HealthOverviewMetric(val metric: HealthMetric, val record: HealthObservation?, val freshness: HealthOverviewFreshness,
    val ranges: List<HealthOverviewRange> = emptyList(),
    val showAdultReference: Boolean = true,
    val sleepBand: HealthOverviewGuidance.SleepBand = HealthOverviewGuidance.SleepBand.ADULT_UNSPECIFIED,
    val stepGoal: Int? = null, val stepProgress: Double? = null, val stepProgressPermitted: Boolean = false) {
    val outsideRange get() = ranges.any { it.outside }
}
internal data class HealthOverviewMetricDetail(val metric: HealthOverviewMetric, val recent: List<HealthObservation>,
    val concernId: String?)
internal data class HealthOverviewDerived(val sleep: HealthWeeklyStat? = null, val alert: HealthSleepAlert? = null,
    val permitted: Boolean = true, val unavailable: Boolean = false)
internal data class HealthOverviewSnapshot(val time: Long, val zone: ZoneId, val hasRecords: Boolean, val metrics: List<HealthOverviewMetric>,
    val derived: HealthOverviewDerived, val attention: List<HealthOverviewAttention>, val reviewUnavailable: Boolean,
    val connectionsUnavailable: Boolean = false)

internal object HealthOverviewRepository {
    private val candidates = HealthMetric.entries.toSet() - setOf(HealthMetric.TEMPERATURE, HealthMetric.OXYGEN_SATURATION)

    fun batch(context: Context, records: HealthRecordStore, names: HealthOverviewDatabases, snapshot: HealthOverviewSnapshot,
        key: String): HealthOverviewSnapshot = HealthPrivacyStore.track(context,
        HealthAccessScope(HealthAccessPurpose.OVERVIEW, HealthMetric.entries.toSet()), names.privacy) {
        HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            val selected = HealthMeasurementBatches(originals).load(records, key).latest
            val items = selected.values.filter { it.draft.metric in candidates && it.draft.metric != HealthMetric.STEPS }.map { record ->
                HealthOverviewMetric(record.draft.metric, record, HealthOverviewPolicy.freshness(record.draft.metric, record.draft.measuredAt,
                    snapshot.time, snapshot.zone), listOfNotNull(HealthOverviewRangePolicy.report(record)), showAdultReference = false)
            }.sortedWith(compareByDescending<HealthOverviewMetric> { it.outsideRange }.thenBy { it.metric.ordinal })
            snapshot.copy(metrics = snapshot.metrics.filter { it.metric == HealthMetric.STEPS } + items)
        }
    }

    fun metricDetail(context: Context, records: HealthRecordStore, names: HealthOverviewDatabases, metric: HealthMetric,
        now: Long, zone: ZoneId): HealthOverviewMetricDetail {
        val versions = records.metricVersions(setOf(metric))
        val recent = records.recentSelf(now, limit = 3, metric = metric)
        val record = recent.firstOrNull()
        val comparison = runCatching { ranges(context, names, mapOf(metric to record), versions, now, zone)[metric] }
            .getOrNull().orEmpty()
        val age = HealthOverviewGuidance.ageOn(profileBirthDate(context, names),
            HealthOverviewPolicy.localDay(record?.draft?.measuredAt ?: now, zone))
        val item = HealthOverviewMetric(metric, record, HealthOverviewPolicy.freshness(metric, record?.draft?.measuredAt, now, zone),
            comparison, HealthOverviewGuidance.adultReference(age), HealthOverviewGuidance.sleep(age))
        val concern = if (record != null) discussionConcern(context, names, record, versions.getValue(metric)) else null
        if (versions != records.metricVersions(setOf(metric))) throw HealthWeeklyChanged()
        return HealthOverviewMetricDetail(item, recent, concern)
    }

    fun discussionConcern(context: Context, names: HealthOverviewDatabases, record: HealthObservation,
        version: String): String? = runCatching {
        if (record.profileId != "self" || !context.getDatabasePath(names.care).exists()) return null
        val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
        if (!privacy.metrics || !privacy.profile) return null
        HealthCareStore(context, names.care).use { care ->
            val settings = care.settings()
            care.forMetric(record.draft.metric)?.takeIf {
                settings.enabled && it.stage !in setOf(HealthCareStage.PAUSED, HealthCareStage.CLOSED) &&
                    it.assessment.record == HealthCareRecordRef(record.id, record.revision) &&
                    it.inputVersion == HealthCareEngine.inputVersion(settings.version, privacy.version, version) &&
                    HealthCareProfileAccess.current(context, it.profileLink, names)
            }?.id
        }
    }.getOrNull()

    fun load(context: Context, records: HealthRecordStore, names: HealthOverviewDatabases, now: Long, zone: ZoneId): HealthOverviewSnapshot {
        val selected = candidates
        val versions = records.metricVersions(selected)
        val latest = (HealthOverviewPolicy.metrics + selected.filter { versions.getValue(it).isNotBlank() }).distinct()
            .associateWith { records.overviewLatestSelf(it, now) }
        val comparisons = runCatching { ranges(context, names, latest, versions, now, zone) }.getOrDefault(emptyMap())
        val birthDate = profileBirthDate(context, names)
        val goal = runCatching { HealthOverviewStepGoalStore(context, names).load() }.getOrNull()
        val metricProgressPermitted = goal != null && runCatching {
            HealthPrivacyStore(context, names.privacy).use { it.policy().metrics }
        }.getOrDefault(false)
        val metrics = latest.map { (metric, record) ->
            val freshness = HealthOverviewPolicy.freshness(metric, record?.draft?.measuredAt, now, zone)
            val age = HealthOverviewGuidance.ageOn(birthDate, HealthOverviewPolicy.localDay(record?.draft?.measuredAt ?: now, zone))
            val stepGoal = goal.takeIf { metric == HealthMetric.STEPS }
            val steps = if (metricProgressPermitted && stepGoal != null) record?.draft?.values?.get("steps")?.toLongOrNull() else null
            HealthOverviewMetric(metric, record, freshness, comparisons[metric].orEmpty(), HealthOverviewGuidance.adultReference(age),
                HealthOverviewGuidance.sleep(age), stepGoal, HealthOverviewGuidance.stepProgress(stepGoal, steps, freshness, metricProgressPermitted),
                metric == HealthMetric.STEPS && metricProgressPermitted)
        }.filter { it.metric in HealthOverviewPolicy.metrics || it.outsideRange }
            .sortedWith(compareByDescending<HealthOverviewMetric> { it.outsideRange }
                .thenByDescending { if (it.outsideRange) it.record?.draft?.measuredAt ?: 0L else 0L })
        val hasRecords = latest.values.any { it != null } || records.overviewLatestSelf(null, now) != null
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

    private fun profileBirthDate(context: Context, names: HealthOverviewDatabases): LocalDate? {
        if (!context.getDatabasePath(names.profile).exists()) return null
        return runCatching {
            val field = HealthProfileField.BIRTH_DATE
            HealthProfileStore(context, names.profile, names.privacy).use {
                it.capture(setOf(field), emptySet()).fields[field]?.text?.let(LocalDate::parse)
            }
        }.getOrNull()
    }

    private fun ranges(context: Context, names: HealthOverviewDatabases, latest: Map<HealthMetric, HealthObservation?>,
        versions: Map<HealthMetric, String>, now: Long, zone: ZoneId): Map<HealthMetric, List<HealthOverviewRange>> {
        val hasCare = context.getDatabasePath(names.care).exists()
        val eligible = latest.mapNotNull { (metric, record) ->
            record?.takeIf { hasCare || it.draft.reference.isNotBlank() }?.let { metric to it }
        }.toMap()
        if (eligible.isEmpty()) return emptyMap()
        return HealthPrivacyStore(context, names.privacy).use { store ->
            val policy = store.policy()
            if (!policy.metrics) return@use emptyMap()
            store.track(HealthAccessScope(HealthAccessPurpose.OVERVIEW, eligible.keys, until = now, zone = zone.id)) {
                val targets = if (!hasCare || !policy.profile) emptyMap() else HealthCareStore(context, names.care).use { care ->
                    val settings = care.settings()
                    if (!settings.enabled) emptyMap() else eligible.mapNotNull { (metric, record) ->
                        val issue = care.forMetric(metric)?.takeIf {
                            it.target != null && it.inputVersion == HealthCareEngine.inputVersion(settings.version, policy.version, versions.getValue(metric)) &&
                                HealthCareProfileAccess.current(context, it.profileLink, names)
                        } ?: return@mapNotNull null
                        HealthOverviewRangePolicy.target(record, issue)?.let { metric to it }
                    }.toMap()
                }
                if (store.policy() != policy) throw HealthAccessBlocked()
                eligible.mapValues { (metric, record) -> listOfNotNull(HealthOverviewRangePolicy.report(record), targets[metric]) }
            }
        }
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
                        HealthImportState.REVIEW -> if (!job.modelRecognized && !job.modelFirst && job.nextPage > 0 && job.originalId.isNotBlank() &&
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
