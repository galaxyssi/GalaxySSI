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

class HealthCareResearchUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun find(activity: Activity, tag: String) = views(activity.window.decorView).firstOrNull { it.tag == tag }
    private fun dialog(review: HealthCareResearchReview) = HealthCareResearchReview::class.java.getDeclaredField("dialog")
        .apply { isAccessible = true }.get(review) as? AlertDialog
    private fun review(activity: HealthCareActivity) = HealthCareActivity::class.java.getDeclaredMethod("getResearchReview")
        .apply { isAccessible = true }.invoke(activity) as HealthCareResearchReview
    private fun <T : Activity> await(scenario: ActivityScenario<T>, ready: (T) -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 20000
        do { var done = false; scenario.onActivity { done = ready(it) }; if (done) return; SystemClock.sleep(50) }
        while (SystemClock.elapsedRealtime() < deadline)
        fail("Research UI did not reach expected state")
    }
    private fun fixture(authorized: Boolean = false, block: (ActivityScenario<HealthCareActivity>, HealthOverviewDatabases, HealthCarePlan) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        var worker: ExecutorService? = null
        try {
            val plan = HealthCareMaintenanceTestFixture.propose(context, names)
            if (authorized) HealthCareStore(context, names.care).use { store ->
                val consent = HealthCareResearchAuthorization(UUID.randomUUID().toString(), plan.grant, "b".repeat(64))
                store.authorizeResearch(consent, null)
                store.queueResearch(consent.id, plan.grant.concernId, System.currentTimeMillis())
            }
            ActivityScenario.launch<HealthCareActivity>(Intent(context, HealthCareActivity::class.java)
                .putHealthNavigationFixture(names).putExtra("health_care_id", plan.grant.concernId)).use { scenario ->
                await(scenario) { find(it, "health-care-research") != null }
                scenario.onActivity { worker = HealthCareResearchReview::class.java.getDeclaredField("worker").apply { isAccessible = true }
                    .get(review(it)) as ExecutorService }
                block(scenario, names, plan)
            }
        } finally {
            worker?.awaitTermination(10, TimeUnit.SECONDS)
            listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase)
        }
    }
    @Test fun stopActionRevokesConsentAndKeepsDurableCancellation() = fixture(true) { scenario, names, plan ->
        scenario.onActivity { find(it, "health-care-research")!!.performClick() }
        await(scenario) { dialog(review(it))?.isShowing == true }
        if (InstrumentationRegistry.getArguments().getString("health_care_screenshot") == "true") {
            instrumentation.waitForIdleSync()
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap -> try {
                File(context.getExternalFilesDir(null), "health-research-fixture.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            } finally { bitmap.recycle() } }
        }
        scenario.onActivity {
            val d = dialog(review(it))!!
            assertNotNull(views(d.window!!.decorView).firstOrNull { view -> view.tag == "health-research-state" })
            views(d.window!!.decorView).first { view -> view.tag == "health-research-revoke" }.performClick()
        }
        await(scenario) { dialog(review(it))?.isShowing == true &&
            views(dialog(review(it))!!.window!!.decorView).none { view -> view.tag == "health-research-revoke" } }
        HealthCareStore(context, names.care).use {
            assertFalse(it.researchAuthorization(plan.grant.concernId)!!.active)
            assertEquals(1, it.pendingResearchCancellations().size)
        }
    }
    @Test fun statusDialogIsClearedInBackgroundWithoutChangingAuthorization() = fixture(true) { scenario, names, plan ->
        lateinit var owned: HealthCareResearchReview
        scenario.onActivity { owned = review(it); find(it, "health-care-research")!!.performClick() }
        await(scenario) { dialog(owned)?.isShowing == true }
        scenario.moveToState(Lifecycle.State.CREATED)
        instrumentation.runOnMainSync { assertNull(dialog(owned)) }
        HealthCareStore(context, names.care).use { assertTrue(it.researchAuthorization(plan.grant.concernId)!!.active) }
        scenario.moveToState(Lifecycle.State.RESUMED)
        await(scenario) { find(it, "health-care-research") != null }
    }
    @Test fun consentIsUncheckedAndCancelNeverStartsResearch() = fixture { scenario, names, plan ->
        val issue = HealthCareStore(context, names.care).use { it.concern(plan.grant.concernId)!! }
        val preview = HealthCareDiscussionPreview(issue, plan.grant,
            AgentCallableTarget("fixture-provider", "Synthetic model", AgentConnectorKind.AGENT, AgentConnectorStatus.AVAILABLE, emptyList()),
            "合成测试资料，不属于个人档案。", "核对新证据。",
            AgentAction("fixture", AgentActionKind.CALL_CONNECTOR, "fixture-provider", AgentRisk.LOW, AgentActionStatus.PENDING_CONFIRMATION, "Fixture"),
            AgentModelSelection(), null)
        scenario.onActivity {
            val method = HealthCareResearchReview::class.java.getDeclaredMethod("consent", HealthCareDiscussionPreview::class.java, String::class.java)
                .apply { isAccessible = true }
            method.invoke(review(it), preview, null)
            val d = dialog(review(it))!!
            val check = views(d.window!!.decorView).filterIsInstance<CheckBox>().single()
            assertFalse(check.isChecked); assertFalse(d.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled)
            check.performClick(); assertTrue(d.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled)
            d.getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
            assertNull(dialog(review(it)))
        }
        HealthCareStore(context, names.care).use {
            assertNull(it.researchAuthorization(issue.id)); assertTrue(it.researchJobs(issue.id).isEmpty())
        }
    }
}
