package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthCareAnswerDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore, HealthCareDiscussionGrant, AgentTranscriptEntry) -> Unit) {
        val names = HealthOverviewDatabases(id())
        try {
            HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
                mapOf("glucose" to "6.3"), "mmol/L", System.currentTimeMillis() - 1000, reference = "4-6")) }
            HealthCareStore(context, names.care).use { care ->
                care.configure(true, ""); HealthCareEngine.evaluate(context, names)
                val before = care.forMetric(HealthMetric.GLUCOSE)!!
                val issue = care.bindDiscussion(before.id, before.revision, id())
                val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
                val grant = HealthCareDiscussionGrant(issue.conversationId, id(), issue.id, issue.revision,
                    care.settings().version, privacy.version, "a".repeat(64), System.currentTimeMillis(), "fixture", "fixture-model", "high",
                    questionsShared = true, userInputDigest = AgentNativeJsonCodec.sha256("合成原话：没有，持续了两天。"))
                care.approveDiscussion(grant)
                val entry = AgentTranscriptEntry(id(), AgentTranscriptRole.USER, "合成原话：没有，持续了两天。", System.currentTimeMillis(),
                    conversationId = grant.conversationId, turnId = grant.turnId)
                test(names, care, grant, entry)
            }
        } finally { listOf(names.care, names.records, names.profile, names.privacy, names.reminders).forEach(context::deleteDatabase) }
    }
    private fun question(care: HealthCareStore, grant: HealthCareDiscussionGrant, key: String = "sample.notes") =
        care.proposeQuestion(grant, key, "合成问题：这次检测前有哪些变化？", "核对本次记录的可比性", System.currentTimeMillis())
    private fun propose(names: HealthOverviewDatabases, grant: HealthCareDiscussionGrant, q: HealthCareQuestion, source: AgentTranscriptEntry?,
        extra: AgentNativeJsonObject = emptyMap()) = HealthCareQuestionTools.execute(context, names, HealthCareAnswerTool.ID,
            AgentNativeToolInvocationContext(conversationId = grant.conversationId, turnId = grant.turnId),
            mapOf("question_id" to q.id, "question_revision" to q.revision, "quote" to "没有", "answer" to "没有") + extra,
            userSource = { source })
    private fun accept(names: HealthOverviewDatabases, care: HealthCareStore, draft: HealthCareAnswerDraft, entry: AgentTranscriptEntry?,
        text: String = draft.answer) = care.reviewAnswer(draft.id, true, text,
            HealthPrivacyStore(context, names.privacy).use { it.policy() }, entry, System.currentTimeMillis())
    @Test fun stagedAnswersDoNotChangeHealthFactsAndSurviveReopenEncrypted(): Unit = fixture { names, care, grant, entry ->
        val q = question(care, grant); val issue = care.concern(q.concernId)!!
        val receipt = propose(names, grant, q, entry); assertFalse(receipt.getBoolean("answer_saved_by_tool"))
        val draft = care.answer(receipt.getString("draft_id"))!!
        assertEquals(issue, care.concern(issue.id)); assertEquals(q, care.question(q.id))
        assertEquals(HealthCareAnswerState.PENDING, draft.state)
        HealthCareStore(context, names.care).use { assertEquals(draft, it.answer(draft.id)) }
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.rawQuery("SELECT payload FROM answer_drafts", null).use {
                assertTrue(it.moveToFirst()); assertFalse(it.getBlob(0).toString(Charsets.UTF_8).contains("没有"))
            }
        }
    }
    @Test fun explicitReviewEditsOnceWithoutOverwritingTheReport(): Unit = fixture { names, care, grant, entry ->
        val q = question(care, grant); val issue = care.concern(q.concernId)!!
        val draft = care.answer(propose(names, grant, q, entry).getString("draft_id"))!!
        val done = accept(names, care, draft, entry, "用户核对后修改的合成回答")
        assertEquals(HealthCareAnswerState.ACCEPTED, done.state)
        assertEquals(done.reviewedAnswer, care.question(q.id)!!.answer)
        assertEquals(issue.assessment, care.concern(issue.id)!!.assessment)
        val after = care.concern(issue.id)!!
        assertEquals(done, accept(names, care, draft, entry, "retry must not replace"))
        assertEquals(after, care.concern(issue.id)); assertEquals(2, care.question(q.id)!!.revision)
        assertTrue(care.answers(after).items.isEmpty())
    }
    @Test fun duplicateToolCallsAndDismissalDoNotReopenTheDraft(): Unit = fixture { names, care, grant, entry ->
        val q = question(care, grant)
        val first = propose(names, grant, q, entry).getString("draft_id")
        assertEquals(first, propose(names, grant, q, entry, mapOf("answer" to "different wording")).getString("draft_id"))
        care.reviewAnswer(first, false, "", HealthPrivacyStore(context, names.privacy).use { it.policy() }, null, System.currentTimeMillis())
        assertEquals("DISMISSED", propose(names, grant, q, entry).getString("review_state"))
        assertEquals(q, care.question(q.id)); assertTrue(care.answers(care.concern(q.concernId)!!).items.isEmpty())
        assertEquals(HealthCareAnswerState.DISMISSED, accept(names, care, care.answer(first)!!, entry).state)
    }
    @Test fun sourceOwnershipQuoteAndConfirmationInjectionAreRejected(): Unit = fixture { names, care, grant, entry ->
        val q = question(care, grant)
        listOf(null, entry.copy(turnId = id()), entry.copy(conversationId = id()), entry.copy(role = AgentTranscriptRole.ASSISTANT),
            entry.copy(text = "The model guessed: 没有")).forEach {
            assertTrue(runCatching { propose(names, grant, q, it) }.exceptionOrNull() is HealthCareConflict)
        }
        assertTrue(runCatching { propose(names, grant, q, entry, mapOf("quote" to "invented")) }.isFailure)
        assertTrue(runCatching { propose(names, grant, q, entry, mapOf("confirmed" to true)) }.isFailure)
        assertTrue(care.answers(care.concern(q.concernId)!!).items.isEmpty())
    }
    @Test fun sourceRevisionAndQuestionRevisionPreventStaleConfirmation(): Unit = fixture { names, care, grant, entry ->
        val q = question(care, grant)
        val draft = care.answer(propose(names, grant, q, entry).getString("draft_id"))!!
        care.reviewQuestion(q.concernId, grant.revision, q.id, 1, HealthCareQuestionState.ANSWERED, "newer human answer", System.currentTimeMillis())
        assertTrue(runCatching { accept(names, care, draft, entry) }.exceptionOrNull() is HealthCareConflict)
        assertEquals("newer human answer", care.question(q.id)!!.answer)
        assertEquals(HealthCareAnswerState.PENDING, care.answer(draft.id)!!.state)
    }
    @Test fun revokedPermissionAndDeletedUserMessagePreventConfirmation(): Unit = fixture { names, care, grant, entry ->
        val q = question(care, grant); val draft = care.answer(propose(names, grant, q, entry).getString("draft_id"))!!
        assertTrue(runCatching { accept(names, care, draft, null) }.isFailure)
        HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.ONLINE_ANALYSIS, true, it.policy().version) }
        assertTrue(runCatching { accept(names, care, draft, entry) }.isFailure)
        assertEquals(q, care.question(q.id))
    }
    @Test fun twoIndependentAnswersCanBeConfirmedAndPauseIsPreserved(): Unit = fixture { names, care, grant, entry ->
        val questions = listOf(question(care, grant, "sample.one"), question(care, grant, "sample.two"))
        val drafts = questions.map { care.answer(propose(names, grant, it, entry).getString("draft_id"))!! }
        val issue = care.concern(grant.concernId)!!
        care.update(issue.id, issue.revision, "fixture_pause") { it.copy(stage = HealthCareStage.PAUSED) }
        drafts.forEach { accept(names, care, it, entry) }
        assertEquals(HealthCareStage.PAUSED, care.concern(issue.id)!!.stage)
        questions.forEach { assertEquals(HealthCareQuestionState.ANSWERED, care.question(it.id)!!.state) }
    }
    @Test fun pendingDraftsPageAndAreRemovedWithTheirConcern(): Unit = fixture { names, care, grant, entry ->
        val ids = (0..34).map { propose(names, grant, question(care, grant, "sample.q$it"), entry).getString("draft_id") }.toSet()
        val issue = care.concern(grant.concernId)!!
        val first = care.answers(issue); val second = care.answers(issue, first.next!!)
        assertEquals(30, first.items.size); assertEquals(5, second.items.size); assertNull(second.next)
        assertEquals(ids, (first.items + second.items).map { it.id }.toSet())
        care.delete(issue.id, issue.revision); ids.forEach { assertNull(care.answer(it)) }
    }
    @Test fun versionEightMigrationKeepsExistingQuestions(): Unit = fixture { names, care, grant, _ ->
        val q = question(care, grant); care.close()
        context.openOrCreateDatabase(names.care, 0, null).use {
            removeHealthEncounterTestTables(it)
            it.execSQL("DROP TABLE action_feedback"); it.execSQL("DROP TABLE action_agenda"); it.execSQL("DROP TABLE action_agenda_state")
            it.execSQL("DROP TABLE answer_drafts"); it.version = 8
        }
        HealthCareStore(context, names.care).use { reopened ->
            assertEquals(q, reopened.question(q.id)); assertTrue(reopened.answers(reopened.concern(q.concernId)!!).items.isEmpty())
        }
        context.openOrCreateDatabase(names.care, 0, null).use { assertEquals(17, it.version) }
    }
    @Test fun originalUserLookupIsIndexedAndDoesNotUseAssistantOrForeignTurns() {
        val name = "health-answer-transcript-${id()}.db"
        try {
            AgentTranscriptEntryDatabase(context, name).use { db ->
                val user = AgentTranscriptEntry(id(), AgentTranscriptRole.USER, "原始合成回答", 100, conversationId = id(), turnId = id())
                db.insert(user)
                repeat(100) { db.insert(user.copy(id = id(), role = AgentTranscriptRole.ASSISTANT, text = "not a human reply")) }
                val restored = db.firstEntryForTurn(user.conversationId, user.turnId)!!
                assertEquals(user.id, restored.id); assertEquals(user.text, restored.text); assertEquals(user.role, restored.role)
                assertNull(db.firstEntryForTurn(id(), user.turnId)); assertNull(db.firstEntryForTurn(user.conversationId, id()))
            }
        } finally { context.deleteDatabase(name) }
    }
    private fun views(root: View): List<View> = listOf(root) + if (root is ViewGroup) (0 until root.childCount).flatMap { views(root.getChildAt(it)) } else emptyList()
    private fun dialog(review: HealthCareAnswerReview) = HealthCareAnswerReview::class.java.getDeclaredField("dialog")
        .apply { isAccessible = true }.get(review) as? AlertDialog
    private fun await(scenario: ActivityScenario<HealthCareActivity>, ready: (HealthCareActivity) -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 20_000
        do { var done = false; scenario.onActivity { done = ready(it) }; if (done) return; SystemClock.sleep(50) } while (SystemClock.elapsedRealtime() < deadline)
        fail("Answer review did not reach its expected state")
    }
    @Test fun userCanEditConfirmAndClearDraftReviewOnBackground(): Unit = fixture { names, care, grant, entry ->
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val q = question(care, grant); val draft = care.answer(propose(names, grant, q, entry).getString("draft_id"))!!
        var worker: ExecutorService? = null
        try {
            ActivityScenario.launch<HealthCareActivity>(Intent(context, HealthCareActivity::class.java)
                .putExtra("health_care_id", q.concernId).putHealthNavigationFixture(names)).use { scenario ->
                lateinit var review: HealthCareAnswerReview
                await(scenario) { views(it.window.decorView).any { v -> v.tag == "health-care-answers" } }
                scenario.onActivity {
                    worker = HealthCareActivity::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(it) as ExecutorService
                    review = HealthCareAnswerReview(it, names) { entry }
                    HealthCareActivity::class.java.getDeclaredField("answerReview\$delegate").apply { isAccessible = true }.set(it, lazyOf(review))
                    views(it.window.decorView).first { v -> v.tag == "health-care-answers" }.performClick()
                }
                await(scenario) { dialog(review)?.isShowing == true }
                scenario.onActivity { views(dialog(review)!!.window!!.decorView).first { v -> v.tag == "health-answer-row-${draft.id}" }.performClick() }
                await(scenario) { dialog(review)?.window?.decorView?.let { root -> views(root).any { it.tag == "health-answer-input" } } == true }
                if (InstrumentationRegistry.getArguments().getString("health_answer_screenshot") == "true") {
                    InstrumentationRegistry.getInstrumentation().waitForIdleSync()
                    SystemClock.sleep(600)
                    InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()?.let { bitmap -> try {
                        java.io.File(context.getExternalFilesDir(null), "health-answer-review-fixture.png").outputStream().use {
                            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                        }
                    } finally { bitmap.recycle() } }
                }
                scenario.moveToState(Lifecycle.State.CREATED); scenario.onActivity { assertNull(dialog(review)) }
                assertEquals(HealthCareAnswerState.PENDING, care.answer(draft.id)!!.state)
                scenario.moveToState(Lifecycle.State.RESUMED)
                await(scenario) { views(it.window.decorView).any { v -> v.tag == "health-care-answers" } }
                scenario.onActivity { review.show(q.concernId) }; await(scenario) { dialog(review)?.isShowing == true }
                scenario.onActivity { views(dialog(review)!!.window!!.decorView).first { v -> v.tag == "health-answer-row-${draft.id}" }.performClick() }
                await(scenario) { dialog(review)?.window?.decorView?.let { root -> views(root).any { it.tag == "health-answer-input" } } == true }
                scenario.onActivity {
                    (views(dialog(review)!!.window!!.decorView).first { v -> v.tag == "health-answer-input" } as EditText).setText("合成回答，已经人工核对")
                    dialog(review)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
                }
                await(scenario) { dialog(review) == null }
                assertEquals("合成回答，已经人工核对", care.question(q.id)!!.answer)
                assertEquals(HealthCareAnswerState.ACCEPTED, care.answer(draft.id)!!.state)
            }
        } finally { worker?.awaitTermination(10, TimeUnit.SECONDS) }
    }
}
