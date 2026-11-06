package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
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

    @Test fun accessibleListSeparatesPressureComponentsAndOpensTheExactFilteredRecord() = fixture { names ->
        val first = HealthRecordStore(context, names.records).use { store ->
            fun pressure(systolic: String, diastolic: String, at: Long, evidence: HealthEvidence? = null) =
                (store.save(HealthDraft(HealthMetric.BLOOD_PRESSURE, mapOf("systolic" to systolic, "diastolic" to diastolic),
                    "mmHg", at, evidence = evidence)) as HealthSaveResult.Saved).record
            pressure("125", "75", time - 86_400_000L + 1000)
            val wanted = pressure("120", "80", time + 1000)
            pressure("143", "93", time + 60_000, HealthEvidence(id(), id(), "value", "a".repeat(64), 1, "Synthetic", confirmed = true))
            wanted
        }
        val intent = Intent(context, HealthTrendActivity::class.java).putExtra("health_metric", HealthMetric.BLOOD_PRESSURE.name)
            .putHealthNavigationFixture(names)
        ActivityScenario.launch<HealthTrendActivity>(intent).use { scenario ->
            lateinit var trend: HealthTrendActivity
            scenario.onActivity { trend = it }
            await(trend) { has(it, "health-trend-chart-data") }
            choose(trend, "health-trend-source", 1)
            await(trend) { has(it, "health-trend-chart-data") }
            scenario.onActivity {
                val chart = it.window.decorView.findViewWithTag<View>("health-trend-chart")
                val info = chart.createAccessibilityNodeInfo()
                assertTrue(info.actionList.any { action -> action.id == AccessibilityNodeInfo.ACTION_CLICK &&
                    action.label == it.getString(R.string.health_trend_chart_data) })
                assertTrue(chart.performAccessibilityAction(AccessibilityNodeInfo.ACTION_CLICK, null))
            }
            instrumentation.waitForIdleSync()
            val labels = chartLabels()
            assertEquals(4, labels.size)
            assertTrue(labels[0].contains("120 mmHg") && labels[1].contains("80 mmHg"))
            assertTrue(labels[2].contains("125 mmHg") && labels[3].contains("75 mmHg"))
            assertTrue(labels.all { it.contains(trend.getString(R.string.health_trend_mean)) })
            assertTrue(labels[0].contains(trend.getString(R.string.health_systolic)))
            assertTrue(labels[1].contains(trend.getString(R.string.health_diastolic)))
            if (InstrumentationRegistry.getArguments().getString("trendPointListScreenshot") == "true") {
                await(trend) { chartList()?.let { list -> list.hasWindowFocus() && list.childCount > 0 } == true }
                instrumentation.uiAutomation.waitForIdle(250, 3_000)
                val screenshot = instrumentation.uiAutomation.takeScreenshot()
                checkNotNull(screenshot)
                try {
                    context.cacheDir.resolve("health-trend-point-list.png").outputStream().use {
                        assertTrue(screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it))
                    }
                } finally { screenshot.recycle() }
            }
            val revision = open(HealthRecordRevisionActivity::class.java) {
                instrumentation.runOnMainSync {
                    val list = requireNotNull(chartList())
                    assertTrue(list.performItemClick(list.getChildAt(1), 1, list.adapter.getItemId(1)))
                }
            }
            try {
                assertEquals(first.id, revision.intent.getStringExtra("health_record"))
                assertEquals(first.revision, revision.intent.getIntExtra("health_revision", 0))
                await(revision) { has(it, "health-revision-value") }
                back(revision)
                await(trend) { has(it, "health-trend-chart-data") }
                assertTrue(chartLabels().isEmpty())
            } finally { finish(revision) }
        }
    }

    @Test fun changedSnapshotClosesThePointListAndRequiresRefreshBeforeOpeningItAgain() = fixture { names ->
        val record = HealthRecordStore(context, names.records).use { save(it, 0, "51") }
        val intent = Intent(context, HealthTrendActivity::class.java).putExtra("health_metric", HealthMetric.WEIGHT.name)
            .putHealthNavigationFixture(names)
        ActivityScenario.launch<HealthTrendActivity>(intent).use { scenario ->
            lateinit var trend: HealthTrendActivity
            scenario.onActivity { trend = it }
            await(trend) { has(it, "health-trend-chart-data") }
            tap(trend, "health-trend-chart-data")
            assertTrue(chartLabels().single().contains("51 kg"))
            HealthRecordStore(context, names.records).use {
                assertTrue(it.save(record.editable().copy(values = mapOf("weight" to "52"))) is HealthSaveResult.Saved)
            }
            await(trend) { it.window.decorView.findViewWithTag<View>("health-trend-chart-data").visibility == View.GONE }
            assertTrue(chartLabels().isEmpty())
            scenario.onActivity {
                val chart = it.window.decorView.findViewWithTag<View>("health-trend-chart")
                assertFalse(chart.performAccessibilityAction(AccessibilityNodeInfo.ACTION_CLICK, null))
            }
            tap(trend, "health-trend-refresh")
            await(trend) { it.window.decorView.findViewWithTag<View>("health-trend-chart-data")?.visibility == View.VISIBLE }
            tap(trend, "health-trend-chart-data")
            assertTrue(chartLabels().single().contains("52 kg"))
        }
    }

    @Test fun sameNameBluetoothDevicesCanBeSelectedIndependentlyAndOnlyTheirRowsAreAudited() = fixture { names ->
        val date = day
        val (first, second, other) = HealthRecordStore(context, names.records).use { store ->
            fun save(device: String, timestamp: Long) =
                (store.saveBluetooth(healthTrendPressure(device, timestamp), "resting") {} as HealthSaveResult.Saved).record
            Triple(save("device-a", time + 60_000), save("device-a", time + 120_000), save("device-b", time + 60_000))
        }
        val intent = Intent(context, HealthTrendActivity::class.java).putExtra("health_metric", HealthMetric.BLOOD_PRESSURE.name)
            .putHealthNavigationFixture(names)
        ActivityScenario.launch<HealthTrendActivity>(intent).use { scenario ->
            lateinit var trend: HealthTrendActivity
            scenario.onActivity { trend = it }
            await(trend) { has(it, "health-trend-latest-record") }
            choose(trend, "health-trend-source", 3)
            val expected = trend.healthBluetoothTrendLabel(first.bluetoothGroup, first.platformOrigin)
            val excluded = trend.healthBluetoothTrendLabel(other.bluetoothGroup, other.platformOrigin)
            chooseSourceLabel(expected, excluded)
            await(trend) { has(it, "health-trend-latest-record") && it.window.decorView.findViewWithTag<View>("health-trend-chart").width > 0 &&
                descendants(it.window.decorView.findViewWithTag<View>("health-trend-source")).filterIsInstance<TextView>().any { label ->
                    label.text.toString() == expected
                } }
            val cohort = open(HealthTrendRecordsActivity::class.java) { tapPoint(trend, date) }
            try {
                await(cohort) { has(it, "health-trend-audit-result") }
                assertEquals(2, contributorCount(cohort))
                instrumentation.runOnMainSync {
                    assertEquals(expected, text(cohort, "health-trend-audit-source"))
                    assertTrue(has(cohort, rowTag(first)))
                    assertTrue(has(cohort, rowTag(second)))
                    assertFalse(has(cohort, rowTag(other)))
                }
                val revision = open(HealthRecordRevisionActivity::class.java) { tap(cohort, rowTag(first)) }
                try {
                    await(revision) { has(it, "health-revision-device") }
                    instrumentation.runOnMainSync { assertEquals(expected, text(revision, "health-revision-device")) }
                    back(revision)
                } finally { finish(revision) }
                await(cohort) { has(it, rowTag(first)) }
                back(cohort)
                await(trend) { has(it, "health-trend-latest-record") }
            } finally { finish(cohort) }
        }
    }

    @Test fun healthConnectFilterShowsOnlyTheSelectedApplicationAndItsRevisionSource() = fixture { names ->
        val date = day
        val origin = "com.fixture.first"
        val other = "com.fixture.second"
        val (wanted, excluded) = HealthRecordStore(context, names.records).use { store ->
            val entries = listOf(origin, origin, other).mapIndexed { index, app ->
                HealthConnectMeasurement("sample-$index", app, HealthDraft(HealthMetric.WEIGHT,
                    mapOf("weight" to "${65 + index}"), "kg", time + (index + 1) * 60_000L))
            }
            assertEquals(3, store.importHealthConnect(entries) {})
            val page = store.page(metric = HealthMetric.WEIGHT).records
            page.first { it.platformOrigin == origin } to page.first { it.platformOrigin == other }
        }
        val intent = Intent(context, HealthTrendActivity::class.java).putExtra("health_metric", HealthMetric.WEIGHT.name)
            .putHealthNavigationFixture(names)
        ActivityScenario.launch<HealthTrendActivity>(intent).use { scenario ->
            lateinit var trend: HealthTrendActivity
            scenario.onActivity { trend = it }
            await(trend) { has(it, "health-trend-latest-record") }
            choose(trend, "health-trend-source", 4)
            val expected = trend.healthConnectTrendLabel(origin, HealthMetric.WEIGHT)
            chooseSourceLabel(expected, trend.healthConnectTrendLabel(other, HealthMetric.WEIGHT))
            await(trend) { has(it, "health-trend-latest-record") && it.window.decorView.findViewWithTag<View>("health-trend-chart").width > 0 &&
                descendants(it.window.decorView.findViewWithTag<View>("health-trend-source")).filterIsInstance<TextView>().any { label ->
                    label.text.toString() == expected
                } }
            val cohort = open(HealthTrendRecordsActivity::class.java) { tapPoint(trend, date) }
            try {
                await(cohort) { has(it, "health-trend-audit-result") }
                assertEquals(2, contributorCount(cohort))
                instrumentation.runOnMainSync {
                    assertEquals(expected, text(cohort, "health-trend-audit-source"))
                    assertTrue(has(cohort, rowTag(wanted)))
                    assertFalse(has(cohort, rowTag(excluded)))
                }
                val revision = open(HealthRecordRevisionActivity::class.java) { tap(cohort, rowTag(wanted)) }
                try {
                    await(revision) { has(it, "health-revision-platform") }
                    instrumentation.runOnMainSync { assertEquals(expected, text(revision, "health-revision-platform")) }
                    back(revision)
                } finally { finish(revision) }
                await(cohort) { has(it, rowTag(wanted)) }
                back(cohort)
                await(trend) { has(it, "health-trend-latest-record") }
            } finally { finish(cohort) }
        }
    }

    private fun chooseSourceLabel(expected: String, other: String) {
        val end = SystemClock.elapsedRealtime() + 12_000
        var selected = false
        do {
            instrumentation.runOnMainSync {
                val list = WindowInspector.getGlobalWindowViews().flatMap(::descendants).filterIsInstance<ListView>().lastOrNull()
                if (list != null) {
                    val choices = (0 until list.count).map { list.adapter.getItem(it).toString() }
                    if (expected in choices && other in choices) {
                        val index = choices.indexOf(expected)
                        selected = list.performItemClick(list.getChildAt(index), index, list.adapter.getItemId(index))
                    }
                }
            }
            if (!selected) SystemClock.sleep(50)
        } while (!selected && SystemClock.elapsedRealtime() < end)
        assertTrue("Both sources should be selectable", selected)
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
    private fun chartList(): ListView? =
        WindowInspector.getGlobalWindowViews().flatMap(::descendants).filterIsInstance<ListView>().lastOrNull()
    private fun chartLabels(): List<String> {
        var labels = emptyList<String>()
        instrumentation.runOnMainSync {
            chartList()?.let { list -> labels = (0 until list.count).map { list.adapter.getItem(it).toString() } }
        }
        return labels
    }
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
