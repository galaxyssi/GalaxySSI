package com.signalasi.chat

import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PeerSignalSessionRecoveryTest {
    @After
    fun tearDown() {
        PeerSignalSessionRecoveryGate.clearForTest()
    }

    @Test
    fun `recovery requests are rate limited per contact`() {
        assertTrue(PeerSignalSessionRecoveryGate.begin("phone:a", 1_000L))
        assertFalse(PeerSignalSessionRecoveryGate.begin("phone:a", 1_001L))
        assertTrue(PeerSignalSessionRecoveryGate.begin("phone:b", 1_001L))
        assertTrue(
            PeerSignalSessionRecoveryGate.begin(
                "phone:a",
                1_000L + PeerSignalSessionRecoveryGate.REQUEST_COOLDOWN_MILLIS
            )
        )
    }

    @Test
    fun `failed publish can retry session recovery immediately`() {
        assertTrue(PeerSignalSessionRecoveryGate.begin("phone:a", 1_000L))
        PeerSignalSessionRecoveryGate.requestFailed("phone:a")

        assertTrue(PeerSignalSessionRecoveryGate.begin("phone:a", 1_001L))
    }

    @Test
    fun `only explicit refresh controls replace a trusted peer session`() {
        assertFalse(PeerSignalBundlePolicy.replacesExistingSession(PhoneContactCard.REQUEST_TYPE))
        assertTrue(
            PeerSignalBundlePolicy.replacesExistingSession(PhoneContactCard.BUNDLE_REFRESH_TYPE)
        )
        assertTrue(
            PeerSignalBundlePolicy.replacesExistingSession(PhoneContactCard.BUNDLE_RESPONSE_TYPE)
        )
    }

    @Test
    fun `small direct peer message retains a recovery envelope`() {
        val payload = JSONObject().put("type", "peer_message").put("content", "hello")
        val envelope = JSONObject().put("message_id", "message-1").put("payload", payload)

        assertEquals(
            envelope.toString(),
            SignalASILinkDeliveryStore.recoverablePeerEnvelope(
                payload,
                envelope,
                isDirectPhoneContact = true
            )
        )
        assertEquals(
            "",
            SignalASILinkDeliveryStore.recoverablePeerEnvelope(
                payload,
                envelope,
                isDirectPhoneContact = false
            )
        )
    }

    @Test
    fun `non-message and oversized envelopes are not retained for recovery`() {
        val control = JSONObject().put("type", "delivery_ack")
        assertEquals(
            "",
            SignalASILinkDeliveryStore.recoverablePeerEnvelope(
                control,
                JSONObject().put("message_id", "ack-1"),
                isDirectPhoneContact = true
            )
        )

        val peer = JSONObject().put("type", "peer_message")
        val oversized = JSONObject().put("content", "x".repeat(70 * 1024))
        assertEquals(
            "",
            SignalASILinkDeliveryStore.recoverablePeerEnvelope(
                peer,
                oversized,
                isDirectPhoneContact = true
            )
        )
    }
}
