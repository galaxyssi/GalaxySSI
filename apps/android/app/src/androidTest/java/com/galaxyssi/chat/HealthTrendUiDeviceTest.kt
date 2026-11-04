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
    private fun launch(): ActivityScenario<HealthTrendActivity> {
        assumeFalse("Visible trend acceptance needs an unlocked device", instrumentation.targetContext.getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked)
        return ActivityScenario.launch(Intent(instrumentation.targetContext, HealthTrendActivity::class.java).putExtra("health_metric", HealthMetric.STEPS.name))
    }
    @Test fun nativeTrendPageLoadsItsControlsWithoutBottomTabsOrSyntheticMeasurements(): Unit = launch().use { scenario ->
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
    @Test fun backgroundClearsChartModelsAndRecreationRestoresThePeriod(): Unit = launch().use { scenario ->
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
    @Test fun cancellingCustomDatesDoesNotApplyAnUnconfirmedPeriod(): Unit = launch().use { scenario ->
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
