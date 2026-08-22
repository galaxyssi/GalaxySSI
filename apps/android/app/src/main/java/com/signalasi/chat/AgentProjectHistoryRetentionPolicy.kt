package com.signalasi.chat

/** Keeps verified project evidence without imposing a fixed action-count window. */
internal object AgentProjectHistoryRetentionPolicy {
    fun retain(actions: List<AgentAction>): List<AgentAction> {
        if (actions.sumOf(::estimatedContextCharacters) <= MAX_CONTEXT_CHARACTERS) return actions

        val selectedIndexes = linkedSetOf<Int>()
        if (actions.isNotEmpty()) selectedIndexes += actions.lastIndex

        val latestMilestones = linkedMapOf<String, Int>()
        val latestFailures = linkedMapOf<String, Int>()
        actions.forEachIndexed { index, action ->
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
            estimatedContextCharacters(actions[index])
        }
        actions.indices.reversed().forEach { index ->
            if (index in selectedIndexes) return@forEach
            val characters = estimatedContextCharacters(actions[index])
            if (selectedCharacters + characters <= MAX_CONTEXT_CHARACTERS) {
                selectedIndexes += index
                selectedCharacters += characters
            }
        }
        return selectedIndexes.sorted().map(actions::get)
    }

    private fun estimatedContextCharacters(action: AgentAction): Int =
        ACTION_CONTEXT_OVERHEAD +
            action.description.take(MAX_DESCRIPTION_CHARACTERS).length +
            action.parameters.entries.sumOf { (key, value) ->
                key.length + value.take(MAX_PARAMETER_CHARACTERS).length
            } +
            AgentPlannerObservation.from(action, MAX_OBSERVATION_CHARACTERS).orEmpty().length

    private fun AgentAction.failureContextKey(): String =
        "${parameters["tool_id"].orEmpty().ifBlank { target }.ifBlank { kind.name }}:${status.name}"

    private val unsuccessfulStatuses = setOf(
        AgentActionStatus.FAILED,
        AgentActionStatus.BLOCKED,
        AgentActionStatus.ROLLED_BACK
    )

    internal const val NON_PROJECT_RECENT_ACTION_LIMIT = 40
    private const val MAX_CONTEXT_CHARACTERS = 24_000
    private const val ACTION_CONTEXT_OVERHEAD = 192
    private const val MAX_DESCRIPTION_CHARACTERS = 320
    private const val MAX_PARAMETER_CHARACTERS = 1_200
    private const val MAX_OBSERVATION_CHARACTERS = 1_200
}
