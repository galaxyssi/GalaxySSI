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
    @Test fun authenticatedLateResultReplacesLocalSilenceTimeout() {
        val timedOut = task.copy(state = TaskState.FAILED, localTimedOut = true)
        assertEquals(timedOut, timedOut.reduce(task.desktopId, event("running")))
        val reply = timedOut.reduce(task.desktopId,
            event("completed").put("type", "text").put("content", "Late answer"))
        assertEquals(TaskState.COMPLETED, reply.state)
        assertEquals("Late answer", reply.reply)
        assertFalse(reply.localTimedOut)
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
    @Test fun acceptsDesktopAllocatedIdentityOnlyWithExactClientCorrelation() {
        val wire = event("failed").put("task_id", "desktop-allocated")
            .put("source_message_id", task.sourceId.toString()).put("error", "Tool registration failed")
        val failed = task.reduce(task.desktopId, wire)
        assertEquals(TaskState.FAILED, failed.state)
        assertEquals("desktop-allocated", failed.remoteTaskId)
        assertEquals("Tool registration failed", failed.progress)
        assertEquals(failed, WatchTask.fromJson(failed.json()))
        for (field in listOf("source_message_id", "client_route_id", "conversation_id", "turn_id", "agent_id", "contact_id")) {
            assertEquals(task, task.reduce(task.desktopId, JSONObject(wire.toString()).put(field, "unrelated")))
        }
        assertEquals(failed, failed.reduce(task.desktopId, JSONObject(wire.toString()).put("task_id", "other-task")))
    }
    @Test fun generationFencesLateRepliesAndAllowsARealRemoteRetry() {
        val failed = task.reduce(task.desktopId, event("failed", 9))
        val retried = failed.reduce(task.desktopId, event("running", 1).put("execution_generation", 2))
        assertEquals(TaskState.RUNNING, retried.state)
        assertEquals(2L, retried.executionGeneration)
        assertEquals(retried, retried.reduce(task.desktopId,
            event("completed", 99).put("type", "text").put("content", "old execution")))
    }
}
