package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.ListView
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthTrendPointUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val day get() = LocalDate.now().minusDays(1)
    private val time get() = day.atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()

    @Test fun tappingMinimumShowsItsExactPagedContributorsAndReturnsToTheSelectedPoint() = fixture { names ->
        val fixtureDay = day
        val (records, otherUnit, imported) = HealthRecordStore(context, names.records).use { store ->
            val rows = List(34) { n -> save(store, n, if (n == 0) "51" else "${70 + n}") }
            val lb = save(store, 1, "150", "lb")
            val ocr = save(store, 35, "40", evidence = HealthEvidence(id(), id(), "value", "a".repeat(64), 1, "Synthetic", confirmed = true))
            store.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "45"), "kg", time - 60_000L))
            Triple(rows, lb, ocr)
        }
        val intent = Intent(context, HealthTrendActivity::class.java).putExtra("health_metric", HealthMetric.WEIGHT.name)
            .putHealthNavigationFixture(names)
        ActivityScenario.launch<HealthTrendActivity>(intent).use { scenario ->
            lateinit var trend: HealthTrendActivity
            scenario.onActivity { trend = it }
            await(trend) { has(it, "health-trend-latest-record") }
            choose(trend, "health-trend-source", 1)
            await(trend) { has(it, "health-trend-latest-record") }
            choose(trend, "health-trend-aggregation", HealthTrendAggregation.MINIMUM.ordinal)
            await(trend) { has(it, "health-trend-latest-record") &&
                it.window.decorView.findViewWithTag<View>("health-trend-chart").width > 0 }
            val cohort = open(HealthTrendRecordsActivity::class.java) { tapPoint(trend, fixtureDay) }
            try {
                await(cohort) { has(it, "health-trend-audit-result") }
                assertEquals(34, contributorCount(cohort))
                instrumentation.runOnMainSync {
                    assertTrue(text(cohort, "health-trend-audit-result").contains("51 kg"))
                    assertEquals(cohort.getString(R.string.health_source_manual), text(cohort, "health-trend-audit-source"))
                    assertEquals(30, rows(cohort).size)
                    assertFalse(has(cohort, rowTag(otherUnit)))
                    assertFalse(has(cohort, rowTag(imported)))
                    assertFalse(has(cohort, rowTag(records.first())))
                }
                val revision = open(HealthRecordRevisionActivity::class.java) { tap(cohort, "health-trend-audit-extremum") }
                try {
                    await(revision) { has(it, "health-revision-value") }
                    instrumentation.runOnMainSync { assertEquals("51 kg", text(revision, "health-revision-value")) }
                    back(revision)
                } finally { finish(revision) }
                await(cohort) { has(it, "health-trend-records-next") }
                tap(cohort, "health-trend-records-next")
                await(cohort) { has(it, rowTag(records.first())) }
                assertEquals(34, contributorCount(cohort))
                instrumentation.runOnMainSync { assertEquals(4, rows(cohort).size) }
                val oldest = open(HealthRecordRevisionActivity::class.java) { tap(cohort, rowTag(records.first())) }
                try {
                    await(oldest) { has(it, "health-revision-value") }
                    back(oldest)
                } finally { finish(oldest) }
                await(cohort) { has(it, "health-trend-records-previous") && has(it, rowTag(records.first())) }
                back(cohort)
                await(trend) {
                    it.window.decorView.findViewWithTag<View>("health-trend-chart")?.contentDescription?.toString() ==
                        it.getString(R.string.health_trend_point, it.getString(healthFieldResource("weight")), "51", "kg", 34L)
                }
            } finally { finish(cohort) }
        }
    }

    @Test fun changingAContributorInvalidatesTheVisiblePointInsteadOfShowingMixedRevisions() = fixture { names ->
        val spec = HealthTrendSpec(HealthMetric.WEIGHT, day, day, ZoneId.systemDefault(), "kg")
        val (first, version) = HealthRecordStore(context, names.records).use {
            val first = save(it, 0, "51")
            save(it, 1, "71")
            first to it.metricVersion(HealthMetric.WEIGHT)
        }
        val intent = Intent(context, HealthTrendRecordsActivity::class.java).putHealthTrend(spec).putHealthNavigationFixture(names)
            .putExtra("health_numeric", true).putExtra("health_point_field", "weight").putExtra("health_version", version)
        ActivityScenario.launch<HealthTrendRecordsActivity>(intent).use { scenario ->
            lateinit var cohort: HealthTrendRecordsActivity
            scenario.onActivity { cohort = it }
            await(cohort) { has(it, "health-trend-audit-result") && has(it, rowTag(first)) }
            assertEquals(2, contributorCount(cohort))
            HealthRecordStore(context, names.records).use {
                assertTrue(it.save(first.editable().copy(values = mapOf("weight" to "52"))) is HealthSaveResult.Saved)
            }
            await(cohort) { has(it, "health-trend-records-status") }
            scenario.onActivity {
                assertEquals(it.getString(R.string.health_trend_changed), text(it, "health-trend-records-status"))
                assertFalse(has(it, "health-trend-audit-result"))
                assertTrue(rows(it).isEmpty())
            }
        }
    }

    private fun id() = UUID.randomUUID().toString()
    private fun save(store: HealthRecordStore, n: Int, value: String, unit: String = "kg", evidence: HealthEvidence? = null) =
        (store.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to value), unit, time + 1000L + n * 60_000L,
            evidence = evidence)) as HealthSaveResult.Saved).record
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        assumeFalse("Trend chart UI requires an unlocked Android 10+ display",
            android.os.Build.VERSION.SDK_INT < 29 || context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(id())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun rowTag(record: HealthObservation) = "health-trend-record-${record.id}"
    private fun rows(activity: Activity) = descendants(activity.window.decorView)
        .filter { (it.tag as? String)?.startsWith("health-trend-record-") == true }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
    private fun has(activity: Activity, tag: String) = activity.window.decorView.findViewWithTag<View>(tag) != null
    private fun text(activity: Activity, tag: String) = activity.window.decorView.findViewWithTag<TextView>(tag).text.toString()
    private fun contributorCount(activity: Activity): Int {
        var result = -1
        instrumentation.runOnMainSync {
            result = Regex("[0-9]+").find(text(activity, "health-trend-audit-count"))!!.value.toInt()
        }
        return result
    }
    private fun tap(activity: Activity, tag: String) = instrumentation.runOnMainSync {
        assertTrue(activity.window.decorView.findViewWithTag<View>(tag).performClick())
    }
    private fun choose(activity: Activity, tag: String, index: Int) {
        tap(activity, tag)
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            val list = WindowInspector.getGlobalWindowViews().flatMap(::descendants).filterIsInstance<ListView>().last()
            assertTrue(list.performItemClick(list.getChildAt(index), index, list.adapter.getItemId(index)))
        }
    }
    private fun tapPoint(activity: Activity, day: LocalDate) = instrumentation.runOnMainSync {
        val chart = activity.window.decorView.findViewWithTag<HealthTrendChart>("health-trend-chart")
        val target = (0 until chart.width step 4).asSequence().flatMap { x ->
            (0 until chart.height step 4).asSequence().map { y -> x.toFloat() to y.toFloat() }
        }.first { (x, y) -> chart.hit(x, y)?.first == day }
        val now = SystemClock.uptimeMillis()
        for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
            val event = MotionEvent.obtain(now, now, action, target.first, target.second, 0)
            try { assertTrue(chart.dispatchTouchEvent(event)) } finally { event.recycle() }
        }
    }
    private fun <T : Activity> open(type: Class<T>, action: () -> Unit): T {
        val monitor = instrumentation.addMonitor(type.name, null, false)
        try { action(); return type.cast(requireNotNull(instrumentation.waitForMonitorWithTimeout(monitor, 12_000))) }
        finally { instrumentation.removeMonitor(monitor) }
    }
    private fun back(activity: Activity) {
        await(activity) { it.hasWindowFocus() }
        instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        instrumentation.waitForIdleSync()
    }
    private fun finish(activity: Activity) = instrumentation.runOnMainSync { if (!activity.isFinishing) activity.finish() }
    private fun await(activity: Activity, ready: (Activity) -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 15_000
        do {
            var result = false
            instrumentation.runOnMainSync { result = ready(activity) }
            if (result) return
            SystemClock.sleep(50)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Trend point UI did not reach the expected state")
    }
}
