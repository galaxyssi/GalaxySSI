package com.signalasi.chat

import android.content.Context

data class AgentContinuousEvalDecision(
    val schedule: Boolean,
    val reason: String
)

object AgentContinuousEvalPolicy {
    fun decide(
        settings: AgentEvalOpsSettings,
        run: AgentRecordedRun,
        sample: AgentEvalSample,
        availableAgentCount: Int,
        lastScheduledAtMillis: Long,
        nowMillis: Long = System.currentTimeMillis()
    ): AgentContinuousEvalDecision {
        val reason = when {
            !settings.captureRealRuns -> "real_run_capture_disabled"
            !settings.continuousEvaluationEnabled -> "continuous_evaluation_disabled"
            run.conversationId.startsWith(AGENT_LAB_CONVERSATION_PREFIX) -> "agent_lab_run"
            run.status != AgentRecordedRunStatus.COMPLETED -> "run_not_completed"
            run.originalRequest.isBlank() -> "empty_task"
            AgentLearningAnalyzer.containsSensitiveData(run.originalRequest) -> "sensitive_task"
            availableAgentCount < MINIMUM_AGENTS -> "insufficient_agents"
            sample.scenarioId.isBlank() -> "missing_scenario"
            lastScheduledAtMillis > 0L && nowMillis - lastScheduledAtMillis < COOLDOWN_MILLIS ->
                "scenario_cooldown"
            else -> "scheduled"
        }
        return AgentContinuousEvalDecision(reason == "scheduled", reason)
    }

    internal const val AGENT_LAB_CONVERSATION_PREFIX = "agent-lab:"
    internal const val MINIMUM_AGENTS = 2
    internal const val COOLDOWN_MILLIS = 24L * 60L * 60_000L
}

private class AgentContinuousEvalStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    fun lastScheduledAtMillis(scenarioId: String): Long =
        database.readString(key(scenarioId), "0").toLongOrNull()?.coerceAtLeast(0L) ?: 0L

    @Synchronized
    fun recordScheduled(scenarioId: String, atMillis: Long) {
        database.writeString(key(scenarioId), atMillis.coerceAtLeast(0L).toString())
    }

    private fun key(scenarioId: String) = "scenario:${scenarioId.trim().take(160)}"

    private companion object {
        const val DATABASE = "signalasi_continuous_eval_v1"
    }
}

object AgentContinuousEvalCoordinator {
    fun observeCompletedRun(
        context: Context,
        run: AgentRecordedRun,
        sample: AgentEvalSample,
        nowMillis: Long = System.currentTimeMillis()
    ): String? {
        val appContext = context.applicationContext
        val settings = AgentEvalOpsStore(appContext).settings()
        val runtime = AgentEvolutionLabRuntimeRegistry.get(appContext)
        val agents = runtime.availableAgents().take(MAXIMUM_AGENTS)
        val store = AgentContinuousEvalStore(appContext)
        val decision = AgentContinuousEvalPolicy.decide(
            settings = settings,
            run = run,
            sample = sample,
            availableAgentCount = agents.size,
            lastScheduledAtMillis = store.lastScheduledAtMillis(sample.scenarioId),
            nowMillis = nowMillis
        )
        if (!decision.schedule) return null
        val campaign = runCatching {
            runtime.createAndStart(
                task = run.originalRequest,
                agentIds = agents.map(AgentRegistration::agentId),
                repetitions = settings.repeatedTrials
            )
        }.getOrNull() ?: return null
        store.recordScheduled(sample.scenarioId, nowMillis)
        return campaign.id
    }

    private const val MAXIMUM_AGENTS = 4
}
