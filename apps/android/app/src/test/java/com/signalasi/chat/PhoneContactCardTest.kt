package com.signalasi.chat

import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneContactCardTest {
    @Test
    fun `signed contact card requires a phone-owned opaque inbox`() {
        val route = SignalASILinkProtocol.newRouteId()
        val fingerprint = "a".repeat(64)
        val card = JSONObject()
            .put("type", PhoneContactCard.TYPE)
            .put("version", PhoneContactCard.VERSION)
            .put("signalasi_id", "signalasi:${fingerprint.take(16)}")
            .put("name", "S26 Ultra")
            .put("identity_public_key", "A".repeat(48))
            .put("identity_fingerprint", fingerprint)
            .put("mqtt_inbox_topic", PhoneContactCard.inboxTopic(route))
            .put("device_id", SignalASILinkProtocol.newRouteId())
            .put("created_at", 1L)
            .put("signature", "B".repeat(64))

        assertTrue(PhoneContactCard.isStructurallyValid(card))
        assertFalse(
            PhoneContactCard.isStructurallyValid(
                JSONObject(card.toString()).put("mqtt_inbox_topic", "signalasichat/android/recv")
            )
        )
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
        first.keys().asSequence().toList().reversed().forEach { key ->
            second.put(key, first.opt(key))
        }

        assertArrayEquals(
            PhoneContactCard.canonicalBytes(first),
            PhoneContactCard.canonicalBytes(second)
        )
    }

    @Test
    fun `contact request must target the local Signal identity`() {
        val request = JSONObject().put("to", "signalasi:${"a".repeat(16)}")

        assertTrue(
            PhoneContactCard.isAddressedToLocalIdentity(
                request,
                "signalasi:${"a".repeat(16)}"
            )
        )
        assertFalse(
            PhoneContactCard.isAddressedToLocalIdentity(
                request,
                "signalasi:${"b".repeat(16)}"
            )
        )
    }

    @Test
    fun `contact control signature input binds sender target bundle and time`() {
        val card = validCard()
        val now = 2_000_000L
        val request = JSONObject()
            .put("type", PhoneContactCard.REQUEST_TYPE)
            .put("version", PhoneContactCard.VERSION)
            .put("control_id", "control-1")
            .put("from", card.getString("signalasi_id"))
            .put("to", "signalasi:${"b".repeat(16)}")
            .put("reply_topic", card.getString("mqtt_inbox_topic"))
            .put("contact_card", card)
            .put("contact_card_signature", card.getString("signature"))
            .put("bundle_identity_fingerprint", card.getString("identity_fingerprint"))
            .put("time", now)
            .put("control_signature", "C".repeat(64))

        assertTrue(PhoneContactCard.isFreshControlPayload(request, now))
        assertFalse(
            PhoneContactCard.isFreshControlPayload(
                JSONObject(request.toString()).put("to", "unexpected"),
                now
            )
        )
        assertFalse(
            PhoneContactCard.canonicalControlBytes(request).contentEquals(
                PhoneContactCard.canonicalControlBytes(
                    JSONObject(request.toString()).put("to", "signalasi:${"c".repeat(16)}")
                )
            )
        )
    }

    @Test
    fun `stale contact control payload is rejected`() {
        val card = validCard()
        val request = JSONObject()
            .put("type", PhoneContactCard.REQUEST_TYPE)
            .put("version", PhoneContactCard.VERSION)
            .put("control_id", "control-1")
            .put("from", card.getString("signalasi_id"))
            .put("to", "signalasi:${"b".repeat(16)}")
            .put("reply_topic", card.getString("mqtt_inbox_topic"))
            .put("contact_card", card)
            .put("contact_card_signature", card.getString("signature"))
            .put("bundle_identity_fingerprint", card.getString("identity_fingerprint"))
            .put("time", 1L)
            .put("control_signature", "C".repeat(64))

        assertFalse(
            PhoneContactCard.isFreshControlPayload(
                request,
                PhoneContactCard.CONTROL_MAX_AGE_MILLIS + 2L
            )
        )
    }

    private fun validCard(): JSONObject {
        val fingerprint = "a".repeat(64)
        return JSONObject()
            .put("type", PhoneContactCard.TYPE)
            .put("version", PhoneContactCard.VERSION)
            .put("signalasi_id", "signalasi:${fingerprint.take(16)}")
            .put("name", "SignalASI")
            .put("identity_public_key", "A".repeat(48))
            .put("identity_fingerprint", fingerprint)
            .put("mqtt_inbox_topic", PhoneContactCard.inboxTopic(SignalASILinkProtocol.newRouteId()))
            .put("device_id", SignalASILinkProtocol.newRouteId())
            .put("created_at", 1L)
            .put("signature", "B".repeat(64))
    }
}
