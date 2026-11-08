package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthCareUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun find(activity: Activity, tag: String) = views(activity.window.decorView).firstOrNull { it.tag == tag }
    private fun <T : Activity> await(scenario: ActivityScenario<T>, predicate: (T) -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 20_000
        do {
            var ready = false; scenario.onActivity { ready = predicate(it) }
            if (ready) return
            SystemClock.sleep(50)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Health care UI did not reach the expected state")
    }
    private fun seed(names: HealthOverviewDatabases) {
        HealthRecordStore(context, names.records).use {
            it.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"), "mmol/L",
                System.currentTimeMillis() - 1000, reference = "4-6"))
        }
        HealthCareStore(context, names.care).use { it.configure(true, "") }
        HealthCareEngine.evaluate(context, names)
    }
    private fun clean(names: HealthOverviewDatabases) {
        listOf(names.care, names.records, names.privacy).forEach(context::deleteDatabase)
    }
    private fun capture(name: String) {
        if (InstrumentationRegistry.getArguments().getString("health_care_screenshot") != "true") return
        instrumentation.waitForIdleSync()
        instrumentation.uiAutomation.waitForIdle(300, 5000)
        instrumentation.uiAutomation.takeScreenshot()?.let { image -> try {
            File(context.getExternalFilesDir(null), name).outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
        } finally { image.recycle() } }
    }
    @Test fun careSectionsAndEvidenceSurviveRecreationAndClearOnBackground() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        var worker: ExecutorService? = null
        try {
            seed(names)
            ActivityScenario.launch<HealthCareActivity>(Intent(context, HealthCareActivity::class.java).putHealthNavigationFixture(names)).use { scenario ->
                await(scenario) { find(it, "health-care-item-GLUCOSE") != null }
                scenario.onActivity { activity ->
                    val labels = views(activity.window.decorView).filterIsInstance<TextView>().map { it.text.toString() }
                    listOf(R.string.health_care_attention, R.string.health_care_plans, R.string.health_care_evidence).forEach {
                        assertTrue(labels.contains(activity.getString(it)))
                    }
                }
                capture("health-care-overview-fixture.png")
                scenario.onActivity { find(it, "health-care-item-GLUCOSE")!!.performClick() }
                await(scenario) { find(it, "health-care-context") != null }
                scenario.onActivity { activity ->
                    val labels = views(activity.window.decorView).filterIsInstance<TextView>().map { it.text.toString() }
                    listOf(R.string.health_care_reference, R.string.health_care_guideline, R.string.health_care_baseline,
                        R.string.health_care_target, R.string.health_care_no_target).forEach { assertTrue(labels.contains(activity.getString(it))) }
                }
                capture("health-care-evidence-fixture.png")
                scenario.recreate()
                await(scenario) { find(it, "health-care-context") != null }
                scenario.moveToState(Lifecycle.State.CREATED)
                scenario.onActivity { assertNull(find(it, "health-care-context")) }
                scenario.moveToState(Lifecycle.State.RESUMED)
                await(scenario) { find(it, "health-care-context") != null }
                scenario.onActivity { worker = HealthCareActivity::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(it) as ExecutorService }
            }
        } finally { worker?.awaitTermination(10, TimeUnit.SECONDS); clean(names) }
    }
    @Test fun privacyRevocationRemovesVisibleDerivedConcern() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        var worker: ExecutorService? = null
        try {
            seed(names)
            ActivityScenario.launch<HealthCareActivity>(Intent(context, HealthCareActivity::class.java).putHealthNavigationFixture(names)).use { scenario ->
                await(scenario) { find(it, "health-care-item-GLUCOSE") != null }
                HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version) }
                await(scenario) { find(it, "health-care-item-GLUCOSE") == null }
                scenario.onActivity { worker = HealthCareActivity::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(it) as ExecutorService }
            }
        } finally { worker?.awaitTermination(10, TimeUnit.SECONDS); clean(names) }
    }
    @Test fun agentMainSurfaceDoesNotEnterCollaborationAndReleasesItsViews() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        var worker: ExecutorService? = null
        try {
            seed(names)
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)).use { scenario ->
                scenario.onActivity { activity ->
                    activity.healthCareSurface?.destroy()
                    activity.healthCareSurface = HealthCareAgentSurface(activity, names).also {
                        it.showForAgent(true); it.resume()
                        worker = HealthCareAgentSurface::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(it) as ExecutorService
                    }
                }
                await(scenario) { find(it, "agent-health-care-concern") != null }
                scenario.onActivity { activity ->
                    activity.healthCareSurface!!.showForAgent(false)
                    assertNull(find(activity, "agent-health-care-concern"))
                    activity.healthCareSurface!!.showForAgent(true)
                }
                await(scenario) { find(it, "agent-health-care-concern") != null }
                scenario.onActivity {
                    it.healthCareSurface!!.pause()
                    assertEquals(View.GONE, it.findViewById<View>(R.id.agentHealthCareSurface).visibility)
                    assertNull(find(it, "agent-health-care-concern"))
                }
            }
        } finally { worker?.awaitTermination(10, TimeUnit.SECONDS); clean(names) }
    }
}
