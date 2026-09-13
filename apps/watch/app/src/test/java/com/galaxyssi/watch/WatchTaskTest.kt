package com.galaxyssi.watch

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WatchTaskTest {
    private val task = WatchTask.create("desktop_test", "route", "agent", "Summarize my work")
    private fun event(status: String, seq: Long = 1): JSONObject = JSONObject()
        .put("type", "agent_task_event").put("task_id", task.id)
        .put("conversation_id", task.conversationId).put("turn_id", task.turnId)
        .put("client_route_id", task.routeId).put("task_status", status).put("status_seq", seq)

    @Test fun stableIdentitySurvivesPersistenceAndRetry() {
        val recovered = WatchTask.fromJson(JSONObject(task.json().toString()))
        assertEquals(task, recovered)
        assertEquals(task.request("en").toString(), recovered.request("en").toString())
    }
    @Test fun rejectsWrongEndpointConversationTurnAndRoute() {
        assertEquals(task, task.reduce("other", event("completed")))
        for (key in listOf("conversation_id", "turn_id", "client_route_id", "task_id")) {
            assertEquals(task, task.reduce(task.desktopId, event("completed").put(key, "other")))
        }
    }
    @Test fun terminalOutcomeCannotRegressOnLateProgress() {
        val complete = task.reduce(task.desktopId, event("completed", 5))
        assertEquals(TaskState.COMPLETED, complete.state)
        assertEquals(complete, complete.reduce(task.desktopId, event("running", 6)))
    }
    @Test fun staleProgressCannotOverwriteNewerState() {
        val running = task.reduce(task.desktopId, event("running", 9))
        assertEquals(running, running.reduce(task.desktopId, event("failed", 8)))
    }
    @Test fun stopRequestRequiresRemoteAcknowledgement() {
        val requested = task.copy(state = TaskState.STOP_REQUESTED)
        assertFalse(requested.state.terminal)
        assertEquals(TaskState.STOP_REQUESTED, requested.reduce(task.desktopId, event("running")).state)
        assertEquals(TaskState.CANCELLED, requested.reduce(task.desktopId, event("cancelled")).state)
    }
    @Test fun finalTextCanArriveAfterCompletionEvent() {
        val completed = task.reduce(task.desktopId, event("completed"))
        val response = event("completed").put("type", "text").put("content", "Summary")
        assertEquals("Summary", completed.reduce(task.desktopId, response).reply)
    }
    @Test fun newTurnUsesSameConversationAndDistinctTaskIdentity() {
        val next = WatchTask.create(task.desktopId, task.routeId, task.agentId, "Continue", task.conversationId)
        assertEquals(task.conversationId, next.conversationId)
        assertNotEquals(task.id, next.id)
        assertNotEquals(task.messageId, next.messageId)
        assertNotEquals(task.turnId, next.turnId)
    }
    @Test fun preservesApprovalState() {
        assertEquals(TaskState.WAITING_APPROVAL, task.reduce(task.desktopId, event("waiting_approval")).state)
    }
}
