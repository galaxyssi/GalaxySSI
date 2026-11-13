package com.galaxyssi.chat

import android.content.Context
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.impl.WorkManagerImpl
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Real dispatch and privacy withdrawal; late final replies are explicitly injected fault cases. */
class HealthCareActiveRevocationDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext.applicationContext
    private val markers get() = context.getSharedPreferences("health-active-revocation", Context.MODE_PRIVATE)
    private val turn get() = checkNotNull(markers.getString("turn", null))
    private val concern get() = checkNotNull(markers.getString("concern", null))
    private val conversation get() = checkNotNull(markers.getString("conversation", null))
    private val authorization get() = checkNotNull(markers.getString("authorization", null))

    @Test fun withdrawalStopsInFlightResearchAcrossRestartAndOnlineReenable() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("health_active_revocation") == "true")
        requireIsolation()
        val phase = InstrumentationRegistry.getArguments().getString("health_revocation_phase") ?: "revoke"
        require(phase in setOf("revoke", "resume", "inspect"))
        if (phase == "inspect") { diagnose(); return }
        AppStore.ensureInitialized(context)
        GalaxySSIMqttClient.connect(context)
        await("Paired transport ready") { GalaxySSIMqttClient.isRequestReplyReady() }
        if (phase == "revoke") {
            if (!markers.contains("authorization")) prepare()
            if (!markers.contains("source")) captureReceipt()
            if (!markers.getBoolean("revoked", false)) {
                HealthPrivacyStore(context).use {
                    val privacy = it.policy()
                    if (privacy.online) it.change(HealthPrivacyOption.ONLINE_ANALYSIS, false, privacy.version)
                }
                check(markers.edit().putBoolean("revoked", true).commit())
            }
            assertNotNull(HealthCareDiscussion.rejection(context, conversation, turn))
            assertFalse(HealthCareResearchWork.allowProjection(context, conversation, turn))
            awaitCancellation()
            assertRetained()
            rejectInjectedLateFinal("before_restart")
            check(markers.edit().putString("process", AgentProcessIdentity.instanceId).commit())
            println("HEALTH_REVOCATION live_dispatch=true withdrawal=true ready_for_restart=true")
            return
        }
        check(markers.getBoolean("revoked", false)) { "Resume the persisted cancellation, not a replacement request" }
        assertNotEquals(markers.getString("process", ""), AgentProcessIdentity.instanceId)
        AgentStartupRecovery.enqueue(context).result.get(30, TimeUnit.SECONDS)
        awaitCancellation()
        if (!markers.getBoolean("reenabled", false)) {
            if (!markers.contains("reenable_work_before")) check(markers.edit()
                .putStringSet("reenable_work_before", work().map { it.id.toString() }.toSet()).commit())
            val before = markers.getStringSet("reenable_work_before", emptySet()).orEmpty()
            HealthPrivacyStore(context).use {
                val privacy = it.policy()
                if (!privacy.online) it.change(HealthPrivacyOption.ONLINE_ANALYSIS, true, privacy.version)
            }
            await("Reenabled online setting reconciled without restoring consent") {
                val pending = work().filter { it.id.toString() !in before }
                pending.any { it.state == WorkInfo.State.SUCCEEDED } && pending.all { it.state.isFinished }
            }
            check(markers.edit().putBoolean("reenabled", true).commit())
        }
        assertTrue(HealthPrivacyStore(context).use { it.policy().online })
        assertFalse(HealthCareResearchWork.allowProjection(context, conversation, turn))
        assertNotNull(HealthCareDiscussion.rejection(context, conversation, turn))
        rejectInjectedLateFinal("after_restart")
        assertRetained()
        println("HEALTH_REVOCATION process_recovery=true online_reenable_no_consent=true injected_late_final_rejected=true retained_archive=true")
    }

    private fun prepare() {
        HealthPrivacyStore(context).use {
            val privacy = it.policy()
            if (!privacy.online) it.change(HealthPrivacyOption.ONLINE_ANALYSIS, true, privacy.version)
        }
        HealthCareStore(context).use { if (!it.settings().enabled) it.configure(true, it.settings().version) }
        if (!markers.contains("record_time")) check(markers.edit().putLong("record_time", System.currentTimeMillis() - 1000).commit())
        if (!markers.contains("record")) {
            val id = HealthRecordStore(context).use {
                when (val result = it.save(HealthDraft(HealthMetric.LDL, mapOf("ldl" to "4.1"), "mmol/L",
                    markers.getLong("record_time", 0), reference = "0-3"))) {
                    is HealthSaveResult.Saved -> result.record.id
                    is HealthSaveResult.Duplicate -> result.id
                    else -> error("Synthetic record save failed")
                }
            }
            check(markers.edit().putString("record", id).commit())
        }
        HealthCareEngine.evaluate(context)
        val issue = HealthCareStore(context).use { it.forMetric(HealthMetric.LDL)!! }
        val chat = HealthCareDiscussion.open(context, issue.id)
        val targets = AppStoreAgentConnectorRegistry(context).availableTargets()
        val target = targets.firstOrNull { it.id == "codex" && it.status == AgentConnectorStatus.AVAILABLE }
            ?: targets.firstOrNull { AppStore.agentIdForContact(context, it.id) == "codex" && it.status == AgentConnectorStatus.AVAILABLE }
            ?: error("Paired Codex unavailable; do not replace pairing or switch provider")
        AgentModelSelectionSettings.selectManual(context, chat, target.id, target.invocationProfile.defaultModelId,
            target.title, AgentModelReasoningEffort.MEDIUM, rememberAsDefault = false)
        val existing = HealthCareStore(context).use { it.researchAuthorization(issue.id) }
        if (existing == null) HealthCareResearchRuntime.authorize(context, HealthCareResearchRuntime.preview(context, issue.id), null)
        val consent = HealthCareStore(context).use { it.researchAuthorization(issue.id)!! }
        check(consent.active)
        check(markers.edit().putString("concern", issue.id).putString("conversation", chat)
            .putString("authorization", consent.id).commit())
    }

    private fun captureReceipt() {
        if (!markers.contains("turn")) {
            await("Production research worker dispatched") { HealthCareStore(context).use { it.latestResearchJob(concern) != null } }
            val job = HealthCareStore(context).use { it.latestResearchJob(concern)!! }
            assertEquals(authorization, job.authorizationId)
            check(markers.edit().putString("turn", job.turnId).commit())
        }
        await("Durable in-flight receipt before withdrawal") {
            val job = HealthCareStore(context).use { it.researchJob(turn)!! }
            check(!job.terminal) { "This task already ended ${job.state}; do not replace it or claim in-flight cancellation" }
            val state = SharedPreferencesAgentSessionStore(context, "task:$turn").load()
            val receipt = state?.lastActionResult?.metadata.orEmpty()
            if (state?.phase != AgentPhase.WAITING_RESPONSE || receipt["source_message_id"]?.toLongOrNull()?.let { it > 0 } != true ||
                receipt["contact_id"].isNullOrBlank() || receipt["remote_task_id"].isNullOrBlank()) return@await false
            assertNull(HealthCareStore(context).use { it.modelReview(turn) })
            check(markers.edit().putLong("source", receipt.getValue("source_message_id").toLong())
                .putString("contact", receipt.getValue("contact_id")).putString("remote", receipt.getValue("remote_task_id")).commit())
            true
        }
    }

    private fun awaitCancellation() = await("Production cancellation outbox completed") {
        val job = HealthCareStore(context).use { it.researchJob(turn)!! }
        val workspace = AgentTaskRuntime.supervisor(context).findWorkspace(turn)
        job.state == HealthCareResearchState.CANCELLED && !job.cancellationPending &&
            workspace?.status == AgentWorkspaceStatus.CANCELLED && turn !in AgentTaskRuntime.supervisor(context).activeTaskIds() &&
            AgentTerminalDeliveryStore.isTerminal(context, markers.getLong("source", 0))
    }

    private fun assertRetained() {
        HealthCareStore(context).use { care ->
            val consent = care.researchAuthorization(concern)!!
            assertEquals(authorization, consent.id); assertFalse(consent.active)
            assertEquals(listOf(turn), care.researchJobs(concern).map { it.turnId })
            assertEquals(HealthCareResearchState.CANCELLED, care.researchJob(turn)!!.state)
            assertNull(care.modelReview(turn)); assertNull(care.modelAttention(concern))
            assertTrue(care.pendingPlans(concern).isEmpty())
            val issue = care.concern(concern)!!
            assertEquals(conversation, issue.conversationId)
            assertTrue(issue.actions.isEmpty()); assertNull(issue.target); assertNull(issue.maintenance); assertNull(care.nextReminder())
        }
        HealthRecordStore(context).use { assertNotNull(it.record(markers.getString("record", "")!!)) }
        val messages = AgentTranscriptStore(context).entriesForTurn(turn)
        assertTrue(messages.any { it.role == AgentTranscriptRole.USER })
        assertTrue(messages.all { it.conversationId == conversation })
        assertFalse(messages.any { it.text.contains("HEALTH_LATE_FIXTURE") })
        assertNotNull(AgentTranscriptStore(context).conversation(conversation))
    }

    private fun rejectInjectedLateFinal(phase: String) = runBlocking {
        val response = AgentConnectorResponse(markers.getLong("source", 0), markers.getString("contact", "")!!,
            "HEALTH_LATE_FIXTURE：已撤销的健康回复不应显示。$phase", conversation, turn, markers.getString("remote", "")!!,
            taskStatus = "completed", statusSequence = if (phase == "before_restart") 1_000_000 else 1_000_001)
        // Reuse the real request identity but never claim this synthetic reply came from the provider.
        val recorded = AgentConnectorResponseStore.append(context, response)
        assertTrue(recorded || AgentConnectorResponseStore.wasRecorded(context, response))
        assertTrue(AgentConnectorBackgroundDelivery(context) { error("Revoked reply rebuilt the model runtime") }.consume(response))
        assertFalse(AgentConnectorResponseStore.contains(context, response))
        assertFalse(AgentTranscriptStore(context).entriesForTurn(turn).any { it.text.contains("HEALTH_LATE_FIXTURE") })
    }

    private fun work() = WorkManager.getInstance(context).getWorkInfosForUniqueWork("health-authorized-research").get(10, TimeUnit.SECONDS)
    private fun await(description: String, ready: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 90_000
        var next = 0L
        while (SystemClock.elapsedRealtime() < until) {
            if (ready()) return
            if (SystemClock.elapsedRealtime() >= next) { diagnose(); next = SystemClock.elapsedRealtime() + 15_000 }
            SystemClock.sleep(250)
        }
        diagnose(); fail("Timed out: $description")
    }
    private fun diagnose() {
        if (!markers.contains("turn")) return
        val job = HealthCareStore(context).use { it.researchJob(turn) }
        val workspace = AgentTaskRuntime.supervisor(context).findWorkspace(turn)
        println("HEALTH_REVOCATION job=${job?.state} cancellation_pending=${job?.cancellationPending} workspace=${workspace?.status}" +
            " terminal_receipt=${AgentTerminalDeliveryStore.isTerminal(context, markers.getLong("source", 0))}")
    }
    @Suppress("RestrictedApi")
    private fun requireIsolation() {
        check(instrumentation is HealthRevocationAcceptanceRunner)
        val prefix = "health-revocation-acceptance-"
        listOf(HealthCareStore.DEFAULT_DB, HealthRecordStore.DEFAULT_DB, HealthPrivacyStore.DEFAULT_DB,
            AgentConversationDatabase.DATABASE_NAME, "galaxyssi_agent_workspaces.db", AgentConnectorResponseInbox.DATABASE_NAME).forEach {
            check(context.getDatabasePath(it).name.startsWith(prefix)) { "Unisolated database" }
        }
        val manager = WorkManagerImpl.getInstance(context)
        val db = manager.javaClass.getMethod("getWorkDatabase").invoke(manager)
        val helper = db.javaClass.getMethod("getOpenHelper").invoke(db)
        val sqlite = Class.forName("androidx.sqlite.db.SupportSQLiteOpenHelper").getMethod("getWritableDatabase").invoke(helper)
        check((Class.forName("androidx.sqlite.db.SupportSQLiteDatabase").getMethod("getPath").invoke(sqlite) as String).contains(prefix))
    }
}
