package com.galaxyssi.chat

import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DesktopPairingLifecycleTest {
    @Test
    fun archivedConversationOnlyReopensForItsVerifiedFingerprint() {
        val contact = JSONObject().put("id", "desktop-a").put("desktop_name", "Home")
        assertTrue(DesktopPairingLifecycle.preserveAsHistory(contact, "desktop-a"))
        assertFalse(DesktopPairingLifecycle.canRestoreHistory(contact, "Home"))
        contact.put("desktop_fingerprint", "aa".repeat(32))
        assertFalse(DesktopPairingLifecycle.canRestoreHistory(contact, null))
        assertFalse(DesktopPairingLifecycle.canRestoreHistory(contact, "ab".repeat(32)))
        assertTrue(DesktopPairingLifecycle.canRestoreHistory(contact, "AA".repeat(32)))
    }

    @Test
    fun matchesDeviceAndAgentContactsOwnedByOneDesktop() {
        val desktopId = "desktop-t14"

        assertTrue(DesktopPairingLifecycle.belongsToDesktop(
            JSONObject().put("id", desktopId).put("desktop_id", desktopId),
            desktopId
        ))
        assertTrue(DesktopPairingLifecycle.belongsToDesktop(
            JSONObject().put("id", "$desktopId:codex").put("desktop_id", desktopId),
            desktopId
        ))
        assertTrue(DesktopPairingLifecycle.belongsToDesktop(
            JSONObject().put("id", "codex-t14").put("parent_contact", desktopId),
            desktopId
        ))
    }

    @Test
    fun preservesContactsOwnedByAnotherDesktopOrCloudProvider() {
        val desktopId = "desktop-t14"

        assertFalse(DesktopPairingLifecycle.belongsToDesktop(
            JSONObject().put("id", "desktop-office:codex").put("desktop_id", "desktop-office"),
            desktopId
        ))
        assertFalse(DesktopPairingLifecycle.belongsToDesktop(
            JSONObject().put("id", "deepseek").put("delivery_mode", "cloud_api"),
            desktopId
        ))
    }

    @Test
    fun disconnectKeepsOriginalIdsAndHistoryButExcludesOldAgentFromRouting() {
        val oldId = "desktop_old"
        val oldAgentId = "$oldId:codex"
        val newAgentId = "desktop_new:codex"
        val oldAgent = JSONObject().put("id", oldAgentId).put("type", "agent")
            .put("desktop_id", oldId).put("desktop_name", "DESKTOP-T14").put("agent_id", "codex")
        val newAgent = JSONObject().put("id", newAgentId).put("type", "agent")
            .put("desktop_id", "desktop_new").put("desktop_name", "DESKTOP-T14").put("agent_id", "codex")
        val oldDevice = JSONObject().put("id", oldId).put("type", "device")

        assertFalse(ConversationHubContactHistoryPolicy.includes(oldAgent))
        assertTrue(DesktopPairingLifecycle.preserveAsHistory(oldAgent, oldId))
        assertTrue(DesktopPairingLifecycle.preserveAsHistory(oldDevice, oldId))
        assertFalse(DesktopPairingLifecycle.preserveAsHistory(newAgent, oldId))
        assertFalse(DesktopPairingLifecycle.preserveAsHistory(oldAgent, oldId))
        assertTrue(ConversationHubContactHistoryPolicy.includes(oldAgent))
        assertFalse(ConversationHubContactHistoryPolicy.hasUnread(oldAgent, 1, 1L))
        assertEquals(oldAgentId, oldAgent.getString("id"))

        val snapshot = AgentConnectorContactSnapshot.from(JSONArray().put(oldAgent).put(newAgent))
        assertEquals(listOf(newAgentId), snapshot.matchingContactIds("codex"))
        assertEquals(emptyList<String>(), snapshot.matchingContactIds(oldAgentId))
        DesktopPairingLifecycle.clearHistoryOnly(oldAgent)
        assertFalse(ConversationHubContactHistoryPolicy.includes(oldAgent))
    }

    @Test
    fun archivedDesktopChatCanStillBeOpenedWithoutDuplicatingActiveChat() {
        val old = ConversationHubContactSummary("old", "DESKTOP-T14", "Existing chat", 1L, unreadCount = 1, archived = true)
        val current = ConversationHubContactSummary("new", "DESKTOP-T14", "New chat", 2L)
        val contacts = listOf(old, current)
        assertEquals(listOf("new"), ConversationHubModels.unifiedConversations(emptyList(), contacts, "", false)
            .recent.map { it.id })
        val archived = ConversationHubModels.unifiedConversations(emptyList(), contacts, "Existing", true).recent.single()
        assertEquals("old", archived.id)
        assertEquals("Existing chat", archived.subtitle)
        assertEquals(0, archived.unreadCount)
    }
}
