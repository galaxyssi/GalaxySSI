package com.signalasi.chat

/** Keeps verified project lifecycle anchors while bounding routine execution history. */
internal object AgentProjectHistoryRetentionPolicy {
    fun retain(actions: List<AgentAction>): List<AgentAction> {
        if (actions.size <= RECENT_ACTION_LIMIT) return actions

        val milestoneIndexes = linkedMapOf<String, Int>()
        actions.forEachIndexed { index, action ->
            AgentSupervisedProjectProgressPolicy.durableMilestoneKeys(action).forEach { key ->
                milestoneIndexes[key] = index
            }
        }
        val recentStart = actions.size - RECENT_ACTION_LIMIT
        val retainedMilestones = milestoneIndexes.values.toSet()
        return actions.filterIndexed { index, _ ->
            index >= recentStart || index in retainedMilestones
        }
    }

    internal const val RECENT_ACTION_LIMIT = 40
}
