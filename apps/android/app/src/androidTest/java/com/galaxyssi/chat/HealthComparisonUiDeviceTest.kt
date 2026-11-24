package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.time.LocalDate
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthComparisonUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun <T : Activity> await(scenario: ActivityScenario<T>, tag: String, enabled: Boolean = false) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        do {
            var ready = false
            scenario.onActivity { ready = views(it.window.decorView).any { it.tag == tag && (!enabled || it.isEnabled) } }
            if (ready) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("Missing comparison view: $tag")
    }
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { context.deleteDatabase(names.activity); clearHealthOverviewFixture(context, names) }
    }
    @Test fun existingTodayTilesKeepTheirOriginalControlsWithSeparateComparisonEntry() = fixture { names ->
        ActivityScenario.launch<HealthCenterActivity>(Intent(context, HealthCenterActivity::class.java).putHealthNavigationFixture(names)).use { screen ->
            await(screen, "health-activity-comparison")
            screen.onActivity { activity ->
                val all = views(activity.window.decorView)
                val tiles = all.single { it.tag == "health-overview-activity" }
                assertFalse(views(tiles).any { it.tag == "health-activity-comparison" })
                assertEquals("health-overview-date-actions", (all.single { it.tag == "health-activity-comparison" }.parent as View).tag)
                assertTrue(all.any { it.tag == "health-overview-step-goal" })
                assertTrue(all.any { it.tag == "health-overview-cycling" })
                val metrics = all.single { it.tag == "health-overview-metrics" }
                assertTrue(metrics is ViewGroup)
                assertFalse(all.any { it.tag == "health-overview-all-records" })
            }
        }
    }
    @Test fun activityComparisonLoadsAndClearsDecryptedViewsInBackground() = fixture { names ->
        HealthActivityHistoryStore(context, names.activity).use { store ->
            repeat(35) { day ->
                val date = LocalDate.now().minusDays(day.toLong())
                if (day != 5) store.save(HealthActivityKind.STEPS, date, 2500L + (day % 6) * 700L)
                store.save(HealthActivityKind.CYCLING, date, 600_000L + (day % 4) * 300_000L)
            }
        }
        ActivityScenario.launch<HealthActivityComparisonActivity>(Intent(context, HealthActivityComparisonActivity::class.java).putHealthNavigationFixture(names)).use { screen ->
            await(screen, "health-activity-chart")
            instrumentation.waitForIdleSync()
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                File(context.getExternalFilesDir(null), "health-activity-comparison-test.png").outputStream().use {
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                }; bitmap.recycle()
            }
            screen.moveToState(Lifecycle.State.CREATED)
            screen.onActivity { activity -> assertFalse(views(activity.window.decorView).any { it.tag == "health-activity-chart" }) }
            screen.moveToState(Lifecycle.State.RESUMED); await(screen, "health-activity-chart")
        }
    }
    @Test fun activityPresetsIncludeTodayAndBothKindsUseTheCompactLayout() = fixture { names ->
        HealthActivityHistoryStore(context, names.activity).use { store ->
            store.save(HealthActivityKind.STEPS, LocalDate.now(), 1234)
            store.save(HealthActivityKind.CYCLING, LocalDate.now(), 5_400_000)
        }
        ActivityScenario.launch<HealthActivityComparisonActivity>(Intent(context, HealthActivityComparisonActivity::class.java)
            .putHealthNavigationFixture(names)).use { screen ->
            listOf(R.string.health_trend_7, R.string.health_trend_30, R.string.health_trend_90).forEach { preset ->
                await(screen, "health-activity-chart")
                screen.onActivity { activity -> views(activity.window.decorView).filterIsInstance<TextView>()
                    .single { it.text.toString() == activity.getString(preset) }.performClick() }
                await(screen, "health-activity-chart")
                screen.onActivity { activity ->
                    val all = views(activity.window.decorView)
                    val total = all.single { it.tag == "health-activity-total" } as TextView
                    assertEquals(java.text.NumberFormat.getIntegerInstance().format(1234) + " " + activity.getString(R.string.health_activity_steps_unit), total.text.toString())
                    assertCompactActivityLayout(activity, all)
                }
            }
            screen.onActivity { activity -> views(activity.window.decorView).filterIsInstance<TextView>()
                .single { it.text.toString() == activity.getString(R.string.health_cycling_today) }.performClick() }
            await(screen, "health-activity-chart")
            screen.onActivity { activity ->
                val all = views(activity.window.decorView)
                val total = all.single { it.tag == "health-activity-total" } as TextView
                assertEquals("90 " + activity.getString(R.string.health_activity_minutes), total.text.toString())
                assertCompactActivityLayout(activity, all)
            }
            screen.recreate(); await(screen, "health-activity-chart")
            screen.onActivity { activity ->
                val total = views(activity.window.decorView).single { it.tag == "health-activity-total" } as TextView
                assertEquals("90 " + activity.getString(R.string.health_activity_minutes), total.text.toString())
            }
        }
    }
    @Test fun emptyActivityHistoryShowsUnknownInsteadOfZeroForBothKinds() = fixture { names ->
        ActivityScenario.launch<HealthActivityComparisonActivity>(Intent(context, HealthActivityComparisonActivity::class.java)
            .putHealthNavigationFixture(names)).use { screen ->
            listOf(R.string.health_overview_today_steps, R.string.health_cycling_today).forEach { label ->
                await(screen, "health-activity-chart")
                screen.onActivity { activity -> views(activity.window.decorView).filterIsInstance<TextView>()
                    .single { it.text.toString() == activity.getString(label) }.performClick() }
                await(screen, "health-activity-chart")
                screen.onActivity { activity -> assertEquals("\u2014", (views(activity.window.decorView)
                    .single { it.tag == "health-activity-total" } as TextView).text.toString()) }
            }
        }
    }
    @Test fun chartTapsShowOneRecordedDayAndBlankTapsClearTheSelection() = fixture { names ->
        val today = LocalDate.now()
        HealthActivityHistoryStore(context, names.activity).use { store ->
            listOf(1_600L, 2_430L, 5_300L, 3_100L, 950L, 8_150L, 4_200L).forEachIndexed { index, steps ->
                store.save(HealthActivityKind.STEPS, today.minusDays(6L - index), steps)
            }
            listOf(0L to 99L, 3L to 0L, 5L to 45L, 6L to 60L, 7L to 300L, 8L to 200L)
                .forEach { (daysAgo, minutes) ->
                    store.save(HealthActivityKind.CYCLING, today.minusDays(daysAgo), minutes * 60_000)
                }
        }
        ActivityScenario.launch<HealthActivityComparisonActivity>(Intent(context, HealthActivityComparisonActivity::class.java)
            .putHealthNavigationFixture(names)).use { screen ->
            await(screen, "health-activity-chart")
            screen.onActivity { activity ->
                val chart = views(activity.window.decorView).single { it.tag == "health-activity-chart" }
                assertTrue(chart.performClick())
                assertTrue(chart.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD, null))
                assertTrue(chart.contentDescription.toString()
                    .endsWith(healthActivityAmount(activity, HealthActivityKind.STEPS, 8_150L)))
            }
            capturePointPreview("health-steps-point-fixture.png")
            screen.onActivity { activity ->
                views(activity.window.decorView).filterIsInstance<TextView>()
                    .single { it.text.toString() == activity.getString(R.string.health_cycling_today) }.performClick()
            }
            await(screen, "health-activity-chart")
            instrumentation.waitForIdleSync()
            screen.onActivity { activity ->
                val chart = views(activity.window.decorView).single { it.tag == "health-activity-chart" }
                val bitmap = Bitmap.createBitmap(chart.width, chart.height, Bitmap.Config.ARGB_8888)
                try {
                    chart.draw(Canvas(bitmap))
                    val green = activity.getColor(R.color.health_overview_green)
                    var blueCount = 0
                    var highestPoint = bitmap.height
                    val columns = bitmap.width.let { width ->
                        val pixels = IntArray(width * bitmap.height)
                        bitmap.getPixels(pixels, 0, width, 0, 0, width, bitmap.height)
                        BooleanArray(width).apply {
                            pixels.forEachIndexed { index, color ->
                                if (color == green) {
                                    this[index % width] = true
                                    highestPoint = minOf(highestPoint, index / width)
                                }
                                if (color == HealthTrendChart.BLUE) blueCount++
                            }
                        }
                    }
                    val from = columns.indexOfFirst { it }
                    val to = columns.indexOfLast { it }
                    assertTrue("Expected data at both ends of the selected week", from >= 0 && to - from > chart.width / 2)
                    assertEquals("A previous-period line must not be drawn", 0, blueCount)
                    assertTrue("The selected range must determine the vertical scale", highestPoint < chart.height / 4)
                    assertFalse("An unrecorded date must not be plotted", columns[from + (to - from) / 3])
                    assertTrue("A recorded zero remains visible", columns[from + (to - from) / 2])

                    fun tapPoint(x: Int) {
                        val y = (0 until bitmap.height).first { bitmap.getPixel(x, it) == green }
                        tapAt(x.toFloat(), y.toFloat(), chart::dispatchTouchEvent)
                    }
                    val zeroX = (from + to) / 2
                    tapPoint(zeroX)
                    val zero = healthActivityAmount(activity, HealthActivityKind.CYCLING, 0)
                    assertTrue(chart.contentDescription.toString().endsWith(zero))
                    tapPoint(from + (activity.resources.displayMetrics.density * 2).toInt())
                    val sixty = healthActivityAmount(activity, HealthActivityKind.CYCLING, 3_600_000)
                    assertTrue(chart.contentDescription.toString().endsWith(sixty))
                    val guideX = from + (activity.resources.displayMetrics.density * 2.5f).toInt()
                    val guideY = bitmap.height / 4
                    val guideColumns = (guideX - 4).coerceAtLeast(0)..(guideX + 4).coerceAtMost(bitmap.width - 1)
                    val beforeGuide = guideColumns.map { bitmap.getPixel(it, guideY) }
                    bitmap.eraseColor(0)
                    chart.draw(Canvas(bitmap))
                    assertNotEquals("The selection must draw a vertical guide", beforeGuide,
                        guideColumns.map { bitmap.getPixel(it, guideY) })
                } finally { bitmap.recycle() }
            }
            capturePointPreview("health-cycling-point-fixture.png")
            screen.onActivity { activity ->
                val chart = views(activity.window.decorView).single { it.tag == "health-activity-chart" }
                tapAt(chart.width / 2f, 0f, chart::dispatchTouchEvent)
                assertEquals(activity.getString(R.string.health_trend_chart_data), chart.contentDescription)
                chart.performClick()
                val position = IntArray(2)
                chart.getLocationOnScreen(position)
                tapAt(position[0] + chart.width / 2f, position[1] + chart.height + 18f, activity::dispatchTouchEvent)
                assertEquals(activity.getString(R.string.health_trend_chart_data), chart.contentDescription)
            }
        }
    }
    private fun tapAt(x: Float, y: Float, dispatch: (MotionEvent) -> Boolean) {
        val time = SystemClock.uptimeMillis()
        listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP).forEach { action ->
            val event = MotionEvent.obtain(time, time, action, x, y, 0)
            try { dispatch(event) } finally { event.recycle() }
        }
    }
    private fun capturePointPreview(name: String) {
        if (InstrumentationRegistry.getArguments().getString("preview") != "true") return
        instrumentation.waitForIdleSync()
        SystemClock.sleep(250)
        instrumentation.uiAutomation.takeScreenshot()?.let { screenshot ->
            try {
                File(context.getExternalFilesDir(null), name).outputStream().use {
                    screenshot.compress(Bitmap.CompressFormat.PNG, 100, it)
                }
            } finally { screenshot.recycle() }
        }
    }
    private fun assertCompactActivityLayout(activity: Activity, all: List<View>) {
        val texts = all.filterIsInstance<TextView>().map { it.text.toString() }
        listOf(R.string.health_activity_current, R.string.health_activity_previous, R.string.health_activity_missing,
            R.string.health_trend_chart_data).forEach { assertFalse(texts.contains(activity.getString(it))) }
        assertFalse(texts.any { Regex(".*\\d{4}-\\d{2}-\\d{2}.*").matches(it) })
        assertTrue(all.single { it.tag == "health-activity-chart" }.isClickable)
    }
    @Test fun emptyPeriodComparisonDoesNotShowInventedMeasurements() = fixture { names ->
        ActivityScenario.launch<HealthMeasurementPeriodsActivity>(Intent(context, HealthMeasurementPeriodsActivity::class.java)
            .putHealthNavigationFixture(names)).use { screen ->
            val deadline = SystemClock.elapsedRealtime() + 15_000
            var found = false
            do {
                screen.onActivity { activity -> found = views(activity.window.decorView).filterIsInstance<TextView>().any {
                    it.text.toString() == activity.getString(R.string.health_no_records)
                } }
                if (!found) SystemClock.sleep(40)
            } while (!found && SystemClock.elapsedRealtime() < deadline)
            assertTrue(found)
        }
    }
    @Test fun twoSamplingPeriodsUseSeparateColumnsOrStackAtNarrowWidths() = fixture { names ->
        val now = System.currentTimeMillis()
        val reports = HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            (0..1).map { index ->
                val job = HealthImportJob(UUID.randomUUID().toString(), "content://health.test/ui-$index", now - 2000 + index,
                    name = "synthetic-$index.pdf")
                originals.createJob(job)
                job to originals.importOriginal(job.id, "synthetic report $index".byteInputStream(), job.name, "application/pdf", "file")
            }
        }
        val period = HealthMeasurementPeriod.of(HealthMeasurementPeriodKind.WEEK, LocalDate.now())
        val sampleTimes = listOf(period.first, period.first.minusDays(1)).map {
            it.atStartOfDay(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
        }
        HealthRecordStore(context, names.records).use { records ->
            reports.forEachIndexed { index, (job, original) ->
                assertTrue(records.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to if (index == 0) "5.1" else "6.3"),
                    "mmol/L", sampleTimes[index], "fasting", reference = "4-6",
                    evidence = HealthEvidence(original.id, job.id, "glucose", original.sha256, 1, "synthetic", confirmed = true))) is HealthSaveResult.Saved)
            }
        }
        ActivityScenario.launch<HealthMeasurementPeriodsActivity>(Intent(context, HealthMeasurementPeriodsActivity::class.java)
            .putHealthNavigationFixture(names).putExtra("health_period", period.key)).use { screen ->
            val deadline = SystemClock.elapsedRealtime() + 15_000
            var ready = false
            do {
                screen.onActivity { activity -> ready = views(activity.window.decorView).filterIsInstance<TextView>().any { it.text.toString() == "B" } }
                if (!ready) SystemClock.sleep(40)
            } while (!ready && SystemClock.elapsedRealtime() < deadline)
            assertTrue(ready); instrumentation.waitForIdleSync()
            screen.onActivity { activity ->
                val all = views(activity.window.decorView).filterIsInstance<TextView>()
                val a = all.single { it.text.toString() == "A" }; val b = all.single { it.text.toString() == "B" }
                val ap = IntArray(2); val bp = IntArray(2); a.getLocationOnScreen(ap); b.getLocationOnScreen(bp)
                val stack = activity.resources.configuration.fontScale >= 1.3f || activity.resources.configuration.screenWidthDp < 344
                if (stack) assertTrue(ap[1] < bp[1]) else { assertTrue(ap[0] < bp[0]); assertEquals(ap[1], bp[1]) }
            }
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                File(context.getExternalFilesDir(null), "health-period-comparison-test.png").outputStream().use {
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                }; bitmap.recycle()
            }
        }
    }
    @Test fun hiddenMetricsAppendToTheSameListAndRestoreAfterOpeningDetails() = fixture { names ->
        val now = System.currentTimeMillis()
        HealthRecordStore(context, names.records).use { store ->
            repeat(65) { index -> store.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "70"), "kg", now - index * 60_000L)) }
            store.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"), "mmol/L", now - 1000, "fasting", reference = "4-6"))
            store.save(HealthDraft(HealthMetric.LDL, mapOf("ldl" to "3.45"), "mmol/L", now - 2000, reference = "<3.37"))
            store.save(HealthDraft(HealthMetric.HDL, mapOf("hdl" to "1.12"), "mmol/L", now - 2000, reference = ">1.03"))
            store.save(HealthDraft(HealthMetric.TRIGLYCERIDES, mapOf("triglycerides" to "1.68"), "mmol/L", now - 2000, reference = "<1.70"))
            store.save(HealthDraft(values = mapOf("systolic" to "119", "diastolic" to "77"), measuredAt = now - 2000))
        }
        ActivityScenario.launch<HealthCenterActivity>(Intent(context, HealthCenterActivity::class.java).putHealthNavigationFixture(names)).use { screen ->
            await(screen, "health-overview-all-records")
            instrumentation.waitForIdleSync(); SystemClock.sleep(150)
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                File(context.getExternalFilesDir(null), "health-period-overview-test.png").outputStream().use {
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                }; bitmap.recycle()
            }
            screen.onActivity { activity -> views(activity.window.decorView).single { it.tag == "health-overview-all-records" }.performClick() }
            var expandedTags = emptyList<Any?>()
            screen.onActivity { activity ->
                val all = views(activity.window.decorView)
                val metrics = all.single { it.tag == "health-overview-metrics" } as ViewGroup
                val rows = (0 until metrics.childCount).map { metrics.getChildAt(it) }.filter { it.isClickable }
                expandedTags = rows.map { it.tag }
                assertTrue(rows.size > 5); assertEquals(rows.size, expandedTags.distinct().size)
                assertFalse(all.any { it.tag == "health-overview-expanded-records" })
                assertEquals(1, rows.count { it.tag.toString().startsWith("health-overview-WEIGHT-") })
                assertTrue(all.any { it.tag == "health-overview-activity" })
                rows.single { it.tag.toString().startsWith("health-overview-WEIGHT-") }.performClick()
                activity.onBackPressed()
            }
            await(screen, "health-overview-all-records")
            screen.onActivity { activity ->
                val all = views(activity.window.decorView)
                val metrics = all.single { it.tag == "health-overview-metrics" } as ViewGroup
                val returned = (0 until metrics.childCount).map { metrics.getChildAt(it) }.filter { it.isClickable }
                assertEquals(expandedTags, returned.map { it.tag })
                assertTrue(activity.measurementRecordsExpanded)
                all.single { it.tag == "health-overview-all-records" }.performClick()
                assertEquals(5, (0 until metrics.childCount).count { metrics.getChildAt(it).isClickable })
                assertFalse(activity.measurementRecordsExpanded)
            }
        }
        HealthRecordStore(context, names.records).use { store ->
            val ids = mutableSetOf<String>(); var cursor: HealthPageCursor? = null
            do {
                val page = store.careHistory(now + 1, HealthMetric.WEIGHT, cursor)
                ids += page.records.map { it.id }; cursor = page.next
            } while (cursor != null)
            assertEquals(65, ids.size)
        }
    }
    @Test fun selectedSamplingMonthAndAbnormalFilterRemainOnTheOverview() = fixture { names ->
        val now = System.currentTimeMillis(); val day = LocalDate.now()
        HealthRecordStore(context, names.records).use { store ->
            store.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"), "mmol/L", now - 1000, "fasting", reference = "4-6"))
            store.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "70"), "kg", now - 2000))
        }
        ActivityScenario.launch<HealthCenterActivity>(Intent(context, HealthCenterActivity::class.java).putHealthNavigationFixture(names)).use { screen ->
            await(screen, "health-overview-metrics")
            screen.onActivity { it.setMeasurementPeriod(HealthMeasurementPeriod.of(HealthMeasurementPeriodKind.MONTH, day)) }
            await(screen, "health-overview-metrics", enabled = true)
            screen.onActivity { (views(it.window.decorView).single { v -> v.tag == "health-measurement-abnormal-filter" } as android.widget.CheckBox).isChecked = true }
            await(screen, "health-overview-metrics")
            screen.onActivity { activity ->
                assertEquals(HealthMeasurementPeriodKind.MONTH, activity.measurementPeriod?.kind)
                val metricList = views(activity.window.decorView).single { it.tag == "health-overview-metrics" }
                assertTrue(views(metricList).any { it.tag?.toString()?.startsWith("health-overview-GLUCOSE-") == true })
                assertFalse(views(metricList).any { it.tag?.toString()?.startsWith("health-overview-WEIGHT-") == true })
            }
        }
    }
    @Test fun abnormalFilterNeverIncludesTheNormalLatestValueFromAnEarlierAbnormalSeries() = fixture { names ->
        val now = System.currentTimeMillis()
        HealthRecordStore(context, names.records).use { store ->
            store.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"), "mmol/L", now - 2000, "fasting", reference = "4-6"))
            store.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "5.1"), "mmol/L", now - 1000, "fasting", reference = "4-6"))
            store.save(HealthDraft(HealthMetric.LDL, mapOf("ldl" to "3.45"), "mmol/L", now - 1000, reference = "<3.37"))
            store.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "70"), "kg", now - 1000))
        }
        ActivityScenario.launch<HealthCenterActivity>(Intent(context, HealthCenterActivity::class.java).putHealthNavigationFixture(names)).use { screen ->
            await(screen, "health-overview-metrics")
            screen.onActivity { it.setMeasurementPeriod(HealthMeasurementPeriod.of(HealthMeasurementPeriodKind.MONTH, LocalDate.now())) }
            await(screen, "health-overview-metrics", enabled = true)
            screen.onActivity { activity ->
                assertTrue((views(activity.window.decorView).single { it.tag == "health-overview-value-GLUCOSE" } as TextView).text.contains("5.1"))
                activity.filterMeasurementAbnormal(true)
            }
            await(screen, "health-overview-metrics")
            fun assertOnlyLdl() = screen.onActivity { activity ->
                val all = views(activity.window.decorView)
                val metrics = all.single { it.tag == "health-overview-metrics" } as ViewGroup
                val rows = (0 until metrics.childCount).map { metrics.getChildAt(it) }.filter { it.isClickable }
                assertEquals(1, rows.size); assertTrue(rows.single().tag.toString().startsWith("health-overview-LDL-"))
                assertFalse(all.any { it.tag == "health-overview-all-records" })
                assertFalse(all.any { it.tag == "health-overview-value-GLUCOSE" || it.tag == "health-overview-value-WEIGHT" })
            }
            assertOnlyLdl()
            screen.recreate(); await(screen, "health-overview-metrics"); assertOnlyLdl()
            screen.moveToState(Lifecycle.State.CREATED)
            screen.onActivity { assertEquals(0, it.body.childCount) }
            screen.moveToState(Lifecycle.State.RESUMED); await(screen, "health-overview-metrics"); assertOnlyLdl()
        }
        HealthRecordStore(context, names.records).use { assertEquals(2, it.recentSelf(now + 1, 10, HealthMetric.GLUCOSE).size) }
    }
}
