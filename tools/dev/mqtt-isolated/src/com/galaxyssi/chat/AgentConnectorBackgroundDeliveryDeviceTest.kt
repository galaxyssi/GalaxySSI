package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.work.ListenableWorker
import androidx.work.testing.TestListenableWorkerBuilder
import androidx.work.workDataOf
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject

@RunWith(AndroidJUnit4::class)
class AgentConnectorBackgroundDeliveryDeviceTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()

    @Test fun tenConnectorResponsesFinishWithoutAnyActivityAndOnlyOnce() = runBlocking {
        val fixtures = (1..10).map { fixture() }
        try {
            val results = fixtures.map { f -> async(Dispatchers.Default) { f.consumer().consume(f.response) } }.awaitAll()
            assertTrue(results.all { it })
            fixtures.forEach { f ->
                assertEquals(AgentWorkspaceStatus.COMPLETED, f.workspace()!!.status)
                val reply = f.store.list(f.conversation).single { it.role == AgentTranscriptRole.ASSISTANT }
                assertEquals(f.response.content, reply.text)
                assertEquals(f.id, reply.turnId)
                assertFalse(AgentConnectorResponseStore.contains(context, f.response))
                assertNull(AgentPendingDeliveryStore.find(context, f.source))
                assertTrue(f.consumer().consume(f.response))
                assertEquals(1, f.store.list(f.conversation).count { it.role == AgentTranscriptRole.ASSISTANT })
                assertEquals(0, f.calls.get())
            }
        } finally { fixtures.forEach { it.close() } }
    }

    @Test fun crossConversationResponseCannotConsumeAnotherPendingTurn() = runBlocking {
        val f = fixture()
        try {
            val wrong = f.response.copy(conversationId = "other-conversation")
            AgentConnectorResponseStore.append(context, wrong)
            assertFalse(f.consumer().consume(wrong))
            assertTrue(AgentConnectorResponseStore.contains(context, wrong))
            assertEquals(AgentPhase.WAITING_RESPONSE, f.sessions.load()!!.phase)
            assertFalse(f.store.list(f.conversation).any { it.role == AgentTranscriptRole.ASSISTANT })
            AgentConnectorResponseStore.remove(context, wrong)
            assertTrue(f.consumer().consume(f.response))
        } finally { f.close() }
    }

    @Test fun missingUserRecordKeepsReplyDurableAndRetriesProjectionWithoutExecutingAgain() = runBlocking {
        val f = fixture(writeUser = false)
        try {
            assertFalse(f.consumer().consume(f.response))
            assertTrue(AgentConnectorResponseStore.contains(context, f.response))
            assertEquals(AgentPhase.COMPLETED, f.sessions.load()!!.phase)
            f.store.append(AgentTranscriptRole.USER, "Question", conversationId = f.conversation, turnId = f.id)
            assertTrue(f.consumer().consume(f.response))
            assertEquals(1, f.store.list(f.conversation).count { it.role == AgentTranscriptRole.ASSISTANT })
            assertEquals(0, f.calls.get())
        } finally { f.close() }
    }

    @Test fun activeWorkspaceClaimDefersWithoutConsuming() = runBlocking {
        val f = fixture()
        try {
            AgentLongTaskRecoveryClaims.tryAcquire(f.id)!!.use {
                assertFalse(f.consumer().consume(f.response))
                assertTrue(AgentConnectorResponseStore.contains(context, f.response))
                assertEquals(AgentPhase.WAITING_RESPONSE, f.sessions.load()!!.phase)
            }
            assertTrue(f.consumer().consume(f.response))
        } finally { f.close() }
    }

    @Test fun workerRetriesWhenPageClaimsButDoesNotCommitThenCanFinishAfterPageDisappears() = runBlocking {
        val f = fixture()
        val listener = AgentConnectorResponseListener { true }
        AgentConnectorResponseBus.addListener(listener)
        try {
            assertEquals(ListenableWorker.Result.retry(), f.worker())
            assertTrue(AgentConnectorResponseStore.contains(context, f.response))
            AgentConnectorResponseBus.removeListener(listener)
            assertTrue(f.consumer().consume(f.response))
            assertEquals(ListenableWorker.Result.success(), f.worker())
        } finally {
            AgentConnectorResponseBus.removeListener(listener)
            f.close()
        }
    }

    @Test fun opaqueInboxLookupDoesNotReturnHandledOrSupersededReplies() {
        val f = fixture()
        try {
            val key = AgentConnectorResponseCodec.identity(f.response)
            assertEquals(f.response, AgentConnectorResponseStore.findPending(context, key))
            val newer = f.response.copy(executionGeneration = 2)
            AgentConnectorResponseStore.append(context, newer)
            assertNull(AgentConnectorResponseStore.findPending(context, key))
            AgentConnectorResponseStore.remove(context, newer)
            assertNull(AgentConnectorResponseStore.findPending(context, AgentConnectorResponseCodec.identity(newer)))
        } finally { f.close() }
    }

    @Test fun acceptedApprovalProjectionDoesNotRestoreExecutableRuntimeOrGrantConsent() = runBlocking {
        val f = fixture()
        try {
            val original = f.sessions.load()!!
            val action = AgentAction("approval", AgentActionKind.DELETE_TEXT, "test", AgentRisk.HIGH,
                AgentActionStatus.PENDING_CONFIRMATION, "Delete text", requiresConfirmation = true)
            val pending = original.copy(phase = AgentPhase.WAITING_CONFIRMATION,
                currentPlan = original.currentPlan!!.copy(actions = listOf(action)),
                lastActionResult = AgentActionResult("approval", true, "Confirm before continuing"))
            f.sessions.save(pending)
            val saved = f.sessions.load()!!
            val key = AgentConnectorResponseCodec.identity(f.response)
            val workspace = f.workspace()!!
            EncryptedAgentWorkspaceStore(context).upsert(workspace.copy(checkpoints = listOf(
                AgentWorkspaceCheckpoint("connector-accepted-$key", stateJson = JSONObject()
                    .put("response_identity", key).put("accepted", true).put("session_id", saved.sessionId)
                    .put("updated_at", saved.updatedAtMillis).put("phase", saved.phase.name)
                    .put("loop_revision", saved.executionLoopSnapshot!!.revision).toString()))),
                expectedRevision = workspace.revision)
            val consumer = AgentConnectorBackgroundDelivery(context) { error("Projection restored executable runtime") }
            assertTrue(consumer.consume(f.response))
            assertEquals(AgentWorkspaceStatus.WAITING_CONFIRMATION, f.workspace()!!.status)
            assertEquals(saved, f.sessions.load())
            assertTrue(f.store.list(f.conversation).flatMap { AgentRichContentCodec.decode(it.richOutputJson) }
                .any { it.type == AgentRichBlockType.APPROVAL })
        } finally { f.close() }
    }

    private fun fixture(writeUser: Boolean = true): Fixture {
        check(context.packageName == "com.galaxyssi.chat.mqttverification")
        return Fixture(writeUser)
    }

    private inner class Fixture(writeUser: Boolean) {
        val id = "background-inbox-${UUID.randomUUID()}"
        val store = AgentTranscriptStore(context, id)
        val conversation = store.createConversation(privateMode = true).id
        val source = sources.incrementAndGet()
        val sessions = SharedPreferencesAgentSessionStore(context, "task:$id")
        val calls = AtomicInteger()
        private val screen = ScreenContext("test", pageTitle = "Background")
        val response = AgentConnectorResponse(source, "test-contact", "Answer $id", conversation, id, "remote-$id")

        init {
            store.append(AgentTranscriptRole.USER, "Question", conversationId = conversation,
                turnId = if (writeUser) id else "other-$id")
            val runtime = runtime(sessions)
            val action = AgentAction("connector-$id", AgentActionKind.CALL_CONNECTOR, "Test",
                AgentRisk.LOW, AgentActionStatus.WAITING_RESPONSE, "Question",
                mapOf("connector_id" to "test-contact"), requiresConfirmation = false)
            runtime.activeConversationContext = AgentConversationContext(conversation, "Test", emptyList(), true)
            runtime.activeConversationTurnId = id
            runtime.currentGoal = "Question"
            runtime.currentPlan = AgentPlan("Question", screen, emptyList(), listOf(action), confirmationRequired = false)
            runtime.phase = AgentPhase.WAITING_RESPONSE
            runtime.lastActionResult = AgentActionResult(action.id, true, "Waiting", mapOf(
                "source_message_id" to source.toString(), "contact_id" to response.contactId,
                "conversation_id" to conversation, "turn_id" to id, "remote_task_id" to response.taskId,
                "awaiting_response" to "true"))
            assertTrue(runtime.startExecutionLoop(id))
            assertTrue(runtime.advanceExecutionLoop(AgentExecutionLoopPhase.ACT, "Dispatch", action.id))
            assertTrue(runtime.advanceExecutionLoop(AgentExecutionLoopPhase.WAITING_RESPONSE, "Wait", action.id))
            runtime.persistSession()
            EncryptedAgentWorkspaceStore(context).upsert(AgentWorkspace(id, id, conversation, id,
                status = AgentWorkspaceStatus.WAITING_RESPONSE))
            AgentPendingDeliveryStore.put(context, AgentPendingDelivery(source, conversation, id, response.taskId, response.contactId))
            AgentConnectorResponseStore.append(context, response)
        }

        fun runtime(sessions: AgentSessionStore) = MobileNativeAgent(context, sessionStore = sessions,
            perceptionProvider = object : ScreenPerceptionProvider {
                override fun capture() = screen
                override fun capture(foregroundApp: String, pageTitle: String) = screen
            }, planner = object : AgentPlanner {
                override fun plan(request: AgentRequest): AgentPlan = error("Unexpected model request")
            }, actionExecutor = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                    calls.incrementAndGet()
                    error("Unexpected side effect")
                }
            }, memoryStore = InMemoryAgentMemoryStore(),
            connectorRegistry = object : AgentConnectorRegistry { override fun availableTargets() = emptyList<AgentCallableTarget>() },
            screenObservationOverride = false).apply { runtimeTiming = com.galaxyssi.chat.metrics.AgentRuntimeTiming.NONE }

        fun consumer() = AgentConnectorBackgroundDelivery(context, ::runtime)
        fun workspace() = EncryptedAgentWorkspaceStore(context).find(id)
        suspend fun worker() = TestListenableWorkerBuilder<AgentConnectorBackgroundWorker>(context)
            .setInputData(workDataOf(AgentConnectorBackgroundRecovery.KEY_RESPONSE to AgentConnectorResponseCodec.identity(response)))
            .build().doWork()
        fun close() {
            AgentConnectorResponseStore.remove(context, response)
            AgentPendingDeliveryStore.remove(context, source)
            sessions.clear()
            EncryptedAgentWorkspaceStore(context).delete(id)
            store.deleteConversation(conversation)
        }
    }

    private companion object { val sources = AtomicLong(System.currentTimeMillis()) }
}
