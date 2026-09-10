package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.FileOutputStream
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentReplanningDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val screen = ScreenContext("Test", pageTitle = "Replanning")
    private val goal = "\u91cd\u89c4\u5212\u6062\u590d\u6d4b\u8bd5\uff1a\u4fdd\u7559\u5148\u524d\u7684\u89c2\u5bdf\u7ed3\u679c"
    private val reason = "\u7ee7\u7eed\u539f\u6765\u7684\u8ba1\u5212\uff0c\u4e0d\u8981\u91cd\u590d\u5df2\u5b8c\u6210\u7684\u64cd\u4f5c"
    private val spec = AgentPlannerRecoverySpec(AgentPlannerRecoveryKind.GUARDED_MODEL, configurationSha256 = "fixture")
    private val descriptor = AgentNativeToolDescriptor("test.replan.observe", "1.0.0", "Observe", "Observe",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
        AgentNativeToolRisk.LOW, setOf("test"))

    @Test fun restoresTheOriginalReasonRevisionAndObservationWithoutRepeatingTools() = isolated { name, store, ledger ->
        interrupt(name, store, ledger)
        val saved = store.load()!!
        assertTrue(saved.pendingPlanning!!.isReplanning)
        assertEquals(7, saved.currentPlan!!.revision)
        store.save(AgentColdBootRecoveryPolicy.pauseSession(saved, "previous-process", 2, "Interrupted"))
        verifyRestoration(name, store, ledger)
    }

    @Test fun baseGraphRoundTripKeepsLargeEvidenceAndToolArguments() = isolated { name, store, ledger ->
        val source = plan(name).copy(actions = listOf(action(name).copy(result = "result".repeat(20_000),
            parameters = action(name).parameters + ("retained" to "x".repeat(40_000)))))
        val journal = AgentPlanningJournal(context, EncryptedAgentModelLoopJournal(context, ledger))
        val digest = journal.planFingerprint(source, goal)
        store.save(AgentSessionSnapshot(name, AgentPhase.PLANNING, goal, screen, source, emptyList(), null,
            updatedAtMillis = 1))
        assertEquals(digest, journal.planFingerprint(store.load()!!.currentPlan!!, goal))
    }

    @Test fun changedBaseGraphIsRejectedBeforeAnotherModelCall() = isolated { name, store, ledger ->
        interrupt(name, store, ledger)
        val saved = store.load()!!
        store.save(AgentColdBootRecoveryPolicy.pauseSession(saved.copy(currentPlan = saved.currentPlan!!.copy(
            actions = listOf(action(name).copy(result = "changed")))), "previous-process", 2, "Interrupted"))
        val agent = runtime(name, store, object : AgentPlanner {
            override fun recoverySpec() = spec
            override fun plan(request: AgentRequest): AgentPlan = error("Changed input must not reach the model")
        }, ledger)
        try { agent.resumeCurrentTask(); fail("Expected mismatched base to be rejected") }
        catch (error: AgentModelLoopRecoveryException) { assertTrue(error.message.orEmpty().contains("base_plan_changed")) }
    }

    @Test fun changedPlannerConfigurationDoesNotSilentlySelectADefaultModel() = isolated { name, store, ledger ->
        interrupt(name, store, ledger)
        store.save(AgentColdBootRecoveryPolicy.pauseSession(store.load()!!, "previous-process", 2, "Interrupted"))
        val agent = runtime(name, store, object : AgentPlanner {
            override fun recoverySpec() = spec.copy(configurationSha256 = "changed")
            override fun plan(request: AgentRequest): AgentPlan = error("Changed provider must not be called")
        }, ledger)
        try { agent.resumeCurrentTask(); fail("Expected changed configuration to be rejected") }
        catch (error: AgentModelLoopRecoveryException) { assertTrue(error.message.orEmpty().contains("configuration_changed")) }
    }

    @Test fun manualReplanDoesNotOverwritePauseOrCancellationAfterTheModelReturns() {
        for (cancel in listOf(false, true)) isolated { name, store, ledger ->
            lateinit var agent: MobileNativeAgent
            agent = runtime(name, store, object : AgentPlanner {
                override fun recoverySpec() = spec
                override fun plan(request: AgentRequest): AgentPlan {
                    if (cancel) agent.cancelCurrentTask() else agent.pauseCurrentTask()
                    return proposal(name, request)
                }
            }, ledger)
            initialize(agent, name)
            val state = agent.replanCurrentTask()
            assertEquals(if (cancel) AgentPhase.CANCELLED else AgentPhase.PAUSED, state.phase)
            if (cancel) assertNull(state.plan) else assertEquals(7, state.plan!!.revision)
            assertEquals(!cancel, store.load()!!.pendingPlanning != null)
        }
    }

    @Test fun interruptAfterTheReplanningToolObservationForPhysicalReboot() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("replanning_prepare") == "true")
        val name = caseName()
        val store = SharedPreferencesAgentSessionStore(context, name)
        check(store.load() == null) { "Preserve the existing case; do not resubmit" }
        val ledger = AgentRunEventStore(context, "$name-ledger.db")
        val agent = runtime(name, store, planner(name, ledger, recovering = false, kill = true), ledger)
        initialize(agent, name)
        agent.replanFromCurrentState(agent.currentPlan!!, reason, force = true)
        fail("Expected controlled process death")
    }

    @Test fun restoreOriginalReplanningAfterPhysicalReboot() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("replanning_verify") == "true")
        val name = caseName()
        val store = SharedPreferencesAgentSessionStore(context, name)
        val ledger = AgentRunEventStore(context, "$name-ledger.db")
        try {
            assertNotEquals(context.getFileStreamPath("$name.pid").readText(), android.os.Process.myPid().toString())
            verifyRestoration(name, store, ledger)
            write("$name.verified", android.os.Process.myPid().toString())
        } finally { ledger.close() }
    }

    private fun interrupt(name: String, store: AgentSessionStore, ledger: AgentRunEventStore) {
        val agent = runtime(name, store, planner(name, ledger, recovering = false), ledger)
        initialize(agent, name)
        try { agent.replanFromCurrentState(agent.currentPlan!!, reason, force = true); fail("Expected interruption") }
        catch (_: CancellationException) { }
    }

    private fun verifyRestoration(name: String, store: AgentSessionStore, ledger: AgentRunEventStore) {
        val state = runtime(name, store, planner(name, ledger, recovering = true), ledger).resumeCurrentTask()
        assertEquals(AgentPhase.COMPLETED, state.phase)
        assertEquals(9, state.plan!!.revision)
        assertEquals(8, state.plan.replanCount)
        assertTrue(state.plan.actionHistory.any { it.result == "previous verified observation" })
        assertTrue(state.plan.actionHistory.any { it.id.startsWith("r8-") && it.status == AgentActionStatus.COMPLETED })
        assertNull(store.load()!!.pendingPlanning)
        assertEquals("observed", context.getFileStreamPath("$name.effect").readText())
    }

    private fun planner(name: String, ledger: AgentRunEventStore, recovering: Boolean, kill: Boolean = false): AgentPlanner {
        val registry = AgentNativeToolRegistry(replayStore = EncryptedAgentNativeToolReplayStore(ledger)).register(
            AgentNativeToolDefinition(descriptor, AgentNativeToolExecutor {
                check(!recovering) { "A committed replanning observation must not execute again" }
                FileOutputStream(context.getFileStreamPath("$name.effect"), true).use {
                    it.write("observed".toByteArray()); it.fd.sync()
                }
                AgentNativeToolExecutionResult.success(mapOf("observed" to true))
            }))
        return object : AgentPlanner {
            override fun recoverySpec() = spec
            override fun plan(request: AgentRequest): AgentPlan {
                if (request.planningRevision == 9) {
                    check(recovering)
                    assertTrue(AgentRollingPlanPolicy.isBatchBoundaryReason(request.replanReason))
                    assertTrue(request.executionHistory.any { it.id.startsWith("r8-") && it.status == AgentActionStatus.COMPLETED })
                    runBlocking { AgentModelToolLoop(AgentModelAdapter {
                        assertEquals(1, it.round)
                        AgentModelResponse("\u89c2\u5bdf\u7ed3\u679c\u5df2\u786e\u8ba4\uff0c\u4efb\u52a1\u5b8c\u6210")
                    }, registry, journal = EncryptedAgentModelLoopJournal(context, ledger)).run(
                        AgentPlannerToolLoopRequest.create(request, AgentModelPlannerSettings(),
                            listOf(AgentModelMessage.user(request.goal)), registry.descriptors())) }
                    return AgentPlanFactory.actions(request, listOf(AgentAction("finish", AgentActionKind.DRAFT_PLAN,
                        "task-complete", AgentRisk.LOW, AgentActionStatus.PROPOSED,
                        "\u5df2\u6062\u590d\u539f\u89c4\u5212\u5e76\u9a8c\u8bc1\u624b\u673a\u5185\u5b58\u67e5\u8be2",
                        requiresConfirmation = false))).copy(plannerProfile = "guarded-model:fixture")
                }
                assertEquals(reason, request.replanReason)
                assertEquals(name, request.executionTurnId)
                assertEquals(name, request.conversationContext.conversationId)
                assertTrue(request.conversationContext.privateMode)
                assertEquals(8, request.planningRevision)
                assertEquals("previous verified observation", request.executionHistory.single().result)
                runBlocking { AgentModelToolLoop(AgentModelAdapter {
                    if (!recovering && it.round == 1) AgentModelResponse(toolCalls = listOf(AgentModelToolCall("observe", descriptor.id)))
                    else if (!recovering) {
                        if (kill) { write("$name.pid", android.os.Process.myPid().toString()); android.os.Process.killProcess(android.os.Process.myPid()) }
                        throw CancellationException("Interrupted during model replanning")
                    } else {
                        assertEquals(2, it.round)
                        assertEquals(true, it.messages.last().toolResult?.output?.get("observed"))
                        AgentModelResponse("\u5df2\u6062\u590d\u89c2\u5bdf\u7ed3\u679c")
                    }
                }, registry, journal = EncryptedAgentModelLoopJournal(context, ledger)).run(
                    AgentPlannerToolLoopRequest.create(request, AgentModelPlannerSettings(),
                        listOf(AgentModelMessage.user(request.goal)), registry.descriptors())) }
                return proposal(name, request)
            }
        }
    }

    private fun initialize(agent: MobileNativeAgent, name: String) {
        agent.sessionId = name; agent.currentGoal = goal; agent.currentPlan = plan(name)
        agent.activeConversationContext = AgentConversationContext(name, "", emptyList(), true)
        agent.activeConversationTurnId = name; agent.phase = AgentPhase.PLANNING
        agent.startExecutionLoop(name)
        check(agent.advanceExecutionLoop(AgentExecutionLoopPhase.ACT, "Test action started"))
        check(agent.advanceExecutionLoop(AgentExecutionLoopPhase.OBSERVE, "Test action observation committed"))
    }
    private fun action(name: String) = AgentAction("done", AgentActionKind.CALL_NATIVE_TOOL, AgentHardwareNativeTools.MEMORY_STATUS,
        AgentRisk.LOW, AgentActionStatus.COMPLETED, "Completed", mapOf("tool_id" to AgentHardwareNativeTools.MEMORY_STATUS,
            "input_json" to "{}", INTERNAL_CONVERSATION_ID to name, INTERNAL_TURN_ID to name),
        requiresConfirmation = false, result = "previous verified observation")
    private fun plan(name: String) = AgentPlan(goal, screen, emptyList(), listOf(action(name)), planId = name,
        revision = 7, replanCount = 6, confirmationRequired = false, plannerProfile = "guarded-model:fixture")
    private fun proposal(name: String, request: AgentRequest) = AgentPlanFactory.actions(request,
        listOf(action(name).copy(id = "next", status = AgentActionStatus.PROPOSED, result = "")))
        .copy(plannerProfile = "guarded-model:fixture")
    private fun runtime(name: String, store: AgentSessionStore, planner: AgentPlanner, ledger: AgentRunEventStore) =
        MobileNativeAgent(context, sessionStore = store, planner = planner, memoryStore = InMemoryAgentMemoryStore(),
            initialPlanningJournal = EncryptedAgentModelLoopJournal(context, ledger), screenObservationOverride = false,
            safetyPolicy = UnrestrictedAgentSafetyPolicy(), taskStore = SQLiteAgentTaskStore(context, "$name-tasks.db"),
            knowledgeStore = SQLiteAgentKnowledgeStore(context, "$name-knowledge.db", "$name-legacy") { _, _ -> },
            perceptionProvider = object : ScreenPerceptionProvider {
                override fun capture() = screen
                override fun capture(foregroundApp: String, pageTitle: String) = screen
            }, connectorRegistry = object : AgentConnectorRegistry { override fun availableTargets() = emptyList<AgentCallableTarget>() },
            actionExecutor = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                    check((action.id.startsWith("r8-") && action.parameters["tool_id"] == AgentHardwareNativeTools.MEMORY_STATUS) ||
                        (action.id.startsWith("r9-") && action.isTaskCompleteMarker())) { "Old completed actions must not execute" }
                    return AndroidAgentActionExecutor(context).execute(action, screen)
                }
            })
    private fun isolated(block: (String, AgentSessionStore, AgentRunEventStore) -> Unit) {
        val name = "test-replanning-${UUID.randomUUID()}"
        val store = SharedPreferencesAgentSessionStore(context, name)
        val ledger = AgentRunEventStore(context, "$name-ledger.db")
        try { block(name, store, ledger) } finally { store.clear(); ledger.close(); context.deleteDatabase("$name-ledger.db") }
    }
    private fun write(name: String, value: String) = FileOutputStream(context.getFileStreamPath(name)).use {
        it.write(value.toByteArray()); it.fd.sync()
    }
    private fun caseName(): String {
        val value = InstrumentationRegistry.getArguments().getString("replanning_case").orEmpty()
        require(value.matches(Regex("[A-Za-z0-9-]{1,64}")))
        return "test-replanning-$value"
    }
}
