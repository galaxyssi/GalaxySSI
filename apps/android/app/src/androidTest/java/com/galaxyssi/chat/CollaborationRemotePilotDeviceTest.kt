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

/** Explicitly authorized engineering trials; does not certify tool isolation or equal-cost efficacy. */
@RunWith(AndroidJUnit4::class)
class CollaborationRemotePilotDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val args = InstrumentationRegistry.getArguments()
    private val reportLock = Any()

    @Test fun runPairedRemotePilot() = runBlocking {
        assumeTrue("Separate real-model authorization required", args.getString("collaborationRemotePilot") == "true")
        require(args.getString("pilotDeviceModel") == "SM-S9480" && Build.MODEL == "SM-S9480")
        require(args.getString("remotePilotTools") == CollaborationRemotePilotPlan.TOOL_SCOPE) {
            "Operator must acknowledge production tools are not isolated"
        }
        val name = args.getString("remotePilotInput").orEmpty()
        require(Regex("[a-zA-Z0-9_-]+\\.json").matches(name))
        val input = File(context.getExternalFilesDir(null), name)
        require(input.length() in 1..512_000)
        val bytes = input.readBytes()
        val digest = CollaborationRemotePilotDispatch.sha256(bytes)
        check(digest == args.getString("remotePilotSha256")) { "Frozen remote protocol changed" }
        val authorized = requireNotNull(args.getString("remotePilotMaxDispatches")?.toIntOrNull())
        val plan = CollaborationRemotePilotPlan.from(JSONObject(bytes.toString(Charsets.UTF_8)), authorized)
        val freezeValue = args.getString("remotePilotFreezeArtifacts")
        require(freezeValue == null || freezeValue in setOf("true", "false"))
        val freezeArtifacts = freezeValue == "true"
        val evaluatorSha256 = args.getString("remotePilotFeedbackEvaluatorSha256")
        require(evaluatorSha256 == null || Regex("[a-f0-9]{64}").matches(evaluatorSha256))
        val transcripts = AgentTranscriptStore(context)
        val selectionConversation = args.getString("remotePilotSelectionConversationId").orEmpty()
        require(selectionConversation.isNotBlank() && transcripts.conversation(selectionConversation) != null)
        val selected = AgentModelSelectionSettings.selection(context, selectionConversation)
        plan.requireAppSelection(selected)
        val reportFile = File(context.getExternalFilesDir(null), "remote-${plan.id}-report.json")
        check(!File(reportFile.path + ".bak").exists() && !File(reportFile.path + ".new").exists() && reportFile.createNewFile()) {
            "Remote pilot already assigned; inspect existing evidence instead of repeating"
        }
        val slots = JSONArray(plan.slots.map { JSONObject().put("id", it.id).put("case_id", it.caseId)
            .put("arm", it.arm).put("status", "not_attempted") })
        val report = JSONObject().put("format", "galaxyssi.remote-pilot-report.v1").put("pilot_id", plan.id)
            .put("protocol_sha256", digest).put("device", Build.MODEL).put("app_version", BuildConfig.VERSION_NAME)
            .put("app_version_code", BuildConfig.VERSION_CODE).put("authorized_phone_dispatches", authorized)
            .put("maximum_planned_dispatches", plan.maximumDispatches).put("tool_scope", CollaborationRemotePilotPlan.TOOL_SCOPE)
            .put("model_selection", plan.selection.json()).put("provider_request_count", JSONObject.NULL)
            .put("selection_source", "app_conversation_snapshot").put("selection_conversation_id", selectionConversation)
            .put("provider_token_total", JSONObject.NULL).put("billed_cost", JSONObject.NULL)
            .put("tool_isolation_verified", false).put("ready_for_equal_budget_comparison", false)
            .put("freeze_candidate_artifacts", freezeArtifacts)
            .put("external_feedback_evaluator_sha256", evaluatorSha256 ?: JSONObject.NULL)
            .put("purpose", "remote_engineering_comparison_not_closed_book_or_efficacy")
            .put("started_at", System.currentTimeMillis()).put("finished", false).put("slots", slots)
        val persist = { synchronized(reportLock) { save(reportFile, report) } }
        persist()
        val previous = transcripts.activeConversation().id
        try {
            for ((index, slot) in plan.slots.withIndex()) {
                plan.requireAppSelection(AgentModelSelectionSettings.selection(context, selectionConversation))
                if (!runSlot(plan, slot, slots.getJSONObject(index), digest, freezeArtifacts, evaluatorSha256, persist)) {
                    for (remaining in index + 1 until slots.length()) slots.getJSONObject(remaining)
                        .put("reason", "previous_trial_cleanup_not_confirmed")
                    break
                }
            }
            report.put("finished", true).put("ended_at", System.currentTimeMillis())
            persist()
        } finally {
            assertEquals("Remote pilot must not switch the user's conversation", previous, transcripts.activeConversation().id)
        }
    }

    private suspend fun runSlot(plan: CollaborationRemotePilotPlan, slot: CollaborationRemotePilotPlan.Slot,
                                outcome: JSONObject, protocolSha256: String, freezeArtifacts: Boolean, evaluatorSha256: String?,
                                persist: () -> Unit): Boolean {
        val run = "remote-pilot-${plan.id}-${slot.id}"
        val turn = "turn-$run"
        val database = AgentEncryptedDatabase(context, run)
        val store = EncryptedAgentTeamExecutionStore(database)
        var group = ""
        var runtime: AgentTeamExecutionRuntime? = null
        var handle: AgentTeamExecutionHandle? = null
        var guard: CollaborationRemotePilotDispatch? = null
        var clean = false
        val started = SystemClock.elapsedRealtime()
        val dispatches = JSONArray()
        outcome.put("status", "started").put("run_id", run).put("turn_id", turn)
            .put("started_at", System.currentTimeMillis()).put("phone_dispatches", dispatches)
            .put("planned_nodes", JSONArray(listOf("draft", "review", "final")))
        persist()
        try {
            withTimeout(plan.timeoutMillis) {
                GalaxySSIMqttClient.connect(context)
                while (!GalaxySSIMqttClient.isConnected() || !GalaxySSIMqttClient.isSecureReady()) delay(250)
                GalaxySSIMqttClient.requestCapabilityManifestRefresh(force = true)
                requireTarget(plan)
                group = AgentTranscriptStore(context).createAgentConversation("Remote pilot ${slot.id}").id
                val roster = plan.members(slot)
                CollaborationGroupStore(context).update(group) { it.copy(members = roster,
                    coordinatorId = roster.first().id, workflow = CollaborationWorkflow.PARALLEL) }
                outcome.put("conversation_id", group).put("execution_database", run)
                persist()
                val definition = plan.definition(slot, group, run)
                guard = CollaborationRemotePilotDispatch(plan, definition, group, run, turn,
                    started + plan.timeoutMillis, SystemClock::elapsedRealtime) { entry ->
                    synchronized(reportLock) { dispatches.put(entry); persist() }
                }
                val activeGuard = requireNotNull(guard)
                val native = AndroidAgentActionExecutor(context)
                val bounded = object : AgentActionExecutor {
                    override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                        requireTarget(plan)
                        return native.execute(activeGuard.admit(action), screen)
                    }
                }
                val delegate = CollaborationRemotePilotWorker.create(context, bounded)
                val feedback = evaluatorSha256?.let { CollaborationPilotExecutionFeedback(plan.id, slot.id, protocolSha256, it) }
                val observations = JSONArray()
                outcome.put("execution_feedback", observations)
                val pinned = object : AgentTeamMemberWorker {
                    override suspend fun execute(context: AgentTeamMemberExecutionContext): AgentSubagentOutput {
                        requireTarget(plan)
                        activeGuard.prepare(context, feedback?.prompt(context.handoff).orEmpty())
                        val output = delegate.execute(context)
                        val node = context.member.memberId
                        if (feedback != null && node in setOf("draft", "review")) {
                            val raw = feedback.request(node, output.content)
                            val prefix = "feedback-${plan.id}-${slot.id}-$node"
                            val requestFile = File(this@CollaborationRemotePilotDeviceTest.context.getExternalFilesDir(null), "$prefix.request.json")
                            val responseFile = File(requestFile.parentFile, "$prefix.response.json")
                            check(!requestFile.exists() && !responseFile.exists()) { "Feedback exchange already exists; do not repeat model work" }
                            saveRaw(requestFile, raw)
                            val record = JSONObject().put("node_id", node).put("request_file", requestFile.name)
                                .put("request_sha256", CollaborationPilotExecutionFeedback.hash(raw)).put("status", "waiting")
                            observations.put(record)
                            persist()
                            while (!responseFile.isFile) delay(250)
                            require(responseFile.length() in 1..40_000)
                            val response = responseFile.readText(Charsets.UTF_8)
                            feedback.accept(node, response)
                            record.put("status", "accepted").put("response", JSONObject(response))
                            persist()
                        }
                        return output
                    }
                    override suspend fun sendMessage(member: AgentTeamMember, runId: String, message: AgentControlMessage) =
                        delegate.sendMessage(member, runId, message)
                }
                runtime = AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 1,
                    maxContextChars = 60_000, maxOutputChars = 24_000))
                handle = runtime!!.start(definition, AgentRunRequest(group, turn, "task-$run", runId = run,
                    goal = slot.prompt, idempotencyKey = run), pinned)
                val result = handle!!.await()
                outcome.put("status", if (result.snapshot.state == AgentTeamExecutionState.SUCCEEDED) "completed" else "failed")
                    .put("result_truncated", result.subagentResult.results.any { it.outputTruncated })
                if (result.subagentResult.results.any { it.outputTruncated }) outcome.put("status", "invalid_output_envelope")
                if (freezeArtifacts && outcome.getString("status") == "completed") {
                    val source = CollaborationPilotArtifact.Source.of(plan, slot, group, run, turn, protocolSha256)
                    val artifact = CollaborationPilotArtifact.capture(source, result.snapshot, dispatches,
                        result.subagentResult.results.any { it.outputTruncated })
                    val ref = CollaborationPilotArtifactStore(context, plan.id).freeze(artifact)
                    outcome.put("candidate_artifact", ref.json()).put("candidate_source", source.json())
                        .put("candidate_trust", "unverified_candidate")
                    persist()
                }
            }
        } catch (failure: Exception) {
            outcome.put("status", "failed").put("failure_type", failure.javaClass.simpleName)
                .put("failure", failure.message.orEmpty())
        } finally {
            guard?.close()
            outcome.put("execution_elapsed_ms", SystemClock.elapsedRealtime() - started).put("execution_ended_at", System.currentTimeMillis())
            withContext(NonCancellable) {
                try {
                    AgentTeamDurableControl(context).set(run, AgentTeamUserControl.STOP)
                    handle?.let { if (it.isActive) it.cancel("Authorized remote pilot slot ended") }
                    val responses = EncryptedAgentManagedResponseLedger(context)
                    val recovery = AgentTeamRemoteStopRecovery(context)
                    clean = withTimeoutOrNull(90_000L) {
                        while (true) {
                            val snapshot = store.snapshot(run)
                            snapshot?.let { recovery.reconcile(listOf(it), responses) { id -> id == run } }
                            if (handle?.isActive != true && responses.pendingForSupervisor(run).isEmpty()) break
                            delay(250)
                        }
                        true
                    } == true
                    outcome.put("cleanup_confirmed", clean).put("durable_control", AgentTeamDurableControl(context).get(run).name)
                        .put("pending_remote_owners", JSONArray(responses.pendingForSupervisor(run).map { it.ownerRunId }))
                        .put("cleanup_elapsed_ms", SystemClock.elapsedRealtime() - started - outcome.getLong("execution_elapsed_ms"))
                        .put("ended_at", System.currentTimeMillis())
                    store.snapshot(run)?.let { snapshot ->
                        outcome.put("state", snapshot.state.name).put("final_output", snapshot.finalOutput)
                            .put("members", JSONArray(snapshot.members.map { JSONObject().put("node", it.memberId)
                                .put("person_id", it.personId).put("status", it.status.name).put("output", it.output)
                                .put("error", it.errorMessage).put("started_at", it.startedAtMillis).put("ended_at", it.completedAtMillis) }))
                    }
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

    private fun requireTarget(plan: CollaborationRemotePilotPlan) {
        CollaborationRemotePilotWorker.requireTarget(context, plan)
    }

    private fun save(file: File, value: JSONObject) {
        saveRaw(file, value.toString())
    }

    private fun saveRaw(file: File, value: String) {
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try { stream.write(value.toByteArray(Charsets.UTF_8)); atomic.finishWrite(stream) }
        catch (failure: Throwable) { atomic.failWrite(stream); throw failure }
    }
}
