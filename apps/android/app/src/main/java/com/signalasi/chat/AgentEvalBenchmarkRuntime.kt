package com.signalasi.chat

import android.content.Context
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

data class AgentBenchmarkAllocation(
    val resources: List<AgentRegistration>,
    val resourceIdsByCase: Map<String, List<String>>,
    val teamResourceIdsByCase: Map<String, List<String>> = emptyMap()
)

object AgentBenchmarkAllocationPolicy {
    fun codexDeepSeek90To10(
        suite: AgentBenchmarkSuite,
        available: List<AgentRegistration>
    ): AgentBenchmarkAllocation {
        val codex = select(available, "codex")
            ?: error("A currently available Codex Agent is required")
        val deepSeek = select(available, "deepseek")
            ?: error("A currently available DeepSeek model is required")
        require(codex.agentId != deepSeek.agentId) { "Codex and DeepSeek must be different resources" }
        val soloCases = suite.cases.filter { it.dimension != AgentBenchmarkDimension.MULTI_AGENT }
        require(soloCases.isNotEmpty() && soloCases.size % 10 == 0) {
            "The 90/10 profile requires a non-empty Single-Agent case count divisible by ten"
        }
        val assignment = buildMap {
            soloCases.forEachIndexed { index, case ->
                put(case.id, listOf(if ((index + 1) % 10 == 0) deepSeek.agentId else codex.agentId))
            }
            suite.cases.filter { it.dimension == AgentBenchmarkDimension.MULTI_AGENT }.forEach { case ->
                put(case.id, listOf(codex.agentId))
            }
        }
        val codexCount = soloCases.count { codex.agentId in assignment.getValue(it.id) }
        val deepSeekCount = soloCases.count { deepSeek.agentId in assignment.getValue(it.id) }
        require(codexCount * 10 == soloCases.size * 9 && deepSeekCount * 10 == soloCases.size) {
            "Single-Agent benchmark allocation must remain 90% Codex and 10% DeepSeek"
        }
        val teams = suite.cases.filter { it.dimension == AgentBenchmarkDimension.MULTI_AGENT }
            .associate { it.id to listOf(codex.agentId, deepSeek.agentId) }
        return AgentBenchmarkAllocation(listOf(codex, deepSeek), assignment, teams)
    }

    private fun select(available: List<AgentRegistration>, name: String): AgentRegistration? = available
        .filter { registration ->
            sequenceOf(
                registration.agentId,
                registration.displayName,
                registration.providerId,
                registration.providerProfile?.modelId.orEmpty(),
                registration.providerProfile?.productId.orEmpty()
            ).any { it.contains(name, ignoreCase = true) }
        }
        .maxWithOrNull(compareBy<AgentRegistration>({ it.hasCapacity }, { it.updatedAtMillis }))
}

class AgentBenchmarkCoordinator(
    context: Context,
    private val suite: AgentBenchmarkSuite = AgentEvalBenchmarkCatalog.standard
) {
    private val appContext = context.applicationContext
    private val benchmarkStore = AgentBenchmarkStore(appContext)
    private val labStore = AgentLabStore(appContext)
    private val labRuntime = AgentEvolutionLabRuntimeRegistry.get(appContext)
    private val runRecorder = AgentRunRecorder(appContext)
    private val runEventStore = AgentRunEventStore(appContext)
    private val androidWorldStore = AgentAndroidWorldStore(appContext)

    fun startCodexDeepSeek90To10(repetitions: Int): AgentBenchmarkSession {
        val current = benchmarkStore.sessions().firstOrNull { it.status == AgentBenchmarkSessionStatus.RUNNING }
        require(current == null || progress(current).terminal) { "A comprehensive benchmark is already running" }
        val count = repetitions.coerceIn(suite.minimumRepetitions, suite.maximumRepetitions)
        val allocation = AgentBenchmarkAllocationPolicy.codexDeepSeek90To10(suite, labRuntime.availableAgents())
        if (suite.cases.any { it.dimension == AgentBenchmarkDimension.ANDROID_WORLD }) {
            AgentAndroidWorldBenchmarkFixtures.install(appContext)
        }
        AgentBenchmarkMemoryFixtures.prepareForSuite(appContext, suite)
        val readiness = AgentBenchmarkPreflight.assess(appContext, suite)
        val readyCases = suite.cases.filter { case ->
            readiness[case.id]?.status == AgentBenchmarkReadinessStatus.READY
        }
        val campaigns = labStore.createBatch(readyCases.map { case ->
            AgentLabCampaignRequest(
                task = case.taggedPrompt,
                agentIds = allocation.resourceIdsByCase.getValue(case.id),
                repetitions = count
            )
        })
        val campaignIds = readyCases.zip(campaigns).associateTo(linkedMapOf()) { (case, campaign) ->
            case.id to campaign.id
        }
        try {
            val session = AgentBenchmarkSession(
                suiteId = suite.id,
                suiteVersion = suite.version,
                appVersionName = BuildConfig.VERSION_NAME,
                appVersionCode = BuildConfig.VERSION_CODE.toLong(),
                deviceModel = Build.MODEL,
                repetitions = count,
                targetPassRate = suite.targetPassRate,
                caseIds = suite.cases.map(AgentBenchmarkCase::id),
                resources = allocation.resources.map(::snapshot),
                resourceIdsByCase = allocation.resourceIdsByCase,
                campaignIdsByCase = campaignIds,
                teamResourceIdsByCase = allocation.teamResourceIdsByCase,
                readinessByCase = readiness
            )
            benchmarkStore.saveSession(session)
            campaigns.forEach(labRuntime::startPrepared)
            return session
        } catch (error: Throwable) {
            campaignIds.values.forEach(labStore::cancel)
            throw error
        }
    }

    fun latest(): AgentBenchmarkSession? = benchmarkStore.latestSession(suite.id, suite.version)

    fun resumeLatestIncomplete(
        condition: AgentEvalCondition = AgentEvalCondition.PROCESS_DEATH,
        reason: String = "Comprehensive benchmark resumed after interruption"
    ): Int {
        val session = benchmarkStore.sessions().firstOrNull {
            it.status == AgentBenchmarkSessionStatus.RUNNING &&
                it.suiteId == suite.id &&
                it.suiteVersion == suite.version
        } ?: return 0
        reconcileDurableResults(session)
        if (benchmarkStore.session(session.id)?.status == AgentBenchmarkSessionStatus.COMPLETED) return 0
        val existingTrialIds = benchmarkStore.results(session.id)
            .mapTo(hashSetOf(), AgentBenchmarkTrialResult::trialId)
        val campaigns = labStore.getAll(session.campaignIdsByCase.values)
        var resumed = labRuntime.resumeIncomplete(
            campaignIds = session.campaignIdsByCase.values,
            condition = condition,
            reason = reason
        )
        campaigns.forEach { campaign ->
            val missingTrialIds = campaign.trials.asSequence()
                .map(AgentLabTrial::id)
                .filterNot(existingTrialIds::contains)
                .toSet()
            if (missingTrialIds.isNotEmpty() && labRuntime.resumeTrialsMissingBenchmarkResults(
                    campaignId = campaign.id,
                    trialIds = missingTrialIds,
                    condition = condition,
                    reason = "$reason; durable benchmark result was missing"
                )
            ) {
                resumed += 1
            }
        }
        return resumed
    }

    fun scorecard(session: AgentBenchmarkSession): AgentBenchmarkScorecard =
        AgentBenchmarkStatistics.scorecard(session, suite, benchmarkStore.results(session.id))

    fun trialEvidence(
        session: AgentBenchmarkSession,
        dimension: AgentBenchmarkDimension? = null
    ): List<AgentBenchmarkTrialEvidence> {
        val resources = session.resources.associateBy(AgentBenchmarkResourceSnapshot::resourceId)
        val benchmarkResults = benchmarkStore.results(session.id)
        val androidWorldRunIds = benchmarkResults.mapNotNull { result ->
            result.runId.takeIf {
                suite.case(result.caseId)?.expectation?.androidWorldTaskId?.isNotBlank() == true
            }
        }
        val worldByRun = androidWorldStore.resultsForRuns(androidWorldRunIds)
        return benchmarkResults
            .asReversed()
            .mapNotNull { result ->
                val case = suite.case(result.caseId) ?: return@mapNotNull null
                if (dimension != null && case.dimension != dimension) return@mapNotNull null
                val run = runRecorder.run(result.runId)
                val events = runEventStore.events(result.runId)
                val world = worldByRun[result.runId]
                AgentBenchmarkTrialEvidence(
                    caseId = case.id,
                    caseTitle = case.title,
                    dimension = case.dimension,
                    resourceName = resources[result.resourceId]?.displayName ?: result.resourceId,
                    repetition = result.repetition,
                    classification = AgentBenchmarkTrialClassificationPolicy.classify(result),
                    failureReasons = result.failureReasons,
                    rawOutput = finalOutputText(run?.finalOutputJson.orEmpty()),
                    planEventCount = events.count { it.type in PLAN_EVENT_TYPES } +
                        meaningfulPlanCount(run?.agentPlanJson.orEmpty()),
                    toolReceipts = run?.toolCalls.orEmpty().map {
                        "${it.toolName}: ${it.status.name.lowercase()}" +
                            it.errorMessage.takeIf(String::isNotBlank)?.let { error -> " ($error)" }.orEmpty() +
                            it.resultJson.takeIf(String::isNotBlank)?.let { result -> " = ${result.take(300)}" }.orEmpty()
                    },
                    androidWorldEvidence = world?.verifierResults.orEmpty().map {
                        "${it.verifierId}: ${it.actual} (${if (it.passed) "passed" else "failed"})"
                    },
                    runId = result.runId
                )
            }
    }

    fun progress(session: AgentBenchmarkSession): AgentBenchmarkProgress {
        val completedTrials = benchmarkStore.resultCount(session.id)
            ?: labStore.getAll(session.campaignIdsByCase.values).sumOf { campaign ->
                campaign.trials.count { it.status in TERMINAL_TRIAL_STATES }
            }
        val completedCampaigns = (completedTrials / session.repetitions)
            .coerceAtMost(session.scheduledCaseIds.size)
        return AgentBenchmarkProgress(
            completedTrials = completedTrials,
            expectedTrials = session.expectedTrials,
            completedCampaigns = completedCampaigns,
            totalCampaigns = session.scheduledCaseIds.size,
            terminal = session.status != AgentBenchmarkSessionStatus.RUNNING ||
                completedTrials >= session.expectedTrials
        )
    }

    fun cancel(sessionId: String): Boolean {
        val session = benchmarkStore.session(sessionId) ?: return false
        benchmarkStore.markStatus(session.id, AgentBenchmarkSessionStatus.CANCELLED)
        labRuntime.cancel(session.campaignIdsByCase.values)
        return true
    }

    private fun reconcileDurableResults(session: AgentBenchmarkSession) {
        val existingTrialIds = benchmarkStore.results(session.id)
            .mapTo(hashSetOf(), AgentBenchmarkTrialResult::trialId)
        val evalStore = AgentEvalOpsStore(appContext)
        labStore.getAll(session.campaignIdsByCase.values).forEach { campaign ->
            campaign.trials.asSequence()
                .filterNot { it.id in existingTrialIds }
                .filter { it.runId.isNotBlank() }
                .forEach { trial ->
                    val run = runRecorder.run(trial.runId) ?: return@forEach
                    val sample = evalStore.sample(trial.runId) ?: return@forEach
                    AgentBenchmarkService.observe(appContext, run, sample)
                }
        }
    }

    private fun snapshot(registration: AgentRegistration) = AgentBenchmarkResourceSnapshot(
        resourceId = registration.agentId,
        displayName = registration.displayName,
        providerId = registration.providerId,
        modelId = registration.providerProfile?.modelId.orEmpty().ifBlank { registration.displayName },
        adapterType = registration.adapterType.ifBlank { registration.providerProfile?.adapterType.orEmpty() },
        capabilitiesHash = registration.capabilitiesHash
    )

    private fun finalOutputText(raw: String): String = runCatching {
        val json = JSONObject(raw)
        sequenceOf("text", "message", "content", "result", "error")
            .map(json::optString)
            .firstOrNull(String::isNotBlank).orEmpty()
    }.getOrDefault(raw)

    private fun meaningfulPlanCount(raw: String): Int = runCatching {
        val array = JSONArray(raw)
        (0 until array.length()).count { index ->
            val item = array.optJSONObject(index) ?: return@count false
            PLAN_KEYS.any(item::has)
        }
    }.getOrDefault(0)

    private companion object {
        val TERMINAL_TRIAL_STATES = setOf(
            AgentLabTrialStatus.COMPLETED,
            AgentLabTrialStatus.FAILED,
            AgentLabTrialStatus.CANCELLED
        )
        val PLAN_EVENT_TYPES = setOf(
            AgentRunControlEventType.PLANNING,
            AgentRunControlEventType.STEP_STARTED,
            AgentRunControlEventType.STEP_COMPLETED
        )
        val PLAN_KEYS = setOf("step", "action", "objective", "description", "title", "status")
    }
}

object AgentBenchmarkTrialEvaluator {
    fun evaluate(
        session: AgentBenchmarkSession,
        case: AgentBenchmarkCase,
        campaign: AgentLabCampaign,
        trial: AgentLabTrial,
        run: AgentRecordedRun,
        sample: AgentEvalSample,
        events: List<AgentRunControlEvent>,
        androidWorldResult: AgentAndroidWorldResult?
    ): AgentBenchmarkTrialResult {
        val output = finalText(run.finalOutputJson)
        val expectation = case.expectation
        val failures = buildList {
            if (run.status != AgentRecordedRunStatus.COMPLETED) {
                add("run_status:${run.status.name.lowercase()}")
            }
            sample.failureReasons.filter { reason ->
                reason.startsWith("run_failure:") || reason.startsWith("duration_budget_exceeded") ||
                    reason.startsWith("cost_budget_exceeded")
            }.forEach(::add)
            if (output.length < expectation.minimumOutputChars) add("output_too_short")
            expectation.requiredOutputPatterns.forEachIndexed { index, pattern ->
                if (!matches(pattern, output)) add("required_output_pattern:$index")
            }
            if (expectation.requiredJsonFields.isNotEmpty()) {
                val json = strictJsonObject(output)
                if (json == null) {
                    add("invalid_json_output")
                } else {
                    expectation.requiredJsonFields.forEach { (key, expected) ->
                        if (json.opt(key)?.toString().orEmpty() != expected) {
                            add("required_json_field:$key")
                        }
                    }
                }
            }
            expectation.forbiddenOutputPatterns.forEachIndexed { index, pattern ->
                if (matches(pattern, output)) add("forbidden_output_pattern:$index")
            }
            val missingEvidence = expectation.requiredEvidence - sample.evidenceKinds
            missingEvidence.forEach { add("missing_evidence:${it.wireValue}") }
            if (expectation.minimumVerifiedSources > 0 &&
                verifiedSourceCount(run.sourcesJson) < expectation.minimumVerifiedSources) {
                add("insufficient_verified_sources")
            }
            val planEvents = maxOf(
                events.count { it.type in PLAN_EVENT_TYPES },
                meaningfulPlanCount(run.agentPlanJson)
            )
            if (planEvents < expectation.minimumPlanEvents) add("missing_plan_evidence")
            val toolReceipts = maxOf(
                run.toolCalls.count { it.status == AgentToolCallStatus.SUCCEEDED },
                events.count {
                    it.type == AgentRunControlEventType.TOOL_COMPLETED &&
                        it.payload["status"]?.toString() == "succeeded"
                }
            )
            if (toolReceipts < expectation.minimumToolReceipts) add("missing_tool_receipt")
            run.toolCalls.filter { it.status != AgentToolCallStatus.SUCCEEDED }.forEach { call ->
                val error = call.errorMessage.lowercase()
                val prefix = if (TOOL_INFRASTRUCTURE_ERRORS.any(error::contains)) {
                    "tool_infrastructure"
                } else {
                    "tool_failure"
                }
                add("$prefix:${call.toolName}:${call.errorMessage.take(160)}")
            }
            val distinctAgents = events.map(AgentRunControlEvent::agentId).filter(String::isNotBlank).distinct().size
            if (distinctAgents < expectation.minimumDistinctAgents) add("insufficient_distinct_agents")
            if (events.count { it.type == AgentRunControlEventType.HANDOFF } < expectation.minimumHandoffs) {
                add("missing_handoff_evidence")
            }
            if (expectation.requiredCondition != AgentEvalCondition.NORMAL) {
                val conditionObserved = expectation.requiredCondition in sample.observedConditions
                if (!conditionObserved) add("condition_not_observed")
                if (conditionObserved && !sample.recovered) add("recovery_failed_after_observation")
            }
            if (expectation.memoryHorizonDays > 0 && sample.memoryHorizonDays < expectation.memoryHorizonDays) {
                add("memory_horizon_not_verified")
            }
            if (expectation.androidWorldTaskId.isNotBlank()) {
                if (androidWorldResult?.taskId != expectation.androidWorldTaskId || !androidWorldResult.passed) {
                    add("android_world_not_verified")
                } else if (expectation.requireAndroidObservedValuesInOutput) {
                    androidWorldResult.verifierResults
                        .filterNot { it.verifierId.startsWith("required-package:") }
                        .map(AgentAndroidWorldVerifierResult::actual)
                        .filter(String::isNotBlank)
                        .filterNot { it.equals("true", true) || it.equals("false", true) }
                        .forEachIndexed { index, actual ->
                            if (!output.contains(actual, ignoreCase = true)) add("android_world_value_missing:$index")
                        }
                }
            }
        }.distinct()
        return AgentBenchmarkTrialResult(
            sessionId = session.id,
            caseId = case.id,
            campaignId = campaign.id,
            trialId = trial.id,
            runId = run.runId,
            resourceId = trial.agentId,
            repetition = trial.repetition,
            passed = failures.isEmpty(),
            verified = sample.verified && run.status != AgentRecordedRunStatus.RUNNING,
            failureReasons = failures,
            durationMillis = sample.durationMillis,
            reportedCostMicros = sample.reportedCostMicros,
            batteryDeltaPercent = sample.batteryDeltaPercent,
            peakThermalStatus = sample.peakThermalStatus,
            completedAtMillis = sample.completedAtMillis
        )
    }

    private fun matches(pattern: String, output: String): Boolean = runCatching {
        Regex(pattern, setOf(RegexOption.IGNORE_CASE)).matches(output.trim()) ||
            Regex(pattern, setOf(RegexOption.IGNORE_CASE)).containsMatchIn(output.trim())
    }.getOrDefault(false)

    private fun strictJsonObject(output: String): JSONObject? = runCatching {
        val clean = output.trim().removePrefix("\uFEFF")
        JSONObject(clean).takeIf { clean.startsWith('{') && clean.endsWith('}') }
    }.getOrNull()

    private fun verifiedSourceCount(raw: String): Int = runCatching {
        val sources = JSONArray(raw)
        (0 until sources.length()).mapNotNull { index ->
            sources.optJSONObject(index)?.let { source ->
                source.optString("url").ifBlank { source.optString("citation_id") }.takeIf(String::isNotBlank)
            }
        }.distinct().size
    }.getOrDefault(0)

    private fun meaningfulPlanCount(raw: String): Int = runCatching {
        val array = JSONArray(raw)
        (0 until array.length()).count { index ->
            val item = array.optJSONObject(index) ?: return@count false
            PLAN_KEYS.any(item::has)
        }
    }.getOrDefault(0)

    private fun finalText(raw: String): String = runCatching {
        val json = JSONObject(raw)
        sequenceOf("text", "message", "content", "result")
            .map(json::optString).firstOrNull(String::isNotBlank).orEmpty()
    }.getOrDefault("")

    private val PLAN_EVENT_TYPES = setOf(
        AgentRunControlEventType.PLANNING,
        AgentRunControlEventType.STEP_STARTED,
        AgentRunControlEventType.STEP_COMPLETED
    )
    private val PLAN_KEYS = setOf("step", "action", "objective", "description", "title", "status")
    private val TOOL_INFRASTRUCTURE_ERRORS = setOf(
        "network",
        "timeout",
        "timed_out",
        "unavailable",
        "connection",
        "transport"
    )
}

object AgentBenchmarkService {
    fun observe(context: Context, run: AgentRecordedRun, sample: AgentEvalSample) {
        val benchmarkStore = AgentBenchmarkStore(context)
        val labStore = AgentLabStore(context)
        val campaign = labStore.campaignForRun(run.runId) ?: return
        val session = benchmarkStore.sessions().firstOrNull { candidate ->
            candidate.status == AgentBenchmarkSessionStatus.RUNNING &&
                campaign.id in candidate.campaignIdsByCase.values
        } ?: return
        val suite = AgentEvalBenchmarkCatalog.suite(session.suiteId, session.suiteVersion) ?: return
        val mapping = session.campaignIdsByCase.entries.firstOrNull { it.value == campaign.id } ?: return
        val case = suite.case(mapping.key) ?: return
        val trial = campaign.trials.firstOrNull { it.runId == run.runId } ?: return
        val events = AgentRunEventStore(context).events(run.runId)
        val worldResult = if (case.expectation.androidWorldTaskId.isNotBlank()) {
            AgentAndroidWorldStore(context).resultForRun(run.runId)
        } else null
        val completedFloor = if (benchmarkStore.resultCount(session.id) == null) {
            labStore.getAll(session.campaignIdsByCase.values).sumOf { candidate ->
                candidate.trials.count { candidateTrial ->
                    candidateTrial.status == AgentLabTrialStatus.COMPLETED ||
                        candidateTrial.status == AgentLabTrialStatus.FAILED ||
                        candidateTrial.status == AgentLabTrialStatus.CANCELLED
                }
            }
        } else 0
        val completed = benchmarkStore.saveResult(
            AgentBenchmarkTrialEvaluator.evaluate(
                session, case, campaign, trial, run, sample, events, worldResult
            ),
            completedTrialsFloor = completedFloor
        )
        if (completed >= session.expectedTrials) {
            benchmarkStore.markStatus(session.id, AgentBenchmarkSessionStatus.COMPLETED)
        }
    }
}

object AgentAndroidWorldBenchmarkFixtures {
    fun install(context: Context) {
        val packageName = context.packageName
        val definitions = listOf(
            task("android-world-01", "确认 SignalASI 当前位于前台，并报告其包名。", packageName,
                AgentAndroidWorldVerifierKind.FOREGROUND_PACKAGE, "", packageName, "equals"),
            task("android-world-02", "读取并报告当前设备的 Android ID。", packageName,
                AgentAndroidWorldVerifierKind.SYSTEM_SETTING, "secure:android_id", "^[0-9a-fA-F]{16}$", "matches"),
            task("android-world-03", "读取并报告当前系统屏幕亮度数值。", packageName,
                AgentAndroidWorldVerifierKind.SYSTEM_SETTING, "system:screen_brightness", "^[0-9]+$", "matches"),
            task("android-world-04", "读取并报告当前系统息屏超时毫秒数。", packageName,
                AgentAndroidWorldVerifierKind.SYSTEM_SETTING, "system:screen_off_timeout", "^[0-9]+$", "matches"),
            task("android-world-05", "读取并报告当前飞行模式状态值。", packageName,
                AgentAndroidWorldVerifierKind.SYSTEM_SETTING, "global:airplane_mode_on", "^[01]$", "matches"),
            task("android-world-06", "读取并报告当前无障碍总开关状态值。", packageName,
                AgentAndroidWorldVerifierKind.SYSTEM_SETTING, "secure:accessibility_enabled", "^[01]$", "matches"),
            task("android-world-07", "读取并报告当前自动旋转状态值。", packageName,
                AgentAndroidWorldVerifierKind.SYSTEM_SETTING, "system:accelerometer_rotation", "^[01]$", "matches"),
            task("android-world-08", "读取并报告当前系统字体比例。", packageName,
                AgentAndroidWorldVerifierKind.SYSTEM_SETTING, "system:font_scale", "^[0-9]+(\\.[0-9]+)?$", "matches"),
            task("android-world-09", "读取并报告当前系统定位模式值。", packageName,
                AgentAndroidWorldVerifierKind.SYSTEM_SETTING, "secure:location_mode", "^[0-9]+$", "matches"),
            task("android-world-10", "读取并报告当前系统低电量模式状态值。", packageName,
                AgentAndroidWorldVerifierKind.SYSTEM_SETTING, "global:low_power", "^[01]$", "matches")
        )
        val store = AgentAndroidWorldStore(context)
        definitions.forEach { store.import(AgentAndroidWorldTaskCodec.encode(it).toString()) }
    }

    private fun task(
        id: String,
        instruction: String,
        packageName: String,
        kind: AgentAndroidWorldVerifierKind,
        key: String,
        expected: String,
        operator: String
    ) = AgentAndroidWorldTask(
        id = id,
        instruction = "[evalops:$id] $instruction [androidworld:$id]",
        category = "signalasi_evalops",
        requiredPackages = listOf(packageName),
        verifiers = listOf(AgentAndroidWorldVerifier(
            id = "$id-verifier",
            kind = kind,
            key = key,
            expected = expected,
            operator = operator
        )),
        sourceVersion = AgentEvalBenchmarkCatalog.standard.version
    )
}

object AgentBenchmarkMemoryFixtures {
    fun prepare(context: Context): Int = prepareImmediate(context) + prepareLongitudinal(context)

    fun prepareForSuite(context: Context, suite: AgentBenchmarkSuite): Int {
        var prepared = 0
        if (suite.cases.any { it.dimension == AgentBenchmarkDimension.IMMEDIATE_MEMORY }) {
            prepared += prepareImmediate(context)
        }
        if (suite.cases.any { it.dimension == AgentBenchmarkDimension.LONG_TERM_MEMORY }) {
            prepared += prepareLongitudinal(context)
        }
        return prepared
    }

    fun prepareImmediate(context: Context): Int {
        val store = EncryptedAgentMemoryStore(context.applicationContext)
        return withoutWorldModelObservations(store) {
            val activeByKey = store.snapshot().activeItems.associateBy(AgentMemoryItem::key)
            IMMEDIATE_VALUES.count { fixture ->
                upsertImmediate(store, fixture, activeByKey[immediateKey(fixture.id)])
            }
        }
    }

    fun prepareLongitudinal(context: Context): Int {
        val store = EncryptedAgentMemoryStore(context.applicationContext)
        return withoutWorldModelObservations(store) {
            val existing = store.snapshot().activeItems.associateBy(AgentMemoryItem::key)
            LONGITUDINAL_VALUES.count { (fixtureId, value) ->
                val key = "evalops.fixture.${fixtureId.lowercase()}"
                if (existing[key]?.value == "$fixtureId = $value") return@count true
                store.remember(AgentMemoryItem(
                    kind = AgentMemoryKind.KNOWLEDGE,
                    value = "$fixtureId = $value",
                    source = "evalops_fixture",
                    key = key,
                    important = true,
                    confidence = 1.0,
                    whyRemembered = "Versioned long-horizon Agent benchmark fixture"
                )).item != null
            }
        }
    }

    private inline fun <T> withoutWorldModelObservations(
        store: EncryptedAgentMemoryStore,
        block: () -> T
    ): T {
        val previous = store.suppressObservations
        store.suppressObservations = true
        return try {
            block()
        } finally {
            store.suppressObservations = previous
        }
    }

    private fun upsertImmediate(
        store: EncryptedAgentMemoryStore,
        fixture: ImmediateFixture,
        active: AgentMemoryItem?
    ): Boolean {
        val key = immediateKey(fixture.id)
        if (
            active != null &&
            active.value.contains(fixture.value) &&
            active.source in IMMEDIATE_SOURCES
        ) return true
        if (fixture.oldValue.isNotBlank() && active == null) {
            val old = store.remember(memoryItem(fixture.id, fixture.oldValue, fixture.kind, key)).item
            return old?.let { store.update(it.id, "${fixture.id} = ${fixture.value}", key)?.item } != null
        } else if (active != null) {
            return store.update(active.id, "${fixture.id} = ${fixture.value}", key)?.item != null
        } else {
            return store.remember(memoryItem(fixture.id, fixture.value, fixture.kind, key)).item != null
        }
    }

    private fun immediateKey(id: String) = "evalops.immediate.${id.lowercase()}"

    private fun memoryItem(id: String, value: String, kind: AgentMemoryKind, key: String) = AgentMemoryItem(
        kind = kind,
        value = "$id = $value",
        source = "evalops_immediate_fixture",
        key = key,
        important = true,
        confidence = 1.0,
        whyRemembered = "Versioned immediate cross-session Agent benchmark fixture"
    )

    private data class ImmediateFixture(
        val id: String,
        val value: String,
        val kind: AgentMemoryKind,
        val oldValue: String = ""
    )

    private val IMMEDIATE_VALUES = listOf(
        ImmediateFixture("IM-01", "SASI-IM-NOVA", AgentMemoryKind.IDENTITY),
        ImmediateFixture("IM-02", "SASI-IM-DARK", AgentMemoryKind.PREFERENCE),
        ImmediateFixture("IM-03", "SASI-IM-TABLET", AgentMemoryKind.IDENTITY),
        ImmediateFixture("IM-04", "SASI-IM-PROJECT", AgentMemoryKind.TASK),
        ImmediateFixture("IM-05", "SASI-IM-KNOWLEDGE", AgentMemoryKind.KNOWLEDGE),
        ImmediateFixture("IM-06", "SASI-IM-WORKFLOW", AgentMemoryKind.WORKFLOW),
        ImmediateFixture("IM-07", "SASI-IM-DECISION", AgentMemoryKind.TASK),
        ImmediateFixture("IM-08", "SASI-IM-CURRENT", AgentMemoryKind.KNOWLEDGE, "SASI-IM-OLD"),
        ImmediateFixture("IM-09-A", "SASI-IM-ALPHA", AgentMemoryKind.KNOWLEDGE),
        ImmediateFixture("IM-09-B", "SASI-IM-BETA", AgentMemoryKind.KNOWLEDGE),
        ImmediateFixture("IM-10", "SASI-IM-PROVENANCE", AgentMemoryKind.KNOWLEDGE)
    )

    private val LONGITUDINAL_VALUES = listOf(
        "M30-01" to "SASI-M30-ALPHA",
        "M30-02" to "SASI-M30-BRAVO",
        "M30-03" to "SASI-M30-CHARLIE",
        "M30-04" to "SASI-M30-DELTA",
        "M30-05" to "SASI-M30-ECHO",
        "M90-01" to "SASI-M90-FOXTROT",
        "M90-02" to "SASI-M90-GOLF",
        "M90-03" to "SASI-M90-HOTEL",
        "M90-04" to "SASI-M90-INDIA",
        "M90-05" to "SASI-M90-JULIET"
    )

    private val IMMEDIATE_SOURCES = setOf("evalops_immediate_fixture", "memory_edit")
}
