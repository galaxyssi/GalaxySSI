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

    @Test fun recoveredAssessmentHonorsNewPauseOrCancellationDuringPlanning() {
        val screen = ScreenContext(foregroundApp = "Test", pageTitle = "Test")
        listOf(AgentPhase.PAUSED, AgentPhase.CANCELLED).forEach { stopped ->
            lateinit var agent: MobileNativeAgent
            agent = runtime(InMemoryAgentSessionStore(), screen, onPlan = { request ->
                assertEquals(AgentPhase.PLANNING, agent.phase)
                agent.phase = stopped
                AgentPlan(request.goal, request.screen, emptyList(), emptyList(), plannerProfile = "unavailable")
            })
            agent.phase = AgentPhase.PAUSED
            agent.currentGoal = "Test interrupted assessment"
            val plan = AgentPlan(agent.currentGoal, screen, emptyList(), listOf(AgentAction(
                "done", AgentActionKind.CALL_NATIVE_TOOL, "test.read", AgentRisk.LOW,
                AgentActionStatus.COMPLETED, "Read result", result = "Retained")), plannerProfile = "guarded-model:test")
            agent.currentPlan = plan
            agent.lastActionResult = AgentActionResult("done", true, "Retained")
            val state = agent.assessRecoveredPlanNodes(plan)
            assertEquals(stopped, state.phase)
            assertEquals("Retained", state.lastActionResult!!.message)
            assertEquals(AgentActionStatus.COMPLETED, agent.currentPlan!!.actions.single().status)
        }
    }

    @Test fun cancelledRecoveryDoesNotCallThePlanner() {
        val screen = ScreenContext(foregroundApp = "Test", pageTitle = "Test")
        val agent = runtime(InMemoryAgentSessionStore(), screen)
        agent.phase = AgentPhase.CANCELLED
        val plan = AgentPlan("Cancelled recovery", screen, emptyList(), emptyList())
        assertEquals(AgentPhase.CANCELLED, agent.assessRecoveredPlanNodes(plan).phase)
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

    @Test fun parallelNativeDispatchDoesNotNeedCoordinatorMonitor() {
        val screen = ScreenContext(foregroundApp = "Test", pageTitle = "Test")
        val registry = AgentNativeToolRegistry().registerAll(AgentHardwareNativeTools.definitions(
            AgentAndroidHardwarePlatformFacade(context)))
        val agent = runtime(InMemoryAgentSessionStore(), screen, registry)
        val id = "test-parallel-monitor-${UUID.randomUUID()}"
        agent.sessionId = id
        val actions = listOf(AgentHardwareNativeTools.MEMORY_STATUS,
            AgentHardwareNativeTools.STORAGE_STATUS).map { tool ->
            AgentAction(tool, AgentActionKind.CALL_NATIVE_TOOL, tool, AgentRisk.LOW,
                AgentActionStatus.RUNNING, "Read device information",
                mapOf("tool_id" to tool, "input_json" to "{}", INTERNAL_CONVERSATION_ID to id,
                    INTERNAL_TURN_ID to "turn"), requiresConfirmation = false)
        }
        val pool = Executors.newFixedThreadPool(2)
        val startedAt = android.os.SystemClock.elapsedRealtime()
        try {
            synchronized(agent) {
                val futures = actions.map { action ->
                    pool.submit<AgentActionResult> { agent.executeAction(action, screen) }
                }
                futures.forEach { future ->
                    val result = future.get(10, TimeUnit.SECONDS)
                    assertTrue(result.message, result.success)
                    val output = org.json.JSONObject(result.metadata.getValue("native_tool_output"))
                    assertTrue(output.getLong("total_bytes") > 0)
                }
            }
            assertFalse(agent.cancelActiveNativeTool("Finished"))
            println("AGENT_PARALLEL_MONITOR tools=2 elapsed_ms=" +
                (android.os.SystemClock.elapsedRealtime() - startedAt))
        } finally {
            pool.shutdownNow()
            assertTrue("Test workers did not stop", pool.awaitTermination(10, TimeUnit.SECONDS))
        }
    }

    @Test fun dependencyLayersExecuteWithBoundedDispatchStack() {
        val screen = ScreenContext(foregroundApp = "Test", pageTitle = "Test")
        val id = "test-dispatch-stack-${UUID.randomUUID()}"
        val depths = mutableListOf<Int>()
        val registry = AgentNativeToolRegistry().registerAll(AgentHardwareNativeTools.definitions(
            AgentAndroidHardwarePlatformFacade(context)))
        val agent = runtime(InMemoryAgentSessionStore(), screen, registry, onReview = {
            depths += Thread.currentThread().stackTrace.count { it.methodName == "executeFirstPendingAction" }
        })
        agent.sessionId = id
        agent.currentGoal = "\u6309\u987a\u5e8f\u8bfb\u53d6\u5341\u516d\u6b21\u624b\u673a\u5185\u5b58\u4fe1\u606f"
        agent.phase = AgentPhase.PLANNING
        agent.currentPlan = AgentPlan(agent.currentGoal, screen, emptyList(), (1..16).map { index ->
            AgentAction("read-$index", AgentActionKind.CALL_NATIVE_TOOL, AgentHardwareNativeTools.MEMORY_STATUS,
                AgentRisk.LOW, AgentActionStatus.PROPOSED, "Read memory sample $index",
                mapOf("tool_id" to AgentHardwareNativeTools.MEMORY_STATUS, "input_json" to "{}",
                    "depends_on" to if (index > 1) "read-${index - 1}" else "",
                    INTERNAL_CONVERSATION_ID to id, INTERNAL_TURN_ID to "turn"), requiresConfirmation = false)
        }, planId = id, confirmationRequired = false)
        try {
            agent.executeFirstPendingAction()
            val plan = requireNotNull(agent.currentPlan)
            assertEquals(AgentPhase.COMPLETED, agent.phase)
            assertEquals(16, plan.actions.count { it.status == AgentActionStatus.COMPLETED })
            assertEquals(16, plan.checkpoints.size)
            plan.actions.forEach { action ->
                val node = requireNotNull(AgentPlanNodeKey.from(id, plan, action))
                assertTrue(requireNotNull(agent.planNodeJournal.read(node)).verified)
            }
            println("AGENT_DISPATCH_STACK actions=16 max_depth=${depths.maxOrNull()} reviews=${depths.size}")
            assertTrue(depths.size >= 16)
            assertTrue("Dispatch stack grew across dependency layers: $depths", depths.maxOrNull()!! <= 2)
        } finally {
            agent.currentPlan?.let { plan ->
                AgentRunEventStore(context).removeRuns(plan.actions.mapNotNull {
                    AgentPlanNodeKey.from(id, plan, it)?.let(EncryptedAgentPlanNodeJournal::runId)
                }.toSet())
            }
        }
    }

    @Test fun parsedRollingBatchesKeepObservationsWithoutGrowingTheDispatchStack() {
        val screen = ScreenContext(foregroundApp = "Test", pageTitle = "Test")
        val id = "test-rolling-stack-${UUID.randomUUID()}"
        val conversation = "conversation-$id"
        val turn = "turn-$id"
        val sessions = SharedPreferencesAgentSessionStore(context, id)
        val registry = AgentNativeToolRegistry().registerAll(AgentHardwareNativeTools.definitions(
            AgentAndroidHardwarePlatformFacade(context)))
        val depths = mutableListOf<Int>()
        var assessments = 0
        val agent = runtime(sessions, screen, registry, onPlan = { request ->
            assessments++
            depths += Thread.currentThread().stackTrace.count { it.methodName == "executeFirstPendingAction" }
            assertTrue(request.replanReason.startsWith(AgentRollingPlanPolicy.REPLAN_REASON_PREFIX))
            assertEquals(assessments * 2, request.executionHistory.count { it.status == AgentActionStatus.COMPLETED })
            assertTrue(request.executionHistory.all { it.result.isNotBlank() })
            assertEquals(conversation, request.conversationContext.conversationId)
            assertEquals(turn, request.executionTurnId)
            val prompt = AgentModelPlanningPrompt.build(request, AgentModelPlannerSettings(),
                AgentTaskRequirementAnalyzer.analyze(request.goal))
            assertTrue("Native observations must reach the reasoning model", prompt.contains("total_bytes"))
            assertTrue(prompt.contains("available_bytes"))
            assertTrue(prompt.contains(request.executionHistory.last().id))
            if (assessments == 8) {
                AgentPlan(request.goal, request.screen, emptyList(), emptyList(), plannerProfile = "unavailable")
            } else {
                // Inject model JSON, but parse it and execute real hardware tools through production code.
                val actions = org.json.JSONArray()
                listOf(AgentHardwareNativeTools.MEMORY_STATUS, AgentHardwareNativeTools.STORAGE_STATUS).forEachIndexed { index, tool ->
                    actions.put(org.json.JSONObject().put("ref", "sample-$index").put("kind", "CALL_NATIVE_TOOL")
                        .put("description", "Read device sample")
                        .put("parameters", org.json.JSONObject().put("tool_id", tool).put("arguments", org.json.JSONObject())))
                }
                requireNotNull(AgentModelPlanParser.parse(request, org.json.JSONObject().put("actions", actions).toString(),
                    AgentModelPlannerSettings())).copy(plannerProfile = "guarded-model:test")
            }
        })
        agent.sessionId = id
        agent.activeConversationContext = AgentConversationContext(conversation, "", emptyList(), false)
        agent.activeConversationTurnId = turn
        agent.currentGoal = "\u8fde\u7eed\u8bfb\u53d6\u624b\u673a\u5185\u5b58\u548c\u5b58\u50a8\u4fe1\u606f\uff0c\u6bcf\u6279\u6839\u636e\u771f\u5b9e\u7ed3\u679c\u51b3\u5b9a\u4e0b\u4e00\u6279"
        agent.phase = AgentPhase.PLANNING
        agent.currentPlan = AgentPlan(agent.currentGoal, screen, emptyList(),
            listOf(AgentHardwareNativeTools.MEMORY_STATUS, AgentHardwareNativeTools.STORAGE_STATUS).map { tool ->
                AgentAction(tool, AgentActionKind.CALL_NATIVE_TOOL, tool, AgentRisk.LOW, AgentActionStatus.PROPOSED,
                    "Read initial sample", mapOf("tool_id" to tool, "input_json" to "{}",
                        INTERNAL_CONVERSATION_ID to conversation, INTERNAL_TURN_ID to turn), requiresConfirmation = false)
            }, planId = id, confirmationRequired = false, plannerProfile = "guarded-model:test")
        try {
            agent.executeFirstPendingAction()
            agent.persistSession()
            val plan = requireNotNull(SharedPreferencesAgentSessionStore(context, id).load()?.currentPlan)
            assertEquals(8, assessments)
            assertEquals(AgentPhase.WAITING_RESPONSE, agent.phase)
            assertEquals("true", agent.lastActionResult!!.metadata["rolling_plan_assessment_pending"])
            val actions = plan.actionHistory + plan.actions
            assertEquals(16, actions.size)
            assertEquals(16, actions.map { it.id }.distinct().size)
            assertEquals(16, plan.checkpoints.size)
            actions.forEach { action ->
                assertEquals(AgentActionStatus.COMPLETED, action.status)
                assertEquals(conversation, action.parameters[INTERNAL_CONVERSATION_ID])
                assertEquals(turn, action.parameters[INTERNAL_TURN_ID])
                val node = requireNotNull(AgentPlanNodeKey.from(id, plan, action))
                assertTrue(requireNotNull(agent.planNodeJournal.read(node)).verified)
            }
            var restoredAssessment = false
            val restored = runtime(SharedPreferencesAgentSessionStore(context, id), screen, registry, onPlan = { request ->
                restoredAssessment = true
                assertEquals(conversation, request.conversationContext.conversationId)
                assertEquals(turn, request.executionTurnId)
                assertEquals(16, request.executionHistory.size)
                val prompt = AgentModelPlanningPrompt.build(request, AgentModelPlannerSettings(),
                    AgentTaskRequirementAnalyzer.analyze(request.goal))
                assertTrue(prompt.contains("total_bytes"))
                assertTrue(prompt.contains("available_bytes"))
                AgentPlan(request.goal, request.screen, emptyList(), emptyList(), plannerProfile = "unavailable")
            })
            assertEquals("", restored.activeConversationContext.conversationId)
            restored.replanFromCurrentState(requireNotNull(restored.currentPlan), "Review persisted results", force = true)
            assertTrue(restoredAssessment)
            restoredAssessment = false
            // submitGoal assigns the incoming message turn before handling a continuation command.
            restored.activeConversationContext = AgentConversationContext(conversation, "", emptyList(), false)
            restored.activeConversationTurnId = "control-message-$id"
            restored.replanFromCurrentState(requireNotNull(restored.currentPlan), "user_requested_replan", force = true)
            assertTrue(restoredAssessment)
            println("AGENT_ROLLING_STACK batches=8 actions=16 max_depth=${depths.maxOrNull()}")
            assertTrue("Dispatch stack grew across rolling plans: $depths", depths.maxOrNull()!! <= 2)
        } finally {
            agent.currentPlan?.let { plan ->
                AgentRunEventStore(context).removeRuns((plan.actionHistory + plan.actions).mapNotNull {
                    AgentPlanNodeKey.from(id, plan, it)?.let(EncryptedAgentPlanNodeJournal::runId)
                }.toSet())
            }
            sessions.clear()
        }
    }

    private fun runtime(session: AgentSessionStore, screen: ScreenContext,
        registry: AgentNativeToolRegistry = AgentNativeToolRegistry(),
        onReview: () -> Unit = {},
        onPlan: (AgentRequest) -> AgentPlan = { error("Recovery must not invent a model response") }
    ) = MobileNativeAgent(context,
        sessionStore = session, memoryStore = InMemoryAgentMemoryStore(), screenObservationOverride = false,
        safetyPolicy = object : AgentSafetyPolicy by UnrestrictedAgentSafetyPolicy() {
            override fun review(plan: AgentPlan, sessionId: String): AgentSafetyReview {
                onReview()
                return UnrestrictedAgentSafetyPolicy().review(plan, sessionId)
            }
        },
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
        }).apply { runtimeTiming = com.galaxyssi.chat.metrics.AgentRuntimeTiming.NONE }

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
