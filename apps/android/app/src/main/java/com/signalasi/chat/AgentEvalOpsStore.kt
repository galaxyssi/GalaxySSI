package com.signalasi.chat

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

class AgentEvalOpsStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    fun settings(): AgentEvalOpsSettings = decodeSettings(database.readString(KEY_SETTINGS, "{}"))

    @Synchronized
    fun updateSettings(transform: (AgentEvalOpsSettings) -> AgentEvalOpsSettings): AgentEvalOpsSettings {
        val updated = transform(settings()).normalized()
        database.writeString(KEY_SETTINGS, encodeSettings(updated).toString())
        return updated
    }

    @Synchronized
    fun saveStart(start: AgentEvalRunStart) {
        database.writeString(startKey(start.runId), encodeStart(start).toString())
    }

    @Synchronized
    fun start(runId: String): AgentEvalRunStart? = decodeStart(
        database.readString(startKey(runId.trim()), "")
    )

    @Synchronized
    fun discardStart(runId: String) {
        database.removeAll(listOf(startKey(runId.trim())))
    }

    @Synchronized
    fun activeStarts(): List<AgentEvalRunStart> = database.entries(START_PREFIX)
        .mapNotNull { decodeStart(it.second) }
        .sortedBy(AgentEvalRunStart::runId)

    @Synchronized
    fun saveSample(sample: AgentEvalSample) {
        database.mutateStrings(
            upserts = mapOf(sampleKey(sample.runId) to encodeSample(sample).toString()),
            removeKeys = listOf(startKey(sample.runId))
        )
        pruneSamples()
    }

    @Synchronized
    fun sample(runId: String): AgentEvalSample? = decodeSample(
        database.readString(sampleKey(runId.trim()), "")
    )

    @Synchronized
    fun samples(limit: Int = MAX_SAMPLES): List<AgentEvalSample> {
        val keys = database.recentKeys(SAMPLE_PREFIX, limit.coerceIn(1, MAX_SAMPLES))
        val values = database.readStrings(keys)
        return keys.mapNotNull { key -> values[key]?.let(::decodeSample) }
            .sortedByDescending(AgentEvalSample::completedAtMillis)
    }

    @Synchronized
    fun recordProactiveFeedback(runId: String, relevant: Boolean, accepted: Boolean): AgentEvalSample? {
        val current = sample(runId) ?: return null
        val updated = current.copy(
            verdict = when {
                relevant && accepted -> AgentEvalVerdict.PASSED
                relevant -> AgentEvalVerdict.PARTIAL
                else -> AgentEvalVerdict.FAILED
            },
            contractSatisfied = relevant && accepted,
            verified = true,
            proactiveRelevant = relevant,
            proactiveAccepted = accepted,
            failureReasons = when {
                relevant && accepted -> emptyList()
                relevant -> listOf("proactive_not_accepted")
                else -> listOf("proactive_not_relevant")
            }
        )
        database.writeString(sampleKey(runId), encodeSample(updated).toString())
        return updated
    }

    @Synchronized
    fun recordProactiveDelivery(
        message: GlobalProactiveMessage,
        attention: AgentAttentionDecisionRecord
    ): AgentEvalSample {
        val runId = proactiveRunId(message.id)
        sample(runId)?.let { return it }
        val sample = AgentEvalSample(
            runId = runId,
            scenarioId = AgentLearningAnalyzer.stableKey(message.topic.ifBlank { message.content }),
            taskClass = AgentEvalTaskClass.PROACTIVE,
            resourceId = "signalasi-proactive-cognition",
            verdict = AgentEvalVerdict.UNVERIFIED,
            contractSatisfied = false,
            verified = false,
            durationMillis = (message.deliveredAtMillis - message.createdAtMillis).coerceAtLeast(0L),
            proactiveRelevant = null,
            proactiveAccepted = null,
            failureReasons = listOf("awaiting_user_feedback", "attention:${attention.decision.disposition.name.lowercase()}"),
            evidenceKinds = setOf(AgentOutcomeEvidenceKind.FINAL_RESPONSE),
            completedAtMillis = message.deliveredAtMillis.takeIf { it > 0L } ?: System.currentTimeMillis()
        )
        saveSample(sample)
        return sample
    }

    fun dashboard(): AgentEvalDashboard = AgentEvalStatistics.dashboard(
        samples(),
        settings().repeatedTrials
    )

    @Synchronized
    fun clearResults() {
        database.removeAll(database.keys(START_PREFIX) + database.keys(SAMPLE_PREFIX))
    }

    private fun pruneSamples() {
        val retainedKeys = database.recentKeys(SAMPLE_PREFIX, MAX_SAMPLES).toHashSet()
        val stale = database.keys(SAMPLE_PREFIX).filterNot(retainedKeys::contains)
        database.removeAll(stale)
    }

    private fun encodeSettings(value: AgentEvalOpsSettings) = JSONObject()
        .put("capture_real_runs", value.captureRealRuns)
        .put("continuous_evaluation", value.continuousEvaluationEnabled)
        .put("repeated_trials", value.repeatedTrials)
        .put("shadow_routing", value.shadowRoutingEnabled)
        .put("automatic_quality_routing", value.automaticQualityRoutingEnabled)
        .put("minimum_automatic_samples", value.minimumAutomaticRoutingSamples)
        .put("attention_threshold", value.attentionThreshold)
        .put("skill_markdown_compatibility", value.skillMarkdownCompatibilityEnabled)
        .put("protocol_adapters", value.protocolAdaptersEnabled)
        .put("shadow_release", value.shadowReleaseEnabled)

    private fun decodeSettings(raw: String): AgentEvalOpsSettings = runCatching {
        val json = JSONObject(raw)
        AgentEvalOpsSettings(
            captureRealRuns = json.optBoolean("capture_real_runs", true),
            continuousEvaluationEnabled = json.optBoolean("continuous_evaluation"),
            repeatedTrials = json.optInt("repeated_trials", 3),
            shadowRoutingEnabled = json.optBoolean("shadow_routing", true),
            automaticQualityRoutingEnabled = json.optBoolean("automatic_quality_routing"),
            minimumAutomaticRoutingSamples = json.optInt("minimum_automatic_samples", 12),
            attentionThreshold = json.optDouble("attention_threshold", 0.58),
            skillMarkdownCompatibilityEnabled = json.optBoolean("skill_markdown_compatibility", true),
            protocolAdaptersEnabled = json.optBoolean("protocol_adapters", true),
            shadowReleaseEnabled = json.optBoolean("shadow_release", true)
        ).normalized()
    }.getOrDefault(AgentEvalOpsSettings())

    private fun encodeStart(value: AgentEvalRunStart) = JSONObject()
        .put("run_id", value.runId)
        .put("contract", encodeContract(value.contract))
        .put("device", encodeDevice(value.device))

    private fun decodeStart(raw: String): AgentEvalRunStart? = runCatching {
        val json = JSONObject(raw)
        AgentEvalRunStart(
            runId = json.getString("run_id"),
            contract = decodeContract(json.getJSONObject("contract")),
            device = decodeDevice(json.getJSONObject("device"))
        )
    }.getOrNull()

    private fun encodeContract(value: AgentOutcomeContract) = JSONObject()
        .put("id", value.id)
        .put("run_id", value.runId)
        .put("goal", value.goal)
        .put("task_class", value.taskClass.wireValue)
        .put("success_criteria", JSONArray(value.successCriteria))
        .put("allowed_resources", JSONArray(value.allowedResources.toList()))
        .put("forbidden_resources", JSONArray(value.forbiddenResources.toList()))
        .put("required_evidence", JSONArray(value.requiredEvidence.map(AgentOutcomeEvidenceKind::wireValue)))
        .put("max_duration_millis", value.maxDurationMillis)
        .put("max_reported_cost_micros", value.maxReportedCostMicros)
        .put("memory_horizon_days", value.memoryHorizonDays)
        .put("condition", value.condition.wireValue)
        .put("created_at_millis", value.createdAtMillis)

    private fun decodeContract(json: JSONObject) = AgentOutcomeContract(
        id = json.getString("id"),
        runId = json.getString("run_id"),
        goal = json.optString("goal"),
        taskClass = AgentEvalTaskClass.entries.firstOrNull {
            it.wireValue == json.optString("task_class")
        } ?: AgentEvalTaskClass.GENERAL,
        successCriteria = json.optJSONArray("success_criteria").strings(),
        allowedResources = json.optJSONArray("allowed_resources").strings().toSet(),
        forbiddenResources = json.optJSONArray("forbidden_resources").strings().toSet(),
        requiredEvidence = json.optJSONArray("required_evidence").strings()
            .mapNotNull { wire -> AgentOutcomeEvidenceKind.entries.firstOrNull { it.wireValue == wire } }
            .toSet(),
        maxDurationMillis = json.optLong("max_duration_millis").coerceAtLeast(1L),
        maxReportedCostMicros = json.optLong("max_reported_cost_micros").coerceAtLeast(0L),
        memoryHorizonDays = json.optInt("memory_horizon_days").coerceIn(0, 3650),
        condition = AgentEvalCondition.entries.firstOrNull {
            it.wireValue == json.optString("condition")
        } ?: AgentEvalCondition.NORMAL,
        createdAtMillis = json.optLong("created_at_millis").coerceAtLeast(0L)
    )

    private fun encodeDevice(value: AgentDeviceEvalSnapshot) = JSONObject()
        .put("captured_at_millis", value.capturedAtMillis)
        .put("elapsed_realtime_millis", value.elapsedRealtimeMillis)
        .put("battery_percent", value.batteryPercent)
        .put("charge_counter_micro_ah", value.chargeCounterMicroAh)
        .put("energy_counter_nano_wh", value.energyCounterNanoWh)
        .put("thermal_status", value.thermalStatus)
        .put("available_memory_bytes", value.availableMemoryBytes)
        .put("low_memory", value.lowMemory)
        .put("power_save_mode", value.powerSaveMode)
        .put("device_idle_mode", value.deviceIdleMode)
        .put("network_available", value.networkAvailable)
        .put("network_validated", value.networkValidated)

    private fun decodeDevice(json: JSONObject) = AgentDeviceEvalSnapshot(
        capturedAtMillis = json.optLong("captured_at_millis"),
        elapsedRealtimeMillis = json.optLong("elapsed_realtime_millis"),
        batteryPercent = json.optInt("battery_percent", -1),
        chargeCounterMicroAh = json.optLong("charge_counter_micro_ah"),
        energyCounterNanoWh = json.optLong("energy_counter_nano_wh"),
        thermalStatus = json.optInt("thermal_status", -1),
        availableMemoryBytes = json.optLong("available_memory_bytes"),
        lowMemory = json.optBoolean("low_memory"),
        powerSaveMode = json.optBoolean("power_save_mode"),
        deviceIdleMode = json.optBoolean("device_idle_mode"),
        networkAvailable = json.optBoolean("network_available"),
        networkValidated = json.optBoolean("network_validated")
    )

    private fun encodeSample(value: AgentEvalSample) = JSONObject()
        .put("id", value.id)
        .put("run_id", value.runId)
        .put("scenario_id", value.scenarioId)
        .put("task_class", value.taskClass.wireValue)
        .put("resource_id", value.resourceId)
        .put("verdict", value.verdict.wireValue)
        .put("contract_satisfied", value.contractSatisfied)
        .put("verified", value.verified)
        .put("duration_millis", value.durationMillis)
        .put("reported_cost_micros", value.reportedCostMicros)
        .put("battery_delta_percent", value.batteryDeltaPercent)
        .put("charge_consumed_micro_ah", value.chargeConsumedMicroAh)
        .put("energy_consumed_nano_wh", value.energyConsumedNanoWh)
        .put("peak_thermal_status", value.peakThermalStatus)
        .put("memory_delta_bytes", value.memoryDeltaBytes)
        .put("recovery_attempted", value.recoveryAttempted)
        .put("recovered", value.recovered)
        .put("condition", value.condition.wireValue)
        .put("observed_conditions", JSONArray(value.observedConditions.map(AgentEvalCondition::wireValue)))
        .put("memory_horizon_days", value.memoryHorizonDays)
        .put("proactive_relevant", value.proactiveRelevant)
        .put("proactive_accepted", value.proactiveAccepted)
        .put("failure_reasons", JSONArray(value.failureReasons))
        .put("evidence_kinds", JSONArray(value.evidenceKinds.map(AgentOutcomeEvidenceKind::wireValue)))
        .put("completed_at_millis", value.completedAtMillis)

    private fun decodeSample(raw: String): AgentEvalSample? = runCatching {
        val json = JSONObject(raw)
        AgentEvalSample(
            id = json.getString("id"),
            runId = json.getString("run_id"),
            scenarioId = json.getString("scenario_id"),
            taskClass = AgentEvalTaskClass.entries.firstOrNull {
                it.wireValue == json.optString("task_class")
            } ?: AgentEvalTaskClass.GENERAL,
            resourceId = json.optString("resource_id").ifBlank { "unknown" },
            verdict = AgentEvalVerdict.entries.firstOrNull {
                it.wireValue == json.optString("verdict")
            } ?: AgentEvalVerdict.UNVERIFIED,
            contractSatisfied = json.optBoolean("contract_satisfied"),
            verified = json.optBoolean("verified"),
            durationMillis = json.optLong("duration_millis").coerceAtLeast(0L),
            reportedCostMicros = json.optLong("reported_cost_micros").coerceAtLeast(0L),
            batteryDeltaPercent = json.optInt("battery_delta_percent").coerceAtLeast(0),
            chargeConsumedMicroAh = json.optLong("charge_consumed_micro_ah").coerceAtLeast(0L),
            energyConsumedNanoWh = json.optLong("energy_consumed_nano_wh").coerceAtLeast(0L),
            peakThermalStatus = json.optInt("peak_thermal_status", -1),
            memoryDeltaBytes = json.optLong("memory_delta_bytes").coerceAtLeast(0L),
            recoveryAttempted = json.optBoolean("recovery_attempted"),
            recovered = json.optBoolean("recovered"),
            condition = AgentEvalCondition.entries.firstOrNull {
                it.wireValue == json.optString("condition")
            } ?: AgentEvalCondition.NORMAL,
            observedConditions = json.optJSONArray("observed_conditions").strings()
                .mapNotNull { wire -> AgentEvalCondition.entries.firstOrNull { it.wireValue == wire } }
                .toSet()
                .ifEmpty {
                    setOfNotNull(AgentEvalCondition.entries.firstOrNull {
                        it.wireValue == json.optString("condition") && it != AgentEvalCondition.NORMAL
                    })
                },
            memoryHorizonDays = json.optInt("memory_horizon_days").coerceIn(0, 3650),
            proactiveRelevant = json.optNullableBoolean("proactive_relevant"),
            proactiveAccepted = json.optNullableBoolean("proactive_accepted"),
            failureReasons = json.optJSONArray("failure_reasons").strings(),
            evidenceKinds = json.optJSONArray("evidence_kinds").strings()
                .mapNotNull { wire -> AgentOutcomeEvidenceKind.entries.firstOrNull { it.wireValue == wire } }
                .toSet(),
            completedAtMillis = json.optLong("completed_at_millis")
        )
    }.getOrNull()

    private fun startKey(runId: String) = "$START_PREFIX$runId"
    private fun sampleKey(runId: String) = "$SAMPLE_PREFIX$runId"
    fun proactiveRunId(messageId: String): String = "proactive:${messageId.trim()}"

    private fun JSONArray?.strings(): List<String> = buildList {
        val array = this@strings ?: return@buildList
        for (index in 0 until array.length()) {
            array.optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
        }
    }

    private fun JSONObject.optNullableBoolean(key: String): Boolean? =
        if (!has(key) || isNull(key)) null else optBoolean(key)

    private companion object {
        const val DATABASE = "signalasi_agent_evalops_v1"
        const val KEY_SETTINGS = "settings"
        const val START_PREFIX = "start:"
        const val SAMPLE_PREFIX = "sample:"
        const val MAX_SAMPLES = 5_000
    }
}

object AgentDeviceEvalProbe {
    fun capture(context: Context): AgentDeviceEvalSnapshot {
        val app = context.applicationContext
        val battery = app.getSystemService(BatteryManager::class.java)
        val power = app.getSystemService(PowerManager::class.java)
        val activity = app.getSystemService(ActivityManager::class.java)
        val connectivity = app.getSystemService(ConnectivityManager::class.java)
        val batteryIntent = app.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val percent = if (level >= 0 && scale > 0) level * 100 / scale else -1
        val memory = ActivityManager.MemoryInfo().also { activity?.getMemoryInfo(it) }
        val network = connectivity?.activeNetwork?.let { connectivity.getNetworkCapabilities(it) }
        return AgentDeviceEvalSnapshot(
            capturedAtMillis = System.currentTimeMillis(),
            elapsedRealtimeMillis = SystemClock.elapsedRealtime(),
            batteryPercent = percent,
            chargeCounterMicroAh = battery?.getLongProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
                ?.coerceAtLeast(0L) ?: 0L,
            energyCounterNanoWh = battery?.getLongProperty(BatteryManager.BATTERY_PROPERTY_ENERGY_COUNTER)
                ?.coerceAtLeast(0L) ?: 0L,
            thermalStatus = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                power?.currentThermalStatus ?: -1
            } else -1,
            availableMemoryBytes = memory.availMem.coerceAtLeast(0L),
            lowMemory = memory.lowMemory,
            powerSaveMode = power?.isPowerSaveMode == true,
            deviceIdleMode = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && power?.isDeviceIdleMode == true,
            networkAvailable = network?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true,
            networkValidated = network?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
        )
    }
}

object AgentEvalOpsService {
    fun observeRunStarted(
        context: Context,
        run: AgentRecordedRun,
        conditionOverride: AgentEvalCondition = AgentEvalCondition.NORMAL
    ) {
        val store = AgentEvalOpsStore(context)
        if (!store.settings().captureRealRuns) return
        val compiled = AgentOutcomeContractCompiler.compile(run.runId, run.originalRequest)
        val contract = if (conditionOverride == AgentEvalCondition.NORMAL) compiled else compiled.copy(
            condition = conditionOverride,
            requiredEvidence = compiled.requiredEvidence + AgentOutcomeEvidenceKind.RECOVERY_EVENT,
            successCriteria = (compiled.successCriteria +
                "Recover from ${conditionOverride.wireValue} without duplicating the final result").distinct()
        )
        store.saveStart(AgentEvalRunStart(run.runId, contract, AgentDeviceEvalProbe.capture(context)))
    }

    fun observeRunInterrupted(
        context: Context,
        runId: String,
        condition: AgentEvalCondition,
        reason: String
    ): AgentEvalSample? {
        val labManaged = AgentLabStore(context).campaignForRun(runId) != null
        val recorder = AgentRunRecorder(context)
        val running = recorder.run(runId)?.takeIf { it.status == AgentRecordedRunStatus.RUNNING } ?: return null
        val store = AgentEvalOpsStore(context)
        val currentStart = store.start(runId)
        val contract = (currentStart?.contract ?: AgentOutcomeContractCompiler.compile(runId, running.originalRequest))
            .copy(
                condition = condition,
                requiredEvidence = (currentStart?.contract?.requiredEvidence.orEmpty() +
                    AgentOutcomeEvidenceKind.RECOVERY_EVENT),
                successCriteria = ((currentStart?.contract?.successCriteria.orEmpty()) +
                    "Recover from ${condition.wireValue} without duplicating the final result").distinct()
            )
        store.saveStart(AgentEvalRunStart(
            runId = runId,
            contract = contract,
            device = currentStart?.device ?: AgentDeviceEvalProbe.capture(context).copy(
                capturedAtMillis = running.createdAtMillis,
                elapsedRealtimeMillis = 0L
            )
        ))
        AgentRunEventStore(context).appendNext(AgentRunControlEvent(
            conversationId = running.conversationId,
            messageId = running.runId,
            taskId = running.taskThreadId,
            runId = running.runId,
            agentId = running.executionResourceId,
            deviceId = "",
            type = AgentRunControlEventType.RUN_FAILED,
            sequence = 0L,
            payload = mapOf(
                "condition" to condition.wireValue,
                "reason" to reason.trim().take(1_024),
                "recoverable" to true
            )
        ))
        val interrupted = recorder.markInterrupted(runId, reason) ?: return null
        if (labManaged) {
            store.discardStart(runId)
            return null
        }
        return observeRunCompleted(context, interrupted)
    }

    fun observeConditionEntered(
        context: Context,
        condition: AgentEvalCondition,
        reason: String
    ): Int {
        if (condition == AgentEvalCondition.NORMAL) return 0
        val store = AgentEvalOpsStore(context)
        val recorder = AgentRunRecorder(context)
        val runningById = recorder.runningRuns().associateBy(AgentRecordedRun::runId)
        var recorded = 0
        store.activeStarts().forEach { start ->
            val run = runningById[start.runId] ?: return@forEach
            store.saveStart(start.copy(contract = start.contract.copy(
                condition = condition,
                requiredEvidence = start.contract.requiredEvidence + AgentOutcomeEvidenceKind.RECOVERY_EVENT,
                successCriteria = (start.contract.successCriteria +
                    "Recover from ${condition.wireValue} without duplicating the final result").distinct()
            )))
            AgentRunEventStore(context).appendNext(AgentRunControlEvent(
                conversationId = run.conversationId,
                messageId = run.runId,
                taskId = run.taskThreadId,
                runId = run.runId,
                agentId = run.executionResourceId,
                deviceId = "",
                type = AgentRunControlEventType.RETRYING,
                sequence = 0L,
                payload = mapOf(
                    "condition" to condition.wireValue,
                    "reason" to reason.trim().take(1_024)
                )
            ))
            recorded += 1
        }
        return recorded
    }

    fun observeConditionRecovered(
        context: Context,
        condition: AgentEvalCondition,
        reason: String
    ): Int {
        if (condition == AgentEvalCondition.NORMAL) return 0
        val store = AgentEvalOpsStore(context)
        val recorder = AgentRunRecorder(context)
        val runningById = recorder.runningRuns().associateBy(AgentRecordedRun::runId)
        var recorded = 0
        store.activeStarts().filter { it.contract.condition == condition }.forEach { start ->
            val run = runningById[start.runId] ?: return@forEach
            AgentRunEventStore(context).appendNext(AgentRunControlEvent(
                conversationId = run.conversationId,
                messageId = run.runId,
                taskId = run.taskThreadId,
                runId = run.runId,
                agentId = run.executionResourceId,
                deviceId = "",
                type = AgentRunControlEventType.RUN_RECOVERED,
                sequence = 0L,
                payload = mapOf(
                    "condition" to condition.wireValue,
                    "reason" to reason.trim().take(1_024)
                )
            ))
            recorded += 1
        }
        return recorded
    }

    fun observeRunCompleted(context: Context, run: AgentRecordedRun): AgentEvalSample? {
        val store = AgentEvalOpsStore(context)
        if (!store.settings().captureRealRuns || store.sample(run.runId) != null) return null
        val start = store.start(run.runId) ?: AgentEvalRunStart(
            runId = run.runId,
            contract = AgentOutcomeContractCompiler.compile(run.runId, run.originalRequest),
            device = AgentDeviceEvalProbe.capture(context).copy(
                capturedAtMillis = run.createdAtMillis,
                elapsedRealtimeMillis = 0L
            )
        )
        val answeredAtMillis = run.completedAtMillis.takeIf { it > 0L } ?: System.currentTimeMillis()
        val memoryTrust = AgentMemoryTrustStore(context)
        val memoryTurnId = run.taskThreadId.takeIf {
            run.conversationId.startsWith(AgentContinuousEvalPolicy.AGENT_LAB_CONVERSATION_PREFIX)
        }.orEmpty()
        val requiresMemoryProvenance = AgentOutcomeEvidenceKind.MEMORY_PROVENANCE in
            start.contract.requiredEvidence
        val hasPendingMemory = memoryTrust.hasPendingSelection(
            conversationId = run.conversationId,
            turnId = memoryTurnId,
            query = run.originalRequest
        )
        if (requiresMemoryProvenance || hasPendingMemory) {
            memoryTrust.attachAnswer(
                conversationId = run.conversationId,
                runId = run.runId,
                answer = finalText(run.finalOutputJson),
                query = run.originalRequest,
                turnId = memoryTurnId,
                answeredAtMillis = answeredAtMillis
            )
        }
        val memoryProvenanceVerified = requiresMemoryProvenance && memoryTrust.verifiedUsageForRun(
            runId = run.runId,
            requiredHorizonDays = start.contract.memoryHorizonDays,
            answeredAtMillis = answeredAtMillis
        ) != null
        val completedDevice = AgentDeviceEvalProbe.capture(context)
        val events = runCatching { AgentRunEventStore(context).events(run.runId) }.getOrDefault(emptyList())
        val assessed = assess(start, completedDevice, run, events, memoryProvenanceVerified)
        val androidWorldStore = AgentAndroidWorldStore(context)
        val programmatic = androidWorldStore.resultForRun(run.runId)
            ?: if (
                run.originalRequest.contains("[androidworld:", ignoreCase = true) ||
                !run.originalRequest.contains("[evalops:", ignoreCase = true)
            ) AgentAndroidWorldBridge(context).evaluateMatching(run) else null
        val sample = if (programmatic == null) assessed else {
            val blockingFailures = assessed.failureReasons.filterNot { it.startsWith("missing_evidence:") }
            val verifierFailures = programmatic.verifierResults.filterNot(AgentAndroidWorldVerifierResult::passed)
                .map { "android_world_verifier:${it.reason}" }
            val passed = programmatic.passed && blockingFailures.isEmpty()
            assessed.copy(
                verdict = if (passed) AgentEvalVerdict.PASSED else AgentEvalVerdict.FAILED,
                contractSatisfied = passed,
                verified = true,
                failureReasons = blockingFailures + verifierFailures,
                evidenceKinds = assessed.evidenceKinds + AgentOutcomeEvidenceKind.PROGRAMMATIC_VERIFIER +
                    AgentOutcomeEvidenceKind.TOOL_RECEIPT
            )
        }
        store.saveSample(sample)
        AgentEvolutionLabService.observe(context, sample)
        AgentBenchmarkService.observe(context, run, sample)
        if (AgentEvalSideEffectPolicy.allowsPersonalLearning(run.conversationId)) {
            AgentTrajectoryLearningService.observe(context, run, sample)
            AgentContinuousEvalCoordinator.observeCompletedRun(context, run, sample)
        }
        return sample
    }

    fun dashboard(context: Context): AgentEvalDashboard = AgentEvalOpsStore(context).dashboard()

    internal fun assess(
        start: AgentEvalRunStart,
        completedDevice: AgentDeviceEvalSnapshot,
        run: AgentRecordedRun,
        events: List<AgentRunControlEvent>,
        memoryProvenanceVerified: Boolean = false
    ): AgentEvalSample {
        val contract = start.contract
        val evidence = collectEvidence(run, events, memoryProvenanceVerified)
        val duration = (run.completedAtMillis - run.createdAtMillis).coerceAtLeast(0L)
        val reasons = buildList {
            if (run.status != AgentRecordedRunStatus.COMPLETED) add("run_status:${run.status.name.lowercase(Locale.ROOT)}")
            runFailureCode(run)?.let { add("run_failure:$it") }
            val missing = contract.requiredEvidence - evidence
            missing.forEach { add("missing_evidence:${it.wireValue}") }
            if (duration > contract.maxDurationMillis) add("duration_budget_exceeded")
            if (contract.maxReportedCostMicros > 0L && reportedCostMicros(run) > contract.maxReportedCostMicros) {
                add("cost_budget_exceeded")
            }
            val resource = run.executionResourceId.lowercase(Locale.ROOT)
            contract.forbiddenResources.filter(resource::contains).forEach { add("forbidden_resource:$it") }
            if (contract.allowedResources.isNotEmpty() && contract.allowedResources.none(resource::contains)) {
                add("resource_not_allowed")
            }
        }
        val contractSatisfied = reasons.isEmpty()
        val verdict = when {
            contractSatisfied -> AgentEvalVerdict.PASSED
            run.status == AgentRecordedRunStatus.COMPLETED && evidence.isNotEmpty() -> AgentEvalVerdict.PARTIAL
            run.status == AgentRecordedRunStatus.RUNNING -> AgentEvalVerdict.UNVERIFIED
            else -> AgentEvalVerdict.FAILED
        }
        val recoveryAttempted = contract.condition != AgentEvalCondition.NORMAL || events.any {
            it.type == AgentRunControlEventType.RETRYING || it.type == AgentRunControlEventType.RUN_RECOVERED
        }
        val recovered = events.any { it.type == AgentRunControlEventType.RUN_RECOVERED } &&
            run.status == AgentRecordedRunStatus.COMPLETED
        val observedConditions = observedConditions(contract, events)
        return AgentEvalSample(
            runId = run.runId,
            scenarioId = AgentLearningAnalyzer.stableKey(run.originalRequest),
            taskClass = contract.taskClass,
            resourceId = run.executionResourceId.ifBlank { "signalasi-mobile" },
            verdict = verdict,
            contractSatisfied = contractSatisfied,
            verified = contract.requiredEvidence.all(evidence::contains),
            durationMillis = duration,
            reportedCostMicros = reportedCostMicros(run),
            batteryDeltaPercent = positiveDelta(start.device.batteryPercent, completedDevice.batteryPercent),
            chargeConsumedMicroAh = positiveDelta(start.device.chargeCounterMicroAh, completedDevice.chargeCounterMicroAh),
            energyConsumedNanoWh = positiveDelta(
                start.device.energyCounterNanoWh,
                completedDevice.energyCounterNanoWh
            ),
            peakThermalStatus = maxOf(start.device.thermalStatus, completedDevice.thermalStatus),
            memoryDeltaBytes = positiveDelta(start.device.availableMemoryBytes, completedDevice.availableMemoryBytes),
            recoveryAttempted = recoveryAttempted,
            recovered = recovered,
            condition = contract.condition,
            observedConditions = observedConditions,
            memoryHorizonDays = contract.memoryHorizonDays,
            failureReasons = reasons,
            evidenceKinds = evidence,
            completedAtMillis = run.completedAtMillis.takeIf { it > 0L } ?: System.currentTimeMillis()
        )
    }

    internal fun observedConditions(
        contract: AgentOutcomeContract,
        events: List<AgentRunControlEvent>
    ): Set<AgentEvalCondition> = buildSet {
        events.forEach { event ->
            val wire = event.payload["condition"]?.toString().orEmpty()
            AgentEvalCondition.entries.firstOrNull { it.wireValue == wire }
                ?.takeIf { it != AgentEvalCondition.NORMAL }
                ?.let(::add)
        }
    }

    private fun collectEvidence(
        run: AgentRecordedRun,
        events: List<AgentRunControlEvent>,
        memoryProvenanceVerified: Boolean
    ): Set<AgentOutcomeEvidenceKind> = buildSet {
        if (finalText(run.finalOutputJson).isNotBlank()) add(AgentOutcomeEvidenceKind.FINAL_RESPONSE)
        if (run.toolCalls.any { call ->
                call.status == AgentToolCallStatus.SUCCEEDED &&
                    (call.toolName != AgentOnDeviceRuntimeTools.EXECUTE ||
                        AgentLearningAnalyzer.hasTrustedExecutionEvidence(call))
            }) add(AgentOutcomeEvidenceKind.TOOL_RECEIPT)
        if (run.artifacts.any(::artifactHasDigest)) add(AgentOutcomeEvidenceKind.ARTIFACT_DIGEST)
        if (runCatching { JSONArray(run.sourcesJson).length() > 0 }.getOrDefault(false)) {
            add(AgentOutcomeEvidenceKind.VERIFIED_SOURCE)
        }
        if (events.any { it.type == AgentRunControlEventType.RUN_RECOVERED }) {
            add(AgentOutcomeEvidenceKind.RECOVERY_EVENT)
        }
        if (memoryProvenanceVerified && run.status == AgentRecordedRunStatus.COMPLETED) {
            add(AgentOutcomeEvidenceKind.MEMORY_PROVENANCE)
        }
        if (run.userFeedback.any { feedback ->
                val normalized = feedback.lowercase(Locale.ROOT)
                POSITIVE_FEEDBACK.any(normalized::contains)
            }) add(AgentOutcomeEvidenceKind.USER_ACCEPTANCE)
    }

    private fun finalText(raw: String): String = runCatching {
        val json = JSONObject(raw)
        sequenceOf("text", "message", "content", "result")
            .map(json::optString)
            .firstOrNull(String::isNotBlank)
            .orEmpty()
    }.getOrDefault("")

    private fun runFailureCode(run: AgentRecordedRun): String? = runCatching {
        JSONObject(run.finalOutputJson).optString("failure_code")
            .trim()
            .takeIf(String::isNotBlank)
    }.getOrNull()

    private fun artifactHasDigest(artifact: AgentArtifactReference): Boolean {
        val value = "${artifact.id}\n${artifact.uri}\n${artifact.metadataJson}".lowercase(Locale.ROOT)
        return SHA256.containsMatchIn(value)
    }

    private fun reportedCostMicros(run: AgentRecordedRun): Long {
        val payloads = listOf(run.finalOutputJson, run.sourcesJson, run.renderSpecJson)
        return payloads.maxOfOrNull { raw ->
            runCatching {
                val normalized = raw.trim()
                if (normalized.startsWith("[")) {
                    val array = JSONArray(normalized)
                    (0 until array.length()).maxOfOrNull { index ->
                        array.optJSONObject(index)?.reportedCostMicros() ?: 0L
                    } ?: 0L
                } else JSONObject(normalized).reportedCostMicros()
            }.getOrDefault(0L)
        } ?: 0L
    }

    private fun JSONObject.reportedCostMicros(): Long {
        val direct = sequenceOf("reported_cost_micros", "cost_micros", "actual_cost_micros")
            .map { key -> optLong(key) }
            .maxOrNull() ?: 0L
        var nested = 0L
        keys().forEach { key ->
            when (val value = opt(key)) {
                is JSONObject -> nested = maxOf(nested, value.reportedCostMicros())
                is JSONArray -> for (index in 0 until value.length()) {
                    nested = maxOf(nested, value.optJSONObject(index)?.reportedCostMicros() ?: 0L)
                }
            }
        }
        return maxOf(direct, nested)
    }

    private fun positiveDelta(start: Int, end: Int): Int =
        if (start < 0 || end < 0) 0 else (start - end).coerceAtLeast(0)

    private fun positiveDelta(start: Long, end: Long): Long =
        if (start <= 0L || end <= 0L) 0L else (start - end).coerceAtLeast(0L)

    private val SHA256 = Regex("(?i)[0-9a-f]{64}")
    private val POSITIVE_FEEDBACK = listOf("good", "correct", "works", "passed", "可以", "正确", "很好", "通过")
}

internal object AgentEvalSideEffectPolicy {
    const val SYNTHETIC_CONVERSATION_ID = "agent-evalops"

    fun allowsPersonalLearning(conversationId: String): Boolean =
        !conversationId.startsWith(AgentContinuousEvalPolicy.AGENT_LAB_CONVERSATION_PREFIX)
}
