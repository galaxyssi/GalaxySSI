package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthMeasurementSelectionUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun find(activity: HealthCenterActivity, tag: String) = views(activity.body).singleOrNull { it.tag == tag }
    private fun field(activity: HealthCenterActivity, name: String) = HealthCenterActivity::class.java.getDeclaredField(name)
        .apply { isAccessible = true }.get(activity)
    private fun generation(activity: HealthCenterActivity) = field(activity, "generation") as Int
    private fun worker(activity: HealthCenterActivity) = field(activity, "worker") as ExecutorService
    private fun await(screen: ActivityScenario<HealthCenterActivity>, ready: (HealthCenterActivity) -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 15_000
        do {
            var found = false
            screen.onActivity { found = ready(it) }
            if (found) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Measurement selection did not finish updating")
    }
    private fun fixture(test: (HealthOverviewDatabases, HealthMeasurementPeriod, HealthMetric) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        val previous = HealthMeasurementPeriod.of(HealthMeasurementPeriodKind.MONTH, LocalDate.now()).previous()
        val metrics = HealthMetric.entries.filter { it.form == HealthResultForm.LABORATORY }.take(15)
        val now = System.currentTimeMillis()
        val earlier = previous.first.plusDays(10).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        try {
            HealthRecordStore(context, names.records).use { store -> metrics.forEach { metric ->
                listOf(earlier to "7", now - 1000 to "5").forEach { (time, value) ->
                    assertTrue(store.save(HealthDraft(metric, mapOf(metric.fields.single() to value), metric.units.first(),
                        time, reference = "4-6")) is HealthSaveResult.Saved)
                }
            } }
            test(names, previous, metrics.first())
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun screen(names: HealthOverviewDatabases, test: (ActivityScenario<HealthCenterActivity>) -> Unit) {
        ActivityScenario.launch<HealthCenterActivity>(Intent(context, HealthCenterActivity::class.java).putHealthNavigationFixture(names)).use {
            await(it) { activity -> find(activity, "health-overview-metrics") != null }
            test(it)
        }
    }
    private fun captureViews(activity: HealthCenterActivity) = listOf("health-overview-scroll", "health-overview-activity",
        "health-overview-value-STEPS", "health-overview-cycling", "health-overview-bottom-actions",
        "health-measurement-period-filter", "health-measurement-abnormal-filter", "health-overview-metrics")
        .associateWith { requireNotNull(find(activity, it)) }
    private fun stable(activity: HealthCenterActivity, original: Map<String, View>, token: Int) {
        assertEquals(token, generation(activity))
        original.forEach { (tag, view) -> assertSame("Rebuilt $tag", view, find(activity, tag)) }
        assertFalse(views(activity.body).filterIsInstance<TextView>().any { it.text.toString() == activity.getString(R.string.health_loading) })
    }
    private fun withBusyWorker(screen: ActivityScenario<HealthCenterActivity>, test: (CountDownLatch) -> Unit) {
        val entered = CountDownLatch(1); val release = CountDownLatch(1)
        screen.onActivity { worker(it).execute { entered.countDown(); release.await(15, TimeUnit.SECONDS) } }
        try { assertTrue(entered.await(3, TimeUnit.SECONDS)); test(release) } finally { release.countDown() }
    }
    private fun capture(name: String) {
        instrumentation.waitForIdleSync()
        instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
            File(context.getExternalFilesDir(null), "$name.png").outputStream().use {
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }; bitmap.recycle()
        }
    }

    @Test fun compactSelectorAndReselectingLatestDoNotReloadEvenWithABusyWorker() = fixture { names, _, _ ->
        screen(names) { screen -> withBusyWorker(screen) {
            screen.onActivity { activity ->
                val original = captureViews(activity); val token = generation(activity)
                val selector = original.getValue("health-measurement-period-filter") as TextView
                val params = selector.layoutParams as LinearLayout.LayoutParams
                assertEquals(ViewGroup.LayoutParams.WRAP_CONTENT, params.width); assertEquals(0f, params.weight, 0f)
                val expected = kotlin.math.ceil(selector.paint.measureText(selector.text.toString()).toDouble()).toInt()
                    .plus(selector.paddingLeft + selector.paddingRight).coerceIn(selector.minWidth, selector.maxWidth)
                assertTrue(kotlin.math.abs(selector.width - expected) <= activity.ui.dp(2))
                repeat(3) {
                    selector.performClick()
                    val dialog = (field(activity, "sensitiveDialogs") as Set<*>).filterIsInstance<AlertDialog>().last { it.isShowing }
                    dialog.listView.performItemClick(null, 0, 0)
                    stable(activity, original, token)
                    assertTrue(original.getValue("health-overview-metrics").isEnabled)
                }
            }
            capture("health-period-latest")
        } }
    }

    @Test fun changingSamplingMonthUpdatesOnlyMeasurementsAndKeepsScroll() = fixture { names, period, metric ->
        screen(names) { screen ->
            var original = emptyMap<String, View>(); var token = 0; var scrollY = 0
            screen.onActivity { find(it, "health-overview-all-records")?.performClick() }
            instrumentation.waitForIdleSync()
            withBusyWorker(screen) { release ->
                screen.onActivity { activity ->
                    original = captureViews(activity); token = generation(activity)
                    val scroll = original.getValue("health-overview-scroll") as ScrollView
                    scroll.scrollTo(0, 80); scrollY = scroll.scrollY; assertEquals(80, scrollY)
                    activity.setMeasurementPeriod(period)
                    stable(activity, original, token)
                    assertFalse(original.getValue("health-overview-metrics").isEnabled)
                    assertTrue((find(activity, "health-overview-value-${metric.name}") as TextView).text.contains("5"))
                }
                release.countDown()
                await(screen) { find(it, "health-overview-metrics")?.isEnabled == true &&
                    (find(it, "health-overview-value-${metric.name}") as? TextView)?.text?.contains("7") == true }
                instrumentation.waitForIdleSync()
                screen.onActivity { activity ->
                    stable(activity, original, token)
                    assertEquals(period.label(activity), (find(activity, "health-measurement-period-filter") as TextView).text.toString())
                    assertEquals(scrollY, (original.getValue("health-overview-scroll") as ScrollView).scrollY)
                    assertFalse(activity.measurementRecordsExpanded)
                    activity.filterMeasurementAbnormal(true)
                    stable(activity, original, token)
                    assertTrue((find(activity, "health-overview-value-${metric.name}") as TextView).text.contains("7"))
                }
                capture("health-period-month")
            }
        }
    }

    @Test fun rapidSelectionsDiscardQueuedOlderRequests() = fixture { names, period, metric ->
        screen(names) { screen -> withBusyWorker(screen) { release ->
            var original = emptyMap<String, View>(); var token = 0
            screen.onActivity { activity ->
                original = captureViews(activity); token = generation(activity)
                activity.setMeasurementPeriod(period)
                val request = field(activity, "measurementGeneration")
                activity.setMeasurementPeriod(period)
                assertEquals(request, field(activity, "measurementGeneration"))
                activity.setMeasurementPeriod(period.previous())
                activity.setMeasurementPeriod(null)
                stable(activity, original, token)
            }
            release.countDown()
            await(screen) { find(it, "health-overview-metrics")?.isEnabled == true }
            screen.onActivity { activity ->
                stable(activity, original, token); assertNull(activity.measurementPeriod)
                assertEquals(activity.getString(R.string.health_measurement_latest),
                    (find(activity, "health-measurement-period-filter") as TextView).text.toString())
                assertTrue((find(activity, "health-overview-value-${metric.name}") as TextView).text.contains("5"))
            }
        } }
    }

    @Test fun returningToLatestCancelsAnOlderPeriodPickerWithoutReopeningIt() = fixture { names, _, _ ->
        screen(names) { screen -> withBusyWorker(screen) { release ->
            val drained = CountDownLatch(1)
            var original = emptyMap<String, View>(); var token = 0
            screen.onActivity { activity ->
                original = captureViews(activity); token = generation(activity)
                fun choose(index: Int) {
                    activity.chooseMeasurementPeriod()
                    val dialog = (field(activity, "sensitiveDialogs") as Set<*>).filterIsInstance<AlertDialog>().last { it.isShowing }
                    dialog.listView.performItemClick(null, index, index.toLong())
                }
                choose(2); choose(0)
                worker(activity).execute { drained.countDown() }
            }
            release.countDown(); assertTrue(drained.await(5, TimeUnit.SECONDS)); instrumentation.waitForIdleSync()
            screen.onActivity { activity ->
                stable(activity, original, token); assertNull(activity.measurementPeriod)
                assertTrue((field(activity, "sensitiveDialogs") as Set<*>).filterIsInstance<AlertDialog>().none { it.isShowing })
            }
        } }
    }

    @Test fun pendingSelectionCannotRestoreSensitiveViewsAfterBackgrounding() = fixture { names, period, metric ->
        screen(names) { screen -> withBusyWorker(screen) { release ->
            screen.onActivity { it.setMeasurementPeriod(period) }
            screen.moveToState(Lifecycle.State.CREATED)
            screen.onActivity { activity ->
                assertEquals(0, activity.body.childCount); assertNull(field(activity, "overviewBase"))
                val overview = (field(activity, "overview\$delegate") as Lazy<*>).value!!
                listOf("measurementBinding", "measurementPendingBinding").forEach {
                    assertNull(overview.javaClass.getDeclaredField(it).apply { isAccessible = true }.get(overview))
                }
            }
            release.countDown(); instrumentation.waitForIdleSync()
            screen.onActivity { assertEquals(0, it.body.childCount) }
            screen.moveToState(Lifecycle.State.RESUMED)
            await(screen) { (find(it, "health-overview-value-${metric.name}") as? TextView)?.text?.contains("7") == true }
            screen.onActivity { assertEquals(period, it.measurementPeriod) }
        } }
    }

    @Test fun blockedSelectionRestoresThePreviousChoiceWithoutRebuildingThePage() = fixture { names, period, _ ->
        HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version) }
        screen(names) { screen ->
            var original = emptyMap<String, View>(); var token = 0
            screen.onActivity { activity -> original = captureViews(activity); token = generation(activity); activity.setMeasurementPeriod(period) }
            await(screen) { find(it, "health-overview-metrics")?.isEnabled == true && it.measurementPeriod == null }
            screen.onActivity { activity ->
                stable(activity, original, token)
                assertEquals(activity.getString(R.string.health_measurement_latest),
                    (find(activity, "health-measurement-period-filter") as TextView).text.toString())
                assertFalse(find(activity, "health-measurement-abnormal-filter")!!.isEnabled)
            }
        }
    }

    @Test fun revokingComparisonPermissionCancelsThePendingSelection() = fixture { names, period, metric ->
        screen(names) { screen -> withBusyWorker(screen) { release ->
            screen.onActivity { it.setMeasurementPeriod(period) }
            HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version) }
            await(screen) { it.measurementPeriod == null && find(it, "health-overview-metrics") == null }
            release.countDown()
            await(screen) { find(it, "health-overview-metrics") != null && find(it, "health-measurement-abnormal-filter")?.isEnabled == false }
            screen.onActivity { activity ->
                assertNull(activity.measurementPeriod)
                assertTrue((find(activity, "health-overview-value-${metric.name}") as TextView).text.contains("5"))
                assertEquals(activity.getString(R.string.health_measurement_latest),
                    (find(activity, "health-measurement-period-filter") as TextView).text.toString())
            }
        } }
    }

    @Test fun emptyPeriodsAndReturningToLatestOnlyReplaceTheMetricRows() = fixture { names, period, metric ->
        screen(names) { screen ->
            var original = emptyMap<String, View>(); var token = 0
            screen.onActivity { activity -> original = captureViews(activity); token = generation(activity); activity.setMeasurementPeriod(period.previous()) }
            await(screen) { find(it, "health-overview-metrics")?.isEnabled == true && find(it, "health-overview-value-${metric.name}") == null }
            screen.onActivity { activity ->
                stable(activity, original, token)
                assertTrue(views(original.getValue("health-overview-metrics")).filterIsInstance<TextView>()
                    .any { it.text.toString() == activity.getString(R.string.health_period_no_matching) })
                activity.setMeasurementPeriod(null)
            }
            await(screen) { find(it, "health-overview-metrics")?.isEnabled == true && find(it, "health-overview-value-${metric.name}") != null }
            screen.onActivity { stable(it, original, token) }
        }
    }
}
