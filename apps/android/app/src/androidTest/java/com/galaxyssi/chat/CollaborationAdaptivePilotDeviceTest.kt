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
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Explicit, bounded trials of the production planner. Task inputs and results are never bundled. */
@RunWith(AndroidJUnit4::class)
class CollaborationAdaptivePilotDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val args = InstrumentationRegistry.getArguments()
    private val lock = Any()

    @Test fun runAdaptiveRemotePilot() = runBlocking<Unit> {
        assumeTrue("Separate real-model authorization required", args.getString("adaptiveRemotePilot") == "true")
        require(args.getString("remotePilotTools") == CollaborationRemotePilotPlan.TOOL_SCOPE)
        val name = args.getString("adaptivePilotInput").orEmpty()
        require(name.matches(Regex("[a-zA-Z0-9_-]+\\.json")))
        val input = File(context.getExternalFilesDir(null), name)
        require(input.length() in 1..512_000)
        val raw = input.readBytes()
        val digest = CollaborationRemotePilotDispatch.sha256(raw)
        require(digest == args.getString("adaptivePilotSha256")) { "Frozen adaptive protocol changed" }
        val plan = CollaborationAdaptivePilotPlan.from(JSONObject(raw.toString(Charsets.UTF_8)),
            requireNotNull(args.getString("adaptivePilotMaxDispatches")?.toIntOrNull()),
            requireNotNull(args.getString("adaptivePilotMaxMillis")?.toLongOrNull()))
        plan.requireDevice(Build.MODEL, args.getString("pilotDeviceModel"))
        val selectionId = args.getString("remotePilotSelectionConversationId").orEmpty()
        val transcripts = AgentTranscriptStore(context)
        require(selectionId.isNotBlank() && transcripts.conversation(selectionId) != null)
        plan.requireAppSelection(AgentModelSelectionSettings.selection(context, selectionId))
        val previous = CollaborationPilotWindowSnapshot.read(context)
        val run = "adaptive-pilot-${plan.id}"
        val turn = "turn-$run"
        val file = File(context.getExternalFilesDir(null), "$run-report.json")
        check(!File(file.path + ".bak").exists() && !File(file.path + ".new").exists() && file.createNewFile()) {
            "Adaptive pilot already assigned; inspect existing evidence instead of repeating"
        }
        val dispatches = JSONArray()
        val outcomes = JSONArray()
        val rounds = JSONArray()
        val report = JSONObject().put("format", "galaxyssi.adaptive-pilot-report.v1").put("pilot_id", plan.id)
            .put("protocol_sha256", digest).put("device", Build.MODEL).put("app_version", BuildConfig.VERSION_NAME)
            .put("protocol_device_model", plan.deviceModel).put("operator_device_model", args.getString("pilotDeviceModel"))
            .put("app_version_code", BuildConfig.VERSION_CODE).put("run_id", run).put("turn_id", turn)
            .put("selection_source", "app_conversation_snapshot").put("selection_conversation_id", selectionId)
            .put("execution_mode", plan.executionMode)
            .put("test_scope", if (plan.singleAgent) "execution_delivery_only" else "host_goal_acceptance")
            .put("single_agent_tool_delegation_audited", false)
            .put("model_selection", plan.selection.json()).put("phone_dispatch_limit", plan.maximumDispatches)
            .put("trial_timeout_ms", plan.timeoutMillis).put("tool_scope", CollaborationRemotePilotPlan.TOOL_SCOPE)
            .put("production_prompt_preserved", true).put("fixed_work_plan", false)
            .put("interim_publication_enabled", !plan.singleAgent).put("milestone_archive_complete", false)
            .put("full_ui_lifecycle_tested", false).put("process_restart_tested", false)
            .put("tool_isolation_verified", false).put("equal_budget_comparison", false)
            .put("billed_cost", JSONObject.NULL).put("provider_request_count", JSONObject.NULL)
            .put("scientific_capability_gain_proven", false).put("goal_verified_by_external_evaluator", false)
            .put("started_at", System.currentTimeMillis()).put("status", "preparing").put("finished", false)
            .put("phone_dispatches", dispatches).put("worker_results", outcomes).put("rounds", rounds)
        fun persist() = synchronized(lock) { save(file, report) }
        persist()
        val database = AgentEncryptedDatabase(context, run)
        check(database.keys().isEmpty()) { "Adaptive execution database already contains evidence; do not restart it" }
        val groups = CollaborationGroupStore(context)
        val control = AgentTeamDurableControl(context)
        val store = CollaborationAdaptivePilotMilestones.executionStore(context, database)
        var group = ""
        var milestoneArchive: CollaborationAdaptivePilotMilestones? = null
        var admission: CollaborationAdaptivePilotAdmission? = null
        var runner: CollaborationAdaptivePilotRunner? = null
        var runtime: AgentTeamExecutionRuntime? = null
        var clean = false
        var executionFailure: Exception? = null
        val started = SystemClock.elapsedRealtime()
        try {
            withTimeout(plan.timeoutMillis) {
                GalaxySSIMqttClient.connect(context)
                while (!GalaxySSIMqttClient.isConnected() || !GalaxySSIMqttClient.isSecureReady()) delay(250)
                GalaxySSIMqttClient.requestCapabilityManifestRefresh(force = true)
                CollaborationRemotePilotWorker.requireTarget(context, plan)
                group = transcripts.createAgentConversation("Adaptive pilot ${plan.id}").id
                groups.update(group) { it.copy(members = plan.members, coordinatorId = plan.members.first().id,
                    workflow = if (plan.singleAgent) CollaborationWorkflow.PARALLEL else CollaborationWorkflow.RESEARCH) }
                milestoneArchive = CollaborationAdaptivePilotMilestones(group, run, turn, CollaborationResearchWorkspace(context)) { access, ref ->
                    CollaborationEvidenceLedger(context).read(access, ref.getString("evidence_id"), ref.getString("sha256"))
                }
                report.put("conversation_id", group).put("execution_database", run).put("status", "running")
                persist()
                val guard = CollaborationAdaptivePilotAdmission(plan, group, run, turn, started + plan.timeoutMillis,
                    SystemClock::elapsedRealtime, { store.deliveryCheckpoint(run) }) { entry ->
                    synchronized(lock) { dispatches.put(entry); persist() }
                }
                admission = guard
                val native = AndroidAgentActionExecutor(context)
                val delegated = object : AgentActionExecutor {
                    override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                        plan.requireAppSelection(AgentModelSelectionSettings.selection(context, selectionId))
                        CollaborationRemotePilotWorker.requireTarget(context, plan)
                        return native.execute(guard.admit(action), screen)
                    }
                }
                val delegate = CollaborationRemotePilotWorker.create(context, delegated)
                val worker = object : AgentTeamMemberWorker {
                    override suspend fun execute(execution: AgentTeamMemberExecutionContext): AgentSubagentOutput {
                        plan.requireAppSelection(AgentModelSelectionSettings.selection(context, selectionId))
                        guard.prepare(execution)
                        val observed = guard.observeResources(execution, System.currentTimeMillis())
                        val begin = System.currentTimeMillis()
                        return delegate.execute(observed).also { output -> synchronized(lock) {
                            outcomes.put(JSONObject().put("node_id", execution.member.memberId)
                                .put("person_id", execution.member.context[CollaborationResearchWorkflow.PERSON])
                                .put("stage", execution.member.context[CollaborationResearchWorkflow.STAGE])
                                .put("assignment", execution.member.objective).put("started_at", begin)
                                .put("ended_at", System.currentTimeMillis()).put("content", output.content)
                                .put("content_sha256", CollaborationRemotePilotDispatch.sha256(output.content.toByteArray(Charsets.UTF_8))))
                            persist()
                        } }
                    }
                    override suspend fun sendMessage(member: AgentTeamMember, runId: String, message: AgentControlMessage) =
                        delegate.sendMessage(member, runId, message)
                }
                runtime = AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = if (plan.singleAgent) 1 else 2,
                    maxContextChars = 60_000, maxOutputChars = 24_000),
                    mailbox = EncryptedAgentTeamMailbox(context))
                runner = CollaborationAdaptivePilotRunner(store, requireNotNull(runtime), guard,
                    projectRecruits = { groups.projectRecruits(group, it) }, checkpoint = { snapshot, checkpoint ->
                        synchronized(lock) {
                            report.put("interim_evidence", requireNotNull(milestoneArchive).capture(checkpoint))
                            rounds.put(JSONObject().put("round", checkpoint.request.context[CollaborationGoalLoop.ROUND]?.toString() ?: "0")
                                .put("state", snapshot.state.name).put("goal_disposition", snapshot.goalDisposition)
                                .put("primary_node", snapshot.primaryMemberId).put("final_output", snapshot.finalOutput)
                                .put("original_goal", checkpoint.request.goal).put("context", JSONObject(checkpoint.request.context))
                                .put("members", members(checkpoint)))
                            persist()
                        }
                    }, singleAgent = plan.singleAgent)
                val reason = requireNotNull(runner).run(plan.definition(group, run),
                    AgentRunRequest(group, turn, "task-$run", runId = run, goal = plan.goal, idempotencyKey = run), worker)
                report.put("status", reason)
            }
        } catch (failure: Exception) {
            executionFailure = failure
            report.put("status", "interrupted_or_failed").put("failure_type", failure.javaClass.simpleName)
                .put("failure", failure.message.orEmpty())
        } finally {
            admission?.close()
            report.put("execution_ended_at", System.currentTimeMillis()).put("execution_elapsed_ms", SystemClock.elapsedRealtime() - started)
            withContext(NonCancellable) {
                control.set(run, AgentTeamUserControl.STOP)
                runner?.activeHandle?.let { if (it.isActive) it.cancel("Authorized adaptive trial ended") }
                val responses = EncryptedAgentManagedResponseLedger(context)
                val recovery = AgentTeamRemoteStopRecovery(context)
                try {
                    clean = withTimeoutOrNull(90_000) {
                        while (true) {
                            store.snapshot(run)?.let { recovery.reconcile(listOf(it), responses) { id -> id == run } }
                            if (runner?.activeHandle?.isActive != true && responses.pendingForSupervisor(run).isEmpty()) break
                            delay(250)
                        }
                        true
                    } == true
                    report.put("cleanup_confirmed", clean).put("durable_control", control.get(run).name)
                        .put("pending_remote_owners", JSONArray(responses.pendingForSupervisor(run).map { it.ownerRunId }))
                    store.deliveryCheckpoint(run)?.let {
                        report.put("last_members", members(it))
                        report.put("interim_evidence", requireNotNull(milestoneArchive).capture(it))
                        report.put("milestone_archive_complete", true)
                    }
                    report.put("saved_execution_records", JSONArray(database.keys().map { key ->
                        JSONObject().put("key", key).put("value", database.readString(key, ""))
                    }))
                    report.put("finished", true).put("ended_at", System.currentTimeMillis())
                    persist()
                    if (clean && report.optBoolean("milestone_archive_complete")) {
                        runtime?.close()
                        if (group.isNotBlank()) { groups.remove(group); transcripts.deleteConversation(group) }
                        store.clear()
                    }
                } catch (failure: Exception) {
                    report.put("cleanup_confirmed", false).put("cleanup_failure", failure.message.orEmpty())
                    persist()
                } finally { runtime?.close() }
            }
            report.put("active_conversation_preserved", previous == CollaborationPilotWindowSnapshot.read(context))
                .put("active_conversation_check", "persisted_window_selections")
        }
        val verdict = CollaborationAdaptivePilotVerdict.evaluate(report)
        report.put("test_verdict", if (verdict.passed) "passed" else "failed")
            .put("test_failures", JSONArray(verdict.failures))
        persist()
        verdict.requirePassed(executionFailure)
    }

    private fun members(checkpoint: AgentTeamExecutionCheckpoint) = JSONArray(checkpoint.definition.members.map { member ->
        val result = checkpoint.completed[member.memberId]
        JSONObject().put("node_id", member.memberId).put("person_id", member.context[CollaborationResearchWorkflow.PERSON])
            .put("role", member.role).put("assignment", member.objective).put("delivery", member.deliveryMode.name)
            .put("context", JSONObject(member.context)).put("dependencies", JSONArray(member.dependsOnAgentIds))
            .put("status", result?.status?.name ?: "not_completed").put("output", result?.output ?: JSONObject.NULL)
            .put("error", result?.errorMessage ?: JSONObject.NULL).put("output_truncated", result?.outputTruncated ?: false)
    })

    private fun save(file: File, value: JSONObject) {
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try { stream.write(value.toString().toByteArray(Charsets.UTF_8)); atomic.finishWrite(stream) }
        catch (failure: Throwable) { atomic.failWrite(stream); throw failure }
    }
}
