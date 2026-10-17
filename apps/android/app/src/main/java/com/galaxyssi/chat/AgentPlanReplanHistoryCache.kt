package com.galaxyssi.chat

import java.lang.ref.WeakReference

internal object AgentPlanReplanHistoryCache {
    private data class CachedHistory(
        val actionHistory: WeakReference<List<AgentAction>>,
        val actions: WeakReference<List<AgentAction>>,
        val plannerProfile: String,
        val value: List<AgentAction>
    )

    private val cacheLock = Any()
    private val histories = mutableListOf<CachedHistory>()

    fun resolve(plan: AgentPlan): List<AgentAction> = resolve(
        actionHistory = plan.actionHistory,
        actions = plan.actions,
        plannerProfile = plan.plannerProfile
    ) { actionHistory, actions, plannerProfile ->
        compile(actionHistory, actions, plannerProfile)
    }

    internal fun resolve(
        actionHistory: List<AgentAction>,
        actions: List<AgentAction>,
        plannerProfile: String,
        compiler: (List<AgentAction>, List<AgentAction>, String) -> List<AgentAction>
    ): List<AgentAction> {
        synchronized(cacheLock) {
            takeCached(actionHistory, actions, plannerProfile)
        }?.let { cached ->
            return cached.value
        }

        val value = compiler(actionHistory, actions, plannerProfile)
        return synchronized(cacheLock) {
            val cached = takeCached(actionHistory, actions, plannerProfile)
            if (cached != null) return@synchronized cached.value
            value.also {
                histories += CachedHistory(
                    actionHistory = WeakReference(actionHistory),
                    actions = WeakReference(actions),
                    plannerProfile = plannerProfile,
                    value = value
                )
                while (histories.size > MAX_CACHED_HISTORIES) histories.removeAt(0)
            }
        }
    }

    private fun compile(
        actionHistory: List<AgentAction>,
        actions: List<AgentAction>,
        plannerProfile: String
    ): List<AgentAction> {
        val supervised = plannerProfile == PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE ||
            actionHistory.any(AgentAction::isSupervisedProjectConnector) ||
            actions.any(AgentAction::isSupervisedProjectConnector)
        val terminalActions = AgentProjectHistoryRetentionPolicy.latestSnapshots(
            buildList(actionHistory.size + actions.size) {
                addAll(actionHistory)
                actions.filterTo(this) { action ->
                    action.status in TERMINAL_ACTION_STATUSES
                }
            }
        )
        return if (supervised) {
            // Planner requests repeat prior context; they are not tool observations. Budgeting them
            // first can evict the fresh receipt that the next model turn needs to finish the goal.
            val retainedIds = AgentProjectHistoryRetentionPolicy.retain(
                terminalActions.filterNot(AgentAction::isSupervisedProjectConnector)
            ).mapTo(hashSetOf(), AgentAction::id)
            terminalActions.mapNotNull { action ->
                when {
                    action.isSupervisedProjectConnector() -> action.copy(description = "", result = "", evidence = "",
                        parameters = action.parameters.filterKeys { it in CONTROL_MARKER_KEYS })
                    action.id in retainedIds -> action
                    else -> null
                }
            }
        } else {
            terminalActions.takeLast(AgentProjectHistoryRetentionPolicy.NON_PROJECT_RECENT_ACTION_LIMIT)
        }
    }

    private fun takeCached(
        actionHistory: List<AgentAction>,
        actions: List<AgentAction>,
        plannerProfile: String
    ): CachedHistory? {
        histories.removeAll { cached ->
            cached.actionHistory.get() == null || cached.actions.get() == null
        }
        val index = histories.indexOfFirst { cached ->
            cached.actionHistory.get() === actionHistory &&
                cached.actions.get() === actions &&
                cached.plannerProfile == plannerProfile
        }
        if (index < 0) return null
        return histories.removeAt(index).also(histories::add)
    }

    private val TERMINAL_ACTION_STATUSES = setOf(
        AgentActionStatus.COMPLETED,
        AgentActionStatus.FAILED,
        AgentActionStatus.BLOCKED,
        AgentActionStatus.ROLLED_BACK
    )

    private const val MAX_CACHED_HISTORIES = 8
    private val CONTROL_MARKER_KEYS = setOf("connector_task_mode", "supervised_iteration",
        AgentUnverifiedOutcomeRecovery.ORIGIN_ACTION, AgentUnverifiedOutcomeRecovery.PHONE_CONTROL,
        INTERNAL_CONVERSATION_ID, INTERNAL_TURN_ID, PLAN_REVISION_PARAMETER)
}
