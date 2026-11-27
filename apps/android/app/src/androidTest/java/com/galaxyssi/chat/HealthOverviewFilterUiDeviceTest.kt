package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import android.widget.ScrollView
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthOverviewFilterUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun find(activity: HealthCenterActivity, tag: String) = views(activity.body).singleOrNull { it.tag == tag }
    private fun await(screen: ActivityScenario<HealthCenterActivity>, ready: (HealthCenterActivity) -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 15_000
        do {
            var found = false
            screen.onActivity { found = ready(it) }
            if (found) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Health filter did not finish updating")
    }
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun generation(activity: HealthCenterActivity) = HealthCenterActivity::class.java.getDeclaredField("generation")
        .apply { isAccessible = true }.getInt(activity)
    private fun worker(activity: HealthCenterActivity) = HealthCenterActivity::class.java.getDeclaredField("worker")
        .apply { isAccessible = true }.get(activity) as ExecutorService
    private fun overview(activity: HealthCenterActivity) = HealthCenterActivity::class.java.getDeclaredField("overview\$delegate")
        .apply { isAccessible = true }.get(activity).let { (it as Lazy<*>).value as HealthOverviewView }

    @Test fun filterChangesOnlyTheMetricListWhileTheDatabaseWorkerIsBusy() = fixture { names ->
        val now = System.currentTimeMillis()
        val laboratory = HealthMetric.entries.filter { it.form == HealthResultForm.LABORATORY }.take(15)
        assertEquals(15, laboratory.size)
        HealthRecordStore(context, names.records).use { records ->
            laboratory.forEach { metric ->
                assertTrue(records.save(HealthDraft(metric, mapOf(metric.fields.single() to "7"), metric.units.first(), now - 1000,
                    reference = "4-6")) is HealthSaveResult.Saved)
            }
            assertTrue(records.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "70"), "kg", now - 1000)) is HealthSaveResult.Saved)
        }
        val release = CountDownLatch(1)
        ActivityScenario.launch<HealthCenterActivity>(Intent(context, HealthCenterActivity::class.java).putHealthNavigationFixture(names)).use { screen ->
            try {
                await(screen) { find(it, "health-overview-all-records") != null }
                val busy = CountDownLatch(1)
                screen.onActivity { activity ->
                    find(activity, "health-overview-all-records")!!.performClick()
                    worker(activity).execute { busy.countDown(); release.await(10, TimeUnit.SECONDS) }
                }
                assertTrue(busy.await(3, TimeUnit.SECONDS))
                instrumentation.waitForIdleSync()
                var scrollBefore = 0
                screen.onActivity { activity ->
                    val scroll = activity.body.getChildAt(0) as ScrollView
                    scroll.scrollTo(0, 80); scrollBefore = scroll.scrollY
                    assertEquals(80, scrollBefore)
                    val tags = listOf("health-overview-activity", "health-overview-value-STEPS", "health-overview-cycling",
                        "health-overview-bottom-actions", "health-measurement-period-filter", "health-measurement-abnormal-filter", "health-overview-metrics")
                    val original = tags.associateWith { requireNotNull(find(activity, it)) }
                    val token = generation(activity)
                    val filter = original.getValue("health-measurement-abnormal-filter") as CheckBox
                    repeat(10) { index ->
                        val checked = index % 2 == 0
                        filter.isChecked = checked
                        assertEquals(token, generation(activity))
                        assertSame(scroll, activity.body.getChildAt(0))
                        original.forEach { (tag, view) -> assertSame("Rebuilt $tag", view, find(activity, tag)) }
                        assertTrue(activity.measurementRecordsExpanded)
                        assertEquals(!checked, find(activity, "health-overview-value-WEIGHT") != null)
                        val metrics = original.getValue("health-overview-metrics") as ViewGroup
                        if (checked) assertEquals(15, (0 until metrics.childCount).count { metrics.getChildAt(it).isClickable })
                        assertFalse(views(activity.body).filterIsInstance<TextView>().any { it.text.toString() == activity.getString(R.string.health_loading) })
                    }
                }
                instrumentation.waitForIdleSync()
                screen.onActivity { assertEquals(scrollBefore, (it.body.getChildAt(0) as ScrollView).scrollY) }
            } finally { release.countDown() }
        }
    }

    @Test fun filteringFarDownKeepsTheSameSurvivingReadingAtTheSameOffset() = fixture { names ->
        val now = System.currentTimeMillis()
        val labs = HealthMetric.entries.filter { it.form == HealthResultForm.LABORATORY }.take(36)
        val outside = mutableSetOf<String>()
        HealthRecordStore(context, names.records).use { records ->
            labs.forEachIndexed { index, metric ->
                val abnormal = index % 3 != 0
                if (abnormal) outside.add(metric.name)
                assertTrue(records.save(HealthDraft(metric, mapOf(metric.fields.single() to if (abnormal) "7" else "5"),
                    metric.units.first(), now - index * 1000L, reference = "4-6")) is HealthSaveResult.Saved)
            }
        }
        ActivityScenario.launch<HealthCenterActivity>(Intent(context, HealthCenterActivity::class.java).putHealthNavigationFixture(names)).use { screen ->
            await(screen) { find(it, "health-overview-all-records") != null }
            screen.onActivity { find(it, "health-overview-all-records")!!.performClick() }
            instrumentation.waitForIdleSync()
            var key = ""
            screen.onActivity { activity ->
                val metrics = find(activity, "health-overview-metrics") as ViewGroup
                val rows = (0 until metrics.childCount).map(metrics::getChildAt).filter { it.getTag(R.id.healthReadingKey) != null }
                fun abnormal(v: View) = v.tag.toString().removePrefix("health-overview-").substringBefore('-') in outside
                val index = rows.indices.first { i -> i >= 4 && abnormal(rows[i]) }
                val row = rows[index]; key = row.getTag(R.id.healthReadingKey) as String
                val scroller = activity.body.getChildAt(0) as ScrollView
                val bounds = android.graphics.Rect()
                scroller.offsetDescendantRectToMyCoords(row, bounds)
                scroller.scrollTo(0, bounds.top + 7)
                assertEquals(bounds.top + 7, scroller.scrollY)
                (find(activity, "health-measurement-abnormal-filter") as CheckBox).isChecked = true
            }
            await(screen) { activity ->
                val scroll = activity.body.getChildAt(0) as ScrollView
                val row = views(scroll).firstOrNull { it.getTag(R.id.healthReadingKey) == key }
                val rect = android.graphics.Rect()
                if (row == null || scroll.isLayoutRequested) false
                else { scroll.offsetDescendantRectToMyCoords(row, rect); rect.top - scroll.scrollY == -7 }
            }
        }
    }

    @Test fun newMeasurementsReplaceTheLocalFilterSnapshot() = fixture { names ->
        val now = System.currentTimeMillis()
        HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "5.1"),
            "mmol/L", now - 2000, reference = "4-6")) }
        ActivityScenario.launch<HealthCenterActivity>(Intent(context, HealthCenterActivity::class.java).putHealthNavigationFixture(names)).use { screen ->
            await(screen) { find(it, "health-overview-value-GLUCOSE") != null }
            screen.onActivity {
                (find(it, "health-measurement-abnormal-filter") as CheckBox).isChecked = true
                assertNull(find(it, "health-overview-value-GLUCOSE"))
            }
            HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"),
                "mmol/L", now - 1000, reference = "4-6")) }
            await(screen) { (find(it, "health-overview-value-GLUCOSE") as? TextView)?.text?.contains("6.3") == true }
            screen.onActivity {
                val token = generation(it)
                val filter = find(it, "health-measurement-abnormal-filter") as CheckBox
                filter.isChecked = false; filter.isChecked = true
                assertEquals(token, generation(it))
                assertTrue((find(it, "health-overview-value-GLUCOSE") as TextView).text.contains("6.3"))
            }
        }
    }

    @Test fun leavingThePageReleasesTheLocalMeasurementBinding() = fixture { names ->
        ActivityScenario.launch<HealthCenterActivity>(Intent(context, HealthCenterActivity::class.java).putHealthNavigationFixture(names)).use { screen ->
            await(screen) { find(it, "health-overview-metrics") != null }
            val binding = HealthOverviewView::class.java.getDeclaredField("measurementBinding").apply { isAccessible = true }
            screen.onActivity { assertNotNull(binding.get(overview(it))) }
            screen.moveToState(Lifecycle.State.CREATED)
            screen.onActivity {
                assertNull(binding.get(overview(it)))
                it.filterMeasurementAbnormal(true)
                assertEquals(0, it.body.childCount)
            }
            screen.moveToState(Lifecycle.State.RESUMED)
            await(screen) { find(it, "health-overview-metrics") != null }
            screen.onActivity {
                assertTrue((find(it, "health-measurement-abnormal-filter") as CheckBox).isChecked)
                assertNotNull(binding.get(overview(it)))
            }
        }
    }
}
