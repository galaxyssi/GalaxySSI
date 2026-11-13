package com.galaxyssi.chat

import android.content.Context
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.impl.WorkManagerImpl
import java.io.File
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Real model questions and production follow-up; the reviewed answer is an isolated synthetic fixture. */
class HealthCareClarificationLoopDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext.applicationContext
    private val markers get() = context.getSharedPreferences("health-clarification-probe", Context.MODE_PRIVATE)
    private val concern get() = checkNotNull(markers.getString("concern", null))
    private val conversation get() = checkNotNull(markers.getString("conversation", null))
    private var observedTurn: String? = null

    @Test fun reviewedQuestionAutomaticallyContinuesWithoutRepeatingKnownContext() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("health_clarification_loop") == "true")
        requireIsolation()
        val phase = InstrumentationRegistry.getArguments().getString("health_clarification_phase") ?: "answer"
        require(phase in setOf("answer", "resume", "inspect"))
        if (phase == "inspect") { inspect(); diagnose(); return }
        AppStore.ensureInitialized(context)
        GalaxySSIMqttClient.connect(context)
        await(45_000, "Paired transport ready") { GalaxySSIMqttClient.isRequestReplyReady() }
        if (phase == "resume") {
            check(markers.contains("followup")) { "Resume the saved follow-up without another answer or authorization" }
            assertNotEquals(markers.getString("process", ""), AgentProcessIdentity.instanceId)
            AgentStartupRecovery.enqueue(context).result.get(30, TimeUnit.SECONDS)
        }
        if (!markers.contains("authorization")) prepare()
        val initial = capture("initial")
        await(600_000, "Initial model assessment and durable clarification") { healthy(initial).state == HealthCareResearchState.COMPLETED }
        val questionId = HealthCareStore(context).use { care ->
            val issue = care.concern(concern)!!
            val question = questions(care, issue).singleOrNull { it.key == "context.fasting_hours" }
                ?: error("The real model did not retain the missing fasting-duration question")
            assertEquals(initial, question.turnId)
            if (!markers.contains("question")) {
                assertEquals(HealthCareQuestionState.OPEN, question.state)
                check(markers.edit().putString("question", question.id).putInt("question_revision", question.revision).commit())
            }
            assertEquals(markers.getString("question", ""), question.id)
            assertNotNull(care.modelReview(initial))
            question.id
        }
        if (!markers.getBoolean("answered", false)) {
            HealthCareStore(context).use { care ->
                val issue = care.concern(concern)!!
                val question = care.question(questionId)!!
                if (question.state == HealthCareQuestionState.OPEN) care.reviewQuestion(issue.id, issue.revision,
                    question.id, question.revision, HealthCareQuestionState.ANSWERED, ANSWER, System.currentTimeMillis())
                else assertEquals(ANSWER, question.answer)
                val saved = care.question(questionId)!!
                assertEquals(HealthCareQuestionState.ANSWERED, saved.state)
                check(markers.edit().putBoolean("answered", true).putInt("answered_revision", saved.revision).commit())
            }
        }
        val next = capture("followup", initial)
        if (phase == "answer") {
            await(90_000, "Follow-up saved before process restart") {
                healthy(next)
                val state = SharedPreferencesAgentSessionStore(context, "task:$next").load()
                state?.phase == AgentPhase.WAITING_RESPONSE && state.lastActionResult?.metadata?.get("source_message_id")
                    ?.toLongOrNull()?.let { it > 0 } == true
            }
            assertTrue(SharedPreferencesAgentSessionStore(context, "task:$next").load()!!.currentGoal.contains(ANSWER))
            check(markers.edit().putString("process", AgentProcessIdentity.instanceId).commit())
            println("HEALTH_CLARIFICATION model_question=true user_review_trigger=true ready_for_process_restart=true")
            return
        }
        await(600_000, "Question response reassessed in the original conversation") { healthy(next).state == HealthCareResearchState.COMPLETED }
        val before = work().map { it.id }.toSet()
        HealthCareStore(context).use { care ->
            val issue = care.concern(concern)!!
            val row = care.question(questionId)!!
            assertEquals(markers.getInt("answered_revision", 0), row.revision)
            assertEquals(ANSWER, row.answer)
            val view = HealthCareQuestionPolicy.view(row, issue, HealthCareQuestionPolicy.known(issue, null))
            assertEquals("ANSWERED", view.getString("state")); assertFalse(view.getBoolean("ask_again"))
            assertEquals(1, questions(care, issue).count { it.key == row.key })
            assertEquals(row, care.reviewQuestion(issue.id, issue.revision, row.id, row.revision,
                HealthCareQuestionState.ANSWERED, ANSWER, System.currentTimeMillis()))
            assertEquals(issue, care.concern(concern))
            assertNull(issue.context!!.fastingHours)
            assertEquals(HealthCareTruth.YES, issue.context.adult)
            assertEquals(HealthCareTruth.NO, issue.context.pregnant)
            assertEquals(HealthCareTruth.NO, issue.context.diagnosedDiabetes)
            assertEquals(HealthCareSpecimen.LAB_PLASMA, issue.context.specimen)
            assertEquals(HealthCareTruth.NO, issue.context.illnessOrMedication)
            assertTrue(issue.actions.isEmpty()); assertNull(issue.target); assertNull(issue.maintenance); assertNull(care.nextReminder())
            val review = checkNotNull(care.modelReview(next))
            assertEquals(conversation, review.grant.conversationId)
            assertTrue(review.input.records.any { it.id == markers.getString("record", "") })
            assertNotNull(care.modelReview(initial))
        }
        await(90_000, "Repeated answer reconciled without a duplicate research turn") {
            val created = work().filter { it.id !in before }
            created.any { it.state == WorkInfo.State.SUCCEEDED } && created.all { it.state.isFinished }
        }
        HealthCareStore(context).use { care ->
            assertEquals(setOf(initial, next), care.researchJobs(concern).map { it.turnId }.toSet())
            assertTrue(care.researchJobs(concern).all { it.state == HealthCareResearchState.COMPLETED })
            care.pendingPlans(concern).forEach { assertEquals(HealthCarePlanState.PENDING, it.state) }
            val consent = care.researchAuthorization(concern)!!
            if (consent.active) care.revokeResearch(concern, consent.id, System.currentTimeMillis())
        }
        HealthRecordStore(context).use { records ->
            val original = checkNotNull(records.record(markers.getString("record", "")!!))
            assertEquals(1L, records.count())
            assertEquals(1, original.revision)
            assertEquals(HealthMetric.GLUCOSE, original.draft.metric)
            assertEquals(mapOf("glucose" to "6.3"), original.draft.values)
            assertEquals("mmol/L", original.draft.unit)
            assertEquals(markers.getLong("time", 0), original.draft.measuredAt)
            assertEquals("fasting", original.draft.condition)
            assertEquals("4-6", original.draft.reference)
            assertEquals("manual", original.source)
        }
        val entries = AgentTranscriptStore(context).entriesForTurn(next)
        assertTrue(entries.isNotEmpty() && entries.all { it.conversationId == conversation })
        assertTrue(entries.any { it.role == AgentTranscriptRole.ASSISTANT && it.text.isNotBlank() })
        inspect()
        println("HEALTH_CLARIFICATION original_conversation=true answered_once=true source_unchanged=true duplicate_answer_no_new_turn=true")
    }

    private fun prepare() {
        HealthPrivacyStore(context).use { if (!it.policy().online) it.change(HealthPrivacyOption.ONLINE_ANALYSIS, true, it.policy().version) }
        HealthCareStore(context).use { if (!it.settings().enabled) it.configure(true, it.settings().version) }
        if (!markers.contains("time")) check(markers.edit().putLong("time", System.currentTimeMillis() - 1000).commit())
        if (!markers.contains("record")) {
            val id = HealthRecordStore(context).use {
                when (val saved = it.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"), "mmol/L",
                    markers.getLong("time", 0), condition = "fasting", reference = "4-6"))) {
                    is HealthSaveResult.Saved -> saved.record.id
                    is HealthSaveResult.Duplicate -> saved.id
                    else -> error("Synthetic measurement save failed")
                }
            }
            check(markers.edit().putString("record", id).commit())
        }
        HealthCareEngine.evaluate(context)
        val issue = HealthCareStore(context).use { care ->
            val value = care.forMetric(HealthMetric.GLUCOSE)!!
            if (value.context == null) care.confirmContext(value.id, value.revision,
                HealthCareContext(value.assessment.record!!, HealthCareTruth.YES, HealthCareTruth.NO, HealthCareTruth.NO,
                    HealthCareSpecimen.LAB_PLASMA, illnessOrMedication = HealthCareTruth.NO, confirmedAt = System.currentTimeMillis()))
            care.concern(value.id)!!
        }
        HealthCareEngine.evaluate(context)
        val chat = HealthCareDiscussion.open(context, issue.id)
        val targets = AppStoreAgentConnectorRegistry(context).availableTargets()
        val target = targets.firstOrNull { it.id == "codex" && it.status == AgentConnectorStatus.AVAILABLE }
            ?: targets.firstOrNull { AppStore.agentIdForContact(context, it.id) == "codex" && it.status == AgentConnectorStatus.AVAILABLE }
            ?: error("Paired Codex unavailable; do not change pairing or provider")
        AgentModelSelectionSettings.selectManual(context, chat, target.id, target.invocationProfile.defaultModelId,
            target.title, AgentModelReasoningEffort.MEDIUM, rememberAsDefault = false)
        if (HealthCareStore(context).use { it.researchAuthorization(issue.id) } == null)
            HealthCareResearchRuntime.authorize(context, HealthCareResearchRuntime.preview(context, issue.id), null)
        val auth = HealthCareStore(context).use { it.researchAuthorization(issue.id)!! }
        check(auth.active && auth.scope.questionsShared)
        check(markers.edit().putString("concern", issue.id).putString("conversation", chat).putString("authorization", auth.id).commit())
    }

    private fun capture(key: String, previous: String? = null): String {
        markers.getString(key, null)?.let { return it }
        await(90_000, "Production worker created $key") { HealthCareStore(context).use {
            it.latestResearchJob(concern)?.let { job -> job.authorizationId == markers.getString("authorization", "") && job.turnId != previous } == true
        } }
        return HealthCareStore(context).use { it.latestResearchJob(concern)!!.turnId }.also {
            check(markers.edit().putString(key, it).commit())
        }
    }
    private fun questions(care: HealthCareStore, issue: HealthCareConcern) = buildList {
        var cursor = ""
        do {
            val page = care.questions(issue, cursor); addAll(page.items)
            cursor = page.next ?: break
        } while (true)
    }
    private fun healthy(turn: String): HealthCareResearchJob {
        observedTurn = turn
        return HealthCareStore(context).use { it.researchJob(turn)!! }.also {
            check(!it.terminal || it.state == HealthCareResearchState.COMPLETED) { "Research ended ${it.state}: ${it.detail.take(200)}" }
        }
    }
    private fun work() = WorkManager.getInstance(context).getWorkInfosForUniqueWork("health-authorized-research").get(10, TimeUnit.SECONDS)
    private fun await(timeout: Long, description: String, ready: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + timeout
        var next = 0L
        while (SystemClock.elapsedRealtime() < until) {
            if (ready()) return
            if (SystemClock.elapsedRealtime() >= next) { diagnose(); next = SystemClock.elapsedRealtime() + 15_000 }
            SystemClock.sleep(250)
        }
        inspect(); fail("Timed out: $description")
    }
    private fun diagnose() {
        val turn = observedTurn ?: markers.getString("followup", null) ?: markers.getString("initial", null) ?: return
        val job = HealthCareStore(context).use { it.researchJob(turn) }
        val workspace = AgentTaskRuntime.supervisor(context).findWorkspace(turn)
        println("HEALTH_CLARIFICATION job=${job?.state} workspace=${workspace?.status} active=${turn in AgentTaskRuntime.supervisor(context).activeTaskIds()}")
    }
    private fun inspect() {
        if (!markers.contains("concern")) return
        val snapshot = HealthCareStore(context).use { care ->
            val issue = care.concern(concern)!!
            JSONObject().put("questions", JSONArray(questions(care, issue).map { it.json() })).put("context", issue.context?.json())
                .put("turns", JSONArray(care.researchJobs(concern).map { job -> JSONObject()
                    .put("job", job.json()).put("assessment", care.modelReview(job.turnId)?.input?.json())
                    .put("goal", SharedPreferencesAgentSessionStore(context, "task:${job.turnId}").load()?.currentGoal)
                    .put("answer", AgentTranscriptStore(context).entriesForTurn(job.turnId).filter { it.role == AgentTranscriptRole.ASSISTANT }
                        .joinToString("\n") { it.text }) }))
        }
        File(context.filesDir, "clarification-inspection.json").writeText(snapshot.toString(2))
    }
    @Suppress("RestrictedApi")
    private fun requireIsolation() {
        check(instrumentation is HealthClarificationAcceptanceRunner)
        val prefix = "health-clarification-acceptance-"
        listOf(HealthCareStore.DEFAULT_DB, HealthRecordStore.DEFAULT_DB, HealthPrivacyStore.DEFAULT_DB,
            AgentConversationDatabase.DATABASE_NAME, "galaxyssi_agent_workspaces.db").forEach { check(context.getDatabasePath(it).name.startsWith(prefix)) }
        val manager = WorkManagerImpl.getInstance(context)
        val db = manager.javaClass.getMethod("getWorkDatabase").invoke(manager)
        val helper = db.javaClass.getMethod("getOpenHelper").invoke(db)
        val sqlite = Class.forName("androidx.sqlite.db.SupportSQLiteOpenHelper").getMethod("getWritableDatabase").invoke(helper)
        check((Class.forName("androidx.sqlite.db.SupportSQLiteDatabase").getMethod("getPath").invoke(sqlite) as String).contains(prefix))
    }
    companion object { private const val ANSWER = "这次采血前空腹10小时，期间没有摄入热量。" }
}
