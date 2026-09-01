package com.signalasi.chat

import java.util.Locale
import java.util.UUID
import kotlin.math.pow

enum class AgentEvalTaskClass(val wireValue: String) {
    GENERAL("general"),
    CODE("code"),
    RESEARCH("research"),
    DEVICE_CONTROL("device_control"),
    AUTOMATION("automation"),
    MEMORY("memory"),
    PROACTIVE("proactive"),
    RELIABILITY("reliability")
}

enum class AgentEvalCondition(val wireValue: String) {
    NORMAL("normal"),
    DOZE("doze"),
    REBOOT("reboot"),
    NETWORK_LOSS("network_loss"),
    PROCESS_DEATH("process_death")
}

enum class AgentOutcomeEvidenceKind(val wireValue: String) {
    FINAL_RESPONSE("final_response"),
    TOOL_RECEIPT("tool_receipt"),
    ARTIFACT_DIGEST("artifact_digest"),
    VERIFIED_SOURCE("verified_source"),
    RECOVERY_EVENT("recovery_event"),
    MEMORY_PROVENANCE("memory_provenance"),
    USER_ACCEPTANCE("user_acceptance")
}

enum class AgentEvalVerdict(val wireValue: String) {
    PASSED("passed"),
    FAILED("failed"),
    PARTIAL("partial"),
    UNVERIFIED("unverified")
}

data class AgentOutcomeContract(
    val id: String = UUID.randomUUID().toString(),
    val runId: String,
    val goal: String,
    val taskClass: AgentEvalTaskClass,
    val successCriteria: List<String>,
    val allowedResources: Set<String> = emptySet(),
    val forbiddenResources: Set<String> = emptySet(),
    val requiredEvidence: Set<AgentOutcomeEvidenceKind>,
    val maxDurationMillis: Long,
    val maxReportedCostMicros: Long = 0L,
    val memoryHorizonDays: Int = 0,
    val condition: AgentEvalCondition = AgentEvalCondition.NORMAL,
    val createdAtMillis: Long = System.currentTimeMillis()
)

data class AgentDeviceEvalSnapshot(
    val capturedAtMillis: Long,
    val elapsedRealtimeMillis: Long,
    val batteryPercent: Int = -1,
    val chargeCounterMicroAh: Long = 0L,
    val energyCounterNanoWh: Long = 0L,
    val thermalStatus: Int = -1,
    val availableMemoryBytes: Long = 0L,
    val lowMemory: Boolean = false,
    val powerSaveMode: Boolean = false,
    val deviceIdleMode: Boolean = false,
    val networkAvailable: Boolean = false,
    val networkValidated: Boolean = false
)

data class AgentEvalRunStart(
    val runId: String,
    val contract: AgentOutcomeContract,
    val device: AgentDeviceEvalSnapshot
)

data class AgentEvalSample(
    val id: String = UUID.randomUUID().toString(),
    val runId: String,
    val scenarioId: String,
    val taskClass: AgentEvalTaskClass,
    val resourceId: String,
    val verdict: AgentEvalVerdict,
    val contractSatisfied: Boolean,
    val verified: Boolean,
    val durationMillis: Long,
    val reportedCostMicros: Long = 0L,
    val batteryDeltaPercent: Int = 0,
    val chargeConsumedMicroAh: Long = 0L,
    val energyConsumedNanoWh: Long = 0L,
    val peakThermalStatus: Int = -1,
    val memoryDeltaBytes: Long = 0L,
    val recoveryAttempted: Boolean = false,
    val recovered: Boolean = false,
    val condition: AgentEvalCondition = AgentEvalCondition.NORMAL,
    val memoryHorizonDays: Int = 0,
    val proactiveRelevant: Boolean? = null,
    val proactiveAccepted: Boolean? = null,
    val failureReasons: List<String> = emptyList(),
    val evidenceKinds: Set<AgentOutcomeEvidenceKind> = emptySet(),
    val completedAtMillis: Long = System.currentTimeMillis()
) {
    val passed: Boolean get() = verdict == AgentEvalVerdict.PASSED
}

data class AgentEvalResourceSummary(
    val resourceId: String,
    val taskClass: AgentEvalTaskClass,
    val verifiedRuns: Int,
    val passAt1: Double,
    val passPowerK: Double,
    val averageLatencyMillis: Long,
    val p95LatencyMillis: Long,
    val averageReportedCostMicros: Long,
    val averageBatteryDeltaPercent: Double,
    val peakThermalStatus: Int,
    val recoveryRate: Double,
    val memoryAccuracy: Double?,
    val proactiveHitRate: Double?,
    val proactiveDisturbanceRate: Double?
)

data class AgentEvalDashboard(
    val totalRuns: Int,
    val verifiedRuns: Int,
    val passAt1: Double,
    val passPowerK: Double,
    val averageLatencyMillis: Long,
    val recoveryRate: Double,
    val memory30DayAccuracy: Double?,
    val memory90DayAccuracy: Double?,
    val proactiveHitRate: Double?,
    val proactiveDisturbanceRate: Double?,
    val resources: List<AgentEvalResourceSummary>,
    val generatedAtMillis: Long = System.currentTimeMillis()
)

data class AgentEvalOpsSettings(
    val captureRealRuns: Boolean = true,
    val continuousEvaluationEnabled: Boolean = false,
    val repeatedTrials: Int = 3,
    val shadowRoutingEnabled: Boolean = true,
    val automaticQualityRoutingEnabled: Boolean = false,
    val minimumAutomaticRoutingSamples: Int = 12,
    val attentionThreshold: Double = 0.58,
    val skillMarkdownCompatibilityEnabled: Boolean = true,
    val protocolAdaptersEnabled: Boolean = true,
    val shadowReleaseEnabled: Boolean = true
) {
    fun normalized(): AgentEvalOpsSettings = copy(
        repeatedTrials = repeatedTrials.coerceIn(2, 10),
        minimumAutomaticRoutingSamples = minimumAutomaticRoutingSamples.coerceIn(6, 100),
        attentionThreshold = attentionThreshold.coerceIn(0.0, 1.0)
    )
}

object AgentOutcomeContractCompiler {
    fun compile(runId: String, goal: String): AgentOutcomeContract {
        val cleanGoal = goal.trim().take(4_000)
        val requirements = AgentTaskRequirementAnalyzer.analyze(cleanGoal)
        val taskClass = classify(cleanGoal, requirements)
        val condition = condition(cleanGoal)
        val requiredEvidence = buildSet {
            add(AgentOutcomeEvidenceKind.FINAL_RESPONSE)
            if (requirements.capabilities.any { it in TOOL_CAPABILITIES }) {
                add(AgentOutcomeEvidenceKind.TOOL_RECEIPT)
            }
            if (taskClass == AgentEvalTaskClass.CODE) add(AgentOutcomeEvidenceKind.ARTIFACT_DIGEST)
            if (taskClass == AgentEvalTaskClass.RESEARCH) add(AgentOutcomeEvidenceKind.VERIFIED_SOURCE)
            if (taskClass == AgentEvalTaskClass.MEMORY) add(AgentOutcomeEvidenceKind.MEMORY_PROVENANCE)
            if (condition != AgentEvalCondition.NORMAL) add(AgentOutcomeEvidenceKind.RECOVERY_EVENT)
        }
        val horizonDays = memoryHorizonDays(cleanGoal)
        val maxDuration = when (requirements.executionHorizon) {
            AgentExecutionHorizon.INTERACTIVE -> 15L * 60_000L
            AgentExecutionHorizon.BACKGROUND -> 2L * 60L * 60_000L
            AgentExecutionHorizon.LONG_RUNNING -> 24L * 60L * 60_000L
        }
        return AgentOutcomeContract(
            runId = runId,
            goal = cleanGoal,
            taskClass = taskClass,
            successCriteria = criteria(taskClass, condition),
            forbiddenResources = if (requirements.localOnly) setOf("cloud") else emptySet(),
            requiredEvidence = requiredEvidence,
            maxDurationMillis = maxDuration,
            memoryHorizonDays = horizonDays,
            condition = condition
        )
    }

    fun classify(goal: String, requirements: AgentTaskRequirements): AgentEvalTaskClass {
        val normalized = goal.lowercase(Locale.ROOT)
        return when {
            memoryHorizonDays(goal) > 0 || MEMORY_TERMS.any(normalized::contains) -> AgentEvalTaskClass.MEMORY
            PROACTIVE_TERMS.any(normalized::contains) -> AgentEvalTaskClass.PROACTIVE
            condition(goal) != AgentEvalCondition.NORMAL -> AgentEvalTaskClass.RELIABILITY
            AgentCapability.CODE in requirements.capabilities -> AgentEvalTaskClass.CODE
            requirements.liveDataRequired || AgentCapability.KNOWLEDGE_SEARCH in requirements.capabilities ->
                AgentEvalTaskClass.RESEARCH
            AgentCapability.DEVICE_CONTROL in requirements.capabilities ||
                AgentCapability.APP_NAVIGATION in requirements.capabilities -> AgentEvalTaskClass.DEVICE_CONTROL
            requirements.executionHorizon != AgentExecutionHorizon.INTERACTIVE -> AgentEvalTaskClass.AUTOMATION
            else -> AgentEvalTaskClass.GENERAL
        }
    }

    private fun criteria(taskClass: AgentEvalTaskClass, condition: AgentEvalCondition): List<String> = buildList {
        add("Return one non-empty final result")
        when (taskClass) {
            AgentEvalTaskClass.CODE -> {
                add("Produce integrity-addressed implementation evidence")
                add("Report executable verification results")
            }
            AgentEvalTaskClass.RESEARCH -> add("Provide traceable source evidence")
            AgentEvalTaskClass.DEVICE_CONTROL -> add("Complete the requested device state change")
            AgentEvalTaskClass.AUTOMATION -> add("Complete or checkpoint every planned action")
            AgentEvalTaskClass.MEMORY -> add("Answer from provenance-linked long-term memory")
            AgentEvalTaskClass.PROACTIVE -> add("Deliver a relevant and actionable insight")
            AgentEvalTaskClass.RELIABILITY -> add("Recover without duplicating the final result")
            AgentEvalTaskClass.GENERAL -> Unit
        }
        if (condition != AgentEvalCondition.NORMAL) {
            add("Record recovery evidence for ${condition.wireValue}")
        }
    }

    private fun condition(goal: String): AgentEvalCondition {
        val normalized = goal.lowercase(Locale.ROOT)
        return when {
            listOf("doze", "idle mode", "休眠", "待机").any(normalized::contains) -> AgentEvalCondition.DOZE
            listOf("reboot", "restart phone", "重启").any(normalized::contains) -> AgentEvalCondition.REBOOT
            listOf("network loss", "disconnect network", "断网", "网络中断").any(normalized::contains) ->
                AgentEvalCondition.NETWORK_LOSS
            listOf("process death", "kill process", "进程死亡", "杀进程").any(normalized::contains) ->
                AgentEvalCondition.PROCESS_DEATH
            else -> AgentEvalCondition.NORMAL
        }
    }

    private fun memoryHorizonDays(goal: String): Int {
        val normalized = goal.lowercase(Locale.ROOT)
        return when {
            listOf("90 day", "90-day", "90天").any(normalized::contains) -> 90
            listOf("30 day", "30-day", "30天").any(normalized::contains) -> 30
            else -> 0
        }
    }

    private val TOOL_CAPABILITIES = setOf(
        AgentCapability.CODE,
        AgentCapability.DEVICE_CONTROL,
        AgentCapability.APP_NAVIGATION,
        AgentCapability.KNOWLEDGE_SEARCH,
        AgentCapability.MCP,
        AgentCapability.SKILL
    )
    private val MEMORY_TERMS = listOf("memory", "remember", "recall", "长期记忆", "记住", "回忆")
    private val PROACTIVE_TERMS = listOf("proactive", "insight", "主动提示", "主动发现", "洞察")
}

object AgentEvalStatistics {
    fun dashboard(samples: List<AgentEvalSample>, k: Int = 3): AgentEvalDashboard {
        val boundedK = k.coerceIn(2, 10)
        val verified = samples.filter(AgentEvalSample::verified)
        val resources = verified.groupBy { it.resourceId to it.taskClass }
            .map { (key, values) -> resourceSummary(key.first, key.second, values, boundedK) }
            .sortedWith(compareByDescending<AgentEvalResourceSummary> { it.passAt1 }
                .thenBy { it.averageLatencyMillis })
        return AgentEvalDashboard(
            totalRuns = samples.size,
            verifiedRuns = verified.size,
            passAt1 = ratio(verified.count(AgentEvalSample::passed), verified.size),
            passPowerK = empiricalPassPowerK(verified, boundedK),
            averageLatencyMillis = averageLong(verified.map(AgentEvalSample::durationMillis)),
            recoveryRate = recoveryRate(verified),
            memory30DayAccuracy = optionalRatio(verified.filter { it.memoryHorizonDays == 30 }),
            memory90DayAccuracy = optionalRatio(verified.filter { it.memoryHorizonDays == 90 }),
            proactiveHitRate = optionalBooleanRate(verified.mapNotNull(AgentEvalSample::proactiveRelevant)),
            proactiveDisturbanceRate = optionalBooleanRate(
                verified.filter { it.proactiveRelevant == false }.mapNotNull(AgentEvalSample::proactiveAccepted)
            ),
            resources = resources
        )
    }

    fun empiricalPassPowerK(samples: List<AgentEvalSample>, k: Int): Double {
        val boundedK = k.coerceIn(2, 10)
        val groups = samples.groupBy { it.scenarioId to it.resourceId }.values
            .flatMap { values -> values.sortedBy(AgentEvalSample::completedAtMillis).chunked(boundedK) }
            .filter { it.size == boundedK }
        if (groups.isEmpty()) return 0.0
        return ratio(groups.count { batch -> batch.all(AgentEvalSample::passed) }, groups.size)
    }

    fun theoreticalPassPowerK(passAt1: Double, k: Int): Double =
        passAt1.coerceIn(0.0, 1.0).pow(k.coerceIn(2, 10))

    private fun resourceSummary(
        resourceId: String,
        taskClass: AgentEvalTaskClass,
        samples: List<AgentEvalSample>,
        k: Int
    ): AgentEvalResourceSummary {
        val latencies = samples.map(AgentEvalSample::durationMillis).sorted()
        val memorySamples = samples.filter { it.memoryHorizonDays > 0 }
        val proactiveSamples = samples.filter { it.taskClass == AgentEvalTaskClass.PROACTIVE }
        return AgentEvalResourceSummary(
            resourceId = resourceId,
            taskClass = taskClass,
            verifiedRuns = samples.size,
            passAt1 = ratio(samples.count(AgentEvalSample::passed), samples.size),
            passPowerK = empiricalPassPowerK(samples, k),
            averageLatencyMillis = averageLong(latencies),
            p95LatencyMillis = percentile(latencies, 0.95),
            averageReportedCostMicros = averageLong(samples.map(AgentEvalSample::reportedCostMicros)),
            averageBatteryDeltaPercent = samples.map(AgentEvalSample::batteryDeltaPercent).averageOrZero(),
            peakThermalStatus = samples.maxOfOrNull(AgentEvalSample::peakThermalStatus) ?: -1,
            recoveryRate = recoveryRate(samples),
            memoryAccuracy = optionalRatio(memorySamples),
            proactiveHitRate = optionalBooleanRate(proactiveSamples.mapNotNull(AgentEvalSample::proactiveRelevant)),
            proactiveDisturbanceRate = optionalBooleanRate(
                proactiveSamples.filter { it.proactiveRelevant == false }
                    .mapNotNull(AgentEvalSample::proactiveAccepted)
            )
        )
    }

    private fun recoveryRate(samples: List<AgentEvalSample>): Double {
        val attempted = samples.filter(AgentEvalSample::recoveryAttempted)
        return if (attempted.isEmpty()) 0.0 else ratio(attempted.count(AgentEvalSample::recovered), attempted.size)
    }

    private fun optionalRatio(samples: List<AgentEvalSample>): Double? =
        samples.takeIf(List<*>::isNotEmpty)?.let { ratio(it.count(AgentEvalSample::passed), it.size) }

    private fun optionalBooleanRate(values: List<Boolean>): Double? =
        values.takeIf(List<*>::isNotEmpty)?.let { ratio(it.count { value -> value }, it.size) }

    private fun averageLong(values: List<Long>): Long =
        if (values.isEmpty()) 0L else values.sumOf { it.coerceAtLeast(0L) } / values.size

    private fun percentile(sorted: List<Long>, percentile: Double): Long {
        if (sorted.isEmpty()) return 0L
        val index = ((sorted.size - 1) * percentile.coerceIn(0.0, 1.0)).toInt()
        return sorted[index]
    }

    private fun ratio(numerator: Int, denominator: Int): Double =
        if (denominator <= 0) 0.0 else numerator.toDouble() / denominator

    private fun List<Int>.averageOrZero(): Double = if (isEmpty()) 0.0 else average()
}
