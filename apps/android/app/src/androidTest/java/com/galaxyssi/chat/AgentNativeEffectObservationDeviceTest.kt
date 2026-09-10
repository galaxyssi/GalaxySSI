package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.FileOutputStream
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentNativeEffectObservationDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val descriptor = AgentNativeToolDescriptor("test.offline.effect", "1.0.0", "Test effect", "Test effect",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
        AgentNativeToolRisk.LOW, setOf("test"), idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT)
    private val invocation = AgentNativeToolInvocationContext(invocationId = "original", sessionId = "test-session",
        conversationId = "test-conversation", turnId = "test-turn", idempotencyKey = "completed",
        attributes = mapOf("client_route_id" to "test-route", "goal_id" to "test-goal", "task_id" to "test-task"))
    private val input = emptyMap<String, Any?>()
    private val key get() = AgentNativeToolReplayKey(descriptor.id, descriptor.version,
        invocation.idempotencyKey!!, AgentNativeEffectScope.from(invocation))

    @Test fun encryptedOutcomeReopensWithoutAvailabilityOrExecutor() = isolated { name ->
        val ledger = AgentRunEventStore(context, name)
        val first = runtime(ledger).invoke(descriptor.id, input, invocation)
        assertTrue(first.toJson(), first.isSuccess)
        ledger.close()
        val reopened = AgentRunEventStore(context, name)
        try {
            val before = reopened.latestEvent(EncryptedAgentNativeToolReplayStore.runId(key))
            val replay = runtime(reopened, offline = true).invoke(descriptor.id, input, invocation.copy(invocationId = "reopen"))
            assertTrue(replay.toJson(), replay.receipt.replayed)
            assertEquals(first.output, replay.output)
            assertEquals("original", replay.receipt.originalInvocationId)
            assertEquals(before, reopened.latestEvent(EncryptedAgentNativeToolReplayStore.runId(key)))
        } finally { reopened.close() }
    }

    @Test fun observingMissingAndUnfinishedEffectsDoesNotClaimOrAppend() = isolated { name ->
        val ledger = AgentRunEventStore(context, name)
        try {
            val journal = EncryptedAgentNativeToolReplayStore(ledger)
            assertNull(journal.observe(key))
            assertNull(ledger.latestEvent(EncryptedAgentNativeToolReplayStore.runId(key)))
            journal.claim(key, AgentNativeJsonCodec.sha256(input), "owner")
            val before = ledger.latestEvent(EncryptedAgentNativeToolReplayStore.runId(key))
            val observed = requireNotNull(journal.observe(key))
            assertFalse(observed.acquired)
            assertNull(observed.result)
            assertEquals("owner", observed.invocationId)
            val retry = runtime(ledger, offline = true).invoke(descriptor.id, input, invocation)
            assertEquals("effect_outcome_unknown", retry.error?.code)
            assertEquals(before, ledger.latestEvent(EncryptedAgentNativeToolReplayStore.runId(key)))
        } finally { ledger.close() }
    }

    @Test fun crashAfterCompletedAndUncommittedRealWrites() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("effect_observation_prepare") == "true")
        val case = restartCase()
        check(!context.getDatabasePath(case + ".db").exists() && !context.getFileStreamPath(case + ".pid").exists()) {
            "Do not replace an existing crash case"
        }
        val ledger = AgentRunEventStore(context, case + ".db")
        write(case + ".pid", android.os.Process.myPid().toString())
        val completed = runtime(ledger, execute = {
            write(case + ".completed", "one-write")
            AgentNativeToolExecutionResult.success(mapOf("saved" to true))
        }).invoke(descriptor.id, input, invocation)
        assertTrue(completed.toJson(), completed.isSuccess)
        runtime(ledger, execute = {
            write(case + ".uncertain", "one-write")
            android.os.Process.killProcess(android.os.Process.myPid())
            error("The test process must terminate before committing this outcome")
        }).invoke(descriptor.id, input, invocation.copy(invocationId = "interrupted", idempotencyKey = "uncertain"))
        fail("The process did not terminate")
    }

    @Test fun recoverBothWritesAfterProcessDeathWhileToolIsOffline() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("effect_observation_verify") == "true")
        val case = restartCase()
        check(context.getDatabasePath(case + ".db").exists())
        assertNotEquals(context.getFileStreamPath(case + ".pid").readText(), android.os.Process.myPid().toString())
        val ledger = AgentRunEventStore(context, case + ".db")
        try {
            val uncertainKey = key.copy(idempotencyKey = "uncertain")
            val beforeCompleted = ledger.latestEvent(EncryptedAgentNativeToolReplayStore.runId(key))
            val beforeUncertain = ledger.latestEvent(EncryptedAgentNativeToolReplayStore.runId(uncertainKey))
            val runtime = runtime(ledger, offline = true)
            val completed = runtime.invoke(descriptor.id, input, invocation.copy(invocationId = "after-restart"))
            assertTrue(completed.toJson(), completed.isSuccess)
            assertTrue(completed.receipt.replayed)
            assertEquals("original", completed.receipt.originalInvocationId)
            val uncertain = runtime.invoke(descriptor.id, input,
                invocation.copy(invocationId = "after-restart-unknown", idempotencyKey = "uncertain"))
            assertEquals("effect_outcome_unknown", uncertain.error?.code)
            assertFalse(uncertain.error!!.retryable)
            assertEquals("interrupted", uncertain.error?.details?.get("original_invocation_id"))
            assertEquals("one-write", context.getFileStreamPath(case + ".completed").readText())
            assertEquals("one-write", context.getFileStreamPath(case + ".uncertain").readText())
            assertEquals(beforeCompleted, ledger.latestEvent(EncryptedAgentNativeToolReplayStore.runId(key)))
            assertEquals(beforeUncertain, ledger.latestEvent(EncryptedAgentNativeToolReplayStore.runId(uncertainKey)))
            write(case + ".verified", android.os.Process.myPid().toString())
        } finally { ledger.close() }
    }

    private fun runtime(ledger: AgentRunEventStore, offline: Boolean = false,
        execute: () -> AgentNativeToolExecutionResult = { AgentNativeToolExecutionResult.success(mapOf("saved" to true)) }) =
        AgentNativeToolRegistry(replayStore = EncryptedAgentNativeToolReplayStore(ledger)).register(
            AgentNativeToolDefinition(descriptor, AgentNativeToolExecutor {
                check(!offline) { "Recovery must not repeat a write" }
                execute()
            }, availabilityProvider = AgentNativeToolAvailabilityProvider {
                check(!offline) { "Recovery must not probe live tool availability" }
                AgentNativeToolAvailability.AVAILABLE
            }))

    private fun write(name: String, text: String) = FileOutputStream(context.getFileStreamPath(name)).use {
        it.write(text.toByteArray()); it.fd.sync()
    }

    private fun restartCase(): String {
        val id = InstrumentationRegistry.getArguments().getString("effect_observation_case").orEmpty()
        require(id.matches(Regex("[A-Za-z0-9-]{1,64}"))) { "A unique bounded case id is required" }
        return "test-effect-observation-$id"
    }

    private fun isolated(block: (String) -> Unit) {
        val name = "test-effect-observation-${UUID.randomUUID()}.db"
        try { block(name) } finally { context.deleteDatabase(name) }
    }
}
