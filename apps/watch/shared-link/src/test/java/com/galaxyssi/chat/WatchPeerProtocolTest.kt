package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WatchPeerProtocolTest {
    private val alice = "galaxyssi:1111111111111111"
    private val bob = "galaxyssi:2222222222222222"
    private val route = "abcdefghijklmnopqrstuv"
    @Test fun phoneCompatibleEnvelopeBindsBothConversationParticipants() {
        val payload = WatchPeerProtocol.outgoing(alice, bob, route, "Hello 你好")
        assertTrue(WatchPeerProtocol.validIncoming(payload, alice, bob, route))
        assertEquals("peer:$alice:$bob", payload.getString("conversation_id"))
        assertEquals(alice, payload.getString("contact_id"))
        assertEquals(alice, payload.getString("sender"))
        assertEquals("text", payload.getString("message_kind"))
        assertEquals(payload.getString("source_message_id"), payload.getLong("client_message_id").toString())
    }
    @Test fun otherContactCannotReuseValidMessage() {
        val payload = WatchPeerProtocol.outgoing(alice, bob, route, "hello")
        assertFalse(WatchPeerProtocol.validIncoming(payload, "galaxyssi:3333333333333333", bob, route))
        assertFalse(WatchPeerProtocol.validIncoming(payload, alice, "galaxyssi:3333333333333333", route))
        assertFalse(WatchPeerProtocol.validIncoming(payload, alice, bob, "another-route"))
    }
    @Test fun tamperedSenderContactOrConversationIsRejected() {
        val original = WatchPeerProtocol.outgoing(alice, bob, route, "hello")
        listOf("sender", "contact_id", "conversation_id", "message_id", "type").forEach { field ->
            assertFalse(field, WatchPeerProtocol.validIncoming(JSONObject(original.toString()).put(field, "forged"), alice, bob, route))
        }
    }
    @Test fun oversizedTextRejected() {
        val payload = WatchPeerProtocol.outgoing(alice, bob, route, "a".repeat(24_001))
        assertFalse(WatchPeerProtocol.validIncoming(payload, alice, bob, route))
    }
    @Test fun conversationIsSymmetricButMessageIdsAreUnique() {
        assertEquals(WatchPeerProtocol.conversation(alice, bob), WatchPeerProtocol.conversation(bob, alice))
        assertNotEquals(WatchPeerProtocol.outgoing(alice, bob, route, "a").getString("message_id"),
            WatchPeerProtocol.outgoing(alice, bob, route, "a").getString("message_id"))
    }
}
