package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.SystemClock
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.text.DateFormat
import java.util.Date
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthSourcesDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    private fun fixture(test: (HealthOverviewDatabases, Long) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names, System.currentTimeMillis()) } finally { clearHealthOverviewFixture(context, names) }
    }

    @Test fun emptySourcesDoNotCreateDatabasesOrClaimSync() = fixture { names, now ->
        val sources = HealthSourcesRepository.load(context, names, now)
        assertEquals(HealthLocalSources(null, 0, 0), sources.local)
        assertEquals(HealthSourceSyncHistory(emptyMap(), 0), sources.syncHistory)
        assertFalse(context.getDatabasePath(names.records).exists())
        assertFalse(context.getDatabasePath(names.originals).exists())
        assertEquals(context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE), sources.bluetoothLe)
        @Suppress("DEPRECATION")
        val manifest = context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
        val healthPermissions = manifest.requestedPermissions.orEmpty()
            .filter { it.startsWith("android.permission.health.") || it.startsWith("androidx.health.permission.") }.toSet()
        assertEquals(HealthConnectScope.entries.map { it.permission }.toSet(), healthPermissions)
    }

    @Test fun appSelectionAndSystemGrantAreIndependent() {
        val sleep = HealthConnectScope.SLEEP
        val steps = HealthConnectScope.STEPS
        val weight = HealthConnectScope.WEIGHT
        val selected = setOf(sleep, steps)
        val permissions = setOf(sleep.permission, weight.permission)
        fun state(platform: HealthPlatformAvailability, grants: Set<String>?) =
            HealthSourcesRepository.scopes(platform, selected, grants).associate { it.scope to it.access }
        val known = state(HealthPlatformAvailability.AVAILABLE, permissions)
        assertEquals(HealthConnectScope.entries.toSet(), known.keys)
        assertEquals(HealthSourceAccess.GRANTED, known[sleep])
        assertEquals(HealthSourceAccess.MISSING_GRANT, known[steps])
        assertEquals(HealthSourceAccess.NOT_SELECTED, known[weight])
        assertEquals(HealthSourceAccess.UNVERIFIED, state(HealthPlatformAvailability.AVAILABLE, null)[sleep])
        assertEquals(HealthSourceAccess.UNVERIFIED, state(HealthPlatformAvailability.CHECK_FAILED, permissions)[sleep])
        assertEquals(HealthSourceAccess.PLATFORM_UNAVAILABLE, state(HealthPlatformAvailability.UNSUPPORTED, permissions)[sleep])
    }

    @Test fun historicalSyncAndBluetoothReceiptStaySeparateAndOpenTheMatchingScope() = fixture { names, now ->
        assumeFalse("Source UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val scope = HealthConnectScope.STEPS
        val success = now - 3 * 3_600_000
        val attempt = now - 2 * 3_600_000
        val receipt = now - 3_600_000
        HealthRecordStore(context, names.records).use { store ->
            store.saveHealthSyncCheckpoint(HealthSyncCheckpoint(scope, lastAttempt = attempt, lastSuccess = success,
                outcome = HealthSyncOutcome.PERMISSION))
            assertTrue(store.saveBluetooth(healthTrendPressure("fixture-source-overview", receipt), "unspecified") {} is HealthSaveResult.Saved)
        }
        val snapshot = requireNotNull(HealthSourcesRepository.load(context, names, now).syncHistory)
        assertEquals(HealthSourceSyncTime(attempt, success), snapshot.checkpoints[scope])
        assertEquals(receipt, snapshot.bluetoothReceipt)
        val intent = Intent(context, HealthSourcesActivity::class.java).putExtra("health_sources_test_id", names.fixture)
        ActivityScenario.launch<HealthSourcesActivity>(intent).use { scenario ->
            val rowTag = "health-sources-scope-${scope.name}"
            await(scenario, rowTag)
            scenario.onActivity { activity ->
                val root = activity.window.decorView
                val row = root.findViewWithTag<View>(rowTag)
                assertTrue(row.isClickable)
                val texts = row.texts()
                assertTrue(texts.any { activity.getString(R.string.health_sources_access_not_selected) in it })
                assertTrue(texts.any { activity.getString(R.string.health_sync_success_time, date(success)) in it })
                assertEquals(activity.getString(R.string.health_sync_ble_receipt, date(receipt)),
                    root.findViewWithTag<TextView>("health-sources-ble-receipt").text.toString())
                assertFalse(root.findViewWithTag<View>("health-sources-scope-WEIGHT").isClickable)
            }
            val monitor = instrumentation.addMonitor(HealthSyncActivity::class.java.name, null, false)
            try {
                scenario.onActivity { assertTrue(it.window.decorView.findViewWithTag<View>(rowTag).performClick()) }
                val child = requireNotNull(instrumentation.waitForMonitorWithTimeout(monitor, 10_000) as? HealthSyncActivity)
                try {
                    assertEquals(scope.name, child.intent.getStringExtra("health_sync_scope"))
                    awaitScope(child, scope, success)
                } finally {
                    instrumentation.runOnMainSync { child.finish() }
                    instrumentation.waitForIdleSync()
                }
            } finally { instrumentation.removeMonitor(monitor) }
            await(scenario, rowTag)
        }
    }

    private fun awaitScope(activity: HealthSyncActivity, scope: HealthConnectScope, success: Long) {
        val deadline = SystemClock.elapsedRealtime() + 12_000
        do {
            var ready = false
            instrumentation.runOnMainSync {
                activity.window.decorView.findViewWithTag<View>("health-sync-scope-${scope.name}")
                    ?.findViewWithTag<TextView>("health-sync-scope-success")?.let {
                        assertEquals(activity.getString(R.string.health_sync_success_time, date(success)), it.text.toString())
                        ready = true
                    }
            }
            if (ready) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("Missing sync history for ${scope.name}")
    }

    private fun View.texts(): List<String> = when (this) {
        is TextView -> listOf(text.toString())
        is android.view.ViewGroup -> (0 until childCount).flatMap { getChildAt(it).texts() }
        else -> emptyList()
    }

    private fun date(time: Long) = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(time))

    @Test fun localSourcesSeparateOriginalsFromConfirmedRowsAndIgnoreFutureManualRows() = fixture { names, now ->
        val (job, original) = overviewOcrJob(context, names, now - 3000)
        assertEquals(HealthLocalSources(null, 0, 1), HealthSourcesRepository.load(context, names, now).local)
        val evidence = HealthEvidence(original.id, job.id, "bp", original.sha256, 1, "120/80", confirmed = true)
        val manual = HealthDraft(values = mapOf("systolic" to "119", "diastolic" to "79"), measuredAt = now - 2000)
        HealthRecordStore(context, names.records).use { store ->
            assertTrue(store.save(manual) is HealthSaveResult.Saved)
            assertTrue(store.save(manual.copy(measuredAt = now + 60_000)) is HealthSaveResult.Saved)
            val imported = store.save(HealthDraft(values = mapOf("systolic" to "120", "diastolic" to "80"),
                measuredAt = now - 1000, evidence = evidence)) as HealthSaveResult.Saved
            assertEquals(HealthLocalSources(manual.measuredAt, 1, 1), HealthSourcesRepository.load(context, names, now).local)
            assertTrue(store.delete(imported.record.id, imported.record.revision))
            assertEquals(HealthLocalSources(manual.measuredAt, 0, 1), HealthSourcesRepository.load(context, names, now).local)
        }
    }

    @Test fun sourceScreenShowsActualPlatformAndRefreshesLocalRecordsOnReturn() = fixture { names, now ->
        assumeFalse("Source UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val intent = Intent(context, HealthSourcesActivity::class.java).putExtra("health_sources_test_id", names.fixture)
        val platformTag = "health-platform-${HealthSourcesRepository.platform(context).name}"
        ActivityScenario.launch<HealthSourcesActivity>(intent).use { scenario ->
            await(scenario, platformTag)
            await(scenario, "health-sources-manual")
            scenario.onActivity { activity ->
                assertEquals(activity.getString(R.string.health_sources_manual_empty), manualSubtitle(activity))
            }
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.onActivity { assertNull(it.window.decorView.findViewWithTag<View>("health-sources-manual")) }
            HealthRecordStore(context, names.records).use { store ->
                assertTrue(store.save(HealthDraft(values = mapOf("systolic" to "120", "diastolic" to "80"),
                    measuredAt = now - 1000)) is HealthSaveResult.Saved)
            }
            scenario.moveToState(Lifecycle.State.RESUMED)
            await(scenario, "health-sources-manual")
            scenario.onActivity { activity ->
                assertNotEquals(activity.getString(R.string.health_sources_manual_empty), manualSubtitle(activity))
                assertNotEquals(activity.getString(R.string.health_sources_local_error), manualSubtitle(activity))
            }
        }
    }

    private fun manualSubtitle(activity: HealthSourcesActivity): String {
        val row = activity.window.decorView.findViewWithTag<LinearLayout>("health-sources-manual")
        return row.findViewWithTag<TextView>("health-source-caption").text.toString()
    }

    private fun await(scenario: ActivityScenario<HealthSourcesActivity>, tag: String) {
        val deadline = SystemClock.elapsedRealtime() + 10_000
        do {
            var found = false
            scenario.onActivity { found = it.window.decorView.findViewWithTag<View>(tag) != null }
            if (found) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("Missing native source view: $tag")
    }
}
