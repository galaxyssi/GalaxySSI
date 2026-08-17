package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

enum class AgentExecutionLoopPhase {
    PLAN,
    ACT,
    OBSERVE,
    REPLAN,
    VERIFY,
    FINALIZE,
    LEARN,
    WAITING_CONFIRMATION,
    WAITING_RESPONSE,
    PAUSED,
    BLOCKED,
    FAILED,
    CANCELLED,
    COMPLETED;

    val isActive: Boolean
        get() = this in ACTIVE_PHASES

    val isTerminal: Boolean
        get() = this == BLOCKED || this == FAILED || this == CANCELLED || this == COMPLETED

    private companion object {
        val ACTIVE_PHASES = setOf(PLAN, ACT, OBSERVE, REPLAN, VERIFY, FINALIZE, LEARN)
    }
}

data class AgentExecutionLoopBudget(
    val maxIterations: Int = 8,
    val maxActions: Int = 16,
    val maxReplans: Int = 3,
    val maxToolCalls: Int = 16,
    val maxRetries: Int = 2,
    val maxSameFailureAttempts: Int = 2,
    val noProgressTimeoutMillis: Long = 3 * 60_000L,
    val enforceCountLimits: Boolean = true
) {
    init {
        require(maxIterations > 0) { "Maximum loop iterations must be positive" }
        require(maxActions > 0) { "Maximum actions must be positive" }
        require(maxReplans >= 0) { "Maximum replans cannot be negative" }
        require(maxToolCalls > 0) { "Maximum tool calls must be positive" }
        require(maxRetries >= 0) { "Maximum retries cannot be negative" }
        require(maxSameFailureAttempts > 0) { "Same-failure budget must be positive" }
        require(noProgressTimeoutMillis > 0L) { "No-progress timeout must be positive" }
    }
}

data class AgentExecutionLoopUsage(
    val iterations: Int = 0,
    val actions: Int = 0,
    val replans: Int = 0,
    val toolCalls: Int = 0,
    val retries: Int = 0,
    val activeDurationMillis: Long = 0L,
    val activeSinceMillis: Long = 0L
) {
    fun elapsedActiveMillis(nowMillis: Long, phase: AgentExecutionLoopPhase): Long =
        activeDurationMillis + if (phase.isActive && activeSinceMillis > 0L) {
            (nowMillis - activeSinceMillis).coerceAtLeast(0L)
        } else {
            0L
        }
}

data class AgentExecutionLoopSnapshot(
    val taskId: String,
    val phase: AgentExecutionLoopPhase,
    val budget: AgentExecutionLoopBudget,
    val usage: AgentExecutionLoopUsage,
    val taskBudget: AgentTaskBudget = AgentTaskBudget.forProfile(AgentTaskBudgetProfile.ADAPTIVE),
    val taskBudgetUsage: AgentTaskBudgetUsage = AgentTaskBudgetUsage(),
    val resumePhase: AgentExecutionLoopPhase = AgentExecutionLoopPhase.PLAN,
    val lastActionId: String = "",
    val lastReason: String = "",
    val budgetFailure: String = "",
    val taskKind: AgentExecutionTaskKind = AgentExecutionTaskKind.CHAT,
    val taskIntent: AgentTaskIntent = AgentTaskIntent.CHAT,
    val taskIntentConfidence: Int = 100,
    val taskIntentSignals: List<String> = emptyList(),
    val reasoningEffort: AgentExecutionReasoningEffort = AgentExecutionReasoningEffort.LOW,
    val lastProgressAtMillis: Long,
    val failureCounts: Map<String, Int> = emptyMap(),
    val startedAtMillis: Long,
    val updatedAtMillis: Long,
    val revision: Long = 1L
)

data class AgentExecutionLoopEvent(
    val previousPhase: AgentExecutionLoopPhase?,
    val phase: AgentExecutionLoopPhase,
    val reason: String,
    val snapshot: AgentExecutionLoopSnapshot,
    val toolCall: Boolean = false,
    val retry: Boolean = false
)

fun interface AgentExecutionLoopEventSink {
    fun onEvent(event: AgentExecutionLoopEvent)

    companion object {
        val NONE = AgentExecutionLoopEventSink { }
    }
}

/**
 * Deterministic, bounded execution state for one mobile Agent task.
 *
 * Tasks have no absolute duration deadline. Waiting and paused phases do not
 * count as active work, while no-progress and bounded retry policies recover
 * stalled execution. Every transition returns a complete snapshot so callers
 * can persist it before allowing the next side effect.
 */
class AgentExecutionLoop private constructor(
    initialSnapshot: AgentExecutionLoopSnapshot?,
    private val clock: () -> Long
) {
    var snapshot: AgentExecutionLoopSnapshot? = initialSnapshot
        private set

    fun start(
        taskId: String,
        budget: AgentExecutionLoopBudget,
        profile: AgentExecutionProfile = AgentExecutionProfile.forGoal(""),
        taskBudget: AgentTaskBudget = AgentTaskBudget.forProfile(AgentTaskBudgetProfile.ADAPTIVE),
        environment: AgentTaskBudgetEnvironment = AgentTaskBudgetEnvironment()
    ): AgentExecutionLoopEvent {
        val now = clock()
        val normalizedTaskBudget = taskBudget.normalized()
        val taskBudgetUsage = AgentTaskBudgetUsage(
            peakMemoryBytes = environment.appMemoryBytes.coerceAtLeast(0L)
        )
        val resourceFailure = AgentTaskBudgetPolicy.evaluate(
            normalizedTaskBudget,
            taskBudgetUsage,
            environment
        )
        val initialPhase = if (resourceFailure.allowed) {
            AgentExecutionLoopPhase.PLAN
        } else {
            AgentExecutionLoopPhase.FAILED
        }
        val initialReason = resourceFailure.reason.ifBlank { "Task accepted" }
        val next = AgentExecutionLoopSnapshot(
            taskId = taskId.trim(),
            phase = initialPhase,
            budget = budget,
            usage = AgentExecutionLoopUsage(
                iterations = 1,
                activeSinceMillis = if (initialPhase.isActive) now else 0L
            ),
            taskBudget = normalizedTaskBudget,
            taskBudgetUsage = taskBudgetUsage,
            resumePhase = AgentExecutionLoopPhase.PLAN,
            lastReason = initialReason,
            budgetFailure = resourceFailure.reason,
            taskKind = profile.taskKind,
            taskIntent = profile.taskIntent,
            taskIntentConfidence = profile.taskIntentConfidence,
            taskIntentSignals = profile.taskIntentSignals,
            reasoningEffort = profile.reasoningEffort,
            lastProgressAtMillis = now,
            startedAtMillis = now,
            updatedAtMillis = now
        )
        snapshot = next
        return AgentExecutionLoopEvent(null, next.phase, next.lastReason, next)
    }

    fun transition(
        phase: AgentExecutionLoopPhase,
        reason: String = "",
        actionId: String = "",
        toolCall: Boolean = false,
        retry: Boolean = false
    ): AgentExecutionLoopEvent {
        val current = requireNotNull(snapshot) { "Agent execution loop has not started" }
        requireTransition(current.phase, phase, retry)
        val now = clock()
        val accounted = accountActiveDuration(current, now)
        var usage = accounted.usage
        if (phase == AgentExecutionLoopPhase.REPLAN) {
            usage = usage.copy(
                iterations = usage.iterations + 1,
                replans = usage.replans + 1
            )
        }
        if (phase == AgentExecutionLoopPhase.ACT) {
            usage = usage.copy(
                actions = usage.actions + 1,
                toolCalls = usage.toolCalls + if (toolCall) 1 else 0,
                retries = usage.retries + if (retry) 1 else 0
            )
        } else if (retry) {
            usage = usage.copy(retries = usage.retries + 1)
        }
        usage = usage.copy(
            activeSinceMillis = if (phase.isActive) now else 0L
        )
        val taskBudgetUsage = current.taskBudgetUsage.copy(
            elapsedMillis = usage.activeDurationMillis
        )
        val budgetFailure = budgetFailure(
            usage,
            current.budget,
            taskBudgetUsage,
            current.taskBudget
        )
        val resolvedPhase = if (budgetFailure.isBlank()) phase else AgentExecutionLoopPhase.FAILED
        val resolvedUsage = if (resolvedPhase.isActive) usage else {
            usage.copy(activeSinceMillis = 0L)
        }
        val resolvedReason = budgetFailure.ifBlank { reason.trim() }
        val next = accounted.copy(
            phase = resolvedPhase,
            usage = resolvedUsage,
            taskBudgetUsage = taskBudgetUsage,
            resumePhase = when {
                resolvedPhase == AgentExecutionLoopPhase.PAUSED -> current.resumePhase
                phase.isActive -> phase
                else -> current.resumePhase
            },
            lastActionId = actionId.trim().ifBlank { current.lastActionId },
            lastReason = resolvedReason,
            budgetFailure = budgetFailure,
            lastProgressAtMillis = now,
            updatedAtMillis = now,
            revision = current.revision + 1L
        )
        snapshot = next
        return AgentExecutionLoopEvent(
            previousPhase = current.phase,
            phase = next.phase,
            reason = resolvedReason,
            snapshot = next,
            toolCall = toolCall,
            retry = retry
        )
    }

    fun recordFailure(
        failureClass: String,
        reason: String,
        actionId: String = ""
    ): AgentExecutionLoopEvent {
        val current = requireNotNull(snapshot) { "Agent execution loop has not started" }
        val now = clock()
        val key = failureFingerprint(failureClass, reason)
        val count = current.failureCounts.getOrDefault(key, 0) + 1
        val failures = current.failureCounts + (key to count)
        val exhausted = count >= current.budget.maxSameFailureAttempts
        val nextPhase = if (exhausted) {
            AgentExecutionLoopPhase.FAILED
        } else {
            AgentExecutionLoopPhase.REPLAN
        }
        val accounted = accountActiveDuration(current, now)
        val usage = accounted.usage.copy(
            iterations = accounted.usage.iterations + if (exhausted) 0 else 1,
            replans = accounted.usage.replans + if (exhausted) 0 else 1,
            activeSinceMillis = if (nextPhase.isActive) now else 0L
        )
        val budgetFailure = if (exhausted) {
            "Same failure repeated $count times"
        } else {
            budgetFailure(
                usage,
                current.budget,
                current.taskBudgetUsage.copy(elapsedMillis = usage.activeDurationMillis),
                current.taskBudget
            )
        }
        val resolvedPhase = if (budgetFailure.isBlank()) nextPhase else AgentExecutionLoopPhase.FAILED
        val next = accounted.copy(
            phase = resolvedPhase,
            usage = usage.copy(activeSinceMillis = if (resolvedPhase.isActive) now else 0L),
            taskBudgetUsage = current.taskBudgetUsage.copy(
                elapsedMillis = usage.activeDurationMillis
            ),
            resumePhase = if (resolvedPhase.isActive) resolvedPhase else current.resumePhase,
            lastActionId = actionId.trim().ifBlank { current.lastActionId },
            lastReason = reason.trim().ifBlank { failureClass },
            budgetFailure = budgetFailure,
            lastProgressAtMillis = now,
            failureCounts = failures,
            updatedAtMillis = now,
            revision = current.revision + 1L
        )
        snapshot = next
        return AgentExecutionLoopEvent(
            previousPhase = current.phase,
            phase = next.phase,
            reason = next.lastReason,
            snapshot = next,
            retry = !exhausted
        )
    }

    fun checkNoProgress(nowMillis: Long = clock()): AgentExecutionLoopEvent? {
        val current = snapshot ?: return null
        if (!current.phase.isActive) return null
        val stalledFor = (nowMillis - current.lastProgressAtMillis).coerceAtLeast(0L)
        if (stalledFor < current.budget.noProgressTimeoutMillis) return null
        return recordFailure(
            failureClass = "no_progress",
            reason = "No meaningful progress for ${current.budget.noProgressTimeoutMillis} ms",
            actionId = current.lastActionId
        )
    }

    fun recordTaskBudgetUsage(
        inputTokens: Long = 0L,
        outputTokens: Long = 0L,
        costMicros: Long = 0L,
        networkBytes: Long = 0L,
        memoryBytes: Long = 0L,
        estimated: Boolean = false,
        environment: AgentTaskBudgetEnvironment = AgentTaskBudgetEnvironment()
    ): AgentExecutionLoopEvent {
        val current = requireNotNull(snapshot) { "Agent execution loop has not started" }
        val now = clock()
        val accounted = accountActiveDuration(current, now)
        val usage = accounted.usage.copy(
            activeSinceMillis = if (current.phase.isActive) now else 0L
        )
        val taskUsage = current.taskBudgetUsage.add(
            elapsedMillis = (usage.activeDurationMillis - current.taskBudgetUsage.elapsedMillis)
                .coerceAtLeast(0L),
            inputTokens = inputTokens,
            outputTokens = outputTokens,
            costMicros = costMicros,
            networkBytes = networkBytes,
            memoryBytes = maxOf(memoryBytes, environment.appMemoryBytes),
            estimated = estimated
        )
        val decision = AgentTaskBudgetPolicy.evaluate(
            current.taskBudget,
            taskUsage,
            environment
        )
        val nextPhase = if (decision.allowed) current.phase else AgentExecutionLoopPhase.FAILED
        val nextReason = decision.reason.ifBlank { "Task resource usage updated" }
        val next = accounted.copy(
            phase = nextPhase,
            usage = usage.copy(activeSinceMillis = if (nextPhase.isActive) now else 0L),
            taskBudgetUsage = taskUsage,
            lastReason = nextReason,
            budgetFailure = decision.reason,
            lastProgressAtMillis = now,
            updatedAtMillis = now,
            revision = current.revision + 1L
        )
        snapshot = next
        return AgentExecutionLoopEvent(
            previousPhase = current.phase,
            phase = next.phase,
            reason = nextReason,
            snapshot = next
        )
    }

    fun pause(reason: String = "Task paused"): AgentExecutionLoopEvent {
        val current = requireNotNull(snapshot) { "Agent execution loop has not started" }
        val resumable = current.phase.takeIf { it.isActive } ?: current.resumePhase
        val event = transition(AgentExecutionLoopPhase.PAUSED, reason)
        val adjusted = event.snapshot.copy(resumePhase = resumable)
        snapshot = adjusted
        return event.copy(snapshot = adjusted)
    }

    fun resume(reason: String = "Task resumed"): AgentExecutionLoopEvent {
        val current = requireNotNull(snapshot) { "Agent execution loop has not started" }
        require(current.phase == AgentExecutionLoopPhase.PAUSED) {
            "Only a paused Agent loop can resume"
        }
        return transition(current.resumePhase, reason)
    }

    fun recoverInterrupted(reason: String = "Execution restored from the last checkpoint"): AgentExecutionLoopEvent? {
        val current = snapshot ?: return null
        if (!current.phase.isActive) return null
        return pause(reason)
    }

    private fun accountActiveDuration(
        current: AgentExecutionLoopSnapshot,
        nowMillis: Long
    ): AgentExecutionLoopSnapshot {
        if (!current.phase.isActive || current.usage.activeSinceMillis <= 0L) return current
        val elapsed = (nowMillis - current.usage.activeSinceMillis).coerceAtLeast(0L)
        return current.copy(
            usage = current.usage.copy(
                activeDurationMillis = current.usage.activeDurationMillis + elapsed,
                activeSinceMillis = 0L
            )
        )
    }

    private fun budgetFailure(
        usage: AgentExecutionLoopUsage,
        budget: AgentExecutionLoopBudget,
        taskBudgetUsage: AgentTaskBudgetUsage,
        taskBudget: AgentTaskBudget
    ): String = when {
        budget.enforceCountLimits && usage.iterations > budget.maxIterations ->
            "Loop iteration budget exhausted (${budget.maxIterations})"
        budget.enforceCountLimits && usage.actions > budget.maxActions ->
            "Action budget exhausted (${budget.maxActions})"
        budget.enforceCountLimits && usage.replans > budget.maxReplans ->
            "Replan budget exhausted (${budget.maxReplans})"
        budget.enforceCountLimits && usage.toolCalls > budget.maxToolCalls ->
            "Tool-call budget exhausted (${budget.maxToolCalls})"
        budget.enforceCountLimits && usage.retries > budget.maxRetries ->
            "Retry budget exhausted (${budget.maxRetries})"
        else -> AgentTaskBudgetPolicy.evaluate(taskBudget, taskBudgetUsage).reason
    }

    private fun failureFingerprint(failureClass: String, reason: String): String {
        val normalized = reason
            .lowercase(Locale.US)
            .replace(Regex("\\b\\d+(?:\\.\\d+)?\\b"), "#")
            .replace(Regex("\\s+"), " ")
            .trim()
            .take(300)
        return "${failureClass.lowercase(Locale.US).trim()}:$normalized"
    }

    private fun requireTransition(
        from: AgentExecutionLoopPhase,
        to: AgentExecutionLoopPhase,
        retry: Boolean
    ) {
        if (from == to) return
        if (from.isTerminal) {
            require(retry && from in RETRYABLE_TERMINAL_PHASES && to in RETRY_TARGET_PHASES) {
                "Terminal Agent loop cannot transition from $from to $to"
            }
            return
        }
        require(to in ALLOWED_TRANSITIONS.getValue(from)) {
            "Invalid Agent loop transition from $from to $to"
        }
    }

    companion object {
        private val RETRYABLE_TERMINAL_PHASES = setOf(
            AgentExecutionLoopPhase.BLOCKED,
            AgentExecutionLoopPhase.FAILED
        )
        private val RETRY_TARGET_PHASES = setOf(
            AgentExecutionLoopPhase.PLAN,
            AgentExecutionLoopPhase.ACT,
            AgentExecutionLoopPhase.REPLAN
        )
        private val COMMON_CONTROL_TRANSITIONS = setOf(
            AgentExecutionLoopPhase.WAITING_CONFIRMATION,
            AgentExecutionLoopPhase.WAITING_RESPONSE,
            AgentExecutionLoopPhase.PAUSED,
            AgentExecutionLoopPhase.BLOCKED,
            AgentExecutionLoopPhase.FAILED,
            AgentExecutionLoopPhase.CANCELLED
        )
        private val ALLOWED_TRANSITIONS = mapOf(
            AgentExecutionLoopPhase.PLAN to COMMON_CONTROL_TRANSITIONS + setOf(
                AgentExecutionLoopPhase.ACT,
                AgentExecutionLoopPhase.VERIFY
            ),
            AgentExecutionLoopPhase.ACT to COMMON_CONTROL_TRANSITIONS + setOf(
                AgentExecutionLoopPhase.OBSERVE
            ),
            AgentExecutionLoopPhase.OBSERVE to COMMON_CONTROL_TRANSITIONS + setOf(
                AgentExecutionLoopPhase.ACT,
                AgentExecutionLoopPhase.REPLAN,
                AgentExecutionLoopPhase.VERIFY
            ),
            AgentExecutionLoopPhase.REPLAN to COMMON_CONTROL_TRANSITIONS + setOf(
                AgentExecutionLoopPhase.ACT,
                AgentExecutionLoopPhase.VERIFY
            ),
            AgentExecutionLoopPhase.VERIFY to COMMON_CONTROL_TRANSITIONS + setOf(
                AgentExecutionLoopPhase.REPLAN,
                AgentExecutionLoopPhase.FINALIZE
            ),
            AgentExecutionLoopPhase.FINALIZE to COMMON_CONTROL_TRANSITIONS + setOf(
                AgentExecutionLoopPhase.LEARN,
                AgentExecutionLoopPhase.COMPLETED
            ),
            AgentExecutionLoopPhase.LEARN to COMMON_CONTROL_TRANSITIONS + setOf(
                AgentExecutionLoopPhase.COMPLETED
            ),
            AgentExecutionLoopPhase.WAITING_CONFIRMATION to setOf(
                AgentExecutionLoopPhase.ACT,
                AgentExecutionLoopPhase.REPLAN,
                AgentExecutionLoopPhase.PAUSED,
                AgentExecutionLoopPhase.BLOCKED,
                AgentExecutionLoopPhase.FAILED,
                AgentExecutionLoopPhase.CANCELLED
            ),
            AgentExecutionLoopPhase.WAITING_RESPONSE to setOf(
                AgentExecutionLoopPhase.OBSERVE,
                AgentExecutionLoopPhase.REPLAN,
                AgentExecutionLoopPhase.VERIFY,
                AgentExecutionLoopPhase.PAUSED,
                AgentExecutionLoopPhase.FAILED,
                AgentExecutionLoopPhase.CANCELLED
            ),
            AgentExecutionLoopPhase.PAUSED to AgentExecutionLoopPhase.entries.toSet() -
                setOf(AgentExecutionLoopPhase.COMPLETED),
            AgentExecutionLoopPhase.BLOCKED to emptySet(),
            AgentExecutionLoopPhase.FAILED to emptySet(),
            AgentExecutionLoopPhase.CANCELLED to emptySet(),
            AgentExecutionLoopPhase.COMPLETED to emptySet()
        )

        fun create(clock: () -> Long = { System.currentTimeMillis() }): AgentExecutionLoop =
            AgentExecutionLoop(null, clock)

        fun restore(
            snapshot: AgentExecutionLoopSnapshot,
            clock: () -> Long = { System.currentTimeMillis() }
        ): AgentExecutionLoop = AgentExecutionLoop(snapshot, clock)
    }
}

object AgentExecutionLoopJsonCodec {
    fun encode(snapshot: AgentExecutionLoopSnapshot): String = JSONObject()
        .put("version", 4)
        .put("task_id", snapshot.taskId)
        .put("phase", snapshot.phase.name)
        .put("resume_phase", snapshot.resumePhase.name)
        .put("last_action_id", snapshot.lastActionId)
        .put("last_reason", snapshot.lastReason)
        .put("budget_failure", snapshot.budgetFailure)
        .put("task_kind", snapshot.taskKind.name)
        .put("task_intent", snapshot.taskIntent.name)
        .put("task_intent_confidence", snapshot.taskIntentConfidence)
        .put("task_intent_signals", JSONArray(snapshot.taskIntentSignals))
        .put("reasoning_effort", snapshot.reasoningEffort.name)
        .put("last_progress_at", snapshot.lastProgressAtMillis)
        .put("failure_counts", JSONObject(snapshot.failureCounts))
        .put("started_at", snapshot.startedAtMillis)
        .put("updated_at", snapshot.updatedAtMillis)
        .put("revision", snapshot.revision)
        .put("budget", JSONObject()
            .put("max_iterations", snapshot.budget.maxIterations)
            .put("max_actions", snapshot.budget.maxActions)
            .put("max_replans", snapshot.budget.maxReplans)
            .put("max_tool_calls", snapshot.budget.maxToolCalls)
            .put("max_retries", snapshot.budget.maxRetries)
            .put("max_same_failure_attempts", snapshot.budget.maxSameFailureAttempts)
            .put("no_progress_timeout_ms", snapshot.budget.noProgressTimeoutMillis)
            .put("enforce_count_limits", snapshot.budget.enforceCountLimits))
        .put("usage", JSONObject()
            .put("iterations", snapshot.usage.iterations)
            .put("actions", snapshot.usage.actions)
            .put("replans", snapshot.usage.replans)
            .put("tool_calls", snapshot.usage.toolCalls)
            .put("retries", snapshot.usage.retries)
            .put("active_duration_ms", snapshot.usage.activeDurationMillis)
            .put("active_since_ms", snapshot.usage.activeSinceMillis))
        .put("task_budget", AgentTaskBudgetJsonCodec.encode(snapshot.taskBudget))
        .put("task_budget_usage", AgentTaskBudgetJsonCodec.encodeUsage(snapshot.taskBudgetUsage))
        .toString()

    fun decode(value: String): AgentExecutionLoopSnapshot? = runCatching {
        val root = JSONObject(value)
        val budget = root.getJSONObject("budget")
        val usage = root.getJSONObject("usage")
        val taskKind = enumValue(
            root.optString("task_kind"),
            AgentExecutionTaskKind.CHAT
        )
        AgentExecutionLoopSnapshot(
            taskId = root.getString("task_id"),
            phase = enumValue(root.getString("phase"), AgentExecutionLoopPhase.PLAN),
            budget = AgentExecutionLoopBudget(
                maxIterations = budget.getInt("max_iterations"),
                maxActions = budget.getInt("max_actions"),
                maxReplans = budget.getInt("max_replans"),
                maxToolCalls = budget.getInt("max_tool_calls"),
                maxRetries = budget.getInt("max_retries"),
                maxSameFailureAttempts = budget.optInt("max_same_failure_attempts", 2),
                noProgressTimeoutMillis = budget.optLong("no_progress_timeout_ms", 180_000L),
                enforceCountLimits = budget.optBoolean(
                    "enforce_count_limits",
                    taskKind !in CONTINUOUS_PROJECT_TASK_KINDS
                )
            ),
            usage = AgentExecutionLoopUsage(
                iterations = usage.getInt("iterations"),
                actions = usage.getInt("actions"),
                replans = usage.getInt("replans"),
                toolCalls = usage.getInt("tool_calls"),
                retries = usage.getInt("retries"),
                activeDurationMillis = usage.getLong("active_duration_ms"),
                activeSinceMillis = usage.getLong("active_since_ms")
            ),
            taskBudget = AgentTaskBudgetJsonCodec.decode(root.optJSONObject("task_budget")),
            taskBudgetUsage = AgentTaskBudgetJsonCodec.decodeUsage(
                root.optJSONObject("task_budget_usage")
            ),
            resumePhase = enumValue(
                root.optString("resume_phase"),
                AgentExecutionLoopPhase.PLAN
            ),
            lastActionId = root.optString("last_action_id"),
            lastReason = root.optString("last_reason"),
            budgetFailure = root.optString("budget_failure"),
            taskKind = taskKind,
            taskIntent = enumValue(root.optString("task_intent"), AgentTaskIntent.CHAT),
            taskIntentConfidence = root.optInt("task_intent_confidence", 100)
                .coerceIn(0, 100),
            taskIntentSignals = root.optJSONArray("task_intent_signals")?.let { values ->
                (0 until values.length()).mapNotNull { index ->
                    values.optString(index).trim().takeIf(String::isNotBlank)
                }.distinct().take(6)
            }.orEmpty(),
            reasoningEffort = enumValue(
                root.optString("reasoning_effort"),
                AgentExecutionReasoningEffort.LOW
            ),
            lastProgressAtMillis = root.optLong(
                "last_progress_at",
                root.getLong("updated_at")
            ),
            failureCounts = root.optJSONObject("failure_counts")?.let { failures ->
                failures.keys().asSequence().associateWith { key ->
                    failures.optInt(key, 0)
                }
            }.orEmpty(),
            startedAtMillis = root.getLong("started_at"),
            updatedAtMillis = root.getLong("updated_at"),
            revision = root.optLong("revision", 1L)
        )
    }.getOrNull()

    fun eventPayload(event: AgentExecutionLoopEvent): String = JSONObject()
        .put("previous_phase", event.previousPhase?.name.orEmpty().lowercase(Locale.ROOT))
        .put("phase", event.phase.name.lowercase(Locale.ROOT))
        .put("reason", event.reason)
        .put("tool_call", event.toolCall)
        .put("retry", event.retry)
        .put("snapshot", JSONObject(encode(event.snapshot)))
        .toString()

    private fun <T : Enum<T>> enumValue(value: String, fallback: T): T {
        val constants = fallback.declaringJavaClass.enumConstants ?: return fallback
        return constants.firstOrNull { it.name == value } ?: fallback
    }

    private val CONTINUOUS_PROJECT_TASK_KINDS = setOf(
        AgentExecutionTaskKind.BUILD,
        AgentExecutionTaskKind.INSTALL
    )
}

internal fun AgentModelPlannerSettings.executionLoopBudget(
    profile: AgentExecutionProfile = AgentExecutionProfile.forGoal("")
): AgentExecutionLoopBudget {
    val projectTask = profile.taskKind in setOf(
        AgentExecutionTaskKind.BUILD,
        AgentExecutionTaskKind.INSTALL
    )
    return AgentExecutionLoopBudget(
        maxIterations = if (projectTask) maxLoopIterations.coerceAtLeast(16) else maxLoopIterations,
        maxActions = if (projectTask) maxActions.coerceAtLeast(24) else maxActions.coerceAtLeast(1),
        maxReplans = if (projectTask) maxReplans.coerceAtLeast(MAX_SUPERVISED_REPLANS) else maxReplans.coerceAtLeast(0),
        maxToolCalls = if (projectTask) maxToolCalls.coerceAtLeast(24) else maxToolCalls.coerceAtLeast(1),
        maxRetries = maxPhaseRetries,
        maxSameFailureAttempts = profile.maxSameFailureAttempts,
        noProgressTimeoutMillis = maxOf(
            noProgressTimeoutSeconds * 1_000L,
            profile.noProgressTimeoutMillis
        ),
        enforceCountLimits = !projectTask
    )
}

internal fun AgentTaskContext.persistExecutionLoop(event: AgentExecutionLoopEvent) {
    if (event.phase != AgentExecutionLoopPhase.CANCELLED) {
        cancellationSource.throwIfCancellationRequested()
    }
    appendEvent(
        kind = event.workspaceEventKind(),
        message = event.reason,
        payloadJson = AgentExecutionLoopJsonCodec.eventPayload(event)
    )
    checkpoint(
        checkpointId = event.checkpointId(),
        stateJson = AgentExecutionLoopJsonCodec.encode(event.snapshot)
    )
}

internal fun AgentTaskSupervisor.persistExecutionLoop(
    workspaceId: String,
    event: AgentExecutionLoopEvent
) {
    appendEvent(
        workspaceId = workspaceId,
        kind = event.workspaceEventKind(),
        message = event.reason,
        payloadJson = AgentExecutionLoopJsonCodec.eventPayload(event)
    )
    checkpoint(
        workspaceId = workspaceId,
        checkpointId = event.checkpointId(),
        stateJson = AgentExecutionLoopJsonCodec.encode(event.snapshot)
    )
}

private fun AgentExecutionLoopEvent.workspaceEventKind(): String =
    "agent.loop.${phase.name.lowercase(Locale.ROOT)}"

private fun AgentExecutionLoopEvent.checkpointId(): String =
    "loop-${snapshot.revision}"
