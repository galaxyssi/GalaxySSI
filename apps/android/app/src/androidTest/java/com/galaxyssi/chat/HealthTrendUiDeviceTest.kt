package com.galaxyssi.chat

import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthTrendUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private fun withTrend(test: (ActivityScenario<HealthTrendActivity>) -> Unit) {
        assumeFalse("Visible trend acceptance needs an unlocked device", instrumentation.targetContext.getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked)
        val name = "health-privacy-test-${java.util.UUID.randomUUID()}.db"
        var worker: java.util.concurrent.ExecutorService? = null
        try {
            ActivityScenario.launch<HealthTrendActivity>(Intent(instrumentation.targetContext, HealthTrendActivity::class.java)
                .putExtra("health_metric", HealthMetric.STEPS.name).putExtra("health_privacy_test_db", name)).use { scenario ->
                try { test(scenario) } finally { scenario.onActivity {
                    worker = HealthTrendActivity::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(it) as java.util.concurrent.ExecutorService
                } }
            }
        } finally { worker?.awaitTermination(10, java.util.concurrent.TimeUnit.SECONDS); instrumentation.targetContext.deleteDatabase(name) }
    }
    @Test fun nativeTrendPageLoadsItsControlsWithoutBottomTabsOrSyntheticMeasurements(): Unit = withTrend { scenario ->
        await(scenario)
        scenario.onActivity { activity ->
            assertEquals(2, (activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as ViewGroup).childCount)
            assertNotNull(views(activity).firstOrNull { it.tag == "health-trend-period-3" }); assertFalse(views(activity).filterIsInstance<HealthTrendChart>().single().isSaveEnabled)
        }
        instrumentation.waitForIdleSync(); SystemClock.sleep(300); instrumentation.waitForIdleSync()
        instrumentation.uiAutomation.takeScreenshot()?.let { image -> try {
            File(instrumentation.targetContext.getExternalFilesDir(null), "health-trend-ui.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        } finally { image.recycle() } }
    }
    @Test fun backgroundClearsChartModelsAndRecreationRestoresThePeriod(): Unit = withTrend { scenario ->
        await(scenario); lateinit var chart: HealthTrendChart
        scenario.onActivity { activity -> views(activity).single { it.tag == "health-trend-period-1" }.performClick() }
        await(scenario)
        scenario.onActivity { chart = views(it).filterIsInstance<HealthTrendChart>().single() }
        scenario.moveToState(Lifecycle.State.CREATED)
        assertEquals("", chart.contentDescription.toString())
        assertNull(HealthTrendChart::class.java.getDeclaredField("summary").apply { isAccessible = true }.get(chart))
        scenario.moveToState(Lifecycle.State.RESUMED); await(scenario); scenario.recreate(); await(scenario)
        scenario.onActivity { activity ->
            val selected = views(activity).filterIsInstance<android.widget.RadioButton>().filter { it.isChecked }
            assertEquals(1, selected.size); assertEquals("health-trend-period-1", selected.single().tag)
        }
    }
    @Test fun cancellingCustomDatesDoesNotApplyAnUnconfirmedPeriod(): Unit = withTrend { scenario ->
        await(scenario); scenario.onActivity { views(it).single { view -> view.tag == "health-trend-period-3" }.performClick() }
        instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
        scenario.onActivity { activity ->
            val selected = views(activity).filterIsInstance<android.widget.RadioButton>().filter { it.isChecked }
            assertEquals("health-trend-period-0", selected.single().tag)
        }
    }
    private fun await(scenario: ActivityScenario<HealthTrendActivity>) {
        val until = SystemClock.elapsedRealtime() + 15_000
        do { var ready = false; scenario.onActivity { activity ->
            val children = views(activity)
            ready = children.any { it.tag == "health-trend-counts" } && children.filterIsInstance<HealthTrendChart>().singleOrNull()?.let {
                it.isEnabled && it.contentDescription.toString() != activity.getString(R.string.health_loading)
            } == true
        }; if (ready) return; SystemClock.sleep(50) } while (SystemClock.elapsedRealtime() < until)
        fail("Native trend did not finish loading")
    }
    private fun views(activity: android.app.Activity): List<View> = descendants(activity.window.decorView)
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
}
