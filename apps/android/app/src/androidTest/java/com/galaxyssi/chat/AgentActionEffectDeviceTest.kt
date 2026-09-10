package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentActionEffectDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val screen = ScreenContext("Test", pageTitle = "Action recovery")
    private val action get() = AgentAction("open-self", AgentActionKind.OPEN_APP, "GalaxySSI", AgentRisk.LOW,
        AgentActionStatus.RUNNING, "Open the test application", mapOf("package" to context.packageName), false)

    @Test fun mobileDirectEntryRunsActualPlatformActionOnce() = isolated { name, ledger ->
        var calls = 0
        val platform = AndroidAgentActionExecutor(context)
        val agent = runtime(name, EncryptedAgentNativeToolReplayStore(ledger), delegate { a, s ->
            calls++; platform.execute(a, s)
        })
        val first = agent.executeDirectAction(action, "conversation", "turn")
        assertTrue(first.message, first.success)
        val replay = agent.executeDirectAction(action, "conversation", "turn")
        assertTrue(replay.message, replay.success)
        assertEquals("true", replay.metadata["action_effect_replayed"])
        assertEquals(first.message, replay.message)
        assertEquals(1, calls)
    }

    @Test fun aNewRuntimeRetainsConnectorAcceptanceInsteadOfSendingAgain() {
        val name = "action-acceptance-${UUID.randomUUID()}"
        val original = AgentRunEventStore(context, "$name.db")
        val call = action.copy(kind = AgentActionKind.CALL_CONNECTOR, target = "test-only-connector")
        val expected = AgentActionResult(call.id, true, "Accepted", mapOf("awaiting_response" to "true",
            "run_id" to "remote-run", "request_id" to "request", "connector_id" to "test-only-connector"))
        try {
            val agent = runtime(name, EncryptedAgentNativeToolReplayStore(original), delegate { _, _ -> expected })
            assertEquals(expected, agent.executeDirectAction(call, "conversation", "turn"))
        } finally { original.close() }
        val reopened = AgentRunEventStore(context, "$name.db")
        try {
            val restored = runtime(name, EncryptedAgentNativeToolReplayStore(reopened), delegate { _, _ -> error("Must not send again") })
            val receipt = restored.executeDirectAction(call, "conversation", "turn")
            assertTrue(receipt.message, receipt.success)
            expected.metadata.forEach { (key, value) -> assertEquals(value, receipt.metadata[key]) }
            assertEquals("true", receipt.metadata["action_effect_replayed"])
        } finally { reopened.close() }
        context.deleteDatabase("$name.db")
    }

    @Test fun providerFallbackSurvivesEncryptedJournalReopen() {
        val name = "action-fallback-${UUID.randomUUID()}"
        val primary = action.copy(kind = AgentActionKind.CALL_CONNECTOR, target = "test-codex",
            parameters = mapOf("connector_id" to "test-codex", "prompt" to "Test only"))
        val fallback = AgentConnectorFallbackAction.prepare(primary,
            AgentConnectorFallbackSelection("test-cloud", emptyList(), listOf("test-codex"),
                emptySet(), setOf("test-codex")), null)
        var dispatches = 0
        val original = AgentRunEventStore(context, "$name.db")
        try {
            val agent = runtime(name, EncryptedAgentNativeToolReplayStore(original), delegate { a, _ ->
                dispatches++
                AgentActionResult(a.id, true, "Accepted", mapOf("awaiting_response" to "true",
                    "request_id" to "request-$dispatches"))
            })
            assertTrue(agent.executeDirectAction(primary, "conversation", "turn").success)
            val next = agent.executeDirectAction(fallback, "conversation", "turn")
            assertTrue(next.message, next.success)
            assertEquals("request-2", next.metadata["request_id"])
        } finally { original.close() }
        val reopened = AgentRunEventStore(context, "$name.db")
        try {
            val restored = runtime(name, EncryptedAgentNativeToolReplayStore(reopened), delegate { _, _ ->
                error("Restored fallback must not send again")
            })
            val replay = restored.executeDirectAction(fallback, "conversation", "turn")
            assertTrue(replay.message, replay.success)
            assertEquals("request-2", replay.metadata["request_id"])
            assertEquals("true", replay.metadata["action_effect_replayed"])
            assertEquals(2, dispatches)
        } finally { reopened.close() }
        context.deleteDatabase("$name.db")
    }

    @Test fun rollbackAfterLostReceiptDoesNotExecuteTheSameRollbackTwice() = isolated { name, ledger ->
        val backing = EncryptedAgentNativeToolReplayStore(ledger)
        val faulty = object : AgentNativeToolReplayStore by backing {
            override fun complete(key: AgentNativeToolReplayKey, invocationId: String, result: AgentNativeToolResult) {
                error("Test rollback receipt interruption")
            }
        }
        val completed = action.copy(status = AgentActionStatus.COMPLETED)
        val plan = AgentPlan("\u6d4b\u8bd5\u56de\u6eda\u6062\u590d", screen, emptyList(), listOf(completed),
            planId = name, confirmationRequired = false).addCheckpoint(AgentExecutionContinuity.checkpointBefore(completed, screen, 1))
        var calls = 0
        val platform = delegate { a, _ -> calls++; AgentActionResult(a.id, true, "Rollback completed") }
        val original = runtime(name, faulty, platform).apply { currentPlan = plan; currentGoal = plan.goal }
        original.rollbackLastAction()
        assertEquals(1, calls)
        val restored = runtime(name, backing, platform).apply { currentPlan = plan; currentGoal = plan.goal }
        restored.rollbackLastAction()
        assertEquals(1, calls)
        assertEquals("effect_outcome_unknown", restored.lastActionResult!!.metadata["error_code"])
    }

    @Test fun crashAfterActualPlatformLaunchBeforeDispatchReceipt() {
        val name = crashCase()
        val directory = File(context.filesDir, name)
        check(!directory.exists()) { "Inspect existing case; never reseed it" }
        check(directory.mkdirs())
        val ledger = AgentRunEventStore(context, "$name.db")
        val backing = EncryptedAgentNativeToolReplayStore(ledger)
        val crashing = object : AgentNativeToolReplayStore by backing {
            override fun complete(key: AgentNativeToolReplayKey, invocationId: String, result: AgentNativeToolResult) {
                check(result.isSuccess) { result.toJson() }
                durableWrite(File(directory, "pid-before.txt"), android.os.Process.myPid().toString())
                android.os.Process.killProcess(android.os.Process.myPid())
                error("Process must stop before receipt commit")
            }
        }
        val platform = AndroidAgentActionExecutor(context)
        val agent = runtime(name, crashing, delegate { a, s ->
            durableWrite(File(directory, "dispatch-count.txt"), "1")
            platform.execute(a, s)
        })
        agent.executeDirectAction(action, "conversation", "turn")
        fail("Expected process termination")
    }

    @Test fun recoverActualPlatformLaunchWithoutDispatchingAgain() {
        val name = crashCase()
        val directory = File(context.filesDir, name)
        assertTrue(File(directory, "pid-before.txt").exists())
        assertNotEquals(File(directory, "pid-before.txt").readText(), android.os.Process.myPid().toString())
        val ledger = AgentRunEventStore(context, "$name.db")
        try {
            val agent = runtime(name, EncryptedAgentNativeToolReplayStore(ledger), delegate { _, _ ->
                durableWrite(File(directory, "dispatch-count.txt"), "2")
                error("The same platform launch must not execute again")
            })
            val result = agent.executeDirectAction(action, "conversation", "turn")
            assertEquals(result.message, "effect_outcome_unknown", result.metadata["error_code"])
            assertEquals("1", File(directory, "dispatch-count.txt").readText())
            durableWrite(File(directory, "verified.txt"), "Original action was not repeated")
        } finally { ledger.close() }
    }

    private fun runtime(name: String, journal: AgentNativeToolReplayStore, platform: AgentActionExecutor) = MobileNativeAgent(
        context, sessionStore = InMemoryAgentSessionStore(), memoryStore = InMemoryAgentMemoryStore(),
        actionExecutor = platform, actionEffectReplayStore = journal, screenObservationOverride = false,
        nativeToolRegistryProvider = { AgentNativeToolRegistry() },
        perceptionProvider = object : ScreenPerceptionProvider {
            override fun capture() = screen
            override fun capture(foregroundApp: String, pageTitle: String) = screen
        },
        planner = object : AgentPlanner { override fun plan(request: AgentRequest): AgentPlan = error("No cloud test") },
        connectorRegistry = object : AgentConnectorRegistry { override fun availableTargets() = emptyList<AgentCallableTarget>() },
        taskStore = object : AgentTaskStore {
            override fun upsert(record: AgentTaskRecord) = Unit
            override fun recent(limit: Int) = emptyList<AgentTaskRecord>()
            override fun forSession(sessionId: String, limit: Int) = emptyList<AgentTaskRecord>()
            override fun find(taskId: String): AgentTaskRecord? = null
            override fun search(query: String, limit: Int) = emptyList<AgentTaskRecord>()
            override fun rebindSession(sourceSessionId: String, targetSessionId: String) = 0
            override fun delete(taskIds: Set<String>) = Unit
            override fun clear() = Unit
        }).apply { sessionId = name; currentScreen = screen }

    private fun delegate(block: (AgentAction, ScreenContext) -> AgentActionResult) = object : AgentActionExecutor {
        override fun execute(action: AgentAction, screen: ScreenContext) = block(action, screen)
    }
    private fun isolated(block: (String, AgentRunEventStore) -> Unit) {
        val name = "action-effect-${UUID.randomUUID()}"
        val ledger = AgentRunEventStore(context, "$name.db")
        try { block(name, ledger) } finally { ledger.close() }
        context.deleteDatabase("$name.db")
    }
    private fun crashCase(): String {
        val id = InstrumentationRegistry.getArguments().getString("action_crash_case").orEmpty()
        assumeTrue("Explicit crash case required", id.isNotBlank())
        require(id.matches(Regex("[a-z0-9-]{1,60}")))
        return "action-crash-$id"
    }
    private fun durableWrite(file: File, value: String) = FileOutputStream(file).use {
        it.write(value.toByteArray(Charsets.UTF_8)); it.fd.sync()
    }
}
