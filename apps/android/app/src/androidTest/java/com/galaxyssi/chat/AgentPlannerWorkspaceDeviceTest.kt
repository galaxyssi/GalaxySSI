package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentPlannerWorkspaceDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun separatePlanningLoopsReadTheSameRealFile() = isolated { root ->
        val source = request()
        val first = run(root, source, write("\u516c\u5f00\u6d4b\u8bd5\u7ed3\u679c"))
        val second = run(root, source.copy(replanReason = "\u6839\u636e\u4e0a\u6b21\u7ed3\u679c\u7ee7\u7eed"), read())
        assertEquals("succeeded", first.tool.status)
        assertEquals("succeeded", second.tool.status)
        assertEquals("\u516c\u5f00\u6d4b\u8bd5\u7ed3\u679c", second.tool.output["text"])
        assertEquals(first.request.workspaceId, second.request.workspaceId)
        assertNotEquals(first.request.loopId, second.request.loopId)
        val firstEvent = first.outcome.events.first { it.type == AgentModelToolLoopEventType.MODEL_REQUESTED }
        val secondEvent = second.outcome.events.first { it.type == AgentModelToolLoopEventType.MODEL_REQUESTED }
        assertNotEquals(AgentModelToolLoopTimelinePolicy.project(firstEvent).dedupeSuffix,
            AgentModelToolLoopTimelinePolicy.project(secondEvent).dedupeSuffix)
    }

    @Test fun anotherRuntimeSessionReopensTheConversationWorkspace() = isolated { root ->
        val source = request()
        assertEquals("succeeded", run(root, source, write("retained file")).tool.status)
        val restarted = source.copy(runtimeContext = source.runtimeContext.copy(sessionId = "restarted-session"),
            executionTurnId = "new-user-turn")
        val result = run(root, restarted, read())
        assertEquals("succeeded", result.tool.status)
        assertEquals("retained file", result.tool.output["text"])
        assertEquals("new-user-turn", result.request.turnId)
    }

    @Test fun anotherConversationCannotReadTheFileEvenWhenTheModelNamesItsWorkspace() = isolated { root ->
        val source = request()
        val first = run(root, source, write("private fixture"))
        assertEquals("succeeded", first.tool.status)
        val other = source.copy(conversationContext = AgentConversationContext("other-${UUID.randomUUID()}", "", emptyList(), false))
        val result = run(root, other, read().copy(arguments = read().arguments +
            ("workspace_id" to first.request.workspaceId)))
        assertNotEquals(first.request.workspaceId, result.request.workspaceId)
        assertNotEquals("succeeded", result.tool.status)
        assertFalse(result.tool.output.toString().contains("private fixture"))
        assertEquals("private fixture", run(root, source, read()).tool.output["text"])
    }

    private data class Result(val request: AgentModelToolLoopRequest, val outcome: AgentModelToolLoopOutcome,
        val tool: AgentModelToolResultContent)

    private fun run(root: Path, source: AgentRequest, call: AgentModelToolCall): Result = runBlocking {
        // Recreate the production file registry for every loop, so a cache cannot satisfy the read.
        val definitions = AgentPhoneNativeToolCatalog.definitions(AgentWorkspaceFileTools(root),
            object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult = error("Not a file tool")
            }, { source.screen }).filter { it.descriptor.id in setOf(
                AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT, AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT) }
        val registry = AgentNativeToolRegistry().registerAll(definitions)
        val loopRequest = AgentPlannerToolLoopRequest.create(source, AgentModelPlannerSettings(),
            listOf(AgentModelMessage.user(source.goal)), registry.descriptors())
        val outcome = AgentModelToolLoop(AgentModelAdapter { model ->
            assertEquals(loopRequest.workspaceId, model.workspaceId)
            assertEquals(source.executionTurnId, model.turnId)
            if (model.round == 1) AgentModelResponse(toolCalls = listOf(call)) else AgentModelResponse("Observed result")
        }, registry).run(loopRequest)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertTrue(outcome.events.all { it.details["model_loop_id"] == loopRequest.loopId })
        Result(loopRequest, outcome, requireNotNull(outcome.messages.last { it.toolResult != null }.toolResult))
    }

    private fun read() = AgentModelToolCall("call-1", AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
        mapOf("workspace_id" to "current", "path" to "notes/result.txt"))
    private fun write(text: String) = AgentModelToolCall("call-1", AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
        mapOf("workspace_id" to "current", "path" to "notes/result.txt", "text" to text, "create_parents" to true))

    private fun request(): AgentRequest {
        val id = "planner-workspace-${UUID.randomUUID()}"
        val goal = "\u5199\u5165\u6587\u4ef6\uff0c\u7136\u540e\u8bfb\u53d6\u5e76\u9a8c\u8bc1\u5185\u5bb9"
        val screen = ScreenContext("Test", pageTitle = "Test")
        return AgentRequest(goal, screen, emptyList(), memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(sessionId = "runtime-$id", goal = goal, screen = screen,
                permissionMode = PermissionMode.AUTO_LOW_RISK, highRiskGuard = true, memoryCapture = false,
                callableTargets = emptyList(), memories = emptyList(), nativeTools = emptyList()),
            conversationContext = AgentConversationContext(id, "", emptyList(), false), executionTurnId = "turn-$id")
    }

    private fun isolated(block: (Path) -> Unit) {
        val root = Files.createTempDirectory(context.filesDir.toPath(), "test-planner-workspace-")
        try { block(root) } finally {
            require(root.parent == context.filesDir.toPath() && root.fileName.toString().startsWith("test-planner-workspace-"))
            check(root.toFile().deleteRecursively())
        }
    }
}
