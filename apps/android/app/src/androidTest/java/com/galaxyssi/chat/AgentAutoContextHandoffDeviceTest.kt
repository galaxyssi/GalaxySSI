package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.coroutines.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentAutoContextHandoffDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun existingConversationRetainsRequirementsAndConfiguredAutoModel() {
        val args = InstrumentationRegistry.getArguments()
        val id = args.getString("existing_conversation_id").orEmpty()
        assumeTrue(id.isNotBlank())
        val dialogue = AgentTranscriptStore(context).context(id)
        val block = dialogue.asTransportBlock(32_768)
        args.getString("required_context_terms").orEmpty().split('|').filter(String::isNotBlank).forEach {
            assertTrue("Missing required context term", block.contains(it))
        }
        val target = requireNotNull(args.getString("existing_target_id"))
        val action = RuleBasedAgentPlanner(context).connectorAction(request(id, emptyList()).copy(
            conversationContext = dialogue), target, "Verify saved Auto profile")
        assertEquals(args.getString("expected_agent_model"), action.parameters["agent_model_id"])
        assertEquals(args.getString("expected_agent_effort"), action.parameters["agent_reasoning_effort"])
        val targets = AppStoreAgentConnectorRegistry(context).availableTargets()
        val aliasAction = RuleBasedAgentPlanner(context).connectorAction(request(id, emptyList()).copy(
            conversationContext = dialogue, targets = targets), target.substringAfterLast(':'), "Verify alias Auto profile")
        assertEquals(args.getString("expected_agent_model"), aliasAction.parameters["agent_model_id"])
        assertEquals(args.getString("expected_agent_effort"), aliasAction.parameters["agent_reasoning_effort"])
        assertEquals(target, aliasAction.parameters[AgentInvocationBinding.TARGET])
        println("EXISTING_CONTEXT preserved=true saved_model=${action.parameters["agent_model_id"]} " +
            "saved_effort=${action.parameters["agent_reasoning_effort"]}")
    }

    @Test fun autoPlanningUsesPerTargetSavedModelAndDoesNotTouchOtherConversations() {
        val id = "test-auto-context-${UUID.randomUUID()}"
        val target = "test-desktop-$id:codex"
        val preferences = context.getSharedPreferences("galaxyssi_agent_model_selection_v2", 0)
        val oldDefault = preferences.getString("default.mode", null)
        try {
            AgentModelSelectionSettings.selectManual(context, id, target, "gpt-6-astra", "Test Codex",
                AgentModelReasoningEffort.HIGH, rememberAsDefault = false)
            AgentModelSelectionSettings.selectAutoForConversation(context, id)
            val action = RuleBasedAgentPlanner(context).connectorAction(request(id, emptyList()), target, "Test")
            assertEquals(AgentModelSelectionMode.AUTO, AgentModelSelectionSettings.selection(context, id).mode)
            assertEquals("gpt-6-astra", action.parameters["agent_model_id"])
            assertEquals("high", action.parameters["agent_reasoning_effort"])
            assertEquals(oldDefault, preferences.getString("default.mode", null))
            assertEquals(target, action.parameters[AgentInvocationBinding.TARGET])
        } finally {
            AgentModelSelectionSettings.clearConversation(context, id)
            preferences.edit().remove(AgentModelSelectionSettings.defaultTargetPreferenceKey(target, "model_id"))
                .remove(AgentModelSelectionSettings.defaultTargetPreferenceKey(target, "reasoning_effort")).commit()
        }
    }

    /** Opt-in real MQTT/provider probe. Only generated public dialogue is transmitted. */
    @Test fun savedAutoInvocationAndLongHandoffReachTheRealProvider(): Unit = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("live_context_handoff") == "true")
        val expectedModel = requireNotNull(args.getString("expected_agent_model"))
        val expectedEffort = requireNotNull(args.getString("expected_agent_effort"))
        val contacts = AppStore.contacts(context)
        val contact = (0 until contacts.length()).map { contacts.getJSONObject(it) }.first {
            it.optString("desktop_id").isNotBlank() && !it.optBoolean("deleted") &&
                AppStore.agentIdForContact(context, it.optString("id")) == "codex" &&
                GalaxySSILinkProtocol.serverLink(context, it.optString("desktop_id"))?.paired == true
        }.getString("id")
        withContext(Dispatchers.IO) { GalaxySSIMqttClient.connect(context) }
        withTimeout(30_000) { while (!GalaxySSIMqttClient.isRequestReplyReady()) delay(100) }
        val id = "context-model-probe-${UUID.randomUUID()}"
        val source = System.currentTimeMillis()
        val turns = (1..7).flatMap { round ->
            listOf(entry(id, round, true, if (round == 1) "我要找在线博士，专业是计算机或人工智能；请给出中文校名和学费。"
                else "继续第${round}轮查询。"), entry(id, round, false, "第${round}轮历史资料。" + "这是公开测试的长回答占位内容。".repeat(300)))
        }
        val request = request(id, turns)
        val action = RuleBasedAgentPlanner(context).connectorAction(request, contact, "Test Auto")
        assertEquals(expectedModel, action.parameters["agent_model_id"])
        assertEquals(expectedEffort, action.parameters["agent_reasoning_effort"])
        val prompt = AgentSupervisedProjectLoop.planningPrompt(request)
        assertTrue(prompt.contains("在线博士"))
        val final = CompletableDeferred<AgentConnectorResponse>()
        val listener = object : GalaxySSIMqttClient.Listener {
            override fun onMessage(payload: String) {
                val json = runCatching { JSONObject(payload) }.getOrNull() ?: return
                if (json.optLong("source_message_id") != source || json.optString("conversation_id") != id ||
                    json.optString("type") != "text") return
                val response = AgentRemoteOutcomeCodec.decode(json, AgentRemoteOutcomeCodec.content(context, json)) ?: return
                GalaxySSIMqttClient.completeIncomingDelivery(context, payload)
                final.complete(response)
            }
        }
        GalaxySSIMqttClient.addListener(listener)
        try {
            val started = android.os.SystemClock.elapsedRealtime()
            withContext(Dispatchers.IO) {
                assertTrue(GalaxySSIMqttClient.publishUserMessage(prompt, contactId = contact,
                    clientMessageId = source, conversationId = id, turnId = "$id-turn", taskId = "$id-task",
                    connectorTaskMode = PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE,
                    executionMode = AgentTaskExecutionMode.PLAN_ONLY, executionPolicyPrompt = request.goal,
                    agentModelId = action.parameters.getValue("agent_model_id"),
                    agentReasoningEffort = AgentModelReasoningEffort.fromWireValue(action.parameters["agent_reasoning_effort"])))
            }
            val response = withTimeout(180_000) { final.await() }
            assertTrue(response.content.take(200), response.success)
            val answer = AgentSupervisedProjectDirectResponseCodec.parse(response.content) ?: response.content
            listOf("在线", "博士", "计算机", "人工智能", "中文", "学费").forEach {
                assertTrue("Missing original requirement: $it", answer.contains(it))
            }
            println("LIVE_CONTEXT conversation=$id model=$expectedModel effort=$expectedEffort " +
                "source=$source preserved_requirements=6 elapsed_ms=${android.os.SystemClock.elapsedRealtime() - started}")
        } finally { GalaxySSIMqttClient.removeListener(listener) }
    }

    private fun entry(id: String, round: Int, user: Boolean, text: String) = AgentTranscriptEntry(
        id = "$round-$user", role = if (user) AgentTranscriptRole.USER else AgentTranscriptRole.ASSISTANT,
        text = text, timestampMillis = round * 2L + if (user) 0 else 1, conversationId = id, turnId = "$id-$round")

    private fun request(id: String, turns: List<AgentTranscriptEntry>): AgentRequest {
        val goal = "无需联网，也不要继续找学校。请复述我最早要求的学位、专业、学习方式和两个输出字段；不要重新询问已给出的条件。"
        val screen = ScreenContext("Test", pageTitle = "Context handoff")
        return AgentRequest(goal, screen, emptyList(), memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(sessionId = id, goal = goal, screen = screen,
                permissionMode = PermissionMode.AUTO_LOW_RISK, highRiskGuard = true, memoryCapture = false,
                callableTargets = emptyList(), memories = emptyList(), nativeTools = emptyList()),
            conversationContext = AgentConversationContext(id, "", turns, true), executionTurnId = "$id-turn")
    }
}
