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

    @Test fun authorizedResearchUsesNormalBackgroundExecutionAndRecovery() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("health_automatic_research") == "true")
        requireIsolation()
        val phase = InstrumentationRegistry.getArguments().getString("health_research_phase") ?: "full"
        if (phase == "inspect") { diagnose(); return }
        AppStore.ensureInitialized(context)
        GalaxySSIMqttClient.connect(context)
        await(45_000, "Paired transport ready") { GalaxySSIMqttClient.isRequestReplyReady() }
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
        assertAnswer(turn)
        val reviewTurn = confirmSyntheticContext(concern, turn)
        await(600_000, "Evidence research after measurement context confirmation") {
            checkHealthy(reviewTurn).state == HealthCareResearchState.COMPLETED
        }
        assertAnswer(reviewTurn)
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

    private fun assertAnswer(turn: String) {
        val entries = AgentTranscriptStore(context).entriesForTurn(turn)
        assertTrue(entries.isNotEmpty())
        assertTrue(entries.all { it.conversationId == markers.getString("conversation", "") })
        val answer = entries.filter { it.role == AgentTranscriptRole.ASSISTANT }.joinToString("\n") { it.text }
        assertTrue("No substantive answer returned to the original conversation", answer.length >= 80 && answer.contains("6.3"))
    }

    private fun confirmSyntheticContext(concern: String, initialTurn: String): String {
        markers.getString("review_turn", null)?.let { return it }
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
        check(markers.edit().putString("review_turn", reviewTurn).commit())
        return reviewTurn
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
        val turn = markers.getString("review_turn", null) ?: markers.getString("turn", "").orEmpty()
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
