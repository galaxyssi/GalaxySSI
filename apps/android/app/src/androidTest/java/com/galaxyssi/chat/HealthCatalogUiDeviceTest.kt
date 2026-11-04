package com.galaxyssi.chat

import android.app.Activity
import android.content.ComponentCallbacks2
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.KeyEvent
import android.widget.EditText
import android.widget.RadioButton
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthCatalogUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private fun unlocked() = assumeFalse("Visible UI acceptance needs an unlocked device", (instrumentation.targetContext.getSystemService(android.app.KeyguardManager::class.java)).isKeyguardLocked)

    @Test fun returningFromPopulatedTrendAndRevisionRetainsSearchButUiHiddenClearsIt() = fixture { names ->
        val context = instrumentation.targetContext
        HealthRecordStore(context, names.records).use { store ->
            assertTrue(store.save(HealthDraft(HealthMetric.STEPS, mapOf("steps" to "1234"))) is HealthSaveResult.Saved)
        }
        ActivityScenario.launch<HealthCatalogActivity>(catalogIntent(names)).use { scenario ->
            lateinit var catalog: HealthCatalogActivity
            scenario.onActivity {
                catalog = it
                (find(it, "health-catalog-group") as Spinner).setSelection(HealthMetricGroup.ACTIVITY.ordinal + 1)
                (find(it, "health-catalog-search") as EditText).setText("\u6b65\u6570")
            }
            await(scenario) { has(it, "health-catalog-STEPS") && !has(it, "health-catalog-SLEEP_DURATION") }
            val trend = open(HealthTrendActivity::class.java) {
                scenario.onActivity { assertTrue(find(it, "health-catalog-STEPS").performClick()) }
            }
            try {
                awaitView(trend, "health-trend-latest-record")
                instrumentation.runOnMainSync { assertTrue(find(trend, "health-trend-period-1").performClick()) }
                awaitView(trend, "health-trend-latest-record")
                val revision = open(HealthRecordRevisionActivity::class.java) {
                    instrumentation.runOnMainSync { assertTrue(find(trend, "health-trend-latest-record").performClick()) }
                }
                try {
                    awaitView(revision, "health-revision-value")
                    instrumentation.runOnMainSync {
                        assertTrue((find(revision, "health-revision-value") as TextView).text.startsWith("1234"))
                    }
                    back()
                    awaitView(trend, "health-trend-latest-record")
                    instrumentation.runOnMainSync { assertTrue((find(trend, "health-trend-period-1") as RadioButton).isChecked) }
                } finally { finishIfOpen(revision) }
                back()
                await(scenario) { has(it, "health-catalog-STEPS") && (find(it, "health-catalog-search") as EditText).text.toString() == "\u6b65\u6570" }
                scenario.onActivity {
                    assertEquals(HealthMetricGroup.ACTIVITY.ordinal + 1, (find(it, "health-catalog-group") as Spinner).selectedItemPosition)
                }
            } finally { finishIfOpen(trend) }
            val hidden = open(HealthTrendActivity::class.java) {
                scenario.onActivity { assertTrue(find(it, "health-catalog-STEPS").performClick()) }
            }
            try {
                awaitView(hidden, "health-trend-latest-record")
                instrumentation.runOnMainSync { catalog.onTrimMemory(ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN) }
                back()
                await(scenario) { has(it, "health-catalog-STEPS") && (find(it, "health-catalog-search") as EditText).text.isEmpty() }
            } finally { finishIfOpen(hidden) }
        }
    }

    @Test fun recordPageAndVisibleRowStayAnchoredWhenNewDataArrivesDuringDetail() = fixture { names ->
        val context = instrumentation.targetContext
        val time = System.currentTimeMillis() - 60_000
        val records = HealthRecordStore(context, names.records).use { store ->
            (0 until 65).map { index ->
                (store.save(HealthDraft(HealthMetric.STEPS, mapOf("steps" to "${1000 + index}"),
                    measuredAt = time - index * 1000L)) as HealthSaveResult.Saved).record
            }
        }
        fun tag(record: HealthObservation) = "health-catalog-record-${record.id}"
        val anchor = records[35]
        ActivityScenario.launch<HealthCatalogActivity>(catalogIntent(names)).use { scenario ->
            scenario.onActivity {
                find(it, "health-catalog-mode-2").performClick()
                (find(it, "health-catalog-search") as EditText).setText("\u6b65\u6570")
            }
            await(scenario) { has(it, "health-catalog-next") }
            scenario.onActivity { assertTrue(find(it, "health-catalog-next").performClick()) }
            await(scenario) { has(it, tag(anchor)) && has(it, "health-catalog-previous") }
            instrumentation.waitForIdleSync()
            val detail = open(HealthCenterActivity::class.java) {
                scenario.onActivity { activity ->
                    val scroll = find(activity, "health-catalog-scroll") as ScrollView
                    val row = find(activity, tag(anchor))
                    scroll.scrollTo(0, row.top + 9)
                    assertEquals(row.top + 9, scroll.scrollY)
                    assertTrue(row.performClick())
                }
            }
            try {
                val inserted = HealthRecordStore(context, names.records).use {
                    (it.save(HealthDraft(HealthMetric.STEPS, mapOf("steps" to "9999"),
                        measuredAt = time - 32_500)) as HealthSaveResult.Saved).record
                }
                back()
                await(scenario) { activity ->
                    has(activity, tag(inserted)) && has(activity, tag(anchor)) && has(activity, "health-catalog-previous") &&
                        (find(activity, "health-catalog-scroll") as ScrollView).scrollY == find(activity, tag(anchor)).top + 9
                }
                scenario.onActivity {
                    assertFalse(has(it, tag(records.first())))
                    assertEquals("\u6b65\u6570", (find(it, "health-catalog-search") as EditText).text.toString())
                }
                val live = HealthRecordStore(context, names.records).use {
                    (it.save(HealthDraft(HealthMetric.STEPS, mapOf("steps" to "9998"),
                        measuredAt = time - 31_500)) as HealthSaveResult.Saved).record
                }
                await(scenario) { activity ->
                    has(activity, tag(live)) && (find(activity, "health-catalog-scroll") as ScrollView).scrollY ==
                        find(activity, tag(anchor)).top + 9
                }
            } finally { finishIfOpen(detail) }
        }
    }

    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        unlocked()
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(instrumentation.targetContext, names) }
    }
    private fun catalogIntent(names: HealthOverviewDatabases) =
        Intent(instrumentation.targetContext, HealthCatalogActivity::class.java).putHealthNavigationFixture(names)
    private fun <T : Activity> open(type: Class<T>, launch: () -> Unit): T {
        val monitor = instrumentation.addMonitor(type.name, null, false)
        try {
            launch()
            return type.cast(requireNotNull(instrumentation.waitForMonitorWithTimeout(monitor, 10_000)))
        } finally { instrumentation.removeMonitor(monitor) }
    }
    private fun back() { instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK); instrumentation.waitForIdleSync() }
    private fun finishIfOpen(activity: Activity) = instrumentation.runOnMainSync { if (!activity.isFinishing) activity.finish() }
    private fun awaitView(activity: Activity, tag: String) {
        val deadline = SystemClock.elapsedRealtime() + 12_000
        do {
            var ready = false
            instrumentation.runOnMainSync { ready = has(activity, tag) }
            if (ready) return
            SystemClock.sleep(50)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("Native health route did not show $tag")
    }
    @Test fun catalogSearchAndCategoryModesUseTheNativePageWithoutBottomTabs() {
        unlocked()
        ActivityScenario.launch(HealthCatalogActivity::class.java).use { scenario ->
            await(scenario) { has(it, "health-catalog-STEPS") }
            scenario.onActivity { activity ->
                find(activity, "health-catalog-mode-1").performClick()
                (find(activity, "health-catalog-search") as EditText).setText("LDL-C")
            }
            await(scenario) { has(it, "health-catalog-LDL") && !has(it, "health-catalog-ALT") }
            scenario.onActivity {
                assertEquals(2, (it.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as ViewGroup).childCount)
                val selected = descendants(it.window.decorView).filterIsInstance<android.widget.RadioButton>().filter { button -> button.isChecked }
                assertEquals(1, selected.size); assertEquals("health-catalog-mode-1", selected.single().tag)
            }
            instrumentation.waitForIdleSync(); SystemClock.sleep(300); instrumentation.waitForIdleSync()
            await(scenario) { has(it, "health-catalog-LDL") && !has(it, "health-catalog-ALT") }
            instrumentation.uiAutomation.takeScreenshot()?.let { image -> try {
                File(instrumentation.targetContext.getExternalFilesDir(null), "health-catalog-ui.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            } finally { image.recycle() } }
        }
    }
    @Test fun backgroundClearsDetachedResultViewsAndRecreationRestoresTheSection() {
        unlocked()
        ActivityScenario.launch(HealthCatalogActivity::class.java).use { scenario ->
            await(scenario) { has(it, "health-catalog-STEPS") }
            scenario.onActivity { find(it, "health-catalog-mode-1").performClick() }
            await(scenario) { has(it, "health-catalog-ALT") }
            scenario.onActivity { (find(it, "health-catalog-search") as EditText).setText("ALT") }
            await(scenario) { has(it, "health-catalog-ALT") && !has(it, "health-catalog-LDL") }
            lateinit var detached: ViewGroup
            scenario.onActivity { detached = find(it, "health-catalog-ALT").parent as ViewGroup }
            scenario.moveToState(Lifecycle.State.CREATED)
            assertEquals(0, detached.childCount)
            scenario.moveToState(Lifecycle.State.RESUMED); await(scenario) { has(it, "health-catalog-ALT") }
            scenario.onActivity { assertTrue((find(it, "health-catalog-search") as EditText).text.isEmpty()) }
            scenario.recreate(); await(scenario) { has(it, "health-catalog-ALT") }
        }
    }
    @Test fun qualitativeManualEntryHasATextResultAndNoInventedUnit() {
        unlocked()
        ActivityScenario.launch<HealthCenterActivity>(Intent(instrumentation.targetContext, HealthCenterActivity::class.java)
            .putExtra("health_manual", true).putExtra("health_metric", HealthMetric.URINE_PROTEIN.name)).use { scenario ->
            val deadline = SystemClock.elapsedRealtime() + 10_000; var ready = false
            do {
                scenario.onActivity { activity -> ready = descendants(activity.window.decorView).any { it.tag == "health-field-urine_protein" } }
                if (!ready) SystemClock.sleep(50)
            } while (!ready && SystemClock.elapsedRealtime() < deadline)
            assertTrue(ready)
            scenario.onActivity { activity ->
                val views = descendants(activity.window.decorView)
                val input = views.single { it.tag == "health-field-urine_protein" } as EditText
                assertEquals(android.text.InputType.TYPE_CLASS_TEXT, input.inputType and android.text.InputType.TYPE_MASK_CLASS)
                assertTrue(views.filterIsInstance<TextView>().any { it.text.toString() == activity.getString(R.string.health_unit_not_applicable) })
                assertNotNull(views.firstOrNull { it.tag == "health-reference" }); assertFalse(input.isSaveEnabled)
                activity.editor!!.showError(HealthValidationError(HealthValidationIssue.INVALID_NUMBER, "urine_protein"))
                assertEquals(activity.getString(R.string.health_invalid_qualitative, activity.getString(R.string.health_metric_urine_protein)),
                    (descendants(activity.window.decorView).single { it.tag == "health-validation" } as TextView).text.toString())
            }
        }
    }
    private fun await(scenario: ActivityScenario<HealthCatalogActivity>, ready: (HealthCatalogActivity) -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 10_000
        do { var done = false; scenario.onActivity { done = ready(it) }; if (done) return; SystemClock.sleep(50) } while (SystemClock.elapsedRealtime() < deadline)
        fail("Native catalog did not reach the requested state")
    }
    private fun has(activity: android.app.Activity, tag: String) = descendants(activity.window.decorView).any { it.tag == tag }
    private fun find(activity: android.app.Activity, tag: String) = descendants(activity.window.decorView).single { it.tag == tag }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
}
