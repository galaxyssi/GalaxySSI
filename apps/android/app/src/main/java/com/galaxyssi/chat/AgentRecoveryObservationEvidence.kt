package com.galaxyssi.chat

import org.json.JSONObject

/** Host receipts bind recovery observations to the original effect, not to model-authored claims. */
internal object AgentRecoveryObservationEvidence {
    const val KEY = "_observation_receipt"
    const val QUERY_KEY = "effect_recovery_query"

    fun recoveryQuery(action: AgentAction): AgentNativeEffectRecoveryQuery? = output(action)?.optJSONObject(KEY)
        ?.optJSONObject("recovery_query")?.let { runCatching {
            AgentNativeEffectRecoveryQuery.fromJsonValue(it.toNativeObject())
        }.getOrNull() }

    fun hasContract(action: AgentAction): Boolean = recoveryQuery(action) != null

    fun compactOriginEvidence(value: String, limit: Int): String {
        val json = runCatching { JSONObject(value) }.getOrNull()
        val proof = json?.optJSONObject(KEY)
        if (proof?.optJSONObject("recovery_query") == null) {
            return AgentWebObservation.compact(value, limit, preserveReceipt = true) ?: value.take(limit)
        }
        if (value.length <= AgentSessionPersistencePolicy.MAX_ACTION_TEXT_CHARACTERS) return value
        val compact = JSONObject().put(KEY, proof).put("state_verified", false).toString()
        return compact.takeIf { it.length <= AgentSessionPersistencePolicy.MAX_ACTION_TEXT_CHARACTERS }
            ?: value.take(limit)
    }

    fun attach(output: AgentNativeJsonObject, result: AgentNativeToolResult,
        context: AgentNativeToolInvocationContext, descriptor: AgentNativeToolDescriptor): AgentNativeJsonObject {
        val query = result.metadata[QUERY_KEY]
        if (descriptor.requiresEffectClaim && query == null) return output - KEY
        return output + (KEY to mapOf(
            "tool_id" to result.provenance.toolId, "tool_version" to result.provenance.toolVersion,
            "status" to result.status.wireValue, "invocation_id" to result.receipt.invocationId,
            "input_sha256" to result.receipt.inputSha256, "replayed" to result.receipt.replayed,
            "started_at_ms" to result.receipt.startedAtEpochMillis,
            "finished_at_ms" to result.receipt.finishedAtEpochMillis,
            "conversation_id" to context.conversationId, "turn_id" to context.turnId,
            "recovery_query" to query))
    }

    fun diagnose(origin: AgentAction, connector: AgentAction, later: List<AgentAction>,
        descriptorFor: (String) -> AgentNativeToolDescriptor?): String? =
        inspect(origin, connector, later, descriptorFor).diagnosis

    data class Inspection(val observation: AgentAction? = null, val diagnosis: String? = null,
        val canInspect: Boolean = true)

    fun inspect(origin: AgentAction, connector: AgentAction, later: List<AgentAction>,
        descriptorFor: (String) -> AgentNativeToolDescriptor?): Inspection {
        fun failure(reason: String, canInspect: Boolean = true) = Inspection(diagnosis = reason, canInspect = canInspect)
        val originProof = output(origin)?.optJSONObject(KEY) ?: return failure("origin_observation_contract_missing", false)
        val conversation = origin.parameters[INTERNAL_CONVERSATION_ID].orEmpty()
        val turn = origin.parameters[INTERNAL_TURN_ID].orEmpty()
        if (conversation.isBlank() || turn.isBlank() || connector.parameters[INTERNAL_CONVERSATION_ID] != conversation ||
            connector.parameters[INTERNAL_TURN_ID] != turn || originProof.optString("conversation_id") != conversation ||
            originProof.optString("turn_id") != turn || originProof.optString("tool_id") != origin.parameters["tool_id"])
            return failure("origin_scope_mismatch", false)
        val finished = originProof.optLong("finished_at_ms")
        if (finished <= 0 || originProof.optString("invocation_id").isBlank()) return failure("origin_receipt_invalid", false)
        val query = runCatching { AgentNativeEffectRecoveryQuery.fromJsonValue(
            originProof.getJSONObject("recovery_query").toNativeObject()) }.getOrNull()
            ?: return failure("origin_observation_contract_missing", false)
        val descriptor = descriptorFor(query.toolId)
        if (descriptor == null || descriptor.requiresEffectClaim || descriptor.version != query.toolVersion)
            return failure("observation_contract_unavailable: ${query.toolId} ${query.toolVersion}", false)
        val inputHash = AgentNativeJsonCodec.sha256(query.arguments)
        for (action in later.asReversed()) {
            if (action.kind != AgentActionKind.CALL_NATIVE_TOOL || action.parameters["tool_id"] != query.toolId ||
                action.parameters[INTERNAL_CONVERSATION_ID] != conversation || action.parameters[INTERNAL_TURN_ID] != turn ||
                action.status in setOf(AgentActionStatus.PROPOSED, AgentActionStatus.PENDING_CONFIRMATION)) continue
            val observed = output(action) ?: return failure("observation_receipt_missing")
            val proof = observed.optJSONObject(KEY)
            // A different operation's read is irrelevant; a missing receipt is uncertainty, never old success.
            if (proof != null && proof.optString("input_sha256").isNotBlank() &&
                proof.optString("input_sha256") != inputHash) continue
            if (proof == null) return failure("observation_receipt_missing")
            if (action.status != AgentActionStatus.COMPLETED || proof.optString("status") != "succeeded")
                return failure("observation_not_succeeded")
            if (proof.optString("conversation_id") != conversation || proof.optString("turn_id") != turn ||
                proof.optString("tool_id") != query.toolId || proof.optString("tool_version") != query.toolVersion ||
                proof.optString("input_sha256") != inputHash) return failure("observation_identity_mismatch")
            if (proof.opt("replayed") != false || proof.optString("invocation_id").isBlank() ||
                proof.optString("invocation_id") == originProof.optString("invocation_id") ||
                proof.optLong("started_at_ms") < finished || proof.optLong("finished_at_ms") < proof.optLong("started_at_ms"))
                return failure("observation_not_fresh")
            if (AgentSupervisedProjectRecoveryPolicy.hasUnknownOutcome(action)) return failure("observation_outcome_unknown")
            val missing = query.observedSubject.filter { (path, value) ->
                AgentObservedOutputFields.at(observed, path)?.toString() != value
            }.keys
            if (missing.isNotEmpty()) return failure("observation_subject_mismatch: ${missing.joinToString()}")
            return Inspection(observation = action)
        }
        return failure("observation_missing: ${AgentNativeJsonCodec.stringify(query.toJsonValue())}")
    }

    private fun output(action: AgentAction): JSONObject? = runCatching { JSONObject(action.evidence) }.getOrNull()
        ?.let { it.optJSONObject("output") ?: it }
}
