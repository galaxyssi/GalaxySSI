package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
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
                System.currentTimeMillis() - 86_400_000, reference = "4-6"))
        }
        HealthCareStore(context, names.care).use { it.configure(true, "") }
        HealthCareEngine.evaluate(context, names)
        HealthRecordStore(context, names.records).use {
            it.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "5.4"), "mmol/L",
                System.currentTimeMillis() - 1000, reference = "4-6"))
        }
        HealthCareEngine.evaluate(context, names)
    }
    private fun clean(names: HealthOverviewDatabases) {
        listOf(names.care, names.records, names.privacy).forEach(context::deleteDatabase)
    }
    private fun historyReview(activity: HealthCareActivity) = HealthCareActivity::class.java.getDeclaredMethod("getHistoryReview")
        .apply { isAccessible = true }.invoke(activity) as HealthCareHistoryReview
    private fun historyDialog(review: HealthCareHistoryReview) = HealthCareHistoryReview::class.java.getDeclaredField("dialog")
        .apply { isAccessible = true }.get(review) as? AlertDialog
    private fun worker(value: Any) = value.javaClass.getDeclaredField("worker").apply { isAccessible = true }.get(value) as ExecutorService
    @Test fun longitudinalHistoryPagesClearOnBackgroundAndPrivacyChange() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        val workers = mutableListOf<ExecutorService>()
        try {
            seed(names)
            HealthRecordStore(context, names.records).use { records -> repeat(33) { index -> records.save(HealthDraft(HealthMetric.GLUCOSE,
                mapOf("glucose" to "6.3"), "mmol/L", System.currentTimeMillis() - (index + 3L) * 86_400_000L, reference = "4-6")) } }
            HealthCareEngine.evaluate(context, names)
            val id = HealthCareStore(context, names.care).use { it.forMetric(HealthMetric.GLUCOSE)!!.id }
            ActivityScenario.launch<HealthCareActivity>(Intent(context, HealthCareActivity::class.java)
                .putExtra("health_care_id", id).putHealthNavigationFixture(names)).use { scenario ->
                await(scenario) { find(it, "health-care-series") != null }
                scenario.onActivity { workers += worker(it); workers += worker(historyReview(it)); find(it, "health-care-series")!!.performClick() }
                await(scenario) { historyDialog(historyReview(it))?.isShowing == true }
                scenario.onActivity { activity ->
                    val d = historyDialog(historyReview(activity))!!
                    assertEquals(30, views(d.window!!.decorView).count { it.tag == "health-series-value" })
                    assertTrue(views(d.window!!.decorView).filterIsInstance<TextView>().any { it.text.toString() == activity.getString(R.string.health_series_earlier) })
                    d.getButton(AlertDialog.BUTTON_NEUTRAL).performClick()
                }
                await(scenario) { historyDialog(historyReview(it))?.window?.decorView?.let { root -> views(root).count { it.tag == "health-series-value" } == 5 } == true }
                capture("health-series-older-fixture.png")
                scenario.moveToState(Lifecycle.State.CREATED)
                scenario.onActivity { assertNull(historyDialog(historyReview(it))) }
                scenario.moveToState(Lifecycle.State.RESUMED)
                await(scenario) { find(it, "health-care-series") != null }
                scenario.onActivity { find(it, "health-care-series")!!.performClick() }
                await(scenario) { historyDialog(historyReview(it))?.isShowing == true }
                capture("health-series-recent-fixture.png")
                HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version) }
                await(scenario) { historyDialog(historyReview(it)) == null && find(it, "health-care-series") == null }
            }
        } finally { workers.forEach { it.awaitTermination(10, TimeUnit.SECONDS) }; clean(names) }
    }
    private fun capture(name: String) {
        if (InstrumentationRegistry.getArguments().getString("health_care_screenshot") != "true") return
        instrumentation.waitForIdleSync()
        instrumentation.uiAutomation.waitForIdle(300, 5000)
        instrumentation.uiAutomation.takeScreenshot()?.let { image -> try {
            File(context.getExternalFilesDir(null), name).outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
        } finally { image.recycle() } }
    }
    @Test fun priorityNoticeIsVisibleBeforeResearchAndClearsWithPrivacy() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        var worker: ExecutorService? = null
        var surfaceWorker: ExecutorService? = null
        try {
            seed(names)
            HealthRecordStore(context, names.records).use {
                it.save(HealthDraft(HealthMetric.BLOOD_PRESSURE, mapOf("systolic" to "185", "diastolic" to "90"), "mmHg",
                    System.currentTimeMillis() - 365L * 86_400_000))
            }
            HealthCareEngine.evaluate(context, names)
            val issue = HealthCareStore(context, names.care).use { it.forMetric(HealthMetric.BLOOD_PRESSURE)!! }
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)).use { scenario ->
                scenario.onActivity { activity ->
                    activity.healthCareSurface?.destroy()
                    activity.healthCareSurface = HealthCareAgentSurface(activity, names).also {
                        it.showForAgent(true); it.resume()
                        surfaceWorker = HealthCareAgentSurface::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(it) as ExecutorService
                    }
                }
                await(scenario) { find(it, "health-care-priority-notice") != null }
                scenario.onActivity { activity ->
                    val text = views(find(activity, "health-care-priority-notice")!!).filterIsInstance<TextView>().joinToString { it.text.toString() }
                    assertTrue(text.contains(activity.getString(R.string.health_care_bp_emergency)))
                    assertTrue(text.contains("185 / 90")); assertTrue(text.contains("mmHg"))
                    val notice = find(activity, "health-care-priority-notice")!!
                    val routine = find(activity, "agent-health-care-concern")!!
                    assertTrue(notice.top < routine.top)
                    activity.healthCareSurface!!.showForAgent(false)
                    assertNull(find(activity, "health-care-priority-notice"))
                    activity.healthCareSurface!!.showForAgent(true)
                }
                await(scenario) { find(it, "health-care-priority-notice") != null }
                capture("health-care-priority-agent-fixture.png")
            }
            surfaceWorker?.awaitTermination(10, TimeUnit.SECONDS)
            ActivityScenario.launch<HealthCareActivity>(Intent(context, HealthCareActivity::class.java)
                .putExtra("health_care_id", issue.id).putHealthNavigationFixture(names)).use { scenario ->
                await(scenario) { find(it, "health-care-priority-notice") != null }
                scenario.onActivity { activity ->
                    val text = views(find(activity, "health-care-priority-notice")!!).filterIsInstance<TextView>().map { it.text.toString() }
                    listOf(R.string.health_care_bp_emergency, R.string.health_care_bp_recheck, R.string.health_care_bp_scope,
                        R.string.health_care_bp_history, R.string.health_care_bp_source).forEach { assertTrue(text.contains(activity.getString(it))) }
                    worker = HealthCareActivity::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(activity) as ExecutorService
                }
                capture("health-care-priority-detail-fixture.png")
                scenario.recreate()
                await(scenario) { find(it, "health-care-priority-notice") != null }
                scenario.onActivity { worker = HealthCareActivity::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(it) as ExecutorService }
                scenario.moveToState(Lifecycle.State.CREATED)
                scenario.onActivity { assertNull(find(it, "health-care-priority-notice")) }
                scenario.moveToState(Lifecycle.State.RESUMED)
                await(scenario) { find(it, "health-care-priority-notice") != null }
                HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version) }
                await(scenario) { find(it, "health-care-priority-notice") == null }
            }
        } finally {
            surfaceWorker?.awaitTermination(10, TimeUnit.SECONDS); worker?.awaitTermination(10, TimeUnit.SECONDS); clean(names)
        }
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
                    assertNotNull(find(activity, "health-care-discuss"))
                    val comparison = (find(activity, "health-care-comparison") as TextView).text.toString()
                    assertTrue(comparison.contains("6.3")); assertTrue(comparison.contains("5.4"))
                    assertTrue(comparison.contains(activity.getString(R.string.health_care_comparison_not_clinical)))
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
                    val label = views(find(activity, "agent-health-care-concern")!!).filterIsInstance<TextView>().joinToString { it.text.toString() }
                    assertTrue(label.contains("6.3")); assertTrue(label.contains("5.4"))
                    assertNotNull(find(activity, "agent-health-care-series"))
                    activity.healthCareSurface!!.showForAgent(false)
                    assertNull(find(activity, "agent-health-care-concern"))
                    assertNull(find(activity, "agent-health-care-series"))
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
