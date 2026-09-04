package com.galaxyssi.chat

/** Keeps verified project evidence without imposing a fixed action-count window. */
internal object AgentProjectHistoryRetentionPolicy {
    fun retain(actions: List<AgentAction>): List<AgentAction> {
        val latestActions = latestSnapshots(actions)
        if (latestActions.sumOf(::estimatedContextCharacters) <= MAX_CONTEXT_CHARACTERS) {
            return latestActions
        }

        val selectedIndexes = linkedSetOf<Int>()
        if (latestActions.isNotEmpty()) selectedIndexes += latestActions.lastIndex

        val latestMilestones = linkedMapOf<String, Int>()
        val latestFailures = linkedMapOf<String, Int>()
        latestActions.forEachIndexed { index, action ->
            AgentSupervisedProjectProgressPolicy.durableMilestoneKeys(action).forEach { key ->
                latestMilestones[key] = index
            }
            if (action.status in unsuccessfulStatuses) {
                latestFailures[action.failureContextKey()] = index
            }
        }
        selectedIndexes += latestMilestones.values
        selectedIndexes += latestFailures.values

        var selectedCharacters = selectedIndexes.sumOf { index ->
            estimatedContextCharacters(latestActions[index])
        }
        latestActions.indices.reversed().forEach { index ->
            if (index in selectedIndexes) return@forEach
            val characters = estimatedContextCharacters(latestActions[index])
            if (selectedCharacters + characters <= MAX_CONTEXT_CHARACTERS) {
                selectedIndexes += index
                selectedCharacters += characters
            }
        }
        return selectedIndexes.sorted().map(latestActions::get)
    }

    fun latestSnapshots(actions: List<AgentAction>): List<AgentAction> {
        if (actions.size < 2) return actions
        val retained = ArrayList<AgentAction>(actions.size)
        val seenIds = hashSetOf<String>()
        actions.asReversed().forEach { action ->
            if (action.id.isBlank() || seenIds.add(action.id)) retained += action
        }
        retained.reverse()
        return retained
    }

    /**
     * Keeps the same semantic ledger across process death without letting one checkpoint consume the
     * complete encrypted-session budget. Runtime replanning and durable storage intentionally use
     * separate size estimates because JSON persistence retains more action detail than the prompt.
     */
    fun retainForPersistence(actions: List<AgentAction>): List<AgentAction> {
        val contextRetained = retain(actions)
        if (estimatedPersistenceCharacters(contextRetained) <= MAX_PERSISTED_HISTORY_CHARACTERS) {
            return contextRetained
        }

        val selectedIndexes = linkedSetOf<Int>()
        if (contextRetained.isNotEmpty()) selectedIndexes += contextRetained.lastIndex

        val semanticIndexes = linkedSetOf<Int>()
        val latestMilestones = linkedMapOf<String, Int>()
        val latestFailures = linkedMapOf<String, Int>()
        contextRetained.forEachIndexed { index, action ->
            AgentSupervisedProjectProgressPolicy.durableMilestoneKeys(action).forEach { key ->
                latestMilestones[key] = index
            }
            if (action.status in unsuccessfulStatuses) {
                latestFailures[action.failureContextKey()] = index
            }
        }
        semanticIndexes += latestMilestones.values
        semanticIndexes += latestFailures.values

        var selectedCharacters = selectedIndexes.sumOf { index ->
            estimatedPersistenceCharacters(contextRetained[index])
        }
        semanticIndexes.sortedDescending().forEach { index ->
            if (index in selectedIndexes) return@forEach
            val characters = estimatedPersistenceCharacters(contextRetained[index])
            if (selectedCharacters + characters <= MAX_PERSISTED_HISTORY_CHARACTERS) {
                selectedIndexes += index
                selectedCharacters += characters
            }
        }
        contextRetained.indices.reversed().forEach { index ->
            if (index in selectedIndexes) return@forEach
            val characters = estimatedPersistenceCharacters(contextRetained[index])
            if (selectedCharacters + characters <= MAX_PERSISTED_HISTORY_CHARACTERS) {
                selectedIndexes += index
                selectedCharacters += characters
            }
        }
        return selectedIndexes.sorted().map(contextRetained::get)
    }

    internal fun estimatedPersistenceCharacters(actions: List<AgentAction>): Int =
        actions.sumOf(::estimatedPersistenceCharacters)

    private fun estimatedContextCharacters(action: AgentAction): Int =
        ACTION_CONTEXT_OVERHEAD +
            action.description.take(MAX_DESCRIPTION_CHARACTERS).length +
            action.parameters.entries.sumOf { (key, value) ->
                key.length + value.take(MAX_PARAMETER_CHARACTERS).length
            } +
            AgentPlannerObservation.from(action, MAX_OBSERVATION_CHARACTERS).orEmpty().length

    private fun estimatedPersistenceCharacters(action: AgentAction): Int =
        PERSISTED_ACTION_OVERHEAD +
            action.id.length +
            action.kind.name.length +
            action.target.length +
            action.status.name.length +
            action.description.take(AgentSessionPersistencePolicy.MAX_ACTION_TEXT_CHARACTERS).length +
            action.result.take(AgentSessionPersistencePolicy.MAX_ACTION_TEXT_CHARACTERS).length +
            action.evidence.take(AgentSessionPersistencePolicy.MAX_ACTION_TEXT_CHARACTERS).length +
            AgentSessionPersistencePolicy.compactMetadata(action.parameters).entries.sumOf { (key, value) ->
                key.length + value.length + PERSISTED_METADATA_ENTRY_OVERHEAD
            }

    private fun AgentAction.failureContextKey(): String =
        "${parameters["tool_id"].orEmpty().ifBlank { target }.ifBlank { kind.name }}:${status.name}"

    private val unsuccessfulStatuses = setOf(
        AgentActionStatus.FAILED,
        AgentActionStatus.BLOCKED,
        AgentActionStatus.ROLLED_BACK
    )

    internal const val NON_PROJECT_RECENT_ACTION_LIMIT = 40
    private const val MAX_CONTEXT_CHARACTERS = 24_000
    internal const val MAX_PERSISTED_HISTORY_CHARACTERS = 48 * 1024
    private const val ACTION_CONTEXT_OVERHEAD = 192
    private const val PERSISTED_ACTION_OVERHEAD = 320
    private const val PERSISTED_METADATA_ENTRY_OVERHEAD = 12
    private const val MAX_DESCRIPTION_CHARACTERS = 320
    private const val MAX_PARAMETER_CHARACTERS = 1_200
    private const val MAX_OBSERVATION_CHARACTERS = 1_200
}
