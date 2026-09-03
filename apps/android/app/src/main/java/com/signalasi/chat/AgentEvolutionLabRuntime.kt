package com.signalasi.chat

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
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONArray
import org.json.JSONObject
import java.io.Closeable
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
    private val worker = ActionExecutorAgentTeamMemberWorker(
        provider = provider,
        directory = directory,
        screenProvider = { AndroidScreenPerceptionProvider(appContext).capture() },
        timeoutMillis = EVAL_TRIAL_TIMEOUT_MILLIS
    )
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO + CoroutineName("AgentEvolutionLab"))
    private val running = ConcurrentHashMap<String, kotlinx.coroutines.Job>()
    private val trialPermits = Semaphore(maximumParallelTrials.coerceIn(1, MAX_PARALLEL_TRIALS))

    init {
        scope.launch(CoroutineName("AgentEvolutionLabWatchdog")) {
            while (isActive) {
                delay(WATCHDOG_INTERVAL_MILLIS)
                recoverStalledCampaigns()
            }
        }
    }

    fun availableAgents(): List<AgentRegistration> = AgentLabAgentSelectionPolicy.independentAgents(
        AppStoreAgentConnectorRegistry(appContext).registrations().filter { registration ->
            registration.kind in setOf(AgentConnectorKind.AGENT, AgentConnectorKind.MODEL) &&
                registration.status in setOf(
                    AgentEndpointStatus.ONLINE,
                    AgentEndpointStatus.IDLE,
                    AgentEndpointStatus.BUSY
                )
        }
    )

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
        if (campaign.status in setOf(AgentLabCampaignStatus.COMPLETED, AgentLabCampaignStatus.CANCELLED)) return false
        if (running[cleanId]?.isActive == true) return false
        val job = scope.launch {
            runCampaign(cleanId)
        }
        running[cleanId] = job
        job.invokeOnCompletion {
            if (running.remove(cleanId, job) && scope.isActive) {
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

    @Synchronized
    private fun recoverAndStart(
        campaignId: String,
        condition: AgentEvalCondition,
        reason: String,
        replaceActive: Boolean
    ): Boolean {
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

    fun cancel(campaignId: String): Boolean {
        val cleanId = campaignId.trim()
        val cancelled = running.remove(cleanId)?.let { job ->
            job.cancel(CancellationException("Agent Lab campaign cancelled"))
            true
        } ?: false
        return store.cancel(cleanId) != null || cancelled
    }

    private suspend fun runCampaign(campaignId: String) {
        val campaign = store.get(campaignId) ?: return
        coroutineScope {
            campaign.trials.filter { it.status == AgentLabTrialStatus.PENDING }.map { trial ->
                async { trialPermits.withPermit { runTrial(campaign, trial) } }
            }.awaitAll()
        }
    }

    private suspend fun runTrial(campaign: AgentLabCampaign, trial: AgentLabTrial) {
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
        store.bindRun(campaign.id, trial.id, recorded.runId)
        val taskId = "${campaign.id}:${trial.id}"
        appendEvent(recorded, taskId, registration, AgentRunControlEventType.RUN_CREATED)
        appendEvent(recorded, taskId, registration, AgentRunControlEventType.RUN_STARTED)
        if (trial.recoveryCondition != AgentEvalCondition.NORMAL && trial.previousRunId.isNotBlank()) {
            appendEvent(
                recorded,
                taskId,
                registration,
                AgentRunControlEventType.RUN_RECOVERED,
                mapOf(
                    "condition" to trial.recoveryCondition.wireValue,
                    "previous_run_id" to trial.previousRunId
                )
            )
        }
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
        val result = runCatching {
            worker.execute(AgentTeamMemberExecutionContext(
                member = member,
                request = request,
                handoff = AgentSubagentContextHandoff("", emptyList(), 0, 0, false),
                depth = 1,
                provenance = AgentSubagentProvenance(
                    source = "agent_lab",
                    sourceId = campaign.id,
                    traceId = trial.id
                )
            ))
        }
        val dispatch = provider.result(registration.agentId, recorded.runId)
        val output = result.getOrNull()?.content.orEmpty().ifBlank {
            dispatch?.takeIf(AgentActionResult::success)?.message.orEmpty()
        }
        val success = result.isSuccess && output.isNotBlank()
        val failureCode = AgentLabRunFailurePolicy.code(result.exceptionOrNull(), dispatch, output)
        val metadata = dispatch?.metadata.orEmpty()
        val finalJson = JSONObject()
            .put("text", output)
            .put("reported_cost_micros", metadata["cost_micros"]?.toLongOrNull() ?: 0L)
            .put("agent_lab_campaign_id", campaign.id)
            .put("agent_lab_trial_id", trial.id)
            .put("blind_alias", trial.blindAlias)
            .put("error", result.exceptionOrNull()?.message.orEmpty())
            .put("failure_code", failureCode)
            .toString()
        val completed = recorder.complete(
            runId = recorded.runId,
            planJson = JSONArray().put(JSONObject()
                .put("agent", registration.agentId)
                .put("blind_alias", trial.blindAlias)
                .put("outcome_contract_id", campaign.outcomeContract.id)
                .put("recovery_condition", trial.recoveryCondition.wireValue)
                .put("previous_run_id", trial.previousRunId)).toString(),
            toolCalls = emptyList(),
            sourcesJson = metadata["rich_output"].orEmpty().ifBlank { "[]" },
            finalOutputJson = finalJson,
            renderSpecJson = metadata["rich_output"].orEmpty().ifBlank { "{}" },
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
                mapOf("result" to output, "error" to result.exceptionOrNull()?.message.orEmpty())
            )
            AgentEvalOpsService.observeRunCompleted(appContext, completed)
        } else {
            store.markTrialFailed(campaign.id, trial.id)
        }
    }

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
        const val DEFAULT_PARALLEL_TRIALS = 3
        const val MAX_PARALLEL_TRIALS = 10
        const val EVAL_TRIAL_TIMEOUT_MILLIS = 6L * 60L * 1_000L
        const val STALE_CAMPAIGN_MILLIS = 8L * 60L * 1_000L
        const val WATCHDOG_INTERVAL_MILLIS = 60_000L
        const val RESTART_AFTER_EXIT_MILLIS = 1_000L
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
