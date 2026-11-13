package com.galaxyssi.chat

import android.content.Context
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.impl.WorkManagerImpl
import java.io.File
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Paid opt-in acceptance through real workers and recovery, not a test-owned model/tool loop. */
class HealthCareAutomaticRelatedDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext.applicationContext
    private val markers get() = context.getSharedPreferences("health-related-probe", Context.MODE_PRIVATE)
    private val selected = setOf(HealthMetric.WEIGHT, HealthMetric.BLOOD_PRESSURE)
    private var observedTurn: String? = null

    @Test fun selectedChangeReassessesAfterProcessRecoveryWithoutUnrelatedCalls() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("health_automatic_related") == "true")
        requireIsolation()
        val phase = InstrumentationRegistry.getArguments().getString("health_related_phase") ?: "full"
        require(phase in setOf("full", "start", "recheck_start", "resume", "inspect"))
        if (phase == "inspect") { diagnose(); inspect(); return }
        AppStore.ensureInitialized(context)
        GalaxySSIMqttClient.connect(context)
        await(45_000, "Paired transport ready") { GalaxySSIMqttClient.isRequestReplyReady() }
        if (phase == "recheck_start") recheck()
        if (phase == "resume") {
            check(markers.contains("initial_turn")) { "Resume the saved test; do not create a replacement" }
            assertNotEquals(markers.getString("process", ""), AgentProcessIdentity.instanceId)
            AgentStartupRecovery.enqueue(context).result.get(30, TimeUnit.SECONDS)
        }
        if (!markers.contains("concern")) prepare()
        val concernId = markers.getString("concern", "")!!
        val conversation = markers.getString("conversation", "")!!
        val authorization = markers.getString("authorization", "")!!
        val initial = captureTurn("initial_turn", concernId, authorization)
        if (phase == "start" || phase == "recheck_start") {
            await(90_000, "Durable receipt before ending this test process") {
                val saved = SharedPreferencesAgentSessionStore(context, "task:$initial").load()
                healthy(initial)
                saved?.phase == AgentPhase.WAITING_RESPONSE &&
                    saved.lastActionResult?.metadata?.get("source_message_id")?.toLongOrNull()?.let { it > 0 } == true
            }
            check(markers.edit().putString("process", AgentProcessIdentity.instanceId).commit())
            checkGoal(initial)
            println("HEALTH_RELATED ready_for_process_restart=true")
            return
        }
        await(600_000, "Original production review completed") { healthy(initial).state == HealthCareResearchState.COMPLETED }
        verifyReview(initial, conversation, markers.getString("weight_record", "")!!)
        val changed = save("changed_weight", HealthMetric.WEIGHT, mapOf("weight" to "72"), "kg")
        // Only the ordinary record notification may reconcile and dispatch this change.
        await(90_000, "Selected record automatically reached the health projection") {
            HealthCareStore(context).use { it.relatedMeasurement(HealthMetric.WEIGHT)?.assessment?.record?.id == changed.id }
        }
        val followup = captureTurn("followup_turn", concernId, authorization, initial)
        await(600_000, "Selected change returned to the original conversation") { healthy(followup).state == HealthCareResearchState.COMPLETED }
        verifyReview(followup, conversation, changed.id)
        HealthCareStore(context).use { care ->
            val first = care.discussionGrant(initial)!!
            val next = care.discussionGrant(followup)!!
            assertEquals(first.related.keys, next.related.keys)
            assertNotEquals(first.related[HealthMetric.WEIGHT], next.related[HealthMetric.WEIGHT])
            assertEquals(first.related[HealthMetric.BLOOD_PRESSURE], next.related[HealthMetric.BLOOD_PRESSURE])
            assertEquals(first.revision, next.revision)
            assertNotEquals(care.researchJob(initial)!!.trigger, care.researchJob(followup)!!.trigger)
        }
        if (!markers.getBoolean("unrelated_verified", false)) {
            val before = work().map { it.id }.toSet()
            val unrelated = save("unrelated", HealthMetric.HEART_RATE, mapOf("pulse" to "72"), "bpm")
            await(90_000, "Unselected record fully reconciled without another research turn") {
                val evaluated = HealthCareStore(context).use {
                    it.relatedMeasurement(HealthMetric.HEART_RATE)?.assessment?.record?.id == unrelated.id
                }
                val newWork = work().filter { it.id !in before }
                evaluated && newWork.any { it.state == WorkInfo.State.SUCCEEDED } && newWork.all { it.state.isFinished }
            }
            check(markers.edit().putBoolean("unrelated_verified", true).commit())
        }
        HealthCareStore(context).use { care ->
            val jobs = jobs(care, concernId).filter { it.authorizationId == authorization }
            assertEquals(setOf(initial, followup), jobs.map { it.turnId }.toSet())
            assertTrue(jobs.all { it.state == HealthCareResearchState.COMPLETED })
            val issue = care.concern(concernId)!!
            assertEquals(conversation, issue.conversationId)
            assertTrue(issue.actions.isEmpty())
            assertNull(issue.target); assertNull(issue.maintenance); assertNull(care.nextReminder())
            assertEquals(2, listOf(initial, followup).mapNotNull(care::modelReview).size)
            val consent = care.researchAuthorization(concernId)!!
            markers.getStringSet("previous_reviews", emptySet()).orEmpty().forEach { assertNotNull(care.modelReview(it)) }
            if (consent.active) care.revokeResearch(concernId, authorization, System.currentTimeMillis())
        }
        assertFalse(HealthCareResearchWork.allowProjection(context, conversation, followup))
        println("HEALTH_RELATED production_workers=true selected_change=true unrelated_no_call=true retained_reviews=true phase=$phase")
    }

    private fun recheck() {
        if (markers.getString("recheck_version", null) == BuildConfig.VERSION_NAME) return
        check(!markers.contains("changed_weight_record")) { "Resume an existing follow-up instead of replacing it" }
        val concern = checkNotNull(markers.getString("concern", null))
        val oldAuthorization = checkNotNull(markers.getString("authorization", null))
        val oldReviews = HealthCareStore(context).use { care ->
            val previous = jobs(care, concern).filter { it.authorizationId == oldAuthorization }
            check(previous.isNotEmpty() && previous.all { it.terminal }) { "An observation timeout is not task completion" }
            previous.mapNotNull { care.modelReview(it.turnId)?.grant?.turnId }.toSet()
        }
        val existing = HealthCareStore(context).use { it.researchAuthorization(concern)!! }
        if (existing.id == oldAuthorization) {
            HealthCareStore(context).use { it.revokeResearch(concern, existing.id, System.currentTimeMillis()) }
            HealthCareResearchRuntime.authorize(context, HealthCareResearchRuntime.preview(context, concern), existing.id, related = selected)
        }
        val consent = HealthCareStore(context).use { it.researchAuthorization(concern)!! }
        check(consent.active && consent.id != oldAuthorization && consent.scope.related.keys == selected)
        check(markers.edit().putString("authorization", consent.id).putString("recheck_version", BuildConfig.VERSION_NAME)
            .putStringSet("previous_reviews", markers.getStringSet("previous_reviews", emptySet()).orEmpty() + oldReviews)
            .remove("initial_turn").remove("followup_turn").commit())
    }

    private fun checkGoal(turn: String, weight: String = markers.getString("weight_record", "")!!) {
        val state = checkNotNull(SharedPreferencesAgentSessionStore(context, "task:$turn").load())
        listOf("primary_record", "pressure_record").forEach {
            assertTrue("Recovery goal lost $it", state.currentGoal.contains(markers.getString(it, "")!!))
        }
        assertTrue("Recovery goal lost the selected weight record", state.currentGoal.contains(weight))
    }

    private fun prepare() {
        HealthPrivacyStore(context).use { it.change(HealthPrivacyOption.ONLINE_ANALYSIS, true, it.policy().version) }
        HealthCareStore(context).use { it.configure(true, it.settings().version) }
        save("primary", HealthMetric.LDL, mapOf("ldl" to "4.1"), "mmol/L", "0-3")
        save("weight", HealthMetric.WEIGHT, mapOf("weight" to "70"), "kg")
        save("pressure", HealthMetric.BLOOD_PRESSURE, mapOf("systolic" to "121", "diastolic" to "79"), "mmHg")
        HealthCareEngine.evaluate(context)
        val issue = HealthCareStore(context).use { it.forMetric(HealthMetric.LDL)!! }
        val conversation = HealthCareDiscussion.open(context, issue.id)
        val targets = AppStoreAgentConnectorRegistry(context).availableTargets()
        val target = targets.firstOrNull { it.id == "codex" && it.status == AgentConnectorStatus.AVAILABLE }
            ?: targets.firstOrNull { AppStore.agentIdForContact(context, it.id) == "codex" && it.status == AgentConnectorStatus.AVAILABLE }
            ?: error("Paired Codex unavailable; keep pairing and do not change provider")
        AgentModelSelectionSettings.selectManual(context, conversation, target.id, target.invocationProfile.defaultModelId,
            target.title, AgentModelReasoningEffort.MEDIUM, rememberAsDefault = false)
        val existing = HealthCareStore(context).use { it.researchAuthorization(issue.id) }
        if (existing == null) HealthCareResearchRuntime.authorize(context,
            HealthCareResearchRuntime.preview(context, issue.id), null, related = selected)
        val consent = HealthCareStore(context).use { it.researchAuthorization(issue.id)!! }
        check(consent.active && consent.scope.related.keys == selected && consent.scope.conversationId == conversation)
        check(markers.edit().putString("concern", issue.id).putString("conversation", conversation)
            .putString("authorization", consent.id).commit())
    }

    private fun save(key: String, metric: HealthMetric, values: Map<String, String>, unit: String, reference: String = ""): HealthObservation {
        markers.getString("${key}_record", null)?.let { id ->
            return HealthRecordStore(context).use { checkNotNull(it.record(id)) { "Keep the original isolated record" } }
        }
        if (!markers.contains("${key}_at")) check(markers.edit().putLong("${key}_at", System.currentTimeMillis() - 1).commit())
        val row = HealthRecordStore(context).use { records ->
            when (val result = records.save(HealthDraft(metric, values, unit, markers.getLong("${key}_at", 0), reference = reference))) {
                is HealthSaveResult.Saved -> result.record
                is HealthSaveResult.Duplicate -> records.record(result.id)!!
                else -> error("Synthetic record save failed")
            }
        }
        check(markers.edit().putString("${key}_record", row.id).commit())
        return row
    }

    private fun captureTurn(key: String, concern: String, authorization: String, prior: String? = null): String {
        markers.getString(key, null)?.let { return it }
        await(90_000, "Production worker created $key") {
            HealthCareStore(context).use { it.latestResearchJob(concern)?.let { job ->
                job.authorizationId == authorization && job.turnId != prior
            } == true }
        }
        val turn = HealthCareStore(context).use { it.latestResearchJob(concern)!!.turnId }
        check(markers.edit().putString(key, turn).commit())
        return turn
    }

    private fun verifyReview(turn: String, conversation: String, weight: String) {
        checkGoal(turn, weight)
        HealthCareStore(context).use { care ->
            val review = checkNotNull(care.modelReview(turn)) { "No durable model assessment" }
            assertEquals(selected, review.grant.related.keys)
            assertEquals(conversation, review.grant.conversationId)
            assertTrue("The assessment omitted the selected weight record", review.input.records.any { it.id == weight })
            assertTrue(review.input.records.any { it.id == markers.getString("primary_record", "") })
        }
        val messages = AgentTranscriptStore(context).entriesForTurn(turn)
        assertTrue(messages.isNotEmpty() && messages.all { it.conversationId == conversation })
        val answer = messages.filter { it.role == AgentTranscriptRole.ASSISTANT }.joinToString("\n") { it.text }
        assertTrue("No substantive response in the bound conversation", answer.length >= 80)
    }

    private fun jobs(care: HealthCareStore, concern: String): List<HealthCareResearchJob> = buildList {
        var after = ""
        do {
            val page = care.researchJobs(concern, after)
            addAll(page)
            if (page.isEmpty()) break
            after = page.last().turnId
        } while (true)
    }

    private fun healthy(turn: String): HealthCareResearchJob {
        observedTurn = turn
        return HealthCareStore(context).use { care -> checkNotNull(care.researchJob(turn)).also {
            check(!it.terminal || it.state == HealthCareResearchState.COMPLETED) { "Research ended ${it.state}: ${it.detail.take(300)}" }
        } }
    }
    private fun work() = WorkManager.getInstance(context).getWorkInfosForUniqueWork("health-authorized-research").get(10, TimeUnit.SECONDS)
    private fun await(timeout: Long, description: String, ready: () -> Boolean) {
        val end = SystemClock.elapsedRealtime() + timeout
        var next = 0L
        while (SystemClock.elapsedRealtime() < end) {
            if (ready()) return
            if (SystemClock.elapsedRealtime() >= next) { diagnose(); next = SystemClock.elapsedRealtime() + 15_000 }
            SystemClock.sleep(250)
        }
        diagnose()
        fail("Timed out: $description")
    }
    private fun diagnose() {
        val turn = observedTurn ?: markers.getString("followup_turn", null) ?: markers.getString("initial_turn", null) ?: return
        val workspace = AgentTaskRuntime.supervisor(context).findWorkspace(turn)
        val state = SharedPreferencesAgentSessionStore(context, "task:$turn").load()
        val job = HealthCareStore(context).use { it.researchJob(turn) }
        println("HEALTH_RELATED job=${job?.state} workspace=${workspace?.status} session=${state?.phase} active=${turn in AgentTaskRuntime.supervisor(context).activeTaskIds()}")
    }
    private fun inspect() {
        val turn = markers.getString("followup_turn", null) ?: markers.getString("initial_turn", null) ?: return
        val sessions = SharedPreferencesAgentSessionStore(context, "task:$turn")
        val state = sessions.load()
        val review = HealthCareStore(context).use { it.modelReview(turn) }
        val answer = AgentTranscriptStore(context).entriesForTurn(turn).filter { it.role == AgentTranscriptRole.ASSISTANT }
            .joinToString("\n") { it.text }
        File(context.filesDir, "related-inspection.json").writeText(JSONObject()
            .put("session", state?.let(sessions::encodeSession) ?: JSONObject.NULL)
            .put("full_goal", state?.currentGoal ?: "")
            .put("assessment", review?.input?.json() ?: JSONObject.NULL).put("answer", answer).toString(2))
    }
    @Suppress("RestrictedApi")
    private fun requireIsolation() {
        check(instrumentation is HealthRelatedResearchAcceptanceRunner)
        val prefix = "health-related-acceptance-"
        listOf(HealthCareStore.DEFAULT_DB, HealthRecordStore.DEFAULT_DB, HealthPrivacyStore.DEFAULT_DB,
            AgentConversationDatabase.DATABASE_NAME, "galaxyssi_agent_workspaces.db").forEach {
            check(context.getDatabasePath(it).name.startsWith(prefix)) { "Unisolated database" }
        }
        val manager = WorkManagerImpl.getInstance(context)
        val db = manager.javaClass.getMethod("getWorkDatabase").invoke(manager)
        val helper = db.javaClass.getMethod("getOpenHelper").invoke(db)
        val sqlite = Class.forName("androidx.sqlite.db.SupportSQLiteOpenHelper").getMethod("getWritableDatabase").invoke(helper)
        check((Class.forName("androidx.sqlite.db.SupportSQLiteDatabase").getMethod("getPath").invoke(sqlite) as String).contains(prefix))
    }
}
