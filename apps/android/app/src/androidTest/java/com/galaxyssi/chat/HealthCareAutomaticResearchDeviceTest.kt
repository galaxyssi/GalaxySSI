package com.galaxyssi.chat

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.impl.WorkManagerImpl
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Runs the production scheduler, planner, tools and delivery; never manually parses model output. */
class HealthCareAutomaticResearchDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext.applicationContext
    private val markers get() = context.getSharedPreferences("health-runtime-probe", Context.MODE_PRIVATE)
    private var observedTurn: String? = null

    @Test fun authorizedResearchUsesNormalBackgroundExecutionAndRecovery() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("health_automatic_research") == "true")
        requireIsolation()
        val phase = InstrumentationRegistry.getArguments().getString("health_research_phase") ?: "full"
        if (phase == "inspect") { diagnose(); return }
        AppStore.ensureInitialized(context)
        GalaxySSIMqttClient.connect(context)
        await(45_000, "Paired transport ready") { GalaxySSIMqttClient.isRequestReplyReady() }
        if (phase == "followup") { followUp(); return }
        if (phase == "outcome") { actionOutcome(); return }
        if (phase == "full" || phase == "start") start()
        val concern = checkNotNull(markers.getString("concern", null)) { "No isolated research to resume" }
        val turn = checkNotNull(markers.getString("turn", null))
        if (phase == "start") {
            await(90_000, "Durable connector receipt") {
                val saved = SharedPreferencesAgentSessionStore(context, "task:$turn").load()
                checkHealthy(turn)
                saved?.lastActionResult?.metadata?.get("source_message_id")?.toLongOrNull()?.let { it > 0 } == true
            }
            check(markers.edit().putString("process", AgentProcessIdentity.instanceId).commit())
            println("HEALTH_AUTOMATIC ready_for_process_restart=true")
            return
        }
        if (phase == "resume") {
            assertNotEquals("Acceptance must restart the process", markers.getString("process", ""), AgentProcessIdentity.instanceId)
            AgentStartupRecovery.enqueue(context).result.get()
        }
        await(600_000, "Research completion through normal delivery") {
            checkHealthy(turn).state == HealthCareResearchState.COMPLETED
        }
        assertAnswer(turn, "6.3")
        val reviewTurn = confirmSyntheticContext(concern, turn)
        await(600_000, "Evidence research after measurement context confirmation") {
            checkHealthy(reviewTurn).state == HealthCareResearchState.COMPLETED
        }
        assertAnswer(reviewTurn, "6.3")
        SQLiteDatabase.openDatabase(context.getDatabasePath(HealthCareStore.DEFAULT_DB).absolutePath,
            null, SQLiteDatabase.OPEN_READONLY).use { database ->
            database.rawQuery("SELECT COUNT(*) FROM evidence_reads WHERE turn_id=?", arrayOf(reviewTurn)).use {
                assertTrue(it.moveToFirst())
                assertTrue("The real execution did not retain any retrieved source evidence", it.getLong(0) > 0)
            }
        }
        HealthCareStore(context).use { store ->
            val issue = store.concern(concern)!!
            assertTrue("Research cannot adopt actions", issue.actions.isEmpty())
            assertNull(store.nextReminder())
            assertEquals("Only the context change may start another research turn", setOf(turn, reviewTurn),
                store.researchJobs(concern).map { it.turnId }.toSet())
            val plan = checkNotNull(store.plan(reviewTurn)) { "Evidence research must produce a reviewable plan" }
            assertEquals(HealthCarePlanState.PENDING, plan.state)
            assertTrue(plan.sources.isNotEmpty())
            assertTrue(plan.sources.all { it.evidence != null && it.quote.isNotBlank() })
            val authorization = store.researchAuthorization(concern)!!
            store.revokeResearch(concern, authorization.id, System.currentTimeMillis())
        }
        assertFalse("Revocation must reject a late projection", HealthCareResearchWork.allowProjection(context,
            markers.getString("conversation", "")!!, reviewTurn))
        println("HEALTH_AUTOMATIC production_scheduler=true original_conversation=true pending_only=true phase=$phase")
    }

    private fun assertAnswer(turn: String, vararg values: String) {
        val entries = AgentTranscriptStore(context).entriesForTurn(turn)
        assertTrue(entries.isNotEmpty())
        assertTrue(entries.all { it.conversationId == markers.getString("conversation", "") })
        val answer = entries.filter { it.role == AgentTranscriptRole.ASSISTANT }.joinToString("\n") { it.text }
        assertTrue("No substantive answer returned to the original conversation", answer.length >= 80)
        values.forEach { assertTrue("The answer lost a required measurement: $it", answer.contains(it)) }
    }

    private fun confirmSyntheticContext(concern: String, initialTurn: String, marker: String = "review_turn"): String {
        markers.getString(marker, null)?.let { return it }
        HealthCareStore(context).use { store ->
            val issue = store.concern(concern)!!
            // Match the context review UI; all measurements and answers in this namespace are synthetic.
            if (issue.context?.screeningFpgApplicable != true) {
                store.confirmContext(issue.id, issue.revision, HealthCareContext(issue.assessment.record!!,
                    adult = HealthCareTruth.YES, pregnant = HealthCareTruth.NO, diagnosedDiabetes = HealthCareTruth.NO,
                    specimen = HealthCareSpecimen.LAB_PLASMA, fastingHours = 10,
                    illnessOrMedication = HealthCareTruth.NO, confirmedAt = System.currentTimeMillis()))
            }
        }
        HealthCareEngine.evaluate(context)
        await(60_000, "Existing authorization reacts to confirmed measurement context") {
            HealthCareStore(context).use { it.latestResearchJob(concern)?.turnId?.let { id -> id != initialTurn } == true }
        }
        val reviewTurn = HealthCareStore(context).use { it.latestResearchJob(concern)!!.turnId }
        check(markers.edit().putString(marker, reviewTurn).commit())
        return reviewTurn
    }

    private fun followUp() {
        val concernId = checkNotNull(markers.getString("concern", null))
        val originalReview = checkNotNull(markers.getString("review_turn", null))
        val conversation = checkNotNull(markers.getString("conversation", null))
        assertEquals(HealthCareResearchState.COMPLETED, checkHealthy(originalReview).state)
        val originalGrant = HealthCareStore(context).use { it.plan(originalReview)!!.grant }
        var authorizationId = markers.getString("followup_authorization", null)
        if (authorizationId == null) {
            val previous = HealthCareStore(context).use { it.researchAuthorization(concernId)!! }
            assertFalse("The preceding acceptance must have revoked its synthetic consent", previous.active)
            val preview = HealthCareResearchRuntime.preview(context, concernId)
            assertEquals(conversation, preview.grant.conversationId)
            assertEquals(originalGrant.targetId, preview.grant.targetId)
            assertEquals(originalGrant.modelId, preview.grant.modelId)
            HealthCareResearchRuntime.authorize(context, preview, previous.id)
            authorizationId = HealthCareStore(context).use { it.researchAuthorization(concernId)!!.id }
            check(markers.edit().putString("followup_authorization", authorizationId).commit())
        }
        val authorization = checkNotNull(authorizationId)
        var seedTurn = markers.getString("followup_seed_turn", null)
        if (seedTurn == null) {
            await(60_000, "Renewed synthetic authorization scheduled") {
                HealthCareStore(context).use { it.latestResearchJob(concernId)?.authorizationId == authorization }
            }
            seedTurn = HealthCareStore(context).use { it.latestResearchJob(concernId)!!.turnId }
            check(markers.edit().putString("followup_seed_turn", seedTurn).commit())
        }
        val seed = checkNotNull(seedTurn)
        if (!markers.contains("followup_record")) {
            await(90_000, "Research is in flight before a new measurement arrives") {
                val saved = SharedPreferencesAgentSessionStore(context, "task:$seed").load()
                checkHealthy(seed)
                saved?.lastActionResult?.metadata?.get("source_message_id")?.toLongOrNull()?.let { it > 0 } == true
            }
            // Persist the timestamp first so retrying this test cannot insert a duplicate reading.
            if (!markers.contains("followup_at")) check(markers.edit().putLong("followup_at", System.currentTimeMillis() - 1).commit())
            val at = markers.getLong("followup_at", 0)
            val record = HealthRecordStore(context).use { records ->
                val draft = HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "5.8"), "mmol/L", at, reference = "4-6")
                when (val saved = records.save(draft)) {
                    is HealthSaveResult.Saved -> saved.record
                    is HealthSaveResult.Duplicate -> records.record(saved.id)!!
                    else -> error("Synthetic follow-up was not saved")
                }
            }
            check(markers.edit().putString("followup_record", record.id).commit())
        }
        val recordId = markers.getString("followup_record", "")!!
        await(60_000, "Normal record notifications reassess the original concern") {
            HealthCareStore(context).use { it.concern(concernId)?.assessment?.record?.id == recordId }
        }
        if (!markers.contains("followup_review_turn")) HealthCareStore(context).use { care ->
            val issue = care.concern(concernId)!!
            assertEquals(conversation, issue.conversationId)
            assertNull("New measurements cannot inherit old collection context", issue.context)
            assertEquals(HealthCareStage.VERIFY_CONTEXT, issue.stage)
            val comparison = issue.assessment.comparison!!
            assertEquals(HealthCareComparisonKind.NEW_RESULT, comparison.kind)
            assertEquals("6.3", comparison.before.values["glucose"])
            assertTrue(comparison.previousContext!!.screeningFpgApplicable)
        }
        var nextTurn = markers.getString("followup_turn", null)
        if (nextTurn == null) {
            await(60_000, "Standing authorization reacts to the new reading without a user message") {
                HealthCareStore(context).use { it.latestResearchJob(concernId)?.let { job ->
                    job.authorizationId == authorization && job.turnId != seed
                } == true }
            }
            nextTurn = HealthCareStore(context).use { it.latestResearchJob(concernId)!!.turnId }
            check(markers.edit().putString("followup_turn", nextTurn).commit())
        }
        val followup = checkNotNull(nextTurn)
        await(600_000, "New reading reaches the original Agent conversation") {
            checkHealthy(followup).state == HealthCareResearchState.COMPLETED
        }
        assertAnswer(followup, "6.3", "5.8")
        assertFalse("Obsolete in-flight research cannot project its answer",
            HealthCareResearchWork.allowProjection(context, conversation, seed))
        val review = confirmSyntheticContext(concernId, followup, "followup_review_turn")
        await(600_000, "Confirmed follow-up reaches a source-backed reviewable plan") {
            checkHealthy(review).state == HealthCareResearchState.COMPLETED
        }
        assertAnswer(review, "6.3", "5.8")
        HealthCareStore(context).use { care ->
            val issue = care.concern(concernId)!!
            assertEquals(conversation, issue.conversationId)
            assertTrue(issue.open)
            assertFalse(issue.stage in setOf(HealthCareStage.MAINTENANCE, HealthCareStage.CLOSED))
            assertNull(issue.target); assertNull(issue.maintenance)
            assertTrue(issue.actions.isEmpty()); assertNull(care.nextReminder())
            val plan = checkNotNull(care.plan(review)) { "Follow-up research did not retain a pending proposal" }
            assertEquals(HealthCarePlanState.PENDING, plan.state)
            assertTrue(plan.sources.isNotEmpty())
            assertTrue(plan.sources.all { it.evidence != null && it.quote.isNotBlank() })
            assertEquals(setOf(seed, followup, review), care.researchJobs(concernId)
                .filter { it.authorizationId == authorization }.map { it.turnId }.toSet())
            care.revokeResearch(concernId, authorization, System.currentTimeMillis())
        }
        println("HEALTH_AUTOMATIC followup=true same_concern=true same_conversation=true no_automatic_closure=true")
    }

    private fun actionOutcome() {
        val concernId = checkNotNull(markers.getString("concern", null))
        val conversation = checkNotNull(markers.getString("conversation", null))
        val priorReview = checkNotNull(markers.getString("followup_review_turn", null))
        val feedback = "还没有复查，也没有新的血糖结果。执行这项安排有困难：每周只有两天能抽出十分钟，希望把下一步调整成更容易坚持的方案。"
        HealthCareStore(context).use { care ->
            val issue = care.concern(concernId)!!
            val plan = care.plan(priorReview)!!
            if (!markers.contains("outcome_action")) {
                if (plan.state == HealthCarePlanState.PENDING) {
                    val action = plan.actions.firstOrNull { it.kind == HealthCareActionKind.LIFESTYLE &&
                        HealthCareApplicabilityPolicy.canAccept(plan, issue, it) }
                        ?: plan.actions.first { HealthCareApplicabilityPolicy.canAccept(plan, issue, it) }
                    val privacy = HealthPrivacyStore(context).use { it.policy() }
                    val source = HealthRecordStore(context).use {
                        HealthCareEngine.inputVersion(care.settings().version, privacy.version, it.metricVersion(issue.metric))
                    }
                    // This is an explicit review of a synthetic proposal, not model-initiated adoption.
                    care.resolvePlan(plan.id, setOf(action.id), issue.revision, privacy, source, System.currentTimeMillis())
                }
                val selected = care.plan(plan.id)!!.selected.single()
                check(markers.edit().putString("outcome_action", selected).commit())
            }
        }
        val actionId = markers.getString("outcome_action", "")!!
        var authorizationId = markers.getString("outcome_authorization", null)
        if (authorizationId == null) {
            val previous = HealthCareStore(context).use { it.researchAuthorization(concernId)!! }
            assertFalse("The follow-up phase must revoke its synthetic consent", previous.active)
            val preview = HealthCareResearchRuntime.preview(context, concernId)
            assertEquals(conversation, preview.grant.conversationId)
            assertEquals(previous.scope.targetId, preview.grant.targetId)
            assertEquals(previous.scope.modelId, preview.grant.modelId)
            HealthCareResearchRuntime.authorize(context, preview, previous.id)
            authorizationId = HealthCareStore(context).use { it.researchAuthorization(concernId)!!.id }
            check(markers.edit().putString("outcome_authorization", authorizationId).commit())
        }
        val authorization = checkNotNull(authorizationId)
        var seedTurn = markers.getString("outcome_seed_turn", null)
        if (seedTurn == null) {
            await(60_000, "Outcome acceptance authorization scheduled") {
                HealthCareStore(context).use { it.latestResearchJob(concernId)?.authorizationId == authorization }
            }
            seedTurn = HealthCareStore(context).use { it.latestResearchJob(concernId)!!.turnId }
            check(markers.edit().putString("outcome_seed_turn", seedTurn).commit())
        }
        val seed = checkNotNull(seedTurn)
        if (!markers.contains("outcome_turn")) {
            val action = HealthCareStore(context).use { it.concern(concernId)!!.actions.single { action -> action.id == actionId } }
            if (action.state == HealthCareActionState.CONFIRMED) {
                await(90_000, "Research receipt exists before recording action feedback") {
                    checkHealthy(seed)
                    SharedPreferencesAgentSessionStore(context, "task:$seed").load()?.lastActionResult?.metadata
                        ?.get("source_message_id")?.toLongOrNull()?.let { it > 0 } == true
                }
                HealthCareStore(context).use { care ->
                    val issue = care.concern(concernId)!!
                    care.finishAction(issue.id, issue.revision, actionId, feedback, System.currentTimeMillis())
                }
            }
            await(60_000, "Action outcome alone schedules reassessment") {
                HealthCareStore(context).use { it.latestResearchJob(concernId)?.let { job ->
                    job.authorizationId == authorization && job.turnId != seed
                } == true }
            }
            val turn = HealthCareStore(context).use { it.latestResearchJob(concernId)!!.turnId }
            check(markers.edit().putString("outcome_turn", turn).commit())
        }
        val turn = markers.getString("outcome_turn", "")!!
        await(600_000, "Action feedback reaches the original Agent conversation") {
            checkHealthy(turn).state == HealthCareResearchState.COMPLETED
        }
        assertAnswer(turn, "6.3", "5.8")
        assertFalse(HealthCareResearchWork.allowProjection(context, conversation, seed))
        HealthCareStore(context).use { care ->
            val issue = care.concern(concernId)!!
            assertEquals(conversation, issue.conversationId)
            assertEquals(markers.getString("followup_record", ""), issue.assessment.record!!.id)
            assertEquals(1, issue.actions.size)
            assertEquals(HealthCareActionState.DONE, issue.actions.single().state)
            assertEquals(feedback, issue.actions.single().outcome)
            assertTrue(issue.open)
            assertFalse(issue.stage in setOf(HealthCareStage.MAINTENANCE, HealthCareStage.CLOSED))
            assertNull(issue.target); assertNull(issue.maintenance); assertNull(care.nextReminder())
            val plan = checkNotNull(care.plan(turn)) { "Outcome research did not retain a reviewable proposal" }
            assertEquals(HealthCarePlanState.PENDING, plan.state)
            assertTrue(plan.sources.all { it.evidence != null && it.quote.isNotBlank() })
            assertEquals(setOf(seed, turn), care.researchJobs(concernId)
                .filter { it.authorizationId == authorization }.map { it.turnId }.toSet())
            care.revokeResearch(concernId, authorization, System.currentTimeMillis())
        }
        println("HEALTH_AUTOMATIC action_outcome=true same_conversation=true pending_only=true no_new_measurement=true")
    }

    private fun start() {
        assertFalse("Use a fresh isolated run or resume the existing one", markers.contains("turn"))
        HealthPrivacyStore(context).use { it.change(HealthPrivacyOption.ONLINE_ANALYSIS, true, it.policy().version) }
        HealthRecordStore(context).use { it.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"),
            "mmol/L", System.currentTimeMillis() - 1000, reference = "4-6")) }
        HealthCareStore(context).use { it.configure(true, it.settings().version) }
        HealthCareEngine.evaluate(context)
        val concern = HealthCareStore(context).use { it.forMetric(HealthMetric.GLUCOSE)!! }
        val conversation = HealthCareDiscussion.open(context, concern.id)
        val targets = AppStoreAgentConnectorRegistry(context).availableTargets()
        val target = targets.firstOrNull { it.id == "codex" && it.status == AgentConnectorStatus.AVAILABLE }
            ?: targets.firstOrNull { AppStore.agentIdForContact(context, it.id) == "codex" && it.status == AgentConnectorStatus.AVAILABLE }
            ?: error("Paired Codex unavailable; do not replace pairing or use another provider")
        AgentModelSelectionSettings.selectManual(context, conversation, target.id, target.invocationProfile.defaultModelId,
            target.title, AgentModelReasoningEffort.MEDIUM, rememberAsDefault = false)
        val preview = HealthCareResearchRuntime.preview(context, concern.id)
        HealthCareResearchRuntime.authorize(context, preview, null)
        await(60_000, "Scheduled research job") {
            HealthCareStore(context).use { it.latestResearchJob(concern.id) != null }
        }
        val job = HealthCareStore(context).use { it.latestResearchJob(concern.id)!! }
        assertEquals(conversation, job.conversationId)
        check(markers.edit().putString("concern", concern.id).putString("turn", job.turnId)
            .putString("conversation", conversation).commit())
        println("HEALTH_AUTOMATIC authorization_dispatched=true")
    }

    private fun checkHealthy(turn: String): HealthCareResearchJob {
        observedTurn = turn
        val job = HealthCareStore(context).use { it.researchJob(turn)!! }
        check(!job.terminal || job.state == HealthCareResearchState.COMPLETED) {
            "Automatic research ended ${job.state}: ${AgentObservationRedaction.redact(job.detail).take(350)}"
        }
        return job
    }

    @Suppress("RestrictedApi")
    private fun requireIsolation() {
        assertTrue("Use HealthResearchAcceptanceRunner, never the ordinary runner",
            instrumentation is HealthResearchAcceptanceRunner)
        for (name in listOf(HealthCareStore.DEFAULT_DB, HealthRecordStore.DEFAULT_DB,
            HealthPrivacyStore.DEFAULT_DB, AgentConversationDatabase.DATABASE_NAME, "galaxyssi_agent_workspaces.db")) {
            check(context.getDatabasePath(name).name.startsWith("health-runtime-acceptance-")) { "Unisolated database: $name" }
        }
        // WorkManager's transitive Room API is runtime-only in this project's test classpath.
        val manager = WorkManagerImpl.getInstance(context)
        val database = manager.javaClass.getMethod("getWorkDatabase").invoke(manager)
        val helper = database.javaClass.getMethod("getOpenHelper").invoke(database)
        val sqlite = Class.forName("androidx.sqlite.db.SupportSQLiteOpenHelper").getMethod("getWritableDatabase").invoke(helper)
        val path = Class.forName("androidx.sqlite.db.SupportSQLiteDatabase").getMethod("getPath").invoke(sqlite) as String
        check(path.contains("health-runtime-acceptance-")) {
            "WorkManager database must be isolated before scheduling"
        }
    }

    private fun await(timeout: Long, description: String, predicate: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + timeout
        var nextDiagnostic = SystemClock.elapsedRealtime() + 15_000
        while (SystemClock.elapsedRealtime() < deadline) {
            if (predicate()) return
            if (SystemClock.elapsedRealtime() >= nextDiagnostic) {
                diagnose()
                nextDiagnostic = SystemClock.elapsedRealtime() + 15_000
            }
            SystemClock.sleep(250)
        }
        diagnose()
        fail("Timed out: $description")
    }

    private fun diagnose() {
        val turn = observedTurn ?: markers.getString("outcome_turn", null) ?: markers.getString("followup_review_turn", null) ?: markers.getString("followup_turn", null)
            ?: markers.getString("review_turn", null) ?: markers.getString("turn", "").orEmpty()
        if (turn.isEmpty()) return
        val supervisor = AgentTaskRuntime.supervisor(context)
        val workspace = supervisor.findWorkspace(turn)
        val saved = SharedPreferencesAgentSessionStore(context, "task:$turn").load()
        val job = HealthCareStore(context).use { it.researchJob(turn) }
        println("HEALTH_AUTOMATIC job=${job?.state} workspace=${workspace?.status} cancelled=${workspace?.cancellationRequested}" +
            " active=${turn in supervisor.activeTaskIds()} session=${saved?.phase}")
        println("HEALTH_AUTOMATIC cold_boot_candidate=${workspace?.let(AgentColdBootRecoveryPolicy::shouldPause)}" +
            " previous_process=${saved?.let { AgentColdBootRecoveryPolicy.belongsToPreviousProcess(it, AgentProcessIdentity.instanceId) }}" +
            " last_action=${saved?.lastActionResult?.actionId} awaiting=${saved?.lastActionResult?.metadata?.get("awaiting_response")}" +
            " actions=${saved?.currentPlan?.actions?.joinToString { "${it.id}:${it.kind}:${it.status}" }}")
        val end = AgentConnectorResponseStore.highWatermark(context)
        var cursor = 0L
        while (cursor < end) {
            val page = AgentConnectorResponseStore.pendingPage(context, cursor, end)
            page.responses.filter { it.turnId == turn }.forEach { response ->
                val delivery = AgentPendingDeliveryStore.find(context, response.sourceMessageId, response.contactId)
                val identity = AgentTaskIdentityPolicy.canonicalConnectorResponseIdentity(delivery,
                    response.conversationId, response.taskId, response.turnId)
                val admitted = saved?.let { AgentConnectorReceiptAdmission.saved(it, response.sourceMessageId,
                    response.contactId, identity.conversationId, identity.turnId, identity.taskId) }
                println("HEALTH_AUTOMATIC inbox_source=${response.sourceMessageId} saved_source=${saved?.lastActionResult?.metadata?.get("source_message_id")}" +
                    " delivery=${delivery != null} identity=${workspace?.let { AgentConnectorBackgroundIdentity.matches(response, identity, it) }}" +
                    " admitted=$admitted terminal=${AgentTerminalDeliveryStore.isTerminal(context, response.sourceMessageId)}")
            }
            if (page.nextSequence <= cursor) break
            cursor = page.nextSequence
        }
    }
}
