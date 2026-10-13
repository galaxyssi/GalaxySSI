package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Host-event fixtures never stop a real guest, submit a user goal or contact a provider/site. */
@RunWith(AndroidJUnit4::class)
class AgentBrowserRuntimeEventsDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val queue = mutableListOf<() -> Unit>()
    private val events = AgentRuntimeInstanceEventHub(queue::add)
    private fun drain() { while (queue.isNotEmpty()) queue.removeAt(0).invoke() }

    @Test fun idleGuestExitResumesOriginalModelCheckpointWithoutAnotherHostOperation() = runBlocking {
        fixture { store, record ->
            val database = "public-runtime-event-${record.generation}.db"
            val journal = AgentRunEventStore(context, database)
            val request = AgentModelToolLoopRequest(record.sessionId, record.conversationId, record.turnId,
                record.taskId, record.workspaceId, listOf(AgentModelMessage.user("公开测试：等待时 Linux 退出后由模型诊断")),
                callerId = record.callerId, loopId = record.modelLoopId)
            val call = AgentModelToolCall("public-handoff", AgentInteractiveBrowserTools.ACT,
                mapOf("operation" to "request_user_control", "session_id" to record.browserSessionId, "page_id" to record.pageId))
            var toolCalls = 0
            val tools = AgentNativeToolRegistry().register(AgentNativeToolDefinition(
                AgentNativeToolDescriptor(call.toolId, "1.0.0", "Public fixture", "Public fixture", AgentNativeToolLocation.PHONE,
                    AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW),
                AgentNativeToolExecutor {
                    toolCalls++
                    AgentNativeToolExecutionResult.success(mapOf("durable_resume_available" to true,
                        "host_wait_key" to record.key, "host_wait_generation" to record.generation))
                }))
            val resolver = AgentBrowserModelEventWaitResolver(store::load, { it.key == record.key },
                commitObservation = store::markObservationCommitted)
            var wakes = 0
            val watch = AgentBrowserRuntimeWatch(context, events, store = store) {
                wakes++
                assertEquals(it, store.current(record.key, record.generation))
                assertFalse(it.modelObservationCommitted)
            }
            try {
                val waiting = AgentModelToolLoop(AgentModelAdapter { AgentModelResponse(toolCalls = listOf(call)) }, tools,
                    journal = EncryptedAgentModelLoopJournal(context, journal), eventWaitResolver = resolver).run(request)
                assertEquals(AgentModelToolLoopStatus.WAITING_FOR_EVENT, waiting.status)
                watch.watch(record)
                assertTrue(queue.isEmpty())
                val child = ProcessBuilder("/system/bin/sh", "-c", "exit 7").start()
                val monitor = AgentRuntimeProcessMonitor.start(child) {
                    assertEquals(7, it)
                    synchronized(queue) { events.exited(record.runtimeInstanceId) }
                }
                try {
                    monitor.join(5000)
                    assertFalse("The process monitor must report the actual child exit", monitor.isAlive)
                } finally {
                    if (child.isAlive) child.destroyForcibly()
                    child.inputStream.close()
                    child.errorStream.close()
                    child.outputStream.close()
                }
                drain()
                assertEquals(1, wakes)
                val interrupted = store.current(record.key, record.generation)
                assertEquals("browser_runtime_exited", interrupted.interruptionCode)
                var modelCalls = 0
                val result = AgentModelToolLoop(AgentModelAdapter {
                    modelCalls++
                    val metadata = it.messages.last().toolResult!!.nativeResult!!["metadata"] as Map<*, *>
                    val event = metadata["external_event"] as Map<*, *>
                    assertEquals("browser_runtime_exited", event["code"])
                    assertEquals("unknown", event["control_owner"])
                    assertEquals(false, event["authentication_verified"])
                    assertEquals(false, event["goal_terminal"])
                    assertEquals(true, event["requires_observation"])
                    AgentModelResponse("已观察到原 Linux 退出，先诊断再选择恢复方法")
                }, tools, journal = EncryptedAgentModelLoopJournal(context, journal), eventWaitResolver = resolver).run(request)
                assertEquals(AgentModelToolLoopStatus.COMPLETED, result.status)
                assertEquals(1, modelCalls)
                assertEquals(1, toolCalls)
                assertTrue(store.acknowledgeObservedRunWake(interrupted))
                val replay = AgentModelToolLoop(AgentModelAdapter { error("No duplicate provider call") }, tools,
                    journal = EncryptedAgentModelLoopJournal(context, journal), eventWaitResolver = resolver).run(request)
                assertEquals(result.assistantText, replay.assistantText)
            } finally {
                watch.close()
                journal.close()
                context.deleteDatabase(database)
                File(context.noBackupFilesDir, "model-loop-leases/${AgentModelLoopScope.from(request).digest}.lock").delete()
            }
        }
    }

    @Test fun exitBeforeSubscriptionStillWakesThePersistedTask() = fixture { store, record ->
        events.exited(record.runtimeInstanceId)
        var wakes = 0
        AgentBrowserRuntimeWatch(context, events, store = store) { wakes++ }.use { watch ->
            watch.watch(record)
            drain()
            assertEquals(1, wakes)
            assertEquals("browser_runtime_exited", store.current(record.key, record.generation).interruptionCode)
        }
    }

    @Test fun oldQueuedExitCannotInterruptNewGenerationOrNewRuntime() = fixture { store, record ->
        var wakes = 0
        AgentBrowserRuntimeWatch(context, events, store = store) { wakes++ }.use { watch ->
            watch.watch(record)
            val replacement = record.copy(generation = UUID.randomUUID().toString(), runtimeInstanceId = UUID.randomUUID().toString())
            events.started(replacement.runtimeInstanceId)
            store.save(record.copy(state = "returned"))
            store.save(replacement, replaceSettled = true)
            watch.watch(replacement)
            events.exited(record.runtimeInstanceId)
            drain()
            assertEquals(0, wakes)
            assertEquals(replacement, store.current(record.key, replacement.generation))
            events.exited(replacement.runtimeInstanceId)
            drain()
            assertEquals(1, wakes)
            assertEquals("browser_runtime_exited", store.current(record.key, replacement.generation).interruptionCode)
        }
    }

    @Test fun returnedControlCannotBeOverwrittenByAnExit() = fixture { store, record ->
        AgentBrowserRuntimeWatch(context, events, store = store) { error("Returned control must not wake twice") }.use { watch ->
            watch.watch(record)
            val returned = record.copy(state = "returned")
            store.save(returned)
            events.exited(record.runtimeInstanceId)
            drain()
            assertEquals(returned, store.current(record.key, record.generation))
        }
    }

    @Test fun failedWakeKeepsTheInterruptionForStartupReconciliation() = fixture { store, record ->
        AgentBrowserRuntimeWatch(context, events, store = store) { error("Public fixture: enqueue unavailable") }.use { watch ->
            watch.watch(record)
            events.exited(record.runtimeInstanceId)
            drain()
            val interrupted = store.current(record.key, record.generation)
            assertTrue(interrupted.pendingRunWake)
            assertFalse(interrupted.modelObservationCommitted)
            assertTrue(store.pendingWakes().any { it == interrupted })
        }
    }

    @Test fun unboundLegacyRecordDoesNotGuessWhichRuntimeWasLost() = fixture { store, record ->
        val legacy = record.copy(generation = UUID.randomUUID().toString(), runtimeInstanceId = "")
        store.save(record.copy(state = "returned"))
        store.save(legacy, replaceSettled = true)
        AgentBrowserRuntimeWatch(context, events, store = store) { error("No guessed runtime binding") }.use { watch ->
            watch.watch(legacy)
            events.exited(record.runtimeInstanceId)
            drain()
            assertEquals(legacy, store.current(record.key, legacy.generation))
        }
    }

    private inline fun fixture(test: (AgentBrowserUserRequestStore, AgentBrowserUserRequest) -> Unit) {
        val id = UUID.randomUUID().toString()
        val invocation = AgentNativeToolInvocationContext(sessionId = "public-session-$id", conversationId = "public-conversation-$id",
            turnId = "public-task-$id", callerId = "public-agent", attributes = mapOf("workspace_id" to "public-workspace-$id",
                "task_id" to "public-task-$id"))
        val scope = AgentInteractiveBrowserTools.scope(invocation)
        val key = AgentBrowserUserRequest.key(scope, "public-browser-$id")
        val record = AgentBrowserUserRequest(key, id, scope, invocation.sessionId, invocation.conversationId, invocation.turnId,
            invocation.callerId, invocation.attributes.getValue("workspace_id"), "public-browser-$id", "public-page", "public-handoff",
            "active", invocation.attributes.getValue("task_id"), "public-loop-$id", "public-run-$id", "public-owner",
            hostProcessId = AgentProcessIdentity.instanceId, runtimeInstanceId = UUID.randomUUID().toString())
        val directory = File(context.filesDir, "public-runtime-events-$id")
        val store = AgentBrowserUserRequestStore(context, directory)
        events.started(record.runtimeInstanceId)
        try { store.save(record); test(store, record) }
        finally {
            android.util.AtomicFile(File(directory, "$key.enc")).delete()
            directory.delete()
        }
    }
}
