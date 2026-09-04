package com.galaxyssi.chat

import java.util.UUID

enum class AgentBenchmarkDimension(val wireValue: String) {
    TASK_QUALITY("task_quality"),
    PLANNING_AND_TOOLS("planning_and_tools"),
    ANDROID_WORLD("android_world"),
    IMMEDIATE_MEMORY("immediate_memory"),
    LONG_TERM_MEMORY("long_term_memory"),
    RECOVERY("recovery"),
    MULTI_AGENT("multi_agent")
}

data class AgentBenchmarkExpectation(
    val requiredOutputPatterns: List<String> = emptyList(),
    val requiredJsonFields: Map<String, String> = emptyMap(),
    val forbiddenOutputPatterns: List<String> = emptyList(),
    val minimumOutputChars: Int = 1,
    val minimumPlanEvents: Int = 0,
    val minimumToolReceipts: Int = 0,
    val minimumVerifiedSources: Int = 0,
    val minimumDistinctAgents: Int = 1,
    val minimumHandoffs: Int = 0,
    val requiredEvidence: Set<AgentOutcomeEvidenceKind> = setOf(AgentOutcomeEvidenceKind.FINAL_RESPONSE),
    val requiredCondition: AgentEvalCondition = AgentEvalCondition.NORMAL,
    val memoryHorizonDays: Int = 0,
    val androidWorldTaskId: String = "",
    val requireAndroidObservedValuesInOutput: Boolean = false
)

data class AgentBenchmarkCase(
    val id: String,
    val dimension: AgentBenchmarkDimension,
    val title: String,
    val prompt: String,
    val expectation: AgentBenchmarkExpectation,
    val critical: Boolean = true
) {
    val taggedPrompt: String get() = buildString {
        append("[evalops:").append(id).append("] ").append(prompt.trim())
        if (expectation.androidWorldTaskId.isNotBlank()) {
            append(" [androidworld:").append(expectation.androidWorldTaskId).append(']')
        }
    }
}

data class AgentBenchmarkSuite(
    val id: String,
    val version: String,
    val title: String,
    val cases: List<AgentBenchmarkCase>,
    val targetPassRate: Double = 0.90,
    val minimumTaskCount: Int = 50,
    val maximumTaskCount: Int = 100,
    val minimumRepetitions: Int = 3,
    val maximumRepetitions: Int = 10
) {
    init {
        require(cases.size in minimumTaskCount..maximumTaskCount)
        require(cases.map(AgentBenchmarkCase::id).distinct().size == cases.size)
        require(targetPassRate in 0.0..1.0)
    }

    fun case(id: String): AgentBenchmarkCase? = cases.firstOrNull { it.id == id }
}

data class AgentBenchmarkResourceSnapshot(
    val resourceId: String,
    val displayName: String,
    val providerId: String,
    val modelId: String,
    val adapterType: String,
    val capabilitiesHash: String
)

enum class AgentBenchmarkReadinessStatus { READY, WAITING, BLOCKED }

data class AgentBenchmarkCaseReadiness(
    val caseId: String,
    val status: AgentBenchmarkReadinessStatus,
    val reasonCode: String = "",
    val eligibleAtMillis: Long = 0L
)

enum class AgentBenchmarkSessionStatus { RUNNING, COMPLETED, CANCELLED }

data class AgentBenchmarkSession(
    val id: String = UUID.randomUUID().toString(),
    val suiteId: String,
    val suiteVersion: String,
    val appVersionName: String,
    val appVersionCode: Long,
    val deviceModel: String,
    val repetitions: Int,
    val targetPassRate: Double,
    val caseIds: List<String>,
    val resources: List<AgentBenchmarkResourceSnapshot>,
    val resourceIdsByCase: Map<String, List<String>>,
    val campaignIdsByCase: Map<String, String>,
    val teamResourceIdsByCase: Map<String, List<String>> = emptyMap(),
    val readinessByCase: Map<String, AgentBenchmarkCaseReadiness> = emptyMap(),
    val allocationProfile: String = "codex_90_deepseek_10",
    val status: AgentBenchmarkSessionStatus = AgentBenchmarkSessionStatus.RUNNING,
    val createdAtMillis: Long = System.currentTimeMillis(),
    val updatedAtMillis: Long = createdAtMillis
) {
    val scheduledCaseIds: List<String> get() = if (readinessByCase.isEmpty()) {
        caseIds
    } else {
        caseIds.filter { readinessByCase[it]?.status == AgentBenchmarkReadinessStatus.READY }
    }
    val expectedTrials: Int get() = scheduledCaseIds.sumOf {
        resourceIdsByCase[it].orEmpty().size
    } * repetitions
}

data class AgentBenchmarkTrialResult(
    val id: String = UUID.randomUUID().toString(),
    val sessionId: String,
    val caseId: String,
    val campaignId: String,
    val trialId: String,
    val runId: String,
    val resourceId: String,
    val repetition: Int,
    val passed: Boolean,
    val verified: Boolean,
    val failureReasons: List<String>,
    val durationMillis: Long,
    val reportedCostMicros: Long,
    val batteryDeltaPercent: Int,
    val peakThermalStatus: Int,
    val completedAtMillis: Long = System.currentTimeMillis()
)

data class AgentBenchmarkMetric(
    val dimension: AgentBenchmarkDimension?,
    val taskCount: Int,
    val coveredTaskCount: Int,
    val expectedTrials: Int,
    val completedTrials: Int,
    val verifiedTrials: Int,
    val passAt1: Double?,
    val passPowerK: Double?,
    val averageLatencyMillis: Long,
    val averageReportedCostMicros: Long,
    val averageBatteryDeltaPercent: Double,
    val peakThermalStatus: Int,
    val qualified: Boolean,
    val targetMet: Boolean,
    val passedTrials: Int = 0,
    val capabilityFailureTrials: Int = 0,
    val infrastructureFailureTrials: Int = 0,
    val waitingForRealConditionTrials: Int = 0,
    val evaluableTrials: Int = 0,
    val evaluableTaskCount: Int = 0,
    val certificationComplete: Boolean = false,
    val plannedTrials: Int = expectedTrials,
    val notExecutedTrials: Int = 0,
    val blockedTrials: Int = 0,
    val certificationCoverage: Double? = null
)

data class AgentBenchmarkTrialEvidence(
    val caseId: String,
    val caseTitle: String,
    val dimension: AgentBenchmarkDimension,
    val resourceName: String,
    val repetition: Int,
    val classification: AgentBenchmarkTrialClassification,
    val failureReasons: List<String>,
    val rawOutput: String,
    val planEventCount: Int,
    val toolReceipts: List<String>,
    val androidWorldEvidence: List<String>,
    val runId: String
)

data class AgentBenchmarkResourceScore(
    val resource: AgentBenchmarkResourceSnapshot,
    val overall: AgentBenchmarkMetric,
    val dimensions: List<AgentBenchmarkMetric>
)

data class AgentBenchmarkScorecard(
    val session: AgentBenchmarkSession,
    val overall: AgentBenchmarkMetric,
    val dimensions: List<AgentBenchmarkMetric>,
    val resources: List<AgentBenchmarkResourceScore>,
    val generatedAtMillis: Long = System.currentTimeMillis()
)

data class AgentBenchmarkProgress(
    val completedTrials: Int,
    val expectedTrials: Int,
    val completedCampaigns: Int,
    val totalCampaigns: Int,
    val terminal: Boolean
)
