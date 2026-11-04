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
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthSourcesDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun fixture(test: (HealthOverviewDatabases, Long) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names, System.currentTimeMillis()) } finally { clearHealthOverviewFixture(context, names) }
    }

    @Test fun emptySourcesDoNotCreateDatabasesOrClaimSync() = fixture { names, now ->
        val sources = HealthSourcesRepository.load(context, names, now)
        assertEquals(HealthLocalSources(null, 0, 0), sources.local)
        assertFalse(context.getDatabasePath(names.records).exists())
        assertFalse(context.getDatabasePath(names.originals).exists())
        assertEquals(context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE), sources.bluetoothLe)
        @Suppress("DEPRECATION")
        val manifest = context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS or PackageManager.GET_SERVICES)
        assertFalse(manifest.requestedPermissions.orEmpty().any { it.startsWith("android.permission.health.") || it.startsWith("androidx.health.permission.") })
        assertFalse(manifest.services.orEmpty().any { it.name.endsWith(".HealthDataSdkService") })
    }

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
