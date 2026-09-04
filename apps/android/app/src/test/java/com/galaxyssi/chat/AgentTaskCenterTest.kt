package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTaskCenterTest {
    @Test
    fun terminalTaskOffersCompleteTaskCenterActions() {
        assertEquals(
            listOf(
                AgentTaskCenterAction.RETRY,
                AgentTaskCenterAction.COPY,
                AgentTaskCenterAction.VIEW_LOG,
                AgentTaskCenterAction.DELETE
            ),
            AgentTaskCenterPolicy.actions(task(phase = AgentPhase.COMPLETED))
        )
    }

    @Test
    fun activeTaskCannotBeDuplicatedOrDeletedFromHistory() {
        assertEquals(
            listOf(AgentTaskCenterAction.COPY, AgentTaskCenterAction.VIEW_LOG),
            AgentTaskCenterPolicy.actions(task(phase = AgentPhase.EXECUTING))
        )
    }

    @Test
    fun redactedGoalCannotBeRetried() {
        val actions = AgentTaskCenterPolicy.actions(
            task(phase = AgentPhase.FAILED, goal = "Sensitive goal withheld")
        )

        assertFalse(AgentTaskCenterAction.RETRY in actions)
        assertTrue(AgentTaskCenterAction.DELETE in actions)
    }

    @Test
    fun deleteRemovesOnlySelectedTask() {
        val first = task(taskId = "task-1", sessionId = "shared-session")
        val second = task(taskId = "task-2", sessionId = "shared-session")
        val store = InMemoryTaskStore(listOf(first, second))
        val center = AgentTaskCenter(store)

        assertTrue(center.deleteTask(first.taskId))
        assertNull(store.find(first.taskId))
        assertEquals(second, store.find(second.taskId))
        assertFalse(center.deleteTask(first.taskId))
    }

    private fun task(
        taskId: String = "task",
        sessionId: String = "conversation",
        goal: String = "Summarize the file",
        phase: AgentPhase = AgentPhase.COMPLETED
    ) = AgentTaskRecord(
        taskId = taskId,
        sessionId = sessionId,
        goal = goal,
        phase = phase,
        routeKind = AgentRouteKind.DESKTOP_AGENT,
        targetTitle = "Codex",
        risk = AgentRisk.LOW,
        blocked = false
    )

    private class InMemoryTaskStore(initial: List<AgentTaskRecord>) : AgentTaskStore {
        private val records = initial.associateByTo(linkedMapOf(), AgentTaskRecord::taskId)

        override fun upsert(record: AgentTaskRecord) {
            records[record.taskId] = record
        }

        override fun recent(limit: Int): List<AgentTaskRecord> =
            records.values.take(limit)

        override fun forSession(sessionId: String, limit: Int): List<AgentTaskRecord> =
            records.values.filter { it.sessionId == sessionId }.take(limit)

        override fun find(taskId: String): AgentTaskRecord? = records[taskId]

        override fun search(query: String, limit: Int): List<AgentTaskRecord> =
            records.values.filter { query in it.goal }.take(limit)

        override fun rebindSession(sourceSessionId: String, targetSessionId: String): Int = 0

        override fun delete(taskIds: Set<String>) {
            records.entries.removeAll { it.key in taskIds || it.value.sessionId in taskIds }
        }

        override fun deleteTask(taskId: String) {
            records.remove(taskId)
        }

        override fun clear() {
            records.clear()
        }
    }
}
