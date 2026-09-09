package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ConversationHubContactHistoryPolicyTest {
    @Test fun agentHistoryIsHiddenWithoutRemovingItsContact() {
        for (type in listOf("agent", "model", "hermes")) {
            val contact = JSONObject().put("type", type).put("id", "desktop-codex")
            val before = contact.toString()
            assertFalse(ConversationHubContactHistoryPolicy.includes(contact))
            assertEquals(before, contact.toString())
        }
    }

    @Test fun peersRemainVisibleEvenWhenNamedCodex() {
        for (type in listOf("person", "device", "group", "system")) {
            val contact = JSONObject().put("type", type).put("name", "Codex Agent")
                .put("agent_kind", "stale-metadata")
            assertTrue(ConversationHubContactHistoryPolicy.includes(contact))
        }
        assertTrue(ConversationHubContactHistoryPolicy.includes(null))
    }

    @Test fun legacyCloudAndLocalAgentsHaveNoSeparateChatEntry() {
        assertFalse(ConversationHubContactHistoryPolicy.includes(JSONObject().put("delivery_mode", "cloud_api")))
        assertFalse(ConversationHubContactHistoryPolicy.includes(JSONObject().put("agent_kind", "local-cli")))
    }
}
