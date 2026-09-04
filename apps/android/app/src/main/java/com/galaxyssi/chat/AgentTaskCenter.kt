package com.galaxyssi.chat

enum class AgentTaskCenterAction {
    RETRY,
    COPY,
    VIEW_LOG,
    DELETE
}

object AgentTaskCenterPolicy {
    private val terminalPhases = setOf(
        AgentPhase.COMPLETED,
        AgentPhase.FAILED,
        AgentPhase.CANCELLED,
        AgentPhase.BLOCKED
    )

    fun actions(task: AgentTaskRecord): List<AgentTaskCenterAction> = buildList {
        if (task.phase in terminalPhases && isReusableGoal(task.goal)) {
            add(AgentTaskCenterAction.RETRY)
        }
        add(AgentTaskCenterAction.COPY)
        add(AgentTaskCenterAction.VIEW_LOG)
        if (task.phase in terminalPhases) {
            add(AgentTaskCenterAction.DELETE)
        }
    }

    fun isReusableGoal(goal: String): Boolean {
        val clean = goal.trim()
        return clean.isNotBlank() && clean != SENSITIVE_GOAL_PLACEHOLDER
    }

    private const val SENSITIVE_GOAL_PLACEHOLDER = "Sensitive goal withheld"
}

class AgentTaskCenter(private val store: AgentTaskStore) {
    fun find(taskId: String): AgentTaskRecord? = store.find(taskId.trim())

    fun deleteTask(taskId: String): Boolean {
        val cleanTaskId = taskId.trim()
        if (cleanTaskId.isBlank() || store.find(cleanTaskId) == null) return false
        store.deleteTask(cleanTaskId)
        return store.find(cleanTaskId) == null
    }
}
