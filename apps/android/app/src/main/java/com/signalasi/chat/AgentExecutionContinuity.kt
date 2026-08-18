package com.signalasi.chat

import java.util.UUID

enum class AgentCheckpointStatus {
    ACTIVE,
    RESTORED,
    INVALIDATED
}

data class AgentExecutionCheckpoint(
    val id: String,
    val actionId: String,
    val planRevision: Int,
    val foregroundApp: String,
    val activityName: String,
    val pageTitle: String,
    val screenDigest: String,
    val rollbackAction: AgentAction? = null,
    val status: AgentCheckpointStatus = AgentCheckpointStatus.ACTIVE,
    val createdAtMillis: Long = System.currentTimeMillis()
)

object AgentExecutionContinuity {
    fun checkpointBefore(action: AgentAction, screen: ScreenContext, planRevision: Int): AgentExecutionCheckpoint =
        AgentExecutionCheckpoint(
            id = UUID.randomUUID().toString(),
            actionId = action.id,
            planRevision = planRevision,
            foregroundApp = screen.foregroundApp,
            activityName = screen.activityName,
            pageTitle = screen.pageTitle,
            screenDigest = screenDigest(screen),
            rollbackAction = rollbackActionFor(action)
        )

    fun screenDigest(screen: ScreenContext): String = listOf(
        screen.foregroundApp,
        screen.activityName,
        screen.pageTitle,
        screen.visibleTexts.take(40).joinToString("\u001f"),
        screen.clickableNodeCount.toString(),
        screen.inputFieldCount.toString()
    ).joinToString("\u001e").hashCode().toString()

    private fun rollbackActionFor(action: AgentAction): AgentAction? = when (action.kind) {
        AgentActionKind.OPEN_APP,
        AgentActionKind.OPEN_URL,
        AgentActionKind.RECENTS -> AgentAction(
            id = "rollback-${action.id}",
            kind = AgentActionKind.BACK,
            target = action.target,
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Return to the screen before ${action.description}",
            requiresConfirmation = false
        )

        AgentActionKind.SWIPE -> reverseSwipe(action)
        else -> null
    }

    private fun reverseSwipe(action: AgentAction): AgentAction? {
        val fromX = action.parameters["from_x"] ?: return null
        val fromY = action.parameters["from_y"] ?: return null
        val toX = action.parameters["to_x"] ?: return null
        val toY = action.parameters["to_y"] ?: return null
        return AgentAction(
            id = "rollback-${action.id}",
            kind = AgentActionKind.SWIPE,
            target = action.target,
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Reverse the previous swipe",
            parameters = mapOf(
                "from_x" to toX,
                "from_y" to toY,
                "to_x" to fromX,
                "to_y" to fromY
            ),
            requiresConfirmation = false
        )
    }
}

fun AgentPlan.addCheckpoint(checkpoint: AgentExecutionCheckpoint): AgentPlan = copy(
    checkpoints = (checkpoints + checkpoint).takeLast(20)
)

fun AgentPlan.markCheckpoint(checkpointId: String, status: AgentCheckpointStatus): AgentPlan = copy(
    checkpoints = checkpoints.map { checkpoint ->
        if (checkpoint.id == checkpointId) checkpoint.copy(status = status) else checkpoint
    }
)

fun AgentPlan.recoverInterruptedExecution(): AgentPlan = copy(
    actions = actions.map { action ->
        if (action.status == AgentActionStatus.RUNNING) {
            action.copy(
                status = AgentActionStatus.FAILED,
                result = "The app process ended before this action produced a verified result",
                evidence = AGENT_INTERRUPTED_EXECUTION_EVIDENCE
            )
        } else {
            action
        }
    }
)

fun AgentPlan.hasInterruptedExecutionEvidence(): Boolean =
    (actionHistory + actions).any { action ->
        action.evidence == AGENT_INTERRUPTED_EXECUTION_EVIDENCE
    }

fun AgentPlan.hasPendingInterruptedRecovery(): Boolean =
    (actionHistory + actions).any { action ->
        action.evidence in setOf(
            AGENT_INTERRUPTED_EXECUTION_EVIDENCE,
            AGENT_INTERRUPTED_RECOVERY_SCHEDULED_EVIDENCE
        )
    }

fun AgentPlan.markConnectorDeliveryFailed(actionId: String, sourceMessageId: Long): AgentPlan {
    if (sourceMessageId <= 0L) return this
    val marker = "$AGENT_CONNECTOR_DELIVERY_FAILED_EVIDENCE_PREFIX$sourceMessageId"
    fun AgentAction.mark(): AgentAction =
        if (id == actionId) copy(evidence = marker) else this
    return copy(
        actions = actions.map(AgentAction::mark),
        actionHistory = actionHistory.map(AgentAction::mark)
    )
}

fun AgentPlan.connectorDeliveryFailureSourceMessageId(): Long? =
    (actions.asReversed() + actionHistory.asReversed())
        .asSequence()
        .mapNotNull { action ->
            action.evidence
                .takeIf { it.startsWith(AGENT_CONNECTOR_DELIVERY_FAILED_EVIDENCE_PREFIX) }
                ?.removePrefix(AGENT_CONNECTOR_DELIVERY_FAILED_EVIDENCE_PREFIX)
                ?.toLongOrNull()
                ?.takeIf { it > 0L }
        }
        .firstOrNull()

object AgentInterruptedWorkspaceRecoveryPolicy {
    fun shouldResume(
        workspaceStatus: AgentWorkspaceStatus,
        phase: AgentPhase,
        plan: AgentPlan?,
        lastActionResult: AgentActionResult?
    ): Boolean =
        workspaceStatus !in setOf(AgentWorkspaceStatus.COMPLETED, AgentWorkspaceStatus.CANCELLED) &&
            phase == AgentPhase.PAUSED &&
            plan != null &&
            (lastActionResult?.actionId == "agent-interrupted" ||
                AgentInterruptedDispatchRecoveryPolicy.completedAction(plan, lastActionResult) != null)
}

/**
 * Detects the narrow process-death window after a native tool returned and its
 * result was persisted, but before the Agent loop observed that result.
 */
object AgentInterruptedDispatchRecoveryPolicy {
    fun completedAction(plan: AgentPlan?, result: AgentActionResult?): AgentAction? {
        if (plan == null || result?.success != true || result.actionId.isBlank()) return null
        if (result.metadata["native_tool_status"] != AgentNativeToolResultStatus.SUCCEEDED.wireValue) return null
        if (result.metadata["invocation_id"].isNullOrBlank()) return null
        return plan.actions.firstOrNull { action ->
            action.id == result.actionId && action.status == AgentActionStatus.RUNNING
        }
    }
}

object AgentWorkspaceRestorePolicy {
    fun shouldRestore(
        workspaceStatus: AgentWorkspaceStatus,
        phase: AgentPhase,
        belongsToCurrentConversation: Boolean,
        hasPendingAction: Boolean,
        interruptedRecovery: Boolean,
        interruptedHandoffRecovery: Boolean = false,
        failedDeliveryRecovery: Boolean = false
    ): Boolean = interruptedRecovery || interruptedHandoffRecovery || failedDeliveryRecovery || when (workspaceStatus) {
        AgentWorkspaceStatus.RUNNING -> false
        AgentWorkspaceStatus.WAITING_CONFIRMATION ->
            belongsToCurrentConversation &&
                phase == AgentPhase.WAITING_CONFIRMATION &&
                hasPendingAction
        AgentWorkspaceStatus.WAITING_RESPONSE -> phase == AgentPhase.WAITING_RESPONSE
        AgentWorkspaceStatus.PAUSED ->
            belongsToCurrentConversation && phase == AgentPhase.PAUSED
        AgentWorkspaceStatus.FAILED -> phase == AgentPhase.WAITING_RESPONSE
        else -> false
    }
}

object AgentConnectorDeliveryRecoveryPolicy {
    fun shouldResume(
        workspaceStatus: AgentWorkspaceStatus,
        phase: AgentPhase,
        lastActionResult: AgentActionResult?,
        plan: AgentPlan?
    ): Boolean = workspaceStatus == AgentWorkspaceStatus.FAILED &&
        phase == AgentPhase.FAILED &&
        plan != null &&
        (plan.connectorDeliveryFailureSourceMessageId() ?: metadataSource(lastActionResult)) != null

    private fun metadataSource(result: AgentActionResult?): Long? = result
        ?.takeIf { it.metadata["delivery_failed"] == "true" }
        ?.metadata
        ?.get("source_message_id")
        ?.toLongOrNull()
        ?.takeIf { it > 0L }
}

object AgentWorkspaceRestoreArbitrationPolicy {
    fun shouldScanPersistedWorkspaces(
        hasLiveRuntimeInConversation: Boolean,
        hasActiveSupervisorTaskInConversation: Boolean
    ): Boolean = !hasLiveRuntimeInConversation && !hasActiveSupervisorTaskInConversation

    fun belongsToActiveConversation(
        candidateConversationId: String,
        activeConversationId: String
    ): Boolean = candidateConversationId.isNotBlank() &&
        activeConversationId.isNotBlank() &&
        candidateConversationId == activeConversationId

    fun stillOwnsRecovery(
        candidateWorkspaceId: String,
        startedConversationId: String,
        currentConversationId: String,
        activeSupervisorWorkspaceIds: Set<String>,
        liveRuntimeWorkspaceIds: Set<String>
    ): Boolean {
        if (!belongsToActiveConversation(startedConversationId, currentConversationId)) return false
        val competingSupervisorTask = activeSupervisorWorkspaceIds.any {
            it.isNotBlank() && it != candidateWorkspaceId
        }
        val competingRuntime = liveRuntimeWorkspaceIds.any {
            it.isNotBlank() && it != candidateWorkspaceId
        }
        return !competingSupervisorTask && !competingRuntime
    }
}

object AgentPendingHandoffRecoveryPolicy {
    const val MAX_RECOVERY_ATTEMPTS = 2

    fun shouldRecover(
        phase: AgentPhase,
        sourceMessageId: Long,
        remainsInReliableOutbox: Boolean,
        metadata: Map<String, String>,
        nowMillis: Long = System.currentTimeMillis(),
        staleAfterMillis: Long = 90_000L
    ): Boolean {
        return isStranded(
            phase,
            sourceMessageId,
            remainsInReliableOutbox,
            metadata,
            nowMillis,
            staleAfterMillis
        ) && recoveryAttempt(metadata) < MAX_RECOVERY_ATTEMPTS
    }

    fun recoveryAttempt(metadata: Map<String, String>): Int =
        metadata["handoff_recovery_attempt"]?.toIntOrNull()?.coerceAtLeast(0) ?: 0

    fun interruptedRecoveryAction(
        phase: AgentPhase,
        plan: AgentPlan?
    ): AgentAction? {
        if (phase != AgentPhase.BLOCKED) return null
        return plan?.actions?.firstOrNull { action ->
            action.kind == AgentActionKind.CALL_CONNECTOR &&
                recoveryAttempt(action.parameters) in 1..MAX_RECOVERY_ATTEMPTS &&
                action.parameters["superseded_source_message_id"]?.toLongOrNull()?.let { it > 0L } == true &&
                action.status in setOf(
                    AgentActionStatus.PROPOSED,
                    AgentActionStatus.PENDING_CONFIRMATION,
                    AgentActionStatus.BLOCKED
                )
        }
    }

    fun isExhausted(
        phase: AgentPhase,
        sourceMessageId: Long,
        remainsInReliableOutbox: Boolean,
        metadata: Map<String, String>,
        nowMillis: Long = System.currentTimeMillis(),
        staleAfterMillis: Long = 90_000L
    ): Boolean = isStranded(
        phase,
        sourceMessageId,
        remainsInReliableOutbox,
        metadata,
        nowMillis,
        staleAfterMillis
    ) && recoveryAttempt(metadata) >= MAX_RECOVERY_ATTEMPTS

    private fun isStranded(
        phase: AgentPhase,
        sourceMessageId: Long,
        remainsInReliableOutbox: Boolean,
        metadata: Map<String, String>,
        nowMillis: Long,
        staleAfterMillis: Long
    ): Boolean {
        if (phase != AgentPhase.WAITING_RESPONSE || sourceMessageId <= 0L) return false
        if (remainsInReliableOutbox) return false
        val status = metadata["remote_task_status"].orEmpty().lowercase()
        if (status in setOf("running", "waiting_on_approval", "waiting_on_user_input")) return false
        if (status !in setOf("", "accepted", "queued", "starting")) return false
        val acceptedAt = sequenceOf(
            metadata["remote_task_status_updated_at"],
            metadata["transport_accepted_at"],
            metadata["resource_started_at"]
        ).mapNotNull { it?.toLongOrNull() }.maxOrNull() ?: 0L
        if (status.isBlank() && metadata["transport_accepted_at"].orEmpty().isBlank()) return true
        if (acceptedAt <= 0L) return true
        return nowMillis - acceptedAt >= staleAfterMillis.coerceAtLeast(1L)
    }
}

fun AgentPlan.markInterruptedRecoveryScheduled(): AgentPlan = copy(
    actions = actions.map(AgentAction::markInterruptedRecoveryScheduled),
    actionHistory = actionHistory.map(AgentAction::markInterruptedRecoveryScheduled)
)

fun AgentPlan.historyForReplan(): List<AgentAction> =
    (actionHistory + actions.filter { action ->
        action.status in setOf(
            AgentActionStatus.COMPLETED,
            AgentActionStatus.FAILED,
            AgentActionStatus.BLOCKED,
            AgentActionStatus.ROLLED_BACK
        )
    }).takeLast(40)

private fun AgentAction.markInterruptedRecoveryScheduled(): AgentAction =
    if (evidence == AGENT_INTERRUPTED_EXECUTION_EVIDENCE) {
        copy(evidence = AGENT_INTERRUPTED_RECOVERY_SCHEDULED_EVIDENCE)
    } else {
        this
    }

internal const val AGENT_INTERRUPTED_EXECUTION_EVIDENCE = "interrupted_unverified"
internal const val AGENT_INTERRUPTED_RECOVERY_SCHEDULED_EVIDENCE = "interrupted_recovery_scheduled"
internal const val AGENT_CONNECTOR_DELIVERY_FAILED_EVIDENCE_PREFIX = "connector_delivery_failed:"
