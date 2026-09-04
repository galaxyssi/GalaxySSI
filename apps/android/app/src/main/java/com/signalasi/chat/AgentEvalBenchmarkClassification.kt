package com.signalasi.chat

enum class AgentBenchmarkTrialClassification {
    PASSED,
    CAPABILITY_FAILURE,
    INFRASTRUCTURE_FAILURE,
    WAITING_FOR_REAL_CONDITION
}

object AgentBenchmarkTrialClassificationPolicy {
    fun classify(result: AgentBenchmarkTrialResult): AgentBenchmarkTrialClassification =
        classify(result.passed, result.failureReasons)

    fun classify(
        passed: Boolean,
        failureReasons: Collection<String>
    ): AgentBenchmarkTrialClassification {
        if (passed) return AgentBenchmarkTrialClassification.PASSED
        val reasons = failureReasons.map(String::trim).filter(String::isNotBlank)
        if (reasons.any(WAITING_REASONS::contains)) {
            return AgentBenchmarkTrialClassification.WAITING_FOR_REAL_CONDITION
        }
        if (reasons.any { reason -> INFRASTRUCTURE_PREFIXES.any(reason::startsWith) }) {
            return AgentBenchmarkTrialClassification.INFRASTRUCTURE_FAILURE
        }
        return AgentBenchmarkTrialClassification.CAPABILITY_FAILURE
    }

    private val WAITING_REASONS = setOf(
        "condition_not_observed",
        "memory_horizon_not_verified",
        "recovery_not_verified"
    )
    private val INFRASTRUCTURE_PREFIXES = setOf(
        "run_status:",
        "run_failure:",
        "tool_infrastructure:",
        "duration_budget_exceeded",
        "cost_budget_exceeded"
    )
}
