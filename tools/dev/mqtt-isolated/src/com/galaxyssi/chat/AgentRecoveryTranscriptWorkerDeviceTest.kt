package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.work.ListenableWorker
import androidx.work.testing.TestListenableWorkerBuilder
import androidx.work.workDataOf
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentRecoveryTranscriptWorkerDeviceTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private val workspaces get() = EncryptedAgentWorkspaceStore(context)

    @Test fun tenRealWorkersCommitSavedResultsWithoutAnActivityOrModel() = runBlocking {
        check(context.packageName == "com.galaxyssi.chat.mqttverification")
        val fixtures = (1..10).map { fixture() }
        try {
            val results = fixtures.map { fixture -> async(Dispatchers.Default) { runWorker(fixture) } }.awaitAll()
            assertTrue(results.all { it == ListenableWorker.Result.success() })
            fixtures.forEach { fixture ->
                assertEquals(AgentWorkspaceStatus.COMPLETED, workspaces.find(fixture.workspace.workspaceId)!!.status)
                val reply = fixture.store.list(fixture.workspace.conversationId)
                    .single { it.role == AgentTranscriptRole.ASSISTANT }
                assertEquals(fixture.session.lastActionResult!!.message, reply.text)
                assertEquals(fixture.workspace.taskId, reply.turnId)
                assertEquals(fixture.session.sessionId, reply.taskId)
                assertEquals(fixture.session, fixture.sessions.load())
                assertEquals(ListenableWorker.Result.success(), runWorker(fixture))
                assertEquals(1, fixture.store.list(fixture.workspace.conversationId)
                    .count { it.role == AgentTranscriptRole.ASSISTANT })
            }
        } finally { fixtures.forEach(::clean) }
    }

    @Test fun pendingApprovalIsProjectedAndNotExecuted() = runBlocking {
        val fixture = fixture(AgentPhase.WAITING_CONFIRMATION)
        try {
            val pending = fixture.workspace.copy(checkpoints = listOf(AgentWorkspaceCheckpoint(
                AgentRecoveryTranscript.CHECKPOINT_ID,
                stateJson = AgentRecoveryTranscript.pendingCheckpoint(fixture.workspace, fixture.session))))
            workspaces.upsert(pending, expectedRevision = workspaces.find(pending.workspaceId)!!.revision)
            assertEquals(ListenableWorker.Result.success(), runWorker(fixture))
            assertEquals(AgentWorkspaceStatus.WAITING_CONFIRMATION, workspaces.find(pending.workspaceId)!!.status)
            assertEquals(fixture.session, fixture.sessions.load())
            val cards = fixture.store.list(pending.conversationId).flatMap {
                AgentRichContentCodec.decode(it.richOutputJson)
            }
            assertEquals(1, cards.count { it.type == AgentRichBlockType.APPROVAL })
            assertTrue(workspaces.find(pending.workspaceId)!!.toolCalls.none {
                it.status == AgentToolCallStatus.SUCCEEDED
            })
        } finally { clean(fixture) }
    }

    @Test fun previouslyWrittenReplyIsReusedWhenWorkspaceCompletionWasInterrupted() = runBlocking {
        val fixture = fixture()
        try {
            AgentRecoveryTranscript.project(context, fixture.workspace,
                AgentRecoveryTranscript.state(fixture.session), fixture.store)
            val before = fixture.store.list(fixture.workspace.conversationId)
                .single { it.role == AgentTranscriptRole.ASSISTANT }
            assertEquals(ListenableWorker.Result.success(), runWorker(fixture))
            val after = fixture.store.list(fixture.workspace.conversationId)
                .single { it.role == AgentTranscriptRole.ASSISTANT }
            assertEquals(before.id, after.id)
            assertEquals(before.text, after.text)
            assertEquals(AgentWorkspaceStatus.COMPLETED, workspaces.find(fixture.workspace.workspaceId)!!.status)
        } finally { clean(fixture) }
    }

    @Test fun missingUserTurnLeavesResultRecoverableInsteadOfFinishingOrInventingAConversation() = runBlocking {
        val fixture = fixture(writeUser = false)
        try {
            assertEquals(ListenableWorker.Result.retry(), runWorker(fixture))
            val pending = workspaces.find(fixture.workspace.workspaceId)!!
            assertEquals(AgentWorkspaceStatus.PAUSED, pending.status)
            assertTrue(AgentRecoveryTranscript.needsProjection(pending, fixture.sessions.load()!!))
            assertFalse(fixture.store.list(pending.conversationId).any { it.role == AgentTranscriptRole.ASSISTANT })
            // Repair only the missing transcript evidence, then resume the same persisted result.
            fixture.store.append(AgentTranscriptRole.USER, "Question", conversationId = pending.conversationId,
                turnId = pending.taskId)
            assertEquals(ListenableWorker.Result.success(), runWorker(fixture))
            assertEquals(1, fixture.store.list(pending.conversationId).count { it.role == AgentTranscriptRole.ASSISTANT })
            assertEquals(fixture.session, fixture.sessions.load())
        } finally { clean(fixture) }
    }

    private suspend fun runWorker(fixture: Fixture): ListenableWorker.Result =
        TestListenableWorkerBuilder<AgentLongTaskRecoveryWorker>(context)
            .setInputData(workDataOf(AgentLongTaskRecoveryScheduler.KEY_WORKSPACE_ID to fixture.workspace.workspaceId))
            .build().doWork()

    private fun fixture(phase: AgentPhase = AgentPhase.COMPLETED, writeUser: Boolean = true): Fixture {
        val id = "recovery-projection-${UUID.randomUUID()}"
        val store = AgentTranscriptStore(context, id)
        val conversation = store.createConversation(privateMode = true)
        val workspace = AgentWorkspace(id, id, conversation.id, id, status = AgentWorkspaceStatus.PAUSED)
        val screen = ScreenContext("test", pageTitle = "Recovery")
        val action = AgentAction("approval-$id", AgentActionKind.DELETE_TEXT, "test", AgentRisk.HIGH,
            AgentActionStatus.PENDING_CONFIRMATION, "Delete text")
        val session = AgentSessionSnapshot("runtime-$id", phase, "Question", screen,
            if (phase == AgentPhase.WAITING_CONFIRMATION) AgentPlan("Question", screen, emptyList(), listOf(action)) else null,
            emptyList(), AgentActionResult("result", true, if (phase == AgentPhase.COMPLETED) "Answer $id" else ""),
            executionLoopSnapshot = AgentExecutionLoop.create().start(id, AgentExecutionLoopBudget()).snapshot,
            processInstanceId = "previous-process", updatedAtMillis = 100L)
        val sessions = SharedPreferencesAgentSessionStore(context, "task:$id")
        store.append(AgentTranscriptRole.USER, "Question", conversationId = conversation.id,
            turnId = if (writeUser) id else "other-$id")
        sessions.save(session)
        workspaces.upsert(workspace)
        return Fixture(workspace, sessions.load()!!, store, sessions)
    }

    private fun clean(fixture: Fixture) {
        fixture.sessions.clear()
        workspaces.delete(fixture.workspace.workspaceId)
        fixture.store.deleteConversation(fixture.workspace.conversationId)
    }

    private data class Fixture(val workspace: AgentWorkspace, val session: AgentSessionSnapshot,
        val store: AgentTranscriptStore, val sessions: SharedPreferencesAgentSessionStore)
}
