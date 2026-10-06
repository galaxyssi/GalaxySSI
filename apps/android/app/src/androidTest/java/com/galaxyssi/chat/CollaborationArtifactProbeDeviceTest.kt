package com.galaxyssi.chat

import android.os.Build
import android.os.SystemClock
import android.util.AtomicFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
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

/** Opt-in fresh-context candidate availability probes. No claim of isolated tools or equal cost. */
@RunWith(AndroidJUnit4::class)
class CollaborationArtifactProbeDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val args = InstrumentationRegistry.getArguments()
    private val lock = Any()

    @Test fun runFreshArtifactProbes() = runBlocking {
        assumeTrue("Explicit live probe authorization required", args.getString("artifactTransferProbe") == "true")
        require(Build.MODEL == "SM-S9480" && args.getString("pilotDeviceModel") == "SM-S9480")
        require(args.getString("remotePilotTools") == CollaborationRemotePilotPlan.TOOL_SCOPE)
        val name = args.getString("remotePilotInput").orEmpty()
        require(name.matches(Regex("[a-zA-Z0-9_-]+\\.json")))
        val input = File(context.getExternalFilesDir(null), name)
        require(input.length() in 1..512_000)
        val bytes = input.readBytes()
        val digest = CollaborationRemotePilotDispatch.sha256(bytes)
        require(digest == args.getString("remotePilotSha256"))
        val allowance = requireNotNull(args.getString("remotePilotMaxDispatches")?.toIntOrNull())
        val plan = CollaborationArtifactProbePlan.from(JSONObject(bytes.toString(Charsets.UTF_8)), allowance)
        val transcripts = AgentTranscriptStore(context)
        val selection = args.getString("remotePilotSelectionConversationId").orEmpty()
        require(transcripts.conversation(selection) != null)
        val reportFile = File(context.getExternalFilesDir(null), "probe-${plan.id}-report.json")
        check(!File(reportFile.path + ".bak").exists() && !File(reportFile.path + ".new").exists() && reportFile.createNewFile())
        val slots = JSONArray(plan.slots.map { JSONObject().put("id", it.id).put("case_id", it.caseId)
            .put("source_id", it.sourceId).put("condition", it.condition).put("status", "not_attempted") })
        val report = JSONObject().put("format", "galaxyssi.artifact-transfer-probe-report.v1").put("pilot_id", plan.id)
            .put("protocol_sha256", digest).put("app_version", BuildConfig.VERSION_NAME).put("app_version_code", BuildConfig.VERSION_CODE)
            .put("model_selection", plan.selection.json()).put("selection_conversation_id", selection)
            .put("authorized_phone_dispatches", allowance).put("maximum_planned_dispatches", plan.slots.size)
            .put("tool_isolation_verified", false).put("provider_request_count", JSONObject.NULL)
            .put("provider_token_total", JSONObject.NULL).put("billed_cost", JSONObject.NULL)
            .put("ready_for_equal_budget_comparison", false).put("finished", false).put("slots", slots)
            .put("started_at", System.currentTimeMillis())
        fun persist() = synchronized(lock) {
            val file = AtomicFile(reportFile)
            val stream = file.startWrite()
            try { stream.write(report.toString().toByteArray(Charsets.UTF_8)); file.finishWrite(stream) }
            catch (failure: Throwable) { file.failWrite(stream); throw failure }
        }
        persist()
        val previous = transcripts.activeConversation().id
        try {
            for ((index, slot) in plan.slots.withIndex()) {
                if (!runSlot(plan, slot, selection, slots.getJSONObject(index), ::persist)) {
                    for (remaining in index + 1 until slots.length()) slots.getJSONObject(remaining)
                        .put("reason", "previous_trial_cleanup_not_confirmed")
                    break
                }
            }
            report.put("finished", true).put("ended_at", System.currentTimeMillis())
            persist()
        } finally { assertEquals(previous, transcripts.activeConversation().id) }
    }

    private suspend fun runSlot(plan: CollaborationArtifactProbePlan, slot: CollaborationArtifactProbePlan.Slot,
                                selection: String, outcome: JSONObject, persist: () -> Unit): Boolean {
        val run = "artifact-probe-${plan.id}-${slot.id}"
        val turn = "turn-$run"
        val database = AgentEncryptedDatabase(context, run)
        val store = EncryptedAgentTeamExecutionStore(database)
        var runtime: AgentTeamExecutionRuntime? = null
        var handle: AgentTeamExecutionHandle? = null
        var guard: CollaborationRemotePilotDispatch? = null
        var group = ""
        var clean = false
        val started = SystemClock.elapsedRealtime()
        val dispatches = JSONArray()
        outcome.put("run_id", run).put("turn_id", turn).put("status", "started")
            .put("started_at", System.currentTimeMillis()).put("phone_dispatches", dispatches)
            .put("candidate_loaded", false)
        persist()
        try {
            withTimeout(plan.timeoutMillis) {
                val policy = plan.bind(slot) { candidate ->
                    CollaborationPilotArtifactStore(context, candidate.source.pilotId).read(candidate.source, candidate.reference)
                }
                policy.requireAppSelection(AgentModelSelectionSettings.selection(context, selection))
                outcome.put("candidate_loaded", policy.candidateText != null)
                    .put("candidate_reference", policy.candidate.reference.json())
                    .put("source_arm", policy.candidate.source["arm"])
                persist()
                GalaxySSIMqttClient.connect(context)
                while (!GalaxySSIMqttClient.isConnected() || !GalaxySSIMqttClient.isSecureReady()) delay(250)
                GalaxySSIMqttClient.requestCapabilityManifestRefresh(force = true)
                CollaborationRemotePilotWorker.requireTarget(context, policy)
                group = AgentTranscriptStore(context).createAgentConversation("Artifact probe ${slot.id}").id
                val member = CollaborationMember(id = "analyst", name = "Target solver", agentId = plan.targetId,
                    providerLabel = "Codex", role = "Independent target solver", modelId = plan.selection.modelId)
                CollaborationGroupStore(context).update(group) { it.copy(members = listOf(member), coordinatorId = member.id) }
                outcome.put("conversation_id", group)
                persist()
                val definition = policy.definition(group, run)
                val activeGuard = CollaborationRemotePilotDispatch(policy, definition, group, run, turn,
                    started + plan.timeoutMillis, SystemClock::elapsedRealtime) { entry -> synchronized(lock) { dispatches.put(entry); persist() } }
                guard = activeGuard
                val native = AndroidAgentActionExecutor(context)
                val bounded = object : AgentActionExecutor {
                    override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                        policy.requireAppSelection(AgentModelSelectionSettings.selection(context, selection))
                        CollaborationRemotePilotWorker.requireTarget(context, policy)
                        return native.execute(activeGuard.admit(action), screen)
                    }
                }
                val worker = CollaborationRemotePilotWorker.create(context, bounded)
                runtime = AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 1,
                    maxContextChars = 60_000, maxOutputChars = 24_000))
                handle = runtime!!.start(definition, AgentRunRequest(group, turn, "task-$run", runId = run,
                    goal = slot.prompt, idempotencyKey = run), object : AgentTeamMemberWorker {
                    override suspend fun execute(context: AgentTeamMemberExecutionContext): AgentSubagentOutput {
                        activeGuard.prepare(context)
                        return worker.execute(context)
                    }
                    override suspend fun sendMessage(member: AgentTeamMember, runId: String, message: AgentControlMessage) =
                        worker.sendMessage(member, runId, message)
                })
                val result = handle!!.await()
                val truncated = result.subagentResult.results.any { it.outputTruncated }
                outcome.put("result_truncated", truncated).put("status", when {
                    truncated -> "invalid_output_envelope"
                    result.snapshot.state == AgentTeamExecutionState.SUCCEEDED -> "completed"
                    else -> "failed"
                })
            }
        } catch (failure: Exception) {
            outcome.put("status", "failed").put("failure_type", failure.javaClass.simpleName).put("failure", failure.message.orEmpty())
        } finally {
            guard?.close()
            outcome.put("execution_elapsed_ms", SystemClock.elapsedRealtime() - started)
            withContext(NonCancellable) {
                try {
                    AgentTeamDurableControl(context).set(run, AgentTeamUserControl.STOP)
                    handle?.let { if (it.isActive) it.cancel("Authorized artifact probe ended") }
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
                    outcome.put("cleanup_confirmed", clean).put("durable_control", AgentTeamDurableControl(context).get(run).name)
                        .put("pending_remote_owners", JSONArray(responses.pendingForSupervisor(run).map { it.ownerRunId }))
                        .put("ended_at", System.currentTimeMillis())
                    store.snapshot(run)?.let { outcome.put("state", it.state.name).put("final_output", it.finalOutput) }
                    persist()
                    if (clean) {
                        runtime?.close()
                        if (group.isNotBlank()) {
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
}
