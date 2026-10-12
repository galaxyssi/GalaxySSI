package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic host responses only; no real website, provider, user Run or runtime is touched. */
@RunWith(AndroidJUnit4::class)
class AgentBrowserInterruptionDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun sameProcessLossIsPersistedBeforeWakeAndReachesTheOriginalModelCheckpoint() = runBlocking {
        for (code in listOf("session_lost", "browser_closed", "browser_user_handoff_invalid")) fixture { store, record ->
            val database = "public-interruption-${record.generation}.db"
            val events = AgentRunEventStore(context, database)
            val request = AgentModelToolLoopRequest(record.sessionId, record.conversationId, record.turnId,
                record.taskId, record.workspaceId, listOf(AgentModelMessage.user("公开测试：浏览器失效后先观察，不重复提交")),
                callerId = record.callerId, loopId = record.modelLoopId)
            val call = AgentModelToolCall("public-handoff", AgentInteractiveBrowserTools.ACT,
                mapOf("operation" to "request_user_control", "session_id" to record.browserSessionId, "page_id" to record.pageId))
            var toolCalls = 0
            val tools = AgentNativeToolRegistry().register(AgentNativeToolDefinition(
                AgentNativeToolDescriptor(call.toolId, "1.0.0", "Public fixture", "Public fixture",
                    AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
                    AgentNativeToolRisk.LOW), AgentNativeToolExecutor {
                    toolCalls++
                    AgentNativeToolExecutionResult.success(mapOf("durable_resume_available" to true,
                        "host_wait_key" to record.key, "host_wait_generation" to record.generation))
                }))
            val resolver = AgentBrowserModelEventWaitResolver(store::load, { it.key == record.key },
                commitObservation = store::markObservationCommitted)
            try {
                val waiting = AgentModelToolLoop(AgentModelAdapter { AgentModelResponse(toolCalls = listOf(call)) }, tools,
                    journal = EncryptedAgentModelLoopJournal(context, events), eventWaitResolver = resolver).run(request)
                assertEquals(AgentModelToolLoopStatus.WAITING_FOR_EVENT, waiting.status)
                var wakes = 0
                val control = AgentBrowserUserControl(context, execute = { failure(code) }, enqueue = {
                    wakes++
                    assertEquals(it, store.current(record.key, record.generation))
                    assertEquals(AgentProcessIdentity.instanceId, it.hostProcessId)
                    assertFalse(it.modelObservationCommitted)
                })
                assertThrows(AgentBrowserControlFailure::class.java) { control.snapshot(record, 320, 640) }
                assertEquals(1, wakes)
                val interrupted = store.current(record.key, record.generation)
                assertEquals(code, interrupted.interruptionCode)
                var modelCalls = 0
                val result = AgentModelToolLoop(AgentModelAdapter {
                    modelCalls++
                    val metadata = it.messages.last().toolResult!!.nativeResult!!["metadata"] as Map<*, *>
                    val event = metadata["external_event"] as Map<*, *>
                    assertEquals(code, event["code"])
                    assertEquals("unknown", event["control_owner"])
                    assertEquals(false, event["authentication_verified"])
                    assertEquals(false, event["goal_terminal"])
                    assertFalse(event["message"].toString().contains("App host restarted"))
                    AgentModelResponse("已收到浏览器中断观察，先诊断，不重复执行")
                }, tools, journal = EncryptedAgentModelLoopJournal(context, events), eventWaitResolver = resolver).run(request)
                assertEquals(AgentModelToolLoopStatus.COMPLETED, result.status)
                assertEquals(1, modelCalls)
                assertEquals(1, toolCalls)
                assertTrue(store.acknowledgeObservedRunWake(interrupted))
                val replay = AgentModelToolLoop(AgentModelAdapter { error("No repeated provider call") }, tools,
                    journal = EncryptedAgentModelLoopJournal(context, events), eventWaitResolver = resolver).run(request)
                assertEquals(result.assistantText, replay.assistantText)
                assertEquals(1, toolCalls)
            } finally {
                events.close()
                context.deleteDatabase(database)
                File(context.noBackupFilesDir, "model-loop-leases/${AgentModelLoopScope.from(request).digest}.lock").delete()
            }
        }
    }

    @Test fun uncertainReadinessAndTimeoutDoNotEndHumanControl() = fixture { store, record ->
        val control = AgentBrowserUserControl(context, execute = { failure("browser_readiness_unobserved") },
            enqueue = { error("Uncertain readiness must not wake the model as session loss") })
        assertThrows(AgentBrowserControlFailure::class.java) { control.snapshot(record, 320, 640) }
        assertEquals(record, store.current(record.key, record.generation))
        val unobserved = AgentBrowserUserControl(context, execute = { AgentRuntimeExecutionResponse(124, "", "", 60_000) },
            enqueue = { error("Timeout must not invent a lost session") })
        assertThrows(AgentBrowserControlFailure::class.java) { unobserved.snapshot(record, 320, 640) }
        assertEquals(record, store.current(record.key, record.generation))
    }

    @Test fun lateFailureCannotInterruptAReplacementGeneration() = fixture { store, record ->
        val replacement = record.copy(generation = UUID.randomUUID().toString(), handoffId = "public-new-handoff")
        val control = AgentBrowserUserControl(context, execute = {
            store.save(record.copy(state = "returned"))
            store.save(replacement, replaceSettled = true)
            failure("session_lost")
        }, enqueue = { error("A stale failure must not wake the replacement") })
        assertThrows(AgentBrowserControlFailure::class.java) { control.snapshot(record, 320, 640) }
        assertEquals(replacement, store.current(record.key, replacement.generation))
    }

    @Test fun duplicateFailureCannotOverwriteACommittedObservation() = fixture { store, record ->
        val input = mapOf("operation" to "human_control_state")
        val interrupted = store.interruptObserved(record, "session_lost", input)!!
        store.markObservationCommitted(interrupted)
        assertNull(store.interruptObserved(record, "browser_closed", input))
        val latest = store.current(record.key, record.generation)
        assertTrue(latest.modelObservationCommitted)
        assertEquals("session_lost", latest.interruptionCode)
        assertTrue(store.acknowledgeObservedRunWake(interrupted))
    }

    @Test fun failedWakeRemainsDurableForReconciliation() = fixture { store, record ->
        val control = AgentBrowserUserControl(context, execute = { failure("session_lost") },
            enqueue = { error("Public fixture: scheduler unavailable") })
        assertThrows(AgentBrowserControlFailure::class.java) { control.finish(record) }
        val pending = store.current(record.key, record.generation)
        assertTrue(pending.pendingRunWake)
        assertFalse(pending.modelObservationCommitted)
        var wakes = 0
        AgentBrowserUserControl(context, execute = { error("Reconciliation must not repeat a browser action") },
            enqueue = { wakes++; assertEquals(pending, it) }).reconcileReturned(pending)
        assertEquals(1, wakes)
        assertTrue(store.current(record.key, record.generation).pendingRunWake)
    }

    private fun failure(code: String) = AgentRuntimeExecutionResponse(1,
        """{"ok":false,"error":{"code":"$code","details":{"executed":false}}}""", "", 1)

    private inline fun fixture(test: (AgentBrowserUserRequestStore, AgentBrowserUserRequest) -> Unit) {
        val id = UUID.randomUUID().toString()
        val invocation = AgentNativeToolInvocationContext(sessionId = "public-session-$id",
            conversationId = "public-conversation-$id", turnId = "public-task-$id", callerId = "agent-model",
            attributes = mapOf("workspace_id" to "public-workspace-$id", "task_id" to "public-task-$id"))
        val scope = AgentInteractiveBrowserTools.scope(invocation)
        val key = AgentBrowserUserRequest.key(scope, "public-browser-$id")
        val record = AgentBrowserUserRequest(key, id, scope, invocation.sessionId, invocation.conversationId,
            invocation.turnId, invocation.callerId, invocation.attributes.getValue("workspace_id"), "public-browser-$id",
            "public-page", "public-handoff", "active", invocation.attributes.getValue("task_id"), "public-loop-$id",
            "public-run-$id", "public-owner", hostProcessId = AgentProcessIdentity.instanceId)
        val store = AgentBrowserUserRequestStore(context)
        try { store.save(record); test(store, record) }
        finally { android.util.AtomicFile(File(context.filesDir, "browser-user-requests/$key.enc")).delete() }
    }
}
