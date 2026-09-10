package com.galaxyssi.chat

/** Durable dispatch for legacy actions without changing their admission, deadlines or routing. */
internal class AgentActionEffectExecutor(
    private val store: AgentNativeToolReplayStore,
    private val clock: AgentNativeClock = AgentNativeClock.SYSTEM
) {
    /** Read a scoped dispatch receipt only; this cannot execute or change its recorded input. */
    fun dispatchedResult(action: AgentAction, context: AgentNativeToolInvocationContext): AgentActionResult? {
        if (action.kind != AgentActionKind.CALL_CONNECTOR) return null
        val key = AgentNativeToolReplayKey("galaxyssi.action.dispatch", "1.0.0",
            AgentConnectorHandoffRecovery.effectAttemptKey(action), AgentNativeEffectScope.from(context))
        val claim = store.observe(key)?.takeIf { it.result != null } ?: return null
        return observe(action, claim.inputSha256, claim)
    }

    fun execute(
        action: AgentAction,
        screen: ScreenContext,
        context: AgentNativeToolInvocationContext,
        delegate: AgentActionExecutor
    ): AgentActionResult {
        if (action.kind == AgentActionKind.READ_SCREEN) return delegate.execute(action, screen)
        require(action.kind != AgentActionKind.CALL_NATIVE_TOOL) { "Native calls already have a journal" }
        require(action.id.isNotBlank()) { "A durable action requires a stable action ID" }
        val key = AgentNativeToolReplayKey("galaxyssi.action.dispatch",
            "1.0.0", AgentConnectorHandoffRecovery.effectAttemptKey(action), AgentNativeEffectScope.from(context))
        val digest = AgentNativeJsonCodec.sha256(mapOf("kind" to action.kind.name, "target" to action.target,
            "description" to action.description, "parameters" to action.parameters,
            "risk" to action.risk.name, "requires_confirmation" to action.requiresConfirmation))
        val startedAt = clock.nowEpochMillis()
        try {
            store.observe(key)?.let { return observe(action, digest, it) }
            val claim = store.claim(key, digest, context.invocationId)
            if (!claim.acquired) return observe(action, digest, claim)
        } catch (error: Exception) {
            return failure(action, "action_effect_journal_unavailable",
                "Action was not dispatched because its execution journal could not be read or claimed: ${error.message}")
        }

        val outcome = try {
            delegate.execute(action, screen)
        } catch (error: Exception) {
            failure(action, "action_execution_failed",
                "Action execution failed; inspect external state before a new action: ${error.message}")
        }
        // Do not replace a returned outcome with a late cancellation or observation timeout.
        return try {
            val packed = pack(action, key, context.invocationId, digest, startedAt, outcome)
            store.complete(key, context.invocationId, packed)
            outcome
        } catch (error: Exception) {
            failure(action, "effect_outcome_unknown",
                "Action ran but its outcome could not be committed: ${error.message}. " +
                    "Observe external state before proposing a new action.")
        }
    }

    private fun observe(action: AgentAction, digest: String, claim: AgentNativeEffectClaim): AgentActionResult {
        if (claim.inputSha256 != digest) return failure(action, "idempotency_key_conflict",
            "The same action ID was already used with different execution input")
        val saved = claim.result ?: return failure(action, "effect_outcome_unknown",
            "This action already started without a durable outcome. It was not dispatched again. " +
                "Observe external state before deciding the next action.",
            mapOf("original_invocation_id" to claim.invocationId))
        val output = saved.output
        val metadata = requireNotNull(output["metadata"] as? Map<*, *>) { "Missing action result metadata" }
        require(metadata.all { it.key is String && it.value is String }) { "Invalid action result metadata" }
        val success = requireNotNull(output["success"] as? Boolean) { "Missing action result status" }
        require(success == saved.isSuccess) { "Action receipt status mismatch" }
        return AgentActionResult(
            actionId = requireNotNull(output["action_id"] as? String), success = success,
            message = requireNotNull(output["message"] as? String),
            metadata = metadata.entries.associate { it.key as String to it.value as String } +
                mapOf("action_effect_replayed" to "true", "original_invocation_id" to claim.invocationId))
    }

    private fun pack(action: AgentAction, key: AgentNativeToolReplayKey, invocationId: String, inputDigest: String,
        startedAt: Long, outcome: AgentActionResult): AgentNativeToolResult {
        val execution = AgentNativeToolAgentActionAdapter.fromAgentActionResult(outcome)
        val status = if (outcome.success) AgentNativeToolResultStatus.SUCCEEDED else AgentNativeToolResultStatus.FAILED
        val finishedAt = clock.nowEpochMillis()
        return AgentNativeToolResult(status, execution.output, outcome.message, emptyMap(), execution.error, null,
            AgentNativeToolReceipt(invocationId, key.idempotencyKey, startedAt, finishedAt,
                (finishedAt - startedAt).coerceAtLeast(0), status, inputDigest, AgentNativeJsonCodec.sha256(execution.output)),
            AgentNativeToolProvenance(key.toolId, key.toolVersion, AgentNativeToolLocation.PHONE,
                "galaxyssi.action_effect", AgentNativeToolRegistry.CONTRACT_VERSION, action.id))
    }

    private fun failure(action: AgentAction, code: String, message: String, details: Map<String, String> = emptyMap()) =
        AgentActionResult(action.id, false, message, details + mapOf("error_code" to code, "action_effect_status" to code))
}
