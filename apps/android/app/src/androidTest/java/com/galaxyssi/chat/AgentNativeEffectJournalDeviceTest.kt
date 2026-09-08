package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.Assume.assumeTrue
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentNativeEffectJournalDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val key = AgentNativeToolReplayKey("phone.test.effect", "1.0.0", "effect-1",
        AgentNativeEffectScope("device", "session", "conversation", "goal", "task", "turn"))
    private val input = AgentNativeJsonCodec.sha256(emptyMap<String, Any>())

    @Test fun claimAndSuccessfulOutcomeSurviveDatabaseReopen() = isolated { name ->
        val ledger = AgentRunEventStore(context, name)
        val journal = EncryptedAgentNativeToolReplayStore(ledger)
        assertTrue(journal.claim(key, input, "first").acquired)
        journal.complete(key, "first", result("first"))
        ledger.close()
        val reopened = AgentRunEventStore(context, name)
        try {
            val restored = EncryptedAgentNativeToolReplayStore(reopened)
            val claim = restored.claim(key, input, "second")
            assertFalse(claim.acquired)
            assertEquals("first", claim.result?.receipt?.invocationId)
            assertEquals(result("first").toJson(), restored.get(key)?.toJson())
        } finally { reopened.close() }
    }

    @Test fun ownerWithoutOutcomeCannotBeStolenAfterReopen() = isolated { name ->
        val original = AgentRunEventStore(context, name)
        assertTrue(EncryptedAgentNativeToolReplayStore(original).claim(key, input, "old-process").acquired)
        original.close()
        val reopened = AgentRunEventStore(context, name)
        try {
            val claim = EncryptedAgentNativeToolReplayStore(reopened).claim(key, input, "new-process")
            assertFalse(claim.acquired)
            assertNull(claim.result)
            assertEquals("old-process", claim.invocationId)
        } finally { reopened.close() }
    }

    @Test fun concurrentStoreInstancesHaveOneOwner() = isolated { name ->
        val ledger = AgentRunEventStore(context, name)
        val workers = Executors.newFixedThreadPool(4)
        try {
            val futures = (1..8).map { index -> workers.submit<AgentNativeEffectClaim> {
                EncryptedAgentNativeToolReplayStore(AgentRunEventStore(context, name)).claim(key, input, "owner-$index")
            } }
            val results = futures.map { it.get(30, TimeUnit.SECONDS) }
            assertEquals(1, results.count { it.acquired })
            assertEquals(1, results.map { it.invocationId }.toSet().size)
        } finally {
            workers.shutdownNow()
            assertTrue(workers.awaitTermination(30, TimeUnit.SECONDS))
            ledger.close()
        }
    }

    @Test fun largeMultilingualOutcomeIsChunkedAndEncrypted() = isolated { name ->
        val ledger = AgentRunEventStore(context, name)
        try {
            val journal = EncryptedAgentNativeToolReplayStore(ledger)
            val text = ("\u6d4b\u8bd5\u7ed3\u679c\uD83D\uDE80" + "x".repeat(17)).repeat(120_000)
            val large = result("large", mapOf("text" to text))
            journal.claim(key, input, "large")
            journal.complete(key, "large", large)
            assertEquals(text, journal.get(key)?.output?.get("text"))
            context.openOrCreateDatabase(name, 0, null).use { db ->
                db.rawQuery("SELECT MAX(length(encrypted_event)),count(*) FROM run_events", null).use {
                    assertTrue(it.moveToFirst())
                    assertTrue(it.getInt(0) < 512 * 1024)
                    assertTrue(it.getInt(1) > 2)
                }
                db.rawQuery("SELECT count(*) FROM run_events WHERE encrypted_event LIKE '%native-effect-private-result-marker%'", null).use {
                    assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0))
                }
            }
        } finally { ledger.close() }
    }

    @Test fun lateOwnerCannotOverwriteAnOutcome() = isolated { name ->
        val ledger = AgentRunEventStore(context, name)
        try {
            val journal = EncryptedAgentNativeToolReplayStore(ledger)
            journal.claim(key, input, "owner")
            assertThrows(IllegalArgumentException::class.java) { journal.complete(key, "stale", result("stale")) }
            journal.complete(key, "owner", result("owner"))
            assertThrows(IllegalArgumentException::class.java) {
                journal.complete(key, "owner", result("owner", mapOf("changed" to true)))
            }
            assertEquals(result("owner").toJson(), journal.get(key)?.toJson())
        } finally { ledger.close() }
    }

    @Test fun clearDoesNotRemoveOtherRunNamespaces() = isolated { name ->
        val ledger = AgentRunEventStore(context, name)
        try {
            ledger.appendNext(AgentRunControlEvent(eventId = "other", runId = "other", taskId = "other",
                conversationId = "other", messageId = "",
                agentId = "other", deviceId = "local", sequence = 0, type = AgentRunControlEventType.RUN_STARTED))
            val journal = EncryptedAgentNativeToolReplayStore(ledger)
            journal.claim(key, input, "owner")
            journal.complete(key, "owner", result("owner"))
            journal.clear()
            assertNull(journal.get(key))
            assertNotNull(ledger.latestEvent("other"))
        } finally { ledger.close() }
    }

    @Test fun failedTerminalCommitRollsBackEveryResultChunk() = isolated { name ->
        val ledger = AgentRunEventStore(context, name)
        try {
            val journal = EncryptedAgentNativeToolReplayStore(ledger)
            journal.claim(key, input, "owner")
            context.openOrCreateDatabase(name, 0, null).use { db ->
                db.execSQL("CREATE TRIGGER reject_effect_result BEFORE INSERT ON run_events " +
                    "WHEN NEW.event_type='RUN_COMPLETED' BEGIN SELECT RAISE(ABORT, 'test disk failure'); END")
            }
            assertThrows(Exception::class.java) { journal.complete(key, "owner", result("owner")) }
            assertEquals(1, ledger.eventsPage(EncryptedAgentNativeToolReplayStore.runId(key)).size)
            val claim = journal.claim(key, input, "later")
            assertFalse(claim.acquired)
            assertNull(claim.result)
        } finally { ledger.close() }
    }

    @Test fun firstReceiptRemainsAfterTwoThousandLaterEffects() = isolated { name ->
        val ledger = AgentRunEventStore(context, name)
        try {
            val journal = EncryptedAgentNativeToolReplayStore(ledger)
            repeat(2_005) { index ->
                journal.put(key.copy(idempotencyKey = "key-$index"), result("owner-$index", effectKey = "key-$index"))
            }
            assertEquals("owner-0", journal.get(key.copy(idempotencyKey = "key-0"))?.receipt?.invocationId)
        } finally { ledger.close() }
    }

    @Test fun seedRestartEvidence() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("native_effect_restart") == "true")
        val ledger = AgentRunEventStore(context, RESTART_DB)
        try {
            check(ledger.latestEvent(EncryptedAgentNativeToolReplayStore.runId(key)) == null) { "Do not seed this restart case twice" }
            val journal = EncryptedAgentNativeToolReplayStore(ledger)
            journal.claim(key, input, "process-before-stop")
            journal.complete(key, "process-before-stop", result("process-before-stop"))
            journal.claim(key.copy(idempotencyKey = "uncertain"), input, "interrupted-effect")
            context.getFileStreamPath(RESTART_FILE).writeText("1")
        } finally { ledger.close() }
    }

    @Test fun recoverRestartEvidenceWithoutAnotherEffect() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("native_effect_restart") == "true")
        val ledger = AgentRunEventStore(context, RESTART_DB)
        try {
            val descriptor = AgentNativeToolDescriptor(key.toolId, key.toolVersion, "Test effect", "Test effect",
                AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
                AgentNativeToolRisk.LOW, setOf("phone.test"), idempotency = AgentNativeToolIdempotency.IDEMPOTENCY_KEY_REQUIRED)
            val runtime = AgentNativeToolRegistry(replayStore = EncryptedAgentNativeToolReplayStore(ledger)).register(
                AgentNativeToolDefinition(descriptor, AgentNativeToolExecutor { error("Restart must not repeat this effect") }))
            val invocation = AgentNativeToolInvocationContext(sessionId = "session", conversationId = "conversation",
                turnId = "turn", idempotencyKey = key.idempotencyKey,
                attributes = mapOf("client_route_id" to "device", "goal_id" to "goal", "task_id" to "task"))
            val replay = runtime.invoke(key.toolId, emptyMap(), invocation)
            assertTrue(replay.toJson(), replay.receipt.replayed)
            val uncertain = runtime.invoke(key.toolId, emptyMap(), invocation.copy(idempotencyKey = "uncertain"))
            assertEquals("effect_outcome_unknown", uncertain.error?.code)
            assertEquals("1", context.getFileStreamPath(RESTART_FILE).readText())
        } finally { ledger.close() }
        context.deleteDatabase(RESTART_DB)
        context.getFileStreamPath(RESTART_FILE).delete()
    }

    @Test fun crashAfterExecutorWriteBeforeOutcomeCommit() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("native_effect_crash") == "true")
        val ledger = AgentRunEventStore(context, CRASH_DB)
        check(ledger.latestEvent(EncryptedAgentNativeToolReplayStore.runId(key)) == null) { "Do not repeat crash setup" }
        val runtime = crashRuntime(EncryptedAgentNativeToolReplayStore(ledger)) {
            val counter = context.getFileStreamPath(CRASH_FILE)
            check(!counter.exists()) { "Previous crash evidence must be inspected before a new test" }
            counter.writeText("1")
            android.os.Process.killProcess(android.os.Process.myPid())
            error("The test process must terminate before returning an outcome")
        }
        runtime.invoke(key.toolId, emptyMap(), crashContext())
        fail("The test executor did not terminate the process")
    }

    @Test fun actualProcessDeathDoesNotRepeatExecutorWrite() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("native_effect_crash") == "true")
        val ledger = AgentRunEventStore(context, CRASH_DB)
        try {
            val replay = crashRuntime(EncryptedAgentNativeToolReplayStore(ledger)) {
                context.getFileStreamPath(CRASH_FILE).appendText("2")
                error("The interrupted effect must not be executed again")
            }.invoke(key.toolId, emptyMap(), crashContext())
            assertEquals("effect_outcome_unknown", replay.error?.code)
            assertEquals("1", context.getFileStreamPath(CRASH_FILE).readText())
        } finally { ledger.close() }
        context.deleteDatabase(CRASH_DB)
        context.getFileStreamPath(CRASH_FILE).delete()
    }

    private fun crashContext() = AgentNativeToolInvocationContext(sessionId = "session", conversationId = "conversation",
        turnId = "turn", idempotencyKey = key.idempotencyKey,
        attributes = mapOf("client_route_id" to "device", "goal_id" to "goal", "task_id" to "task"))

    private fun crashRuntime(store: AgentNativeToolReplayStore, executor: AgentNativeToolExecutor) =
        AgentNativeToolRegistry(replayStore = store).register(AgentNativeToolDefinition(
            AgentNativeToolDescriptor(key.toolId, key.toolVersion, "Test effect", "Test effect",
                AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
                AgentNativeToolRisk.LOW, setOf("phone.test"), idempotency = AgentNativeToolIdempotency.IDEMPOTENCY_KEY_REQUIRED), executor))

    @Test fun migratedUnscopedReceiptCannotLeakIntoAnotherConversation() = isolated { name ->
        val legacyName = "legacy-$name"
        val legacy = AgentEncryptedDatabase(context, legacyName)
        legacy.writeString("entries", JSONArray().put(JSONObject()
            .put("tool_id", key.toolId).put("tool_version", key.toolVersion)
            .put("idempotency_key", key.idempotencyKey).put("saved_at_millis", 1L)
            .put("result", JSONObject(result("old").toJson()))).toString())
        val ledger = AgentRunEventStore(context, name)
        try {
            val journal = EncryptedAgentNativeToolReplayStore(ledger, LegacyAgentNativeToolReplayReader(context, legacyName))
            assertEquals("old", journal.get(key.copy(scope = AgentNativeEffectScope()))?.receipt?.invocationId)
            val error = assertThrows(IllegalStateException::class.java) { journal.get(key) }
            assertTrue(error.message.orEmpty().startsWith("legacy_effect_scope_unverified"))
            assertTrue(legacy.contains("entries"))
        } finally { ledger.close(); legacy.clear() }
    }

    private fun result(owner: String, output: Map<String, Any> = mapOf("saved" to true), effectKey: String = key.idempotencyKey) = AgentNativeToolResult(
        status = AgentNativeToolResultStatus.SUCCEEDED, output = output,
        message = "native-effect-private-result-marker", metadata = emptyMap(), error = null, verification = null,
        receipt = AgentNativeToolReceipt(owner, effectKey, 1, 2, 1,
            AgentNativeToolResultStatus.SUCCEEDED, input, AgentNativeJsonCodec.sha256(output)),
        provenance = AgentNativeToolProvenance(key.toolId, key.toolVersion, AgentNativeToolLocation.PHONE,
            "test", AgentNativeToolRegistry.CONTRACT_VERSION)
    )

    private fun isolated(block: (String) -> Unit) {
        val name = "test-native-effects-${UUID.randomUUID()}.db"
        try { block(name) } finally { context.deleteDatabase(name) }
    }

    private companion object {
        const val RESTART_DB = "test-native-effect-restart.db"
        const val RESTART_FILE = "test-native-effect-restart-count.txt"
        const val CRASH_DB = "test-native-effect-crash.db"
        const val CRASH_FILE = "test-native-effect-crash-count.txt"
    }
}
