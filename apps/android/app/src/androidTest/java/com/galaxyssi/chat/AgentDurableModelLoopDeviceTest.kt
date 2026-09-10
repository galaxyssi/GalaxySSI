package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.FileOutputStream
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentDurableModelLoopDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val descriptor = AgentNativeToolDescriptor("test.loop.write", "1.0.0", "Write", "Write test marker",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
        AgentNativeToolRisk.LOW, setOf("test"), idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT)

    @Test fun largeModelResponseReopensFromEncryptedBoundedRecords() = runBlocking {
        val name = "test-model-loop-${UUID.randomUUID()}"
        val db = "$name.db"
        val ledger = AgentRunEventStore(context, db)
        val answer = "private-loop-response-marker" + "\u6d4b\u8bd5\uD83D\uDE80".repeat(35_000)
        try {
            val first = AgentModelToolLoop(AgentModelAdapter { AgentModelResponse(answer) }, registry(ledger),
                journal = EncryptedAgentModelLoopJournal(context, ledger)).run(request(name))
            assertEquals(answer, first.assistantText)
        } finally { ledger.close() }
        val reopened = AgentRunEventStore(context, db)
        try {
            val next = AgentModelToolLoop(AgentModelAdapter { error("Must recover the saved model response") },
                registry(reopened), journal = EncryptedAgentModelLoopJournal(context, reopened)).run(request(name))
            assertEquals(answer, next.assistantText)
            context.openOrCreateDatabase(db, 0, null).use { raw ->
                raw.rawQuery("SELECT MAX(length(encrypted_event)),count(*) FROM run_events", null).use {
                    assertTrue(it.moveToFirst()); assertTrue(it.getInt(0) < 512 * 1024); assertTrue(it.getInt(1) > 3)
                }
                raw.rawQuery("SELECT count(*) FROM run_events WHERE encrypted_event LIKE '%private-loop-response-marker%'", null).use {
                    assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0))
                }
            }
        } finally { reopened.close(); context.deleteDatabase(db) }
    }

    @Test fun separateJournalInstancesCannotOwnTheSameLiveLoop() = runBlocking {
        val name = "test-model-lease-${UUID.randomUUID()}"
        val ledger = AgentRunEventStore(context, "$name.db")
        try {
            val first = EncryptedAgentModelLoopJournal(context, ledger)
            val second = EncryptedAgentModelLoopJournal(context, ledger)
            val scope = AgentModelLoopScope.from(request(name))
            first.withLease(scope) {
                try { second.withLease(scope) { fail("Duplicate live owner") }; fail("Expected busy loop") }
                catch (error: AgentModelLoopRecoveryException) { assertEquals("model_loop_busy", error.message) }
            }
            second.withLease(scope) { assertNull(it.read("missing")) }
        } finally { ledger.close(); context.deleteDatabase("$name.db") }
    }

    @Test fun unreadableCommitIsNotTreatedAsANewLoop() = rejectCorruption(2)

    @Test fun unreadableChunkIsNotTreatedAsANewLoop() = rejectCorruption(1)

    private fun rejectCorruption(sequence: Int) = runBlocking {
        val name = "test-model-corruption-${UUID.randomUUID()}"
        val db = "$name.db"
        val ledger = AgentRunEventStore(context, db)
        try {
            AgentModelToolLoop(AgentModelAdapter { AgentModelResponse("Stored answer") }, registry(ledger),
                journal = EncryptedAgentModelLoopJournal(context, ledger)).run(request(name))
        } finally { ledger.close() }
        context.openOrCreateDatabase(db, 0, null).use { raw ->
            raw.execSQL("UPDATE run_events SET encrypted_event = ? WHERE sequence = ?", arrayOf("invalid-ciphertext", sequence))
        }
        val reopened = AgentRunEventStore(context, db)
        try {
            val journal = EncryptedAgentModelLoopJournal(context, reopened)
            assertTrue(journal.hasRecords(AgentModelLoopScope.from(request(name))))
            var modelCalls = 0
            try {
                AgentModelToolLoop(AgentModelAdapter { modelCalls++; AgentModelResponse("Must not replace evidence") },
                    registry(reopened) { error("Must not execute") }, journal = journal).run(request(name))
                fail("Corrupt evidence must require recovery")
            } catch (error: AgentModelLoopRecoveryException) {
                assertEquals("model_loop_journal_unavailable", error.message)
            }
            assertEquals(0, modelCalls)
        } finally { reopened.close(); context.deleteDatabase(db) }
    }

    @Test fun stopAfterACommittedObservationBeforeTheNextModelReply() = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("model_loop_prepare") == "true")
        val name = caseName()
        check(!context.getDatabasePath("$name.db").exists() && !context.getFileStreamPath("$name.pid").exists()) {
            "Inspect the existing case; do not prepare it again"
        }
        val ledger = AgentRunEventStore(context, "$name.db")
        write("$name.pid", android.os.Process.myPid().toString())
        AgentModelToolLoop(AgentModelAdapter {
            if (it.round == 1) {
                write("$name.model", "one-request")
                AgentModelResponse("\u5148\u4fdd\u5b58\u6d4b\u8bd5\u6807\u8bb0", listOf(AgentModelToolCall("write-1", descriptor.id)))
            } else {
                assertEquals(true, it.messages.last().toolResult?.output?.get("saved"))
                android.os.Process.killProcess(android.os.Process.myPid())
                error("Process must terminate before the next model reply")
            }
        }, registry(ledger) {
            write("$name.effect", "one-write")
            AgentNativeToolExecutionResult.success(mapOf("saved" to true))
        }, journal = EncryptedAgentModelLoopJournal(context, ledger)).run(request(name))
        fail("Expected deliberate process death")
    }

    @Test fun resumeTheModelWithItsExistingObservationAfterProcessDeath() = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("model_loop_verify") == "true")
        val name = caseName()
        check(context.getDatabasePath("$name.db").exists())
        assertNotEquals(context.getFileStreamPath("$name.pid").readText(), android.os.Process.myPid().toString())
        val ledger = AgentRunEventStore(context, "$name.db")
        try {
            var calls = 0
            val events = mutableListOf<AgentModelToolLoopEvent>()
            val journal = EncryptedAgentModelLoopJournal(context, ledger)
            val runtime = registry(ledger) { error("Do not repeat a committed tool") }
            val resumed = AgentModelToolLoop(AgentModelAdapter {
                calls++
                assertEquals(2, it.round)
                assertEquals(true, it.messages.last().toolResult?.output?.get("saved"))
                AgentModelResponse("\u5df2\u6062\u590d\u5e76\u5b8c\u6210")
            }, runtime, journal = journal).run(request(name).copy(eventSink = AgentModelToolLoopEventSink { events += it }))
            assertEquals(AgentModelToolLoopStatus.COMPLETED, resumed.status)
            assertEquals(1, calls)
            assertTrue(events.none { it.type == AgentModelToolLoopEventType.TOOL_STARTED })
            assertTrue(events.filter { it.type == AgentModelToolLoopEventType.MODEL_REQUESTED }.all { it.round == 2 })
            val completed = AgentModelToolLoop(AgentModelAdapter { error("Completed model must not be requested again") },
                runtime, journal = journal).run(request(name))
            assertEquals(resumed.assistantText, completed.assistantText)
            assertEquals("one-request", context.getFileStreamPath("$name.model").readText())
            assertEquals("one-write", context.getFileStreamPath("$name.effect").readText())
            write("$name.verified", android.os.Process.myPid().toString())
        } finally { ledger.close() }
    }

    private fun request(name: String) = AgentModelToolLoopRequest(name, name, "$name-turn", "$name-task", name,
        listOf(AgentModelMessage.user("\u4fdd\u5b58\u4e00\u4e2a\u6d4b\u8bd5\u6807\u8bb0\uff0c\u518d\u6839\u636e\u89c2\u5bdf\u5b8c\u6210\u4efb\u52a1")), loopId = "revision-1")
    private fun registry(ledger: AgentRunEventStore, execute: () -> AgentNativeToolExecutionResult = {
        AgentNativeToolExecutionResult.success()
    }) = AgentNativeToolRegistry(replayStore = EncryptedAgentNativeToolReplayStore(ledger)).register(
        AgentNativeToolDefinition(descriptor, AgentNativeToolExecutor { execute() }))
    private fun write(name: String, text: String) = FileOutputStream(context.getFileStreamPath(name)).use {
        it.write(text.toByteArray()); it.fd.sync()
    }
    private fun caseName(): String {
        val id = InstrumentationRegistry.getArguments().getString("model_loop_case").orEmpty()
        require(id.matches(Regex("[A-Za-z0-9-]{1,64}")))
        return "test-model-loop-$id"
    }
}
