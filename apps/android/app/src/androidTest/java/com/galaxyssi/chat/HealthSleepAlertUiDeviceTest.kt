package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.RadioButton
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthSleepAlertUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun screen(merged: Boolean = false,
        test: (ActivityScenario<HealthReminderActivity>, HealthPrivacyStore, HealthOverviewDatabases) -> Unit) {
        assumeFalse("Sleep reminder UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        val now = System.currentTimeMillis()
        val zone = ZoneId.systemDefault()
        var worker: ExecutorService? = null
        try {
            HealthReminderStore(context, names.reminders).use { store ->
                store.save(store.settings().copy(sleepChanges = true, mergeSleepChanges = true), now)
                HealthRecordStore(context, names.records).use { records ->
                    val last = seedHealthSleep(records, now, zone)
                    if (merged) {
                        assertTrue(HealthSleepAlertEngine.evaluate(context, store, now, zone, names.records, names.privacy))
                        assertTrue(records.save(last.editable().copy(values = mapOf("sleep_duration" to "5"))) is HealthSaveResult.Saved)
                        assertTrue(HealthSleepAlertEngine.evaluate(context, store, now + 1, zone, names.records, names.privacy))
                    }
                }
            }
            HealthPrivacyStore(context, names.privacy).use { privacy ->
                val intent = Intent(context, HealthReminderActivity::class.java).putHealthNavigationFixture(names)
                ActivityScenario.launch<HealthReminderActivity>(intent).use { scenario -> try { test(scenario, privacy, names) } finally {
                    scenario.onActivity { worker = HealthReminderActivity::class.java.getDeclaredField("io").apply { isAccessible = true }.get(it) as ExecutorService }
                } }
            }
        } finally { worker?.awaitTermination(10, TimeUnit.SECONDS); clearHealthOverviewFixture(context, names) }
    }
    private fun find(view: View, tag: String): View? {
        if (view.tag == tag) return view
        if (view is ViewGroup) for (i in 0 until view.childCount) find(view.getChildAt(i), tag)?.let { return it }
        return null
    }
    private fun await(scenario: ActivityScenario<HealthReminderActivity>, tag: String) {
        val until = SystemClock.elapsedRealtime() + 15_000
        do {
            var ready = false
            scenario.onActivity { ready = find(it.window.decorView, tag) != null }
            if (ready) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Missing native view: $tag")
    }
    private fun click(scenario: ActivityScenario<HealthReminderActivity>, tag: String) {
        await(scenario, tag)
        scenario.onActivity { requireNotNull(find(it.window.decorView, tag)).performClick() }
    }
    @Test fun calculatedAlertOpensRealChartAndKeepsSnoozeAndCompletion() = screen { scenario, _, _ ->
        click(scenario, "health-sleep-alert")
        await(scenario, "health-sleep-chart")
        click(scenario, "health-sleep-snooze")
        await(scenario, "health-sleep-state-SNOOZED")
        click(scenario, "health-sleep-complete")
        await(scenario, "health-sleep-state-COMPLETE")
        scenario.recreate()
        await(scenario, "health-sleep-state-COMPLETE")
    }
    @Test fun backgroundClearsChartAndForegroundRestoresTheSameAlert() = screen { scenario, _, _ ->
        click(scenario, "health-sleep-alert"); await(scenario, "health-sleep-chart")
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertNull(find(it.window.decorView, "health-sleep-chart")) }
        scenario.moveToState(Lifecycle.State.RESUMED)
        await(scenario, "health-sleep-chart")
    }
    @Test fun revocationRemovesAlreadyDisplayedSleepEvidence() = screen(merged = true) { scenario, privacy, _ ->
        click(scenario, "health-sleep-alert"); click(scenario, "health-sleep-evidence-original")
        privacy.change(HealthPrivacyOption.CONFIRMED_METRICS, false, privacy.policy().version)
        await(scenario, "health-sleep-blocked")
        scenario.onActivity {
            assertNull(find(it.window.decorView, "health-sleep-chart"))
            assertNull(find(it.window.decorView, "health-sleep-evidence-report"))
        }
    }
    @Test fun mergedAlertKeepsItsFirstComparisonAndRefusesToSubstituteNewRecords() = screen(merged = true) { scenario, _, names ->
        click(scenario, "health-sleep-alert")
        val (first, latest) = HealthReminderStore(context, names.reminders).use {
            requireNotNull(it.activeSleep()).let { alert -> alert.trigger to alert.evidence }
        }
        assertNotEquals(first.metricVersion, latest.metricVersion)
        assertEvidence(scenario, latest, "latest", "351.4", "-68.6")
        click(scenario, "health-sleep-evidence-original")
        scenario.recreate()
        assertEvidence(scenario, first, "original", "360", "-60")
        child(HealthTrendRecordsActivity::class.java, { click(scenario, "health-sleep-evidence-records") }) { cohort ->
            awaitChild(cohort, "health-trend-records-status") { status ->
                assertEquals(cohort.getString(R.string.health_trend_changed), (status as TextView).text.toString())
            }
            assertEquals(first.metricVersion, cohort.intent.getStringExtra("health_version"))
            assertEquals(first.first, cohort.intent.healthTrendSpec()?.first)
        }
        assertEvidence(scenario, first, "original", "360", "-60")
        child(HealthWeeklyActivity::class.java, { click(scenario, "health-sleep-evidence-report") }) { weekly ->
            awaitChild(weekly, "health-weekly-refresh-link") {
                assertNull(find(weekly.window.decorView, "health-weekly-prepare"))
                it.performClick()
            }
            awaitChild(weekly, "health-weekly-stat-SLEEP_DURATION") {
                assertNull(find(weekly.window.decorView, "health-weekly-stat-STEPS"))
                assertEquals(HealthWeeklyText(weekly).range(first.weeklyStamp().scope),
                    (find(weekly.window.decorView, "health-weekly-range") as TextView).text.toString())
            }
        }
    }
    @Test fun latestEvidenceOpensTheBaselineAndTheScopedWeeklyReport() = screen(merged = true) { scenario, _, names ->
        click(scenario, "health-sleep-alert")
        val evidence = HealthReminderStore(context, names.reminders).use { requireNotNull(it.activeSleep()).evidence }
        val baseline = HealthRecordStore(context, names.records).use {
            it.trendRecords(HealthTrendSpec(HealthMetric.SLEEP_DURATION, evidence.baselineFirst, evidence.baselineLast,
                ZoneId.of(evidence.zone), "min")).records.first()
        }
        child(HealthTrendRecordsActivity::class.java, { click(scenario, "health-sleep-evidence-baseline") }) { cohort ->
            awaitChild(cohort, "health-trend-record-${baseline.id}") {}
            assertEquals(evidence.baselineFirst, cohort.intent.healthTrendSpec()?.first)
            assertEquals(evidence.baselineLast, cohort.intent.healthTrendSpec()?.last)
            assertEquals(evidence.metricVersion, cohort.intent.getStringExtra("health_version"))
        }
        child(HealthWeeklyActivity::class.java, { click(scenario, "health-sleep-evidence-report") }) { weekly ->
            awaitChild(weekly, "health-weekly-linked") {
                assertEquals(weekly.getString(R.string.health_weekly_reminder_scope), (it as TextView).text.toString())
                assertNotNull(find(weekly.window.decorView, "health-weekly-stat-SLEEP_DURATION"))
                assertNull(find(weekly.window.decorView, "health-weekly-stat-STEPS"))
                val stamp = requireNotNull(weekly.intent.getBundleExtra("health_weekly_handoff"))
                assertEquals(evidence.end.toString(), stamp.getString("end"))
                assertEquals(evidence.metricVersion, stamp.getBundle("versions")?.getString("SLEEP_DURATION"))
                assertFalse(stamp.getBoolean("records"))
            }
        }
    }
    private fun assertEvidence(scenario: ActivityScenario<HealthReminderActivity>, evidence: HealthSleepAlertEvidence,
        selection: String, recent: String, delta: String) {
        await(scenario, "health-sleep-evidence-comparison")
        scenario.onActivity { activity ->
            val root = activity.window.decorView
            assertTrue((find(root, "health-sleep-evidence-$selection") as RadioButton).isChecked)
            assertEquals(activity.getString(R.string.health_weekly_compare, recent, "420", delta),
                (find(root, "health-sleep-evidence-comparison") as TextView).text.toString())
            assertEquals(activity.getString(R.string.health_weekly_compare_coverage, evidence.recentDays, evidence.baselineDays),
                (find(root, "health-sleep-evidence-coverage") as TextView).text.toString())
        }
    }
    private fun <T : Activity> child(type: Class<T>, open: () -> Unit, test: (T) -> Unit) {
        val monitor = instrumentation.addMonitor(type.name, null, false)
        try {
            open()
            val activity = requireNotNull(type.cast(instrumentation.waitForMonitorWithTimeout(monitor, 12_000)))
            try { test(activity) } finally {
                instrumentation.runOnMainSync { activity.finish() }
                instrumentation.waitForIdleSync()
            }
        } finally { instrumentation.removeMonitor(monitor) }
    }
    private fun awaitChild(activity: Activity, tag: String, test: (View) -> Unit) {
        val until = SystemClock.elapsedRealtime() + 12_000
        do {
            var ready = false
            instrumentation.runOnMainSync { find(activity.window.decorView, tag)?.let { test(it); ready = true } }
            if (ready) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Missing child view: $tag")
    }
}
