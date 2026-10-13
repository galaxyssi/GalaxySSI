package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Encrypted persistence with scripted inference and a host-event fixture, not a live website/login. */
@RunWith(AndroidJUnit4::class)
class LocalModelLoopContinuationDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun identity() = UUID.randomUUID().toString().let { id ->
        AgentLocalDispatchIdentity(System.currentTimeMillis(), "local-llm", "public-conversation-$id",
            "public-turn-$id", "public-native-$id", "public-action-$id")
    }

    @Test fun largeRequestReopensFromEncryptedChunkedStorageWithOriginalSelection() = runBlocking {
        val id = identity()
        val database = "public-local-continuation-${UUID.randomUUID()}.db"
        val store = AgentRunEventStore(context, database)
        val prompt = "PUBLIC-LOCAL-REQUEST-MARKER-" + "public evidence ".repeat(6_000)
        val manifest = "a".repeat(64)
        try {
            val original = LocalModelLoopContinuationStore(EncryptedAgentModelLoopJournal(context, store))
                .prepare(id, prompt, "public-selected-profile", true, null, manifest, "Public original system")
            val restored = LocalModelLoopContinuationStore(EncryptedAgentModelLoopJournal(context, store)).restore(id, manifest)
            assertEquals(original, restored)
            assertTrue(restored.prompt.length > 64 * 1024)
            val changedLocale = LocalModelLoopContinuationStore(EncryptedAgentModelLoopJournal(context, store))
                .prepare(id, prompt, "public-selected-profile", true, null, manifest, "Public different locale")
            assertEquals(original, changedLocale)
            for (suffix in listOf("", "-wal", "-shm")) {
                val file = File(context.getDatabasePath(database).path + suffix)
                if (file.exists()) {
                    val bytes = file.readBytes()
                    try { assertFalse(bytes.toString(Charsets.ISO_8859_1).contains("PUBLIC-LOCAL-REQUEST-MARKER-")) }
                    finally { bytes.fill(0) }
                }
            }
        } finally { store.close(); context.deleteDatabase(database); removeLease(id) }
    }

    @Test fun changedSelectionAndForeignDispatchCannotConsumeTheOriginalCheckpoint() = runBlocking {
        val id = identity()
        val database = "public-local-binding-${UUID.randomUUID()}.db"
        val store = AgentRunEventStore(context, database)
        val journal = EncryptedAgentModelLoopJournal(context, store)
        val snapshots = LocalModelLoopContinuationStore(journal)
        val manifest = "a".repeat(64)
        try {
            val saved = snapshots.prepare(id, "Public goal", "public-model-a", false, null, manifest, "Public system")
            try {
                snapshots.prepare(id, "Public goal", "public-model-b", false, null, manifest, "Public system")
                fail("Changed model must not create another executable loop")
            } catch (error: AgentModelLoopRecoveryException) {
                assertEquals("local_model_saved_request_changed", error.message)
            }
            try { snapshots.restore(id.copy(turnId = "public-foreign-turn"), manifest); fail("Foreign turn") }
            catch (error: AgentModelLoopRecoveryException) { assertEquals("local_model_saved_request_missing", error.message) }
            assertEquals(saved, snapshots.restore(id, manifest))
            assertFalse(journal.hasRecords(saved.scope))
        } finally {
            store.close(); context.deleteDatabase(database); removeLease(id)
            removeLease(id.copy(turnId = "public-foreign-turn"))
        }
    }

    @Test fun restoredLocalAdapterWaitsWithoutInferenceThenObservesReturnWithoutRepeatingHandoff() = runBlocking {
        val id = identity()
        val database = "public-local-wait-${UUID.randomUUID()}.db"
        val store = AgentRunEventStore(context, database)
        val journal = EncryptedAgentModelLoopJournal(context, store)
        val directory = File(context.cacheDir, "public-local-browser-${UUID.randomUUID()}")
        val browser = AgentBrowserUserRequestStore(context, directory)
        val scope = LocalModelLoopContinuation.scope(id)
        val invocationContext = AgentNativeToolInvocationContext("public-handoff", scope.session, scope.conversation,
            scope.turn, scope.caller, attributes = mapOf("task_id" to scope.task, "workspace_id" to scope.workspace))
        val browserScope = AgentInteractiveBrowserTools.scope(invocationContext)
        val record = AgentBrowserUserRequest(AgentBrowserUserRequest.key(browserScope, "public-browser"),
            UUID.randomUUID().toString(), browserScope, scope.session, scope.conversation, scope.turn, scope.caller,
            scope.workspace, "public-browser", "public-page", handoffId = "public-handoff", state = "active",
            taskId = scope.task, modelLoopId = scope.loop, runWorkspaceId = id.turnId)
        var handoffs = 0
        var observations = 0
        var rounds = 0
        fun descriptor(tool: String) = AgentNativeToolDescriptor(tool, "1.0.0", "Public browser fixture",
            "Public browser fixture", AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(),
            AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW)
        val registry = AgentNativeToolRegistry().registerAll(listOf(
            AgentNativeToolDefinition(descriptor(AgentInteractiveBrowserTools.ACT), AgentNativeToolExecutor {
                handoffs++
                AgentNativeToolExecutionResult.success(mapOf("durable_resume_available" to true,
                    "host_wait_key" to record.key, "host_wait_generation" to record.generation))
            }),
            AgentNativeToolDefinition(descriptor(AgentInteractiveBrowserTools.OBSERVE), AgentNativeToolExecutor {
                observations++
                AgentNativeToolExecutionResult.success(mapOf("public_fixture_page_observed" to true))
            })))
        val catalog = registry.availableCatalog()
        val resolver = AgentBrowserModelEventWaitResolver(browser::load,
            { it.key == record.key && it.generation == record.generation && it.modelLoopId == scope.loop },
            commitObservation = browser::markObservationCommitted)
        fun local() = LocalModelWebToolSession(context, "public-scripted-profile", false, inference = { _, prompt ->
            val output = when (++rounds) {
                1 -> """{"tool_calls":[{"id":"public-handoff-call","name":"${AgentInteractiveBrowserTools.ACT}","arguments":{"operation":"request_user_control","session_id":"public-browser","page_id":"public-page"}}]}"""
                2 -> {
                    assertTrue(prompt.contains("browser_control_returned"))
                    assertTrue(prompt.contains("authentication_verified"))
                    assertTrue(requireNotNull(browser.load(record.key)).modelObservationCommitted)
                    """{"tool_calls":[{"id":"public-observe-call","name":"${AgentInteractiveBrowserTools.OBSERVE}","arguments":{}}]}"""
                }
                3 -> {
                    assertTrue(prompt.contains("public_fixture_page_observed"))
                    """{"answer":"Public fixture observed after return","tool_calls":[]}"""
                }
                else -> error("Unexpected additional inference")
            }
            LocalModelInferenceResult(text = output, profileId = "public-scripted-profile", backend = "fixture",
                smeAvailable = false, elapsedMillis = 1, promptTokens = 1, generatedTokens = 1)
        })
        try {
            browser.save(record)
            val snapshots = LocalModelLoopContinuationStore(journal)
            val saved = snapshots.prepare(id, "Public browser continuation fixture", "public-scripted-profile",
                false, null, catalog.manifest.sha256, "Public system")
            fun request(savedRequest: LocalModelLoopContinuation) = savedRequest.request(catalog.descriptors,
                AgentNativeToolCancellationToken.NONE, AgentModelToolLoopEventSink.NONE)
            val waiting = AgentModelToolLoop(local().adapter(catalog.descriptors), registry, journal = journal,
                eventWaitResolver = resolver).run(request(saved))
            assertEquals(AgentModelToolLoopStatus.WAITING_FOR_EVENT, waiting.status)
            assertFalse(waiting.isTerminal)
            repeat(2) {
                val restored = LocalModelLoopContinuationStore(EncryptedAgentModelLoopJournal(context, store))
                    .restore(id, catalog.manifest.sha256)
                val pending = AgentModelToolLoop(AgentModelAdapter { error("No model polling while waiting") },
                    registry, journal = journal, eventWaitResolver = resolver).run(request(restored))
                assertEquals(AgentModelToolLoopStatus.WAITING_FOR_EVENT, pending.status)
            }
            assertEquals(1, rounds)
            assertEquals(1, handoffs)
            browser.save(record.copy(state = "returned"))
            val resumed = AgentModelToolLoop(local().adapter(catalog.descriptors), registry, journal = journal,
                eventWaitResolver = resolver).run(request(snapshots.restore(id, catalog.manifest.sha256)))
            assertEquals(AgentModelToolLoopStatus.COMPLETED, resumed.status)
            assertEquals(3, rounds)
            assertEquals(1, handoffs)
            assertEquals(1, observations)
            assertTrue(browser.acknowledgeObservedRunWake(requireNotNull(browser.load(record.key))))
            val replay = AgentModelToolLoop(AgentModelAdapter { error("Completed request must not infer again") },
                registry, journal = journal, eventWaitResolver = resolver).run(request(saved))
            assertEquals(resumed.assistantText, replay.assistantText)
            assertEquals(1, handoffs)
            assertEquals(1, observations)
        } finally {
            store.close(); context.deleteDatabase(database); removeLease(id); directory.deleteRecursively()
        }
    }

    private fun removeLease(id: AgentLocalDispatchIdentity) {
        File(context.noBackupFilesDir, "model-loop-leases/${LocalModelLoopContinuation.scope(id).digest}.lock").delete()
    }
}
