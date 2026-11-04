package com.galaxyssi.chat

import android.content.Context
import java.security.MessageDigest
import java.time.ZoneId

internal object HealthSleepAlertEngine {
    fun evaluate(context: Context, store: HealthReminderStore, now: Long, zone: ZoneId,
        recordsName: String = "health_records_v1.db", privacyName: String = HealthPrivacyStore.DEFAULT_DB): Boolean {
        val settings = store.settings()
        if (!settings.sleepChanges && !store.hasSleepHistory()) return false
        HealthPrivacyStore(context, privacyName).use { access ->
            val policy = access.policy()
            if (!policy.metrics) {
                if (settings.sleepChanges) store.applySleep(settings.revision, null, null, now)
                return false
            }
            if (!settings.sleepChanges) return true
            val end = HealthReminderPolicy.day(now, zone).minusDays(1)
            val scope = HealthWeeklyScope(end, zone, setOf(HealthMetric.SLEEP_DURATION))
            HealthRecordStore(context, recordsName).use { records ->
                val stamp = HealthWeeklyStamp(scope, records.metricVersions(scope.metrics), now)
                val input = listOf(HealthSleepAlertPolicy.VERSION, HealthWeeklySnapshot.METHOD_VERSION, end, zone.id,
                    settings.sleepDecrease, settings.mergeSleepChanges, policy.version, stamp.versions.getValue(HealthMetric.SLEEP_DURATION))
                val key = MessageDigest.getInstance("SHA-256").digest(input.joinToString("|").toByteArray(Charsets.UTF_8))
                    .joinToString("") { "%02x".format(it.toInt() and 255) }
                if (!store.sleepEvaluated(key)) {
                    val report = access.track(HealthAccessScope.sleepChange(scope)) { HealthWeeklyRepository.calculate(records, scope, stamp) }
                    val current = access.policy()
                    if (!current.metrics || current.version != policy.version) return false
                    HealthWeeklyRepository.requireCurrent(records, stamp)
                    store.applySleep(settings.revision, key, HealthSleepAlertPolicy.evidence(settings, report), now)
                }
            }
            store.resumeSleep(now)
            return true
        }
    }
}
