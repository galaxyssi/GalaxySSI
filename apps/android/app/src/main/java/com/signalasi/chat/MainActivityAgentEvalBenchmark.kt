package com.signalasi.chat

import android.app.AlertDialog
import android.widget.Toast
import java.util.Locale

internal fun MainActivity.agentBenchmarkRow(): ControlCenterRowSpec {
    val coordinator = AgentBenchmarkCoordinator(this)
    val latest = coordinator.latest()
    val progress = latest?.let(coordinator::progress)
    val status = when {
        latest == null -> getString(R.string.cc_agent_benchmark_not_run)
        else -> "${progress?.completedTrials ?: 0}/${progress?.expectedTrials ?: latest.expectedTrials}"
    }
    return ControlCenterRowSpec(
        actionId = "lab.benchmark",
        title = getString(R.string.cc_agent_benchmark_title),
        subtitle = getString(
            R.string.cc_agent_benchmark_subtitle,
            AgentEvalBenchmarkCatalog.standard.cases.size,
            AgentEvalOpsStore(this).settings().repeatedTrials
        ),
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
    val coordinator = AgentBenchmarkCoordinator(this)
    val latest = coordinator.latest()
    val progress = latest?.let(coordinator::progress)
    val builder = AlertDialog.Builder(this)
        .setTitle(R.string.cc_agent_benchmark_title)
        .setMessage(latest?.let { benchmarkSummary(coordinator, it, progress!!, includeScorecard = false) }
            ?: getString(R.string.cc_agent_benchmark_description))
        .setNegativeButton(android.R.string.cancel, null)
    if (latest == null || progress?.terminal == true) {
        builder.setPositiveButton(R.string.cc_agent_benchmark_prepare) { _, _ -> confirmAgentBenchmarkStart() }
    } else {
        builder.setNeutralButton(R.string.cc_agent_benchmark_cancel) { _, _ ->
            coordinator.cancel(latest.id)
            showAgentEvolutionLabPage()
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

private fun MainActivity.confirmAgentBenchmarkStart() {
    val suite = AgentEvalBenchmarkCatalog.standard
    val repetitions = AgentEvalOpsStore(this).settings().repeatedTrials.coerceIn(3, 10)
    val available = AgentEvolutionLabRuntimeRegistry.get(this).availableAgents()
    val allocation = runCatching {
        AgentBenchmarkAllocationPolicy.codexDeepSeek90To10(suite, available)
    }.getOrElse { error ->
        Toast.makeText(this, error.message.orEmpty(), Toast.LENGTH_LONG).show()
        return
    }
    val codex = allocation.resources.first { resource ->
        allocation.resourceIdsByCase.values.count { resource.agentId in it } == 54
    }
    val deepSeek = allocation.resources.first { it.agentId != codex.agentId }
    val totalRuns = suite.cases.size * repetitions
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_agent_benchmark_confirm_title)
        .setMessage(getString(
            R.string.cc_agent_benchmark_confirm_message,
            codex.displayName,
            54,
            deepSeek.displayName,
            6,
            repetitions,
            totalRuns
        ))
        .setPositiveButton(R.string.cc_agent_lab_start) { _, _ ->
            runCatching { AgentBenchmarkCoordinator(this).startCodexDeepSeek90To10(repetitions) }
                .onSuccess {
                    Toast.makeText(this, R.string.cc_agent_benchmark_started, Toast.LENGTH_LONG).show()
                    showAgentEvolutionLabPage()
                }
                .onFailure { error -> Toast.makeText(this, error.message.orEmpty(), Toast.LENGTH_LONG).show() }
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
        append("\n").append(getString(R.string.cc_agent_benchmark_allocation_line))
        if (!includeScorecard) {
            append("\n\n").append(getString(R.string.cc_agent_benchmark_provisional_notice))
            return@buildString
        }
        val scorecard = coordinator.scorecard(session)
        append("\n\n").append(getString(R.string.cc_agent_benchmark_overall)).append(": ")
        append(metricText(scorecard.overall))
        scorecard.dimensions.filter { it.taskCount > 0 }.forEach { metric ->
            append("\n").append(dimensionName(metric.dimension!!)).append(": ").append(metricText(metric))
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
    metric.completedTrials == 0 -> getString(R.string.cc_agent_benchmark_not_run)
    !metric.qualified -> getString(
        R.string.cc_agent_benchmark_metric_provisional,
        percent(metric.passAt1),
        metric.completedTrials,
        metric.expectedTrials
    )
    metric.targetMet -> getString(R.string.cc_agent_benchmark_metric_pass, percent(metric.passAt1), percent(metric.passPowerK))
    else -> getString(R.string.cc_agent_benchmark_metric_fail, percent(metric.passAt1), percent(metric.passPowerK))
}

private fun MainActivity.dimensionName(dimension: AgentBenchmarkDimension): String = getString(when (dimension) {
    AgentBenchmarkDimension.TASK_QUALITY -> R.string.cc_agent_benchmark_dimension_quality
    AgentBenchmarkDimension.PLANNING_AND_TOOLS -> R.string.cc_agent_benchmark_dimension_plan_tools
    AgentBenchmarkDimension.ANDROID_WORLD -> R.string.cc_agent_benchmark_dimension_android_world
    AgentBenchmarkDimension.LONG_TERM_MEMORY -> R.string.cc_agent_benchmark_dimension_memory
    AgentBenchmarkDimension.RECOVERY -> R.string.cc_agent_benchmark_dimension_recovery
    AgentBenchmarkDimension.MULTI_AGENT -> R.string.cc_agent_benchmark_dimension_multi_agent
})

private fun percent(value: Double?): String = value?.let {
    String.format(Locale.US, "%.1f%%", it * 100.0)
} ?: "--"
