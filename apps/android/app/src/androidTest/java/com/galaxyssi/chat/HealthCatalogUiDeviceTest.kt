package com.galaxyssi.chat

import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

/** No measurements or synthetic drafts are saved by these native UI tests. */
class HealthCatalogUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private fun unlocked() = assumeFalse("Visible UI acceptance needs an unlocked device", (instrumentation.targetContext.getSystemService(android.app.KeyguardManager::class.java)).isKeyguardLocked)
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
            lateinit var detached: ViewGroup
            scenario.onActivity { detached = find(it, "health-catalog-ALT").parent as ViewGroup }
            scenario.moveToState(Lifecycle.State.CREATED)
            assertEquals(0, detached.childCount)
            scenario.moveToState(Lifecycle.State.RESUMED); await(scenario) { has(it, "health-catalog-ALT") }
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
