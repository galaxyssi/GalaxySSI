package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentPlanNodeJournalDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val key = AgentPlanNodeKey("session", "plan", "first", "checkpoint", "conversation", "turn", "spec")
    private val raw = AgentPlanNodeObservation(AgentActionResult("first", true, "node-private-output"), false)

    @Test fun returnedAndVerifiedObservationsSurviveReopen() = isolated { name ->
        val first = AgentRunEventStore(context, name)
        EncryptedAgentPlanNodeJournal(first).apply { start(key); record(key, raw) }
        first.close()
        val second = AgentRunEventStore(context, name)
        try {
            val journal = EncryptedAgentPlanNodeJournal(second)
            assertEquals(raw, journal.read(key))
            val observed = raw.copy(verified = true, evidence = "Observed output")
            journal.record(key, observed)
            assertEquals(observed, journal.read(key))
        } finally { second.close() }
    }

    @Test fun duplicateDispatchIsRejectedBeforeExecutorCanRun() = isolated { name ->
        val ledger = AgentRunEventStore(context, name)
        try {
            val journal = EncryptedAgentPlanNodeJournal(ledger)
            journal.start(key)
            assertThrows(IllegalStateException::class.java) { journal.start(key) }
            assertNull(journal.read(key))
        } finally { ledger.close() }
    }

    @Test fun staleReturnedCallbackCannotOverwriteVerifiedObservation() = isolated { name ->
        val ledger = AgentRunEventStore(context, name)
        try {
            val journal = EncryptedAgentPlanNodeJournal(ledger)
            journal.start(key)
            journal.record(key, raw)
            val verified = raw.copy(verified = true)
            journal.record(key, verified)
            assertThrows(IllegalStateException::class.java) { journal.record(key, raw) }
            journal.record(key, verified)
            assertEquals(verified, journal.read(key))
        } finally { ledger.close() }
    }

    @Test fun changedDuplicateOutcomeIsRejected() = isolated { name ->
        val ledger = AgentRunEventStore(context, name)
        try {
            val journal = EncryptedAgentPlanNodeJournal(ledger)
            journal.start(key)
            journal.record(key, raw)
            assertThrows(IllegalStateException::class.java) {
                journal.record(key, raw.copy(result = raw.result.copy(message = "different")))
            }
            assertEquals(raw, journal.read(key))
        } finally { ledger.close() }
    }

    @Test fun largeMultilingualResultHasNoOversizedPlaintextRow() = isolated { name ->
        val ledger = AgentRunEventStore(context, name)
        try {
            val journal = EncryptedAgentPlanNodeJournal(ledger)
            val large = raw.copy(result = raw.result.copy(message = ("\u7ed3\u679c\uD83D\uDE80" + "x".repeat(11)).repeat(180_000)))
            journal.start(key)
            journal.record(key, large)
            assertEquals(large, journal.read(key))
            context.openOrCreateDatabase(name, 0, null).use { db ->
                db.rawQuery("SELECT MAX(length(encrypted_event)),count(*) FROM run_events", null).use {
                    assertTrue(it.moveToFirst())
                    assertTrue(it.getInt(0) < 512 * 1024)
                    assertTrue(it.getInt(1) > 2)
                }
            }
        } finally { ledger.close() }
    }

    @Test fun failedCommitDoesNotExposePartialResult() = isolated { name ->
        val ledger = AgentRunEventStore(context, name)
        try {
            val journal = EncryptedAgentPlanNodeJournal(ledger)
            journal.start(key)
            context.openOrCreateDatabase(name, 0, null).use { db ->
                db.execSQL("CREATE TRIGGER reject_node_result BEFORE INSERT ON run_events " +
                    "WHEN NEW.sequence=3 BEGIN SELECT RAISE(ABORT, 'test disk failure'); END")
            }
            assertThrows(Exception::class.java) { journal.record(key, raw) }
            assertNull(journal.read(key))
            assertEquals(1, ledger.eventsPage(EncryptedAgentPlanNodeJournal.runId(key)).size)
        } finally { ledger.close() }
    }

    @Test fun completedParallelSiblingIsDurableBeforeBatchReturns() = isolated { name ->
        val ledger = AgentRunEventStore(context, name)
        val journal = EncryptedAgentPlanNodeJournal(ledger)
        val saved = CountDownLatch(1)
        val release = CountDownLatch(1)
        val worker = Executors.newSingleThreadExecutor()
        try {
            val future = worker.submit<List<AgentActionResult>> {
                runBlocking {
                    AgentNativeToolBatchExecutor.executeOrdered(listOf("first", "second"), limitProvider = { 2 }) { id ->
                        val node = key.copy(actionId = id)
                        journal.start(node)
                        if (id == "second") check(release.await(30, TimeUnit.SECONDS))
                        val result = raw.result.copy(actionId = id)
                        journal.record(node, AgentPlanNodeObservation(result, false))
                        if (id == "first") saved.countDown()
                        result
                    }
                }
            }
            assertTrue(saved.await(30, TimeUnit.SECONDS))
            assertFalse(future.isDone)
            assertEquals(raw, journal.read(key))
            assertNull(journal.read(key.copy(actionId = "second")))
            release.countDown()
            assertEquals(listOf("first", "second"), future.get(30, TimeUnit.SECONDS).map { it.actionId })
        } finally {
            release.countDown()
            worker.shutdownNow()
            assertTrue(worker.awaitTermination(30, TimeUnit.SECONDS))
            ledger.close()
        }
    }

    @Test fun mobileRuntimeRestoresMultipleNodesWithoutInvokingTheirExecutors() {
        val screen = ScreenContext(foregroundApp = "Test", pageTitle = "Test")
        val sessionId = "test-plan-runtime-${UUID.randomUUID()}"
        val actions = (1..3).map { index -> AgentAction("node-$index", AgentActionKind.CALL_NATIVE_TOOL,
            "test.read", AgentRisk.LOW, AgentActionStatus.RUNNING, "Read test result",
            mapOf("tool_id" to "test.read", "input_json" to "{}",
                INTERNAL_CONVERSATION_ID to sessionId, INTERNAL_TURN_ID to "turn"), requiresConfirmation = false) }
        var plan = AgentPlan("\u8bfb\u53d6\u4e09\u9879\u6d4b\u8bd5\u7ed3\u679c", screen, emptyList(), actions,
            planId = sessionId, confirmationRequired = false)
        actions.forEach { plan = plan.addCheckpoint(AgentExecutionContinuity.checkpointBefore(it, screen, 1)) }
        val session = InMemoryAgentSessionStore()
        val original = runtime(session, screen)
        original.sessionId = sessionId
        original.currentPlan = plan
        original.currentGoal = plan.goal
        original.phase = AgentPhase.EXECUTING
        val keys = actions.map { requireNotNull(AgentPlanNodeKey.from(sessionId, plan, it)) }
        try {
            original.persistSession()
            keys.take(2).forEach { node ->
                original.executeJournaledPlanAction(node) { AgentActionResult(node.actionId, true,
                    "Saved ${node.actionId}", mapOf("native_tool_status" to "succeeded", "invocation_id" to node.checkpointId)) }
            }
            // Simulate the session snapshot still preceding the two independent callbacks.
            session.save(requireNotNull(session.load()).copy(processInstanceId = "previous-process"))
            val restored = runtime(session, screen)
            assertEquals(AgentPhase.PAUSED, restored.phase)
            assertEquals(2, restored.currentPlan!!.actions.count { it.evidence == AGENT_NODE_OBSERVATION_PENDING })
            assertTrue(restored.resumePersistedPlanObservations())
            assertEquals(listOf(AgentActionStatus.COMPLETED, AgentActionStatus.COMPLETED, AgentActionStatus.FAILED),
                restored.currentPlan!!.actions.map { it.status })
            assertEquals(listOf("Saved node-1", "Saved node-2"), restored.currentPlan!!.actions.take(2).map { it.result })
            assertFalse(restored.resumePersistedPlanObservations())
        } finally {
            AgentRunEventStore(context).removeRuns(keys.map(EncryptedAgentPlanNodeJournal::runId).toSet())
        }
    }

    @Test fun recoveredRollingBatchRequestsModelAssessmentWithoutDiscardingResults() {
        val screen = ScreenContext(foregroundApp = "Test", pageTitle = "Test")
        var assessed = false
        val agent = runtime(InMemoryAgentSessionStore(), screen, onPlan = { request ->
            assessed = true
            assertTrue(request.replanReason.startsWith(AgentRollingPlanPolicy.REPLAN_REASON_PREFIX))
            assertEquals(AgentActionStatus.COMPLETED, request.executionHistory.last().status)
            assertEquals("Actual retained output", request.executionHistory.last().result)
            AgentPlan(request.goal, request.screen, emptyList(), emptyList(), plannerProfile = "unavailable")
        })
        agent.phase = AgentPhase.PAUSED
        agent.currentGoal = "\u7ee7\u7eed\u5b8c\u6210\u591a\u9636\u6bb5\u4efb\u52a1"
        agent.currentPlan = AgentPlan(agent.currentGoal, screen, emptyList(), listOf(AgentAction(
            "done", AgentActionKind.CALL_NATIVE_TOOL, "test.read", AgentRisk.LOW,
            AgentActionStatus.COMPLETED, "Read result", result = "Actual retained output")),
            plannerProfile = "guarded-model:test")
        agent.lastActionResult = AgentActionResult("done", true, "Actual retained output")
        val state = agent.assessRecoveredPlanNodes(requireNotNull(agent.currentPlan))
        assertTrue(assessed)
        assertEquals(AgentPhase.WAITING_RESPONSE, state.phase)
        assertEquals("Actual retained output", state.lastActionResult!!.message)
        assertEquals("true", state.lastActionResult!!.metadata["rolling_plan_assessment_pending"])
        assertEquals(AgentActionStatus.COMPLETED, agent.currentPlan!!.actions.single().status)
    }

    @Test fun ordinaryPlanExecutesRealMemoryAndStorageToolsAndCommitsTheirObservations() {
        val screen = ScreenContext(foregroundApp = "Test", pageTitle = "Test")
        val registry = AgentNativeToolRegistry().registerAll(AgentHardwareNativeTools.definitions(
            AgentAndroidHardwarePlatformFacade(context)))
        val agent = runtime(InMemoryAgentSessionStore(), screen, registry = registry)
        val id = "test-real-node-${UUID.randomUUID()}"
        agent.sessionId = id
        agent.currentGoal = "\u8bfb\u53d6\u624b\u673a\u7684\u5185\u5b58\u548c\u5b58\u50a8\u7a7a\u95f4"
        agent.currentPlan = AgentPlan(agent.currentGoal, screen, emptyList(),
            listOf(AgentHardwareNativeTools.MEMORY_STATUS, AgentHardwareNativeTools.STORAGE_STATUS).map { tool ->
                AgentAction(tool, AgentActionKind.CALL_NATIVE_TOOL, tool, AgentRisk.LOW,
                    AgentActionStatus.PROPOSED, "Read device information",
                    mapOf("tool_id" to tool, "input_json" to "{}", INTERNAL_CONVERSATION_ID to id,
                        INTERNAL_TURN_ID to "turn"), requiresConfirmation = false)
            }, planId = id, confirmationRequired = false)
        try {
            agent.executeFirstPendingAction()
            val plan = requireNotNull(agent.currentPlan)
            assertTrue(plan.actions.toString(), plan.actions.all { it.status == AgentActionStatus.COMPLETED })
            plan.actions.forEach { action ->
                val saved = requireNotNull(agent.planNodeJournal.read(requireNotNull(AgentPlanNodeKey.from(id, plan, action))))
                assertTrue(saved.verified)
                assertTrue(saved.result.success)
                val output = org.json.JSONObject(saved.result.metadata.getValue("native_tool_output"))
                assertTrue(output.getLong("total_bytes") > 0)
                assertTrue(output.getLong("available_bytes") >= 0)
            }
        } finally {
            val plan = agent.currentPlan
            if (plan != null) AgentRunEventStore(context).removeRuns(plan.actions.mapNotNull {
                AgentPlanNodeKey.from(id, plan, it)?.let(EncryptedAgentPlanNodeJournal::runId)
            }.toSet())
        }
    }

    private fun runtime(session: AgentSessionStore, screen: ScreenContext,
        registry: AgentNativeToolRegistry = AgentNativeToolRegistry(),
        onPlan: (AgentRequest) -> AgentPlan = { error("Recovery must not invent a model response") }
    ) = MobileNativeAgent(context,
        sessionStore = session, memoryStore = InMemoryAgentMemoryStore(), screenObservationOverride = false,
        perceptionProvider = object : ScreenPerceptionProvider {
            override fun capture() = screen
            override fun capture(foregroundApp: String, pageTitle: String) = screen
        },
        planner = object : AgentPlanner {
            override fun plan(request: AgentRequest): AgentPlan = onPlan(request)
        },
        actionExecutor = object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult = error("Must not reexecute")
        },
        nativeToolRegistryProvider = { registry },
        connectorRegistry = object : AgentConnectorRegistry { override fun availableTargets() = emptyList<AgentCallableTarget>() },
        taskStore = object : AgentTaskStore {
            private val records = linkedMapOf<String, AgentTaskRecord>()
            override fun upsert(record: AgentTaskRecord) { records[record.taskId] = record }
            override fun recent(limit: Int) = records.values.take(limit)
            override fun forSession(sessionId: String, limit: Int) = recent(limit).filter { it.sessionId == sessionId }
            override fun find(taskId: String) = records[taskId]
            override fun search(query: String, limit: Int) = emptyList<AgentTaskRecord>()
            override fun rebindSession(sourceSessionId: String, targetSessionId: String) = 0
            override fun delete(taskIds: Set<String>) { taskIds.forEach(records::remove) }
            override fun clear() { records.clear() }
        })

    @Test fun crashAfterFirstParallelResultBeforeSecondReturns() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("plan_node_crash") == "true")
        val ledger = AgentRunEventStore(context, CRASH_DB)
        val journal = EncryptedAgentPlanNodeJournal(ledger)
        check(ledger.latestEvent(EncryptedAgentPlanNodeJournal.runId(key)) == null) { "Inspect prior evidence before repeating setup" }
        val firstSaved = CountDownLatch(1)
        runBlocking {
            AgentNativeToolBatchExecutor.executeOrdered(listOf("first", "second"), limitProvider = { 2 }) { id ->
                val node = key.copy(actionId = id)
                journal.start(node)
                if (id == "second") {
                    check(firstSaved.await(30, TimeUnit.SECONDS))
                    android.os.Process.killProcess(android.os.Process.myPid())
                    error("Process must terminate")
                }
                journal.record(node, raw)
                firstSaved.countDown()
                raw.result
            }
        }
        fail("Test process did not terminate")
    }

    @Test fun recoverParallelResultsAfterActualProcessDeath() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("plan_node_crash") == "true")
        val ledger = AgentRunEventStore(context, CRASH_DB)
        try {
            val journal = EncryptedAgentPlanNodeJournal(ledger)
            assertEquals(raw, journal.read(key))
            assertNull(journal.read(key.copy(actionId = "second")))
            assertThrows(IllegalStateException::class.java) { journal.start(key.copy(actionId = "second")) }
            journal.record(key, raw.copy(verified = true, evidence = "Observed saved output after restart"))
            assertTrue(journal.read(key)!!.verified)
        } finally { ledger.close() }
        context.deleteDatabase(CRASH_DB)
    }

    private fun isolated(block: (String) -> Unit) {
        val name = "test-plan-nodes-${UUID.randomUUID()}.db"
        try { block(name) } finally { context.deleteDatabase(name) }
    }
    private companion object { const val CRASH_DB = "test-plan-node-crash.db" }
}
