package com.galaxyssi.chat

import android.app.Activity
import android.app.Instrumentation
import android.app.KeyguardManager
import android.content.Intent
import android.content.IntentFilter
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthWeeklyReportUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val zone get() = ZoneId.systemDefault()
    private fun add(store: HealthRecordStore, second: Long = 0) = store.save(HealthDraft(HealthMetric.SLEEP_DURATION,
        mapOf("sleep_duration" to "6"), "h", LocalDate.now(zone).minusDays(1).atTime(12, 0).atZone(zone).toInstant().toEpochMilli() + second * 1000L))

    private fun screen(denied: Boolean = false, test: (ActivityScenario<HealthWeeklyActivity>, HealthRecordStore, HealthPrivacyStore) -> Unit) {
        assumeFalse("Weekly report UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val id = UUID.randomUUID()
        val recordsName = "health-weekly-test-$id.db"; val privacyName = "health-privacy-test-$id.db"
        var worker: ExecutorService? = null
        try {
            HealthRecordStore(context, recordsName).use { records -> HealthPrivacyStore(context, privacyName).use { privacy ->
                add(records)
                if (denied) privacy.change(HealthPrivacyOption.CONFIRMED_METRICS, false, privacy.policy().version)
                val intent = Intent(context, HealthWeeklyActivity::class.java)
                    .putExtra("health_weekly_test_db", recordsName).putExtra("health_privacy_test_db", privacyName)
                ActivityScenario.launch<HealthWeeklyActivity>(intent).use { scenario -> try { test(scenario, records, privacy) } finally {
                    scenario.onActivity {
                        worker = HealthWeeklyActivity::class.java.getDeclaredField("io").apply { isAccessible = true }.get(it) as ExecutorService
                    }
                } }
            } }
        } finally {
            worker?.awaitTermination(10, TimeUnit.SECONDS)
            context.deleteDatabase(recordsName); context.deleteDatabase(privacyName)
        }
    }
    private fun find(view: View, tag: String): View? {
        if (view.tag == tag) return view
        if (view is ViewGroup) for (i in 0 until view.childCount) find(view.getChildAt(i), tag)?.let { return it }
        return null
    }
    private fun await(scenario: ActivityScenario<HealthWeeklyActivity>, tag: String) {
        val timeout = SystemClock.elapsedRealtime() + 15_000
        do {
            var found = false
            scenario.onActivity { found = find(it.window.decorView, tag) != null }
            if (found) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < timeout)
        fail("Missing native view: $tag")
    }
    private fun click(scenario: ActivityScenario<HealthWeeklyActivity>, tag: String) {
        await(scenario, tag)
        scenario.onActivity { requireNotNull(find(it.window.decorView, tag)).performClick() }
    }
    private fun review(scenario: ActivityScenario<HealthWeeklyActivity>, raw: Boolean = false) {
        click(scenario, "health-weekly-prepare")
        if (raw) click(scenario, "health-weekly-include-raw")
        click(scenario, "health-weekly-preview-action")
        await(scenario, "health-weekly-save")
    }
    @Test fun scopedPreviewExcludesUnselectedMetricsAndRequiresExplicitConsent() = screen { scenario, _, _ ->
        click(scenario, "health-weekly-prepare")
        click(scenario, "health-weekly-select-STEPS")
        click(scenario, "health-weekly-include-raw")
        click(scenario, "health-weekly-preview-action")
        await(scenario, "health-weekly-record")
        scenario.onActivity {
            assertNull(find(it.window.decorView, "health-weekly-stat-STEPS"))
            assertNotNull(find(it.window.decorView, "health-weekly-stat-SLEEP_DURATION"))
            assertFalse(requireNotNull(find(it.window.decorView, "health-weekly-save")).isEnabled)
            assertFalse((find(it.window.decorView, "health-weekly-consent") as CheckBox).isChecked)
        }
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertNull(find(it.window.decorView, "health-weekly-record")) }
        scenario.moveToState(Lifecycle.State.RESUMED)
        await(scenario, "health-weekly-record")
    }
    @Test fun changedRecordsInvalidateAReviewedSnapshotUntilReviewedAgain() = screen { scenario, records, _ ->
        review(scenario)
        click(scenario, "health-weekly-consent")
        add(records, 1)
        await(scenario, "health-weekly-review-again")
        scenario.onActivity { assertNull(find(it.window.decorView, "health-weekly-save")) }
        click(scenario, "health-weekly-review-again")
        await(scenario, "health-weekly-save")
        scenario.onActivity { assertFalse(requireNotNull(find(it.window.decorView, "health-weekly-save")).isEnabled) }
    }
    @Test fun disabledDerivedAccessBlocksTheNativeReport() = screen(denied = true) { scenario, _, _ ->
        await(scenario, "health-weekly-blocked")
        scenario.onActivity { assertNull(find(it.window.decorView, "health-weekly-stat-SLEEP_DURATION")) }
    }
    @Test fun confirmedSaveWritesThroughTheSelectedContentUriAndRecordsTheOutcome() = screen { scenario, _, privacy ->
        val file = File(context.cacheDir, "health-capture/weekly-test-${UUID.randomUUID()}.pdf")
        file.parentFile!!.mkdirs()
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val filter = IntentFilter(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            addDataType("application/pdf")
        }
        val monitor = Instrumentation.ActivityMonitor(filter,
            Instrumentation.ActivityResult(Activity.RESULT_OK, Intent().setData(uri)), true)
        instrumentation.addMonitor(monitor)
        try {
            review(scenario, raw = true)
            assertFalse(file.exists())
            click(scenario, "health-weekly-consent")
            click(scenario, "health-weekly-save")
            assertEquals(1, monitor.hits)
            await(scenario, "health-weekly-saved")
            assertTrue(file.length() > 500)
            val event = privacy.page().entries.single { it.scope.purpose == HealthAccessPurpose.SAVE_WEEKLY_REPORT }
            assertEquals(HealthAccessOutcome.COMPLETE, event.outcome)
        } finally {
            instrumentation.removeMonitor(monitor)
            file.delete()
        }
    }
}
