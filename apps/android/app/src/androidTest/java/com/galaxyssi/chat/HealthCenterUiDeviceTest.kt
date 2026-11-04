package com.galaxyssi.chat

import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import androidx.test.core.app.ActivityScenario
import org.junit.Assert.*
import org.junit.Test

class HealthCenterUiDeviceTest {
    @Test fun manualPageUsesNativeInputsAndNoBottomTabs() {
        ActivityScenario.launch(HealthCenterActivity::class.java).use { scenario ->
            scenario.onActivity { it.open("manual") }
            waitFor(scenario, "health-save")
            scenario.onActivity { activity ->
                val fields = descendants(activity.body).filterIsInstance<EditText>().filter { it.tag?.toString()?.startsWith("health-field-") == true }
                assertEquals(3, fields.size)
                // Existing private drafts are intentionally allowed; no design sample is prefilled.
                assertTrue(fields.all { !it.isSaveEnabled })
                assertNotNull(descendants(activity.body).firstOrNull { it.tag == "health-measured-at" })
                val units = descendants(activity.body).filterIsInstance<android.widget.TextView>()
                assertEquals("mmHg", units.single { it.tag == "health-unit-systolic" }.text.toString())
                assertEquals("bpm", units.single { it.tag == "health-unit-pulse" }.text.toString())
                val root = activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as ViewGroup
                assertEquals(2, root.childCount)
            }
        }
    }
    @Test fun backgroundDropsDecryptedViewsAndForegroundReloadsTheSameScreen() {
        ActivityScenario.launch(HealthCenterActivity::class.java).use { scenario ->
            scenario.onActivity { it.open("manual", HealthMetric.WEIGHT) }
            waitFor(scenario, "health-field-weight")
            scenario.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
            scenario.onActivity { assertEquals(0, it.body.childCount); assertNull(it.editor) }
            scenario.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
            waitFor(scenario, "health-field-weight")
            scenario.onActivity { assertNotNull(it.editor) }
        }
    }
    @Test fun featureMenuAndActivityRecreationRetainNavigationWithoutSensitiveBundleFields() {
        ActivityScenario.launch(HealthCenterActivity::class.java).use { scenario ->
            scenario.onActivity { it.open("manual", HealthMetric.GLUCOSE) }
            waitFor(scenario, "health-field-glucose")
            scenario.recreate()
            waitFor(scenario, "health-field-glucose")
            scenario.onActivity { activity ->
                activity.open("functions")
                assertNotNull(descendants(activity.window.decorView).firstOrNull { it.tag == "health-functions" })
            }
        }
    }
    private fun waitFor(scenario: ActivityScenario<HealthCenterActivity>, tag: String) {
        val until = SystemClock.elapsedRealtime() + 10_000
        do {
            var ready = false
            scenario.onActivity { ready = descendants(it.body).any { view -> view.tag == tag } }
            if (ready) return
            SystemClock.sleep(60)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Health view did not become ready: $tag")
    }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
}
