package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Production HTTP adapters and encrypted planning journals; scripted local Provider, not real model acceptance. */
@RunWith(AndroidJUnit4::class)
class AgentPlannerCatalogRecoveryDeviceTest {
    @Test fun openAiRepairRestoresOriginalPlanningJournal() = scenario("openai", reopen = true)
    @Test fun anthropicRepairRestoresOriginalPlanningJournal() = scenario("anthropic", reopen = true)
    @Test fun geminiRepairRestoresOriginalPlanningJournal() = scenario("gemini", reopen = true)
    @Test fun repairUpdatesTheSameHttpAdapterBeforeReadinessCacheExpires() = scenario("openai", reopen = false)
    @Test fun canonicalJournalResumesThroughWireNamedHttpCalls() = scenario("openai", reopen = true, legacy = true)

    private fun scenario(style: String, reopen: Boolean, legacy: Boolean = false) = runBlocking {
        val app = InstrumentationRegistry.getInstrumentation().targetContext
        val token = UUID.randomUUID().toString()
        val database = "public-planner-catalog-$token.db"
        val goal = "请修好缺少的公开测试依赖，再读取测试页面并验证原始目标。"
        val screen = ScreenContext("Public fixture", pageTitle = "Public fixture")
        val original = AgentRequest(goal, screen, emptyList(), memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(sessionId = "public-session-$token", goal = goal, screen = screen,
                permissionMode = PermissionMode.AUTO_LOW_RISK, highRiskGuard = true, memoryCapture = false,
                callableTargets = emptyList(), memories = emptyList(), nativeTools = emptyList()),
            conversationContext = AgentConversationContext("public-conversation-$token", "", emptyList(), false),
            executionTurnId = "public-turn-$token")
        val settings = AgentModelPlannerSettings()
        val identity = AgentPlannerToolLoopRequest.create(original, settings,
            listOf(AgentModelMessage.system("Public fixture system"), AgentModelMessage.user(goal)), emptyList())
        var store = AgentRunEventStore(app, database)
        var ready = false
        var installs = 0
        var reads = 0
        fun descriptor(id: String) = AgentNativeToolDescriptor(id, "1.0.0", "Public fixture", "Public fixture contract",
            AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW)
        fun registry() = AgentNativeToolRegistry(clock = AgentNativeClock { 10L }, descriptorCacheTtlMillis = 60_000)
            .registerAll(listOf(
                AgentNativeToolDefinition(descriptor(INSTALL), AgentNativeToolExecutor {
                    installs++; ready = true; AgentNativeToolExecutionResult.success(mapOf("public_fixture_installed" to true))
                }), AgentNativeToolDefinition(descriptor(READ).copy(effect = AgentNativeToolEffect.READ_ONLY), AgentNativeToolExecutor {
                    reads++; AgentNativeToolExecutionResult.success(mapOf("public_fixture_verified" to true))
                }, availabilityProvider = AgentNativeToolAvailabilityProvider {
                    if (ready) AgentNativeToolAvailability.AVAILABLE else AgentNativeToolAvailability(
                        AgentNativeToolAvailabilityStatus.REQUIRES_SETUP, "Public fixture dependency absent")
                })))
        fun request(session: AgentPlannerToolCatalogSession, fresh: Boolean = false) = identity.copy(
            messages = if (fresh) listOf(AgentModelMessage.user("公开测试：这是新的易变环境快照，不应替代原目标。")) else identity.messages,
            grantedPermissions = session.binding.descriptors.flatMap { it.requiredPermissions }.filter { it.required }
                .mapTo(linkedSetOf()) { it.id })
        try {
            MockWebServer().use { server ->
                server.start()
                if (!legacy) server.enqueue(response(style, INSTALL))
                server.enqueue(response(style, READ))
                server.enqueue(response(style, null))
                AgentProviderWireNameFixture.enforce(server, style) { validContinuation(style, it, legacy) }
                val contact = JSONObject().put("id", "public-provider-$token").put("name", "Public local Provider fixture")
                    .put("cloud_provider", "custom").put("cloud_api_style", style).put("cloud_model", "public-fixture-model")
                    .put("cloud_api_key", "fixture-only-key").put("cloud_endpoint",
                        server.url(if (style == "gemini") "/models/public-fixture-model:generateContent" else "/fixture").toString())
                val initialRegistry = registry()
                val initialJournal = EncryptedAgentModelLoopJournal(app, store)
                val initial = AgentPlannerToolCatalogBinding.prepare(initialJournal, identity, initialRegistry)
                val http = CloudModelClient.nativeToolAdapter(app, contact, initial.initialAvailable, initial::providerCatalog)
                fun loop(adapter: AgentModelAdapter, tools: AgentNativeToolRegistry, session: AgentPlannerToolCatalogSession,
                    journal: AgentModelLoopJournal) = AgentModelToolLoop(adapter, tools,
                        disclosedToolManifestJson = session.binding.manifest.json,
                        disclosedToolManifestSha256 = session.binding.manifest.sha256, journal = journal)
                val completed = withTimeout(30_000) {
                    if (reopen) {
                        try {
                            loop(AgentModelAdapter { incoming ->
                                if (incoming.round == 2) throw CancellationException("Public interruption after setup receipt")
                                if (legacy) AgentModelResponse(toolCalls = listOf(AgentModelToolCall("legacy-install", INSTALL)))
                                else http.complete(incoming)
                            }, initialRegistry, initial, initialJournal).run(request(initial))
                            fail("Expected public interruption")
                        } catch (_: CancellationException) { }
                        assertEquals(1, installs)
                        store.close()
                        store = AgentRunEventStore(app, database)
                        val restoredRegistry = registry()
                        val restoredJournal = EncryptedAgentModelLoopJournal(app, store)
                        val restored = AgentPlannerToolCatalogBinding.prepare(restoredJournal, identity, restoredRegistry)
                        assertEquals(initial.binding.manifest, restored.binding.manifest)
                        assertNotEquals(initial.initialAvailable.manifest.sha256, restored.initialAvailable.manifest.sha256)
                        val resumed = CloudModelClient.nativeToolAdapter(app, contact, restored.initialAvailable, restored::providerCatalog)
                        loop(resumed, restoredRegistry, restored, restoredJournal).run(request(restored, fresh = true))
                    } else loop(http, initialRegistry, initial, initialJournal).run(request(initial))
                }
                assertEquals(AgentModelToolLoopStatus.COMPLETED, completed.status)
                assertEquals("已验证原始公开测试目标。", completed.assistantText)
                assertEquals(1, installs)
                assertEquals(1, reads)
                val expectedRequests = if (legacy) 2 else 3
                assertEquals(expectedRequests, server.requestCount)
                val requests = (0 until expectedRequests).map { checkNotNull(server.takeRequest(1, TimeUnit.SECONDS)) }
                val bodies = requests.map { JSONObject(it.body.readUtf8()) }
                val repaired = if (legacy) 0 else 1
                if (!legacy) assertFalse(AgentProviderWireNameFixture.declarations(style, bodies[0]).contains(AgentModelToolWireNames.name(READ)))
                assertTrue(AgentProviderWireNameFixture.declarations(style, bodies[repaired]).contains(AgentModelToolWireNames.name(READ)))
                assertTrue(AgentProviderWireNameFixture.historicalCalls(style, bodies[repaired]).contains(AgentModelToolWireNames.name(INSTALL)))
                assertTrue(bodies.all { it.toString().contains(goal) })
                assertFalse(bodies[repaired].toString().contains("不应替代原目标"))
                assertTrue(bodies[repaired].toString().contains("public_fixture_installed"))
                assertTrue(bodies.last().toString().contains("public_fixture_verified"))
                if (style == "gemini") {
                    assertTrue(bodies.none { it.has("model") })
                    assertTrue(requests.all { it.path.orEmpty().startsWith("/models/public-fixture-model:generateContent?") })
                } else assertTrue(bodies.all { it.getString("model") == "public-fixture-model" })
            }
        } finally {
            store.close()
            app.deleteDatabase(database)
            File(app.noBackupFilesDir, "model-loop-leases/${AgentModelLoopScope.from(identity).digest}.lock").delete()
        }
    }

    private fun response(style: String, tool: String?): MockResponse {
        val text = "已验证原始公开测试目标。"
        val wireName = tool?.let(AgentModelToolWireNames::name)
        val callId = tool?.let { "fixture_" + it.replace('.', '_') }
        val body = when (style) {
            "anthropic" -> {
                val block = if (tool == null) JSONObject().put("type", "text").put("text", text)
                else JSONObject().put("type", "tool_use").put("id", callId).put("name", wireName).put("input", JSONObject())
                val blocks = JSONArray()
                if (tool != null) blocks.put(JSONObject().put("type", "thinking").put("thinking", "Public opaque fixture")
                    .put("signature", "signature-$tool"))
                if (tool != null) blocks.put(JSONObject().put("type", "redacted_thinking").put("data", "opaque-$tool"))
                JSONObject().put("content", blocks.put(block))
            }
            "gemini" -> {
                val part = if (tool == null) JSONObject().put("text", text)
                else JSONObject().put("functionCall", JSONObject().put("name", wireName).put("args", JSONObject()))
                val parts = JSONArray()
                if (tool != null) {
                    parts.put(JSONObject().put("text", "Public opaque fixture").put("thought", true).put("thoughtSignature", "thought-$tool"))
                    part.put("thoughtSignature", "signature-$tool")
                }
                val content = JSONObject().put("parts", parts.put(part))
                JSONObject().put("candidates", JSONArray().put(JSONObject().put("content", content)))
            }
            else -> {
                val message = JSONObject().put("content", if (tool == null) text else "")
                if (tool != null) {
                    message.put("reasoning_content", "Public opaque fixture $tool")
                    val function = JSONObject().put("name", wireName).put("arguments", "{}")
                    message.put("tool_calls", JSONArray().put(JSONObject().put("id", callId)
                        .put("type", "function").put("function", function)))
                }
                JSONObject().put("choices", JSONArray().put(JSONObject().put("message", message)))
            }
        }
        return MockResponse().setHeader("Content-Type", "application/json").setBody(body.toString())
    }

    private fun validContinuation(style: String, body: JSONObject, legacy: Boolean): Boolean {
        if (style == "gemini" && body.has("model")) return false
        val messages = body.getJSONArray(if (style == "gemini") "contents" else "messages")
        for (index in 0 until messages.length()) {
            val message = messages.getJSONObject(index)
            if (message.optString("role") !in setOf("assistant", "model")) continue
            val calls = AgentProviderWireNameFixture.historicalCalls(style,
                JSONObject().put(if (style == "gemini") "contents" else "messages", JSONArray().put(message)))
            if (calls.isEmpty()) continue
            val tool = when (calls.single()) {
                AgentModelToolWireNames.name(INSTALL) -> INSTALL
                AgentModelToolWireNames.name(READ) -> READ
                else -> return false
            }
            if (legacy && tool == INSTALL) continue
            when (style) {
                "gemini" -> {
                    val parts = message.getJSONArray("parts")
                    if (parts.length() != 2 || !parts.getJSONObject(0).getBoolean("thought") ||
                        parts.getJSONObject(0).getString("thoughtSignature") != "thought-$tool" ||
                        parts.getJSONObject(1).getString("thoughtSignature") != "signature-$tool") return false
                }
                "anthropic" -> {
                    val blocks = message.getJSONArray("content")
                    if (blocks.length() != 3 || blocks.getJSONObject(0).getString("signature") != "signature-$tool" ||
                        blocks.getJSONObject(1).getString("data") != "opaque-$tool") return false
                }
                else -> if (message.getString("reasoning_content") != "Public opaque fixture $tool") return false
            }
        }
        return true
    }

    private companion object {
        const val INSTALL = "public.fixture.install"
        const val READ = "public.fixture.read"
    }
}
