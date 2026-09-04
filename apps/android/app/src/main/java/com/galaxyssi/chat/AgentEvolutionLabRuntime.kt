package com.galaxyssi.chat

import android.content.Context
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.io.Closeable
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

data class AgentLabRuntimeSnapshot(
    val runningCampaignIds: Set<String>,
    val availableAgents: List<AgentRegistration>,
    val maximumParallelTrials: Int
)

class AgentEvolutionLabRuntime(
    context: Context,
    private val store: AgentLabStore = AgentLabStore(context),
    private val recorder: AgentRunRecorder = AgentRunRecorder(context),
    private val runEvents: AgentRunEventStore = AgentRunEventStore(context),
    private val maximumParallelTrials: Int = DEFAULT_PARALLEL_TRIALS
) : Closeable {
    private val appContext = context.applicationContext
    private val provider = ActionExecutorAgentProvider(
        registrationSource = { AppStoreAgentConnectorRegistry(appContext).registrations() },
        delegate = AndroidAgentActionExecutor(appContext),
        runStartReceipts = EncryptedAgentRunStartReceiptStore(appContext),
        healthLedger = EncryptedAgentProviderHealthLedger(appContext),
        managedResponses = EncryptedAgentManagedResponseLedger(appContext),
        globalRunSlots = AgentGlobalRunSlotStore(appContext)
    )
    private val directory = AgentAdapterDirectory().apply { register(provider) }
    private val screenPerceptionProvider = AndroidScreenPerceptionProvider(appContext)
    private val worker = ActionExecutorAgentTeamMemberWorker(
        provider = provider,
        directory = directory,
        screenProvider = { screenPerceptionProvider.capture() },
        livenessProbeMillis = EVAL_TRIAL_LIVENESS_PROBE_MILLIS
    )
    private val nativeTools by lazy {
        AgentPhoneNativeToolCatalog.defaultRegistry(
            context = appContext,
            screenProvider = { screenPerceptionProvider.capture() }
        )
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO + CoroutineName("AgentEvolutionLab"))
    private val running = ConcurrentHashMap<String, kotlinx.coroutines.Job>()
    private val trialPermits = Semaphore(maximumParallelTrials.coerceIn(1, MAX_PARALLEL_TRIALS))
    private val recoveryTrialMutex = Mutex()
    private val agentSnapshotLock = Any()
    @Volatile private var agentSnapshot: List<AgentRegistration> = emptyList()
    @Volatile private var agentSnapshotAtMillis: Long = 0L

    init {
        scope.launch(CoroutineName("AgentEvolutionLabWatchdog")) {
            while (isActive) {
                delay(WATCHDOG_INTERVAL_MILLIS)
                recoverStalledCampaigns()
            }
        }
    }

    fun availableAgents(): List<AgentRegistration> {
        val now = System.currentTimeMillis()
        agentSnapshot.takeIf {
            it.isNotEmpty() && now - agentSnapshotAtMillis < AGENT_SNAPSHOT_TTL_MILLIS
        }?.let { return it }
        return synchronized(agentSnapshotLock) {
            val refreshedAt = System.currentTimeMillis()
            agentSnapshot.takeIf {
                it.isNotEmpty() && refreshedAt - agentSnapshotAtMillis < AGENT_SNAPSHOT_TTL_MILLIS
            } ?: AgentLabAgentSelectionPolicy.independentAgents(
                AppStoreAgentConnectorRegistry(appContext).registrations().filter { registration ->
                    registration.kind in setOf(AgentConnectorKind.AGENT, AgentConnectorKind.MODEL) &&
                        registration.status in setOf(
                            AgentEndpointStatus.ONLINE,
                            AgentEndpointStatus.IDLE,
                            AgentEndpointStatus.BUSY
                        )
                }
            ).also {
                agentSnapshot = it
                agentSnapshotAtMillis = refreshedAt
            }
        }
    }

    fun snapshot(): AgentLabRuntimeSnapshot = AgentLabRuntimeSnapshot(
        runningCampaignIds = running.keys.toSet(),
        availableAgents = availableAgents(),
        maximumParallelTrials = maximumParallelTrials.coerceIn(1, MAX_PARALLEL_TRIALS)
    )

    fun createAndStart(task: String, agentIds: List<String>, repetitions: Int): AgentLabCampaign {
        val availableIds = availableAgents().mapTo(hashSetOf(), AgentRegistration::agentId)
        require(agentIds.distinct().all(availableIds::contains)) { "Agent Lab selection contains an unavailable Agent" }
        return store.create(task, agentIds, repetitions).also { start(it.id) }
    }

    @Synchronized
    fun start(campaignId: String): Boolean {
        val cleanId = campaignId.trim()
        val campaign = store.get(cleanId) ?: return false
        return startPrepared(campaign)
    }

    @Synchronized
    internal fun startPrepared(campaign: AgentLabCampaign): Boolean {
        val cleanId = campaign.id.trim()
        if (store.isCancellationRequested(cleanId)) return false
        if (campaign.status in setOf(AgentLabCampaignStatus.COMPLETED, AgentLabCampaignStatus.CANCELLED)) return false
        if (running[cleanId]?.isActive == true) return false
        val job = scope.launch {
            runCampaign(cleanId)
        }
        running[cleanId] = job
        job.invokeOnCompletion {
            if (running.remove(cleanId, job) && scope.isActive && !store.isCancellationRequested(cleanId)) {
                scope.launch {
                    delay(RESTART_AFTER_EXIT_MILLIS)
                    resumeIncomplete(
                        listOf(cleanId),
                        AgentEvalCondition.PROCESS_DEATH,
                        "Agent Lab campaign worker exited before all trials became terminal"
                    )
                }
            }
        }
        return true
    }

    fun resumeInterrupted(
        condition: AgentEvalCondition = AgentEvalCondition.PROCESS_DEATH,
        reason: String = "Agent Lab trial was interrupted and resumed"
    ): Int = resumeIncomplete(
        campaignIds = store.list()
            .filter { it.status == AgentLabCampaignStatus.RUNNING }
            .map(AgentLabCampaign::id),
        condition = condition,
        reason = reason
    )

    fun resumeIncomplete(
        campaignIds: Collection<String>,
        condition: AgentEvalCondition = AgentEvalCondition.PROCESS_DEATH,
        reason: String = "Agent Lab campaign was incomplete and resumed"
    ): Int {
        var resumed = 0
        campaignIds.map(String::trim).filter(String::isNotBlank).distinct().forEach { campaignId ->
            if (recoverAndStart(campaignId, condition, reason, replaceActive = false)) resumed += 1
        }
        return resumed
    }

    fun resumeTrialsMissingBenchmarkResults(
        campaignId: String,
        trialIds: Set<String>,
        condition: AgentEvalCondition = AgentEvalCondition.PROCESS_DEATH,
        reason: String = "Agent Lab trial had no durable benchmark result"
    ): Boolean = synchronized(this) {
        val cleanCampaignId = campaignId.trim()
        val cleanTrialIds = trialIds.map(String::trim).filter(String::isNotBlank).toSet()
        if (cleanCampaignId.isBlank() || cleanTrialIds.isEmpty()) return@synchronized false
        if (store.isCancellationRequested(cleanCampaignId)) return@synchronized false
        if (running[cleanCampaignId]?.isActive == true) return@synchronized false
        val campaign = store.get(cleanCampaignId) ?: return@synchronized false
        val selected = campaign.trials.filter { it.id in cleanTrialIds }
        if (selected.isEmpty()) return@synchronized false
        selected.filter { it.runId.isNotBlank() }.forEach { trial ->
            AgentEvalOpsService.observeRunInterrupted(
                appContext,
                trial.runId,
                condition,
                reason
            )
        }
        val reset = store.resetTrialsMissingBenchmarkResults(
            cleanCampaignId,
            cleanTrialIds,
            condition
        ) ?: return@synchronized false
        startPrepared(reset)
    }

    @Synchronized
    private fun recoverAndStart(
        campaignId: String,
        condition: AgentEvalCondition,
        reason: String,
        replaceActive: Boolean
    ): Boolean {
        if (store.isCancellationRequested(campaignId)) return false
        val active = running[campaignId]?.takeIf { it.isActive }
        if (active != null && !replaceActive) return false
        if (active != null) {
            running.remove(campaignId, active)
            active.cancel(CancellationException(reason))
        }
        val campaign = store.get(campaignId) ?: return false
        if (campaign.status in TERMINAL_CAMPAIGN_STATES) return false
        val interrupted = campaign.trials.filter {
            it.status !in TERMINAL_TRIAL_STATES && it.runId.isNotBlank()
        }
        store.resetIncompleteTrials(campaign.id, condition)
        interrupted.forEach { trial ->
            AgentEvalOpsService.observeRunInterrupted(
                appContext,
                trial.runId,
                condition,
                reason
            )
        }
        return start(campaign.id)
    }

    private fun recoverStalledCampaigns(nowMillis: Long = System.currentTimeMillis()) {
        store.list().forEach { campaign ->
            val hasActiveJob = running[campaign.id]?.isActive == true
            if (AgentLabStallRecoveryPolicy.shouldRecover(
                    campaign = campaign,
                    hasActiveJob = hasActiveJob,
                    nowMillis = nowMillis,
                    staleAfterMillis = STALE_CAMPAIGN_MILLIS
                )
            ) {
                recoverAndStart(
                    campaign.id,
                    AgentEvalCondition.PROCESS_DEATH,
                    "Agent Lab campaign made no progress before its watchdog deadline",
                    replaceActive = hasActiveJob
                )
            }
        }
    }

    fun cancel(campaignId: String): Boolean = cancel(listOf(campaignId)) > 0

    @Synchronized
    fun cancel(campaignIds: Collection<String>): Int {
        val cleanIds = campaignIds.map(String::trim).filter(String::isNotBlank).distinct()
        store.requestCancellation(cleanIds)
        val cancelled = linkedSetOf<String>()
        cleanIds.forEach { campaignId ->
            running.remove(campaignId)?.let { job ->
                job.cancel(CancellationException("Agent Lab campaign cancelled"))
                cancelled += campaignId
            }
        }
        cancelled += store.cancelBatch(cleanIds).map(AgentLabCampaign::id)
        return cancelled.size
    }

    private suspend fun runCampaign(campaignId: String) {
        if (store.isCancellationRequested(campaignId)) return
        val campaign = store.get(campaignId) ?: return
        val pendingTrials = campaign.trials.filter { it.status == AgentLabTrialStatus.PENDING }
        if (benchmarkCase(campaign.task)?.dimension == AgentBenchmarkDimension.RECOVERY) {
            pendingTrials.forEach { trial ->
                trialPermits.withPermit {
                    if (!store.isCancellationRequested(campaignId)) runTrial(campaign, trial)
                }
            }
            return
        }
        coroutineScope {
            pendingTrials.map { trial ->
                async {
                    trialPermits.withPermit {
                        if (!store.isCancellationRequested(campaignId)) runTrial(campaign, trial)
                    }
                }
            }.awaitAll()
        }
    }

    private suspend fun runTrial(campaign: AgentLabCampaign, trial: AgentLabTrial) {
        currentCoroutineContext().ensureActive()
        if (store.isCancellationRequested(campaign.id)) return
        val registration = availableAgents().firstOrNull { it.agentId == trial.agentId }
        if (registration == null) {
            store.markTrialFailed(campaign.id, trial.id)
            return
        }
        val conversationId = "agent-lab:${campaign.id}"
        val recorded = recorder.begin(
            conversationId = conversationId,
            request = campaign.task,
            forceNewThread = true
        )
        AgentEvalOpsService.observeRunStarted(appContext, recorded, trial.recoveryCondition)
        val bound = store.bindRun(campaign.id, trial.id, recorded.runId) ?: return
        if (bound.status == AgentLabCampaignStatus.CANCELLED || store.isCancellationRequested(campaign.id)) return
        val taskId = "${campaign.id}:${trial.id}"
        appendEvent(recorded, taskId, registration, AgentRunControlEventType.RUN_CREATED)
        appendEvent(recorded, taskId, registration, AgentRunControlEventType.RUN_STARTED)
        val request = AgentRunRequest(
            conversationId = conversationId,
            messageId = trial.id,
            taskId = taskId,
            runId = recorded.runId,
            goal = campaign.task,
            requiredCapabilities = emptySet(),
            context = mapOf(
                "managed_team" to true,
                "agent_lab_campaign_id" to campaign.id,
                "agent_lab_trial_id" to trial.id,
                "outcome_contract_id" to campaign.outcomeContract.id,
                "recovery_condition" to trial.recoveryCondition.wireValue,
                "previous_run_id" to trial.previousRunId
            ),
            idempotencyKey = AgentLabRunIdentity.idempotencyKey(campaign.id, trial)
        )
        val member = AgentTeamMember(
            agentId = registration.agentId,
            instanceId = trial.id,
            deliveryMode = AgentDeliveryMode.RESPOND,
            role = "blind evaluation candidate",
            objective = campaign.task
        )
        val benchmarkCase = benchmarkCase(campaign.task)
        val execution = when (benchmarkCase?.dimension) {
            AgentBenchmarkDimension.PLANNING_AND_TOOLS,
            AgentBenchmarkDimension.ANDROID_WORLD ->
                executeEvidenceHarness(campaign, trial, recorded, registration, member, request, benchmarkCase)
            AgentBenchmarkDimension.MULTI_AGENT ->
                executeMultiAgentHarness(campaign, trial, recorded, registration, request, benchmarkCase)
            AgentBenchmarkDimension.RECOVERY ->
                recoveryTrialMutex.withLock {
                    executeRecoveryHarness(campaign, trial, recorded, registration, member, request, benchmarkCase)
                }
            AgentBenchmarkDimension.IMMEDIATE_MEMORY,
            AgentBenchmarkDimension.LONG_TERM_MEMORY ->
                executeMemoryHarness(campaign, trial, recorded, registration, member, request, benchmarkCase)
            else -> executeDirectRound(campaign, trial, registration, member, request)
        }
        currentCoroutineContext().ensureActive()
        if (store.isCancellationRequested(campaign.id)) return
        val output = execution.output
        val success = execution.success
        val finalJson = JSONObject()
            .put("text", output)
            .put("reported_cost_micros", execution.reportedCostMicros)
            .put("agent_lab_campaign_id", campaign.id)
            .put("agent_lab_trial_id", trial.id)
            .put("blind_alias", trial.blindAlias)
            .put("error", execution.errorMessage)
            .put("failure_code", execution.failureCode)
            .toString()
        val completed = recorder.complete(
            runId = recorded.runId,
            planJson = execution.planJson,
            toolCalls = execution.toolCalls,
            sourcesJson = execution.sourcesJson,
            finalOutputJson = finalJson,
            renderSpecJson = execution.richOutputJson,
            artifacts = emptyList(),
            success = success,
            executionResourceId = registration.agentId
        )
        if (completed != null) {
            appendEvent(
                completed,
                taskId,
                registration,
                if (success) AgentRunControlEventType.RUN_COMPLETED else AgentRunControlEventType.RUN_FAILED,
                mapOf("result" to output, "error" to execution.errorMessage)
            )
            AgentEvalOpsService.observeRunCompleted(appContext, completed)
        } else {
            store.markTrialFailed(campaign.id, trial.id)
        }
    }

    private suspend fun executeDirectRound(
        campaign: AgentLabCampaign,
        trial: AgentLabTrial,
        registration: AgentRegistration,
        member: AgentTeamMember,
        request: AgentRunRequest
    ): AgentLabExecutionResult {
        val round = executeAgentRound(campaign, trial, registration, member, request, "answer")
        return AgentLabExecutionResult(
            output = round.output,
            success = round.success,
            failureCode = round.failureCode,
            errorMessage = round.errorMessage,
            reportedCostMicros = round.reportedCostMicros,
            planJson = JSONArray().put(JSONObject()
                .put("agent", registration.agentId)
                .put("blind_alias", trial.blindAlias)
                .put("outcome_contract_id", campaign.outcomeContract.id)
                .put("recovery_condition", trial.recoveryCondition.wireValue)
                .put("previous_run_id", trial.previousRunId)).toString(),
            sourcesJson = round.richOutputJson.takeIf { it.trim().startsWith("[") } ?: "[]",
            richOutputJson = round.richOutputJson.takeIf { it.trim().startsWith("{") } ?: "{}"
        )
    }

    private suspend fun executeRecoveryHarness(
        campaign: AgentLabCampaign,
        trial: AgentLabTrial,
        recorded: AgentRecordedRun,
        registration: AgentRegistration,
        member: AgentTeamMember,
        request: AgentRunRequest,
        case: AgentBenchmarkCase
    ): AgentLabExecutionResult {
        val condition = case.expectation.requiredCondition
        val controller = AgentEvalFaultControllerStore(appContext)
        val previousRequest = controller.requestForTrial(case.id, trial.id, condition)
        val faultRequest = previousRequest ?: controller.request(case.id, trial.id, recorded.runId, condition)
            ?: return AgentLabExecutionResult(
                output = "",
                success = false,
                failureCode = "fault_controller_unavailable",
                errorMessage = "A live external fault controller lease is required",
                reportedCostMicros = 0L,
                planJson = "[]"
            )

        appendEvent(recorded, request.taskId, registration, AgentRunControlEventType.STEP_STARTED, mapOf(
            "step" to "await_external_fault",
            "condition" to condition.wireValue,
            "controller_nonce" to faultRequest.nonce
        ))

        val proof = withTimeoutOrNull(FAULT_INJECTION_TIMEOUT_MILLIS) {
            while (true) {
                store.touch(campaign.id)
                val receipt = controller.verifiedReceipt(faultRequest)
                if (receipt != null) return@withTimeoutOrNull receipt
                delay(FAULT_POLL_INTERVAL_MILLIS)
            }
            @Suppress("UNREACHABLE_CODE")
            null
        }
        if (proof == null) {
            return AgentLabExecutionResult(
                output = "",
                success = false,
                failureCode = "fault_evidence_missing",
                errorMessage = "The requested ${condition.wireValue} fault was not observed with a matching receipt",
                reportedCostMicros = 0L,
                planJson = JSONArray().put(JSONObject()
                    .put("step", "await_external_fault")
                    .put("condition", condition.wireValue)
                    .put("nonce", faultRequest.nonce)).toString()
            )
        }

        appendEvent(recorded, request.taskId, registration, AgentRunControlEventType.RETRYING, mapOf(
            "condition" to condition.wireValue,
            "reason" to "External fault controller completed the requested fault",
            "controller_id" to proof.controllerId,
            "controller_nonce" to proof.nonce,
            "injected_at_millis" to proof.injectedAtMillis
        ))
        appendEvent(recorded, request.taskId, registration, AgentRunControlEventType.RUN_RECOVERED, mapOf(
            "condition" to condition.wireValue,
            "previous_run_id" to trial.previousRunId,
            "controller_id" to proof.controllerId,
            "controller_nonce" to proof.nonce,
            "injected_at_millis" to proof.injectedAtMillis
        ))
        appendEvent(recorded, request.taskId, registration, AgentRunControlEventType.STEP_COMPLETED, mapOf(
            "step" to "await_external_fault",
            "condition" to condition.wireValue,
            "status" to "succeeded"
        ))
        controller.markCompleted(faultRequest, recorded.runId)
        if (condition == AgentEvalCondition.NETWORK_LOSS) {
            delay(NETWORK_RECOVERY_SETTLE_MILLIS)
        }
        val recoveredRequest = request.copy(
            goal = buildString {
                append(case.prompt)
                append("\n真实故障已由控制器注入并由 Android 事件确认：")
                append(condition.wireValue)
                append("。现在完成原任务；不要声称未发生故障。")
            },
            context = request.context + mapOf(
                "verified_recovery_condition" to condition.wireValue,
                "fault_controller_receipt" to proof.nonce
            )
        )
        return executeDirectRound(campaign, trial, registration, member, recoveredRequest)
    }

    private suspend fun executeMemoryHarness(
        campaign: AgentLabCampaign,
        trial: AgentLabTrial,
        recorded: AgentRecordedRun,
        registration: AgentRegistration,
        member: AgentTeamMember,
        request: AgentRunRequest,
        case: AgentBenchmarkCase
    ): AgentLabExecutionResult {
        val baseContext = AgentConversationContext(
            conversationId = recorded.conversationId,
            summary = "",
            turns = listOf(AgentTranscriptEntry(
                id = "memory-eval:${recorded.runId}",
                role = AgentTranscriptRole.USER,
                text = recorded.originalRequest,
                timestampMillis = recorded.createdAtMillis,
                conversationId = recorded.conversationId,
                turnId = recorded.taskThreadId,
                taskId = request.taskId
            )),
            privateMode = false
        )
        val globalRuntime = GlobalSuperAgentRuntime.get(appContext)
        val memoryContext = if (case.dimension == AgentBenchmarkDimension.IMMEDIATE_MEMORY) {
            globalRuntime.augmentImmediateMemoryContext(baseContext, recorded.originalRequest)
        } else {
            globalRuntime.augmentContext(baseContext, recorded.originalRequest)
        }.globalContext
        if (memoryContext.isBlank()) {
            return AgentLabExecutionResult(
                output = "",
                success = false,
                failureCode = "memory_context_unavailable",
                errorMessage = "Production memory retrieval returned no attributable context",
                reportedCostMicros = 0L,
                planJson = "[]"
            )
        }
        val round = executeAgentRound(
            campaign = campaign,
            trial = trial,
            registration = registration,
            member = member,
            request = request.copy(
                goal = buildString {
                    append(case.prompt)
                    append("\n\n")
                    append(memoryContext)
                    append("\n\nUse only relevant memory evidence above. Do not invent a missing value.")
                },
                context = request.context + mapOf("memory_context_compiled" to "true")
            ),
            phase = "memory_answer"
        )
        return AgentLabExecutionResult(
            output = round.output,
            success = round.success,
            failureCode = round.failureCode,
            errorMessage = round.errorMessage,
            reportedCostMicros = round.reportedCostMicros,
            planJson = JSONArray().put(JSONObject()
                .put("step", "retrieve_memory")
                .put("production_prompt_compiler", true)
                .put("memory_horizon_days", case.expectation.memoryHorizonDays)).toString(),
            richOutputJson = round.richOutputJson.takeIf { it.trim().startsWith("{") } ?: "{}"
        )
    }

    private suspend fun executeEvidenceHarness(
        campaign: AgentLabCampaign,
        trial: AgentLabTrial,
        recorded: AgentRecordedRun,
        registration: AgentRegistration,
        member: AgentTeamMember,
        request: AgentRunRequest,
        case: AgentBenchmarkCase
    ): AgentLabExecutionResult {
        val plannedTools = AgentBenchmarkHarnessProtocol.toolsFor(case, trial.id)
        val planningRequest = request.forHarnessRound(
            recorded.runId,
            "plan",
            AgentBenchmarkHarnessProtocol.planningPrompt(case, plannedTools),
            case.taggedPrompt
        )
        val planning = executeAgentRound(campaign, trial, registration, member, planningRequest, "plan")
        store.touch(campaign.id)
        val planJson = AgentBenchmarkHarnessProtocol.planJson(planning.output)
        appendEvent(recorded, request.taskId, registration, AgentRunControlEventType.PLANNING, mapOf(
            "source" to "model",
            "plan" to planJson,
            "round_run_id" to planningRequest.runId
        ))
        val receipts = if (case.dimension == AgentBenchmarkDimension.ANDROID_WORLD) {
            listOf(executeAndroidWorldObservation(recorded, request.taskId, registration, case))
        } else {
            plannedTools.mapIndexed { index, tool ->
                executeNativeTool(recorded, request.taskId, registration, campaign, trial, tool, index).also {
                    store.touch(campaign.id)
                }
            }
        }
        val finalRequest = request.forHarnessRound(
            recorded.runId,
            "final",
            AgentBenchmarkHarnessProtocol.finalPrompt(case, planJson, receipts),
            case.taggedPrompt
        )
        val final = executeAgentRound(campaign, trial, registration, member, finalRequest, "final")
        store.touch(campaign.id)
        val transportSuccess = planning.success && final.success
        val failureCode = when {
            !planning.success -> "planner_${planning.failureCode.ifBlank { "failed" }}"
            !final.success -> "synthesis_${final.failureCode.ifBlank { "failed" }}"
            else -> ""
        }
        return AgentLabExecutionResult(
            output = final.output,
            success = transportSuccess,
            failureCode = failureCode,
            errorMessage = listOf(planning.errorMessage, final.errorMessage).filter(String::isNotBlank)
                .joinToString("; "),
            reportedCostMicros = planning.reportedCostMicros + final.reportedCostMicros,
            planJson = planJson,
            toolCalls = receipts,
            sourcesJson = sourceEvidence(receipts),
            richOutputJson = final.richOutputJson.takeIf { it.trim().startsWith("{") } ?: "{}"
        )
    }

    private suspend fun executeMultiAgentHarness(
        campaign: AgentLabCampaign,
        trial: AgentLabTrial,
        recorded: AgentRecordedRun,
        primary: AgentRegistration,
        request: AgentRunRequest,
        case: AgentBenchmarkCase
    ): AgentLabExecutionResult = coroutineScope {
        val collaborator = availableAgents().firstOrNull { candidate ->
            candidate.agentId != primary.agentId && sequenceOf(
                candidate.agentId,
                candidate.displayName,
                candidate.providerId,
                candidate.providerProfile?.modelId.orEmpty()
            ).any { value ->
                if (primary.matchesAgentFamily("codex")) {
                    value.contains("deepseek", ignoreCase = true)
                } else {
                    value.contains("codex", ignoreCase = true)
                }
            }
        } ?: return@coroutineScope AgentLabExecutionResult(
            output = "",
            success = false,
            failureCode = "multi_agent_member_unavailable",
            errorMessage = "A distinct Codex/DeepSeek collaborator is unavailable",
            reportedCostMicros = 0L,
            planJson = "[]"
        )
        val reviewerId = "reviewer-${trial.id}"
        val primaryId = "primary-${trial.id}"
        val members = listOf(
            AgentTeamMember(
                agentId = collaborator.agentId,
                instanceId = reviewerId,
                deliveryMode = AgentDeliveryMode.OBSERVE,
                role = "independent reviewer",
                objective = "独立分析以下任务，重点寻找错误、反例和风险，给主执行 Agent 可核查的审查证据：${case.prompt}"
            ),
            AgentTeamMember(
                agentId = primary.agentId,
                instanceId = primaryId,
                deliveryMode = AgentDeliveryMode.RESPOND,
                role = "primary implementer and synthesizer",
                objective = "先独立完成任务，再综合审查 Agent 的证据，只输出一份有明确结论的最终回答：${case.prompt}"
            )
        )
        val definition = AgentTeamDefinition(
            teamId = "benchmark-${campaign.id}-${trial.id}",
            primaryAgentId = primary.agentId,
            primaryInstanceId = primaryId,
            members = members,
            visibilityMode = AgentTeamVisibilityMode.BACKGROUND
        )
        val teamStore = EncryptedAgentTeamExecutionStore(appContext)
        val heartbeat = launch {
            while (isActive) {
                delay(TEAM_HEARTBEAT_MILLIS)
                store.touch(campaign.id)
            }
        }
        val outcome = runCatching {
            AgentTeamExecutionRuntime(
                store = teamStore,
                limits = AgentSubagentLimits(maxChildren = 2, maxConcurrency = 2)
            ).use { teamRuntime ->
                teamRuntime.start(definition, request, worker).await()
            }
        }
        heartbeat.cancel()
        store.touch(campaign.id)
        val result = outcome.getOrNull()
        val registrations = mapOf(primary.agentId to primary, collaborator.agentId to collaborator)
        result?.snapshot?.members.orEmpty().forEach { memberSnapshot ->
            val memberRegistration = registrations[memberSnapshot.agentId] ?: return@forEach
            appendEvent(recorded, request.taskId, memberRegistration, AgentRunControlEventType.AGENT_CONNECTED, mapOf(
                "instance_id" to memberSnapshot.memberId,
                "role" to memberSnapshot.role,
                "status" to memberSnapshot.status.name.lowercase()
            ))
            appendEvent(recorded, request.taskId, memberRegistration, AgentRunControlEventType.STEP_COMPLETED, mapOf(
                "instance_id" to memberSnapshot.memberId,
                "status" to memberSnapshot.status.name.lowercase(),
                "output_sha256" to AgentNativeJsonCodec.sha256(memberSnapshot.output)
            ))
        }
        val primarySnapshot = result?.snapshot?.members?.firstOrNull { it.memberId == primaryId }
        result?.snapshot?.members.orEmpty()
            .filter { it.deliveryMode == AgentDeliveryMode.OBSERVE && it.status.isTerminal }
            .forEach { reviewer ->
                registrations[reviewer.agentId]?.let { reviewerRegistration ->
                    appendEvent(recorded, request.taskId, reviewerRegistration, AgentRunControlEventType.HANDOFF, mapOf(
                        "from_instance_id" to reviewer.memberId,
                        "to_instance_id" to primaryId,
                        "status" to reviewer.status.name.lowercase(),
                        "evidence_sha256" to AgentNativeJsonCodec.sha256(reviewer.output)
                    ))
                }
            }
        val planJson = JSONArray().apply {
            result?.snapshot?.members.orEmpty().forEach { memberSnapshot ->
                put(JSONObject()
                    .put("step", memberSnapshot.role)
                    .put("agent", memberSnapshot.agentId)
                    .put("instance_id", memberSnapshot.memberId)
                    .put("status", memberSnapshot.status.name.lowercase()))
            }
        }.toString()
        val memberErrors = result?.snapshot?.members.orEmpty().map(AgentTeamMemberSnapshot::errorMessage)
            .filter(String::isNotBlank)
        val success = outcome.isSuccess &&
            result?.subagentResult?.status == AgentSubagentRunStatus.SUCCEEDED &&
            !result.finalOutput.isNullOrBlank()
        val reportedCost = members.sumOf { member ->
            provider.result(member.agentId, stableAgentTeamMemberRunId(recorded.runId, member.memberId))
                ?.metadata?.get("cost_micros")?.toLongOrNull() ?: 0L
        }
        val primaryRichOutput = primarySnapshot?.let { snapshot ->
            provider.result(primary.agentId, stableAgentTeamMemberRunId(recorded.runId, snapshot.memberId))
                ?.metadata?.get("rich_output")
        }.orEmpty()
        AgentLabExecutionResult(
            output = result?.finalOutput.orEmpty(),
            success = success,
            failureCode = when {
                outcome.isFailure -> "multi_agent_runtime_failure"
                result?.subagentResult?.status != AgentSubagentRunStatus.SUCCEEDED -> "multi_agent_member_failure"
                result?.finalOutput.isNullOrBlank() -> "empty_response"
                else -> ""
            },
            errorMessage = (listOfNotNull(outcome.exceptionOrNull()?.message) + memberErrors).joinToString("; "),
            reportedCostMicros = reportedCost,
            planJson = planJson,
            richOutputJson = primaryRichOutput.takeIf { it.trim().startsWith("{") } ?: "{}"
        )
    }

    private suspend fun executeAgentRound(
        campaign: AgentLabCampaign,
        trial: AgentLabTrial,
        registration: AgentRegistration,
        member: AgentTeamMember,
        request: AgentRunRequest,
        phase: String
    ): AgentLabRoundResult {
        val result = runCatching {
            worker.execute(AgentTeamMemberExecutionContext(
                member = member.copy(objective = request.goal),
                request = request,
                handoff = AgentSubagentContextHandoff("", emptyList(), 0, 0, false),
                depth = 1,
                provenance = AgentSubagentProvenance(
                    source = "agent_lab_$phase",
                    sourceId = campaign.id,
                    traceId = trial.id
                )
            ))
        }
        val dispatch = provider.result(registration.agentId, request.runId)
        val output = result.getOrNull()?.content.orEmpty().ifBlank {
            dispatch?.takeIf(AgentActionResult::success)?.message.orEmpty()
        }
        return AgentLabRoundResult(
            output = output,
            success = result.isSuccess && output.isNotBlank(),
            failureCode = AgentLabRunFailurePolicy.code(result.exceptionOrNull(), dispatch, output),
            errorMessage = result.exceptionOrNull()?.message.orEmpty(),
            reportedCostMicros = dispatch?.metadata?.get("cost_micros")?.toLongOrNull() ?: 0L,
            richOutputJson = dispatch?.metadata?.get("rich_output").orEmpty()
        )
    }

    private fun executeNativeTool(
        recorded: AgentRecordedRun,
        taskId: String,
        registration: AgentRegistration,
        campaign: AgentLabCampaign,
        trial: AgentLabTrial,
        planned: AgentBenchmarkPlannedTool,
        index: Int
    ): AgentToolCallRecord {
        val definition = nativeTools.lookup(planned.id)
        val startedAt = System.currentTimeMillis()
        appendEvent(recorded, taskId, registration, AgentRunControlEventType.STEP_STARTED, mapOf(
            "step" to index + 1,
            "tool_id" to planned.id
        ))
        appendEvent(recorded, taskId, registration, AgentRunControlEventType.TOOL_STARTED, mapOf(
            "tool_id" to planned.id,
            "step" to index + 1
        ))
        val result = if (definition == null) {
            null
        } else if (!benchmarkAllows(definition.descriptor)) {
            null
        } else {
            val descriptor = definition.descriptor
            nativeTools.invoke(
                id = planned.id,
                input = planned.input,
                context = AgentNativeToolInvocationContext(
                    sessionId = campaign.id,
                    conversationId = recorded.conversationId,
                    turnId = trial.id,
                    callerId = "galaxyssi.agent_benchmark",
                    idempotencyKey = "${recorded.runId}:tool:$index:${AgentNativeJsonCodec.sha256(planned.input)}",
                    grantedPermissions = descriptor.requiredPermissions.mapTo(linkedSetOf()) { it.id },
                    grantedConsents = descriptor.requiredConsents.mapTo(linkedSetOf()) { it.id },
                    attributes = mapOf(
                        "benchmark_case" to campaign.task.substringAfter("[evalops:").substringBefore(']'),
                        "user_confirmed" to "true"
                    )
                )
            )
        }
        val status = when (result?.status) {
            AgentNativeToolResultStatus.SUCCEEDED -> AgentToolCallStatus.SUCCEEDED
            AgentNativeToolResultStatus.CANCELLED -> AgentToolCallStatus.CANCELLED
            else -> AgentToolCallStatus.FAILED
        }
        val error = when {
            definition == null -> "unknown_tool"
            !benchmarkAllows(definition.descriptor) -> "benchmark_blocks_tool_risk"
            result?.error != null -> "${result.error.code}: ${result.error.message}"
            result == null -> "tool_not_executed"
            !result.isSuccess -> result.status.wireValue
            else -> ""
        }
        val record = AgentToolCallRecord(
            id = result?.receipt?.invocationId ?: UUID.randomUUID().toString(),
            toolName = planned.id,
            status = status,
            argumentsJson = AgentNativeJsonCodec.stringify(planned.input),
            resultJson = result?.let(::boundedToolResult).orEmpty(),
            errorMessage = error,
            startedAtMillis = result?.receipt?.startedAtEpochMillis ?: startedAt,
            completedAtMillis = result?.receipt?.finishedAtEpochMillis ?: System.currentTimeMillis()
        )
        appendEvent(recorded, taskId, registration, AgentRunControlEventType.TOOL_COMPLETED, mapOf(
            "tool_id" to planned.id,
            "status" to if (record.status == AgentToolCallStatus.SUCCEEDED) "succeeded" else "failed",
            "receipt_id" to record.id,
            "error" to record.errorMessage
        ))
        appendEvent(recorded, taskId, registration, AgentRunControlEventType.STEP_COMPLETED, mapOf(
            "step" to index + 1,
            "tool_id" to planned.id,
            "status" to record.status.name.lowercase()
        ))
        return record
    }

    private fun executeAndroidWorldObservation(
        recorded: AgentRecordedRun,
        taskId: String,
        registration: AgentRegistration,
        case: AgentBenchmarkCase
    ): AgentToolCallRecord {
        val toolId = "galaxyssi.androidworld.observe.${case.id}"
        appendEvent(recorded, taskId, registration, AgentRunControlEventType.STEP_STARTED, mapOf("tool_id" to toolId))
        appendEvent(recorded, taskId, registration, AgentRunControlEventType.TOOL_STARTED, mapOf("tool_id" to toolId))
        val result = AgentAndroidWorldBridge(appContext).evaluateMatching(recorded)
        val receipt = result?.let(AgentBenchmarkHarnessProtocol::androidWorldReceipt) ?: AgentToolCallRecord(
            id = UUID.randomUUID().toString(),
            toolName = toolId,
            status = AgentToolCallStatus.FAILED,
            argumentsJson = JSONObject().put("task_id", case.id).toString(),
            errorMessage = "android_world_task_not_found",
            startedAtMillis = System.currentTimeMillis(),
            completedAtMillis = System.currentTimeMillis()
        )
        appendEvent(recorded, taskId, registration, AgentRunControlEventType.TOOL_COMPLETED, mapOf(
            "tool_id" to toolId,
            "status" to if (receipt.status == AgentToolCallStatus.SUCCEEDED) "succeeded" else "failed",
            "receipt_id" to receipt.id,
            "error" to receipt.errorMessage
        ))
        appendEvent(recorded, taskId, registration, AgentRunControlEventType.STEP_COMPLETED, mapOf(
            "tool_id" to toolId,
            "status" to receipt.status.name.lowercase()
        ))
        return receipt
    }

    private fun sourceEvidence(receipts: List<AgentToolCallRecord>): String = JSONArray().apply {
        receipts.forEach { receipt ->
            AgentBenchmarkHarnessProtocol.verifiedSources(receipt).forEach(::put)
        }
    }.toString()

    private fun boundedToolResult(result: AgentNativeToolResult): String {
        val raw = result.toJson()
        if (raw.length <= MAX_STORED_TOOL_RESULT_CHARS) return raw
        return AgentBenchmarkHarnessProtocol.boundedToolResult(
            result.provenance.toolId,
            raw,
            MAX_STORED_TOOL_RESULT_CHARS
        )
    }

    private fun benchmarkAllows(descriptor: AgentNativeToolDescriptor): Boolean =
        descriptor.risk == AgentNativeToolRisk.LOW ||
            (descriptor.risk == AgentNativeToolRisk.MEDIUM && descriptor.id in BENCHMARK_ALLOWED_MEDIUM_TOOLS)

    private fun AgentRunRequest.forHarnessRound(
        parentRunId: String,
        phase: String,
        prompt: String,
        executionPolicyPrompt: String
    ): AgentRunRequest {
        val roundRunId = UUID.nameUUIDFromBytes("$parentRunId:$phase".toByteArray()).toString()
        return copy(
            messageId = "$messageId:$phase",
            runId = roundRunId,
            parentRunId = parentRunId,
            goal = prompt,
            context = context + mapOf(
                "benchmark_harness_phase" to phase,
                "parent_run_id" to parentRunId,
                EXECUTION_POLICY_PROMPT_ACTION_PARAMETER to executionPolicyPrompt
            ),
            idempotencyKey = "$idempotencyKey:$phase"
        )
    }

    private fun benchmarkCase(task: String): AgentBenchmarkCase? {
        val id = task.substringAfter("[evalops:", "").substringBefore(']').trim()
        return id.takeIf(String::isNotBlank)?.let(AgentEvalBenchmarkCatalog.standard::case)
    }

    private fun AgentRegistration.matchesAgentFamily(name: String): Boolean = sequenceOf(
        agentId,
        displayName,
        providerId,
        providerProfile?.modelId.orEmpty(),
        providerProfile?.productId.orEmpty()
    ).any { it.contains(name, ignoreCase = true) }

    private fun appendEvent(
        run: AgentRecordedRun,
        taskId: String,
        registration: AgentRegistration,
        type: AgentRunControlEventType,
        payload: AgentNativeJsonObject = emptyMap()
    ) {
        runEvents.appendNext(AgentRunControlEvent(
            conversationId = run.conversationId,
            messageId = run.runId,
            taskId = taskId,
            runId = run.runId,
            agentId = registration.agentId,
            deviceId = registration.deviceId,
            type = type,
            sequence = 0L,
            payload = payload
        ))
    }

    override fun close() {
        running.clear()
        scope.cancel()
    }

    private companion object {
        const val AGENT_SNAPSHOT_TTL_MILLIS = 30_000L
        const val DEFAULT_PARALLEL_TRIALS = 3
        const val MAX_PARALLEL_TRIALS = 10
        const val EVAL_TRIAL_LIVENESS_PROBE_MILLIS = 6L * 60L * 1_000L
        const val STALE_CAMPAIGN_MILLIS = 8L * 60L * 1_000L
        const val WATCHDOG_INTERVAL_MILLIS = 60_000L
        const val RESTART_AFTER_EXIT_MILLIS = 1_000L
        const val TEAM_HEARTBEAT_MILLIS = 60_000L
        const val FAULT_INJECTION_TIMEOUT_MILLIS = 4L * 60L * 1_000L
        const val FAULT_POLL_INTERVAL_MILLIS = 500L
        const val NETWORK_RECOVERY_SETTLE_MILLIS = 4_000L
        const val MAX_STORED_TOOL_RESULT_CHARS = 48_000
        val BENCHMARK_ALLOWED_MEDIUM_TOOLS = setOf(
            AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT
        )
        val TERMINAL_CAMPAIGN_STATES = setOf(
            AgentLabCampaignStatus.READY_FOR_REVIEW,
            AgentLabCampaignStatus.COMPLETED,
            AgentLabCampaignStatus.CANCELLED
        )
        val TERMINAL_TRIAL_STATES = setOf(
            AgentLabTrialStatus.COMPLETED,
            AgentLabTrialStatus.FAILED,
            AgentLabTrialStatus.CANCELLED
        )
    }
}

private data class AgentLabRoundResult(
    val output: String,
    val success: Boolean,
    val failureCode: String,
    val errorMessage: String,
    val reportedCostMicros: Long,
    val richOutputJson: String
)

private data class AgentLabExecutionResult(
    val output: String,
    val success: Boolean,
    val failureCode: String,
    val errorMessage: String,
    val reportedCostMicros: Long,
    val planJson: String,
    val toolCalls: List<AgentToolCallRecord> = emptyList(),
    val sourcesJson: String = "[]",
    val richOutputJson: String = "{}"
)

internal object AgentLabAgentSelectionPolicy {
    fun independentAgents(registrations: List<AgentRegistration>): List<AgentRegistration> = registrations
        .distinctBy(AgentRegistration::agentId)
        .groupBy(AgentRegistration::runtimeHealthScope)
        .values
        .map { aliases ->
            aliases.maxWithOrNull(compareBy<AgentRegistration>(
                { it.agentId.contains(':') },
                { it.displayName.contains('\u00b7') },
                { it.updatedAtMillis }
            )) ?: aliases.first()
        }
        .sortedBy(AgentRegistration::displayName)
}

internal object AgentLabRunFailurePolicy {
    fun code(error: Throwable?, dispatch: AgentActionResult?, output: String): String = when {
        error is kotlinx.coroutines.TimeoutCancellationException -> "response_timeout"
        error is CancellationException -> "cancelled"
        error != null -> "worker_failure"
        dispatch?.success == false -> "dispatch_failed"
        output.isBlank() -> "empty_response"
        else -> ""
    }
}

object AgentEvolutionLabRuntimeRegistry {
    private val runtimes = ConcurrentHashMap<String, AgentEvolutionLabRuntime>()

    fun get(context: Context): AgentEvolutionLabRuntime {
        val key = context.applicationContext.packageName
        return runtimes.computeIfAbsent(key) { AgentEvolutionLabRuntime(context.applicationContext) }
    }
}
