package com.galaxyssi.chat

import java.util.Locale

enum class AgentExecutionLoopTimelineLabel {
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
    CANCELLED
}

enum class AgentExecutionLoopTimelineAction {
    PAUSE,
    RESUME,
    RETRY,
    REPLAN,
    CANCEL
}

data class AgentExecutionLoopTimelineProjection(
    val controlEventType: AgentRunControlEventType,
    val label: AgentExecutionLoopTimelineLabel?,
    val stepId: String,
    val toolCallId: String,
    val payload: AgentNativeJsonObject
)

enum class AgentRunTimelineKind {
    PLAN,
    TOOL,
    RESULT,
    FAILURE,
    RETRY,
    ACT,
    OBSERVE,
    VERIFY,
    LEARN,
    OTHER
}

data class AgentRunTimelineCoverage(
    val hasPlan: Boolean,
    val toolEventCount: Int,
    val hasResult: Boolean,
    val hasFailure: Boolean,
    val retryEventCount: Int
) {
    val terminal: Boolean
        get() = hasResult || hasFailure
    val complete: Boolean
        get() = hasPlan && terminal
}

object AgentRunTimelineContract {
    const val VERSION = "galaxyssi.run-timeline/1.0"

    fun kind(event: AgentRunControlEvent): AgentRunTimelineKind {
        val declared = event.payload["timeline_kind"]
            ?.toString()
            ?.trim()
            ?.uppercase(Locale.ROOT)
            ?.let { value -> AgentRunTimelineKind.entries.firstOrNull { it.name == value } }
        if (declared != null) return declared
        return when (event.type) {
            AgentRunControlEventType.PLANNING -> AgentRunTimelineKind.PLAN
            AgentRunControlEventType.TOOL_STARTED,
            AgentRunControlEventType.TOOL_PROGRESS,
            AgentRunControlEventType.TOOL_COMPLETED,
            AgentRunControlEventType.TOOL_PERMISSION_REQUIRED -> AgentRunTimelineKind.TOOL
            AgentRunControlEventType.RETRYING,
            AgentRunControlEventType.RUN_RECOVERED -> AgentRunTimelineKind.RETRY
            AgentRunControlEventType.RUN_COMPLETED -> AgentRunTimelineKind.RESULT
            AgentRunControlEventType.RUN_FAILED,
            AgentRunControlEventType.RUN_CANCELLED -> AgentRunTimelineKind.FAILURE
            else -> AgentRunTimelineKind.OTHER
        }
    }

    fun coverage(events: List<AgentRunControlEvent>): AgentRunTimelineCoverage {
        val kinds = events.map(::kind)
        return AgentRunTimelineCoverage(
            hasPlan = AgentRunTimelineKind.PLAN in kinds,
            toolEventCount = kinds.count { it == AgentRunTimelineKind.TOOL },
            hasResult = AgentRunTimelineKind.RESULT in kinds,
            hasFailure = AgentRunTimelineKind.FAILURE in kinds,
            retryEventCount = kinds.count { it == AgentRunTimelineKind.RETRY }
        )
    }
}

object AgentExecutionLoopTimelinePolicy {
    fun actionsForPhase(phase: AgentPhase): List<AgentExecutionLoopTimelineAction> = when (phase) {
        AgentPhase.PLANNING,
        AgentPhase.WAITING_CONFIRMATION,
        AgentPhase.EXECUTING,
        AgentPhase.VERIFYING -> listOf(
            AgentExecutionLoopTimelineAction.PAUSE,
            AgentExecutionLoopTimelineAction.CANCEL
        )
        AgentPhase.OBSERVING,
        AgentPhase.WAITING_RESPONSE -> listOf(AgentExecutionLoopTimelineAction.CANCEL)
        AgentPhase.PAUSED -> listOf(
            AgentExecutionLoopTimelineAction.RESUME,
            AgentExecutionLoopTimelineAction.CANCEL
        )
        AgentPhase.BLOCKED -> listOf(
            AgentExecutionLoopTimelineAction.REPLAN,
            AgentExecutionLoopTimelineAction.CANCEL
        )
        AgentPhase.FAILED -> listOf(
            AgentExecutionLoopTimelineAction.RETRY,
            AgentExecutionLoopTimelineAction.REPLAN
        )
        AgentPhase.CANCELLED,
        AgentPhase.COMPLETED -> emptyList()
    }

    fun project(event: AgentExecutionLoopEvent): AgentExecutionLoopTimelineProjection {
        val recovered = event.previousPhase in setOf(
            AgentExecutionLoopPhase.BLOCKED,
            AgentExecutionLoopPhase.FAILED
        ) && event.phase.isActive
        val phaseType = when (event.phase) {
            AgentExecutionLoopPhase.PLAN -> AgentRunControlEventType.PLANNING
            AgentExecutionLoopPhase.ACT -> if (event.toolCall) {
                AgentRunControlEventType.TOOL_STARTED
            } else {
                AgentRunControlEventType.STEP_STARTED
            }
            AgentExecutionLoopPhase.OBSERVE -> AgentRunControlEventType.TOOL_PROGRESS
            AgentExecutionLoopPhase.REPLAN -> AgentRunControlEventType.RETRYING
            AgentExecutionLoopPhase.VERIFY -> AgentRunControlEventType.TOOL_PROGRESS
            AgentExecutionLoopPhase.FINALIZE -> AgentRunControlEventType.STEP_COMPLETED
            AgentExecutionLoopPhase.LEARN -> AgentRunControlEventType.STEP_COMPLETED
            AgentExecutionLoopPhase.WAITING_CONFIRMATION -> AgentRunControlEventType.WAITING_FOR_USER
            AgentExecutionLoopPhase.WAITING_RESPONSE -> AgentRunControlEventType.WAITING_FOR_DEVICE
            AgentExecutionLoopPhase.PAUSED -> AgentRunControlEventType.PAUSED
            AgentExecutionLoopPhase.BLOCKED -> AgentRunControlEventType.RUN_FAILED
            AgentExecutionLoopPhase.FAILED -> AgentRunControlEventType.RUN_FAILED
            AgentExecutionLoopPhase.CANCELLED -> AgentRunControlEventType.RUN_CANCELLED
            AgentExecutionLoopPhase.COMPLETED -> AgentRunControlEventType.RUN_COMPLETED
        }
        val controlType = if (recovered) AgentRunControlEventType.RUN_RECOVERED else phaseType
        val label = event.phase.takeUnless { it == AgentExecutionLoopPhase.COMPLETED }
            ?.let { AgentExecutionLoopTimelineLabel.valueOf(it.name) }
        val actionId = event.snapshot.lastActionId
        val timelineKind = when (event.phase) {
            AgentExecutionLoopPhase.PLAN -> AgentRunTimelineKind.PLAN
            AgentExecutionLoopPhase.ACT -> if (event.toolCall) {
                AgentRunTimelineKind.TOOL
            } else {
                AgentRunTimelineKind.ACT
            }
            AgentExecutionLoopPhase.OBSERVE -> AgentRunTimelineKind.OBSERVE
            AgentExecutionLoopPhase.REPLAN -> AgentRunTimelineKind.RETRY
            AgentExecutionLoopPhase.VERIFY -> AgentRunTimelineKind.VERIFY
            AgentExecutionLoopPhase.FINALIZE,
            AgentExecutionLoopPhase.COMPLETED -> AgentRunTimelineKind.RESULT
            AgentExecutionLoopPhase.LEARN -> AgentRunTimelineKind.LEARN
            AgentExecutionLoopPhase.BLOCKED,
            AgentExecutionLoopPhase.FAILED,
            AgentExecutionLoopPhase.CANCELLED -> AgentRunTimelineKind.FAILURE
            AgentExecutionLoopPhase.WAITING_CONFIRMATION,
            AgentExecutionLoopPhase.WAITING_RESPONSE,
            AgentExecutionLoopPhase.PAUSED -> AgentRunTimelineKind.OTHER
        }
        return AgentExecutionLoopTimelineProjection(
            controlEventType = controlType,
            label = label,
            stepId = actionId,
            toolCallId = actionId.takeIf { event.toolCall }.orEmpty(),
            payload = mapOf(
                "timeline_contract" to AgentRunTimelineContract.VERSION,
                "timeline_kind" to timelineKind.name.lowercase(Locale.ROOT),
                "loop_phase" to event.phase.name.lowercase(Locale.ROOT),
                "previous_loop_phase" to event.previousPhase?.name.orEmpty().lowercase(Locale.ROOT),
                "loop_revision" to event.snapshot.revision,
                "loop_reason" to event.reason,
                "loop_task_id" to event.snapshot.taskId,
                "loop_action_id" to actionId,
                "loop_retry" to event.retry,
                "loop_tool_call" to event.toolCall,
                "loop_iterations" to event.snapshot.usage.iterations,
                "loop_actions" to event.snapshot.usage.actions,
                "loop_replans" to event.snapshot.usage.replans,
                "loop_tool_calls" to event.snapshot.usage.toolCalls,
                "loop_retries" to event.snapshot.usage.retries,
                "loop_active_ms" to event.snapshot.usage.activeDurationMillis,
                "loop_budget_failure" to event.snapshot.budgetFailure
            )
        )
    }

    fun isSameRevision(
        event: AgentRunControlEvent?,
        revision: Long
    ): Boolean = event?.payload?.get("loop_revision").toString().toLongOrNull() == revision

    fun transcriptDedupeKey(turnId: String, event: AgentExecutionLoopEvent): String =
        "agent-loop:$turnId:${event.phase.name}:${event.snapshot.revision}"

    fun phaseFromTranscriptDedupeKey(value: String): AgentExecutionLoopPhase? {
        if (!value.startsWith("agent-loop:")) return null
        val phaseName = value.split(':').getOrNull(2).orEmpty()
        return AgentExecutionLoopPhase.entries.firstOrNull { it.name == phaseName }
    }

    fun suppressSupersededPlaceholders(
        entries: List<AgentTranscriptEntry>
    ): List<AgentTranscriptEntry> {
        val hasToolStart = entries.any { it.dedupeKey.contains(":TOOL_STARTED:") }
        val hasToolCompletion = entries.any { it.dedupeKey.contains(":TOOL_COMPLETED:") }
        return entries.filterNot { entry ->
            when (phaseFromTranscriptDedupeKey(entry.dedupeKey)) {
                AgentExecutionLoopPhase.ACT -> hasToolStart
                AgentExecutionLoopPhase.OBSERVE -> hasToolCompletion
                else -> false
            }
        }
    }
}
