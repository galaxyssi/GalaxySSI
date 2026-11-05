package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.Button
import android.widget.CheckBox
import android.widget.DatePicker
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthWeeklyHandoffDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val zone = ZoneId.systemDefault()
    private val date get() = LocalDate.now(zone).minusDays(21)

    @Test fun assistantOpensTheHistoricalScopeAndItsRevisionWithNoRawExportSelected() = fixture { names ->
        val scope = HealthWeeklyScope(date, zone, setOf(HealthMetric.STEPS, HealthMetric.SLEEP_DURATION))
        val (inside, outside) = HealthRecordStore(context, names.records).use { store ->
            save(store, scope.from, "1240") to save(store, scope.until + 1000, "6789")
        }
        val intent = Intent(context, HealthAssistantActivity::class.java).putExtra("health_assistant_test_id", names.fixture)
        ActivityScenario.launch<HealthAssistantActivity>(intent).use { scenario ->
            lateinit var assistant: HealthAssistantActivity
            scenario.onActivity { assistant = it }
            tap(assistant, "health-assistant-date")
            instrumentation.waitForIdleSync()
            instrumentation.runOnMainSync {
                val roots = WindowInspector.getGlobalWindowViews()
                val picker = roots.flatMap(::views).filterIsInstance<DatePicker>().last()
                picker.updateDate(scope.end.year, scope.end.monthValue - 1, scope.end.dayOfMonth)
                val ok = roots.mapNotNull { it.findViewById<Button>(android.R.id.button1) }.last()
                assertTrue(ok.performClick())
            }
            awaitCondition("selected historical date") {
                view(assistant, "health-assistant-date")?.let { row -> views(row).filterIsInstance<TextView>().any {
                    it.text.toString() == HealthWeeklyText(assistant).range(scope)
                } } == true
            }
            tap(assistant, "health-assistant-calculate")
            await(assistant, "health-assistant-action-WEEKLY_REPORT")
            val weekly = open(HealthWeeklyActivity::class.java) { tap(assistant, "health-assistant-action-WEEKLY_REPORT") }
            try {
                await(weekly, "health-weekly-stat-STEPS")
                instrumentation.runOnMainSync {
                    assertEquals(HealthWeeklyText(weekly).range(scope), text(weekly, "health-weekly-range"))
                    assertNotNull(view(weekly, "health-weekly-linked"))
                    assertNull(view(weekly, "health-weekly-stat-BLOOD_PRESSURE"))
                    assertEquals(setOf("end", "zone", "created", "records", "comparison", "versions"),
                        weekly.intent.getBundleExtra("health_weekly_handoff")?.keySet())
                }
                val cohort = open(HealthTrendRecordsActivity::class.java) { tap(weekly, "health-weekly-stat-STEPS") }
                try {
                    await(cohort, "health-trend-record-${inside.id}")
                    instrumentation.runOnMainSync { assertNull(view(cohort, "health-trend-record-${outside.id}")) }
                    val revision = open(HealthRecordRevisionActivity::class.java) { tap(cohort, "health-trend-record-${inside.id}") }
                    try {
                        await(revision, "health-revision-value")
                        instrumentation.runOnMainSync { assertTrue(text(revision, "health-revision-value").startsWith("1240")) }
                        back(revision)
                    } finally { finish(revision) }
                    await(cohort, "health-trend-record-${inside.id}")
                    back(cohort)
                } finally { finish(cohort) }
                await(weekly, "health-weekly-prepare")
                tap(weekly, "health-weekly-prepare")
                instrumentation.runOnMainSync {
                    assertTrue((view(weekly, "health-weekly-select-STEPS") as CheckBox).isChecked)
                    assertTrue((view(weekly, "health-weekly-select-SLEEP_DURATION") as CheckBox).isChecked)
                    assertFalse((view(weekly, "health-weekly-select-BLOOD_PRESSURE") as CheckBox).isChecked)
                    assertFalse((view(weekly, "health-weekly-include-raw") as CheckBox).isChecked)
                }
            } finally { finish(weekly) }
        }
    }

    @Test fun staleAssistantVersionsRequireAnExplicitRefreshAndKeepTheChosenScope() = fixture { names ->
        val scope = HealthWeeklyScope(date, zone, setOf(HealthMetric.STEPS), comparison = false)
        val original = HealthRecordStore(context, names.records).use { store ->
            val row = save(store, scope.from, "1234")
            val stamp = HealthWeeklyRepository.calculate(store, scope).stamp
            assertTrue(store.save(row.editable().copy(values = mapOf("steps" to "1250"))) is HealthSaveResult.Saved)
            stamp
        }
        val intent = Intent(context, HealthWeeklyActivity::class.java).putHealthWeeklyHandoff(original)
            .putHealthNavigationFixture(names)
        ActivityScenario.launch<HealthWeeklyActivity>(intent).use { scenario ->
            lateinit var weekly: HealthWeeklyActivity
            scenario.onActivity { weekly = it }
            await(weekly, "health-weekly-refresh-link")
            scenario.onActivity {
                assertNull(view(it, "health-weekly-stat-STEPS"))
                assertNull(view(it, "health-weekly-prepare"))
            }
            scenario.recreate()
            scenario.onActivity { weekly = it }
            await(weekly, "health-weekly-refresh-link")
            tap(weekly, "health-weekly-refresh-link")
            await(weekly, "health-weekly-stat-STEPS")
            scenario.onActivity {
                assertEquals(HealthWeeklyText(it).range(scope), text(it, "health-weekly-range"))
                assertNull(view(it, "health-weekly-stat-SLEEP_DURATION"))
                assertNull(view(it, "health-weekly-linked"))
            }
            tap(weekly, "health-weekly-prepare")
            scenario.onActivity {
                assertFalse((view(it, "health-weekly-include-comparison") as CheckBox).isChecked)
            }
        }
    }

    @Test fun exportOptionsCannotSilentlyReplaceAChangedLinkedAnalysis() = fixture { names ->
        val scope = HealthWeeklyScope(date, zone, setOf(HealthMetric.STEPS))
        val (row, stamp) = HealthRecordStore(context, names.records).use { store ->
            save(store, scope.from, "1234") to HealthWeeklyRepository.calculate(store, scope).stamp
        }
        val intent = Intent(context, HealthWeeklyActivity::class.java).putHealthWeeklyHandoff(stamp).putHealthNavigationFixture(names)
        ActivityScenario.launch<HealthWeeklyActivity>(intent).use { scenario ->
            lateinit var weekly: HealthWeeklyActivity
            scenario.onActivity { weekly = it }
            await(weekly, "health-weekly-prepare")
            tap(weekly, "health-weekly-prepare")
            HealthRecordStore(context, names.records).use { store ->
                assertTrue(store.save(row.editable().copy(values = mapOf("steps" to "1250"))) is HealthSaveResult.Saved)
            }
            tap(weekly, "health-weekly-preview-action")
            await(weekly, "health-weekly-review-again")
            scenario.onActivity { assertNull(view(it, "health-weekly-save")) }
            tap(weekly, "health-weekly-review-again")
            await(weekly, "health-weekly-save")
            scenario.onActivity {
                assertEquals(HealthWeeklyText(it).range(scope), text(it, "health-weekly-range"))
                assertFalse(requireNotNull(view(it, "health-weekly-save")).isEnabled)
                assertNull(view(it, "health-weekly-record"))
            }
        }
    }

    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        assumeFalse("Weekly handoff UI requires an unlocked Android 10+ display",
            android.os.Build.VERSION.SDK_INT < 29 || context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun save(store: HealthRecordStore, time: Long, value: String) =
        (store.save(HealthDraft(HealthMetric.STEPS, mapOf("steps" to value), measuredAt = time)) as HealthSaveResult.Saved).record
    private fun views(root: View): List<View> = listOf(root) + if (root is ViewGroup)
        (0 until root.childCount).flatMap { views(root.getChildAt(it)) } else emptyList()
    private fun view(activity: Activity, tag: String) = activity.window.decorView.findViewWithTag<View>(tag)
    private fun text(activity: Activity, tag: String) = (view(activity, tag) as TextView).text.toString()
    private fun tap(activity: Activity, tag: String) = instrumentation.runOnMainSync {
        assertTrue(requireNotNull(view(activity, tag)).performClick())
    }
    private fun <T : Activity> open(type: Class<T>, action: () -> Unit): T {
        val monitor = instrumentation.addMonitor(type.name, null, false)
        try { action(); return type.cast(requireNotNull(instrumentation.waitForMonitorWithTimeout(monitor, 12_000))) }
        finally { instrumentation.removeMonitor(monitor) }
    }
    private fun back(activity: Activity) {
        awaitCondition { activity.hasWindowFocus() }
        instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        instrumentation.waitForIdleSync()
    }
    private fun finish(activity: Activity) = instrumentation.runOnMainSync { if (!activity.isFinishing) activity.finish() }
    private fun await(activity: Activity, tag: String) = awaitCondition(tag) { view(activity, tag) != null }
    private fun awaitCondition(label: String = "window focus", predicate: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 15_000
        do {
            var result = false
            instrumentation.runOnMainSync { result = predicate() }
            if (result) return
            SystemClock.sleep(50)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Weekly handoff did not reach $label")
    }
}
