package com.galaxyssi.watch

import org.junit.Assert.*
import org.junit.Test

class WatchConversationStatusTest {
    private val task = WatchTask.create("desktop", "route", "codex", "Question")
    private fun status(state: TaskState, reply: String = "", unread: Boolean = false) =
        WatchConversationStatus.resolve(task.copy(state = state, reply = reply), unread)

    @Test fun activeStatesRemainAnimatedEvenWithUnreadPartialText() {
        for (state in listOf(TaskState.QUEUED, TaskState.SENT, TaskState.ACCEPTED, TaskState.RUNNING)) {
            assertEquals(state.name, status(state, "Partial", true).name)
            assertTrue(status(state).animated)
        }
    }
    @Test fun completedWithoutReplyWaitsForDelivery() {
        assertEquals(WatchConversationStatus.DELIVERING, status(TaskState.COMPLETED, "  ", true))
        assertTrue(status(TaskState.COMPLETED).animated)
    }
    @Test fun unreadCompleteBecomesGreenCheckState() {
        assertEquals(WatchConversationStatus.COMPLETE_UNREAD, status(TaskState.COMPLETED, "Answer", true))
    }
    @Test fun openingCompleteReplyBecomesReadState() {
        assertEquals(WatchConversationStatus.READ, status(TaskState.COMPLETED, "Answer", false))
    }
    @Test fun failedReplyNeverBecomesSuccess() {
        assertEquals(WatchConversationStatus.FAILED, status(TaskState.FAILED, "Error", true))
    }
    @Test fun cancelledReplyNeverBecomesSuccess() {
        assertEquals(WatchConversationStatus.CANCELLED, status(TaskState.CANCELLED, "Stopped", true))
    }
    @Test fun approvalWaitDoesNotSpin() {
        assertEquals(WatchConversationStatus.WAITING_APPROVAL, status(TaskState.WAITING_APPROVAL, "Approve", true))
        assertFalse(status(TaskState.WAITING_APPROVAL).animated)
    }
    @Test fun stopRequestWaitsForConfirmationWithoutPretendingPaused() {
        assertEquals(WatchConversationStatus.STOP_REQUESTED, status(TaskState.STOP_REQUESTED))
        assertTrue(status(TaskState.STOP_REQUESTED).animated)
    }
    @Test fun latestTurnDoesNotDependOnStorageOrder() {
        val old = task.copy(id = "old", sourceId = 1, state = TaskState.COMPLETED, reply = "Old")
        val new = task.copy(id = "new", sourceId = 2, state = TaskState.RUNNING)
        assertEquals(new, WatchConversationStatus.latest(listOf(old, new)))
        assertEquals(new, WatchConversationStatus.latest(listOf(new, old)))
        assertEquals(WatchConversationStatus.RUNNING, WatchConversationStatus.resolve(new, true))
    }
    @Test fun terminalVisualsDoNotAnimate() {
        for (state in listOf(WatchConversationStatus.COMPLETE_UNREAD, WatchConversationStatus.READ,
            WatchConversationStatus.FAILED, WatchConversationStatus.CANCELLED)) assertFalse(state.animated)
    }
    @Test fun stateSurvivesTaskSerialization() {
        val completed = task.copy(state = TaskState.COMPLETED, reply = "Saved answer")
        val restored = WatchTask.fromJson(completed.json())
        assertEquals(WatchConversationStatus.COMPLETE_UNREAD, WatchConversationStatus.resolve(restored, true))
        assertEquals(WatchConversationStatus.READ, WatchConversationStatus.resolve(restored, false))
    }
}
