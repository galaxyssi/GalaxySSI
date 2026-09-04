package com.signalasi.chat

import android.app.AlertDialog
import android.widget.Toast
import java.util.Locale

internal fun MainActivity.agentBenchmarkRow(): ControlCenterRowSpec {
    val suite = AgentEvalBenchmarkCatalog.standard
    return benchmarkRow(
        suite = suite,
        actionId = "lab.benchmark",
        title = getString(R.string.cc_agent_benchmark_title),
        subtitle = getString(
            R.string.cc_agent_benchmark_subtitle,
            suite.cases.size,
            AgentEvalOpsStore(this).settings().repeatedTrials
        )
    )
}

internal fun MainActivity.longitudinalMemoryBenchmarkRow(): ControlCenterRowSpec {
    val suite = AgentEvalBenchmarkCatalog.longitudinalMemory
    return benchmarkRow(
        suite = suite,
        actionId = "lab.benchmark.longitudinal",
        title = getString(R.string.cc_agent_longitudinal_benchmark_title),
        subtitle = getString(R.string.cc_agent_longitudinal_benchmark_subtitle, suite.cases.size)
    )
}

private fun MainActivity.benchmarkRow(
    suite: AgentBenchmarkSuite,
    actionId: String,
    title: String,
    subtitle: String
): ControlCenterRowSpec {
    val coordinator = AgentBenchmarkCoordinator(this, suite)
    val latest = coordinator.latest()
    val progress = latest?.let(coordinator::progress)
    val status = when {
        latest == null -> getString(R.string.cc_agent_benchmark_not_run)
        else -> "${progress?.completedTrials ?: 0}/${progress?.expectedTrials ?: latest.expectedTrials}"
    }
    return ControlCenterRowSpec(
        actionId = actionId,
        title = title,
        subtitle = subtitle,
        iconRes = R.drawable.ic_settings_diagnostics,
        status = status,
        tone = when {
            latest != null && progress?.terminal == true -> ControlCenterTone.BLUE
            latest != null -> ControlCenterTone.BLUE
            else -> ControlCenterTone.NEUTRAL
        }
    )
}

internal fun MainActivity.showAgentBenchmarkDialog() {
    showAgentBenchmarkDialog(
        suite = AgentEvalBenchmarkCatalog.standard,
        titleRes = R.string.cc_agent_benchmark_title,
        descriptionRes = R.string.cc_agent_benchmark_description
    )
}

internal fun MainActivity.showLongitudinalMemoryBenchmarkDialog() {
    showAgentBenchmarkDialog(
        suite = AgentEvalBenchmarkCatalog.longitudinalMemory,
        titleRes = R.string.cc_agent_longitudinal_benchmark_title,
        descriptionRes = R.string.cc_agent_longitudinal_benchmark_description
    )
}

private fun MainActivity.showAgentBenchmarkDialog(
    suite: AgentBenchmarkSuite,
    titleRes: Int,
    descriptionRes: Int
) {
    val coordinator = AgentBenchmarkCoordinator(this, suite)
    val latest = coordinator.latest()
    val progress = latest?.let(coordinator::progress)
    val builder = AlertDialog.Builder(this)
        .setTitle(titleRes)
        .setMessage(latest?.let { benchmarkSummary(coordinator, it, progress!!, includeScorecard = false) }
            ?: getString(descriptionRes))
        .setNegativeButton(android.R.string.cancel, null)
    if (latest == null || progress?.terminal == true) {
        builder.setPositiveButton(R.string.cc_agent_benchmark_prepare) { _, _ ->
            confirmAgentBenchmarkStart(suite, titleRes)
        }
        if (latest != null) {
            builder.setNeutralButton(R.string.cc_agent_benchmark_details) { _, _ ->
                showAgentBenchmarkDimensionPicker(coordinator, latest)
            }
        }
    } else {
        builder.setNeutralButton(R.string.cc_agent_benchmark_cancel) { _, _ ->
            Toast.makeText(this, R.string.cc_agent_benchmark_cancelling, Toast.LENGTH_SHORT).show()
            agentEvalExecutor.execute {
                val result = runCatching { coordinator.cancel(latest.id) }
                runOnUiThread {
                    if (isFinishing || isDestroyed) return@runOnUiThread
                    result.onSuccess { showAgentEvolutionLabPage() }
                        .onFailure { error ->
                            Toast.makeText(this, error.message.orEmpty(), Toast.LENGTH_LONG).show()
                        }
                }
            }
        }
    }
    val dialog = builder.show()
    if (latest != null && progress?.terminal == true) {
        agentTaskPersistenceExecutor.execute {
            val summary = benchmarkSummary(coordinator, latest, progress, includeScorecard = true)
            runOnUiThread {
                if (!isFinishing && !isDestroyed && dialog.isShowing) dialog.setMessage(summary)
            }
        }
    }
}

private fun MainActivity.confirmAgentBenchmarkStart(suite: AgentBenchmarkSuite, titleRes: Int) {
    val repetitions = AgentEvalOpsStore(this).settings().repeatedTrials.coerceIn(3, 10)
    if (suite.id == AgentEvalBenchmarkCatalog.standard.id) {
        AgentAndroidWorldBenchmarkFixtures.install(this)
        AgentBenchmarkMemoryFixtures.prepareImmediate(this)
    } else {
        AgentBenchmarkMemoryFixtures.prepareLongitudinal(this)
    }
    val readiness = AgentBenchmarkPreflight.assess(this, suite)
    val readyCount = readiness.values.count { it.status == AgentBenchmarkReadinessStatus.READY }
    if (readyCount == 0) {
        val message = buildString {
            append(readinessLine(readiness))
            readinessReasonLine(readiness)?.let { append("\n").append(it) }
            if (suite.id == AgentEvalBenchmarkCatalog.longitudinalMemory.id) {
                longitudinalEligibilityLine(readiness)?.let { append("\n").append(it) }
                append("\n\n").append(getString(R.string.cc_agent_longitudinal_benchmark_waiting_notice))
            }
        }
        AlertDialog.Builder(this)
            .setTitle(titleRes)
            .setMessage(message)
            .setPositiveButton(android.R.string.ok, null)
            .show()
        return
    }
    val available = AgentEvolutionLabRuntimeRegistry.get(this).availableAgents()
    val allocation = runCatching {
        AgentBenchmarkAllocationPolicy.codexDeepSeek90To10(suite, available)
    }.getOrElse { error ->
        Toast.makeText(this, error.message.orEmpty(), Toast.LENGTH_LONG).show()
        return
    }
    val codexId = allocation.teamResourceIdsByCase.values.firstOrNull()?.firstOrNull()
        ?: allocation.resourceIdsByCase.values.flatten().groupingBy { it }.eachCount()
            .maxByOrNull { it.value }?.key
    val codex = allocation.resources.first { it.agentId == codexId }
    val deepSeek = allocation.resources.first { it.agentId != codex.agentId }
    val totalRuns = readyCount * repetitions
    val readyCaseIds = readiness.values.filter { it.status == AgentBenchmarkReadinessStatus.READY }
        .mapTo(hashSetOf(), AgentBenchmarkCaseReadiness::caseId)
    val soloCaseIds = suite.cases.filter { it.dimension != AgentBenchmarkDimension.MULTI_AGENT }
        .mapTo(hashSetOf(), AgentBenchmarkCase::id)
    val codexTasks = allocation.resourceIdsByCase.count { (caseId, resourceIds) ->
        caseId in readyCaseIds && caseId in soloCaseIds && codex.agentId in resourceIds
    }
    val deepSeekTasks = allocation.resourceIdsByCase.count { (caseId, resourceIds) ->
        caseId in readyCaseIds && caseId in soloCaseIds && deepSeek.agentId in resourceIds
    }
    val teamTasks = allocation.teamResourceIdsByCase.keys.count(readyCaseIds::contains)
    val confirmation = buildString {
        if (suite.id == AgentEvalBenchmarkCatalog.longitudinalMemory.id) {
            append(getString(
                R.string.cc_agent_longitudinal_benchmark_confirm_message,
                codex.displayName,
                codexTasks,
                deepSeek.displayName,
                deepSeekTasks,
                repetitions,
                totalRuns
            ))
        } else {
            append(getString(
                R.string.cc_agent_benchmark_confirm_message,
                codex.displayName,
                codexTasks,
                deepSeek.displayName,
                deepSeekTasks,
                teamTasks,
                repetitions,
                totalRuns
            ))
        }
        append("\n\n").append(readinessLine(readiness))
        readinessReasonLine(readiness)?.let { append("\n").append(it) }
        if (suite.id == AgentEvalBenchmarkCatalog.longitudinalMemory.id) {
            longitudinalEligibilityLine(readiness)?.let { append("\n").append(it) }
        }
    }
    AlertDialog.Builder(this)
        .setTitle(titleRes)
        .setMessage(confirmation)
        .setPositiveButton(R.string.cc_agent_lab_start) { _, _ ->
            Toast.makeText(this, R.string.cc_agent_benchmark_preparing, Toast.LENGTH_SHORT).show()
            agentEvalExecutor.execute {
                val result = runCatching {
                    AgentBenchmarkCoordinator(applicationContext, suite)
                        .startCodexDeepSeek90To10(repetitions)
                }
                runOnUiThread {
                    if (isFinishing || isDestroyed) return@runOnUiThread
                    result.onSuccess {
                        Toast.makeText(
                            this,
                            if (suite.id == AgentEvalBenchmarkCatalog.longitudinalMemory.id) {
                                R.string.cc_agent_longitudinal_benchmark_started
                            } else {
                                R.string.cc_agent_benchmark_started
                            },
                            Toast.LENGTH_LONG
                        ).show()
                        showAgentEvolutionLabPage()
                    }.onFailure { error ->
                        Toast.makeText(this, error.message.orEmpty(), Toast.LENGTH_LONG).show()
                    }
                }
            }
        }
        .setNegativeButton(android.R.string.cancel, null)
        .show()
}

private fun MainActivity.benchmarkSummary(
    coordinator: AgentBenchmarkCoordinator,
    session: AgentBenchmarkSession,
    progress: AgentBenchmarkProgress,
    includeScorecard: Boolean
): String {
    return buildString {
        append(getString(
            R.string.cc_agent_benchmark_version_line,
            session.suiteVersion,
            session.appVersionName,
            session.appVersionCode,
            session.deviceModel
        ))
        append("\n").append(getString(
            R.string.cc_agent_benchmark_progress_line,
            progress.completedTrials,
            progress.expectedTrials,
            session.repetitions
        ))
        append("\n").append(allocationLine(session))
        if (session.readinessByCase.isNotEmpty()) {
            append("\n").append(readinessLine(session.readinessByCase))
            readinessReasonLine(session.readinessByCase)?.let { append("\n").append(it) }
        }
        if (!includeScorecard) {
            append("\n\n").append(getString(R.string.cc_agent_benchmark_provisional_notice))
            return@buildString
        }
        val scorecard = coordinator.scorecard(session)
        append("\n\n").append(getString(R.string.cc_agent_benchmark_overall)).append(": ")
        append(metricText(scorecard.overall))
        append("\n  ").append(metricEvidenceText(scorecard.overall))
        scorecard.dimensions.filter { it.taskCount > 0 }.forEach { metric ->
            append("\n").append(dimensionName(metric.dimension!!)).append(": ").append(metricText(metric))
            append("\n  ").append(metricEvidenceText(metric))
        }
        append("\n\n").append(getString(R.string.cc_agent_benchmark_models))
        scorecard.resources.forEach { resource ->
            append("\n").append(resource.resource.displayName)
                .append(" · ").append(resource.overall.taskCount).append(' ')
                .append(getString(R.string.cc_agent_benchmark_tasks_suffix))
                .append(" · ").append(metricText(resource.overall))
        }
        if (!scorecard.overall.qualified) {
            append("\n\n").append(getString(R.string.cc_agent_benchmark_provisional_notice))
        }
    }
}

private fun MainActivity.metricText(metric: AgentBenchmarkMetric): String = when {
    metric.evaluableTrials == 0 && metric.waitingForRealConditionTrials > 0 -> getString(
        R.string.cc_agent_benchmark_metric_waiting,
        metric.waitingForRealConditionTrials,
        metric.plannedTrials
    )
    metric.evaluableTrials == 0 && metric.blockedTrials > 0 -> getString(
        R.string.cc_agent_benchmark_metric_blocked,
        metric.blockedTrials,
        metric.plannedTrials
    )
    metric.completedTrials == 0 -> getString(R.string.cc_agent_benchmark_not_run)
    !metric.qualified -> getString(
        R.string.cc_agent_benchmark_metric_provisional,
        percent(metric.passAt1),
        metric.completedTrials,
        metric.expectedTrials
    )
    !metric.certificationComplete -> getString(
        R.string.cc_agent_benchmark_metric_certification_pending,
        percent(metric.passAt1),
        percent(metric.passPowerK)
    )
    metric.targetMet -> getString(R.string.cc_agent_benchmark_metric_pass, percent(metric.passAt1), percent(metric.passPowerK))
    else -> getString(R.string.cc_agent_benchmark_metric_fail, percent(metric.passAt1), percent(metric.passPowerK))
}

private fun MainActivity.metricEvidenceText(metric: AgentBenchmarkMetric): String = getString(
    R.string.cc_agent_benchmark_metric_evidence,
    metric.evaluableTaskCount,
    metric.taskCount,
    metric.passedTrials,
    metric.capabilityFailureTrials,
    metric.infrastructureFailureTrials,
    metric.notExecutedTrials,
    metric.waitingForRealConditionTrials,
    metric.blockedTrials,
    percent(metric.certificationCoverage)
)

private fun MainActivity.allocationLine(session: AgentBenchmarkSession): String {
    val parts = session.resources.map { resource ->
        val cases = session.scheduledCaseIds.count { caseId ->
            session.teamResourceIdsByCase[caseId].isNullOrEmpty() &&
                resource.resourceId in session.resourceIdsByCase[caseId].orEmpty()
        }
        "${resource.displayName} ${cases * session.repetitions}"
    }.toMutableList()
    val teamRuns = session.scheduledCaseIds.count { session.teamResourceIdsByCase[it].orEmpty().size >= 2 } *
        session.repetitions
    if (teamRuns > 0) parts += getString(R.string.cc_agent_benchmark_team_runs, teamRuns)
    return getString(R.string.cc_agent_benchmark_allocation_dynamic, parts.joinToString(" · "))
}

private fun MainActivity.showAgentBenchmarkDimensionPicker(
    coordinator: AgentBenchmarkCoordinator,
    session: AgentBenchmarkSession
) {
    val suite = AgentEvalBenchmarkCatalog.suite(session.suiteId, session.suiteVersion)
        ?: AgentEvalBenchmarkCatalog.standard
    val dimensions = listOf<AgentBenchmarkDimension?>(null) + session.caseIds
        .mapNotNull(suite::case)
        .map(AgentBenchmarkCase::dimension)
        .distinct()
    val labels = dimensions.map { dimension ->
        dimension?.let(::dimensionName) ?: getString(R.string.cc_agent_benchmark_overall)
    }.toTypedArray()
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_agent_benchmark_details)
        .setItems(labels) { _, index ->
            showAgentBenchmarkEvidenceDialog(coordinator, session, dimensions[index])
        }
        .setNegativeButton(android.R.string.cancel, null)
        .show()
}

private fun MainActivity.showAgentBenchmarkEvidenceDialog(
    coordinator: AgentBenchmarkCoordinator,
    session: AgentBenchmarkSession,
    dimension: AgentBenchmarkDimension?
) {
    val failures = coordinator.trialEvidence(session, dimension)
        .filter { it.classification != AgentBenchmarkTrialClassification.PASSED }
    val message = if (failures.isEmpty()) {
        getString(R.string.cc_agent_benchmark_no_failures)
    } else buildString {
        failures.take(MAX_VISIBLE_FAILURES).forEachIndexed { index, item ->
            if (index > 0) append("\n\n")
            append(item.caseId).append(" · ").append(item.caseTitle)
            append("\n").append(item.resourceName).append(" · #").append(item.repetition)
            append("\n").append(getString(
                R.string.cc_agent_benchmark_failure_classification,
                failureClassificationName(item.classification)
            ))
            append("\n").append(getString(
                R.string.cc_agent_benchmark_failure_reasons,
                item.failureReasons.joinToString(", ").ifBlank { "-" }
            ))
            append("\n").append(getString(
                R.string.cc_agent_benchmark_plan_tool_evidence,
                item.planEventCount,
                item.toolReceipts.joinToString(", ").ifBlank { "-" }
            ))
            if (item.androidWorldEvidence.isNotEmpty()) {
                append("\n").append(getString(
                    R.string.cc_agent_benchmark_android_evidence,
                    item.androidWorldEvidence.joinToString(", ")
                ))
            }
            append("\n").append(getString(
                R.string.cc_agent_benchmark_raw_output,
                item.rawOutput.ifBlank { "-" }.take(MAX_VISIBLE_OUTPUT_CHARS)
            ))
            append("\nrun_id: ").append(item.runId)
        }
        if (failures.size > MAX_VISIBLE_FAILURES) {
            append("\n\n").append(getString(
                R.string.cc_agent_benchmark_more_failures,
                failures.size - MAX_VISIBLE_FAILURES
            ))
        }
    }
    AlertDialog.Builder(this)
        .setTitle(dimension?.let(::dimensionName) ?: getString(R.string.cc_agent_benchmark_overall))
        .setMessage(message)
        .setPositiveButton(android.R.string.ok, null)
        .show()
}

private fun MainActivity.failureClassificationName(
    classification: AgentBenchmarkTrialClassification
): String = getString(when (classification) {
    AgentBenchmarkTrialClassification.PASSED -> R.string.cc_agent_benchmark_state_passed
    AgentBenchmarkTrialClassification.CAPABILITY_FAILURE -> R.string.cc_agent_benchmark_state_capability_failure
    AgentBenchmarkTrialClassification.INFRASTRUCTURE_FAILURE -> R.string.cc_agent_benchmark_state_infrastructure_failure
    AgentBenchmarkTrialClassification.WAITING_FOR_REAL_CONDITION -> R.string.cc_agent_benchmark_state_waiting
})

private fun MainActivity.readinessLine(
    readiness: Map<String, AgentBenchmarkCaseReadiness>
): String = getString(
    R.string.cc_agent_benchmark_readiness_line,
    readiness.values.count { it.status == AgentBenchmarkReadinessStatus.READY },
    readiness.size,
    readiness.values.count { it.status == AgentBenchmarkReadinessStatus.WAITING },
    readiness.values.count { it.status == AgentBenchmarkReadinessStatus.BLOCKED }
)

private fun MainActivity.readinessReasonLine(
    readiness: Map<String, AgentBenchmarkCaseReadiness>
): String? {
    val reasons = readiness.values.filter { it.status != AgentBenchmarkReadinessStatus.READY }
        .groupingBy(AgentBenchmarkCaseReadiness::reasonCode)
        .eachCount()
        .toSortedMap()
        .map { (reason, count) -> "${readinessReasonName(reason)} $count" }
    return reasons.takeIf(List<*>::isNotEmpty)?.let {
        getString(R.string.cc_agent_benchmark_readiness_reasons, it.joinToString(" · "))
    }
}

private fun MainActivity.readinessReasonName(reason: String): String = getString(when {
    reason == "memory_horizon_not_reached" -> R.string.cc_agent_benchmark_reason_memory
    reason == "external_fault_controller_required" -> R.string.cc_agent_benchmark_reason_fault_controller
    reason == "planning_tool_harness_unavailable" -> R.string.cc_agent_benchmark_reason_planning_tools
    reason.startsWith("required_tool_unavailable:") -> R.string.cc_agent_benchmark_reason_required_tool
    reason == "android_world_harness_unavailable" -> R.string.cc_agent_benchmark_reason_android_world
    reason.startsWith("android_world_task_unavailable:") -> R.string.cc_agent_benchmark_reason_android_world_task
    reason == "multi_agent_harness_unavailable" -> R.string.cc_agent_benchmark_reason_multi_agent
    else -> R.string.cc_agent_benchmark_incomplete
})

private fun MainActivity.longitudinalEligibilityLine(
    readiness: Map<String, AgentBenchmarkCaseReadiness>
): String? {
    val eligible = readiness.values.map(AgentBenchmarkCaseReadiness::eligibleAtMillis)
        .filter { it > System.currentTimeMillis() }
        .sorted()
    if (eligible.isEmpty()) return null
    val formatter = java.text.DateFormat.getDateTimeInstance(
        java.text.DateFormat.MEDIUM,
        java.text.DateFormat.SHORT
    )
    return getString(
        R.string.cc_agent_longitudinal_benchmark_eligibility,
        formatter.format(java.util.Date(eligible.first())),
        formatter.format(java.util.Date(eligible.last()))
    )
}

private fun MainActivity.dimensionName(dimension: AgentBenchmarkDimension): String = getString(when (dimension) {
    AgentBenchmarkDimension.TASK_QUALITY -> R.string.cc_agent_benchmark_dimension_quality
    AgentBenchmarkDimension.PLANNING_AND_TOOLS -> R.string.cc_agent_benchmark_dimension_plan_tools
    AgentBenchmarkDimension.ANDROID_WORLD -> R.string.cc_agent_benchmark_dimension_android_world
    AgentBenchmarkDimension.IMMEDIATE_MEMORY -> R.string.cc_agent_benchmark_dimension_immediate_memory
    AgentBenchmarkDimension.LONG_TERM_MEMORY -> R.string.cc_agent_benchmark_dimension_memory
    AgentBenchmarkDimension.RECOVERY -> R.string.cc_agent_benchmark_dimension_recovery
    AgentBenchmarkDimension.MULTI_AGENT -> R.string.cc_agent_benchmark_dimension_multi_agent
})

private fun percent(value: Double?): String = value?.let {
    String.format(Locale.US, "%.1f%%", it * 100.0)
} ?: "--"

private const val MAX_VISIBLE_FAILURES = 30
private const val MAX_VISIBLE_OUTPUT_CHARS = 800
