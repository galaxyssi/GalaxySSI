package com.galaxyssi.chat

import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

internal object HealthCareEngine {
    fun evaluate(context: Context, names: HealthOverviewDatabases = HealthOverviewDatabases(), now: Long = System.currentTimeMillis(),
        cancelled: () -> Boolean = { false }): Int {
        if (!context.getDatabasePath(names.care).exists()) return 0
        HealthCareStore(context, names.care).use { care ->
            val settings = care.settings()
            if (!settings.enabled || cancelled()) return 0
            HealthPrivacyStore(context, names.privacy).use { privacy ->
                val permission = privacy.policy()
                if (!permission.metrics) return 0
                HealthRecordStore(context, names.records).use { records ->
                    val versions = records.metricVersions(HealthMetric.entries.toSet())
                    var changed = 0
                    for (metric in HealthMetric.entries) {
                        if (cancelled()) return changed
                        val prior = care.forMetric(metric)
                        val stamp = versions.getValue(metric)
                        if (stamp.isBlank() && prior == null) continue
                        val key = inputVersion(settings.version, permission.version, stamp)
                        if (care.evaluated(metric) == key) continue
                        val assessment = privacy.track(HealthAccessScope(HealthAccessPurpose.PROACTIVE_CARE, setOf(metric))) {
                            HealthCarePolicy.assess(metric, records.recentSelf(now, 30, metric), prior?.context)
                        }
                        if (cancelled()) return changed
                        if (privacy.policy() != permission || records.metricVersion(metric) != stamp) throw HealthCareConflict()
                        val value = care.applyEvaluation(metric, key, settings.version, prior?.revision, assessment, now)
                        if (value != prior) changed++
                    }
                    return changed
                }
            }
        }
    }
    internal fun inputVersion(settings: String, privacy: String, metricClock: String): String =
        token(listOf(HealthCarePolicy.VERSION, settings, privacy, metricClock).joinToString("|"))
    private fun token(value: String): String {
        val bytes = value.toByteArray(Charsets.UTF_8)
        return try { MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) } }
        finally { bytes.fill(0) }
    }
}

internal object HealthCareWork {
    private const val NAME = "health-proactive-care-reconcile"
    fun changed(context: Context) {
        if (!context.getDatabasePath(HealthCareStore.DEFAULT_DB).exists()) return
        // Coalesce import batches and sensor bursts; the persisted metric clocks survive cancellation and restart.
        val request = OneTimeWorkRequestBuilder<HealthCareWorker>().setInitialDelay(750, TimeUnit.MILLISECONDS).build()
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(NAME, ExistingWorkPolicy.REPLACE, request)
    }
}

class HealthCareWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result = try {
        HealthCareEngine.evaluate(applicationContext, cancelled = { isStopped })
        Result.success()
    } catch (_: HealthCareConflict) {
        Result.retry()
    } catch (_: android.database.sqlite.SQLiteDatabaseLockedException) {
        Result.retry()
    } catch (_: Exception) {
        Result.failure()
    }
}
