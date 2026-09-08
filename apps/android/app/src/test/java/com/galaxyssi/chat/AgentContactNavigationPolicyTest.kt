package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentContactNavigationPolicyTest {
    @Test fun everyProviderUsesAgentHomeRegardlessOfTransportAndAvailability() {
        for (provider in listOf("codex", "deepseek", "hermes", "claude", "openclaw", "gemini", "local-llm", "custom-agent")) {
            for (mode in listOf("pc_connector", "cloud_api", "local", "")) {
                for (deleted in listOf(false, true)) {
                    val contact = JSONObject().put("id", provider).put("type", "agent")
                        .put("delivery_mode", mode).put("deleted", deleted)
                    assertTrue("$provider/$mode/$deleted", AgentContactNavigationPolicy.opensAgentConversation(contact))
                }
            }
        }
    }

    @Test fun peerIdentityWinsOverNamesAndStaleAgentMetadata() {
        for (type in listOf("person", "device", "group", "system")) {
            val contact = JSONObject().put("type", type).put("name", "Codex DeepSeek Agent")
                .put("delivery_mode", "pc_connector").put("agent_kind", "local-cli")
            assertFalse(type, AgentContactNavigationPolicy.opensAgentConversation(contact))
        }
        assertFalse(AgentContactNavigationPolicy.opensAgentConversation(JSONObject().put("name", "Codex")))
        assertFalse(AgentContactNavigationPolicy.opensAgentConversation(null))
    }

    @Test fun legacyHermesAndModelMetadataUseAgentHome() {
        for (contact in listOf(
            JSONObject().put("type", "hermes"),
            JSONObject().put("type", "model"),
            JSONObject().put("delivery_mode", "cloud_api"),
            JSONObject().put("agent_kind", "local-model")
        )) assertTrue(AgentContactNavigationPolicy.opensAgentConversation(contact))
        assertFalse(AgentContactNavigationPolicy.opensAgentConversation(JSONObject().put("delivery_mode", "pc_connector")))
    }

    @Test fun cloudAndLocalModelTargetsCanBeSelectedIncludingUnavailableModels() {
        for (status in AgentConnectorStatus.entries) {
            val target = target("deepseek", AgentConnectorKind.MODEL).copy(status = status)
            val contact = JSONObject().put("id", target.id).put("type", "agent").put("delivery_mode", "cloud_api")
            assertEquals(target, AgentContactNavigationPolicy.resolveTarget(target.id, contact, listOf(target)))
        }
    }

    @Test fun deletedAgentsCannotResolveLiveTargetsAndDevicesCannotBeSelected() {
        val target = target("desktop:codex", AgentConnectorKind.AGENT)
        val contact = JSONObject().put("id", target.id).put("type", "agent").put("deleted", true)
        assertNull(AgentContactNavigationPolicy.resolveTarget(target.id, contact, listOf(target)))
        contact.put("deleted", false)
        assertNull(AgentContactNavigationPolicy.resolveTarget(target.id, contact, listOf(target.copy(kind = AgentConnectorKind.DEVICE))))
    }

    private fun target(id: String, kind: AgentConnectorKind) = AgentCallableTarget(
        id = id, title = id, kind = kind, status = AgentConnectorStatus.AVAILABLE,
        capabilities = listOf(AgentCapability.CHAT)
    )
}
