package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID
import kotlin.random.Random
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Explicit opt-in: calls a configured real provider with generated public fixture data only. */
@RunWith(AndroidJUnit4::class)
class AgentLivePlannerLoopDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val arguments get() = InstrumentationRegistry.getArguments()

    @Test fun providerInventory() {
        enabled()
        val contacts = readyContacts()
        println("LIVE_PLANNER ready_cloud_count=${contacts.size} models=" +
            contacts.map { it.optString("cloud_model") }.distinct().joinToString(","))
        assertTrue("No ready real cloud provider on this device; do not alter pairing or credentials to pass", contacts.isNotEmpty())
    }

    @Test fun pairedReasoningInventory() {
        enabled()
        val contacts = AppStore.contacts(context)
        val paired = (0 until contacts.length()).mapNotNull { contacts.optJSONObject(it) }.filter {
            val id = it.optString("id")
            val desktop = it.optString("desktop_id")
            !it.optBoolean("deleted", false) && desktop.isNotBlank() &&
                !AppStore.isDesktopDeviceContact(context, id) &&
                GalaxySSILinkProtocol.serverLink(context, desktop)?.paired == true
        }
        println("LIVE_PLANNER paired_reasoning_count=${paired.size} agents=" +
            paired.map { AppStore.agentIdForContact(context, it.optString("id")) }.distinct().joinToString(","))
        assertTrue("No paired Desktop reasoning contact on this device; preserve existing pairing", paired.isNotEmpty())
    }

    @Test fun realProviderReadsWritesAndContinuesTheWorkspace(): Unit = runBlocking {
        enabled()
        val contacts = readyContacts()
        val requested = arguments.getString("live_planner_contact").orEmpty()
        val contact = requireNotNull(if (requested.isBlank()) contacts.firstOrNull() else
            contacts.firstOrNull { it.optString("id") == requested }) { "No configured real cloud provider selected" }
        val root = Files.createTempDirectory(context.filesDir.toPath(), "test-live-planner-")
        val conversation = "live-planner-${UUID.randomUUID()}"
        val proof = UUID.randomUUID().toString()
        val a = Random.nextInt(100, 900)
        val b = Random.nextInt(100, 900)
        try {
            val seed = request(conversation, "initial", "")
            val workspace = AgentWorkspaceScope.id(conversation, seed.runtimeContext.sessionId)
            val files = AgentWorkspaceFileTools(root)
            assertTrue(files.initializeWorkspace(workspace).successful)
            assertTrue(files.writeText(workspace, "source-${UUID.randomUUID()}.json",
                JSONObject().put("a", a).put("b", b).put("proof", proof).toString()).successful)
            val first = run(root, contact, request(conversation, "initial",
                "\u8fd9\u662f\u516c\u5f00\u6d4b\u8bd5\u3002\u5148\u7528\u5de5\u5177\u8bfb\u53d6 input.json\uff0c\u5982\u679c\u4e0d\u5b58\u5728\u5c31\u81ea\u884c\u67e5\u770b\u5f53\u524d\u76ee\u5f55\u627e\u5230\u5b9e\u9645\u6e90\u6587\u4ef6\u3002" +
                "\u5c06\u6587\u4ef6\u4e2d a \u548c b \u76f8\u52a0\uff0c\u7528\u5de5\u5177\u5199\u5165 result.json\uff0c\u4ec5\u5305\u542b total \u548c\u539f\u6837\u590d\u5236\u7684 proof\u3002" +
                "\u518d\u7528\u5de5\u5177\u8bfb\u56de result.json \u9a8c\u8bc1\uff0c\u6700\u540e\u7528\u4e2d\u6587\u56de\u590d\u3002\u5fc5\u987b\u771f\u5b9e\u64cd\u4f5c\u6587\u4ef6\uff0c\u4e0d\u8981\u53ea\u7ed9\u51fa\u8ba1\u5212\u3002"))
            assertResult(files, workspace, "result.json", a + b, proof)
            assertObservedReadAfterWrite(first, "result.json")
            assertTrue("Missing source must be an observed tool failure, not simulated by the harness",
                first.messages.mapNotNull { it.toolResult }.any {
                    it.toolId == AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT && it.status == "failed" &&
                        it.error?.code == "workspace_not_found" && it.error.details["path"] == "input.json"
                })

            // New request and registry, same conversation; no old file contents are sent as context.
            val second = run(root, contact, request(conversation, "replacement-runtime",
                "\u7ee7\u7eed\u516c\u5f00\u6d4b\u8bd5\u3002\u7528\u5de5\u5177\u8bfb\u53d6 result.json\uff0c\u4fdd\u7559 proof\uff0c\u5c06 total \u52a0 7\uff0c" +
                "\u5199\u5165 continued.json\u3002\u518d\u7528\u5de5\u5177\u8bfb\u56de continued.json \u9a8c\u8bc1\uff0c\u6700\u540e\u7528\u4e2d\u6587\u56de\u590d\u3002"))
            assertResult(AgentWorkspaceFileTools(root), workspace, "continued.json", a + b + 7, proof)
            assertObservedReadAfterWrite(second, "continued.json")
            println("LIVE_PLANNER verified_files=2 same_workspace=true real_provider=true")
        } finally {
            require(root.parent == context.filesDir.toPath() && root.fileName.toString().startsWith("test-live-planner-"))
            check(root.toFile().deleteRecursively())
        }
    }

    private suspend fun run(root: Path, contact: JSONObject, source: AgentRequest): AgentModelToolLoopOutcome {
        val definitions = AgentPhoneNativeToolCatalog.definitions(AgentWorkspaceFileTools(root),
            object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult = error("Only fixture file tools")
            }, { source.screen }).filter { it.descriptor.id in setOf(AgentPhoneNativeToolCatalog.WORKSPACE_LIST,
                AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT, AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT) }
        val registry = AgentNativeToolRegistry().registerAll(definitions)
        val catalog = registry.availableCatalog()
        val modelRequest = AgentPlannerToolLoopRequest.create(source, AgentModelPlannerSettings(), listOf(
            AgentModelMessage.system("Use the available tools to complete the user's public fixture task. " +
                "Use workspace_id=current and relative paths. Observe tool failures and correct the plan. " +
                "Never claim to have changed or verified a file without a successful tool result."),
            AgentModelMessage.user(source.goal)), catalog.descriptors,
            eventSink = AgentModelToolLoopEventSink { event ->
                println("LIVE_PLANNER event=${event.type} round=${event.round} tool=${event.details["tool_id"]?.toString().orEmpty()}")
            })
        // Bound paid acceptance probes only; production planner budgets are unchanged.
        val outcome = withTimeout(240_000L) {
            AgentModelToolLoop(CloudModelClient.nativeToolAdapter(context, contact, catalog.descriptors,
                catalog.manifest.sha256), registry).run(modelRequest.copy(budget = modelRequest.budget.copy(
                    maxRounds = 16, maxToolCalls = 24, maxTokens = 16_000, enforceCountLimits = true)))
        }
        println("LIVE_PLANNER model=${contact.optString("cloud_model")} status=${outcome.status} " +
            "rounds=${outcome.usage.rounds} calls=${outcome.usage.toolCallAttempts} elapsed_ms=${outcome.usage.durationMillis}")
        assertEquals(AgentObservationRedaction.redact(outcome.error?.message.orEmpty()).take(600),
            AgentModelToolLoopStatus.COMPLETED, outcome.status)
        return outcome
    }

    private fun assertObservedReadAfterWrite(outcome: AgentModelToolLoopOutcome, path: String) {
        val results = outcome.messages.mapNotNull { it.toolResult }
        val write = results.indexOfFirst { it.toolId == AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT && it.status == "succeeded" }
        assertTrue("Provider must write through the actual file tool", write >= 0)
        assertTrue("Provider must read back its result", results.drop(write + 1).any {
            it.toolId == AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT && it.status == "succeeded" &&
                it.output["path"] == path })
    }

    private fun assertResult(files: AgentWorkspaceFileTools, workspace: String, path: String, total: Int, proof: String) {
        val read = files.readText(workspace, path)
        assertTrue("Missing actual output $path", read is AgentWorkspaceFileResult.Success)
        val output = JSONObject((read as AgentWorkspaceFileResult.Success).value.text)
        assertEquals(total, output.getInt("total"))
        assertEquals(proof, output.getString("proof"))
    }

    private fun readyContacts(): List<JSONObject> {
        val contacts = AppStore.contacts(context)
        return (0 until contacts.length()).mapNotNull { contacts.optJSONObject(it) }.filter {
            !it.optBoolean("deleted", false) && it.optString("delivery_mode") == "cloud_api"
        }.map { AppStore.selectedCloudModelContact(context, it.optString("id")) ?: it }
            .filter(CloudModelCredentialPolicy::isAutoRoutable)
    }

    private fun request(conversation: String, session: String, goal: String): AgentRequest {
        val screen = ScreenContext("Test", pageTitle = "Public fixture")
        return AgentRequest(goal, screen, emptyList(), memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(sessionId = "$conversation-$session", goal = goal, screen = screen,
                permissionMode = PermissionMode.AUTO_LOW_RISK, highRiskGuard = true, memoryCapture = false,
                callableTargets = emptyList(), memories = emptyList(), nativeTools = emptyList()),
            conversationContext = AgentConversationContext(conversation, "", emptyList(), false), executionTurnId = "turn-$conversation")
    }

    private fun enabled() = assumeTrue("Opt in with -e live_planner true", arguments.getString("live_planner") == "true")
}
