package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.Spinner
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthCareQuestionDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
                mapOf("glucose" to "6.3"), "mmol/L", System.currentTimeMillis() - 1000, reference = "4-6")) }
            HealthCareStore(context, names.care).use { care ->
                care.configure(true, ""); HealthCareEngine.evaluate(context, names); test(names, care)
            }
        } finally { listOf(names.care, names.records, names.profile, names.privacy, names.reminders).forEach(context::deleteDatabase) }
    }
    private fun grant(names: HealthOverviewDatabases, care: HealthCareStore): HealthCareDiscussionGrant {
        val current = care.forMetric(HealthMetric.GLUCOSE)!!
        val issue = care.bindDiscussion(current.id, current.revision, UUID.randomUUID().toString())
        val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
        return HealthCareDiscussionGrant(issue.conversationId, UUID.randomUUID().toString(), issue.id, issue.revision,
            care.settings().version, privacy.version, "a".repeat(64), System.currentTimeMillis(), "fixture", "fixture-model", "high",
            profileLink = issue.profileLink, questionsShared = true).also(care::approveDiscussion)
    }
    private fun propose(care: HealthCareStore, grant: HealthCareDiscussionGrant, key: String = "sample.notes") =
        care.proposeQuestion(grant, key, "合成问题：这次检测前有哪些变化？", "核对是否影响本次记录的可比性", System.currentTimeMillis())
    private fun execute(names: HealthOverviewDatabases, grant: HealthCareDiscussionGrant, id: String = HealthCareQuestionTools.READ,
        input: AgentNativeJsonObject = emptyMap(), conversation: String = grant.conversationId) =
        HealthCareQuestionTools.execute(context, names, id, AgentNativeToolInvocationContext(conversationId = conversation, turnId = grant.turnId), input)

    @Test fun questionsAndReviewedAnswersSurviveReopenWithoutPlaintextStorage(): Unit = fixture { names, care ->
        val grant = grant(names, care); val q = propose(care, grant)
        val saved = care.reviewQuestion(q.concernId, grant.revision, q.id, q.revision, HealthCareQuestionState.ANSWERED,
            "synthetic-sensitive-answer", System.currentTimeMillis())
        HealthCareStore(context, names.care).use { reopened -> assertEquals(saved, reopened.question(q.id)) }
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.rawQuery("SELECT question_key,payload FROM questions", null).use {
                assertTrue(it.moveToFirst()); assertNotEquals(q.key, it.getString(0))
                assertFalse(it.getBlob(1).toString(Charsets.ISO_8859_1).contains("synthetic-sensitive-answer"))
            }
            db.rawQuery("SELECT COUNT(*) FROM question_history WHERE question_id=?", arrayOf(q.id)).use { assertTrue(it.moveToFirst()); assertEquals(2, it.getInt(0)) }
        }
    }
    @Test fun duplicateProposalsAcrossTurnsReuseAnsweredQuestionWithoutOverwriting(): Unit = fixture { names, care ->
        val first = grant(names, care); val q = propose(care, first)
        assertEquals(q, propose(care, first))
        care.reviewQuestion(q.concernId, first.revision, q.id, 1, HealthCareQuestionState.DECLINED, "", System.currentTimeMillis())
        val next = grant(names, care)
        val reused = care.proposeQuestion(next, q.key, "A different wording", "Same intent", System.currentTimeMillis())
        assertEquals(q.id, reused.id); assertEquals(HealthCareQuestionState.DECLINED, reused.state)
        assertEquals(q.question, reused.question)
        assertEquals(1, care.questions(care.concern(q.concernId)!!).items.size)
        assertTrue(execute(names, next).getJSONArray("items").getJSONObject(0).getBoolean("user_reopen_required"))
    }
    @Test fun sixtyFiveQuestionsPageWithoutLossOrDuplicates(): Unit = fixture { names, care ->
        val grant = grant(names, care); val ids = (0..64).map { propose(care, grant, "sample.q$it").id }.toSet()
        val found = mutableListOf<String>(); var after: String? = null
        do {
            val page = execute(names, grant, input = after?.let { mapOf("after_id" to it) } ?: emptyMap())
            val rows = page.getJSONArray("items"); assertTrue(rows.length() <= 30)
            (0 until rows.length()).forEach { found += rows.getJSONObject(it).getString("id") }
            after = if (page.isNull("next")) null else page.getString("next")
            assertEquals(after == null, page.getBoolean("done"))
        } while (after != null)
        assertEquals(ids, found.toSet()); assertEquals(65, found.size)
        assertTrue(care.questions(care.concern(grant.concernId)!!, found.last()).items.isEmpty())
    }
    @Test fun responseInvalidatesOldGrantAndResearchBasisButDoesNotRewriteMeasurement(): Unit = fixture { names, care ->
        val grant = grant(names, care); val q = propose(care, grant); val before = care.concern(q.concernId)!!
        care.reviewQuestion(before.id, before.revision, q.id, 1, HealthCareQuestionState.ANSWERED, "0", System.currentTimeMillis())
        val after = care.concern(before.id)!!
        assertNotEquals(HealthCareFollowUpPolicy.basis(before), HealthCareFollowUpPolicy.basis(after))
        assertEquals(before.assessment, after.assessment); assertEquals(before.context, after.context)
        assertEquals(HealthCareStage.REASSESS, after.stage)
        assertTrue(runCatching { execute(names, grant) }.exceptionOrNull() is HealthCareConflict)
        assertEquals("0", execute(names, grant(names, care)).getJSONArray("items").getJSONObject(0).getString("reviewed_answer"))
    }
    @Test fun sourceRevisionMakesOldResponseStaleAndPreventsOldTurnWrites(): Unit = fixture { names, care ->
        val grant = grant(names, care); val q = propose(care, grant)
        care.reviewQuestion(q.concernId, grant.revision, q.id, 1, HealthCareQuestionState.ANSWERED, "old answer", System.currentTimeMillis())
        val next = grant(names, care)
        val issue = care.concern(q.concernId)!!
        HealthRecordStore(context, names.records).use { records ->
            val record = records.record(issue.assessment.record!!.id)!!
            records.save(record.editable().copy(values = mapOf("glucose" to "6.4")))
        }
        assertTrue(runCatching { execute(names, next) }.exceptionOrNull() is HealthCareConflict)
        HealthCareEngine.evaluate(context, names)
        val current = grant(names, care)
        val view = execute(names, current).getJSONArray("items").getJSONObject(0)
        assertEquals("STALE", view.getString("state")); assertTrue(view.isNull("reviewed_answer"))
        assertFalse(view.toString().contains("old answer"))
    }
    @Test fun wrongSessionRevokedPrivacyAndModelAnswersAreRejected(): Unit = fixture { names, care ->
        val grant = grant(names, care); propose(care, grant)
        assertTrue(runCatching { execute(names, grant, conversation = UUID.randomUUID().toString()) }.exceptionOrNull() is HealthCareConflict)
        assertTrue(runCatching { execute(names, grant, HealthCareQuestionTools.PROPOSE,
            mapOf("key" to "sample.other", "question" to "Q?", "purpose" to "purpose", "answer" to "invented")) }.exceptionOrNull() is IllegalArgumentException)
        HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        assertTrue(runCatching { execute(names, grant) }.exceptionOrNull() is HealthCareConflict)
    }
    @Test fun legacyConsentCannotReadOrProposeQuestionsEvenWithAValidTurn(): Unit = fixture { names, care ->
        val disclosed = grant(names, care)
        val old = disclosed.copy(turnId = UUID.randomUUID().toString(), questionsShared = false)
        care.approveDiscussion(old)
        assertTrue(runCatching { execute(names, old) }.exceptionOrNull() is HealthCareConflict)
        assertTrue(runCatching { propose(care, old) }.exceptionOrNull() is HealthCareConflict)
        val q = propose(care, disclosed)
        care.reviewQuestion(q.concernId, disclosed.revision, q.id, 1, HealthCareQuestionState.ANSWERED, "self report", System.currentTimeMillis())
        val current = care.concern(q.concernId)!!
        val next = old.copy(turnId = UUID.randomUUID().toString(), revision = current.revision)
        assertTrue(runCatching { care.approveDiscussion(next) }.exceptionOrNull() is HealthCareConflict)
        assertEquals("self report", execute(names, grant(names, care)).getJSONArray("items").getJSONObject(0).getString("reviewed_answer"))
    }
    @Test fun scopeChangesDoNotImportOldAnswersAndConcernDeletionRemovesHistory(): Unit = fixture { names, care ->
        val grant = grant(names, care); val q = propose(care, grant)
        val issue = care.concern(q.concernId)!!
        val capture = HealthProfileStore(context, names.profile, names.privacy).use { it.capture(setOf(HealthProfileField.HEIGHT), emptySet()) }
        val changed = care.update(issue.id, issue.revision, "fixture_scope") {
            it.copy(profileLink = HealthCareProfileLink(HealthCareProfileScope(capture.stamp.generation, capture.fields.keys, emptySet()), capture.stamp))
        }
        assertTrue(care.questions(changed).items.isEmpty())
        assertTrue(runCatching { care.reviewQuestion(changed.id, changed.revision, q.id, 1, HealthCareQuestionState.ANSWERED, "no", System.currentTimeMillis()) }.exceptionOrNull() is HealthCareConflict)
        care.delete(changed.id, changed.revision)
        assertNull(care.question(q.id))
        context.openOrCreateDatabase(names.care, 0, null).use { db -> db.rawQuery("SELECT COUNT(*) FROM question_history", null).use {
            assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0))
        } }
    }
    @Test fun staleReviewCannotOverwriteAnotherReplyAndPauseIsPreserved(): Unit = fixture { names, care ->
        val grant = grant(names, care); val q = propose(care, grant)
        val paused = care.update(q.concernId, grant.revision, "fixture_pause") { it.copy(stage = HealthCareStage.PAUSED) }
        care.reviewQuestion(paused.id, paused.revision, q.id, 1, HealthCareQuestionState.DEFERRED, "", System.currentTimeMillis())
        assertEquals(HealthCareStage.PAUSED, care.concern(paused.id)!!.stage)
        assertTrue(runCatching { care.reviewQuestion(paused.id, paused.revision, q.id, 1, HealthCareQuestionState.ANSWERED, "race", System.currentTimeMillis()) }.exceptionOrNull() is HealthCareConflict)
        assertEquals(HealthCareQuestionState.DEFERRED, care.question(q.id)!!.state)
    }
    @Test fun savedContextIsUsedBeforeAskingAgain(): Unit = fixture { names, care ->
        val issue = care.forMetric(HealthMetric.GLUCOSE)!!
        care.confirmContext(issue.id, issue.revision, HealthCareContext(issue.assessment.record!!, pregnant = HealthCareTruth.NO,
            fastingHours = 0, confirmedAt = System.currentTimeMillis()))
        HealthCareEngine.evaluate(context, names)
        val grant = grant(names, care); propose(care, grant, "context.pregnant"); propose(care, grant, "context.fasting_hours")
        val rows = execute(names, grant).getJSONArray("items")
        assertEquals(setOf("NO", "0"), (0 until rows.length()).map { rows.getJSONObject(it).getString("saved_fact") }.toSet())
        (0 until rows.length()).forEach { assertEquals("ANSWERED", rows.getJSONObject(it).getString("state")) }
    }
    @Test fun versionSevenDatabaseUpgradesWithoutLosingConcerns() {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            var saved: HealthCareSettings
            var concern: HealthCareConcern
            HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
                mapOf("glucose" to "6.3"), "mmol/L", System.currentTimeMillis() - 1000, reference = "4-6")) }
            HealthCareStore(context, names.care).use {
                saved = it.configure(true, ""); HealthCareEngine.evaluate(context, names); concern = it.forMetric(HealthMetric.GLUCOSE)!!
            }
            context.openOrCreateDatabase(names.care, 0, null).use {
                removeHealthEncounterTestTables(it)
                it.execSQL("DROP TABLE action_feedback"); it.execSQL("DROP TABLE action_agenda"); it.execSQL("DROP TABLE action_agenda_state")
                it.execSQL("DROP TABLE answer_drafts"); it.execSQL("DROP TABLE question_history"); it.execSQL("DROP TABLE questions"); it.version = 7
            }
            HealthCareStore(context, names.care).use { assertEquals(saved, it.settings()); assertEquals(concern, it.concern(concern.id)) }
        context.openOrCreateDatabase(names.care, 0, null).use { assertEquals(17, it.version) }
        } finally { listOf(names.care, names.records, names.privacy).forEach(context::deleteDatabase) }
    }

    private fun views(root: View): List<View> = listOf(root) + if (root is ViewGroup) (0 until root.childCount).flatMap { views(root.getChildAt(it)) } else emptyList()
    private fun review(activity: HealthCareActivity) = HealthCareActivity::class.java.getDeclaredMethod("getQuestionReview")
        .apply { isAccessible = true }.invoke(activity) as HealthCareQuestionReview
    private fun dialog(activity: HealthCareActivity) = HealthCareQuestionReview::class.java.getDeclaredField("dialog")
        .apply { isAccessible = true }.get(review(activity)) as? AlertDialog
    private fun await(scenario: ActivityScenario<HealthCareActivity>, ready: (HealthCareActivity) -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 20_000
        do { var done = false; scenario.onActivity { done = ready(it) }; if (done) return; SystemClock.sleep(50) } while (SystemClock.elapsedRealtime() < deadline)
        fail("Question review did not reach its expected state")
    }
    @Test fun userCanAnswerDeferAndClearTheReviewOnBackground(): Unit = fixture { names, care ->
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val grant = grant(names, care); val q = propose(care, grant)
        var worker: ExecutorService? = null
        try {
            ActivityScenario.launch<HealthCareActivity>(Intent(context, HealthCareActivity::class.java)
                .putExtra("health_care_id", q.concernId).putHealthNavigationFixture(names)).use { scenario ->
                await(scenario) { views(it.window.decorView).any { v -> v.tag == "health-care-questions" } }
                scenario.onActivity {
                    worker = HealthCareActivity::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(it) as ExecutorService
                    review(it).show(q.concernId)
                }
                await(scenario) { dialog(it)?.isShowing == true }
                scenario.onActivity { views(dialog(it)!!.window!!.decorView).first { v -> v.tag == "health-question-row-${q.id}" }.performClick() }
                scenario.onActivity {
                    val root = dialog(it)!!.window!!.decorView
                    (views(root).first { v -> v.tag == "health-question-state" } as Spinner).setSelection(HealthCareQuestionState.ANSWERED.ordinal)
                    (views(root).first { v -> v.tag == "health-question-answer" } as EditText).setText("合成回答，仅用于测试")
                    dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
                }
                await(scenario) { dialog(it) == null }
                assertEquals(HealthCareQuestionState.ANSWERED, care.question(q.id)!!.state)
                scenario.onActivity { review(it).show(q.concernId) }; await(scenario) { dialog(it)?.isShowing == true }
                scenario.onActivity { views(dialog(it)!!.window!!.decorView).first { v -> v.tag == "health-question-row-${q.id}" }.performClick() }
                if (InstrumentationRegistry.getArguments().getString("health_question_screenshot") == "true") {
                    SystemClock.sleep(500)
                    InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()?.let { bitmap -> try {
                        java.io.File(context.getExternalFilesDir(null), "health-question-review-fixture.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                    } finally { bitmap.recycle() } }
                }
                scenario.moveToState(Lifecycle.State.CREATED); scenario.onActivity { assertNull(dialog(it)) }
                scenario.moveToState(Lifecycle.State.RESUMED)
                await(scenario) { views(it.window.decorView).any { v -> v.tag == "health-care-questions" } }
                scenario.onActivity { review(it).show(q.concernId) }; await(scenario) { dialog(it)?.isShowing == true }
                scenario.onActivity {
                    views(dialog(it)!!.window!!.decorView).first { v -> v.tag == "health-question-row-${q.id}" }.performClick()
                    (views(dialog(it)!!.window!!.decorView).first { v -> v.tag == "health-question-state" } as Spinner).setSelection(HealthCareQuestionState.DEFERRED.ordinal)
                    dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
                }
                await(scenario) { dialog(it) == null }; assertEquals(HealthCareQuestionState.DEFERRED, care.question(q.id)!!.state)
            }
        } finally { worker?.awaitTermination(10, TimeUnit.SECONDS) }
    }
}
