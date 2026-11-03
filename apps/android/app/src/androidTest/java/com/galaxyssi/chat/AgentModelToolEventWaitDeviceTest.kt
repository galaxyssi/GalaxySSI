package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Isolated framework fixture: no real provider, user goal, login or task is created. */
@RunWith(AndroidJUnit4::class)
class AgentModelToolEventWaitDeviceTest {
    @Test fun encryptedLoopReopensDormantAndConsumesItsReturnOnceWithoutRepeatingTheTool() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val id = UUID.randomUUID().toString()
        val database = "public-model-event-wait-$id.db"
        val store = AgentRunEventStore(context, database)
        val request = AgentModelToolLoopRequest("public-session-$id", "public-conversation-$id", "public-turn-$id",
            "public-task-$id", "public-workspace-$id", listOf(AgentModelMessage.user("Public event fixture")), loopId = "fixture")
        val descriptor = AgentNativeToolDescriptor("public.test.event", "1.0.0", "Public fixture", "Public fixture",
            AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
            AgentNativeToolRisk.LOW)
        var tools = 0
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(descriptor,
            AgentNativeToolExecutor { tools++; AgentNativeToolExecutionResult.success(mapOf("fixture" to "original")) }))
        val pending = object : AgentModelToolEventWaitResolver {
            override fun supports(toolId: String) = toolId == descriptor.id
            override fun resolve(request: AgentModelToolLoopRequest, call: AgentModelToolCall,
                result: AgentNativeToolResult) = AgentModelToolEventWait.Pending(id, "Waiting for public fixture event")
        }
        try {
            val first = AgentModelToolLoop(AgentModelAdapter {
                AgentModelResponse(toolCalls = listOf(AgentModelToolCall("public-call", descriptor.id)))
            }, registry, journal = EncryptedAgentModelLoopJournal(context, store), eventWaitResolver = pending).run(request)
            assertEquals(AgentModelToolLoopStatus.WAITING_FOR_EVENT, first.status)
            assertFalse(first.isTerminal)
            repeat(3) {
                val restored = AgentModelToolLoop(AgentModelAdapter { error("Pending event must not call a model") }, registry,
                    journal = EncryptedAgentModelLoopJournal(context, store), eventWaitResolver = pending).run(request)
                assertEquals(AgentModelToolLoopStatus.WAITING_FOR_EVENT, restored.status)
            }
            val returned = object : AgentModelToolEventWaitResolver {
                override fun supports(toolId: String) = toolId == descriptor.id
                override fun resolve(request: AgentModelToolLoopRequest, call: AgentModelToolCall,
                    result: AgentNativeToolResult) = AgentModelToolEventWait.Resolved(result.copy(metadata =
                        result.metadata + mapOf("external_event" to mapOf("event_id" to id, "returned" to true))))
            }
            val resumed = AgentModelToolLoop(AgentModelAdapter {
                assertEquals(2, it.round)
                AgentModelResponse("Public fixture observed")
            }, registry, journal = EncryptedAgentModelLoopJournal(context, store), eventWaitResolver = returned).run(request)
            assertEquals(AgentModelToolLoopStatus.COMPLETED, resumed.status)
            val completed = AgentModelToolLoop(AgentModelAdapter { error("No duplicate model request") }, registry,
                journal = EncryptedAgentModelLoopJournal(context, store), eventWaitResolver = pending).run(request)
            assertEquals(resumed.assistantText, completed.assistantText)
            assertEquals(1, tools)
        } finally {
            store.close()
            context.deleteDatabase(database)
            File(context.noBackupFilesDir, "model-loop-leases/${AgentModelLoopScope.from(request).digest}.lock").delete()
        }
    }
}
