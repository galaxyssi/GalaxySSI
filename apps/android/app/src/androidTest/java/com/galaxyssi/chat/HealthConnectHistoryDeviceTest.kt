package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.view.inspector.WindowInspector
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CancellationException
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthConnectHistoryDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val now = System.currentTimeMillis()
    private val pressure = HealthConnectScope.BLOOD_PRESSURE

    @Test fun eraseBindsPreviewAndPreservesManualBluetoothAndOtherTypes() = fixture { names ->
        HealthRecordStore(context, names.records).use { store ->
            val rows = (0..32).map { index -> bp("bp-$index", now - 200_000 - index * 1000L) }
            assertEquals(rows.size, store.importHealthConnect(rows) {})
            val original = requireNotNull(store.overviewLatestSelf(HealthMetric.BLOOD_PRESSURE, now))
            val edited = (store.save(original.editable().copy(note = "first edit")) as HealthSaveResult.Saved).record
            store.saveDraft(edited.editable().copy(note = "next edit"))
            val softDeleted = store.page(metric = HealthMetric.BLOOD_PRESSURE).records[1]
            assertTrue(store.delete(softDeleted.id, softDeleted.revision))
            val stale = store.connectPreview(pressure)
            assertEquals(33L, stale.count)

            val later = bp("new-reading", now - 50_000, "example.otherapp")
            assertEquals(1, store.importHealthConnect(listOf(later)) {})
            assertTrue(runCatching { store.eraseMeasurementHistory(stale) }.exceptionOrNull() is HealthMeasurementHistoryChanged)
            val weight = HealthConnectMeasurement("weight", "example.scale",
                HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "67"), "kg", now - 40_000))
            assertEquals(1, store.importHealthConnect(listOf(weight)) {})
            val manual = (store.save(HealthDraft(values = mapOf("systolic" to "115", "diastolic" to "75"),
                measuredAt = now - 20_000)) as HealthSaveResult.Saved).record
            val bluetooth = (store.saveBluetooth(healthTrendPressure("monitor", now - 10_000), "unspecified") {} as HealthSaveResult.Saved).record
            val legacy = HealthObservationPolicy.observation(HealthDraft(values = mapOf("systolic" to "130", "diastolic" to "87"),
                measuredAt = now - 30_000)).copy(source = "bluetooth", platformOrigin = "Legacy monitor")
            val db = store.tableDatabase
            db.beginTransaction()
            try { store.insertRestored(legacy); db.setTransactionSuccessful() }
            finally { db.endTransaction(); store.publishCommittedChanges() }
            val checkpoint = HealthSyncCheckpoint(pressure, token = "checkpoint", lastAttempt = now, lastSuccess = now,
                outcome = HealthSyncOutcome.NO_NEW)
            store.saveHealthSyncCheckpoint(checkpoint)
            val preview = store.connectPreview(pressure)
            assertEquals(34L, preview.count)
            assertEquals(later.draft.measuredAt, preview.last)
            var checks = 0
            assertTrue(runCatching {
                store.eraseMeasurementHistory(preview) { if (++checks == 32) throw CancellationException() }
            }.exceptionOrNull() is CancellationException)
            assertEquals(preview, store.connectPreview(pressure))
            assertNotNull(store.draft("edit:${edited.id}"))

            assertEquals(34L, store.eraseMeasurementHistory(preview))
            assertEquals(0L, store.connectPreview(pressure).count)
            assertEquals(1L, store.connectPreview(HealthConnectScope.WEIGHT).count)
            assertEquals(checkpoint, store.healthSyncCheckpoint(pressure))
            assertEquals(manual, store.record(manual.id))
            assertEquals(bluetooth, store.record(bluetooth.id))
            assertEquals(legacy, store.record(legacy.id))
            assertTrue(store.history(original.id).isEmpty())
            assertTrue(store.history(softDeleted.id).isEmpty())
            assertNull(store.draft("edit:${edited.id}"))
        }
    }

    @Test fun sourcePageDeletesOnlyReviewedCopiesWithLocalAnalysisDisabled() = fixture { names ->
        assumeFalse("History dialog verification requires an unlocked Android 10+ display",
            Build.VERSION.SDK_INT < 29 || context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        HealthPrivacyStore(context, names.privacy).use { privacy ->
            privacy.change(HealthPrivacyOption.CONFIRMED_METRICS, false, privacy.policy().version)
        }
        HealthRecordStore(context, names.records).use {
            assertEquals(1, it.importHealthConnect(listOf(bp("history", now - 60_000))) {})
        }
        val intent = Intent(context, HealthSourcesActivity::class.java).putExtra("health_sources_test_id", names.fixture)
        ActivityScenario.launch<HealthSourcesActivity>(intent).use { scenario ->
            val entry = "health-connect-history-entry"
            await("local copies entry") {
                var ready = false
                scenario.onActivity { ready = it.window.decorView.findViewWithTag<View>(entry) != null }
                ready
            }
            val monitor = instrumentation.addMonitor(HealthMeasurementHistoryActivity::class.java.name, null, false)
            try {
                scenario.onActivity { assertTrue(it.window.decorView.findViewWithTag<View>(entry).performClick()) }
                val child = requireNotNull(instrumentation.waitForMonitorWithTimeout(monitor, 12_000) as? HealthMeasurementHistoryActivity)
                try {
                    openPreview(child)
                    dialogButton(android.R.id.button2)
                    assertEquals(1L, copies(names))
                    openPreview(child)
                    HealthRecordStore(context, names.records).use {
                        assertEquals(1, it.importHealthConnect(listOf(bp("late-reading", now - 15_000))) {})
                    }
                    dialogButton(android.R.id.button1)
                    awaitNotice(child, R.string.health_connect_history_changed)
                    assertEquals(2L, copies(names))
                    openPreview(child)
                    dialogButton(android.R.id.button1)
                    awaitNotice(child, R.string.health_connect_history_deleted)
                    assertEquals(0L, copies(names))
                    openType(child, "BLOOD_PRESSURE")
                    awaitNotice(child, R.string.health_connect_history_empty)
                } finally { instrumentation.runOnMainSync { child.finish() } }
            } finally { instrumentation.removeMonitor(monitor) }
        }
        HealthPrivacyStore(context, names.privacy).use { privacy ->
            assertFalse(privacy.policy().metrics)
            val event = privacy.page().entries.single {
                it.scope.purpose == HealthAccessPurpose.DELETE_HEALTH_CONNECT_HISTORY && it.outcome == HealthAccessOutcome.COMPLETE
            }
            assertEquals(setOf(HealthMetric.BLOOD_PRESSURE), event.scope.metrics)
            assertEquals(HealthAccessSource.HEALTH_CONNECT, event.scope.source)
            assertEquals(2L, event.scope.count)
        }
    }

    @Test fun privacyPagePreviewsSourceCountsAndErasesOnlyTheSelectedMetric() = fixture { names ->
        assumeFalse("Measurement deletion UI requires an unlocked Android 10+ display",
            Build.VERSION.SDK_INT < 29 || context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val (job, original) = overviewOcrJob(context, names, now - 60_000)
        val scope = HealthMeasurementHistoryScope(HealthMetric.BLOOD_PRESSURE, healthConnectOnly = false)
        val (weight, pressureRecord) = HealthRecordStore(context, names.records).use { store ->
            val weight = (store.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "67"), "kg", now - 40_000)) as HealthSaveResult.Saved).record
            val manual = (store.save(HealthDraft(values = mapOf("systolic" to "115", "diastolic" to "75"),
                measuredAt = now - 20_000)) as HealthSaveResult.Saved).record
            assertEquals(1, store.importHealthConnect(listOf(bp("from-connect", now - 10_000))) {})
            val evidence = HealthEvidence(original.id, job.id, "bp", original.sha256, 1, "120/80", confirmed = true)
            assertTrue(store.save(HealthDraft(values = mapOf("systolic" to "120", "diastolic" to "80"),
                measuredAt = now - 50_000, evidence = evidence)) is HealthSaveResult.Saved)
            assertEquals(mapOf(HealthMeasurementSource.MANUAL to 1L, HealthMeasurementSource.OCR to 1L,
                HealthMeasurementSource.CONNECT to 1L), store.measurementHistoryPreview(scope).sources)
            weight to manual
        }
        val launch = Intent(context, HealthPrivacyActivity::class.java).putHealthNavigationFixture(names)
            .putExtra("health_privacy_test_db", names.privacy)
        ActivityScenario.launch<HealthPrivacyActivity>(launch).use { scenario ->
            val tag = "health-privacy-delete-measurements"
            await("local measurement deletion") {
                var ready = false
                scenario.onActivity { ready = it.window.decorView.findViewWithTag<View>(tag) != null }
                ready
            }
            val monitor = instrumentation.addMonitor(HealthMeasurementHistoryActivity::class.java.name, null, false)
            try {
                scenario.onActivity { assertTrue(it.window.decorView.findViewWithTag<View>(tag).performClick()) }
                val child = requireNotNull(instrumentation.waitForMonitorWithTimeout(monitor, 12_000) as? HealthMeasurementHistoryActivity)
                try {
                    openType(child, "BLOOD_PRESSURE", "health-measurement-history")
                    val counts = listOf(HealthMeasurementSource.MANUAL, HealthMeasurementSource.OCR, HealthMeasurementSource.CONNECT).map {
                        child.getString(R.string.health_measurement_history_source, child.getString(healthRecordSourceResource(it.code)), 1L)
                    }
                    await("source breakdown") { onMain {
                        WindowInspector.getGlobalWindowViews().any { root ->
                            val message = root.findViewById<TextView>(android.R.id.message)?.text?.toString().orEmpty()
                            counts.all { it in message }
                        }
                    } }
                    dialogButton(android.R.id.button1)
                    awaitNotice(child, R.string.health_measurement_history_deleted, "health-measurement-history")
                } finally { instrumentation.runOnMainSync { child.finish() } }
            } finally { instrumentation.removeMonitor(monitor) }
        }
        HealthRecordStore(context, names.records).use {
            assertEquals(0L, it.measurementHistoryPreview(scope).count)
            assertTrue(it.history(pressureRecord.id).isEmpty())
            assertEquals(weight, it.record(weight.id))
        }
        HealthOriginalStore(context, names.originals, names.originalRoot(context)).use {
            assertTrue(it.present(requireNotNull(it.original(original.id))))
        }
        HealthPrivacyStore(context, names.privacy).use {
            val event = it.page().entries.single { row -> row.scope.purpose == HealthAccessPurpose.DELETE_MEASUREMENT_HISTORY }
            assertEquals(HealthAccessOutcome.COMPLETE, event.outcome)
            assertEquals(3L, event.scope.count)
        }
    }

    private fun HealthRecordStore.connectPreview(scope: HealthConnectScope) =
        measurementHistoryPreview(HealthMeasurementHistoryScope(scope.metric, healthConnectOnly = true))
    private fun bp(id: String, time: Long, origin: String = "example.watch") = HealthConnectMeasurement(id, origin,
        HealthDraft(values = mapOf("systolic" to "120", "diastolic" to "80"), measuredAt = time))
    private fun copies(names: HealthOverviewDatabases) = HealthRecordStore(context, names.records).use { it.connectPreview(pressure).count }
    private fun openType(activity: HealthMeasurementHistoryActivity, type: String, prefix: String = "health-connect-history") = await("data type $type") { onMain {
        activity.hasWindowFocus() && activity.window.decorView.findViewWithTag<View>("$prefix-$type")?.performClick() == true
    } }
    private fun openPreview(activity: HealthMeasurementHistoryActivity) {
        openType(activity, "BLOOD_PRESSURE")
        await("history scope preview") { onMain {
            WindowInspector.getGlobalWindowViews().any { it.findViewById<TextView>(android.R.id.message)?.text?.isNotBlank() == true }
        } }
    }
    private fun dialogButton(id: Int) = await("confirmation button") { onMain {
        WindowInspector.getGlobalWindowViews().mapNotNull { it.findViewById<View>(id) }.lastOrNull()?.performClick() == true
    } }
    private fun awaitNotice(activity: HealthMeasurementHistoryActivity, resource: Int, prefix: String = "health-connect-history") = await("local copies status") { onMain {
        activity.window.decorView.findViewWithTag<TextView>("$prefix-notice")?.text?.toString() == activity.getString(resource)
    } }
    private fun onMain(block: () -> Boolean): Boolean {
        var found = false
        instrumentation.runOnMainSync { found = block() }
        return found
    }
    private fun await(label: String, ready: () -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 12_000
        do {
            if (ready()) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < end)
        fail("Missing $label")
    }
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
}
