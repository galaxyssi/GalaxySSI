package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Encrypted-journal restore on real hardware, with injected public decisions; not real-model acceptance. */
@RunWith(AndroidJUnit4::class)
class AgentModelHistoryDeviceTest {
    @Test fun encryptedRestoreRecoversFullHistoryWithoutRepeatingWork(): Unit = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val id = UUID.randomUUID().toString()
        val database = "test-model-history-$id.db"
        val proof = "public-history-$id"
        val request = AgentModelToolLoopRequest.forUserMessage("s-$id", "c-$id", "t-$id", "task-$id", "w-$id",
            "\u56de\u67e5\u539f\u59cb\u89c2\u5bdf\u5e76\u7ee7\u7eed\u4efb\u52a1\uff0c\u4e0d\u8981\u91cd\u590d\u6267\u884c\u3002",
            budget = AgentModelToolLoopBudget(enforceCountLimits = false)).copy(loopId = "history-$id")
        val scope = AgentModelLoopScope.from(request)
        var executions = 0
        fun registry() = AgentNativeToolRegistry().register(AgentNativeToolDefinition(AgentNativeToolDescriptor(
            "public.read", "1.0.0", "Public fixture", "Public proof", AgentNativeToolLocation.APPLICATION,
            AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW,
            effect = AgentNativeToolEffect.READ_ONLY), AgentNativeToolExecutor {
            executions++; AgentNativeToolExecutionResult.success(mapOf("proof" to proof))
        }))
        fun call(id: String, tool: String, input: AgentNativeJsonObject = emptyMap()) =
            AgentModelResponse(toolCalls = listOf(AgentModelToolCall(id, tool, input)))
        var store = AgentRunEventStore(context, database)
        try {
            var journal = EncryptedAgentModelLoopJournal(context, store)
            val first = AgentModelHistoryCatalog.prepare(journal, scope, registry())
            try {
                AgentModelToolLoop(AgentModelAdapter { when (it.round) {
                    1 -> call("read", "public.read")
                    2 -> call("history", AgentModelHistoryTools.ID)
                    else -> throw CancellationException("Public process boundary")
                } }, first, journal = journal).run(request)
                fail("Expected interruption")
            } catch (_: CancellationException) { }
            store.close()
            store = AgentRunEventStore(context, database)
            journal = EncryptedAgentModelLoopJournal(context, store)
            val restored = AgentModelHistoryCatalog.prepare(journal, scope, registry())
            val outcome = AgentModelToolLoop(AgentModelAdapter { response ->
                if (response.round == 3) {
                    val record = ((response.messages.last().toolResult!!.output["entries"] as List<*>).single() as Map<*, *>)["record"]
                    call("detail", AgentModelHistoryTools.ID, mapOf("record" to record, "path" to "/observation/output/proof"))
                } else {
                    assertEquals(proof, response.messages.last().toolResult!!.output["text"])
                    AgentModelResponse("\u5df2\u6062\u590d\u539f\u59cb\u89c2\u5bdf\uff0c\u672a\u91cd\u590d\u6267\u884c\u3002")
                }
            }, restored, journal = journal).run(request)
            assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
            assertEquals(1, executions)
            context.openOrCreateDatabase(database, 0, null).use { db ->
                db.rawQuery("SELECT count(*) FROM run_events WHERE encrypted_event LIKE ?", arrayOf("%$proof%")).use {
                    assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0))
                }
            }
        } finally {
            store.close()
            context.deleteDatabase(database)
            java.io.File(context.noBackupFilesDir, "model-loop-leases/${scope.digest}.lock").delete()
        }
    }
}
