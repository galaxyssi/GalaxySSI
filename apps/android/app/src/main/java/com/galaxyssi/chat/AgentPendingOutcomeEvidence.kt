package com.galaxyssi.chat

/** Each uncertain effect needs its own host-bound observation and declared postcondition. */
internal object AgentPendingOutcomeEvidence {
    data class Pending(val receipt: AgentGoalEvidence.PendingReceipt, val diagnosis: String,
        val canInspect: Boolean = receipt.canInspect) {
        fun missingEvidence(): String = "Unverified action ${receipt.actionId} (${receipt.toolId}): $diagnosis. " +
            "${receipt.message} Inspect the original effect's recovery_query before retrying; verify the affected " +
            "subject with completion_requirements.outcomes. Unrelated success cannot settle this action. " +
            if (receipt.requiredCapability.isBlank()) "Repair only missing work; do not repeat an accepted effect."
            else "Required capability: ${receipt.requiredCapability}. Preserve this unresolved result while completing other work."
    }

    fun unresolved(requirements: AgentCompletionRequirements?, history: List<AgentAction>,
        descriptorFor: (String) -> AgentNativeToolDescriptor?): List<Pending> {
        val latest = AgentProjectHistoryRetentionPolicy.latestSnapshots(history)
        val indices = latest.withIndex().associate { it.value.id to it.index }
        return AgentGoalEvidence.pendingReceipts(latest).mapNotNull { receipt ->
            val index = indices.getValue(receipt.actionId)
            val origin = latest[index]
            val query = AgentRecoveryObservationEvidence.recoveryQuery(origin)
                ?: return@mapNotNull Pending(receipt, "origin_observation_contract_missing", false)
            val inspection = AgentRecoveryObservationEvidence.inspect(origin, origin, latest.drop(index + 1), descriptorFor)
            val observation = inspection.observation
                ?: return@mapNotNull Pending(receipt, inspection.diagnosis ?: "observation_missing",
                    receipt.canInspect && inspection.canInspect)
            // The exact receipt that passed provenance/freshness checks must also satisfy the goal.
            val outcomes = requirements?.outcomes.orEmpty().filter { outcome ->
                outcome.toolId == query.toolId && outcome.afterToolId == receipt.toolId &&
                    query.observedSubject.isNotEmpty() && query.observedSubject.all { (path, identity) ->
                        outcome.subject[path] == identity
                    }
            }
            if (outcomes.isEmpty()) return@mapNotNull Pending(receipt,
                "postcondition_binding_missing: after_tool_id=${receipt.toolId}; tool_id=${query.toolId}; " +
                    "subject must include ${AgentNativeJsonCodec.stringify(query.observedSubject)}")
            val scopedHistory = latest.filter { action ->
                action.parameters[INTERNAL_CONVERSATION_ID] == origin.parameters[INTERNAL_CONVERSATION_ID] &&
                    action.parameters[INTERNAL_TURN_ID] == origin.parameters[INTERNAL_TURN_ID]
            }
            val satisfied = outcomes.any { outcome ->
                AgentObservedOutcomeEvidence.diagnose(outcome.copy(afterToolId = ""), listOf(observation)) == null &&
                    AgentObservedOutcomeEvidence.diagnose(outcome, scopedHistory) == null
            }
            if (satisfied) null else Pending(receipt, "bound_postcondition_not_satisfied")
        }
    }
}
