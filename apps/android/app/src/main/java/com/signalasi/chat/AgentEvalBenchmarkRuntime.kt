package com.signalasi.chat

import android.content.Context
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

data class AgentBenchmarkAllocation(
    val resources: List<AgentRegistration>,
    val resourceIdsByCase: Map<String, List<String>>
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
        val assignment = buildMap {
            AgentBenchmarkDimension.entries.forEach { dimension ->
                val cases = suite.cases.filter { it.dimension == dimension }
                require(cases.size == 10) { "The 90/10 profile requires ten cases per dimension" }
                cases.forEachIndexed { index, case ->
                    put(case.id, listOf(if (index == cases.lastIndex) deepSeek.agentId else codex.agentId))
                }
            }
        }
        val codexCount = assignment.values.count { codex.agentId in it }
        val deepSeekCount = assignment.values.count { deepSeek.agentId in it }
        require(codexCount == 54 && deepSeekCount == 6) { "The benchmark allocation must remain 90% Codex and 10% DeepSeek" }
        return AgentBenchmarkAllocation(listOf(codex, deepSeek), assignment)
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

class AgentBenchmarkCoordinator(context: Context) {
    private val appContext = context.applicationContext
    private val suite = AgentEvalBenchmarkCatalog.standard
    private val benchmarkStore = AgentBenchmarkStore(appContext)
    private val labStore = AgentLabStore(appContext)
    private val labRuntime = AgentEvolutionLabRuntimeRegistry.get(appContext)

    fun startCodexDeepSeek90To10(repetitions: Int): AgentBenchmarkSession {
        val current = benchmarkStore.sessions().firstOrNull()
        require(current == null || progress(current).terminal) { "A comprehensive benchmark is already running" }
        val count = repetitions.coerceIn(suite.minimumRepetitions, suite.maximumRepetitions)
        val allocation = AgentBenchmarkAllocationPolicy.codexDeepSeek90To10(suite, labRuntime.availableAgents())
        AgentAndroidWorldBenchmarkFixtures.install(appContext)
        AgentBenchmarkMemoryFixtures.prepare(appContext)
        val campaignIds = linkedMapOf<String, String>()
        try {
            suite.cases.forEach { case ->
                val resourceIds = allocation.resourceIdsByCase.getValue(case.id)
                val campaign = labStore.create(case.taggedPrompt, resourceIds, count)
                campaignIds[case.id] = campaign.id
            }
        } catch (error: Throwable) {
            campaignIds.values.forEach(labStore::cancel)
            throw error
        }
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
            campaignIdsByCase = campaignIds
        )
        benchmarkStore.saveSession(session)
        campaignIds.values.forEach(labRuntime::start)
        return session
    }

    fun latest(): AgentBenchmarkSession? = benchmarkStore.sessions().firstOrNull()

    fun scorecard(session: AgentBenchmarkSession): AgentBenchmarkScorecard =
        AgentBenchmarkStatistics.scorecard(session, suite, benchmarkStore.results(session.id))

    fun progress(session: AgentBenchmarkSession): AgentBenchmarkProgress {
        val campaigns = session.campaignIdsByCase.values.mapNotNull(labStore::get)
        val terminalCampaigns = campaigns.count { it.status in TERMINAL_CAMPAIGN_STATES }
        val completedTrials = campaigns.sumOf { campaign ->
            campaign.trials.count { it.status in TERMINAL_TRIAL_STATES }
        }
        return AgentBenchmarkProgress(
            completedTrials = completedTrials,
            expectedTrials = session.expectedTrials,
            completedCampaigns = terminalCampaigns,
            totalCampaigns = session.caseIds.size,
            terminal = session.status != AgentBenchmarkSessionStatus.RUNNING ||
                (campaigns.size == session.caseIds.size && terminalCampaigns == campaigns.size)
        )
    }

    fun cancel(sessionId: String): Boolean {
        val session = benchmarkStore.session(sessionId) ?: return false
        session.campaignIdsByCase.values.forEach(labRuntime::cancel)
        benchmarkStore.markStatus(session.id, AgentBenchmarkSessionStatus.CANCELLED)
        return true
    }

    private fun snapshot(registration: AgentRegistration) = AgentBenchmarkResourceSnapshot(
        resourceId = registration.agentId,
        displayName = registration.displayName,
        providerId = registration.providerId,
        modelId = registration.providerProfile?.modelId.orEmpty().ifBlank { registration.displayName },
        adapterType = registration.adapterType.ifBlank { registration.providerProfile?.adapterType.orEmpty() },
        capabilitiesHash = registration.capabilitiesHash
    )

    private companion object {
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
            expectation.forbiddenOutputPatterns.forEachIndexed { index, pattern ->
                if (matches(pattern, output)) add("forbidden_output_pattern:$index")
            }
            val missingEvidence = expectation.requiredEvidence - sample.evidenceKinds
            missingEvidence.forEach { add("missing_evidence:${it.wireValue}") }
            val planEvents = events.count { it.type in PLAN_EVENT_TYPES } + meaningfulPlanCount(run.agentPlanJson)
            if (planEvents < expectation.minimumPlanEvents) add("missing_plan_evidence")
            val toolReceipts = run.toolCalls.count { it.status == AgentToolCallStatus.SUCCEEDED } +
                events.count { it.type == AgentRunControlEventType.TOOL_COMPLETED }
            if (toolReceipts < expectation.minimumToolReceipts) add("missing_tool_receipt")
            val distinctAgents = events.map(AgentRunControlEvent::agentId).filter(String::isNotBlank).distinct().size
            if (distinctAgents < expectation.minimumDistinctAgents) add("insufficient_distinct_agents")
            if (events.count { it.type == AgentRunControlEventType.HANDOFF } < expectation.minimumHandoffs) {
                add("missing_handoff_evidence")
            }
            if (expectation.requiredCondition != AgentEvalCondition.NORMAL) {
                if (expectation.requiredCondition !in sample.observedConditions) add("condition_not_observed")
                if (!sample.recovered) add("recovery_not_verified")
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
            verified = run.status != AgentRecordedRunStatus.RUNNING,
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
}

object AgentBenchmarkService {
    fun observe(context: Context, run: AgentRecordedRun, sample: AgentEvalSample) {
        val benchmarkStore = AgentBenchmarkStore(context)
        val suite = AgentEvalBenchmarkCatalog.standard
        val labStore = AgentLabStore(context)
        val session = benchmarkStore.sessions().firstOrNull { candidate ->
            candidate.status == AgentBenchmarkSessionStatus.RUNNING &&
                candidate.suiteId == suite.id && candidate.suiteVersion == suite.version &&
                candidate.campaignIdsByCase.values.any { campaignId ->
                    labStore.get(campaignId)?.trials?.any { it.runId == run.runId } == true
                }
        } ?: return
        val mapping = session.campaignIdsByCase.entries.firstOrNull { (_, campaignId) ->
            labStore.get(campaignId)?.trials?.any { it.runId == run.runId } == true
        } ?: return
        val case = suite.case(mapping.key) ?: return
        val campaign = labStore.get(mapping.value) ?: return
        val trial = campaign.trials.firstOrNull { it.runId == run.runId } ?: return
        val events = AgentRunEventStore(context).events(run.runId)
        val worldResult = AgentAndroidWorldStore(context).results(500).firstOrNull { it.runId == run.runId }
        benchmarkStore.saveResult(AgentBenchmarkTrialEvaluator.evaluate(
            session, case, campaign, trial, run, sample, events, worldResult
        ))
        val completed = benchmarkStore.results(session.id)
            .groupBy(AgentBenchmarkTrialResult::trialId).size
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
    fun prepare(context: Context): Int {
        val store = EncryptedAgentMemoryStore(context.applicationContext)
        return VALUES.count { (fixtureId, value) ->
            store.remember(AgentMemoryItem(
                kind = AgentMemoryKind.KNOWLEDGE,
                value = "$fixtureId = $value",
                source = "evalops_fixture",
                key = "evalops.fixture.${fixtureId.lowercase()}",
                important = true,
                confidence = 1.0,
                whyRemembered = "Versioned long-horizon Agent benchmark fixture"
            )).item != null
        }
    }

    private val VALUES = listOf(
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
}
