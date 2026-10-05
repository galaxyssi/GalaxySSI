package com.galaxyssi.chat

import android.os.Build
import android.os.SystemClock
import android.util.AtomicFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.MessageDigest
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Real, opt-in cloud trials. Prompts/answers and reports stay on the authorized device and host. */
@RunWith(AndroidJUnit4::class)
class CollaborationPairedPilotDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val args = InstrumentationRegistry.getArguments()

    @Test fun preflight() {
        assumeTrue(args.getString("collaborationPilotPreflight") == "true")
        requireDevice()
        val targets = AppStoreAgentConnectorRegistry(context).registrations().filter { it.adapterType == "cloud-model-api" }
        save(File(context.getExternalFilesDir(null), "collaboration-pilot-preflight.json"), JSONObject()
            .put("device", Build.MODEL).put("app_version", BuildConfig.VERSION_NAME)
            .put("targets", JSONArray(targets.map { target -> JSONObject().put("id", target.agentId)
                .put("name", target.displayName) })))
    }

    @Test fun runPairedPilot() = runBlocking {
        assumeTrue("Requires explicit small-scale real-model authorization", args.getString("collaborationPairedPilot") == "true")
        requireDevice()
        val inputName = args.getString("pilotInput").orEmpty()
        require(Regex("[a-zA-Z0-9_-]+\\.json").matches(inputName))
        val bytes = File(context.getExternalFilesDir(null), inputName).readBytes()
        require(bytes.size <= 512_000)
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        check(digest == args.getString("pilotSha256")) { "Protocol differs from the frozen host input" }
        val cap = requireNotNull(args.getString("pilotMaxAdmissions")?.toIntOrNull())
        val plan = CollaborationPilotPlan.from(JSONObject(bytes.toString(Charsets.UTF_8)), cap)
        val reportFile = File(context.getExternalFilesDir(null), "${plan.id}-report.json")
        check(!reportFile.exists() && !File(reportFile.path + ".bak").exists()) {
            "Pilot already assigned; export/recover it, never silently repeat its trials"
        }
        val slots = JSONArray(plan.slots.map { JSONObject().put("id", it.id).put("case_id", it.caseId)
            .put("arm", it.arm).put("status", "not_attempted") })
        val report = JSONObject().put("format", "galaxyssi.paired-pilot-report.v1").put("pilot_id", plan.id)
            .put("protocol_sha256", digest).put("app_version", BuildConfig.VERSION_NAME).put("app_version_code", BuildConfig.VERSION_CODE)
            .put("device", Build.MODEL).put("maximum_admissions", plan.maximumAdmissions).put("authorized_admissions", cap)
            .put("purpose", "closed_book_calibration_not_efficacy").put("billing_cost", JSONObject.NULL)
            .put("text_profile", plan.profile.json()).put("slots", slots).put("finished", false)
        save(reportFile, report)
        val previous = AgentTranscriptStore(context).activeConversation().id
        for ((index, slot) in plan.slots.withIndex()) {
            val outcome = slots.getJSONObject(index)
            val clean = runSlot(plan, slot, digest, outcome) { save(reportFile, report) }
            save(reportFile, report)
            if (!clean) {
                for (remaining in index + 1 until slots.length()) slots.getJSONObject(remaining)
                    .put("reason", "previous_trial_cleanup_not_confirmed")
                break
            }
        }
        report.put("finished", true).put("ended_at", System.currentTimeMillis())
        save(reportFile, report)
        assertEquals("Pilot must not switch the user's selected conversation", previous, AgentTranscriptStore(context).activeConversation().id)
    }

    private suspend fun runSlot(plan: CollaborationPilotPlan, slot: CollaborationPilotPlan.Slot, digest: String,
                                outcome: JSONObject, persist: () -> Unit): Boolean {
        val run = "pilot-${plan.id}-${slot.id}"
        val database = AgentEncryptedDatabase(context, run)
        val store = EncryptedAgentTeamExecutionStore(database)
        val ledger = CollaborationModelCallLedger(context)
        var group = ""
        var runtime: AgentTeamExecutionRuntime? = null
        var handle: AgentTeamExecutionHandle? = null
        var clean = false
        val started = SystemClock.elapsedRealtime()
        outcome.put("status", "started").put("run_id", run).put("started_at", System.currentTimeMillis())
        persist()
        try {
            val available = AppStoreAgentConnectorRegistry(context).availableTargets()
                .any { it.id == plan.targetId && it.status == AgentConnectorStatus.AVAILABLE }
            check(available) { "Frozen target is unavailable; no fallback or replacement trial" }
            group = AgentTranscriptStore(context).createAgentConversation("Pilot ${slot.id}").id
            outcome.put("conversation_id", group)
            persist()
            val roster = plan.members(slot)
            CollaborationGroupStore(context).update(group) { it.copy(members = roster, coordinatorId = roster.first().id,
                workflow = CollaborationWorkflow.PARALLEL) }
            ledger.configureTrial(group, run, CollaborationTrialPolicy(digest, plan.targetId, plan.modelId, 3,
                System.currentTimeMillis() + plan.timeoutMillis, plan.profile))
            runtime = AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 1,
                maxContextChars = 60_000, maxOutputChars = 24_000))
            handle = runtime.start(plan.definition(slot, group, run), AgentRunRequest(group, "turn-$run", "task-$run",
                runId = run, goal = slot.prompt, idempotencyKey = run), worker())
            val result = withTimeout(plan.timeoutMillis) { handle.await() }
            outcome.put("status", if (result.snapshot.state == AgentTeamExecutionState.SUCCEEDED) "completed" else "failed")
        } catch (failure: Exception) {
            outcome.put("status", "failed").put("failure_type", failure.javaClass.simpleName)
                .put("failure", failure.message.orEmpty())
        } finally {
            outcome.put("execution_elapsed_ms", SystemClock.elapsedRealtime() - started)
                .put("execution_ended_at", System.currentTimeMillis())
            withContext(NonCancellable) {
                try {
                    if (group.isNotEmpty()) ledger.closeTrial(group, run)
                    AgentTeamDurableControl(context).set(run, AgentTeamUserControl.STOP)
                    handle?.let { if (it.isActive) it.cancel("Preregistered pilot ended") }
                    val responses = EncryptedAgentManagedResponseLedger(context)
                    val recovery = AgentTeamRemoteStopRecovery(context)
                    clean = withTimeoutOrNull(90_000L) {
                        while (true) {
                            store.snapshot(run)?.let { recovery.reconcile(listOf(it), responses) { id -> id == run } }
                            if (handle?.isActive != true && responses.pendingForSupervisor(run).isEmpty()) break
                            delay(250)
                        }
                        true
                    } == true
                    outcome.put("elapsed_ms", SystemClock.elapsedRealtime() - started)
                        .put("cleanup_elapsed_ms", SystemClock.elapsedRealtime() - started - outcome.getLong("execution_elapsed_ms"))
                        .put("ended_at", System.currentTimeMillis()).put("cleanup_confirmed", clean)
                    store.snapshot(run)?.let { snapshot ->
                        outcome.put("state", snapshot.state.name).put("final_output", snapshot.finalOutput)
                            .put("members", JSONArray(snapshot.members.map { JSONObject().put("node", it.memberId)
                                .put("person_id", it.personId).put("status", it.status.name).put("output", it.output)
                                .put("error", it.errorMessage).put("started_at", it.startedAtMillis).put("ended_at", it.completedAtMillis) }))
                    }
                    if (group.isNotEmpty()) {
                        outcome.put("admissions", ledger.trialSnapshot(group, run))
                        val calls = JSONArray()
                        var cursor = ""
                        do {
                            val page = ledger.page(group, run, cursor)
                            page.first.forEach(calls::put)
                            cursor = page.second.orEmpty()
                        } while (cursor.isNotEmpty())
                        outcome.put("model_calls", calls)
                    }
                    persist()
                    if (clean) {
                        runtime?.close()
                        if (group.isNotEmpty()) {
                            CollaborationGroupStore(context).remove(group)
                            AgentTranscriptStore(context).deleteConversation(group)
                        }
                        database.clear()
                    }
                } catch (failure: Exception) {
                    clean = false
                    outcome.put("cleanup_confirmed", false).put("cleanup_failure", failure.message.orEmpty())
                    persist()
                } finally { runtime?.close() }
            }
        }
        return clean
    }

    private fun worker(): ActionExecutorAgentTeamMemberWorker {
        val provider = ActionExecutorAgentProvider(
            registrationSource = { AppStoreAgentConnectorRegistry(context).registrations() },
            delegate = AndroidAgentActionExecutor(context), runStartReceipts = EncryptedAgentRunStartReceiptStore(context),
            healthLedger = EncryptedAgentProviderHealthLedger(context), managedResponses = EncryptedAgentManagedResponseLedger(context),
            globalRunSlots = AgentGlobalRunSlotStore(context))
        return ActionExecutorAgentTeamMemberWorker(provider, AgentAdapterDirectory().apply { register(provider) },
            screenProvider = { ScreenContext(foregroundApp = "GalaxySSI pilot", pageTitle = "Closed-book calibration") },
            progressContext = context.applicationContext)
    }

    private fun requireDevice() {
        require(args.getString("pilotDeviceModel") == "SM-S9480" && Build.MODEL == "SM-S9480") { "S26U authorization required" }
    }

    private fun save(file: File, value: JSONObject) {
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try { stream.write(value.toString().toByteArray(Charsets.UTF_8)); atomic.finishWrite(stream) }
        catch (failure: Throwable) { atomic.failWrite(stream); throw failure }
    }
}
