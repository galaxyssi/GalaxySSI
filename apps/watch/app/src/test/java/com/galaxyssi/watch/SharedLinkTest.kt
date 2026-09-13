package com.galaxyssi.watch

import com.galaxyssi.chat.GalaxySSILinkProtocol as Link
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

/** Exercise the exact phone protocol source compiled by shared-link. */
class SharedLinkTest {
    @Test fun privacyPacketRoundTripAndTamperRejection() {
        val secret = Link.newLinkSecret()
        val wire = Link.sealWirePacket("private watch request", secret)
        assertEquals("private watch request", Link.openWirePacket(wire.toByteArray(), secret))
        assertFalse(wire.contains("private watch request"))
        assertThrows(Exception::class.java) { Link.openWirePacket(wire.toByteArray(), Link.newLinkSecret()) }
        val modified = wire.toCharArray().apply { this[size / 2] = if (this[size / 2] == 'A') 'B' else 'A' }.concatToString()
        assertThrows(Exception::class.java) { Link.openWirePacket(modified.toByteArray(), secret) }
    }
    @Test fun directionalTopicsDoNotRevealIdentity() {
        val secret = Link.newLinkSecret()
        val out = Link.relationshipTopic(secret, "watch", "computer", 10)
        val incoming = Link.relationshipTopic(secret, "computer", "watch", 10)
        assertNotEquals(out, incoming)
        assertNotEquals(out, Link.relationshipTopic(secret, "watch", "computer", 11))
        assertTrue(Link.validTopic(out))
    }
    @Test fun validatesEnvelopeExpiryAndStableMessageId() {
        val id = UUID.randomUUID().toString()
        val payload = JSONObject().put("type", "text").put("content", "Hello").put("message_id", id)
        val envelope = Link.makeEnvelope(payload, "watch", "computer")
        assertEquals(id, envelope.getString("message_id"))
        assertNotNull(Link.unwrapEnvelope(envelope))
        envelope.put("expires_at", System.currentTimeMillis() - 1)
        assertNull(Link.unwrapEnvelope(envelope))
    }
    @Test fun rejectsStalePairingOffers() {
        val source = JSONObject().put("t", "o2").put("n", "Test computer")
            .put("h", "a".repeat(64)).put("e", Link.newLinkSecret())
            .put("x", "b".repeat(32)).put("c", System.currentTimeMillis() / 1000)
        val offer = Link.normalizePairingQr(source)!!
        assertTrue(Link.validatePairingQr(offer))
        assertFalse(Link.validatePairingQr(offer, System.currentTimeMillis() + 11 * 60_000))
        assertFalse(Link.validatePairingQr(offer.put("pairing_topic", "wrong")))
    }
}
