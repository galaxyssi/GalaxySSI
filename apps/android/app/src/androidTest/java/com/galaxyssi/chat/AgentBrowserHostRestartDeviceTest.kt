package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Run seed and recover in separate instrumentation processes. No real goal, provider or website is used. */
@RunWith(AndroidJUnit4::class)
class AgentBrowserHostRestartDeviceTest {
    @Test fun encryptedWaitResumesInANewProcessWithoutRepeatingTheHandoff() = runBlocking {
        val arguments = InstrumentationRegistry.getArguments()
        val phase = arguments.getString("host_restart_phase")
        assumeTrue(phase in setOf("seed", "recover"))
        val id = arguments.getString("host_restart_fixture").orEmpty()
        require(id.matches(Regex("[a-f0-9-]{36}")))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.filesDir, "public-browser-host-restart-$id")
        val database = "public-browser-host-restart-$id.db"
        val requests = AgentBrowserUserRequestStore(context, directory)
        val events = AgentRunEventStore(context, database)
        val request = AgentModelToolLoopRequest("public-session-$id", "public-conversation-$id", "public-turn-$id",
            "public-task-$id", "public-workspace-$id", listOf(AgentModelMessage.user("公开框架测试：等待浏览器控制事件后继续观察")),
            loopId = "public-host-restart")
        val invocationContext = AgentNativeToolInvocationContext(sessionId = request.sessionId,
            conversationId = request.conversationId, turnId = request.turnId, callerId = request.callerId,
            attributes = mapOf("workspace_id" to request.workspaceId, "task_id" to request.taskId))
        val scope = AgentInteractiveBrowserTools.scope(invocationContext)
        val key = AgentBrowserUserRequest.key(scope, "public-browser")
        val record = AgentBrowserUserRequest(key, "generation-$id", scope, request.sessionId,
            request.conversationId, request.turnId, request.callerId, request.workspaceId, "public-browser", "public-page",
            "public-handoff", "active", request.taskId, request.loopId, "public-fixture-run", "public-fixture-owner",
            runPlanningBinding = "public-fixture-binding", hostProcessId = AgentProcessIdentity.instanceId)
        val call = AgentModelToolCall("public-handoff-call", AgentInteractiveBrowserTools.ACT,
            mapOf("operation" to "request_user_control", "session_id" to record.browserSessionId, "page_id" to record.pageId))
        val tools = AgentNativeToolRegistry().register(AgentNativeToolDefinition(
            AgentNativeToolDescriptor(call.toolId, "1.0.0", "Public fixture", "Public fixture",
                AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
                AgentNativeToolRisk.LOW), AgentNativeToolExecutor {
                check(phase == "seed") { "The committed handoff must not be executed again" }
                check(record.sameOwner(it.context))
                requests.save(record)
                AgentNativeToolExecutionResult.success(mapOf("durable_resume_available" to true,
                    "host_wait_key" to key, "host_wait_generation" to record.generation))
            }))
        val resolver = AgentBrowserModelEventWaitResolver(requests::load, { candidate ->
            candidate.key == key && candidate.generation == record.generation && candidate.runWorkspaceId == record.runWorkspaceId
        }, commitObservation = requests::markObservationCommitted)
        var cleanup = false
        try {
            if (phase == "seed") {
                val result = AgentModelToolLoop(AgentModelAdapter { AgentModelResponse(toolCalls = listOf(call)) }, tools,
                    journal = EncryptedAgentModelLoopJournal(context, events), eventWaitResolver = resolver).run(request)
                assertEquals(AgentModelToolLoopStatus.WAITING_FOR_EVENT, result.status)
                assertEquals(record, requests.current(key, record.generation))
                assertTrue(requests.pendingWakes().none())
                println("PUBLIC_BROWSER_HOST_RESTART phase=seed pid=${android.os.Process.myPid()} waiting=true")
            } else {
                val previous = requests.current(key, record.generation)
                assertNotEquals("A new App process is required", previous.hostProcessId, AgentProcessIdentity.instanceId)
                val interruption = requests.pendingWakes().single()
                assertEquals("interrupted", interruption.state)
                assertEquals(previous.generation, interruption.generation)
                assertEquals(previous.hostProcessId, interruption.hostProcessId)
                val result = AgentModelToolLoop(AgentModelAdapter {
                    assertEquals(2, it.round)
                    val metadata = it.messages.last().toolResult!!.nativeResult!!["metadata"] as Map<*, *>
                    val observation = metadata["external_event"] as Map<*, *>
                    assertEquals("browser_control_interrupted", observation["kind"])
                    assertEquals("browser_host_restarted", observation["code"])
                    assertEquals("unknown", observation["control_owner"])
                    assertEquals(false, observation["authentication_verified"])
                    assertEquals(false, observation["goal_terminal"])
                    assertEquals(true, observation["requires_observation"])
                    AgentModelResponse("已观察到宿主重启，需要先诊断浏览器实际状态")
                }, tools, journal = EncryptedAgentModelLoopJournal(context, events), eventWaitResolver = resolver).run(request)
                assertEquals(AgentModelToolLoopStatus.COMPLETED, result.status)
                assertTrue(requests.current(key, record.generation).modelObservationCommitted)
                assertTrue(requests.acknowledgeObservedRunWake(interruption))
                assertFalse(requests.current(key, record.generation).pendingRunWake)
                android.util.AtomicFile(File(directory, "$key.enc")).delete()
                val replay = AgentModelToolLoop(AgentModelAdapter { error("No duplicate provider request") }, tools,
                    journal = EncryptedAgentModelLoopJournal(context, events), eventWaitResolver = resolver).run(request)
                assertEquals(result.assistantText, replay.assistantText)
                cleanup = true
                println("PUBLIC_BROWSER_HOST_RESTART phase=recover pid=${android.os.Process.myPid()} new_process=true same_checkpoint=true handoff_replayed=false")
            }
        } finally {
            events.close()
            if (cleanup) {
                context.deleteDatabase(database)
                directory.delete()
                File(context.noBackupFilesDir, "model-loop-leases/${AgentModelLoopScope.from(request).digest}.lock").delete()
            }
        }
    }
}
