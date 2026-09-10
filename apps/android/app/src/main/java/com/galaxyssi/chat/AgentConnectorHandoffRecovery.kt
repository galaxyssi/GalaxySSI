package com.galaxyssi.chat

/** A transport recovery is an attempt of one action, never an unscoped new action. */
internal object AgentConnectorHandoffRecovery {
    private const val OWNER = "handoff_recovery_action_id"

    fun prepare(action: AgentAction, sourceMessageId: Long, attempt: Int, sessionId: String): AgentAction {
        require(action.kind == AgentActionKind.CALL_CONNECTOR && sourceMessageId > 0L)
        require(attempt in 1..AgentPendingHandoffRecoveryPolicy.MAX_RECOVERY_ATTEMPTS)
        val key = action.parameters["idempotency_key"].orEmpty().ifBlank { "$sessionId:${action.id}" }
        return action.copy(status = AgentActionStatus.PENDING_CONFIRMATION, result = "", evidence = "",
            parameters = action.parameters + mapOf(
                OWNER to action.id,
                "handoff_recovery_attempt" to attempt.toString(),
                "superseded_source_message_id" to sourceMessageId.toString(),
                "idempotency_key" to "$key:handoff-recovery:$attempt"
            ))
    }

    fun effectAttemptKey(action: AgentAction): String {
        val base = AgentConnectorFallbackAction.effectAttemptKey(action)
        if (action.kind != AgentActionKind.CALL_CONNECTOR || action.parameters[OWNER] != action.id) return base
        val attempt = action.parameters["handoff_recovery_attempt"]?.toIntOrNull() ?: return base
        val source = action.parameters["superseded_source_message_id"]?.toLongOrNull() ?: return base
        if (attempt !in 1..AgentPendingHandoffRecoveryPolicy.MAX_RECOVERY_ATTEMPTS || source <= 0L) return base
        return "$base/handoff/$source/$attempt"
    }

    fun needsPreTimeoutObservation(metadata: Map<String, String>, stage: AgentConnectorTimeoutStage): Boolean {
        if (stage == AgentConnectorTimeoutStage.READ_ONLY_STALE) return false
        val status = AgentRemoteTaskStatusPolicy.normalize(metadata["remote_task_status"].orEmpty())
        val hasFallback = metadata["remaining_fallback_ids"].orEmpty().split(',').any { it.isNotBlank() }
        return AgentFailoverPolicy.shouldFailOver(stage, status, liveReadOnly = false) &&
            !AgentFailoverPolicy.shouldKeepOnlyResourceAlive(stage, status, hasFallback)
    }

    // Empty local outbox means delivered OR lost local state, not remote rejection.
    fun requiresRemoteObservation(metadata: Map<String, String>, hasDesktopBinding: Boolean): Boolean =
        hasDesktopBinding || metadata["resource_location"] == "desktop" ||
            metadata["remote_task_id"].orEmpty().isNotBlank() ||
            metadata["remote_task_status"].orEmpty().lowercase() in setOf(
                "accepted", "queued", "starting", "recovering", "running", "waiting_input", "waiting_approval",
                "waiting_on_user_input", "waiting_on_approval", "completed", "failed", "timed_out", "cancelled"
            )
}
