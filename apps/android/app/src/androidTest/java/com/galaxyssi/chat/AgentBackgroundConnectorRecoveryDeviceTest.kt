package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import android.view.KeyEvent
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real Android persistence and Agent loop; provider timeouts are injected, not live outages. */
@RunWith(AndroidJUnit4::class)
class AgentBackgroundConnectorRecoveryDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun tenBackgroundConversationsRestoreAndFallbackIndependently() {
        val fixtures = (1..10).map(::Fixture)
        val pool = Executors.newFixedThreadPool(10)
        try {
            val gate = CountDownLatch(1)
            val initial = fixtures.map { fixture -> pool.submit<AgentUiState> { gate.await(); fixture.start() } }
            gate.countDown()
            initial.forEach { assertEquals(AgentPhase.WAITING_RESPONSE, it.get(120, TimeUnit.SECONDS).phase) }
            assertEquals(10, fixtures.map { it.pending().metadata["source_message_id"] }.toSet().size)
            InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_HOME)
            fixtures.forEach { it.recreate() }
            // A valid source ID does not excuse a wrong conversation or turn.
            fixtures.forEach { target -> fixtures.filter { it !== target }.forEach { other ->
                assertNull(target.agent.acceptConnectorOutcome(other.timeout()))
            } }
            val completed = fixtures.map { fixture -> pool.submit<AgentUiState> {
                val timeout = fixture.timeout()
                val fallback = requireNotNull(fixture.agent.acceptConnectorOutcome(timeout))
                assertEquals(AgentPhase.WAITING_RESPONSE, fallback.phase)
                assertEquals("test-deepseek", fallback.lastActionResult?.metadata?.get("contact_id"))
                assertEquals(2, fixture.calls.get())
                assertNull(fixture.agent.acceptConnectorOutcome(timeout))
                fixture.recreate()
                val pending = fixture.pending()
                val answer = (1..10).joinToString("\n") { "$it. ${fixture.index + it} + $it = ?" }
                val result = requireNotNull(fixture.agent.acceptConnectorOutcome(fixture.response(pending, true, answer)))
                assertEquals(answer, result.lastActionResult?.message)
                result
            } }
            completed.forEach { assertEquals(AgentPhase.COMPLETED, it.get(180, TimeUnit.SECONDS).phase) }
            fixtures.forEach {
                assertEquals(AgentPhase.COMPLETED, it.session.load()?.phase)
                assertEquals(2, it.calls.get())
            }
        } finally {
            pool.shutdownNow()
            assertTrue(pool.awaitTermination(30, TimeUnit.SECONDS))
            fixtures.forEach(Fixture::close)
        }
    }

    @Test fun localRecoveryConflictRestoresReceiptAndStillFallsBack() = withFixture { fixture ->
        fixture.start()
        val timeout = fixture.timeout()
        val original = fixture.pending()
        fixture.agent.lastActionResult = AgentActionResult(original.actionId, false,
            "The same action ID was already used with different execution input",
            mapOf("error_code" to "idempotency_key_conflict"))
        fixture.agent.phase = AgentPhase.FAILED
        fixture.agent.currentPlan = fixture.agent.currentPlan!!.let { plan ->
            plan.copy(actions = plan.actions.map { action ->
                // Legacy recovery changed these parameters but had no separate attempt owner.
                action.copy(parameters = action.parameters + mapOf("handoff_recovery_attempt" to "1",
                    "superseded_source_message_id" to timeout.sourceMessageId.toString()))
            })
        }
        fixture.agent.currentPlan = fixture.agent.currentPlan!!.markAction(original.actionId,
            AgentActionStatus.FAILED, fixture.agent.lastActionResult)
        fixture.agent.failExecutionLoop("Local handoff conflict")
        fixture.agent.saveTaskRecord()
        fixture.recreate()
        assertFalse(fixture.agent.restoreConflictedConnectorReceipt(timeout.sourceMessageId, timeout.contactId,
            "other", timeout.turnId, timeout.taskId))
        assertTrue(fixture.agent.restoreConflictedConnectorReceipt(timeout.sourceMessageId, timeout.contactId,
            timeout.conversationId, timeout.turnId, timeout.taskId))
        assertEquals(1, fixture.calls.get())
        val fallback = requireNotNull(fixture.agent.acceptConnectorOutcome(timeout))
        assertEquals(AgentPhase.WAITING_RESPONSE, fallback.phase)
        assertEquals("test-deepseek", fallback.lastActionResult?.metadata?.get("contact_id"))
        assertEquals(2, fixture.calls.get())
    }

    @Test fun explicitTransportRecoveryUsesNewReceiptAndKeepsOriginalSource() = withFixture { fixture ->
        fixture.start()
        val source = fixture.pending().metadata.getValue("source_message_id").toLong()
        val recovered = requireNotNull(fixture.agent.recoverStrandedConnectorHandoff(source, "Injected rejected handoff"))
        assertEquals(AgentPhase.WAITING_RESPONSE, recovered.phase)
        assertEquals(source.toString(), recovered.lastActionResult?.metadata?.get("superseded_source_message_id"))
        assertEquals(2, fixture.calls.get())
        assertNotEquals(source.toString(), recovered.lastActionResult?.metadata?.get("source_message_id"))
    }

    @Test fun cancelledTaskIsNeverResurrectedByLateOutcome() = withFixture { fixture ->
        fixture.start()
        val timeout = fixture.timeout()
        fixture.agent.cancelCurrentTask()
        fixture.recreate()
        assertNull(fixture.agent.acceptConnectorOutcome(timeout))
        assertFalse(fixture.agent.restoreConflictedConnectorReceipt(timeout.sourceMessageId, timeout.contactId,
            timeout.conversationId, timeout.turnId, timeout.taskId))
        assertEquals(1, fixture.calls.get())
    }

    private fun withFixture(block: (Fixture) -> Unit) {
        val fixture = Fixture(11)
        try { block(fixture) } finally { fixture.close() }
    }

    private inner class Fixture(val index: Int) {
        val id = "background-test-${UUID.randomUUID()}"
        val conversation = "conversation-$id"
        val session = SharedPreferencesAgentSessionStore(context, "task:$id")
        val ledger = AgentRunEventStore(context, "$id.db")
        val calls = AtomicInteger()
        private val records = ConcurrentHashMap<String, AgentTaskRecord>()
        private val screen = ScreenContext("GalaxySSI", pageTitle = "Test")
        var agent = runtime()

        fun recreate() { agent = runtime() }
        fun pending() = requireNotNull(agent.snapshot().lastActionResult)
        fun timeout() = response(pending(), false, "Codex task stalled")
        fun response(pending: AgentActionResult, success: Boolean, content: String) = AgentConnectorResponse(
            pending.metadata.getValue("source_message_id").toLong(), pending.metadata.getValue("contact_id"), content,
            conversation, id, pending.metadata.getValue("remote_task_id"), success = success,
            taskStatus = if (success) "completed" else "timed_out", statusSequence = 3)

        fun start(): AgentUiState {
            agent.sessionId = id
            agent.currentGoal = "\u8bf7\u51fa10\u9053\u52a0\u51cf\u6cd5\u6570\u5b66\u9898 $index"
            agent.activeConversationContext = AgentConversationContext(conversation, "Test", emptyList(), false)
            agent.activeConversationTurnId = id
            val action = AgentAction("connector-codex", AgentActionKind.CALL_CONNECTOR, "Codex test", AgentRisk.LOW,
                AgentActionStatus.PROPOSED, "Test request", mapOf("connector_id" to "test-codex",
                    "connector_adapter_type" to "desktop-agent", "prompt" to agent.currentGoal,
                    "routing_fallback_ids" to "test-deepseek", "manual_target_locked" to "false",
                    INTERNAL_CONVERSATION_ID to conversation, INTERNAL_TURN_ID to id), false)
            val plan = AgentPlan(agent.currentGoal, screen, emptyList(), listOf(action), confirmationRequired = false)
            agent.currentPlan = plan
            assertTrue(agent.startExecutionLoop(id))
            return agent.executePlannedAction(plan, action, false, trustedHandoffReplay = true)
        }

        private fun runtime() = MobileNativeAgent(context,
            perceptionProvider = object : ScreenPerceptionProvider {
                override fun capture() = screen
                override fun capture(foregroundApp: String, pageTitle: String) = screen
            }, planner = object : AgentPlanner {
                override fun plan(request: AgentRequest): AgentPlan = error("Unexpected model replanning")
            }, actionExecutor = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                    val attempt = calls.incrementAndGet()
                    val source = index * 1000L + attempt
                    val contact = action.parameters.getValue("connector_id")
                    assertEquals(conversation, action.parameters[INTERNAL_CONVERSATION_ID])
                    assertEquals(id, action.parameters[INTERNAL_TURN_ID])
                    return AgentActionResult(action.id, true, "Waiting $index", AgentConnectorFallbackAction.resultMetadata(action) + mapOf(
                        "awaiting_response" to "true", "source_message_id" to source.toString(),
                        "contact_id" to contact, "resource_id" to contact, "conversation_id" to conversation,
                        "turn_id" to id, "remote_task_id" to "remote-$source", "resource_location" to "desktop",
                        "resource_started_at" to System.currentTimeMillis().toString(), "failure_domain" to "test-$contact"))
                }
            }, memoryStore = InMemoryAgentMemoryStore(), taskStore = object : AgentTaskStore {
                override fun upsert(record: AgentTaskRecord) { records[record.taskId] = record }
                override fun recent(limit: Int) = records.values.take(limit)
                override fun forSession(sessionId: String, limit: Int) = recent(limit).filter { it.sessionId == sessionId }
                override fun find(taskId: String) = records[taskId]
                override fun search(query: String, limit: Int) = emptyList<AgentTaskRecord>()
                override fun rebindSession(sourceSessionId: String, targetSessionId: String) = 0
                override fun delete(taskIds: Set<String>) { taskIds.forEach(records::remove) }
                override fun clear() = records.clear()
            }, connectorRegistry = object : AgentConnectorRegistry {
                override fun availableTargets() = listOf("test-codex", "test-deepseek").map { name ->
                    AgentCallableTarget(name, name, AgentConnectorKind.AGENT, AgentConnectorStatus.AVAILABLE,
                        listOf(AgentCapability.CHAT), "test-$name", adapterType = "desktop-agent")
                }
            }, sessionStore = session, actionEffectReplayStore = EncryptedAgentNativeToolReplayStore(ledger),
            screenObservationOverride = false).apply { runtimeTiming = com.galaxyssi.chat.metrics.AgentRuntimeTiming.NONE }

        fun close() { session.clear(); ledger.close(); context.deleteDatabase("$id.db") }
    }
}
