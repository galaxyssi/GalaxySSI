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
import org.json.JSONObject
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
    private fun capture(name: String) {
        if (InstrumentationRegistry.getArguments().getString("health_care_screenshot") != "true") return
        instrumentation.waitForIdleSync()
        // Dialog visibility precedes its compositor transition; capture the settled surface.
        SystemClock.sleep(300)
        instrumentation.uiAutomation.takeScreenshot()?.let { bitmap -> try {
            File(context.getExternalFilesDir(null), name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        } finally { bitmap.recycle() } }
    }
    private fun fixture(authorized: Boolean = false, questionsShared: Boolean = false,
        block: (ActivityScenario<HealthCareActivity>, HealthOverviewDatabases, HealthCarePlan) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        var worker: ExecutorService? = null
        try {
            val plan = HealthCareMaintenanceTestFixture.propose(context, names)
            if (authorized) HealthCareStore(context, names.care).use { store ->
                val consent = HealthCareResearchAuthorization(UUID.randomUUID().toString(), plan.grant.copy(questionsShared = questionsShared), "b".repeat(64))
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
    @Test fun structuredAssessmentIsReadableAndClearedWhenBackgrounded() = fixture(true) { scenario, names, plan ->
        val saved = HealthCareStore(context, names.care).use { store ->
            val job = store.latestResearchJob(plan.grant.concernId)!!
            HealthCareModelReviewTestFixture.record(store, job)
        }
        scenario.onActivity { find(it, "health-care-research")!!.performClick() }
        await(scenario) { dialog(review(it))?.isShowing == true }
        scenario.onActivity {
            val text = views(dialog(review(it))!!.window!!.decorView).filterIsInstance<TextView>()
            assertEquals(saved.input.summary, text.single { view -> view.tag == "health-model-review-summary" }.text.toString())
            assertTrue(text.any { view -> view.text.toString() == saved.input.nextStep })
            assertTrue(text.any { view -> view.text.toString() == context.getString(R.string.health_model_review_notice) })
            assertTrue(HealthCareModelReviewVisibility.contains(names.care, saved.grant.conversationId))
        }
        capture("health-model-review-fixture.png")
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertNull(dialog(review(it))) }
        assertFalse(HealthCareModelReviewVisibility.contains(names.care, saved.grant.conversationId))
        HealthCareStore(context, names.care).use { assertEquals(saved, it.modelReview(saved.grant.turnId)) }
    }
    @Test fun clarificationOpensOnlyItsReferencedQuestionsAndClearsInBackground() = fixture(true, true) { scenario, names, plan ->
        val saved = HealthCareStore(context, names.care).use { care ->
            val job = care.latestResearchJob(plan.grant.concernId)!!
            val grant = care.researchAuthorization(job.concernId)!!.scope.copy(turnId = job.turnId,
                researchAuthorizationId = job.authorizationId, approvedAt = System.currentTimeMillis())
            care.approveDiscussion(grant)
            val q = care.proposeQuestion(grant, "measurement.timing", "本次测量前的活动是什么？", "核对可比性。", System.currentTimeMillis())
            care.proposeQuestion(grant, "measurement.other", "另一个合成问题", "只用于验证范围。", System.currentTimeMillis())
            care.recordModelReview(grant, HealthCareModelReviewTestFixture.input(care, job.concernId).copy(
                decision = HealthCareReviewDecision.CLARIFY, questions = listOf(HealthCareQuestionRef(q.id, q.revision))), System.currentTimeMillis())
        }
        fun questionDialog(activity: HealthCareActivity): AlertDialog? {
            val owner = HealthCareResearchReview::class.java.getDeclaredField("questionReview").apply { isAccessible = true }
                .get(review(activity)) ?: return null
            return HealthCareQuestionReview::class.java.getDeclaredField("dialog").apply { isAccessible = true }.get(owner) as? AlertDialog
        }
        scenario.onActivity { find(it, "health-care-research")!!.performClick() }
        await(scenario) { dialog(review(it))?.isShowing == true }
        scenario.onActivity {
            views(dialog(review(it))!!.window!!.decorView).first { view -> view.tag == "health-model-review-questions" }.performClick()
        }
        await(scenario) { questionDialog(it)?.isShowing == true }
        scenario.onActivity {
            val rows = views(questionDialog(it)!!.window!!.decorView).filter { view -> view.tag?.toString()?.startsWith("health-question-row-") == true }
            assertEquals(listOf("health-question-row-${saved.input.questions.single().id}"), rows.map { view -> view.tag })
        }
        capture("health-model-clarification-fixture.png")
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertNull(questionDialog(it)) }
        HealthCareStore(context, names.care).use {
            assertEquals(saved, it.modelReview(saved.grant.turnId))
            assertEquals(2, it.questions(it.concern(saved.grant.concernId)!!).items.size)
            val issue = it.concern(saved.grant.concernId)!!
            val q = it.question(saved.input.questions.single().id)!!
            it.reviewQuestion(issue.id, issue.revision, q.id, q.revision, HealthCareQuestionState.ANSWERED,
                "\u6d4b\u91cf\u524d\u5b89\u9759\u4f11\u606f", System.currentTimeMillis())
        }
        scenario.moveToState(Lifecycle.State.RESUMED)
        scenario.onActivity { review(it).show(saved.grant.concernId) }
        await(scenario) { dialog(review(it))?.isShowing == true }
        scenario.onActivity {
            views(dialog(review(it))!!.window!!.decorView).first { view -> view.tag == "health-model-review-questions" }.performClick()
        }
        await(scenario) { questionDialog(it)?.isShowing == true }
        scenario.onActivity { activity ->
            val texts = views(questionDialog(activity)!!.window!!.decorView).filterIsInstance<TextView>().map { it.text.toString() }
            assertTrue(texts.any { it.contains(activity.getString(R.string.health_question_answered)) })
            assertFalse(texts.any { it.contains(activity.getString(R.string.health_question_open)) })
        }
        HealthCareStore(context, names.care).use { assertEquals(saved, it.modelReview(saved.grant.turnId)) }
    }
    @Test fun stopActionRevokesConsentAndKeepsDurableCancellation() = fixture(true) { scenario, names, plan ->
        scenario.onActivity { find(it, "health-care-research")!!.performClick() }
        await(scenario) { dialog(review(it))?.isShowing == true }
        capture("health-research-fixture.png")
        scenario.onActivity {
            val d = dialog(review(it))!!
            assertNotNull(views(d.window!!.decorView).firstOrNull { view -> view.tag == "health-research-state" })
            val scope = views(d.window!!.decorView).first { view -> view.tag == "health-research-feedback-scope" } as TextView
            assertEquals(context.getString(R.string.health_research_feedback_off), scope.text.toString())
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
        HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.HEIGHT,
            mapOf("height" to "170"), "cm", System.currentTimeMillis() - 1000)) }
        HealthCareEngine.evaluate(context, names)
        val issue = HealthCareStore(context, names.care).use { it.concern(plan.grant.concernId)!! }
        val options = HealthCareStore(context, names.care).use { HealthCareRelatedContext.options(it, issue.metric) }
        assertTrue(options.none { it.metric == issue.metric })
        assertTrue(options.any { it.metric == HealthMetric.HEIGHT })
        val preview = HealthCareDiscussionPreview(issue, plan.grant,
            AgentCallableTarget("fixture-provider", "Synthetic model", AgentConnectorKind.AGENT, AgentConnectorStatus.AVAILABLE, emptyList()),
            HealthCareDiscussionPolicy.snapshot(issue), "核对新证据。",
            AgentAction("fixture", AgentActionKind.CALL_CONNECTOR, "fixture-provider", AgentRisk.LOW, AgentActionStatus.PENDING_CONFIRMATION, "Fixture"),
            AgentModelSelection(), null, options)
        scenario.onActivity {
            val method = HealthCareResearchReview::class.java.getDeclaredMethod("consent", HealthCareDiscussionPreview::class.java, String::class.java)
                .apply { isAccessible = true }
            method.invoke(review(it), preview, null)
            val d = dialog(review(it))!!
            val check = views(d.window!!.decorView).first { view -> view.tag == "health-research-consent" } as CheckBox
            val feedback = views(d.window!!.decorView).first { view -> view.tag == "health-research-feedback-history" } as CheckBox
            val raw = views(d.window!!.decorView).first { view -> view.tag == "health-research-data-preview" } as TextView
            val height = views(d.window!!.decorView).first { view -> view.tag == "health-research-related-HEIGHT" } as CheckBox
            assertFalse(height.isChecked)
            assertFalse(JSONObject(raw.text.toString()).has("related_measurements"))
            height.performClick()
            assertEquals("HEIGHT", JSONObject(raw.text.toString()).getJSONObject("related_measurements")
                .getJSONArray("selected").getJSONObject(0).getString("metric"))
            assertFalse(feedback.isChecked)
            assertFalse(JSONObject(raw.text.toString()).getJSONObject("feedback_history").getBoolean("authorized"))
            feedback.performClick()
            assertTrue(feedback.isChecked)
            assertTrue(JSONObject(raw.text.toString()).getJSONObject("feedback_history").getBoolean("authorized"))
            assertTrue(JSONObject(raw.text.toString()).has("related_measurements"))
            height.performClick()
            assertFalse(JSONObject(raw.text.toString()).has("related_measurements"))
            assertTrue(JSONObject(raw.text.toString()).getJSONObject("feedback_history").getBoolean("authorized"))
            feedback.performClick()
            assertFalse(JSONObject(raw.text.toString()).getJSONObject("feedback_history").getBoolean("authorized"))
            feedback.performClick()
            assertFalse(check.isChecked); assertFalse(d.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled)
        }
        capture("health-research-consent-fixture.png")
        scenario.onActivity {
            val d = dialog(review(it))!!
            val check = views(d.window!!.decorView).first { view -> view.tag == "health-research-consent" } as CheckBox
            check.performClick(); assertTrue(d.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled)
            d.getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
        }
        await(scenario) { dialog(review(it)) == null }
        HealthCareStore(context, names.care).use {
            assertNull(it.researchAuthorization(issue.id)); assertTrue(it.researchJobs(issue.id).isEmpty())
        }
        scenario.onActivity {
            HealthCareResearchReview::class.java.getDeclaredMethod("consent", HealthCareDiscussionPreview::class.java, String::class.java)
                .apply { isAccessible = true }.invoke(review(it), preview, null)
            val d = dialog(review(it))!!
            assertTrue(views(d.window!!.decorView).filterIsInstance<CheckBox>().all { check -> !check.isChecked })
            assertFalse(d.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled)
        }
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertNull(dialog(review(it))) }
        HealthCareStore(context, names.care).use { assertNull(it.researchAuthorization(issue.id)) }
    }
}
