package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.KeyguardManager
import android.app.TimePickerDialog
import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthCareVisitReviewUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun field(value: Any, name: String) = value.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(value)
    private fun editor(activity: Any) = (field(activity, "reminderEditor\$delegate") as Lazy<*>).value!!
    private fun dialog(activity: Any) = field(editor(activity), "dialog") as? AlertDialog
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun find(activity: HealthCareVisitFollowUpActivity, tag: String) = views(activity.window.decorView).firstOrNull { it.tag == tag }
    private fun await(scenario: ActivityScenario<HealthCareVisitFollowUpActivity>, ready: (HealthCareVisitFollowUpActivity) -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 20000
        do { var done = false; scenario.onActivity { done = ready(it) }; if (done) return; SystemClock.sleep(50) }
        while (SystemClock.elapsedRealtime() < end)
        fail("Journal review UI did not reach its expected state")
    }
    private fun fixture(test: (HealthCareVisitFollowUpFixture, ActivityScenario<HealthCareVisitFollowUpActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        HealthCareVisitFollowUpFixture(context).use { f ->
            f.start(); lateinit var worker: ExecutorService; lateinit var actionWorker: ExecutorService
            ActivityScenario.launch<HealthCareVisitFollowUpActivity>(Intent(context, HealthCareVisitFollowUpActivity::class.java)
                .putHealthNavigationFixture(f.names).putExtra("health_care_id", f.issue.id).putExtra("health_encounter_id", f.visit.id)).use { scenario ->
                scenario.onActivity { worker = field(it, "worker") as ExecutorService
                    actionWorker = field((field(it, "actionReview\$delegate") as Lazy<*>).value!!, "worker") as ExecutorService }
                await(scenario) { find(it, "visit-review-schedule") != null }
                test(f, scenario)
            }
            assertTrue(worker.awaitTermination(20, TimeUnit.SECONDS)); assertTrue(actionWorker.awaitTermination(20, TimeUnit.SECONDS))
            assertFalse(HealthCareVisitReviewVisibility.contains(f.names.care, f.visit.id))
        }
    }
    private fun confirmScreen(scenario: ActivityScenario<HealthCareVisitFollowUpActivity>) {
        scenario.onActivity {
            find(it, "visit-review-schedule")!!.performClick()
            assertTrue(dialog(it) is DatePickerDialog); dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
        }
        await(scenario) { dialog(it) is TimePickerDialog }
        scenario.onActivity {
            assertTrue(dialog(it) is TimePickerDialog); dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
        }
        await(scenario) { dialog(it)?.let { d -> d !is TimePickerDialog && d !is DatePickerDialog && d.isShowing } == true }
    }
    @Test fun dateTimeAndFinalConfirmationAreRequiredAndCancellationCreatesNothing(): Unit = fixture { f, scenario ->
        confirmScreen(scenario); assertNull(f.snapshot().reminder)
        scenario.onActivity { dialog(it)!!.getButton(AlertDialog.BUTTON_NEGATIVE).performClick() }
        assertNull(f.snapshot().reminder); assertEquals(f.issue.actions, f.snapshot().visit.issue.actions)
    }
    @Test fun confirmedReminderDisplaysAndCanBeCancelledWithoutChangingJournal(): Unit = fixture { f, scenario ->
        confirmScreen(scenario)
        scenario.onActivity { dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick() }
        await(scenario) { find(it, "visit-review-cancel") != null && !(field(it, "busy") as Boolean) }
        assertEquals(HealthCareReminderState.SCHEDULED, f.snapshot().reminder!!.state)
        if (InstrumentationRegistry.getArguments().getString("health_visit_review_screenshot") == "true") {
            scenario.onActivity { activity ->
                val target = find(activity, "visit-review-schedule")!!
                target.requestRectangleOnScreen(android.graphics.Rect(0, 0, target.width, target.height + 350), false)
            }
            instrumentation.waitForIdleSync(); SystemClock.sleep(300)
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap -> try {
                File(context.getExternalFilesDir(null), "health-visit-review-fixture.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            } finally { bitmap.recycle() } }
        }
        scenario.onActivity { find(it, "visit-review-cancel")!!.performClick() }
        await(scenario) { find(it, "visit-review-status") != null && find(it, "visit-review-cancel") == null && !(field(it, "busy") as Boolean) }
        assertEquals(HealthCareReminderState.CANCELLED, f.snapshot().reminder!!.state)
        assertEquals(HealthCareVisitFollowUpState.ACTIVE, f.snapshot().followUp!!.state)
    }
    @Test fun backgroundClearsPickerAndForegroundSuppressionWithoutSaving(): Unit = fixture { f, scenario ->
        confirmScreen(scenario); assertTrue(HealthCareVisitReviewVisibility.contains(f.names.care, f.visit.id))
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertNull(dialog(it)); assertNull(field(it, "snapshot")) }
        assertFalse(HealthCareVisitReviewVisibility.contains(f.names.care, f.visit.id)); assertNull(f.snapshot().reminder)
        scenario.moveToState(Lifecycle.State.RESUMED)
        await(scenario) { find(it, "visit-review-schedule") != null }
        assertTrue(HealthCareVisitReviewVisibility.contains(f.names.care, f.visit.id))
    }
    @Test fun concurrentJournalPauseDismissesConfirmationAndDisablesSchedule(): Unit = fixture { f, scenario ->
        confirmScreen(scenario)
        f.record(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.PAUSE, note = "Synthetic concurrent pause"))
        await(scenario) { dialog(it) == null && find(it, "visit-followup-RESUME") != null }
        scenario.onActivity { assertNull(find(it, "visit-review-schedule")) }
        assertNull(f.snapshot().reminder)
    }
}
