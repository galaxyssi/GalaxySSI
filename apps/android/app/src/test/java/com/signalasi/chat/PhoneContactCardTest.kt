package com.signalasi.chat

import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.MessageDigest
import java.util.Base64

class PhoneContactCardTest {
    @Test
    fun `one-time contact card uses an opaque rendezvous mailbox`() {
        val card = validCard()

        assertTrue(SignalASILinkProtocol.validTopic(card.getString("pairing_topic")))
        assertTrue(
            card.getString("pairing_topic") ==
                SignalASILinkProtocol.pairingTopic(card.getString("pairing_secret"))
        )
        assertFalse(card.getString("pairing_topic").contains('/'))
        assertFalse(card.toString().contains("signalasichat/v1"))
    }

    @Test
    fun `contact card rejects a rendezvous mailbox not derived from its secret`() {
        val card = validCard().put("pairing_topic", SignalASILinkProtocol.newLinkSecret())

        assertFalse(PhoneContactCard.isStructurallyValid(card))
    }

    @Test
    fun `contact identity must be derived from its public key fingerprint`() {
        val card = validCard().put("signalasi_id", "signalasi:${"b".repeat(16)}")

        assertFalse(PhoneContactCard.isStructurallyValid(card))
    }

    @Test
    fun `canonical signature bytes are stable across json insertion order`() {
        val first = validCard()
        val second = JSONObject()
        first.keys().asSequence().toList().reversed().forEach { key -> second.put(key, first.opt(key)) }

        assertArrayEquals(PhoneContactCard.canonicalBytes(first), PhoneContactCard.canonicalBytes(second))
    }

    @Test
    fun `contact request must target the local cryptographic identity`() {
        val request = JSONObject().put("to", "signalasi:${"a".repeat(16)}")

        assertTrue(
            PhoneContactCard.isAddressedToLocalIdentity(request, "signalasi:${"a".repeat(16)}")
        )
        assertFalse(
            PhoneContactCard.isAddressedToLocalIdentity(request, "signalasi:${"b".repeat(16)}")
        )
    }

    @Test
    fun `stale pairing offer is rejected`() {
        val card = validCard(createdAt = 1L)

        assertFalse(
            PhoneContactCard.isFreshControlPayload(
                card,
                PhoneContactCard.CONTROL_MAX_AGE_MILLIS + 2L
            )
        )
    }

    @Test
    fun `pairing controls never expose relationship secrets or internal routes`() {
        val localCard = validCard()
            .put("type", PhoneContactCard.IDENTITY_TYPE)
            .put("pairing_token", "")
            .put("pairing_secret", "")
            .put("pairing_topic", "")
        val claim = PhoneContactCard.controlPayload(
            PhoneContactCard.REQUEST_TYPE,
            "signalasi:${"b".repeat(16)}",
            localCard,
            SignalASILinkProtocol.newLinkSecret(),
            nowMillis = 123L
        )

        assertEquals(PhoneContactCard.REQUEST_TYPE, claim.getString("type"))
        assertEquals(123L, claim.getLong("time"))
        assertTrue(claim.has("pairing_token"))
        listOf("link_secret", "client_route_id", "signal_bundle", "reply_topic").forEach { key ->
            assertFalse(claim.has(key))
        }
        assertTrue(claim.getJSONObject("contact_card").has("signal_bundle"))

        val confirmation = PhoneContactCard.controlPayload(
            PhoneContactCard.BUNDLE_RESPONSE_TYPE,
            "signalasi:${"b".repeat(16)}",
            localCard,
            nowMillis = 124L
        )
        assertFalse(confirmation.has("pairing_token"))
        listOf("link_secret", "client_route_id", "signal_bundle", "reply_topic").forEach { key ->
            assertFalse(confirmation.has(key))
        }
    }

    private fun validCard(createdAt: Long = System.currentTimeMillis()): JSONObject {
        val identityBytes = ByteArray(32) { index -> (index + 1).toByte() }
        val fingerprint = MessageDigest.getInstance("SHA-256")
            .digest(identityBytes)
            .joinToString("") { "%02x".format(it) }
        val secret = SignalASILinkProtocol.newLinkSecret()
        val bundle = JSONObject().put(
            "identityKey",
            Base64.getEncoder().encodeToString(identityBytes)
        )
        return JSONObject()
            .put("type", PhoneContactCard.TYPE)
            .put("version", PhoneContactCard.VERSION)
            .put("signalasi_id", "signalasi:${fingerprint.take(16)}")
            .put("name", "S26 Ultra")
            .put("identity_public_key", "A".repeat(48))
            .put("identity_fingerprint", fingerprint)
            .put("signal_bundle", bundle)
            .put("bundle_identity_fingerprint", fingerprint)
            .put("pairing_token", SignalASILinkProtocol.newLinkSecret())
            .put("pairing_secret", secret)
            .put("pairing_topic", SignalASILinkProtocol.pairingTopic(secret))
            .put("device_id", SignalASILinkProtocol.newRouteId())
            .put("created_at", createdAt)
            .put("signature", "B".repeat(64))
    }
}
