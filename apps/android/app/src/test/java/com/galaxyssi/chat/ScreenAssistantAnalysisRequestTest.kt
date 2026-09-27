package com.galaxyssi.chat

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test

class ScreenAssistantAnalysisRequestTest {
    @Test fun cancellationIsIdempotent() {
        val request = ScreenAssistantAnalysisRequest()
        assertFalse(request.isCancelled)
        assertTrue(request.cancel())
        assertFalse(request.cancel())
        assertTrue(request.isCancelled)
    }

    @Test fun lateSubmissionCallbackRetainsCancellation() {
        val request = ScreenAssistantAnalysisRequest()
        val shouldCancel = { request.isCancelled }
        request.cancel()
        request.turnId = "late-screen-turn"
        assertTrue(shouldCancel())
        assertEquals("late-screen-turn", request.turnId)
    }

    @Test fun anotherScreenRequestIsNotCancelled() {
        val first = ScreenAssistantAnalysisRequest()
        val second = ScreenAssistantAnalysisRequest()
        first.cancel()
        assertTrue(first.isCancelled)
        assertFalse(second.isCancelled)
    }

    @Test fun followUpTurnsShareCancellationWithoutLosingOriginalIdentity() {
        val request = ScreenAssistantAnalysisRequest()
        request.turnId = "original-screen-turn"
        request.turnId = "follow-up-turn"
        request.turnId = "follow-up-turn"
        request.cancel()
        assertEquals(setOf("original-screen-turn", "follow-up-turn"), request.turnIds)
        assertTrue(request.isCancelled)
    }

    @Test fun closingPanelDoesNotCancelRequest() {
        val request = ScreenAssistantAnalysisRequest()
        request.turnId = "running-screen-turn"
        assertFalse(request.isCancelled)
        assertEquals("running-screen-turn", request.turnId)
    }

    @Test fun stoppingScreenWorkspaceDoesNotStopOtherConversation() = runBlocking {
        val store = InMemoryAgentWorkspaceStore()
        val supervisor = AgentTaskSupervisor(store, maxConcurrentReadReasoningTasks = 2)
        val screenStarted = CompletableDeferred<Unit>()
        val otherStarted = CompletableDeferred<Unit>()
        val otherFinished = CompletableDeferred<Unit>()
        try {
            val screen = AgentWorkspace("screen-turn", "screen-turn", "screen-conversation", "screen-turn")
            val other = AgentWorkspace("other-turn", "other-turn", "other-conversation", "other-turn")
            val screenHandle = supervisor.submit(screen) { screenStarted.complete(Unit); awaitCancellation() }
            val otherHandle = supervisor.submit(other) { otherStarted.complete(Unit); otherFinished.await() }
            withTimeout(5_000) { screenStarted.await(); otherStarted.await() }
            assertTrue(supervisor.cancelWorkspace(screen.workspaceId, "Stop screen analysis"))
            withTimeout(5_000) { screenHandle.join() }
            assertEquals(AgentWorkspaceStatus.CANCELLED, store.find(screen.workspaceId)?.status)
            assertTrue(store.find(screen.workspaceId)?.cancellationRequested == true)
            assertEquals(AgentWorkspaceStatus.RUNNING, store.find(other.workspaceId)?.status)
            otherFinished.complete(Unit)
            withTimeout(5_000) { otherHandle.join() }
            assertEquals(AgentWorkspaceStatus.COMPLETED, store.find(other.workspaceId)?.status)
        } finally { supervisor.close() }
    }
}
