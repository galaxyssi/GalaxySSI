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
import android.widget.EditText
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthCareVisitFollowUpUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun field(value: Any, name: String) = value.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(value)
    private fun editor(activity: Activity) = (field(activity, "editor\$delegate") as Lazy<*>).value!!
    private fun dialog(activity: Activity) = field(editor(activity), "dialog") as? AlertDialog
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun find(activity: Activity, tag: String) = (views(activity.window.decorView) +
        dialog(activity)?.window?.decorView?.let(::views).orEmpty()).firstOrNull { it.tag == tag }
    private fun await(scenario: ActivityScenario<HealthCareVisitFollowUpActivity>, ready: (HealthCareVisitFollowUpActivity) -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 15000
        do { var done = false; scenario.onActivity { done = ready(it) }; if (done) return; SystemClock.sleep(50) }
        while (SystemClock.elapsedRealtime() < end)
        fail("Follow-up UI did not reach the expected state")
    }
    private fun fixture(seed: Boolean = true, test: (HealthCareVisitFollowUpFixture, ActivityScenario<HealthCareVisitFollowUpActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        HealthCareVisitFollowUpFixture(context).use { f ->
            if (seed) f.start()
            lateinit var worker: ExecutorService
            ActivityScenario.launch<HealthCareVisitFollowUpActivity>(Intent(context, HealthCareVisitFollowUpActivity::class.java)
                .putHealthNavigationFixture(f.names).putExtra("health_care_id", f.issue.id).putExtra("health_encounter_id", f.visit.id)).use { scenario ->
                scenario.onActivity { worker = field(it, "worker") as ExecutorService }
                await(scenario) { find(it, if(seed) "visit-followup-CHECK_IN" else "visit-followup-START") != null }
                test(f, scenario)
            }
            assertTrue(worker.awaitTermination(20, TimeUnit.SECONDS))
        }
    }
    private fun save(scenario: ActivityScenario<HealthCareVisitFollowUpActivity>) {
        scenario.onActivity { dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick() }
        await(scenario) { dialog(it) == null && !(field(it, "busy") as Boolean) && field(it, "snapshot") != null }
    }
    @Test fun explicitStartAndCheckinPersistIndependentFieldsWithoutCompletingTheIssue(): Unit = fixture(false) { f, scenario ->
        val before = f.snapshot().visit.issue
        scenario.onActivity {
            find(it, "visit-followup-START")!!.performClick()
            dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick(); assertTrue(dialog(it)!!.isShowing)
            (find(it, "visit-followup-goal") as EditText).setText("合成测试：跟进日常活动能力")
        }
        save(scenario)
        scenario.onActivity {
            find(it, "visit-followup-CHECK_IN")!!.performClick()
            (find(it, "visit-followup-feelings") as EditText).setText("合成自述：与昨天相似")
            (find(it, "visit-followup-function") as EditText).setText("合成记录：日常活动")
            (find(it, "visit-followup-sleep") as EditText).setText("合成睡眠记录")
            (find(it, "visit-followup-needs-review") as CheckBox).performClick()
        }
        save(scenario)
        val after = f.snapshot()
        assertEquals(HealthCareVisitFollowUpState.REVIEW, after.followUp!!.state)
        assertEquals("合成睡眠记录", after.history.items.first().input.sleep)
        assertEquals(before.actions, after.visit.issue.actions); assertEquals(before.assessment, after.visit.issue.assessment)
        if (InstrumentationRegistry.getArguments().getString("health_visit_followup_screenshot") == "true") {
            instrumentation.waitForIdleSync(); SystemClock.sleep(250)
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap -> try {
                File(context.getExternalFilesDir(null), "health-visit-followup-fixture.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            } finally { bitmap.recycle() } }
        }
    }
    @Test fun cancelClearsTextAndCannotAddAnObservation(): Unit = fixture { f, scenario ->
        lateinit var input: EditText
        scenario.onActivity {
            find(it, "visit-followup-CHECK_IN")!!.performClick(); input = find(it, "visit-followup-feelings") as EditText
            input.setText("合成未保存内容"); dialog(it)!!.getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
        }
        await(scenario) { dialog(it) == null }
        scenario.onActivity { assertTrue(input.text.isEmpty()) }
        assertEquals(1, f.snapshot().history.items.size)
    }
    @Test fun archiveNeedsAcknowledgementAndReopenReturnsToReview(): Unit = fixture { f, scenario ->
        scenario.onActivity {
            find(it, "visit-followup-ARCHIVE")!!.performClick()
            (find(it, "visit-followup-note") as EditText).setText("用户暂时结束记录，不代表康复")
            dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick(); assertTrue(dialog(it)!!.isShowing)
            (find(it, "visit-followup-acknowledge") as CheckBox).performClick()
        }
        save(scenario)
        scenario.onActivity {
            assertNull(find(it, "visit-followup-CHECK_IN")); find(it, "visit-followup-REOPEN")!!.performClick()
            (find(it, "visit-followup-note") as EditText).setText("继续记录并重新核对")
        }
        save(scenario)
        assertEquals(HealthCareVisitFollowUpState.REVIEW, f.snapshot().followUp!!.state)
        assertEquals(f.issue.stage, f.snapshot().visit.issue.stage)
    }
    @Test fun pauseResumeDoesNotDeleteHistoryOrCreateReminders(): Unit = fixture { f, scenario ->
        scenario.onActivity {
            find(it, "visit-followup-PAUSE")!!.performClick(); (find(it, "visit-followup-note") as EditText).setText("合成暂停原因")
        }
        save(scenario)
        scenario.onActivity {
            assertNull(find(it, "visit-followup-CHECK_IN")); find(it, "visit-followup-RESUME")!!.performClick()
            (find(it, "visit-followup-note") as EditText).setText("合成继续原因")
        }
        save(scenario)
        assertEquals(3, f.snapshot().history.items.size)
        HealthCareStore(context, f.names.care).use { assertTrue(it.reminders(f.issue.id).isEmpty()) }
    }
    @Test fun maintenanceDiscussionDoesNotChangeTheClinicalStage(): Unit = fixture { f, scenario ->
        scenario.onActivity {
            find(it, "visit-followup-REVIEW")!!.performClick()
            (find(it, "visit-followup-note") as EditText).setText("需要讨论长期维护，不代表已经确认")
            dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick(); assertTrue(dialog(it)!!.isShowing)
            find(it, "visit-followup-decision-DISCUSS_MAINTENANCE")!!.performClick()
        }
        save(scenario)
        assertEquals(HealthCareVisitFollowUpState.REVIEW, f.snapshot().followUp!!.state)
        assertEquals(f.issue.stage, f.snapshot().visit.issue.stage)
    }
    @Test fun backgroundAndMemoryPressureDiscardUnsavedPlaintext(): Unit = fixture { f, scenario ->
        lateinit var input: EditText
        scenario.onActivity {
            find(it, "visit-followup-CHECK_IN")!!.performClick(); input = find(it, "visit-followup-feelings") as EditText
            input.setText("合成后台清理内容")
        }
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertNull(dialog(it)); assertNull(field(it, "snapshot")); assertTrue(input.text.isEmpty()) }
        scenario.moveToState(Lifecycle.State.RESUMED)
        await(scenario) { find(it, "visit-followup-CHECK_IN") != null }
        scenario.onActivity { it.onTrimMemory(android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW); assertNull(field(it, "snapshot")) }
        await(scenario) { find(it, "visit-followup-CHECK_IN") != null }
        assertEquals(1, f.snapshot().history.items.size)
    }
    @Test fun revokedPrivacyDismissesOpenEditor(): Unit = fixture { f, scenario ->
        scenario.onActivity { find(it, "visit-followup-CHECK_IN")!!.performClick() }
        HealthPrivacyStore(context, f.names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        await(scenario) { dialog(it) == null && field(it, "snapshot") == null && !(field(it, "busy") as Boolean) }
        HealthCareStore(context, f.names.care).use { assertEquals(1, it.visitFollowUpHistory(f.issue.id, f.visit.id).items.size) }
    }
    @Test fun historyPagesAndDeletionRemainResponsive(): Unit = fixture { f, scenario ->
        repeat(32) { f.record(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.CHECK_IN, note = "合成历史 $it")) }
        await(scenario) { find(it, "visit-followup-next") != null && !(field(it, "busy") as Boolean) }
        scenario.onActivity {
            assertEquals(30, views(it.window.decorView).count { v -> v.tag?.toString()?.startsWith("visit-followup-event-") == true })
            find(it, "visit-followup-next")!!.performClick()
        }
        await(scenario) { find(it, "visit-followup-previous") != null }
        scenario.onActivity {
            assertEquals(3, views(it.window.decorView).count { v -> v.tag?.toString()?.startsWith("visit-followup-event-") == true })
            find(it, "visit-followup-delete")!!.performClick()
            (field(it, "dialog") as AlertDialog).getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
        }
        assertNotNull(f.snapshot().followUp)
        scenario.onActivity {
            find(it, "visit-followup-delete")!!.performClick()
            (field(it, "dialog") as AlertDialog).getButton(AlertDialog.BUTTON_POSITIVE).performClick()
        }
        await(scenario) { find(it, "visit-followup-START") != null }
        assertNull(f.snapshot().followUp)
    }
}
