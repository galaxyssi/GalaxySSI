package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Scripted inference exercises the real local adapter, not real-model intelligence or speed. */
@RunWith(AndroidJUnit4::class)
class LocalModelAgentToolsDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun productionLocalRegistryDisclosesPhoneToolsAndCanInspectTheirFullContracts() = runBlocking {
        val registry = LocalModelWebToolRunner.registry(context, "public-catalog", "public-turn", null)
        val ids = registry.descriptors().map { it.id }.toSet()
        assertEquals(LocalModelAgentToolPolicy.toolIds, ids)
        assertTrue(AgentDesktopRemoteNativeTools.toolIds.none(ids::contains))
        assertTrue(AgentInteractiveBrowserTools.toolIds.none(ids::contains))
        var rounds = 0
        val session = session { system, prompt ->
            assertTrue(system.contains(AgentRuntimeControlTools.DIAGNOSE))
            assertTrue(system.contains(AgentLinuxSoftwareNativeTools.INSTALL))
            assertTrue(system.contains(AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH_BATCH))
            when (++rounds) {
                1 -> call("inspect", AgentToolInspectionTools.DESCRIBE,
                    mapOf("tool_id" to AgentOnDeviceRuntimeTools.EXECUTE))
                else -> {
                    val result = lastTool(prompt)
                    assertEquals("succeeded", result.getString("status"))
                    val contract = result.getJSONObject("output").getJSONObject("definition")
                    assertTrue(contract.getJSONObject("properties").has("source"))
                    answer("已读取手机 Linux 工具契约，未启动 Linux 或执行命令。")
                }
            }
        }
        val outcome = loop(registry, session, "public-catalog-${UUID.randomUUID()}")
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(1, outcome.usage.toolCallAttempts)
        assertEquals(2, rounds)
    }

    @Test fun realFileToolsShareAStableConversationWorkspaceAndCannotUseAModelSuppliedForeignId() = runBlocking {
        val conversation = "public-local-files-${UUID.randomUUID()}"
        val other = "$conversation-other"
        val own = LocalModelAgentToolPolicy.workspace(conversation, "first")
        val foreign = LocalModelAgentToolPolicy.workspace(other, "first")
        val root = File(context.filesDir, "agent-native-workspaces")
        val text = "公开测试：本地模型会话工作区"
        try {
            val registry = LocalModelWebToolRunner.registry(context, conversation, "public-turn", null)
            var rounds = 0
            val write = loop(registry, session { _, prompt ->
                when (++rounds) {
                    1 -> call("initialize", AgentPhoneNativeToolCatalog.WORKSPACE_INITIALIZE,
                        mapOf("workspace_id" to foreign))
                    2 -> call("write", AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
                        mapOf("workspace_id" to foreign, "path" to "public.txt", "text" to text))
                    else -> {
                        assertEquals("succeeded", lastTool(prompt).getString("status"))
                        answer("公开文件已写入。")
                    }
                }
            }, conversation, "first")
            assertEquals(AgentModelToolLoopStatus.COMPLETED, write.status)
            assertEquals(text, File(root, "$own/public.txt").readText())
            assertFalse(File(root, "$foreign/public.txt").exists())
            rounds = 0
            val read = loop(registry, session { _, prompt ->
                if (++rounds == 1) call("read", AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
                    mapOf("workspace_id" to foreign, "path" to "public.txt")) else {
                    assertEquals(text, lastTool(prompt).getJSONObject("output").getString("text"))
                    answer("后续轮次已读回相同文件。")
                }
            }, conversation, "second")
            assertEquals(AgentModelToolLoopStatus.COMPLETED, read.status)
            rounds = 0
            val isolated = loop(registry, session { _, prompt ->
                if (++rounds == 1) call("read-other", AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
                    mapOf("workspace_id" to own, "path" to "public.txt")) else {
                    assertNotEquals("succeeded", lastTool(prompt).getString("status"))
                    answer("另一个会话不能读取该文件。")
                }
            }, other, "third")
            assertEquals(AgentModelToolLoopStatus.COMPLETED, isolated.status)
        } finally {
            listOf(own, foreign).forEach { id ->
                val directory = File(root, id).canonicalFile
                check(directory.parentFile == root.canonicalFile)
                directory.deleteRecursively()
            }
        }
    }

    @Test fun localInferenceObservesFailureChoosesRepairAndVerifiesTheOriginallyBlockedOperation() = runBlocking {
        var repaired = false
        val operations = mutableListOf<String>()
        val id = "public.local.operation"
        val definition = AgentNativeToolDefinition(AgentNativeToolDescriptor(id, "1.0.0", "Public operation",
            "Public dependency fixture", AgentNativeToolLocation.PHONE,
            AgentNativeJsonSchema.objectSchema(mapOf("operation" to AgentNativeJsonSchema.string()), setOf("operation")),
            AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW), AgentNativeToolExecutor {
                val operation = it.input.getValue("operation").toString()
                operations += operation
                when (operation) {
                    "build" -> if (repaired) AgentNativeToolExecutionResult.success(mapOf("exit_code" to 0))
                        else AgentNativeToolExecutionResult.failure("dependency_missing", "公开测试编译器未安装")
                    "inspect" -> AgentNativeToolExecutionResult.success(mapOf("installed" to repaired))
                    "repair" -> { repaired = true; AgentNativeToolExecutionResult.success(mapOf("installed" to true)) }
                    else -> error("Unexpected public fixture operation")
                }
            })
        val registry = AgentNativeToolRegistry().register(definition).register(AgentToolInspectionTools.definition())
        var rounds = 0
        val local = session { _, prompt ->
            assertTrue(JSONObject(prompt).getJSONArray("messages").getJSONObject(0)
                .getString("text").contains(AgentProblemSolvingPolicy.CONTRACT))
            when (++rounds) {
                1 -> call("first-build", id, mapOf("operation" to "build"))
                2 -> {
                    assertEquals("dependency_missing", lastTool(prompt).getJSONObject("error").getString("code"))
                    call("contract", AgentToolInspectionTools.DESCRIBE, mapOf("tool_id" to id))
                }
                3 -> call("diagnosis", id, mapOf("operation" to "inspect"))
                4 -> {
                    assertFalse(lastTool(prompt).getJSONObject("output").getBoolean("installed"))
                    call("repair", id, mapOf("operation" to "repair"))
                }
                5 -> call("verify-original", id, mapOf("operation" to "build"))
                else -> {
                    assertEquals(0, lastTool(prompt).getJSONObject("output").getInt("exit_code"))
                    answer("已观察缺失依赖，修复后原操作验证成功。")
                }
            }
        }
        val outcome = loop(registry, local, "public-local-repair-${UUID.randomUUID()}")
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(listOf("build", "inspect", "repair", "build"), operations)
        assertEquals(6, rounds)
        assertEquals(0, outcome.usage.retries)
        assertEquals("public-scripted-local-model", local.lastInference?.profileId)
    }

    @Test fun ordinaryConversationUsesOneLocalInferenceAndDoesNotExecuteAnyTool() = runBlocking {
        val registry = LocalModelWebToolRunner.registry(context, "public-chat", "public-turn", null)
        var rounds = 0
        val local = session { _, _ -> rounds++; answer("你好！") }
        val outcome = loop(registry, local, "public-local-chat-${UUID.randomUUID()}")
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(1, rounds)
        assertEquals(0, outcome.usage.toolCallAttempts)
        assertEquals("你好！", outcome.assistantText)
    }

    @Test fun localAdapterCanDiscoverAnUnavailableCapabilityInspectSetupAndVerifyAfterRepair() = runBlocking {
        var installed = false
        var installations = 0
        var reads = 0
        val target = "public.browser.read"
        val install = "public.fixture.install"
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(
            AgentNativeToolDescriptor(target, "1.0.0", "Public browser page", "Read a public browser page",
                AgentNativeToolLocation.APPLICATION, AgentNativeJsonSchema.objectSchema(),
                AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW,
                effect = AgentNativeToolEffect.READ_ONLY), AgentNativeToolExecutor {
                reads++
                AgentNativeToolExecutionResult.success(mapOf("title" to "公开测试文章", "verified" to true))
            }, availabilityProvider = AgentNativeToolAvailabilityProvider {
                if (installed) AgentNativeToolAvailability.AVAILABLE else AgentNativeToolAvailability(
                    AgentNativeToolAvailabilityStatus.REQUIRES_SETUP, "公开测试浏览器依赖缺失")
            })).register(AgentNativeToolDefinition(
                AgentNativeToolDescriptor(install, "1.0.0", "Public dependency fixture", "Install public fixture dependency",
                    AgentNativeToolLocation.APPLICATION, AgentNativeJsonSchema.objectSchema(),
                    AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW), AgentNativeToolExecutor {
                    installations++
                    installed = true
                    AgentNativeToolExecutionResult.success(mapOf("installed" to true))
                })).register(AgentToolInspectionTools.definition()).register(AgentToolDiscoveryTools.definition())
        assertTrue(registry.availableCatalog().descriptors.none { it.id == target })
        var rounds = 0
        val local = session { _, prompt ->
            when (++rounds) {
                1 -> call("discover", AgentToolDiscoveryTools.ID, mapOf("query" to "public browser page"))
                2 -> {
                    val found = lastTool(prompt).getJSONObject("output").getJSONArray("tools").getJSONObject(0)
                    assertEquals(target, found.getString("id"))
                    assertEquals("requires_setup", found.getJSONObject("availability").getString("status"))
                    assertEquals(0, reads)
                    assertEquals(0, installations)
                    call("describe", AgentToolInspectionTools.DESCRIBE,
                        mapOf("tool_id" to target, "schema_path" to "/availability"))
                }
                3 -> {
                    assertEquals("requires_setup", lastTool(prompt).getJSONObject("output")
                        .getJSONObject("definition").getString("status"))
                    call("repair", install, emptyMap())
                }
                4 -> call("refresh", AgentToolDiscoveryTools.ID, mapOf("query" to "public browser page"))
                5 -> {
                    assertEquals("available", lastTool(prompt).getJSONObject("output").getJSONArray("tools")
                        .getJSONObject(0).getJSONObject("availability").getString("status"))
                    call("verify-original", target, emptyMap())
                }
                else -> {
                    assertEquals("公开测试文章", lastTool(prompt).getJSONObject("output").getString("title"))
                    answer("已发现缺失依赖并检查说明，修复后读回文章并完成验证。")
                }
            }
        }
        val outcome = loop(registry, local, "public-discovery-repair-${UUID.randomUUID()}")
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(6, rounds)
        assertEquals(1, reads)
        assertEquals(1, installations)
        assertEquals(0, outcome.usage.retries)
    }

    @Test fun productionLocalDiscoveryExposesOnlyItsOwnPhoneCapabilityView() {
        val registry = LocalModelWebToolRunner.registry(context, "public-discovery", "public-turn", null)
        val result = registry.invoke(AgentToolDiscoveryTools.ID, mapOf("limit" to 50))
        assertTrue(result.toJson(), result.isSuccess)
        val ids = (result.output["tools"] as List<*>).map { (it as Map<*, *>)["id"].toString() }.toSet()
        assertTrue(AgentToolDiscoveryTools.ID in ids)
        assertTrue(AgentToolInspectionTools.DESCRIBE in ids)
        assertTrue(ids.all { it in LocalModelAgentToolPolicy.toolIds })
        assertTrue(AgentDesktopRemoteNativeTools.toolIds.none(ids::contains))
        assertEquals(false, result.output["target_executed"])
    }

    private fun session(generate: (String, String) -> String) = LocalModelWebToolSession(
        context, "public-scripted-local-model", false, inference = { system, prompt ->
            LocalModelInferenceResult(text = generate(system, prompt), profileId = "public-scripted-local-model",
                backend = "scripted-device-fixture", smeAvailable = false, elapsedMillis = 1L,
                promptTokens = 20L, generatedTokens = 5L, decodeTokensPerSecond = 0.0)
        })

    private suspend fun loop(registry: AgentNativeToolRegistry, session: LocalModelWebToolSession,
        conversation: String, turn: String = "public-turn"): AgentModelToolLoopOutcome {
        val catalog = registry.availableCatalog()
        return AgentModelToolLoop(session.adapter(catalog.descriptors), registry,
            disclosedToolManifestJson = catalog.manifest.json, disclosedToolManifestSha256 = catalog.manifest.sha256)
            .run(AgentModelToolLoopRequest.forUserMessage("public-session-$turn", conversation, turn, turn,
                LocalModelAgentToolPolicy.workspace(conversation, "public-session-$turn"), "公开测试：请完成目标并验证结果。",
                budget = AgentModelToolLoopBudget(maxRetriesPerCall = 0, enforceCountLimits = false),
                grantedPermissions = catalog.descriptors.flatMap { it.requiredPermissions }.map { it.id }.toSet(),
                grantedConsents = catalog.descriptors.flatMap { it.requiredConsents }.map { it.id }.toSet()))
    }

    private fun lastTool(prompt: String): JSONObject {
        val messages = JSONObject(prompt).getJSONArray("messages")
        return (messages.length() - 1 downTo 0).map { messages.getJSONObject(it) }
            .first { !it.isNull("tool_result") }.getJSONObject("tool_result")
    }

    private fun call(id: String, tool: String, input: AgentNativeJsonObject) = AgentNativeJsonCodec.stringify(mapOf(
        "answer" to "公开测试：正在执行下一步。", "tool_calls" to listOf(mapOf("id" to id, "name" to tool, "arguments" to input))))
    private fun answer(text: String) = AgentNativeJsonCodec.stringify(mapOf("answer" to text, "tool_calls" to emptyList<Any>()))
}
