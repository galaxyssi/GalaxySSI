package com.galaxyssi.chat

import android.content.Intent
import androidx.test.core.app.ActivityScenario
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
class AgentInitialPlanningDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val screen = ScreenContext("Test", pageTitle = "Planning recovery")
    private val goal = "\u89c4\u5212\u6062\u590d\u9a8c\u8bc1\uff1a\u4fdd\u7559\u89c2\u5bdf\u5e76\u5b8c\u6210\u539f\u4efb\u52a1"
    private val action = AgentAction("observe", AgentActionKind.CALL_NATIVE_TOOL,
        AgentHardwareNativeTools.MEMORY_STATUS, AgentRisk.LOW, AgentActionStatus.PROPOSED, "Read memory",
        mapOf("tool_id" to AgentHardwareNativeTools.MEMORY_STATUS, "input_json" to "{}"), requiresConfirmation = false)
    private val spec = AgentPlannerRecoverySpec(AgentPlannerRecoveryKind.NATIVE_ACTION, action)

    @Test fun encryptedInputPreservesLargeContextAndExactProviderParameters() {
        val name = "test-initial-input-${UUID.randomUUID()}"
        val ledger = AgentRunEventStore(context, "$name.db")
        try {
            val journal = AgentPlanningJournal(context, EncryptedAgentModelLoopJournal(context, ledger))
            val entry = AgentTranscriptEntry("entry", AgentTranscriptRole.USER, "\u4e0a\u6587".repeat(100_000), 1,
                conversationId = name, turnId = "earlier", richOutputJson = "{\"file\":\"test-input.png\"}")
            val input = AgentPlanningInput(goal.repeat(3000), AgentConversationContext(name, "summary",
                listOf(entry), true, "private local context", true), name,
                listOf(AgentRequestedMember("provider", "Provider", 2, "review")), AgentTaskExecutionMode.PLAN_ONLY,
                spec.copy(action = action.copy(parameters = action.parameters + ("retained" to "x".repeat(40_000)))))
            lateinit var ref: AgentPlanningReference
            journal.begin(name, input) { ref = it }
            journal.restore(ref) { assertEquals(input, it) }
            val store = SharedPreferencesAgentSessionStore(context, name)
            val saved = AgentSessionSnapshot(name, AgentPhase.PLANNING, input.goal, screen, null, emptyList(), null,
                pendingPlanning = ref, updatedAtMillis = 1)
            store.save(saved)
            assertEquals(ref, store.load()!!.pendingPlanning)
            assertTrue(store.encodeRecoverySession(saved, minimal = true).toString().length < 128 * 1024)
            store.clear()
        } finally { ledger.close(); context.deleteDatabase("$name.db") }
    }

    @Test fun ordinaryRuntimeRestoresPlanningAndItsModelObservationWithoutResubmission() {
        val name = "test-initial-model-${UUID.randomUUID()}"
        val ledger = AgentRunEventStore(context, "$name.db")
        val journal = EncryptedAgentModelLoopJournal(context, ledger)
        val store = SharedPreferencesAgentSessionStore(context, name)
        var effects = 0
        var recovering = false
        val descriptor = AgentNativeToolDescriptor("test.initial.observe", "1.0.0", "Observe", "Observe",
            AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
            AgentNativeToolRisk.LOW, setOf("test"))
        val registry = AgentNativeToolRegistry(replayStore = EncryptedAgentNativeToolReplayStore(ledger))
            .register(AgentNativeToolDefinition(descriptor, AgentNativeToolExecutor {
                effects++; AgentNativeToolExecutionResult.success(mapOf("observed" to true))
            }))
        val planning = object : AgentPlanner {
            override fun recoverySpec() = AgentPlannerRecoverySpec(AgentPlannerRecoveryKind.GUARDED_MODEL,
                configurationSha256 = "fixture")
            override fun plan(request: AgentRequest): AgentPlan {
                assertEquals(name, request.executionTurnId)
                assertEquals(name, request.conversationContext.conversationId)
                assertTrue(request.conversationContext.privateMode)
                assertEquals("review", request.requestedMembers.single().roleHint)
                runBlocking { AgentModelToolLoop(AgentModelAdapter {
                    if (!recovering && it.round == 1) AgentModelResponse(toolCalls = listOf(AgentModelToolCall("observe", descriptor.id)))
                    else if (!recovering) throw CancellationException("Simulated process interruption")
                    else {
                        assertEquals(2, it.round)
                        assertEquals(true, it.messages.last().toolResult?.output?.get("observed"))
                        AgentModelResponse("\u89c2\u5bdf\u5df2\u6062\u590d")
                    }
                }, registry, journal = journal).run(AgentPlannerToolLoopRequest.create(request,
                    AgentModelPlannerSettings(), listOf(AgentModelMessage.user(request.goal)), registry.descriptors())) }
                return AgentPlanFactory.actions(request, listOf(action))
            }
        }
        try {
            val runtime = runtime(name, store, planning, journal)
            runtime.currentGoal = goal
            runtime.activeConversationContext = AgentConversationContext(name, "", emptyList(), true)
            runtime.activeConversationTurnId = name
            runtime.activeRequestedMembers = listOf(AgentRequestedMember("provider", "Provider", roleHint = "review"))
            runtime.activeTaskExecutionMode = AgentTaskExecutionMode.PLAN_ONLY
            runtime.startExecutionLoop(name)
            try { runtime.beginInitialPlanning(android.os.SystemClock.elapsedRealtime()); fail("Expected interruption") }
            catch (_: CancellationException) { }
            val saved = store.load()!!
            assertNull(saved.currentPlan)
            assertNotNull(saved.pendingPlanning)
            store.save(AgentColdBootRecoveryPolicy.pauseSession(saved, "previous-process", 2, "Interrupted"))
            recovering = true
            val resumed = runtime(name, store, planning, journal).resumeCurrentTask()
            assertEquals(AgentPhase.COMPLETED, resumed.phase)
            assertEquals(AgentTaskExecutionMode.PLAN_ONLY, resumed.taskExecutionMode)
            assertNull(store.load()!!.pendingPlanning)
            assertNotNull(store.load()!!.currentPlan)
            assertEquals(1, effects)
        } finally { store.clear(); ledger.close(); context.deleteDatabase("$name.db") }
    }

    @Test fun pauseAndCancelDuringPlanningPreventPlanPublication() {
        for (cancel in listOf(false, true)) {
            val name = "test-initial-stop-${UUID.randomUUID()}"
            val store = SharedPreferencesAgentSessionStore(context, name)
            lateinit var agent: MobileNativeAgent
            val planning = object : AgentPlanner {
                override fun recoverySpec() = spec
                override fun plan(request: AgentRequest): AgentPlan {
                    if (cancel) agent.cancelCurrentTask() else agent.pauseCurrentTask()
                    return AgentPlanFactory.actions(request, listOf(action))
                }
            }
            try {
                agent = runtime(name, store, planning, InMemoryAgentModelLoopJournal())
                agent.currentGoal = goal; agent.activeConversationTurnId = name
                agent.activeConversationContext = AgentConversationContext(name, "", emptyList(), true)
                agent.startExecutionLoop(name)
                val state = agent.beginInitialPlanning(android.os.SystemClock.elapsedRealtime())
                assertEquals(if (cancel) AgentPhase.CANCELLED else AgentPhase.PAUSED, state.phase)
                assertNull(state.plan)
                assertEquals(!cancel, store.load()!!.pendingPlanning != null)
            } finally { store.clear() }
        }
    }

    @Test fun prepareAutomaticStartupRecoveryBeforeAPlanIsPublished() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("initial_planning_prepare") == "true")
        val name = caseName()
        val store = SharedPreferencesAgentSessionStore(context, "task:$name")
        check(store.load() == null) { "Preserve the existing case; do not submit again" }
        val planning = object : AgentPlanner {
            override fun recoverySpec() = spec
            override fun plan(request: AgentRequest): AgentPlan {
                val saved = store.load()!!
                check(saved.pendingPlanning != null && saved.currentPlan == null)
                EncryptedAgentWorkspaceStore(context).upsert(AgentWorkspace(name, name, name, name,
                    goal = goal, status = AgentWorkspaceStatus.RUNNING))
                write("$name.pid", android.os.Process.myPid().toString())
                android.os.Process.killProcess(android.os.Process.myPid())
                error("Expected process death")
            }
        }
        runtime(name, store, planning).submitGoal(goal, AgentConversationContext(name, "", emptyList(), true), name,
            AgentTaskExecutionMode.AUTO_COMPLETE)
        fail("Expected process death")
    }

    @Test fun appStartupWorkerRecoversTheOriginalPendingPlannerWithoutExplicitResubmission() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("initial_planning_verify") == "true")
        val name = caseName()
        val store = SharedPreferencesAgentSessionStore(context, "task:$name")
        val workspaceStore = EncryptedAgentWorkspaceStore(context)
        ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)).use {
            awaitStartupRecovery(name, store, workspaceStore)
        }
    }

    private fun awaitStartupRecovery(name: String, store: AgentSessionStore,
        workspaceStore: EncryptedAgentWorkspaceStore) {
        val deadline = System.nanoTime() + java.util.concurrent.TimeUnit.SECONDS.toNanos(120)
        while (System.nanoTime() < deadline) {
            val workspace = workspaceStore.find(name) ?: error("Missing original workspace")
            if (workspace.status == AgentWorkspaceStatus.COMPLETED) {
                val session = store.load()!!
                assertNull(session.pendingPlanning)
                assertEquals(AgentPhase.COMPLETED, session.phase)
                assertEquals(name, session.executionLoopSnapshot!!.taskId)
                assertEquals(1, session.currentPlan!!.actions.size)
                assertEquals(AgentActionStatus.COMPLETED, session.currentPlan.actions.single().status)
                assertEquals(AgentHardwareNativeTools.MEMORY_STATUS, session.currentPlan.actions.single().parameters["tool_id"])
                assertNotEquals(context.getFileStreamPath("$name.pid").readText(), android.os.Process.myPid().toString())
                write("$name.verified", android.os.Process.myPid().toString())
                return
            }
            check(!workspace.status.isTerminal) { "Recovery became ${workspace.status}: ${workspace.errorMessage}" }
            Thread.sleep(200)
        }
        fail("Startup did not recover the retained initial planner; inspect this case without resubmission")
    }

    private fun runtime(name: String, store: AgentSessionStore, planning: AgentPlanner,
        journal: AgentModelLoopJournal? = null) = MobileNativeAgent(context, planner = planning, sessionStore = store,
        initialPlanningJournal = journal, memoryStore = InMemoryAgentMemoryStore(),
        taskStore = SQLiteAgentTaskStore(context, "$name-tasks.db"),
        knowledgeStore = SQLiteAgentKnowledgeStore(context, "$name-knowledge.db", "$name-legacy") { _, _ -> },
        screenObservationOverride = false, perceptionProvider = object : ScreenPerceptionProvider {
            override fun capture() = screen
            override fun capture(foregroundApp: String, pageTitle: String) = screen
        }, connectorRegistry = object : AgentConnectorRegistry {
            override fun availableTargets() = listOf(AgentCallableTarget("provider", "Provider",
                AgentConnectorKind.AGENT, AgentConnectorStatus.AVAILABLE, emptyList()))
        }, actionExecutor = object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult =
                error("The prepare/test runtime must not execute a plan")
        })
    private fun write(name: String, value: String) = FileOutputStream(context.getFileStreamPath(name)).use {
        it.write(value.toByteArray()); it.fd.sync()
    }
    private fun caseName(): String {
        val value = InstrumentationRegistry.getArguments().getString("initial_planning_case").orEmpty()
        require(value.matches(Regex("[A-Za-z0-9-]{1,64}")))
        return "test-initial-planner-$value"
    }
}
