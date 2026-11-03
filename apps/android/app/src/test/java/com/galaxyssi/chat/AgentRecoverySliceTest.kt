package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class AgentRecoverySliceTest {
    private fun workspace() = AgentWorkspace("public-recovery-run", "public-owner", "public-conversation", "public-turn",
        status = AgentWorkspaceStatus.PAUSED)

    @Test fun `early recovery failure preserves a resumable run and its checkpoint`() = runBlocking {
        val store = InMemoryAgentWorkspaceStore()
        val original = workspace()
        store.upsert(original, expectedRevision = 0L)
        val supervisor = AgentTaskSupervisor(store)
        try {
            val failed = AgentRecoverySlice()
            supervisor.resume(original.workspaceId, hook = AgentTaskResumeHook { context, _ ->
                context.checkpoint("original-model", stateJson = "saved-observation")
                failed.prepareAndCommit(context) { throw AgentModelLoopRecoveryException("fixture_ledger_unavailable") }
            }).join()
            assertFalse(failed.committed)
            assertEquals("fixture_ledger_unavailable", failed.failure!!.message)
            val paused = supervisor.findWorkspace(original.workspaceId)!!
            assertEquals(AgentWorkspaceStatus.PAUSED, paused.status)
            assertEquals("saved-observation", paused.checkpoints.single { it.id == "original-model" }.stateJson)
            assertFalse(paused.eventJournal.any { it.kind == AgentTaskEventKinds.FAILED })
            assertTrue(paused.eventJournal.last().message.contains("fixture_ledger_unavailable"))
            val recovered = AgentRecoverySlice()
            supervisor.resume(original.workspaceId, hook = AgentTaskResumeHook { context, _ ->
                recovered.prepareAndCommit(context) {
                    assertEquals(original.taskId, context.workspace().taskId)
                    context.checkpoint("recovery-result", stateJson = "committed-observation")
                }
                context.waitForResponse("Continue from the original observation")
            }).join()
            assertTrue(recovered.committed)
            assertNull(recovered.failure)
            assertEquals(AgentWorkspaceStatus.WAITING_RESPONSE, supervisor.findWorkspace(original.workspaceId)!!.status)
        } finally { supervisor.shutdown() }
    }

    @Test fun `cancellation never becomes an acknowledged or failed recovery slice`() = runBlocking {
        val store = InMemoryAgentWorkspaceStore()
        val original = workspace()
        store.upsert(original, expectedRevision = 0L)
        val supervisor = AgentTaskSupervisor(store)
        try {
            val slice = AgentRecoverySlice()
            supervisor.resume(original.workspaceId, hook = AgentTaskResumeHook { context, _ ->
                slice.prepareAndCommit(context) { throw CancellationException("fixture cancellation") }
            }).join()
            assertFalse(slice.committed)
            assertNull(slice.failure)
            assertFalse(supervisor.findWorkspace(original.workspaceId)!!.eventJournal.any {
                it.kind == AgentTaskEventKinds.FAILED
            })
        } finally { supervisor.shutdown() }
    }
}
