package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentTranscriptProjectionInstrumentedTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private val screen = ScreenContext("projection-test", pageTitle = "Projection")

    @Test fun applicationContextPersistsFinalAndImageMetadataIdempotently() = withConversation { store, id, turn ->
        assertFalse(context is Activity)
        val image = AgentRichBlock("image-1", AgentRichBlockType.IMAGE,
            title = "Image", uri = "https://example.invalid/fixture.png", mimeType = "image/png")
        val rich = AgentRichContentCodec.encode(listOf(image))
        val state = state(AgentPhase.COMPLETED, "Verified result", metadata = mapOf(
            "awaiting_response" to "false", "rich_output" to rich, "source_message_id" to "901"))
        repeat(2) { context.persistAgentTranscript(state, id, turn, store) }
        val answer = store.list(id).filter { it.role == AgentTranscriptRole.ASSISTANT }.single()
        assertEquals("Verified result", answer.text)
        assertEquals(turn, answer.turnId)
        assertEquals(state.sessionId, answer.taskId)
        assertEquals(AgentFinalResponseIdentity.dedupeKey(turn), answer.dedupeKey)
        val persisted = AgentRichContentCodec.decode(answer.richOutputJson)
        assertEquals(1, persisted.size)
        assertEquals(image.uri, persisted.single().uri)
    }

    @Test fun tenIndependentStoresKeepSelectionAndReplyOwnership() {
        val rows = (0 until 10).map { index ->
            val store = AgentTranscriptStore(context, "projection-window-$index-${UUID.randomUUID()}")
            val conversation = store.createConversation(privateMode = true)
            val turn = "projection-turn-${UUID.randomUUID()}"
            store.append(AgentTranscriptRole.USER, "Question $index", conversationId = conversation.id, turnId = turn)
            Triple(store, conversation.id, turn)
        }
        val selected = rows.map { it.first.activeConversation().id }
        try {
            rows.asReversed().forEachIndexed { index, (store, id, turn) ->
                context.persistAgentTranscript(state(AgentPhase.COMPLETED, "Answer $id", "session-$index"),
                    id, turn, store)
            }
            rows.forEachIndexed { index, (store, id, turn) ->
                assertEquals(selected[index], store.activeConversation().id)
                val answer = store.list(id).single { it.role == AgentTranscriptRole.ASSISTANT }
                assertEquals("Answer $id", answer.text)
                assertEquals(turn, answer.turnId)
                assertEquals(id, answer.conversationId)
            }
        } finally { rows.forEach { (store, id, _) -> store.deleteConversation(id) } }
    }

    @Test fun waitingOutputDoesNotBecomeAFinalReplyAndAuditIsNotDuplicated() = withConversation { store, id, turn ->
        val waiting = state(AgentPhase.WAITING_RESPONSE, "Waiting for provider",
            metadata = mapOf("awaiting_response" to "true", "source_message_id" to "903"))
            .copy(auditTrail = listOf(AgentAuditEntry(AgentAuditEvent.TASK_PAUSED, "paused", 11L)))
        repeat(2) { context.persistAgentTranscript(waiting, id, turn, store) }
        assertFalse(store.list(id).any { it.role == AgentTranscriptRole.ASSISTANT })
        assertEquals(1, store.list(id).count { it.dedupeKey.startsWith("audit:") })
        assertEquals(1, store.list(id).count { it.dedupeKey == "connector-turn:$turn" })
    }

    @Test fun confirmationRemainsAnApprovalCardWithoutExecutingAnAction() = withConversation { store, id, turn ->
        val action = AgentAction("approval-action", AgentActionKind.DELETE_TEXT, "editor", AgentRisk.HIGH,
            AgentActionStatus.PENDING_CONFIRMATION, "Delete selected text")
        val waiting = state(AgentPhase.WAITING_CONFIRMATION, "").copy(pendingAction = action,
            plan = AgentPlan("Edit", screen, emptyList(), listOf(action), planId = "approval-plan"))
        repeat(2) { context.persistAgentTranscript(waiting, id, turn, store) }
        val entry = store.list(id).single { it.role == AgentTranscriptRole.ASSISTANT }
        assertEquals("approval:approval-plan:approval-action", entry.dedupeKey)
        val block = AgentRichContentCodec.decode(entry.richOutputJson).single()
        assertEquals(AgentRichBlockType.APPROVAL, block.type)
        assertTrue(block.actions.any { it.value == AgentPermissionChoice.ALLOW_ONCE.wireValue })
        assertTrue(block.actions.any { it.value == AgentPermissionChoice.DENY_ALWAYS.wireValue })
        assertEquals(AgentActionStatus.PENDING_CONFIRMATION, action.status)
        assertFalse(store.list(id).any { it.dedupeKey.startsWith("assistant-final:") })
    }

    private fun withConversation(test: (AgentTranscriptStore, String, String) -> Unit) {
        val store = AgentTranscriptStore(context, "projection-context-${UUID.randomUUID()}")
        val conversation = store.createConversation(privateMode = true)
        val turn = "projection-turn-${UUID.randomUUID()}"
        try {
            store.append(AgentTranscriptRole.USER, "Question", conversationId = conversation.id, turnId = turn)
            test(store, conversation.id, turn)
        } finally { store.deleteConversation(conversation.id) }
    }

    private fun state(phase: AgentPhase, text: String, session: String = "projection-session",
        metadata: Map<String, String> = emptyMap()): AgentUiState {
        val runtime = AgentRuntimeContext(session, "Goal", screen, PermissionMode.ASK_BEFORE_ACTION,
            true, false, emptyList(), callableTargets = emptyList(), memories = emptyList(),
            knowledgeItems = emptyList(), knowledgeStats = AgentKnowledgeStats())
        return AgentUiState(phase, "Goal", screen, permissionMode = PermissionMode.ASK_BEFORE_ACTION,
            highRiskGuard = true, callableTargets = emptyList(), runtimeContext = runtime, runningTaskCount = 0,
            steps = emptyList(), lastEvent = AgentEvent.GOAL_RECEIVED, sessionId = session,
            lastActionResult = AgentActionResult("action", true, text, metadata))
    }
}
