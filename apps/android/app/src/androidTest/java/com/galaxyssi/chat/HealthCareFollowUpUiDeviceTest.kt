package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.KeyguardManager
import android.app.TimePickerDialog
import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
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

class HealthCareFollowUpUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun find(activity: Activity, tag: String) = views(activity.window.decorView).firstOrNull { it.tag == tag }
    private fun review(activity: HealthCareActivity) = HealthCareActivity::class.java.getDeclaredMethod("getActionReview")
        .apply { isAccessible = true }.invoke(activity) as HealthCareActionReview
    private fun dialog(review: HealthCareActionReview) = HealthCareActionReview::class.java.getDeclaredField("dialog")
        .apply { isAccessible = true }.get(review) as? AlertDialog
    private fun <T : Activity> await(scenario: ActivityScenario<T>, ready: (T) -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 20000
        do { var done = false; scenario.onActivity { done = ready(it) }; if (done) return; SystemClock.sleep(50) }
        while (SystemClock.elapsedRealtime() < end)
        fail("Health follow-up UI did not reach expected state")
    }
    private fun fixture(block: (HealthOverviewDatabases, HealthCareConcern, ActivityScenario<HealthCareActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString()); val workers = mutableListOf<ExecutorService>()
        try {
            val issue = HealthCareFollowUpTestFixture.confirmed(context, names)
            ActivityScenario.launch<HealthCareActivity>(Intent(context, HealthCareActivity::class.java)
                .putHealthNavigationFixture(names).putExtra("health_care_id", issue.id)).use { scenario ->
                await(scenario) { find(it, "health-care-followup-${issue.actions.first().id}") != null }
                scenario.onActivity {
                    listOf(it, review(it)).forEach { instance -> workers += instance.javaClass.getDeclaredField("worker")
                        .apply { isAccessible = true }.get(instance) as ExecutorService }
                }
                block(names, issue, scenario)
            }
        } finally {
            workers.forEach { it.awaitTermination(10, TimeUnit.SECONDS) }
            listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase)
        }
    }
    private fun open(scenario: ActivityScenario<HealthCareActivity>, actionId: String) {
        scenario.onActivity { find(it, "health-care-followup-$actionId")!!.performClick() }
        await(scenario) { dialog(review(it))?.isShowing == true }
    }
    @Test fun scheduleRequiresDateTimeConfirmationAndCanBeCancelled(): Unit = fixture { names, issue, scenario ->
        val id = issue.actions.first().id
        open(scenario, id)
        scenario.onActivity { views(dialog(review(it))!!.window!!.decorView).first { v -> v.tag == "health-care-followup-schedule" }.performClick() }
        scenario.onActivity { assertTrue(dialog(review(it)) is DatePickerDialog); dialog(review(it))!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick() }
        scenario.onActivity { assertTrue(dialog(review(it)) is TimePickerDialog); dialog(review(it))!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick() }
        HealthCareStore(context, names.care).use { assertNull(it.reminder(id)) }
        scenario.onActivity { dialog(review(it))!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick() }
        await(scenario) { dialog(review(it)) == null }
        val deadline = SystemClock.elapsedRealtime() + 5000
        while (HealthCareStore(context, names.care).use { it.reminder(id) } == null && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(30)
        HealthCareStore(context, names.care).use { assertEquals(HealthCareReminderState.SCHEDULED, it.reminder(id)!!.state) }
        open(scenario, id)
        if (InstrumentationRegistry.getArguments().getString("health_care_screenshot") == "true") {
            instrumentation.waitForIdleSync(); instrumentation.uiAutomation.waitForIdle(500, 5000); SystemClock.sleep(500)
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap -> try {
                File(context.getExternalFilesDir(null), "health-followup-fixture.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            } finally { bitmap.recycle() } }
        }
        scenario.onActivity { views(dialog(review(it))!!.window!!.decorView).first { v -> v.tag == "health-care-followup-cancel" }.performClick() }
        await(scenario) { dialog(review(it)) == null }
        val cancelledBy = SystemClock.elapsedRealtime() + 5000
        while (HealthCareStore(context, names.care).use { it.reminder(id)?.state } != HealthCareReminderState.CANCELLED &&
            SystemClock.elapsedRealtime() < cancelledBy) SystemClock.sleep(30)
        HealthCareStore(context, names.care).use { assertEquals(HealthCareReminderState.CANCELLED, it.reminder(id)!!.state) }
    }
    @Test fun agentMainOpensFollowUpAndClearsItInBackground() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        val transcripts = AgentTranscriptStore(context)
        val previous = transcripts.activeConversation().id
        val temporary = transcripts.createAgentConversation("Synthetic follow-up UI", privateMode = true, trackingPaused = true)
        val workers = mutableListOf<ExecutorService>()
        try {
            transcripts.switchConversation(temporary.id)
            val issue = HealthCareFollowUpTestFixture.confirmed(context, names)
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", temporary.id)).use { scenario ->
                await(scenario) { it.agentTranscriptStore.activeConversation().id == temporary.id && it.renderedAgentTranscriptSourceEntries.isEmpty() }
                lateinit var review: HealthCareActionReview
                scenario.onActivity { activity ->
                    activity.healthCareSurface?.destroy()
                    activity.healthCareSurface = HealthCareAgentSurface(activity, names).also { surface ->
                        review = HealthCareAgentSurface::class.java.getDeclaredField("actionReview")
                            .apply { isAccessible = true }.get(surface) as HealthCareActionReview
                        listOf(surface, review).forEach { instance -> workers += instance.javaClass.getDeclaredField("worker")
                            .apply { isAccessible = true }.get(instance) as ExecutorService }
                        surface.showForAgent(true); surface.resume()
                    }
                }
                await(scenario) { find(it, "agent-health-care-followup") != null }
                scenario.onActivity { find(it, "agent-health-care-followup")!!.performClick() }
                await(scenario) { dialog(review)?.isShowing == true }
                scenario.onActivity {
                    assertTrue(views(dialog(review)!!.window!!.decorView).any { v -> v.tag == "health-care-followup-schedule" })
                }
                scenario.moveToState(Lifecycle.State.CREATED)
                scenario.onActivity { assertNull(dialog(review)) }
                scenario.moveToState(Lifecycle.State.RESUMED)
                await(scenario) { find(it, "agent-health-care-followup") != null }
                HealthCareStore(context, names.care).use { store ->
                    assertEquals(issue, store.concern(issue.id))
                    assertNull(store.reminder(issue.actions.first().id))
                }
            }
        } finally {
            workers.forEach { it.awaitTermination(10, TimeUnit.SECONDS) }
            transcripts.switchConversation(previous); transcripts.deleteConversation(temporary.id)
            listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase)
        }
    }
    @Test fun outcomeRequiredAndOnlySelectedActionCompletes(): Unit = fixture { names, issue, scenario ->
        val id = issue.actions.first().id
        open(scenario, id)
        scenario.onActivity { views(dialog(review(it))!!.window!!.decorView).first { v -> v.tag == "health-care-followup-complete" }.performClick() }
        scenario.onActivity {
            val d = dialog(review(it))!!; d.getButton(AlertDialog.BUTTON_POSITIVE).performClick(); assertTrue(d.isShowing)
            (views(d.window!!.decorView).first { v -> v.tag == "health-care-followup-outcome" } as EditText).setText("已整理复查问题，隔离测试。")
            d.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
        }
        await(scenario) { dialog(review(it)) == null }
        val deadline = SystemClock.elapsedRealtime() + 5000
        while (HealthCareStore(context, names.care).use { it.concern(issue.id)!!.revision } == issue.revision && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(30)
        HealthCareStore(context, names.care).use { store ->
            val saved = store.concern(issue.id)!!
            assertEquals(HealthCareStage.REASSESS, saved.stage)
            assertEquals(HealthCareActionState.DONE, saved.actions.first().state)
            assertEquals(HealthCareActionState.CONFIRMED, saved.actions.last().state)
        }
    }
    @Test fun backgroundAndPrivacyRevocationDismissSensitiveFollowUp(): Unit = fixture { names, issue, scenario ->
        val id = issue.actions.first().id; open(scenario, id)
        scenario.moveToState(Lifecycle.State.CREATED); scenario.onActivity { assertNull(dialog(review(it))) }
        scenario.moveToState(Lifecycle.State.RESUMED)
        await(scenario) { find(it, "health-care-followup-$id") != null }; open(scenario, id)
        HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version) }
        await(scenario) { dialog(review(it)) == null && find(it, "health-care-followup-$id") == null }
        HealthCareStore(context, names.care).use { assertNull(it.reminder(id)); assertEquals(issue, it.concern(issue.id)) }
    }
}
