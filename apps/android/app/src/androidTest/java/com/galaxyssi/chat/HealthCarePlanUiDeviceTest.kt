package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
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

class HealthCarePlanUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun find(activity: Activity, tag: String) = views(activity.window.decorView).firstOrNull { it.tag == tag }
    private fun dialog(review: HealthCarePlanReview) = HealthCarePlanReview::class.java.getDeclaredField("dialog")
        .apply { isAccessible = true }.get(review) as? AlertDialog
    private fun review(activity: HealthCareActivity) = HealthCareActivity::class.java.getDeclaredMethod("getPlanReview")
        .apply { isAccessible = true }.invoke(activity) as HealthCarePlanReview
    private fun <T : Activity> await(scenario: ActivityScenario<T>, predicate: (T) -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 20000
        do { var ready = false; scenario.onActivity { ready = predicate(it) }; if (ready) return; SystemClock.sleep(50) }
        while (SystemClock.elapsedRealtime() < deadline)
        fail("Health plan UI did not reach expected state")
    }
    private fun worker(instance: Any) = instance.javaClass.getDeclaredField("worker").apply { isAccessible = true }.get(instance) as ExecutorService
    private fun clean(names: HealthOverviewDatabases) = listOf(names.care, names.records, names.privacy).forEach(context::deleteDatabase)
    private fun capture(name: String = "health-plan-review-fixture.png") {
        if (InstrumentationRegistry.getArguments().getString("health_care_screenshot") != "true") return
        instrumentation.waitForIdleSync()
        instrumentation.uiAutomation.waitForIdle(500, 5000)
        SystemClock.sleep(500)
        instrumentation.uiAutomation.takeScreenshot()?.let { image -> try {
            File(context.getExternalFilesDir(null), name).outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
        } finally { image.recycle() } }
    }
    @Test fun agentPageReviewsOnlyExplicitlySelectedSteps() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        val transcripts = AgentTranscriptStore(context)
        val previous = transcripts.activeConversation().id
        val temporary = transcripts.createAgentConversation("Synthetic plan UI", privateMode = true, trackingPaused = true)
        val workers = mutableListOf<ExecutorService>()
        try {
            transcripts.switchConversation(temporary.id)
            val plan = HealthCarePlanTestFixture.propose(context, names)
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", temporary.id)).use { scenario ->
                await(scenario) { it.agentTranscriptStore.activeConversation().id == temporary.id && it.renderedAgentTranscriptSourceEntries.isEmpty() }
                lateinit var review: HealthCarePlanReview
                scenario.onActivity { activity ->
                    activity.healthCareSurface?.destroy()
                    activity.healthCareSurface = HealthCareAgentSurface(activity, names).also { surface ->
                        workers += worker(surface)
                        review = HealthCareAgentSurface::class.java.getDeclaredField("planReview").apply { isAccessible = true }.get(surface) as HealthCarePlanReview
                        workers += worker(review); surface.showForAgent(true); surface.resume()
                    }
                }
                await(scenario) { find(it, "agent-health-care-plan") != null }
                scenario.onActivity { find(it, "agent-health-care-plan")!!.performClick() }
                await(scenario) { dialog(review)?.isShowing == true }
                scenario.onActivity {
                    val d = dialog(review)!!
                    assertFalse(d.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled)
                    val checks = views(d.window!!.decorView).filterIsInstance<CheckBox>()
                    assertEquals(2, checks.size); assertTrue(checks.none { it.isChecked })
                    checks.first().performClick(); assertTrue(d.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled)
                }
                capture()
                scenario.onActivity { dialog(review)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick() }
                await(scenario) { find(it, "agent-health-care-plan") == null }
                HealthCareStore(context, names.care).use {
                    val saved = it.concern(plan.grant.concernId)!!
                    assertEquals(listOf(plan.actions.first().id), saved.actions.map { it.id }); assertNull(it.nextDue())
                    assertEquals(HealthCarePlanState.ACCEPTED, it.plan(plan.id)!!.state)
                }
            }
        } finally {
            workers.forEach { it.awaitTermination(10, TimeUnit.SECONDS) }
            transcripts.switchConversation(previous); transcripts.deleteConversation(temporary.id); clean(names)
        }
    }
    @Test fun carePageCancelBackgroundAndRecreationDoNotAcceptDraft() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString()); val workers = mutableListOf<ExecutorService>()
        try {
            val plan = HealthCarePlanTestFixture.propose(context, names)
            val tag = "health-care-plan-${plan.id}"
            ActivityScenario.launch<HealthCareActivity>(Intent(context, HealthCareActivity::class.java)
                .putHealthNavigationFixture(names).putExtra("health_care_id", plan.grant.concernId)).use { scenario ->
                await(scenario) { find(it, tag) != null }
                scenario.onActivity { workers += worker(it); workers += worker(review(it)); find(it, tag)!!.performClick() }
                await(scenario) { dialog(review(it))?.isShowing == true }
                scenario.onActivity { dialog(review(it))!!.getButton(AlertDialog.BUTTON_NEUTRAL).performClick() }
                HealthCareStore(context, names.care).use { assertEquals(plan, it.plan(plan.id)) }
                scenario.onActivity { find(it, tag)!!.performClick() }
                await(scenario) { dialog(review(it))?.isShowing == true }
                scenario.moveToState(Lifecycle.State.CREATED)
                scenario.onActivity { assertNull(dialog(review(it))) }
                scenario.moveToState(Lifecycle.State.RESUMED)
                await(scenario) { find(it, tag) != null }
                scenario.recreate()
                await(scenario) { find(it, tag) != null }
                scenario.onActivity { workers += worker(it); workers += worker(review(it)); find(it, tag)!!.performClick() }
                await(scenario) { dialog(review(it))?.isShowing == true }
                scenario.onActivity { dialog(review(it))!!.getButton(AlertDialog.BUTTON_NEGATIVE).performClick() }
                await(scenario) { find(it, tag) == null }
                HealthCareStore(context, names.care).use { assertTrue(it.concern(plan.grant.concernId)!!.actions.isEmpty()) }
            }
        } finally { workers.forEach { it.awaitTermination(10, TimeUnit.SECONDS) }; clean(names) }
    }
    @Test fun revokingHealthPermissionDismissesOpenReview() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString()); val workers = mutableListOf<ExecutorService>()
        try {
            val plan = HealthCarePlanTestFixture.propose(context, names)
            val tag = "health-care-plan-${plan.id}"
            ActivityScenario.launch<HealthCareActivity>(Intent(context, HealthCareActivity::class.java)
                .putHealthNavigationFixture(names).putExtra("health_care_id", plan.grant.concernId)).use { scenario ->
                await(scenario) { find(it, tag) != null }
                scenario.onActivity { workers += worker(it); workers += worker(review(it)); find(it, tag)!!.performClick() }
                await(scenario) { dialog(review(it))?.isShowing == true }
                HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version) }
                await(scenario) { dialog(review(it)) == null && find(it, tag) == null }
                HealthCareStore(context, names.care).use { assertEquals(plan, it.plan(plan.id)) }
            }
        } finally { workers.forEach { it.awaitTermination(10, TimeUnit.SECONDS) }; clean(names) }
    }
    @Test fun applicabilityGapsDisableOnlyTheAffectedActionAndShowSourceConflicts() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString()); val workers = mutableListOf<ExecutorService>()
        try {
            val plan = HealthCarePlanTestFixture.propose(context, names) { HealthCareApplicabilityTestFixture.input(it, true) }
            val tag = "health-care-plan-${plan.id}"
            ActivityScenario.launch<HealthCareActivity>(Intent(context, HealthCareActivity::class.java)
                .putHealthNavigationFixture(names).putExtra("health_care_id", plan.grant.concernId)).use { scenario ->
                await(scenario) { find(it, tag) != null }
                scenario.onActivity { workers += worker(it); workers += worker(review(it)); find(it, tag)!!.performClick() }
                await(scenario) { dialog(review(it))?.isShowing == true }
                scenario.onActivity { activity ->
                    val d = dialog(review(activity))!!
                    val all = views(d.window!!.decorView)
                    val checks = all.filterIsInstance<CheckBox>()
                    assertFalse(checks[0].isEnabled); assertTrue(checks[1].isEnabled)
                    val text = (all.single { it.tag == "health-plan-applicability-0" } as TextView).text.toString()
                    assertTrue(text.contains(activity.getString(R.string.health_applicability_conflict)))
                    assertTrue(text.contains(activity.getString(R.string.health_care_unknown)))
                    assertTrue(text.contains(plan.applicability.getValue(plan.actions[0].id).conflicts.single().nextStep))
                    assertFalse(d.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled)
                    checks[1].performClick(); assertTrue(d.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled)
                }
                capture("health-plan-applicability-fixture.png")
                scenario.onActivity { dialog(review(it))!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick() }
                await(scenario) { find(it, tag) == null }
                HealthCareStore(context, names.care).use { store ->
                    assertEquals(listOf(plan.actions[1].id), store.concern(plan.grant.concernId)!!.actions.map { it.id })
                    assertNull(store.nextDue())
                }
            }
        } finally { workers.forEach { it.awaitTermination(10, TimeUnit.SECONDS) }; clean(names) }
    }
}
